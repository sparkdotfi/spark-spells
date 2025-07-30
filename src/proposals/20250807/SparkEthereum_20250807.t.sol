// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { InterestStrategyValues, ReserveConfig } from '../../test-harness/ProtocolV3TestBase.sol';
import { ICustomIRM, IRateSource }               from '../../test-harness/SparkEthereumTests.sol';
import { SparkLendContext }                      from '../../test-harness/SparklendTests.sol';
import { SparkTestBase }                         from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250807Test is SparkTestBase {

    address internal constant CURVE_PYUSDUSDC     = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address internal constant PYUSD               = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant PYUSD_ATOKEN        = 0x779224df1c756b4EDD899854F32a53E8c2B2ce5d;
    address internal constant PYUSD_PRICE_FEED    = 0x42a03F81dd8A1cEcD746dc262e4d1CD9fD39F777;
    address internal constant USDS_DAI_IRM        = 0xD99f41B22BBb4af36ae452Bf0Cc3aA07ce91bD66;
    address internal constant USDS_DAI_IRM_OLD    = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;
    address internal constant USDC_USDT_IRM_OLD   = 0x7F2fc6A7E3b3c658A84999b26ad2013C4Dc87061;
    address internal constant USDC_USDT_PYUSD_IRM = 0xD3d3BcD8cC1D3d0676Da13F7Fc095497329EC683;

    constructor() {
        id = "20250807";
    }

    function setUp() public {
        setupDomains("2025-07-29T15:43:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x41EdbF09cd2f272175c7fACB857B767859543D15;

        // Deal the amount of pyUSD to Spark Proxy
        deal(PYUSD, Ethereum.SPARK_PROXY, 1e6);
    }

    function test_ETHEREUM_sparkLend_collateralOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        int256 ssrRate = IRateSource(ICustomIRM(USDC_USDT_PYUSD_IRM).RATE_SOURCE()).getAPR();

        SparkLendAssetOnboardingParams memory params = SparkLendAssetOnboardingParams({
            // General
            symbol:            'PYUSD',
            tokenAddress:      PYUSD,
            oracleAddress:     PYUSD_PRICE_FEED,
            collateralEnabled: false,
            // IRM Params
            optimalUsageRatio:      0.95e27,
            baseVariableBorrowRate: 0,
            variableRateSlope1:     uint256(ssrRate) + 0.015e27,
            variableRateSlope2:     0.15e27,
            // Borrowing configuration
            borrowEnabled:          true,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       true,
            // Reserve configuration
            ltv:                  0,
            liquidationThreshold: 0,
            liquidationBonus:     0,
            reserveFactor:        10_00,
            // Supply caps
            supplyCap:    50_000_000,
            supplyCapMax: 500_000_000,
            supplyCapGap: 50_000_000,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    25_000_000,
            borrowCapMax: 475_000_000,
            borrowCapGap: 25_000_000,
            borrowCapTtl: 12 hours,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   0,
            emodeCategory:            2
        });

        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);

        uint256 startingReserveLength = allConfigsBefore.length;

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        assertEq(allConfigsAfter.length, startingReserveLength + 1);

        address irm = _findReserveConfigBySymbol(allConfigsAfter, params.symbol).interestRateStrategy;

        assertEq(irm, USDC_USDT_PYUSD_IRM);

        ReserveConfig memory reserveConfig = ReserveConfig({
            symbol:                   params.symbol,
            underlying:               params.tokenAddress,
            aToken:                   address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 IERC20(params.tokenAddress).decimals(),
            ltv:                      params.ltv,
            liquidationThreshold:     params.liquidationThreshold,
            liquidationBonus:         params.liquidationBonus,
            liquidationProtocolFee:   params.liquidationProtocolFee,
            reserveFactor:            params.reserveFactor,
            usageAsCollateralEnabled: params.collateralEnabled,
            borrowingEnabled:         params.borrowEnabled,
            interestRateStrategy:     irm,
            stableBorrowRateEnabled:  false,
            isPaused:                 false,
            isActive:                 true,
            isFrozen:                 false,
            isSiloed:                 params.siloedBorrowEnabled,
            isBorrowableInIsolation:  params.isolationBorrowEnabled,
            isFlashloanable:          params.flashloanEnabled,
            supplyCap:                params.supplyCap,
            borrowCap:                params.borrowCap,
            debtCeiling:              params.isolationModeDebtCeiling,
            eModeCategory:            params.emodeCategory
        });

        InterestStrategyValues memory irmParams = InterestStrategyValues({
            addressesProvider:             address(ctx.poolAddressesProvider),
            optimalUsageRatio:             params.optimalUsageRatio,
            optimalStableToTotalDebtRatio: 0,
            baseStableBorrowRate:          params.variableRateSlope1,
            stableRateSlope1:              0,
            stableRateSlope2:              0,
            baseVariableBorrowRate:        params.baseVariableBorrowRate,
            variableRateSlope1:            params.variableRateSlope1,
            variableRateSlope2:            params.variableRateSlope2
        });

        _validateReserveConfig(reserveConfig, allConfigsAfter);

        _validateInterestRateStrategy(irm, irm, irmParams);

        _assertSupplyCapConfig({
            asset:            params.tokenAddress,
            max:              params.supplyCapMax,
            gap:              params.supplyCapGap,
            increaseCooldown: params.supplyCapTtl
        });

        _assertBorrowCapConfig({
            asset:            params.tokenAddress,
            max:              params.borrowCapMax,
            gap:              params.borrowCapGap,
            increaseCooldown: params.borrowCapTtl
        });

        assertEq(IERC20(_findReserveConfigBySymbol(allConfigsAfter, params.symbol).aToken).totalSupply(), 1e6);

        require(
            ctx.priceOracle.getSourceOfAsset(params.tokenAddress) == params.oracleAddress,
            '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
        );
    }

    function test_ETHEREUM_sparkLend_usdsIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDS_DAI_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0075e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetKinkIRMUpdate("USDS", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_daiIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDS_DAI_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0075e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetKinkIRMUpdate("DAI", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdcIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_PYUSD_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDC", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_PYUSD_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdsFlashloanEnabled() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);

        assertEq(_findReserveConfigBySymbol(allConfigsBefore, 'USDS').isFlashloanable, false);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        assertEq(_findReserveConfigBySymbol(allConfigsAfter, 'USDS').isFlashloanable, true);
    }

    function test_ETHEREUM_sll_onboardPyusd() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 pyusdDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
            PYUSD_ATOKEN
        );
        bytes32 pyusdWithdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_WITHDRAW(),
            PYUSD_ATOKEN
        );

        _assertRateLimit(pyusdDepositKey,  0, 0);
        _assertRateLimit(pyusdWithdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(pyusdDepositKey,  50_000_000e6,      25_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdWithdrawKey, type(uint256).max, 0);
    }

    function test_ETHEREUM_curve_pyusdusdcOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testCurveOnboarding({
            pool:                        CURVE_PYUSDUSDC,
            expectedDepositAmountToken0: 0,
            expectedSwapAmountToken0:    50_000e6,
            maxSlippage:                 0.9995e18,
            swapLimit:                   RateLimitData(5_000_000e18, 25_000_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(0, 0),
            withdrawLimit:               RateLimitData(0, 0)
        });
    }

}
