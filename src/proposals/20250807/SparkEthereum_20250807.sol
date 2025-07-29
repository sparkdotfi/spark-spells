// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { SparkPayloadEthereum, IEngine, EngineFlags, Rates } from "../../SparkPayloadEthereum.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPoolConfigurator } from 'sparklend-v1-core/contracts/interfaces/IPoolConfigurator.sol';

/**
 * @title  August 7, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard SparkLend pyUSD
 *         - Onboard Curve pyUSD/USDC Pool (TODO)
 *         SparkLend:
 *         - Onboard pyUSD (TODO)
 *         - Update Stablecoin Rate Models
 *         - Enable Flash Loans for USDS
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/august-7-2025-proposed-changes-to-spark-for-upcoming-spell/26896
 * Vote:   
 */
contract SparkEthereum_20250807 is SparkPayloadEthereum {

    address internal constant PYUSD               = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant PYUSD_PRICE_FEED    = 0x42a03F81dd8A1cEcD746dc262e4d1CD9fD39F777;
    address internal constant USDS_DAI_IRM        = 0xD99f41B22BBb4af36ae452Bf0Cc3aA07ce91bD66;
    address internal constant USDC_USDT_PYUSD_IRM = 0xD3d3BcD8cC1D3d0676Da13F7Fc095497329EC683;

    function newListings() public pure override returns (IEngine.Listing[] memory) {
        IEngine.Listing[] memory listings = new IEngine.Listing[](1);

        listings[0] = IEngine.Listing({
            asset:              PYUSD,
            assetSymbol:        'PYUSD',
            priceFeed:          PYUSD_PRICE_FEED,
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
            liqBonus:              10_00,
            reserveFactor:         10_00,
            supplyCap:             50_000_000,
            borrowCap:             25_000_000,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         2
        });

        return listings;
    }

    function _postExecute() internal override {
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDS, USDS_DAI_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.DAI,  USDS_DAI_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDC, USDC_USDT_PYUSD_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, USDC_USDT_PYUSD_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(PYUSD,         USDC_USDT_PYUSD_IRM);

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: PYUSD, max: 500_000_000, gap: 50_000_000, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: PYUSD, max: 475_000_000, gap: 25_000_000, increaseCooldown: 12 hours });

        // Seed the new pyUSD pool
        IERC20(PYUSD).approve(address(LISTING_ENGINE.POOL()), 1e6);
        LISTING_ENGINE.POOL().supply(PYUSD, 1e6, address(this), 0);

        IPoolConfigurator(Ethereum.POOL_CONFIGURATOR).setReserveFlashLoaning(Ethereum.USDS, true);
    }

}
