// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { AllocatorBuffer } from 'dss-allocator/src/AllocatorBuffer.sol';
import { AllocatorVault }  from 'dss-allocator/src/AllocatorVault.sol';

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { ArbitrumForwarder, ICrossDomainArbitrum } from 'xchain-helpers/forwarders/ArbitrumForwarder.sol';

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { IMorphoVaultLike, ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

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
 * @title  January 15, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend - Add LBTC to Oracle Kill Switch
           Spark USDS Morpho Vault - Update Vault Roles
           Spark Blue Chip USDC Morpho Vault - Update Vault Roles
           Spark Savings:
           - Increase spUSDC Deposit Cap
           - Increase spETH Deposit Cap
           Spark Liquidity Layer:
           - Mint sUSDS to Arbitrum PSM3
           - Mint sUSDS to OP Mainnet PSM3
           - Onboard Curve weETH/WETH-ng for Swaps
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-15-2026-proposed-changes-to-spark-for-upcoming-spell/27585
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xdd79e0fc0308fd0e4393b88cccb8e9b23237c9c398e0458c8c5c43198669e4bb
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x994d54ecdadc8f4a69de921207afe3731f3066f086e63ff6a1fd0d4bbfb51b53
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x7eb3a86a4da21475e760e2b2ed0d82fd72bbd4d33c99a0fbedf3d978e472f362
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x85f242a3d35252380a21ae3e5c80b023122e74af95698a301b541c7b610ffee8
 */
contract SparkEthereum_20260115 is SparkPayloadEthereum {

    address internal constant CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

    uint256 internal constant ARBITRUM_USDS_AMOUNT = 250_000_000e18;
    uint256 internal constant OPTIMISM_USDS_AMOUNT = 100_000_000e18;

    address internal constant CURVE_WEETHWETHNG = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;

    IMorphoVaultLike internal constant morphoUsds = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS);
    IMorphoVaultLike internal constant morphoUsdc = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC);

    IERC20 internal constant usdc = IERC20(Ethereum.USDC);
    IERC20 internal constant usds = IERC20(Ethereum.USDS);

    IERC4626 internal constant susds = IERC4626(Ethereum.SUSDS);

    ISparkVaultV2Like internal constant spEth  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);
    ISparkVaultV2Like internal constant spUsdc = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);

    constructor() {
        // AVALANCHE = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;
        // BASE      = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;
    }

    function _postExecute() internal override {
        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // SparkLend - Add LBTC to Oracle Kill Switch
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(LBTC_BTC_ORACLE, 0.95e8);

        // Spark USDS Morpho Vault - Update Vault Roles
        morphoUsds.setCurator(CURATOR_MULTISIG);
        morphoUsds.submitGuardian(GUARDIAN_MULTISIG);
        morphoUsds.submitTimelock(10 days);

        // Spark Blue Chip USDC Morpho Vault - Update Vault Roles
        morphoUsdc.setCurator(CURATOR_MULTISIG);
        morphoUsdc.submitGuardian(GUARDIAN_MULTISIG);
        morphoUsdc.submitTimelock(10 days);

        // Increase Vault Deposit Caps
        spUsdc.setDepositCap(1_000_000_000e6);
        spEth.setDepositCap(250_000e18);

        // Mint USDS and sUSDS
        uint256 totalAmount = ARBITRUM_USDS_AMOUNT + OPTIMISM_USDS_AMOUNT;
        AllocatorVault(Ethereum.ALLOCATOR_VAULT).draw(totalAmount);
        AllocatorBuffer(Ethereum.ALLOCATOR_BUFFER).approve(Ethereum.USDS, address(this), totalAmount);
        usds.transferFrom(Ethereum.ALLOCATOR_BUFFER, address(this), totalAmount);
        usds.approve(Ethereum.SUSDS, totalAmount);
        uint256 susdsShares = susds.deposit(totalAmount, address(this));

        // Bridge to Arbitrum
        uint256 susdsSharesArbitrum = susds.convertToShares(ARBITRUM_USDS_AMOUNT);
        susds.approve(Ethereum.ARBITRUM_TOKEN_BRIDGE, susdsSharesArbitrum);
        _sendArbTokens(Ethereum.SUSDS, susdsSharesArbitrum);

        // Bridge to Optimism
        uint256 susdsSharesOptimism = susds.convertToShares(OPTIMISM_USDS_AMOUNT);
        susds.approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, susdsSharesOptimism);
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Optimism.SUSDS, Optimism.ALM_PROXY, susdsSharesOptimism, 1_000_000, "");

        // Onboard Curve weETH/WETH-ng for Swaps
        _configureCurvePool({
            controller:    Ethereum.ALM_CONTROLLER,
            pool:          CURVE_WEETHWETHNG,
            maxSlippage:   0.9975e18,
            swapMax:       100e18,
            swapSlope:     1_000e18 / uint256(1 days),
            depositMax:    0,
            depositSlope:  0,
            withdrawMax:   0,
            withdrawSlope: 0
        });
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
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).outboundTransfer{value: maxSubmission + maxRedemption}({
            l1Token:     token, 
            to:          Arbitrum.ALM_PROXY, 
            amount:      amount, 
            maxGas:      gasLimit, 
            gasPriceBid: maxFeePerGas,
            data:        abi.encode(maxSubmission, bytes(""))
        });
    }

}
