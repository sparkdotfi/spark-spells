// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { IRateSourceLike } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20260827_SLLTests is SparkLiquidityLayerTests {

    address internal constant USDG_RLUSD_IRM = 0x473fDf9713C9a02A9a9c17173a57d120493F3C6B;

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 20260827;
        _blockDate = 1787063010;
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sll_onboardSPUSDG() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  USDG_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), USDG_SPTOKEN);

        IERC20 spUsdg = IERC20(USDG_SPTOKEN);
        IERC20 usdg   = IERC20(Ethereum.USDG);

        uint256 depositAmount = 1_000_000e6;

        deal(address(usdg), address(ctx.proxy), depositAmount);

        assertEq(controller.maxSlippages(USDG_SPTOKEN), 0);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(USDG_SPTOKEN), 0.99999e18);

        _assertRateLimit(depositKey,  100_000_000e6,     100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        uint256 aTokenUnderlyingBalance = usdg.balanceOf(USDG_SPTOKEN);

        assertEq(usdg.balanceOf(address(ctx.proxy)),   depositAmount);
        assertEq(spUsdg.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.depositAave(USDG_SPTOKEN, depositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e6 - depositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(usdg.balanceOf(USDG_SPTOKEN),       aTokenUnderlyingBalance + depositAmount);
        assertEq(usdg.balanceOf(address(ctx.proxy)), 0);

        assertEq(spUsdg.balanceOf(address(ctx.proxy)), depositAmount);

        vm.prank(ctx.relayer);
        controller.withdrawAave(USDG_SPTOKEN, depositAmount / 2);

        // Withdrawals refill the deposit rate limit
        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e6 - depositAmount + depositAmount / 2);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(usdg.balanceOf(address(ctx.proxy)),   depositAmount / 2);
        assertEq(spUsdg.balanceOf(address(ctx.proxy)), depositAmount / 2);
        assertEq(usdg.balanceOf(USDG_SPTOKEN),         aTokenUnderlyingBalance + depositAmount / 2);

        skip(1 days);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e6);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
    }

    function test_ETHEREUM_sll_onboardSPRLUSD() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  RLUSD_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), RLUSD_SPTOKEN);

        IERC20 rlUsd   = IERC20(Ethereum.RLUSD);
        IERC20 spRlusd = IERC20(RLUSD_SPTOKEN);

        uint256 depositAmount = 1_000_000e18;

        deal(address(rlUsd), address(ctx.proxy), depositAmount);

        assertEq(controller.maxSlippages(RLUSD_SPTOKEN), 0);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(RLUSD_SPTOKEN), 0.99999e18);

        _assertRateLimit(depositKey,  100_000_000e18,    100_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        uint256 aTokenUnderlyingBalance = rlUsd.balanceOf(RLUSD_SPTOKEN);

        assertEq(rlUsd.balanceOf(address(ctx.proxy)),   depositAmount);
        assertEq(spRlusd.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.depositAave(RLUSD_SPTOKEN, depositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e18 - depositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(rlUsd.balanceOf(RLUSD_SPTOKEN),      aTokenUnderlyingBalance + depositAmount);
        assertEq(rlUsd.balanceOf(address(ctx.proxy)), 0);

        assertEq(spRlusd.balanceOf(address(ctx.proxy)), depositAmount);

        vm.prank(ctx.relayer);
        controller.withdrawAave(RLUSD_SPTOKEN, depositAmount / 2);

        // Withdrawals refill the deposit rate limit
        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e18 - depositAmount + depositAmount / 2);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(rlUsd.balanceOf(address(ctx.proxy)),   depositAmount / 2);
        assertEq(spRlusd.balanceOf(address(ctx.proxy)), depositAmount / 2);
        assertEq(rlUsd.balanceOf(RLUSD_SPTOKEN),        aTokenUnderlyingBalance + depositAmount / 2);

        skip(1 days);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  100_000_000e18);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }
        super.deal(token, to, amount);
    }

}

contract SparkEthereum_20260827_SparklendTests is SparklendTests {

    address internal constant USDG_RLUSD_IRM = 0x473fDf9713C9a02A9a9c17173a57d120493F3C6B;

    address internal constant USDG_SPTOKEN  = 0x6f335538257ef440F3c51e925a5C820f722a1F9F;
    address internal constant RLUSD_SPTOKEN = 0x59275Fb72c8004F44BA44432e25082932Fd677f1;

    constructor() {
        _spellId   = 20260827;
        _blockDate = 1787063010;
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkLend_onboardUsdgAndRlusd() external onChain(ChainIdUtils.Ethereum()) {
        uint256 ssrRate = uint256(IRateSourceLike(SparkLend.SSR_RATE_SOURCE).getAPR());

        SparkLendAssetOnboardingParams[] memory newAssets = new SparkLendAssetOnboardingParams[](2);

        newAssets[0] = SparkLendAssetOnboardingParams({
            // General
            symbol:            'USDG',
            tokenAddress:      Ethereum.USDG,
            oracleAddress:     SparkLend.FIXED_USD_PRICE_FEED,
            collateralEnabled: false,
            // IRM Params
            optimalUsageRatio:      0.95e27,
            baseVariableBorrowRate: ssrRate,
            variableRateSlope1:     0.003e27,
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
            supplyCap:    uint48(ReserveConfiguration.MAX_VALID_SUPPLY_CAP),
            supplyCapMax: 0,
            supplyCapGap: 0,
            supplyCapTtl: 0,
            // Borrow caps
            borrowCap:    uint48(ReserveConfiguration.MAX_VALID_BORROW_CAP),
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        newAssets[1] = SparkLendAssetOnboardingParams({
            // General
            symbol:            'RLUSD',
            tokenAddress:      Ethereum.RLUSD,
            oracleAddress:     SparkLend.FIXED_USD_PRICE_FEED,
            collateralEnabled: false,
            // IRM Params
            optimalUsageRatio:      0.95e27,
            baseVariableBorrowRate: ssrRate,
            variableRateSlope1:     0.003e27,
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
            supplyCap:    uint48(ReserveConfiguration.MAX_VALID_SUPPLY_CAP),
            supplyCapMax: 0,
            supplyCapGap: 0,
            supplyCapTtl: 0,
            // Borrow caps
            borrowCap:    uint48(ReserveConfiguration.MAX_VALID_BORROW_CAP),
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        _testAssetOnboardings(newAssets);

        // The spTokens must land at the predicted addresses baked into the payload, the
        // reserves must point at the custom SSR IRM, and the seed deposits must be supplied.
        DataTypes.ReserveData memory usdgData  = IPool(SparkLend.POOL).getReserveData(Ethereum.USDG);
        DataTypes.ReserveData memory rlusdData = IPool(SparkLend.POOL).getReserveData(Ethereum.RLUSD);

        assertEq(usdgData.aTokenAddress,  USDG_SPTOKEN);
        assertEq(rlusdData.aTokenAddress, RLUSD_SPTOKEN);

        assertEq(usdgData.interestRateStrategyAddress,  USDG_RLUSD_IRM);
        assertEq(rlusdData.interestRateStrategyAddress, USDG_RLUSD_IRM);

        assertEq(IERC20(USDG_SPTOKEN).totalSupply(),  1e6);
        assertEq(IERC20(RLUSD_SPTOKEN).totalSupply(), 1e18);
    }

    function test_ETHEREUM_sparkLend_activateUsdgAndRlusd_e2e() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigs = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory rlusdConfig = _findReserveConfigBySymbol(allConfigs, 'RLUSD');
        ReserveConfig memory usdgConfig  = _findReserveConfigBySymbol(allConfigs, 'USDG');
        ReserveConfig memory wethConfig  = _findReserveConfigBySymbol(allConfigs, 'WETH');

        assertEq(usdgConfig.borrowingEnabled,  true);
        assertEq(rlusdConfig.borrowingEnabled, true);

        uint256 snapshot = vm.snapshot();

        _e2eTestAsset(ctx.pool, wethConfig, usdgConfig);
        vm.revertTo(snapshot);

        _e2eTestAsset(ctx.pool, wethConfig, rlusdConfig);
        vm.revertTo(snapshot);
    }

}

contract SparkEthereum_20260827_SpellTests is SpellTests {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;

    constructor() {
        _spellId   = 20260827;
        _blockDate = 1787063010;
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkTreasury_foundationGrants() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      48_142_491.085806286854722044e18);
        assertEq(foundationBalanceBefore,      2_367_790.0222e18);
        assertEq(assetFoundationBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - SPARK_FOUNDATION_GRANT_AMOUNT - SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + SPARK_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
