// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { IV3RateStrategyFactory as Rates } from "src/interfaces/IV3RateStrategyFactory.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { EngineFlags } from "../../AaveV3PayloadBase.sol";

import { SparkPayloadEthereum, IEngine } from "../../SparkPayloadEthereum.sol";

/**
 * @title  August 27, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Onboard USDG.
 *         - Onboard RLUSD.
 *         Spark Liquidity Layer:
 *         - Onboard SparkLend USDG.
 *         - Onboard SparkLend RLUSD.
 *         Spark Treasury:
 *         - Grants for Spark Foundation and Spark Assets Foundation.
 * Forum:  https://forum.skyeco.com/t/august-27-2026-proposed-changes-to-spark-for-upcoming-spell/28181
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xf8a0b03d3638192899495e8d85a272d78f7c61324e3f1c1f320add23ab91bda3
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x01a287ddec297d1ffe1e5c8391431fe1ee1c415e3f7e8b93d437ee9a66f29820
 */
contract SparkEthereum_20260827 is SparkPayloadEthereum {

    address internal constant RLUSD                = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address internal constant FIXED_USD_PRICE_FEED = 0x42a03F81dd8A1cEcD746dc262e4d1CD9fD39F777;
    address internal constant USDG_RLUSD_IRM       = 0x5fCFEc770eDF3971C4f700a599364c244217dc9A;

    // Predicted spToken proxy addresses, CREATE(POOL_CONFIGURATOR, nonce 55 and 58). Valid
    // only while no other reserve is listed before this spell executes.
    address internal constant USDG_SPTOKEN  = 0x6f335538257ef440F3c51e925a5C820f722a1F9F;
    address internal constant RLUSD_SPTOKEN = 0x59275Fb72c8004F44BA44432e25082932Fd677f1;

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;

    function newListings() public pure override returns (IEngine.Listing[] memory) {
        IEngine.Listing[] memory listings = new IEngine.Listing[](2);

        // 1. Onboard USDG to SparkLend.
        listings[0] = IEngine.Listing({
            asset:              Ethereum.USDG,
            assetSymbol:        'USDG',
            priceFeed:          FIXED_USD_PRICE_FEED,
            rateStrategyParams: Rates.RateStrategyParams({
                optimalUsageRatio:             _bpsToRay(0),
                baseVariableBorrowRate:        0,
                variableRateSlope1:            _bpsToRay(0),
                variableRateSlope2:            _bpsToRay(0),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseStableRateOffset:          0,
                stableRateExcessOffset:        0,
                optimalStableToTotalDebtRatio: 0
            }),
            enabledToBorrow:       EngineFlags.ENABLED,
            stableRateModeEnabled: EngineFlags.DISABLED,
            borrowableInIsolation: EngineFlags.DISABLED,
            withSiloedBorrowing:   EngineFlags.DISABLED,
            flashloanable:         EngineFlags.ENABLED,
            ltv:                   0,
            liqThreshold:          0,
            liqBonus:              0,
            reserveFactor:         10_00,
            supplyCap:             ReserveConfiguration.MAX_VALID_SUPPLY_CAP,
            borrowCap:             ReserveConfiguration.MAX_VALID_BORROW_CAP,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });

        // 2. Onboard RLUSD to SparkLend.
        listings[1] = IEngine.Listing({
            asset:              RLUSD,
            assetSymbol:        'RLUSD',
            priceFeed:          FIXED_USD_PRICE_FEED,
            rateStrategyParams: Rates.RateStrategyParams({
                optimalUsageRatio:             _bpsToRay(0),
                baseVariableBorrowRate:        0,
                variableRateSlope1:            _bpsToRay(0),
                variableRateSlope2:            _bpsToRay(0),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseStableRateOffset:          0,
                stableRateExcessOffset:        0,
                optimalStableToTotalDebtRatio: 0
            }),
            enabledToBorrow:       EngineFlags.ENABLED,
            stableRateModeEnabled: EngineFlags.DISABLED,
            borrowableInIsolation: EngineFlags.DISABLED,
            withSiloedBorrowing:   EngineFlags.DISABLED,
            flashloanable:         EngineFlags.ENABLED,
            ltv:                   0,
            liqThreshold:          0,
            liqBonus:              0,
            reserveFactor:         10_00,
            supplyCap:             ReserveConfiguration.MAX_VALID_SUPPLY_CAP,
            borrowCap:             ReserveConfiguration.MAX_VALID_BORROW_CAP,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });

        return listings;
    }

    function _postExecute() internal override {
        // 1. Onboard USDG to SparkLend.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDG, USDG_RLUSD_IRM);

        // The config engine skips the liquidation protocol fee for non-collateral listings
        // (liqThreshold == 0), so it is set directly.
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Ethereum.USDG, 10_00);

        // Seed the new USDG pool
        IERC20(Ethereum.USDG).approve(address(LISTING_ENGINE.POOL()), 1e6);
        LISTING_ENGINE.POOL().supply(Ethereum.USDG, 1e6, address(this), 0);

        // 2. Onboard RLUSD to SparkLend.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(RLUSD, USDG_RLUSD_IRM);

        // The config engine skips the liquidation protocol fee for non-collateral listings
        // (liqThreshold == 0), so it is set directly.
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(RLUSD, 10_00);

        // Seed the new RLUSD pool
        IERC20(RLUSD).approve(address(LISTING_ENGINE.POOL()), 1e18);
        LISTING_ENGINE.POOL().supply(RLUSD, 1e18, address(this), 0);

        // 3. Onboard SparkLend USDG to the Spark Liquidity Layer.
        _configureAaveToken({
            token        : USDG_SPTOKEN,
            depositMax   : 100_000_000e6,
            depositSlope : 100_000_000e6 / uint256(1 days)
        });

        MainnetController(Ethereum.ALM_CONTROLLER).setMaxSlippage(USDG_SPTOKEN, 0.99999e18);

        // 4. Onboard SparkLend RLUSD to the Spark Liquidity Layer.
        _configureAaveToken({
            token        : RLUSD_SPTOKEN,
            depositMax   : 100_000_000e18,
            depositSlope : 100_000_000e18 / uint256(1 days)
        });

        MainnetController(Ethereum.ALM_CONTROLLER).setMaxSlippage(RLUSD_SPTOKEN, 0.99999e18);

        // 5. Grants for Spark Foundation and Spark Assets Foundation.
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       SPARK_FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
