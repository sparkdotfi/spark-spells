// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IACLManager } from 'aave-v3-core/contracts/interfaces/IACLManager.sol';

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

/**
 * @title  March 26, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Add USAT transferAsset Rate Limit to Anchorage.
 *         - Add USDT transferAsset Rate Limit to Anchorage.
 *         - Onboard Uniswap v4 USAT/USDS Pool.
 *         Spark Treasury:
 *         - Spark Foundation and Spark Assets Foundation Grants for Q2 2026.
 *         - Transfer Excess USDS from SubDAO Proxy for SPK Buybacks.
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20260326 is SparkPayloadEthereum {

    address internal constant ANCHORAGE_USAT_USDT                    = 0x49506C3Aa028693458d6eE816b2EC28522946872;
    address internal constant USAT                                   = 0x07041776f5007ACa2A54844F50503a18A72A8b68;
    address internal constant SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT = 0xEabCb8C0346Ac072437362f1692706BA5768A911;

    bytes32 internal constant USAT_USDS_POOL_ID = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;  // TODO change

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT       = 414_215e18;

    function collateralsUpdates()
        public view override returns (IEngine.CollateralUpdate[] memory)
    {
        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset:          Ethereum.WBTC,
            ltv:            77_00,
            liqThreshold:   78_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        // 1. Spark Foundation and Spark Assets Foundation Grants for Q2 2026
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,     FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT, ASSET_FOUNDATION_GRANT_AMOUNT);

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

        // 5. Onboard Uniswap v4 USAT/USDS Pool.
        SLLHelpers.configureUniswapV4Pool({
            controller     : Ethereum.ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : USAT_USDS_POOL_ID,
            maxSlippage    : 0.999e18,
            tickLower      : 276_314,
            tickUpper      : 276_334,
            maxTickSpacing : 10,
            depositMax     : 10_000_000e18,
            depositSlope   : 100_000_000e18 / uint256(1 days),
            withdrawMax    : 50_000_000e18,
            withdrawSlope  : 300_000_000e18 / uint256(1 days),
            swapMax        : 5_000_000e18,
            swapSlope      : 50_000_000e18 / uint256(1 days)
        });

        // 7. Transfer Excess USDS from SubDAO Proxy for SPK Buybacks
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
