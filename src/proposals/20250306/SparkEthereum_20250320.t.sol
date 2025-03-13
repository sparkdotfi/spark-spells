// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { DataTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { ReserveConfig } from "src/test-harness/ProtocolV3TestBase.sol";

import 'src/test-harness/SparkTestBase.sol';

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

contract SparkEthereum_20250320Test is SparkTestBase {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;
    address internal constant CBBTC_USDC_ORACLE   = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;

    address internal constant EZETH_ORACLE = 0x52E85eB49e07dF74c8A9466D2164b4C4cA60014A;
    address internal constant RSETH_ORACLE = 0x70942D6b580741CF50A7906f4100063EE037b8eb;

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_USDE_31JUL2025             = 0x917459337CaAC939D41d7493B3999f571D20D667;
    address internal constant PT_USDE_31JUL2025_PRICE_FEED  = 0xFCaE69BEF9B6c96D89D58664d8aeA84BddCe2E5c;

    constructor() {
        id = '20250320';
    }

    function setUp() public {
        // March 12, 2025
        setupDomains({
            mainnetForkBlock:     22031539,
            baseForkBlock:        27499543,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 314934161
        });
        
        deployPayloads();
    }

    function test_ETHEREUM_sparkLend_emodeUpdate() public {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        DataTypes.EModeCategory memory eModeBefore = pool.getEModeCategoryData(3);

        assertEq(eModeBefore.ltv,                  0);
        assertEq(eModeBefore.liquidationThreshold, 0);
        assertEq(eModeBefore.liquidationBonus,     0);
        assertEq(eModeBefore.priceSource,          address(0));
        assertEq(eModeBefore.label,                '');

        executeAllPayloadsAndBridges();

        DataTypes.EModeCategory memory eModeAfter = pool.getEModeCategoryData(3);

        assertEq(eModeAfter.ltv,                  85_00);
        assertEq(eModeAfter.liquidationThreshold, 90_00);
        assertEq(eModeAfter.liquidationBonus,     102_00);
        assertEq(eModeAfter.priceSource,          address(0));
        assertEq(eModeAfter.label,                'BTC');
    }

    function test_ETHEREUM_sparkLend_collateralOnboarding() public {
        SparkLendAssetOnboardingParams memory lbtcParams = SparkLendAssetOnboardingParams({
            // General
            symbol:            'LBTC',
            tokenAddress:      Ethereum.LBTC,
            oracleAddress:     AGGOR_BTCUSD_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  65_00,
            liquidationThreshold: 70_00,
            liquidationBonus:     108_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    250,
            supplyCapMax: 2500,
            supplyCapGap: 250,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            3
        });

        SparkLendAssetOnboardingParams memory tbtcParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'tBTC',
            tokenAddress:      Ethereum.TBTC,
            oracleAddress:     AGGOR_BTCUSD_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.60e27,
            baseVariableBorrowRate: 0,
            variableRateSlope1:     0.04e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          true,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       true,
            // Reserve configuration
            ltv:                  65_00,
            liquidationThreshold: 70_00,
            liquidationBonus:     108_00,
            reserveFactor:        20_00,
            // Supply caps
            supplyCap:    125,
            supplyCapMax: 500,
            supplyCapGap: 125,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    25,
            borrowCapMax: 250,
            borrowCapGap: 25,
            borrowCapTtl: 12 hours,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams memory ezethParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'ezETH',
            tokenAddress:      Ethereum.EZETH,
            oracleAddress:     EZETH_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  72_00,
            liquidationThreshold: 73_00,
            liquidationBonus:     110_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    2_000,
            supplyCapMax: 20_000,
            supplyCapGap: 2_000,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams memory rsethParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'rsETH',
            tokenAddress:      Ethereum.RSETH,
            oracleAddress:     RSETH_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  72_00,
            liquidationThreshold: 73_00,
            liquidationBonus:     110_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    2_000,
            supplyCapMax: 20_000,
            supplyCapGap: 2_000,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams[] memory newAssets = new SparkLendAssetOnboardingParams[](4);
        newAssets[0] = lbtcParams;
        newAssets[1] = tbtcParams;
        newAssets[2] = ezethParams;
        newAssets[3] = rsethParams;

        _testAssetOnboardings(newAssets);
    }

    function test_ETHEREUM_sparkLend_cbBtcEmode() public {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);
        ReserveConfig   memory cbBtcConfig      = _findReserveConfigBySymbol(allConfigsBefore, 'cbBTC');

        assertEq(cbBtcConfig.eModeCategory, 0);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);
        cbBtcConfig.eModeCategory = 3;

        _validateReserveConfig(cbBtcConfig, allConfigsAfter);
    }

    function test_ETHEREUM_morpho_PTEUSDE29MAY2025Onboarding() public {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_29MAY2025,
                oracle:          PT_EUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     300_000_000e18
        });
    }

    function test_ETHEREUM_morpho_PTUSDE31JUL2025Onboarding() public {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_31JUL2025,
                oracle:          PT_USDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     200_000_000e18
        });
    }

    function test_BASE_morphoConfiguration() public onChain(ChainIdUtils.Base()) {
        IMetaMorpho susdc = IMetaMorpho(Base.MORPHO_VAULT_SUSDC);

        MarketParams memory usdcCBBTC = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: Base.CBBTC,
            oracle:          CBBTC_USDC_ORACLE,
            irm:             Base.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });

        _assertMorphoCap(address(susdc), usdcCBBTC, 100_000_000e6);

        executeAllPayloadsAndBridges();

        _assertMorphoCap(address(susdc), usdcCBBTC, 100_000_000e6, 500_000_000e6);

        skip(1 days);

        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).acceptCap(usdcCBBTC);

        _assertMorphoCap(address(susdc), usdcCBBTC, 500_000_000e6);
    }

}
