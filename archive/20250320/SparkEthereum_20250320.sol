// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { IAaveV3ConfigEngine as IEngine } from '../../interfaces/IAaveV3ConfigEngine.sol';

import { SparkPayloadEthereum, Rates, EngineFlags } from "../../SparkPayloadEthereum.sol";

/**
 * @title  March 20, 2025 Spark Ethereum Proposal
 * @notice SparkLend: Onboard LBTC, tBTC, ezETH, rsETH, create new BTC emode with LBTC and cbBTC
 *                    Update DAI/USDS IRMs to 50bps spread (No poll required)
 *         Morpho: Onboard May eUSDe PT, July USDe PT
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/march-6-2025-proposed-changes-to-spark-for-upcoming-spell/26036
 *         https://forum.sky.money/t/march-20-2025-proposed-changes-to-spark-for-upcoming-spell/26113
 *         https://forum.sky.money/t/mar-20-2025-stability-scope-parameter-changes-24/26129
 * Vote:   https://vote.makerdao.com/polling/QmfM4SBB
 *         https://vote.makerdao.com/polling/QmbDzZ3F
 *         https://vote.makerdao.com/polling/QmTj3BSu
 *         https://vote.makerdao.com/polling/QmPkA2GP
 *         https://vote.makerdao.com/polling/QmXvuNAv
 *         https://vote.makerdao.com/polling/QmXrHgdj
 */
contract SparkEthereum_20250320 is SparkPayloadEthereum {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;

    address internal constant EZETH_ORACLE = 0x52E85eB49e07dF74c8A9466D2164b4C4cA60014A;
    address internal constant RSETH_ORACLE = 0x70942D6b580741CF50A7906f4100063EE037b8eb;

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_USDE_31JUL2025             = 0x917459337CaAC939D41d7493B3999f571D20D667;
    address internal constant PT_USDE_31JUL2025_PRICE_FEED  = 0xFCaE69BEF9B6c96D89D58664d8aeA84BddCe2E5c;

    address internal constant DAI_IRM  = 0x5a7E7a32331189a794ac33Fec76C0A1dD3dDCF9c;
    address internal constant USDS_IRM = 0xD94BA511284d2c56F59a687C3338441d33304E07;

    constructor() {
        PAYLOAD_BASE     = 0x356f19Cb575CF40c7ff33A5117F9a9264C23f6e8;
        PAYLOAD_ARBITRUM = 0x1d54A093b8FDdFcc6fBB411d9Af31D96e034B3D5;
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
        IEngine.Listing[] memory listings = new IEngine.Listing[](4);

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

        listings[2] = IEngine.Listing({
            asset:       Ethereum.EZETH,
            assetSymbol: 'ezETH',
            priceFeed:   EZETH_ORACLE,
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
            ltv:                   72_00,
            liqThreshold:          73_00,
            liqBonus:              10_00,
            reserveFactor:         15_00,
            supplyCap:             2_000,
            borrowCap:             0,
            debtCeiling:           0,
            liqProtocolFee:        10_00,
            eModeCategory:         0
        });

        listings[3] = IEngine.Listing({
            asset:       Ethereum.RSETH,
            assetSymbol: 'rsETH',
            priceFeed:   RSETH_ORACLE,
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
            ltv:                   72_00,
            liqThreshold:          73_00,
            liqBonus:              10_00,
            reserveFactor:         15_00,
            supplyCap:             2_000,
            borrowCap:             0,
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

        // Seed the new ezETH pool
        IERC20(Ethereum.EZETH).approve(address(LISTING_ENGINE.POOL()), 0.0001e18);
        LISTING_ENGINE.POOL().supply(Ethereum.EZETH, 0.0001e18, address(this), 0);

        // Seed the new rsETH pool
        IERC20(Ethereum.RSETH).approve(address(LISTING_ENGINE.POOL()), 0.0001e18);
        LISTING_ENGINE.POOL().supply(Ethereum.RSETH, 0.0001e18, address(this), 0);

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.LBTC, max: 2500, gap: 250, increaseCooldown: 12 hours });

        capAutomator.setSupplyCapConfig({ asset: Ethereum.TBTC, max: 500, gap: 125, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: Ethereum.TBTC, max: 250, gap: 25,  increaseCooldown: 12 hours });

        capAutomator.setSupplyCapConfig({ asset: Ethereum.EZETH, max: 20_000, gap: 2_000, increaseCooldown: 12 hours });

        capAutomator.setSupplyCapConfig({ asset: Ethereum.RSETH, max: 20_000, gap: 2_000, increaseCooldown: 12 hours });

        // Onboard PT-eUSDE-29MAY2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_29MAY2025,
                oracle:          PT_EUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            300_000_000e18
        );

        // Onboard PT-USDe-31JUL2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_31JUL2025,
                oracle:          PT_USDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            200_000_000e18
        );

        // Update DAI/USDS IRMs to 50bps spread
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(
            Ethereum.DAI,
            DAI_IRM
        );
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(
            Ethereum.USDS,
            USDS_IRM
        );
    }

}
