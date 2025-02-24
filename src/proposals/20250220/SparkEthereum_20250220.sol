// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { SparkPayloadEthereum, Ethereum } from "../../SparkPayloadEthereum.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';

import { AllocatorBuffer } from 'dss-allocator/src/AllocatorBuffer.sol';
import { AllocatorVault }  from 'dss-allocator/src/AllocatorVault.sol';

import { CCTPForwarder }                           from 'xchain-helpers/forwarders/CCTPForwarder.sol';
import { ArbitrumForwarder, ICrossDomainArbitrum } from 'xchain-helpers/forwarders/ArbitrumForwarder.sol';

import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";
import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";

import { ICapAutomator } from "lib/sparklend-cap-automator/src/interfaces/ICapAutomator.sol";

interface IOptimismTokenBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

interface IArbitrumTokenBridge {
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (bytes memory res);
    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external pure returns (bytes memory outboundCalldata);
}

/**
 * @title  Feb 20, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer: Onboard Arbitrum One, Mint 100m USDS worth of sUSDS into Base,
                                  Whitelist sUSDS Deposit/Withdraw
 *         SparkLend: Increase weETH supply cap parameters
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/feb-20-2025-proposed-changes-to-spark-for-upcoming-spell/25951
 *         https://forum.sky.money/t/feb-20-2025-proposed-changes-to-spark-for-upcoming-spell-2/25961
 * Vote:   https://vote.makerdao.com/polling/QmcicBXG#poll-detail
 *         https://vote.makerdao.com/polling/QmWQcu5A#poll-detail
 *         https://vote.makerdao.com/polling/Qmdr4yqX#poll-detail
 *         https://vote.makerdao.com/polling/QmWbSTxi#poll-detail
 */
contract SparkEthereum_20250220 is SparkPayloadEthereum {

    uint256 internal constant USDS_MINT_AMOUNT             = 300_000_000e18;
    uint256 internal constant SUSDS_DEPOSIT_AMOUNT         = 200_000_000e18;
    uint256 internal constant SUSDS_BASE_BRIDGE_AMOUNT     = 100_000_000e18;
    uint256 internal constant USDS_ARBITRUM_BRIDGE_AMOUNT  = 100_000_000e18;

    constructor() {
        PAYLOAD_BASE     = 0x1e59bBDbd97DDa3E72a65061ecEFEF428F5EFB9a;
        PAYLOAD_ARBITRUM = 0x930e7EFC310F1E62ff3DfC7b60A8FF06d4046887;
    }

    function _postExecute() internal override {
        // --- Increase weETH supply cap parameters ---
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.WEETH,
            max:              500_000,
            gap:              10_000,
            increaseCooldown: 12 hours
        });

        // --- sUSDS Deposit/Withdraw Rate Limit ---
        _onboardERC4626Vault(
            Ethereum.SUSDS,
            type(uint256).max,
            0
        );

        // --- Set up Arbitrum One ---
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 25_000_000e6 / uint256(1 days)
            }),
            "usdcToCctpArbitrumOneLimit",
            6
        );
        MainnetController(Ethereum.ALM_CONTROLLER).setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            bytes32(uint256(uint160(Arbitrum.ALM_PROXY)))
        );

        // --- Send USDS and sUSDS to Base and Arbitrum ---

        // Mint USDS and sUSDS
        AllocatorVault(Ethereum.ALLOCATOR_VAULT).draw(USDS_MINT_AMOUNT);
        AllocatorBuffer(Ethereum.ALLOCATOR_BUFFER).approve(Ethereum.USDS, address(this), USDS_MINT_AMOUNT);
        IERC20(Ethereum.USDS).transferFrom(Ethereum.ALLOCATOR_BUFFER, address(this), USDS_MINT_AMOUNT);
        IERC20(Ethereum.USDS).approve(Ethereum.SUSDS, SUSDS_DEPOSIT_AMOUNT);
        uint256 susdsShares = IERC4626(Ethereum.SUSDS).deposit(SUSDS_DEPOSIT_AMOUNT, address(this));

        // Bridge to Base
        uint256 susdsSharesBase = IERC4626(Ethereum.SUSDS).convertToShares(SUSDS_BASE_BRIDGE_AMOUNT);
        IERC20(Ethereum.SUSDS).approve(Ethereum.BASE_TOKEN_BRIDGE, susdsSharesBase);
        IOptimismTokenBridge(Ethereum.BASE_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Base.SUSDS, Base.ALM_PROXY, susdsSharesBase, 1_000_000, "");

        // Bridge to Arbitrum
        uint256 susdsSharesArbitrum = susdsShares - susdsSharesBase;
        _sendArbTokens(Ethereum.USDS, USDS_ARBITRUM_BRIDGE_AMOUNT);
        _sendArbTokens(Ethereum.SUSDS, susdsSharesArbitrum);
    }

    function _sendArbTokens(address token, uint256 amount) internal {
        // Gas submission adapted from ArbitrumForwarder.sendMessageL1toL2
        bytes memory finalizeDepositCalldata = IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).getOutboundCalldata({
            l1Token: token,
            from:    address(this),
            to:      Arbitrum.ALM_PROXY,
            amount:  amount,
            data:    ""
        });
        uint256 gasLimit = 1_000_000;
        uint256 baseFee = block.basefee;
        uint256 maxFeePerGas = 50e9;
        uint256 maxSubmission = ICrossDomainArbitrum(ArbitrumForwarder.L1_CROSS_DOMAIN_ARBITRUM_ONE).calculateRetryableSubmissionFee(finalizeDepositCalldata.length, baseFee);
        uint256 maxRedemption = gasLimit * maxFeePerGas;

        IERC20(token).approve(Ethereum.ARBITRUM_TOKEN_BRIDGE, amount);
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).outboundTransfer{value:maxSubmission + maxRedemption}({
            l1Token:     token, 
            to:          Arbitrum.ALM_PROXY, 
            amount:      amount, 
            maxGas:      gasLimit, 
            gasPriceBid: maxFeePerGas,
            data:        abi.encode(maxSubmission, bytes(""))
        });
    }

}
