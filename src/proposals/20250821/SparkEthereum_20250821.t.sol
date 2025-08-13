// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { ReserveConfig }              from '../../test-harness/ProtocolV3TestBase.sol';
import { SparkLendContext }           from '../../test-harness/SparklendTests.sol';
import { SparkLiquidityLayerContext } from '../../test-harness/SparkLiquidityLayerTests.sol';
import { SparkTestBase }              from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250821Test is SparkTestBase {

    uint256 internal constant USDS_AMOUNT = 19_411.17e18;

    address internal constant AAVE_V3_COLLECTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    address internal constant MORPHO_TOKEN      = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address internal constant SPARK_MULTISIG    = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;

    address internal constant OLD_USDC_USDT_IRM = 0xD3d3BcD8cC1D3d0676Da13F7Fc095497329EC683;
    address internal constant NEW_USDC_USDT_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;

    address internal constant OLD_USDS_DAI_IRM = 0xD99f41B22BBb4af36ae452Bf0Cc3aA07ce91bD66;
    address internal constant NEW_USDS_DAI_IRM = 0x8a95998639A34462A1FdAaaA5506F66F90Ef2fDd;

    address internal constant OLD_WETH_IRM = 0xf4268AeC16d13446381F8a2c9bB05239323756ca;
    address internal constant NEW_WETH_IRM = 0x4FD869adB651917D5c2591DD7128Ae6e1C24bDD5;

    constructor() {
        id = "20250821";
    }

    function setUp() public {
        setupDomains("2025-08-13T13:24:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xb12057500EB57C3c43B91171D52b6DB141cCa01a;
    }

    function test_ETHEREUM_Spark_MorphoUSDSVaultFee() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).fee(),          0);
        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).feeRecipient(), address(0));

        executeAllPayloadsAndBridges();

        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).fee(),          0.1e18);
        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).feeRecipient(), Ethereum.ALM_PROXY);
    }

    function test_ETHEREUM_Spark_MorphoTransferLimit() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            MORPHO_TOKEN,
            SPARK_MULTISIG
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 100_000e18, 100_000e18 / uint256(1 days));

        deal(MORPHO_TOKEN, Ethereum.ALM_PROXY, 200_000e18);

        vm.prank(ctx.relayer);
        controller.transferAsset(MORPHO_TOKEN, SPARK_MULTISIG, 100_000e18);

        assertEq(IERC20(MORPHO_TOKEN).balanceOf(SPARK_MULTISIG),     100_000e18);
        assertEq(IERC20(MORPHO_TOKEN).balanceOf(Ethereum.ALM_PROXY), 100_000e18);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey),    0);

        skip(1 days + 1 seconds);  // +1 second due to rounding

        vm.prank(ctx.relayer);
        controller.transferAsset(MORPHO_TOKEN, SPARK_MULTISIG, 100_000e18);

        assertEq(IERC20(MORPHO_TOKEN).balanceOf(SPARK_MULTISIG),     200_000e18);
        assertEq(IERC20(MORPHO_TOKEN).balanceOf(Ethereum.ALM_PROXY), 0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey),    0);

        skip(1 days + 1 seconds);  // +1 second due to rounding

        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 100_000e18);
    }

    function test_ETHEREUM_USDSTransfer() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(IERC20(Ethereum.USDS).balanceOf(AAVE_V3_COLLECTOR),    0);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY), 22_058_467.785801365846236778e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(AAVE_V3_COLLECTOR),    USDS_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY), 22_058_467.785801365846236778e18 - USDS_AMOUNT);
    }

    function test_ETHEREUM_sparkLend_daiIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetKinkIRMUpdate("DAI", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdsIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
         RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDS_DAI_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetKinkIRMUpdate("USDS", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdcIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDC", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_wethIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.005e27,
            variableRateSlope2       : 1.2e27,
            optimalUsageRatio        : 0.90e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.003e27,
            variableRateSlope2       : 1.2e27,
            optimalUsageRatio        : 0.90e27
        });
        _testRateTargetKinkIRMUpdate("WETH", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_marketUpdates() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);

        // wstETH Before

        ReserveConfig memory wstethConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'wstETH');

        assertEq(wstethConfigBefore.ltv,                  79_00);
        assertEq(wstethConfigBefore.liquidationThreshold, 80_00);

        // cbBTC Before

        ReserveConfig memory cbBTCConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'cbBTC');

        assertEq(cbBTCConfigBefore.ltv,                  74_00);
        assertEq(cbBTCConfigBefore.liquidationThreshold, 75_00);

        // weETH Before

        ReserveConfig memory weETHConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'weETH');

        assertEq(weETHConfigBefore.ltv,                  72_00);
        assertEq(weETHConfigBefore.liquidationThreshold, 73_00);
        assertEq(weETHConfigBefore.liquidationBonus,     110_00);

        // rsETH Before

        ReserveConfig memory rsETHConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'rsETH');

        assertEq(rsETHConfigBefore.ltv,                  72_00);
        assertEq(rsETHConfigBefore.liquidationThreshold, 73_00);

        // ezETH Before

        ReserveConfig memory ezETHConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'ezETH');

        assertEq(ezETHConfigBefore.ltv,                  72_00);
        assertEq(ezETHConfigBefore.liquidationThreshold, 73_00);

        // lBTC Before

        ReserveConfig memory lBTCConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'LBTC');

        assertEq(lBTCConfigBefore.ltv,                  65_00);
        assertEq(lBTCConfigBefore.liquidationThreshold, 70_00);

        // tBTC Before

        ReserveConfig memory tBTCConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'tBTC');

        assertEq(tBTCConfigBefore.ltv,                  65_00);
        assertEq(tBTCConfigBefore.liquidationThreshold, 70_00);

        // wETH Before

        ReserveConfig memory wethConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'WETH');

        assertEq(wethConfigBefore.ltv,                  82_00);
        assertEq(wethConfigBefore.liquidationThreshold, 83_00);
        assertEq(wethConfigBefore.interestRateStrategy, OLD_WETH_IRM);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        // wstETH After

        ReserveConfig memory wstethConfigAfter = wstethConfigBefore;

        wstethConfigAfter.ltv                  = 83_00;
        wstethConfigAfter.liquidationThreshold = 84_00;

        _validateReserveConfig(wstethConfigAfter, allConfigsAfter);

        _assertBorrowCapConfig({
            asset:            Ethereum.WSTETH,
            max:              1,
            gap:              1,
            increaseCooldown: 12 hours
        });

        // cbBTC After

        ReserveConfig memory cbBTCConfigAfter = cbBTCConfigBefore;

        cbBTCConfigAfter.ltv                  = 81_00;
        cbBTCConfigAfter.liquidationThreshold = 82_00;

        _validateReserveConfig(cbBTCConfigAfter, allConfigsAfter);

        // weETH After

        ReserveConfig memory weETHConfigAfter = weETHConfigBefore;

        weETHConfigAfter.ltv                  = 79_00;
        weETHConfigAfter.liquidationThreshold = 80_00;
        weETHConfigAfter.liquidationBonus     = 108_00;

        _validateReserveConfig(weETHConfigAfter, allConfigsAfter);

        // rsETH After

        ReserveConfig memory rsETHConfigAfter = rsETHConfigBefore;

        rsETHConfigAfter.ltv                  = 75_00;
        rsETHConfigAfter.liquidationThreshold = 76_00;

        _validateReserveConfig(rsETHConfigAfter, allConfigsAfter);

        // ezETH After

        ReserveConfig memory ezETHConfigAfter = ezETHConfigBefore;

        ezETHConfigAfter.ltv                  = 75_00;
        ezETHConfigAfter.liquidationThreshold = 76_00;

        _validateReserveConfig(ezETHConfigAfter, allConfigsAfter);

        // lBTC After

        ReserveConfig memory lBTCConfigAfter = lBTCConfigBefore;

        lBTCConfigAfter.ltv                  = 74_00;
        lBTCConfigAfter.liquidationThreshold = 75_00;

        _validateReserveConfig(lBTCConfigAfter, allConfigsAfter);

        // tBTC After

        ReserveConfig memory tBTCConfigAfter = tBTCConfigBefore;

        tBTCConfigAfter.ltv                  = 74_00;
        tBTCConfigAfter.liquidationThreshold = 75_00;

        _validateReserveConfig(tBTCConfigAfter, allConfigsAfter);

        // wETH After

        ReserveConfig memory wethConfigAfter = wethConfigBefore;

        wethConfigAfter.ltv                  = 85_00;
        wethConfigAfter.liquidationThreshold = 86_00;
        wethConfigAfter.interestRateStrategy = NEW_WETH_IRM;

        _validateReserveConfig(wethConfigAfter, allConfigsAfter);

        // rETH After

        _assertBorrowCapConfig({
            asset:            Ethereum.RETH,
            max:              1,
            gap:              1,
            increaseCooldown: 12 hours
        });
    }

}
