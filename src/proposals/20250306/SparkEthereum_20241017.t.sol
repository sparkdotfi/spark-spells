// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import 'src/test-harness/SparkTestBase.sol';

import { InterestStrategyValues, ReserveConfig } from 'src/test-harness/ProtocolV3TestBase.sol';

contract SparkEthereum_20250306Test is SparkEthereumTests {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;

    constructor() {
        id = '20250306';
    }

    function setUp() public {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 21930000);  // Feb 26, 2024

        // Feb 26, 2025
        setupDomains({
            mainnetForkBlock:     21930000,
            baseForkBlock:        26348524,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 307093406  // Not used
        });

        deployPayloads();
    }

    function test_ETHEREUM_sparkLend_collateralOnboardingLbtcAndTbtc() public {

        address poolAddressesProvider = _getPoolAddressesProviderRegistry().getAddressesProvidersList()[0];

        loadPoolContext(poolAddressesProvider);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);

        assertEq(allConfigsBefore.length, 13);

        // _assertSupplyCapConfig({
        //     asset:            SUSDS,
        //     max:              0,
        //     gap:              0,
        //     increaseCooldown: 0
        // });

        // _assertBorrowCapConfig({
        //     asset:            SUSDS,
        //     max:              0,
        //     gap:              0,
        //     increaseCooldown: 0
        // });

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);

        assertEq(allConfigsAfter.length, 15);

        // TODO: Reorder to follow forum post
        // TODO: Change emode

        CollateralOnboardingTestParams memory lbtcConfigParams = CollateralOnboardingTestParams({
            // General
            symbol:       'LBTC',
            tokenAddress:  Ethereum.LBTC,
            tokenDecimals: 8,
            oracleAddress: AGGOR_BTCUSD_ORACLE,
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
            supplyCap:    0,
            supplyCapMax: 0,
            supplyCapGap: 0,
            supplyCapTtl: 0,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0  // TODO: Change
        });

        CollateralOnboardingTestParams memory tbtcConfigParams = CollateralOnboardingTestParams({
            // General
            symbol:       'TBTC',
            tokenAddress:  Ethereum.TBTC,
            tokenDecimals: 8,
            oracleAddress: AGGOR_BTCUSD_ORACLE,
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
            supplyCap:    0,
            supplyCapMax: 0,
            supplyCapGap: 0,
            supplyCapTtl: 0,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0  // TODO: Change
        });

        _testCollateralOnboarding(allConfigsAfter, lbtcConfigParams);
        _testCollateralOnboarding(allConfigsAfter, tbtcConfigParams);


        // _assertSupplyCapConfig({
        //     asset:            SUSDS,
        //     max:              500_000_000,
        //     gap:              50_000_000,
        //     increaseCooldown: 12 hours
        // });

        // _assertBorrowCapConfig({
        //     asset:            SUSDS,
        //     max:              0,
        //     gap:              0,
        //     increaseCooldown: 0
        // });

        // // The sUSDS price feed does not have a decimals() function so we validate manually
        // IAaveOracle oracle = IAaveOracle(poolAddressesProvider.getPriceOracle());

        // require(
        //     oracle.getSourceOfAsset(SUSDS) == SUSDS_PRICE_FEED,
        //     '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
        // );
    }

    struct CollateralOnboardingTestParams {
        // General
        string  symbol;
        address tokenAddress;
        uint256 tokenDecimals;
        address oracleAddress;
        // IRM Params
        uint256 optimalUsageRatio;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
        // Borrowing configuration
        bool borrowEnabled;
        bool stableBorrowEnabled;
        bool isolationBorrowEnabled;
        bool siloedBorrowEnabled;
        bool flashloanEnabled;
        // Reserve configuration
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        // Supply and borrow caps
        uint256 supplyCap;
        uint256 supplyCapMax;
        uint256 supplyCapGap;
        uint256 supplyCapTtl;
        uint256 borrowCap;
        uint256 borrowCapMax;
        uint256 borrowCapGap;
        uint256 borrowCapTtl;
        // Isolation  and emode configurations
        bool    isolationMode;
        uint256 isolationModeDebtCeiling;
        uint256 liquidationProtocolFee;
        uint256 emodeCategory;
    }

    function _testCollateralOnboarding(
        ReserveConfig[]  memory allReserveConfigs,
        CollateralOnboardingTestParams memory params
    )
        internal view
    {
        // TODO: Refactor this
        address poolAddressesProvider = _getPoolAddressesProviderRegistry().getAddressesProvidersList()[0];

        address irm = _findReserveConfigBySymbol(allReserveConfigs, params.symbol).interestRateStrategy;

        ReserveConfig memory lbtcConfig = ReserveConfig({
            symbol:                   params.symbol,
            underlying:               params.tokenAddress,
            aToken:                   address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 params.tokenDecimals,
            ltv:                      params.ltv,
            liquidationThreshold:     params.liquidationThreshold,
            liquidationBonus:         params.liquidationBonus,
            liquidationProtocolFee:   params.liquidationProtocolFee,
            reserveFactor:            params.reserveFactor,
            usageAsCollateralEnabled: true,
            borrowingEnabled:         params.borrowEnabled,
            interestRateStrategy:     irm,
            stableBorrowRateEnabled:  false,
            isPaused:                 false,
            isActive:                 true,
            isFrozen:                 false,
            isSiloed:                 params.siloedBorrowEnabled,
            isBorrowableInIsolation:  params.isolationBorrowEnabled,
            isFlashloanable:          params.flashloanEnabled,
            supplyCap:                params.supplyCap,  // TODO: Fix
            borrowCap:                params.borrowCap,
            debtCeiling:              params.isolationModeDebtCeiling,
            eModeCategory:            params.emodeCategory
        });

        InterestStrategyValues memory lbtcIrmParams = InterestStrategyValues({
            addressesProvider:             address(poolAddressesProvider),
            optimalUsageRatio:             params.optimalUsageRatio,
            optimalStableToTotalDebtRatio: 0,
            baseStableBorrowRate:          params.variableRateSlope1,
            stableRateSlope1:              0,
            stableRateSlope2:              0,
            baseVariableBorrowRate:        params.baseVariableBorrowRate,
            variableRateSlope1:            params.variableRateSlope1,
            variableRateSlope2:            params.variableRateSlope2
        });

        _validateReserveConfig(lbtcConfig, allReserveConfigs);

        _validateInterestRateStrategy(irm, irm, lbtcIrmParams);
    }

}
