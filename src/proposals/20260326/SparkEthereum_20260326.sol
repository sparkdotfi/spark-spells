// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

/**
 * @title  March 26, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Reactivate WBTC.
 *         Spark Liquidity Layer:
 *         - Add USAT transferAsset Rate Limit to Anchorage.
 *         - Add USDT transferAsset Rate Limit to Anchorage.
 *         Spark Treasury:
 *         - Spark Foundation and Spark Assets Foundation Grants for Q2 2026.
 *         - Transfer Excess USDS from SubDAO Proxy for SPK Buybacks.
 * Forum:  https://forum.skyeco.com/t/march-26-2026-proposed-changes-to-spark-for-upcoming-spell/27770
 * Vote:   
 */
contract SparkEthereum_20260326 is SparkPayloadEthereum {

    address internal constant ANCHORAGE_USAT_USDT                    = 0x49506C3Aa028693458d6eE816b2EC28522946872;
    address internal constant USAT                                   = 0x07041776f5007ACa2A54844F50503a18A72A8b68;
    address internal constant SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT = 0xEabCb8C0346Ac072437362f1692706BA5768A911;

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT       = 414_215e18;

    function collateralsUpdates()
        public view override returns (IEngine.CollateralUpdate[] memory)
    {
        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset          : Ethereum.WBTC,
            ltv            : 77_00,
            liqThreshold   : 78_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        // 1. Spark Foundation and Spark Assets Foundation Grants for Q2 2026
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,     FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT, ASSET_FOUNDATION_GRANT_AMOUNT);

        // 2. Reactivate WBTC.
        ICapAutomator(SparkLend.CAP_AUTOMATOR).setSupplyCapConfig({
            asset            : Ethereum.WBTC,
            max              : 3_000,
            gap              : 500,
            increaseCooldown : 12 hours
        });

        // 3. Add USAT transferAsset Rate Limit to Anchorage.
        // 4. Add USDT transferAsset Rate Limit to Anchorage.
        bytes32 transferKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER();

        bytes32 USAT_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, USAT,          ANCHORAGE_USAT_USDT);
        bytes32 USDT_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT, ANCHORAGE_USAT_USDT);

        SLLHelpers.setRateLimitData({
            key        : USAT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 250_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : USDT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 250_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // 7. Transfer Excess USDS from SubDAO Proxy for SPK Buybacks
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
