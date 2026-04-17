// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { UserConfiguration }    from "sparklend-v1-core/protocol/libraries/configuration/UserConfiguration.sol";

import { AaveOracle }        from "sparklend-v1-core/misc/AaveOracle.sol";
import { DataTypes }         from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPool }             from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator } from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

contract SparkEthereum_20260423_SLLTests is SparkLiquidityLayerTests {

    constructor() {
        _spellId   = 20260423;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
    }

}

contract SparkEthereum_20260423_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using SafeERC20 for IERC20;

    address internal constant OLD_USDT_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;
    address internal constant NEW_USDT_IRM = 0x4E494988E68e6Fc52309BE4937869e27F0C304AC;

    address internal constant OLD_WETH_IRM = 0x4FD869adB651917D5c2591DD7128Ae6e1C24bDD5;
    address internal constant NEW_WETH_IRM = 0xDFB6206FfC5BA5B48D2852370ee6A1bf6887476a;

    constructor() {
        _spellId   = 20260423;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
    }

    function test_ETHEREUM_sparkLend_wethIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.003e27,
            variableRateSlope2       : 1.2e27,
            optimalUsageRatio        : 0.90e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.001e27,
            variableRateSlope2       : 0.75e27,
            optimalUsageRatio        : 0.90e27
        });
        _testRateTargetKinkIRMUpdate("WETH", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.005e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_deprecateRETH() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory rethConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'rETH');

        assertEq(rethConfigBefore.ltv,      79_00);
        assertEq(rethConfigBefore.isFrozen, false);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory rethConfigAfter = rethConfigBefore;

        rethConfigAfter.ltv      = 0;
        rethConfigAfter.isFrozen = true;

        _validateReserveConfig(rethConfigAfter, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_deprecateRETHUserActions() external onChain(ChainIdUtils.Ethereum()) {
        IPool pool = IPool(SparkLend.POOL);

        IERC20 reth = IERC20(Ethereum.RETH);
        IERC20 usdc = IERC20(Ethereum.USDC);

        // Step 1: Set up an existing position

        address testUser = makeAddr("testUser");

        uint256 rethAmount = 100 * 10 ** IERC20Metadata(address(reth)).decimals();
        uint256 usdcAmount = 10  * 10 ** IERC20Metadata(address(usdc)).decimals();

        deal(address(reth), testUser, 2 * rethAmount);

        vm.startPrank(testUser);

        reth.approve(address(pool), type(uint256).max);

        pool.supply(address(reth), 2 * rethAmount, testUser, 0);
        pool.borrow(address(usdc), 2 * usdcAmount, 2,        0, testUser);

        vm.stopPrank();

        // Step 2: Execute spell

        _executeAllPayloadsAndBridges();

        // Step 3: Ensure user can't supply or borrow.

        vm.startPrank(testUser);

        reth.approve(address(pool), type(uint256).max);

        // User can't supply.
        vm.expectRevert(abi.encode("28"));  // RESERVE_FROZEN
        pool.supply(address(reth), rethAmount, testUser, 0);

        // User can't borrow.
        vm.expectRevert(abi.encode("57"));  // As LTV is 0, user can't borrow.
        pool.borrow(address(usdc), usdcAmount, 2, 0, testUser);

        // Step 4: User can repay the debt.

        usdc.safeIncreaseAllowance(address(pool), type(uint256).max);

        pool.repay(address(usdc), usdcAmount, 2, testUser);

        // Step 5: User can withdraw the collateral.

        pool.withdraw(address(reth), 1 * 10 ** IERC20Metadata(address(reth)).decimals(), testUser);

        vm.stopPrank();

        // Step 6: User can be liquidated.

        address mockOracle = address(new MockAggregator(1));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);

        assets[0]  = address(reth);
        sources[0] = mockOracle;

        vm.prank(Ethereum.SPARK_PROXY);
        AaveOracle(SparkLend.AAVE_ORACLE).setAssetSources(assets, sources);

        deal(address(usdc), testUser, usdcAmount);

        vm.prank(testUser);
        pool.liquidationCall(address(reth), address(usdc), testUser, usdcAmount, false);
    }

}

contract SparkEthereum_20260423_SpellTests is SpellTests {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;

    constructor() {
        _spellId   = 20260423;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      36_373_387.913977620254401020e18);
        assertEq(foundationBalanceBefore,      0.0095e18);
        assertEq(assetFoundationBalanceBefore, 142_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
