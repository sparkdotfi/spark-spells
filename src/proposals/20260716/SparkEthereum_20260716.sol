// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { ISyrupLike } from "src/interfaces/Interfaces.sol";

/**
 * @title  July 16, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Deactivate Old USDT Morpho V2 Vault.
 *         - Enable USDT Bridging to X Layer.
 *         - Enable USDG Bridging to Robinhood Chain.
 *         - Transfer USDS to Grove.
 *         Spark Treasury:
 *         - USDS Transfer to Spark Foundation for Incentives.
 *         - USDS Transfer to Spark Assets Foundation for Anchorage Fees.
 *         - Grants for Spark Foundation and Spark Assets Foundation (Exec).
 *         - Transfer USDS for Buybacks (Exec).
 * Forum:  https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-spark-for-upcoming-spell/28029
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xd177bc28b65afb23dc39a5e7cfdded7084b3b722b230e08d7067b68fa0f4486a
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0xdde478db4ba5882a5d48d19fdbae057fd703688e4f1e16fb673407fc08476a9f
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0xf99372ccca4b99dd04dc0ddb038e949b62f4d25810b0203572dc90bce025e805
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x2df281a276e0c17eff9a05e65bfc05937c2f600edec1a82386a6efb6dbe9d63d
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x3cb4165f1357d553445b0de790e4e8b4a71358f42f39d35f7de51b308ade558c
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x451bb53f80ad2906ff06cc3d03c88a6b09f350db371c4782e0621e26a1d55a43
 */
contract SparkEthereum_20260716 is SparkPayloadEthereum {

    address internal constant GROVE_ALM_PROXY          = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant OLD_MORPHO_VAULT_V2_USDT = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;
    address internal constant USDT_OFT                 = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;

    uint256 internal constant ANCHORAGE_FEES_AMOUNT         = 500_000e18;
    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant GROVE_SYRUP_USDC_AMOUNT       = 85_943_747.637271e6;
    uint256 internal constant INCENTIVES_AMOUNT             = 2_000_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 64_231e18;

    uint32 internal constant LZ_ENDPOINT_XLAYER = 30274;

    constructor() {
        PAYLOAD_ROBINHOOD = 0xE7933ffE5D03f0c0100456cE2E41d911db70Afa4;
        PAYLOAD_XLAYER    = 0x03801438834a9127088b4F2Cba02F42F8a600036;
    }

    function _postExecute() internal override {
        MainnetController almController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        // Enable USDG Bridging to Robinhood Chain.

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                almController.LIMIT_ASSET_TRANSFER(),
                Ethereum.USDG,
                Ethereum.PAXOS_USDG_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            50_000_000e6,
            250_000_000e6 / uint256(1 days),
            6
        );

        // Enable USDT Bridging to X Layer.

        almController.setLayerZeroRecipient(
            LZ_ENDPOINT_XLAYER,
            bytes32(uint256(uint160(XLayer.ALM_PROXY)))
        );

        rateLimits.setRateLimitData(
            keccak256(abi.encode(almController.LIMIT_LAYERZERO_TRANSFER(), USDT_OFT, LZ_ENDPOINT_XLAYER)),
            5_000_000e6,
            uint256(100_000_000e6) / 1 days
        );

        // Deactivate Old USDT Morpho V2 Vault.

        bytes32 MORPHO_VAULT_V2_USDT_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_DEPOSIT(),  OLD_MORPHO_VAULT_V2_USDT);
        bytes32 MORPHO_VAULT_V2_USDT_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_WITHDRAW(), OLD_MORPHO_VAULT_V2_USDT);

        rateLimits.setRateLimitData(MORPHO_VAULT_V2_USDT_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(MORPHO_VAULT_V2_USDT_WITHDRAW_KEY, 0, 0);

        // USDS Transfer to Spark Assets Foundation for Anchorage Fees.
        // USDS Transfer to Spark Foundation for Incentives.
        // Grants for Spark Foundation and Spark Assets Foundation (Exec).

        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       FOUNDATION_GRANT_AMOUNT + INCENTIVES_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, ASSET_FOUNDATION_GRANT_AMOUNT + ANCHORAGE_FEES_AMOUNT);

        // Transfer USDS for Buybacks (Exec).

        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);

        // Transfer USDS to Grove.

        uint256 usdsAmount = ISyrupLike(Ethereum.SYRUP_USDC).convertToAssets(GROVE_SYRUP_USDC_AMOUNT) * 1e12;

        almController.grantRole(almController.RELAYER(), address(this));

        almController.mintUSDS(usdsAmount);

        almController.revokeRole(almController.RELAYER(), address(this));

        IALMProxy almProxy = IALMProxy(Ethereum.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        almProxy.doCall(Ethereum.USDS, abi.encodeCall(IERC20.transfer, (GROVE_ALM_PROXY, usdsAmount)));

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
