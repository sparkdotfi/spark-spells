// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IAaveV3ConfigEngine as IEngine } from '../../interfaces/IAaveV3ConfigEngine.sol';

import { SparkPayloadEthereum, Rates, EngineFlags } from "../../SparkPayloadEthereum.sol";

/**
 * @title  March 06, 2025 Spark Ethereum Proposal
 * @notice SparkLend: Onboard LBTC, tBTC, create new BTC emode with LBTC and cbBTC
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/march-6-2025-proposed-changes-to-spark-for-upcoming-spell/26036
 * Vote:   https://vote.makerdao.com/polling/QmfM4SBB
 *         https://vote.makerdao.com/polling/QmbDzZ3F
 */
contract SparkEthereum_20250306 is SparkPayloadEthereum {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;

    constructor() {
        PAYLOAD_BASE = 0xAFaFC068B62195B60B53d05803A6a91687B61e44;
    }

    function _preExecute() internal override {
        LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory({
            categoryId:           3,
            ltv:                  85_00,
            liquidationThreshold: 90_00,
            liquidationBonus:     102_00,
            oracle:               address(0),  // No oracle override
            label:                'BTC'
        });
    }

    function newListings() public pure override returns (IEngine.Listing[] memory) {
        IEngine.Listing[] memory listings = new IEngine.Listing[](2);

        listings[0] = IEngine.Listing({
            asset:       Ethereum.LBTC,
            assetSymbol: 'LBTC',
            priceFeed:   AGGOR_BTCUSD_ORACLE,
            rateStrategyParams:                Rates.RateStrategyParams({
                optimalUsageRatio:             _bpsToRay(45_00),
                baseVariableBorrowRate:        _bpsToRay(5_00),
                variableRateSlope1:            _bpsToRay(15_00),
                variableRateSlope2:            _bpsToRay(300_00),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseStableRateOffset:          0,
                stableRateExcessOffset:        0,
                optimalStableToTotalDebtRatio: 0
            }),
            enabledToBorrow:       EngineFlags.DISABLED,
            stableRateModeEnabled: EngineFlags.DISABLED,
            borrowableInIsolation: EngineFlags.DISABLED,
            withSiloedBorrowing:   EngineFlags.DISABLED,
            flashloanable:         EngineFlags.DISABLED,
            ltv:                   65_00,
            liqThreshold:          70_00,
            liqBonus:              8_00,
            reserveFactor:         15_00,
            supplyCap:             250,
            borrowCap:             0,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         3
        });

        listings[1] = IEngine.Listing({
            asset:       Ethereum.TBTC,
            assetSymbol: 'tBTC',
            priceFeed:   AGGOR_BTCUSD_ORACLE,
            rateStrategyParams:                Rates.RateStrategyParams({
                optimalUsageRatio:             _bpsToRay(60_00),
                baseVariableBorrowRate:        0,
                variableRateSlope1:            _bpsToRay(4_00),
                variableRateSlope2:            _bpsToRay(300_00),
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
            ltv:                   65_00,
            liqThreshold:          70_00,
            liqBonus:              8_00,
            reserveFactor:         20_00,
            supplyCap:             125,
            borrowCap:             25,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });

        return listings;
    }

    function collateralsUpdates()
        public pure override returns (IEngine.CollateralUpdate[] memory collateralUpdates)
    {
        collateralUpdates = new IEngine.CollateralUpdate[](1);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset:          Ethereum.CBBTC,
            ltv:            EngineFlags.KEEP_CURRENT,
            liqThreshold:   EngineFlags.KEEP_CURRENT,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  3
        });
    }

    function _postExecute() internal override {
        // Seed the new LBTC pool
        IERC20(Ethereum.LBTC).approve(address(LISTING_ENGINE.POOL()), 0.0001e8);
        LISTING_ENGINE.POOL().supply(Ethereum.LBTC, 0.0001e8, address(this), 0);

        // Seed the new tBTC pool
        IERC20(Ethereum.TBTC).approve(address(LISTING_ENGINE.POOL()), 0.0001e18);
        LISTING_ENGINE.POOL().supply(Ethereum.TBTC, 0.0001e18, address(this), 0);

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.LBTC, max: 2500, gap: 250, increaseCooldown: 12 hours });

        capAutomator.setSupplyCapConfig({ asset: Ethereum.TBTC, max: 500, gap: 125, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: Ethereum.TBTC, max: 250, gap: 25,  increaseCooldown: 12 hours });
    }

}
