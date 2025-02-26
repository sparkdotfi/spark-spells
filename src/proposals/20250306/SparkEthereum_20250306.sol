// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IAaveV3ConfigEngine as IEngine } from '../../interfaces/IAaveV3ConfigEngine.sol';

import { SparkPayloadEthereum, Rates, EngineFlags } from "../../SparkPayloadEthereum.sol";

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

/**
 * @title  March 06, 2025 Spark Ethereum Proposal
 * @notice SparkLend: Onboard LBTC, tBTC
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/march-6-2025-proposed-changes-to-spark-for-upcoming-spell/26036
 * Vote:   TODO
 */
contract SparkEthereum_20250306 is SparkPayloadEthereum {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;

    constructor() {
        // PAYLOAD_BASE = 0x1e59bBDbd97DDa3E72a65061ecEFEF428F5EFB9a;
    }

    function newListings() public pure override returns (IEngine.Listing[] memory) {
        IEngine.Listing[] memory listings = new IEngine.Listing[](2);

        // TODO: Add cap automator
        listings[0] = IEngine.Listing({
            asset:       Ethereum.LBTC,
            assetSymbol: 'LBTC',
            priceFeed:   AGGOR_BTCUSD_ORACLE,
            rateStrategyParams:                Rates.RateStrategyParams({
                optimalUsageRatio:             45_00,
                baseVariableBorrowRate:        5_00,
                variableRateSlope1:            15_00,
                variableRateSlope2:            300_00,
                stableRateSlope1:              0,   // TODO: Revisit
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
            supplyCap:             0,
            borrowCap:             0,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });

        // TODO: Add cap automator
        listings[0] = IEngine.Listing({
            asset:       Ethereum.TBTC,
            assetSymbol: 'TBTC',
            priceFeed:   AGGOR_BTCUSD_ORACLE,
            rateStrategyParams:                Rates.RateStrategyParams({
                optimalUsageRatio:             60_00,
                baseVariableBorrowRate:        0,
                variableRateSlope1:            4_00,
                variableRateSlope2:            300_00,
                stableRateSlope1:              0,  // TODO: Revisit
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
            supplyCap:             0,
            borrowCap:             0,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });


        return listings;
    }

}
