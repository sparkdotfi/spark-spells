// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import {
    IPoolAddressesProvider,
    RateTargetBaseInterestRateStrategy
} from "sparklend-advanced/src/RateTargetBaseInterestRateStrategy.sol";

import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";
import { MorphoTests }              from "src/test-harness/MorphoTests.sol";

import {
    ISyrupLike,
    ISparkVaultV2Like,
    ITargetKinkIRMLike,
    ITargetBaseIRMLike,
    ICustomIRMLike,
    IRateSourceLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20251113_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;

        // Maple onboarding process
        ISyrupLike syrup = ISyrupLike(SYRUP_USDT);

        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(Ethereum.ALM_PROXY);
        booleans[0] = true;

        vm.startPrank(permissionManager.admin());
        permissionManager.setLenderAllowlist(
            syrup.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();
    }

    function test_ETHEREUM_sll_sparkLendUsdcRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  SparkLend.USDC_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), SparkLend.USDC_SPTOKEN);

        _assertRateLimit(depositKey,  100_000_000e6,     50_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     200_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, SparkLend.USDC_SPTOKEN, 10_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_sparkLendUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  SparkLend.USDT_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), SparkLend.USDT_SPTOKEN);

        _assertRateLimit(depositKey,  100_000_000e6,     100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     200_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, SparkLend.USDT_SPTOKEN, 10_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_onboardB2C2() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdcKey =  RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            address(0xdeadbeef)  // TODO change
        );

        bytes32 usdtKey =  RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            address(0xdeadbeef)  // TODO change
        );

        bytes32 pyusdKey =  RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.PYUSD,
            address(0xdeadbeef)  // TODO change
        );

        _assertRateLimit(usdcKey,  0, 0);
        _assertRateLimit(usdtKey,  0, 0);
        _assertRateLimit(pyusdKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdcKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(usdtKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.USDC,
            destination:    address(0xdeadbeef),  // TODO change
            transferKey:    usdcKey,
            transferAmount: 100_000e6
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.USDT,
            destination:    address(0xdeadbeef),  // TODO change
            transferKey:    usdtKey,
            transferAmount: 100_000e6
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.PYUSD,
            destination:    address(0xdeadbeef),  // TODO change
            transferKey:    pyusdKey,
            transferAmount: 100_000e6
        }));
    }

}

contract SparkEthereum_20251113_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address internal constant PYUSD_IRM_OLD = 0xD3d3BcD8cC1D3d0676Da13F7Fc095497329EC683;
    address internal constant PYUSD_IRM_NEW = 0xDF7dedCfd522B1ee8da2c8526f642745800c8035;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_ETHEREUM_sparkLend_pyusdIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : PYUSD_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : PYUSD_IRM_NEW,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.02e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.95e27
        });
        _testRateTargetKinkToBaseIRMUpdate("PYUSD", oldParams, newParams);
    }

    function _testRateTargetKinkToBaseIRMUpdate(
        string                  memory symbol,
        RateTargetKinkIRMParams memory oldParams,
        RateTargetBaseIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRMLike(newParams.irm).RATE_SOURCE(), ICustomIRMLike(oldParams.irm).RATE_SOURCE());

        uint256 ssrRateDecimals = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).decimals();

        int256 ssrRate = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).getAPR() * int256(10 ** (27 - ssrRateDecimals));

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configBefore = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + oldParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        oldParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + oldParams.variableRateSlope1Spread),
                variableRateSlope2:            oldParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configBefore.interestRateStrategy).getVariableRateSlope1Spread()), uint256(oldParams.variableRateSlope1Spread));

        _executeAllPayloadsAndBridges();

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configAfter = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,  // NOTE: Hasn't changed
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          newParams.variableRateSlope1,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        uint256(ssrRate) + newParams.baseRateSpread,
                variableRateSlope1:            newParams.variableRateSlope1,
                variableRateSlope2:            oldParams.variableRateSlope2  // NOTE: Hasn't changed
            })
        );

        assertEq(ITargetBaseIRMLike(configAfter.interestRateStrategy).getBaseVariableBorrowRateSpread(), newParams.baseRateSpread);

        address expectedIRM = address(new RateTargetBaseInterestRateStrategy(
            IPoolAddressesProvider(address(ctx.poolAddressesProvider)),
            ICustomIRMLike(newParams.irm).RATE_SOURCE(),
            oldParams.optimalUsageRatio,  // NOTE: Hasn't changed
            newParams.baseRateSpread,
            newParams.variableRateSlope1,
            oldParams.variableRateSlope2  // NOTE: Hasn't changed
        ));

        _assertBytecodeMatches(expectedIRM, newParams.irm);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  412_668_505.386398818232221198e18);
        assertEq(spUsdsBalanceBefore, 380_702_415.599903984243896154e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 3_957.586227730796606180e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 3_592.730987073276327968e18);
    }

    function test_ETHEREUM_sparkLend_depreciateSUSDSandSDAI() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory susdsConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'sUSDS');
        ReserveConfig memory sdaiConfigBefore  = _findReserveConfigBySymbol(allConfigsBefore, 'sDAI');

        assertEq(susdsConfigBefore.ltv,                  79_00);
        assertEq(susdsConfigBefore.liquidationThreshold, 80_00);
        assertEq(susdsConfigBefore.liquidationBonus,     105_00);

        assertEq(sdaiConfigBefore.ltv,                  79_00);
        assertEq(sdaiConfigBefore.liquidationThreshold, 80_00);
        assertEq(sdaiConfigBefore.liquidationBonus,     105_00);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        // SUSDS

        ReserveConfig memory susdsConfigAfter = susdsConfigBefore;

        susdsConfigAfter.ltv       = 0;
        susdsConfigAfter.supplyCap = 1;

        _validateReserveConfig(susdsConfigAfter, allConfigsAfter);

        _assertSupplyCapConfig({
            asset:            Ethereum.SUSDS,
            max:              0,
            gap:              0,
            increaseCooldown: 0
        });

        _test_cannotSupplyNewCollateral(Ethereum.SUSDS);

        // Caps can’t be changed with automator
        ICapAutomator(SparkLend.CAP_AUTOMATOR).execSupply(Ethereum.SUSDS);

        DataTypes.ReserveConfigurationMap memory sUsdsConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.SUSDS);

        assertEq(sUsdsConfig.getSupplyCap(), 1);

        // SDAI

        ReserveConfig memory sdaiConfigAfter = sdaiConfigBefore;

        sdaiConfigAfter.ltv       = 0;
        sdaiConfigAfter.supplyCap = 1;

        _validateReserveConfig(sdaiConfigAfter, allConfigsAfter);

        _assertSupplyCapConfig({
            asset:            Ethereum.SDAI,
            max:              0,
            gap:              0,
            increaseCooldown: 0
        });

        _test_cannotSupplyNewCollateral(Ethereum.SDAI);

        // Caps can’t be changed with automator
        ICapAutomator(SparkLend.CAP_AUTOMATOR).execSupply(Ethereum.SDAI);

        DataTypes.ReserveConfigurationMap memory sDaiConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.SDAI);

        assertEq(sDaiConfig.getSupplyCap(), 1);
    }

    function test_ETHEREUM_sparkLend_healthySusdsPositionNotLiquidatable() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Setup test user with a healthy sUSDS position
        address testUser = makeAddr("testUser");

        // Give the user some sUSDS to use as collateral
        uint256 collateralAmount = 100_000e18;
        deal(Ethereum.SUSDS, testUser, collateralAmount);

        vm.startPrank(testUser);
        IERC20(Ethereum.SUSDS).approve(address(ctx.pool), type(uint256).max);

        // Supply sUSDS as collateral
        ctx.pool.supply(Ethereum.SUSDS, collateralAmount, testUser, 0);

        // Borrow DAI against sUSDS collateral (at 50% of collateral value to be very safe)
        uint256 borrowAmount = 40_000e18;  // Well under the 79% LTV
        ctx.pool.borrow(Ethereum.DAI, borrowAmount, 2, 0, testUser);
        vm.stopPrank();

        // Execute payload which sets LTV to 0
        _executeAllPayloadsAndBridges();

        // Verify user still has a healthy position (can't be liquidated)
        (,,,,, uint256 healthFactor) = ctx.pool.getUserAccountData(testUser);
        
        // Health factor should still be healthy (>1e18)
        assertGt(healthFactor, 1e18);

        // Try to liquidate the position - should revert with error code 45 (HEALTH_FACTOR_NOT_BELOW_THRESHOLD)
        vm.expectRevert(bytes("45"));
        ctx.pool.liquidationCall(
            Ethereum.SUSDS,  // collateral
            Ethereum.DAI,    // debt
            testUser,        // user
            borrowAmount,    // debt to cover
            false            // receive aToken
        );
    }

    function test_ETHEREUM_sparkLend_healthySdaiPositionNotLiquidatable() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Setup test user with a healthy sDAI position
        address testUser = makeAddr("testUser");

        // Give the user some sDAI to use as collateral
        uint256 collateralAmount = 100_000e18;
        deal(Ethereum.SDAI, testUser, collateralAmount);

        vm.startPrank(testUser);
        IERC20(Ethereum.SDAI).approve(address(ctx.pool), type(uint256).max);

        // Supply sDAI as collateral
        ctx.pool.supply(Ethereum.SDAI, collateralAmount, testUser, 0);

        // Borrow DAI against sDAI collateral (at 50% of collateral value to be very safe)
        uint256 borrowAmount = 40_000e18;  // Well under the 79% LTV
        ctx.pool.borrow(Ethereum.DAI, borrowAmount, 2, 0, testUser);
        vm.stopPrank();

        // Execute payload which sets LTV to 0
        _executeAllPayloadsAndBridges();

        // Verify user still has a healthy position (can't be liquidated)
        (,,,,, uint256 healthFactor) = ctx.pool.getUserAccountData(testUser);
        
        // Health factor should still be healthy (>1e18)
        assertGt(healthFactor, 1e18);

        // Try to liquidate the position - should revert with error code 45 (HEALTH_FACTOR_NOT_BELOW_THRESHOLD)
        vm.expectRevert(bytes("45"));
        ctx.pool.liquidationCall(
            Ethereum.SDAI,   // collateral
            Ethereum.DAI,    // debt
            testUser,        // user
            borrowAmount,    // debt to cover
            false            // receive aToken
        );
    }

    function _test_cannotSupplyNewCollateral(address asset) public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Setup test user
        address testUser = makeAddr("testUser");

        // Give the user some asset
        uint256 supplyAmount = 1;
        deal(asset, testUser, supplyAmount);

        vm.startPrank(testUser);
        IERC20(asset).approve(address(ctx.pool), type(uint256).max);

        // Attempt to supply asset should fail due to supply cap
        vm.expectRevert(bytes("51")); // Cap exceeded error
        ctx.pool.supply(asset, supplyAmount, testUser, 0);

        vm.stopPrank();

        // Verify no supply occurred
        assertEq(IERC20(asset).balanceOf(testUser), supplyAmount);
    }

    function test_ETHEREUM_sUSDS_borrowsCannotBeIncreased() public onChain(ChainIdUtils.Ethereum()) {
        _test_cannotIncreaseBorrowsAfterSpellExecution(Ethereum.SUSDS);
    }

    function test_ETHEREUM_sDAI_borrowsCannotBeIncreased() public onChain(ChainIdUtils.Ethereum()) {
        _test_cannotIncreaseBorrowsAfterSpellExecution(Ethereum.SDAI);
    }

    function _test_cannotIncreaseBorrowsAfterSpellExecution(address asset) internal {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Setup test user with collateral
        address testUser = makeAddr("testUser");
        uint256 collateralAmount = 100_000e18;
        deal(asset, testUser, collateralAmount);

        vm.startPrank(testUser);
        IERC20(asset).approve(address(ctx.pool), type(uint256).max);

        // Supply collateral
        ctx.pool.supply(asset, collateralAmount, testUser, 0);

        // Borrow a small amount of USDC initially (well under the LTV limit)
        uint256 initialBorrowAmount = 1_000e6;  // 1,000 USDC
        ctx.pool.borrow(Ethereum.USDC, initialBorrowAmount, 2, 0, testUser);

        (uint256 totalCollateralBaseBefore,,,,, uint256 healthFactorBefore) = ctx.pool.getUserAccountData(testUser);
        assertTrue(totalCollateralBaseBefore > 0, "User should have collateral");
        assertTrue(healthFactorBefore > 1e18, "Position should be healthy");

        vm.stopPrank();

        // Execute payload which sets LTV to 0
        _executeAllPayloadsAndBridges();

        vm.startPrank(testUser);

        // Try to borrow an additional small amount - should fail
        uint256 additionalBorrowAmount = 1;  // 1 wei
        vm.expectRevert(bytes("57"));        // Ltv validation failed
        ctx.pool.borrow(Ethereum.USDC, additionalBorrowAmount, 2, 0, testUser);

        // Verify user still has their existing borrow
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = ctx.pool.getUserAccountData(testUser);
        assertTrue(totalCollateralBase > 0, "User should still have collateral");
        assertTrue(totalDebtBase > 0, "User should still have debt");

        vm.stopPrank();
    }

    function test_ETHEREUM_sparkLend_wethAndSusdsCollateralWithdrawalOrder() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Setup test user
        address testUser = makeAddr("testUser");

        // Give the user some WETH and sUSDS to use as collateral
        uint256 wethCollateralAmount  = 10e18;     // 10 WETH
        uint256 susdsCollateralAmount = 50_000e18; // 50k sUSDS
        deal(Ethereum.WETH, testUser, wethCollateralAmount);
        deal(Ethereum.SUSDS, testUser, susdsCollateralAmount);

        vm.startPrank(testUser);
        
        // Approve pool to use tokens
        IERC20(Ethereum.WETH).approve(address(ctx.pool),  type(uint256).max);
        IERC20(Ethereum.SUSDS).approve(address(ctx.pool), type(uint256).max);

        // Supply both sUSDS and WETH as collateral
        ctx.pool.supply(Ethereum.SUSDS, susdsCollateralAmount, testUser, 0);
        ctx.pool.supply(Ethereum.WETH,  wethCollateralAmount,  testUser, 0);

        // Borrow USDC against the combined collateral
        uint256 borrowAmount = 20_000e6; // 20k USDC
        ctx.pool.borrow(Ethereum.USDC, borrowAmount, 2, 0, testUser);

        // Execute the payload which changes isolation mode
        vm.stopPrank();

        _executeAllPayloadsAndBridges();

        vm.startPrank(testUser);

        // Try to withdraw WETH - should fail while sUSDS is still being used
        vm.expectRevert(bytes("57")); // Ltv validation failed
        ctx.pool.withdraw(Ethereum.WETH, 1e18, testUser);

        // Withdraw sUSDS collateral first
        uint256 susdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(testUser);
        ctx.pool.withdraw(Ethereum.SUSDS, type(uint256).max, testUser);
        uint256 susdsBalanceAfter = IERC20(Ethereum.SUSDS).balanceOf(testUser);
        
        // Verify sUSDS withdrawal succeeded
        assertGe(susdsBalanceAfter, susdsBalanceBefore + susdsCollateralAmount);

        // Now should be able to withdraw WETH after sUSDS is removed
        uint256 wethBalanceBefore = IERC20(Ethereum.WETH).balanceOf(testUser);
        ctx.pool.withdraw(Ethereum.WETH, 1e18, testUser);
        uint256 wethBalanceAfter = IERC20(Ethereum.WETH).balanceOf(testUser);

        // Verify WETH withdrawal succeeded
        assertGe(wethBalanceAfter, wethBalanceBefore + 1e18);

        vm.stopPrank();
    }

}

contract SparkEthereum_20251113_SpellTests is SpellTests {

    using SafeERC20 for IERC20;

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 625_069e18;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 250_000_000e6);
        assertEq(usdtVault.depositCap(), 250_000_000e6);
        assertEq(ethVault.depositCap(),  50_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(usdtVault.depositCap(), 500_000_000e6);
        assertEq(ethVault.depositCap(),  100_000e18);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 425_482_672.814637e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              usdtVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 441_712_918.49959e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              ethVault,
            depositCap:         100_000e18,
            expectedMaxDeposit: 84_629.835138740220858047e18
        });
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(usdcVault.depositCap(), 150_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 250_000_000e6);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         250_000_000e6,
            expectedMaxDeposit: 249_999_997.9e6
        });
    }

    function _test_vault_depositBoundaryLimit(
        ISparkVaultV2Like vault,
        uint256           depositCap,
        uint256           expectedMaxDeposit
    ) internal {
        address asset = vault.asset();

        uint256 maxDeposit = depositCap - vault.totalAssets();

        assertEq(maxDeposit, expectedMaxDeposit);

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        vault.deposit(maxDeposit + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(vault.balanceOf(address(this)), 0);

        deal(asset, address(this), maxDeposit);
        IERC20(asset).safeIncreaseAllowance(address(vault), maxDeposit);

        uint256 shares = vault.deposit(maxDeposit, address(this));

        assertEq(vault.balanceOf(address(this)), shares);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 groveUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.GROVE_SUBDAO_PROXY);

        assertEq(sparkUsdsBalanceBefore, 32_722_317.445801365846236778e18);
        assertEq(groveUsdsBalanceBefore, 1_167_444e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),        sparkUsdsBalanceBefore - GROVE_PAYMENT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.GROVE_SUBDAO_PROXY), groveUsdsBalanceBefore + GROVE_PAYMENT_AMOUNT);
    }

}

contract SparkEthereum_20251113_MorphoTests is MorphoTests {

    address internal constant ETH        = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-06T05:55:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_BASE_sparkUSDCVault_onboardEth() external onChain(ChainIdUtils.Base()) {
        _testMorphoCapUpdate({
            vault: Base.MORPHO_VAULT_SUSDC,
            config: MarketParams({
                loanToken:       Base.USDC,
                collateralToken: ETH,
                oracle:          ETH_ORACLE,
                irm:             Base.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            currentCap: 0,
            newCap:     1_000_000_000e6
        });
    }

}
