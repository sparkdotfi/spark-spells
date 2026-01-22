// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Gnosis }    from "spark-address-registry/Gnosis.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";
import { TickMath } from "spark-alm-controller/lib/uniswap-v4-core/src/libraries/TickMath.sol";
import { PoolId }   from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolId.sol";

import { PositionInfo }     from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { LiquidityAmounts } from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/LiquidityAmounts.sol";
import { Actions }          from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { IV4Router }        from "spark-alm-controller/lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { UserConfiguration }    from "sparklend-v1-core/protocol/libraries/configuration/UserConfiguration.sol";

import { AaveOracle }        from "sparklend-v1-core/misc/AaveOracle.sol";
import { IPool }             from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator } from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { DataTypes }         from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";
import { DealUtils }    from "src/libraries/DealUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ISparkVaultV2Like,
    ISyrupLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IPositionManagerLike {

    function transferFrom(address from, address to, uint256 id) external;

    function getPoolAndPositionInfo(uint256 tokenId)
        external view returns (PoolKey memory poolKey, PositionInfo info);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function nextTokenId() external view returns (uint256 nextTokenId);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory poolKeys);

}

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    function allowance(address user, address token, address spender)
        external view returns (uint160 amount, uint48 expiration, uint48 nonce);

}

interface IUniversalRouterLike {

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;

}

interface IMinimalERC20ApproveLike {

    function approve(address spender, uint256 amount) external;

}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

contract SparkEthereum_20260129_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xc9ff605003A1b389980f650e1aEFA1ef25C8eE32;

    uint256 internal constant _V4_SWAP = 0x10;

    address internal constant _STATE_VIEW = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;
    address internal constant _V4_QUOTER  = 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1769005086;  // 2026-01-21T14:18:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;

        // Maple onboarding process
        ISyrupLike syrup = ISyrupLike(Ethereum.SYRUP_USDT);

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

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

        assertEq(usdtVault.depositCap(), 500_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdtVault.depositCap(), 2_000_000_000e6);

        _testSparkVaultDepositCapBoundary({
            vault:              usdtVault,
            depositCap:         2_000_000_000e6,
            expectedMaxDeposit: 1_840_172_664.849384e6
        });
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_controllerUpgradeEvents() public onChain(ChainIdUtils.Ethereum()) {
        _testMainnetControllerUpgradeEvents({
            _oldController: Ethereum.ALM_CONTROLLER,
            _newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4PYUSDUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        bytes32 depositPoolId  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  PYUSD_USDS_POOL_ID));
        bytes32 withdrawPoolId = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), PYUSD_USDS_POOL_ID));
        bytes32 swapPoolId     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     PYUSD_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(PYUSD_USDS_POOL_ID)))), 0);

        _assertRateLimit(depositPoolId,  0, 0);
        _assertRateLimit(withdrawPoolId, 0, 0);
        _assertRateLimit(swapPoolId,     0, 0);

        (int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing) = controller.uniswapV4TickLimits(PYUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(PYUSD_USDS_POOL_ID)))), 0.999e18);

        _assertRateLimit(depositPoolId,  10_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawPoolId, 50_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapPoolId,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        (_tickLowerMin, _tickUpperMax, _maxTickSpacing) = controller.uniswapV4TickLimits(PYUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   276_314);
        assertEq(_tickUpperMax,   276_334);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4LimitOrder(PYUSD_USDS_POOL_ID);
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4USDTUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        bytes32 depositPoolId  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  USDT_USDS_POOL_ID));
        bytes32 withdrawPoolId = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), USDT_USDS_POOL_ID));
        bytes32 swapPoolId     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     USDT_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(USDT_USDS_POOL_ID)))), 0);

        _assertRateLimit(depositPoolId,  0, 0);
        _assertRateLimit(withdrawPoolId, 0, 0);
        _assertRateLimit(swapPoolId,     0, 0);

        (int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing) = controller.uniswapV4TickLimits(USDT_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(USDT_USDS_POOL_ID)))), 0.998e18);

        _assertRateLimit(depositPoolId,  5_000_000e18, 50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawPoolId, 50_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapPoolId,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        (_tickLowerMin, _tickUpperMax, _maxTickSpacing) = controller.uniswapV4TickLimits(USDT_USDS_POOL_ID);

        assertEq(_tickLowerMin,   276_304);
        assertEq(_tickUpperMax,   276_344);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4LimitOrder(USDT_USDS_POOL_ID);
    }

    // Helper functions

    function _testUniswapV4LimitOrder(bytes32 poolId) internal {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        ( int24 tickLowerMin, int24 tickUpperMax, ) = controller.uniswapV4TickLimits(poolId);

        int24 currentTick = _getCurrentTick(poolId);

        bool placeLimitOrderSellToken0 = tickUpperMax >= currentTick + 2;
        bool placeLimitOrderSellToken1 = tickLowerMin <= currentTick - 2;

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        if (placeLimitOrderSellToken0) {
            ( uint256 tokenId, uint256 depositedAmount0 ) = _addToken0Liquidity(poolId);

            _performSwapToTakeToken0(poolId, depositedAmount0);

            ( , uint256 withdrawnAmount1 ) = _removeLiquidity(poolId, tokenId);

            assertApproxEqRel(
                _toNormalizedAmount(poolKey.currency0, depositedAmount0),
                _toNormalizedAmount(poolKey.currency1, withdrawnAmount1),
                0.001e18
            );
        }

        if (placeLimitOrderSellToken0 && placeLimitOrderSellToken1) {
            IRateLimits.RateLimitData memory depositRateLimit = controller.rateLimits().getRateLimitData(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(), poolId))
            );

            uint256 maxDepositTime = depositRateLimit.maxAmount / depositRateLimit.slope;

            IRateLimits.RateLimitData memory withdrawRateLimit = controller.rateLimits().getRateLimitData(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), poolId))
            );

            uint256 maxWithdrawTime = withdrawRateLimit.maxAmount / withdrawRateLimit.slope;

            vm.warp(vm.getBlockTimestamp() + (maxDepositTime > maxWithdrawTime ? maxDepositTime : maxWithdrawTime));
        }

        if (placeLimitOrderSellToken1) {
            ( uint256 tokenId, uint256 depositedAmount1 ) = _addToken1Liquidity(poolId);

            _performSwapToTakeToken1(poolId, depositedAmount1);

            ( uint256 withdrawnAmount0, ) = _removeLiquidity(poolId, tokenId);

            assertApproxEqRel(
                _toNormalizedAmount(poolKey.currency1, depositedAmount1),
                _toNormalizedAmount(poolKey.currency0, withdrawnAmount0),
                0.001e18
            );
        }
    }

    function _getCurrentTick(bytes32 poolId) internal view returns (int24 tick) {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(poolId));

        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function _addToken0Liquidity(bytes32 poolId) internal returns (uint256 tokenId, uint256 amount0) {
        // Add liquidity to the pool with tickLower = currentTick + 1 and tickUpper = currentTick + 2, such that all the
        // funds added are token0, acting as a limit order.
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        uint256 depositRateLimit = controller.rateLimits().getCurrentRateLimit(
            keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(), poolId))
        );

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        amount0 = _fromNormalizedAmount(poolKey.currency0, depositRateLimit);

        deal(Currency.unwrap(poolKey.currency0), address(ctx.proxy), amount0);

        int24 currentTick = _getCurrentTick(poolId);

        uint256 balanceBefore = _getBalanceOf(poolKey.currency0, address(ctx.proxy));

        vm.prank(ctx.relayer);
        controller.mintPositionUniswapV4({
            poolId     : poolId,
            tickLower  : currentTick + 1,
            tickUpper  : currentTick + 2,
            liquidity  : _getLiquidityForAmount0(currentTick + 1, currentTick + 2, amount0),
            amount0Max : amount0,
            amount1Max : 0
        });

        tokenId = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).nextTokenId() - 1;

        uint256 balanceAfter = _getBalanceOf(poolKey.currency0, address(ctx.proxy));

        amount0 = balanceBefore - balanceAfter;
    }

    function _addToken1Liquidity(bytes32 poolId) internal returns (uint256 tokenId, uint256 amount1) {
        // Add liquidity to the pool with tickLower = currentTick - 2 and tickUpper = currentTick - 1, such that all the
        // funds added are token1, acting as a limit order.
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        uint256 depositRateLimit = controller.rateLimits().getCurrentRateLimit(
            keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(), poolId))
        );

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        amount1 = _fromNormalizedAmount(poolKey.currency1, depositRateLimit);

        deal(Currency.unwrap(poolKey.currency1), address(ctx.proxy), amount1);

        int24 currentTick = _getCurrentTick(poolId);

        uint256 balanceBefore = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        vm.prank(ctx.relayer);
        controller.mintPositionUniswapV4({
            poolId     : poolId,
            tickLower  : currentTick - 2,
            tickUpper  : currentTick - 1,
            liquidity  : _getLiquidityForAmount1(currentTick - 2, currentTick - 1, amount1),
            amount0Max : 0,
            amount1Max : amount1
        });

        tokenId = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).nextTokenId() - 1;

        uint256 balanceAfter = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        amount1 = balanceBefore - balanceAfter;
    }

    function _performSwapToTakeToken0(bytes32 poolId, uint256 amount) internal {
        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));
        _externalSwap(poolId, poolKey.currency0, uint128(amount));
    }

    function _performSwapToTakeToken1(bytes32 poolId, uint256 amount) internal {
        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));
        _externalSwap(poolId, poolKey.currency1, uint128(amount));
    }

    function _externalSwap(bytes32 poolId, Currency currencyOut, uint128 amountOut) internal {
        address account = makeAddr("alice");

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        Currency currencyIn      = currencyOut == poolKey.currency0 ? poolKey.currency1 : poolKey.currency0;
        uint256  amountInMaximum = _fromNormalizedAmount(currencyIn, 2 * _toNormalizedAmount(currencyOut, amountOut));

        deal(Currency.unwrap(currencyIn), account, amountInMaximum);

        bytes memory commands = abi.encodePacked(uint8(_V4_SWAP));

        bytes[] memory inputs = new bytes[](1);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey          : poolKey,
                zeroForOne       : currencyIn == poolKey.currency0,
                amountOut        : amountOut,
                amountInMaximum  : uint128(amountInMaximum),
                hookData         : bytes("")
            })
        );

        address tokenIn = Currency.unwrap(currencyIn);

        params[1] = abi.encode(tokenIn, amountInMaximum);
        params[2] = abi.encode(Currency.unwrap(currencyOut), amountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        vm.startPrank(account);
        IMinimalERC20ApproveLike(tokenIn).approve(UniswapV4Lib._PERMIT2, amountInMaximum);
        IPermit2Like(UniswapV4Lib._PERMIT2).approve(tokenIn, UniswapV4Lib._ROUTER, uint160(amountInMaximum), uint48(block.timestamp));
        IUniversalRouterLike(UniswapV4Lib._ROUTER).execute(commands, inputs, block.timestamp);
        vm.stopPrank();
    }

    function _removeLiquidity(bytes32 poolId, uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        uint128 liquidity = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).getPositionLiquidity(tokenId);

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        uint256 balance0Before = _getBalanceOf(poolKey.currency0, address(ctx.proxy));
        uint256 balance1Before = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        vm.prank(ctx.relayer);
        MainnetController(ETHEREUM_NEW_ALM_CONTROLLER).decreaseLiquidityUniswapV4({
            poolId            : poolId,
            tokenId           : tokenId,
            liquidityDecrease : liquidity,
            amount0Min        : 0,
            amount1Min        : 0
        });

        uint256 balance0After = _getBalanceOf(poolKey.currency0, address(ctx.proxy));
        uint256 balance1After = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        amount0 = balance0After - balance0Before;
        amount1 = balance1After - balance1Before;
    }

    function _toNormalizedAmount(Currency currency, uint256 amount)
        internal view returns (uint256 normalizedAmount)
    {
        return amount * 1e18 / (10 ** IERC20Metadata(Currency.unwrap(currency)).decimals());
    }

    function _fromNormalizedAmount(Currency currency, uint256 normalizedAmount) internal view returns (uint256 amount) {
        return normalizedAmount * (10 ** IERC20Metadata(Currency.unwrap(currency)).decimals()) / 1e18;
    }

    function _getLiquidityForAmount0(int24 tickLower, int24 tickUpper, uint256 amount0) internal view returns (uint128 amount) {
        return LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), amount0);
    }

    function _getLiquidityForAmount1(int24 tickLower, int24 tickUpper, uint256 amount1) internal view returns (uint128 amount) {
        return LiquidityAmounts.getLiquidityForAmount1(TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), amount1);
    }

    function _getBalanceOf(Currency currency, address  account)
        internal view returns (uint256 balance)
    {
        return IERC20(Currency.unwrap(currency)).balanceOf(account);
    }
}

contract SparkEthereum_20260129_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using SafeERC20 for IERC20;

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xc9ff605003A1b389980f650e1aEFA1ef25C8eE32;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1769005086;  // 2026-01-21T14:18:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;
    }

    function test_GNOSIS_sparkLend_deprecateMarket() external onChain(ChainIdUtils.Gnosis()) {
        address[] memory reserves = IPool(Gnosis.POOL).getReservesList();

        assertGt(reserves.length, 0);

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveConfigurationMap memory config = IPool(Gnosis.POOL).getConfiguration(reserves[i]);

            assertEq(config.getActive(), true);
            assertEq(config.getPaused(), false);
            assertEq(config.getFrozen(), false);

            assertLt(config.getReserveFactor(), 50_00);
        }

        _executeAllPayloadsAndBridges();

        uint256 snapshot = vm.snapshotState();

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveConfigurationMap memory config = IPool(Gnosis.POOL).getConfiguration(reserves[i]);

            assertEq(config.getActive(), true);
            assertEq(config.getPaused(), false);
            assertEq(config.getFrozen(), true);

            assertEq(config.getReserveFactor(), 50_00);

            _testUserActionsOnFrozenReserve(reserves[i], Gnosis.USDC);

            vm.revertToState(snapshot);
        }
    }

    function test_ETHEREUM_sparkLend_deprecateTBTC() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.TBTC);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 20_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.TBTC);

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 99_00);

        _testUserActionsOnFrozenReserve(Ethereum.TBTC, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateEZETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.EZETH);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.EZETH);

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 15_00);

        _testUserActionsOnFrozenReserve(Ethereum.EZETH, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateRSETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.RSETH);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.RSETH);

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 15_00);

        _testUserActionsOnFrozenReserve(Ethereum.RSETH, Ethereum.USDC);
    }

    function _testUserActionsOnFrozenReserve(address reserveAsset, address debtAsset) internal {
        address testUser      = makeAddr("testUser");
        uint256 reserveAmount = 100 * 10 ** IERC20Metadata(reserveAsset).decimals();
        uint256 debtAmount    = 10 * 10 ** IERC20Metadata(debtAsset).decimals();

        IPool pool = IPool(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.POOL : SparkLend.POOL);

        // --- Step 1: Check reserve freeze conditions (can't supply/borrow, can withdraw/repay)

        deal(reserveAsset, testUser, reserveAmount);

        vm.startPrank(testUser);

        IERC20(reserveAsset).approve(address(pool), type(uint256).max);

        // User can't supply.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.supply(reserveAsset, reserveAmount, testUser, 0);

        // User can't borrow.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.borrow(reserveAsset, debtAmount, 2, 0, testUser);

        // User can repay when conditions are correct.
        vm.expectRevert(bytes("39"));  // NO_DEBT_OF_SELECTED_TYPE (past RESERVE_FROZEN error, able to repay if there is debt)
        pool.repay(reserveAsset, debtAmount, 2, testUser);

        // User can withdraw collateral when conditions are correct.
        vm.expectRevert(bytes("32"));  // NOT_ENOUGH_AVAILABLE_USER_BALANCE (past RESERVE_FROZEN error, able to withdraw if there is collateral)
        pool.withdraw(reserveAsset, reserveAmount, testUser);

        vm.stopPrank();

        // --- Step 2: Check collateral behaviour when borrowing another borrowable asset
        //             (should be able to withdraw collateral, repay borrowAsset, and get liquidated)

        // If the reserve is not active or has a debt ceiling, skip the test as user collateral enabled will be false.
        if (pool.getReserveData(reserveAsset).configuration.getLtv() == 0) return;
        if (pool.getReserveData(reserveAsset).configuration.getDebtCeiling() > 0) return;

        // Increase the supply cap and set up a new collateral position

        IPoolConfigurator poolConfigurator =
            IPoolConfigurator(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.POOL_CONFIGURATOR : SparkLend.POOL_CONFIGURATOR);

        uint256 currentSupplyCap = pool.getConfiguration(reserveAsset).getSupplyCap();

        vm.prank(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.AMB_EXECUTOR : Ethereum.SPARK_PROXY);
        poolConfigurator.setSupplyCap(reserveAsset, currentSupplyCap + 1_000_000);

        _setupUserSparkLendPosition(reserveAsset, debtAsset, testUser, reserveAmount, debtAmount);

        // User can repay the debt in the borrowAsset

        deal(debtAsset, testUser, debtAmount);

        vm.startPrank(testUser);

        IERC20(debtAsset).safeIncreaseAllowance(address(pool), type(uint256).max);

        pool.repay(debtAsset, debtAmount, 2, testUser);

        vm.stopPrank();

        // User can repay the debt in reserveAsset

        if (pool.getConfiguration(reserveAsset).getBorrowingEnabled()) {
            _setupUserSparkLendPosition(reserveAsset, reserveAsset, testUser, reserveAmount, debtAmount);

            vm.startPrank(testUser);

            deal(reserveAsset, testUser, debtAmount);

            IERC20(reserveAsset).safeIncreaseAllowance(address(pool), type(uint256).max);

            pool.repay(reserveAsset, debtAmount, 2, testUser);

            vm.stopPrank();
        }

        // User can withdraw the collateral

        vm.startPrank(testUser);

        pool.withdraw(reserveAsset, 1 * 10 ** IERC20Metadata(reserveAsset).decimals(), testUser);

        vm.stopPrank();

        // User can get liquidated

        _setupUserSparkLendPosition(reserveAsset, debtAsset, testUser, reserveAmount, debtAmount);

        address mockOracle = address(new MockAggregator(1));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);

        assets[0]  = reserveAsset;
        sources[0] = mockOracle;

        if (block.chainid == ChainIdUtils.Gnosis()) {
            vm.prank(Gnosis.AMB_EXECUTOR);
            AaveOracle(Gnosis.AAVE_ORACLE).setAssetSources(assets, sources);
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            AaveOracle(SparkLend.AAVE_ORACLE).setAssetSources(assets, sources);
        }

        deal(debtAsset,    testUser, debtAmount);
        deal(reserveAsset, testUser, reserveAmount);

        // User can be liquidated.
        vm.prank(testUser);
        pool.liquidationCall(reserveAsset, debtAsset, testUser, debtAmount, false);
    }

    function _setupUserSparkLendPosition(
        address collateralAsset,
        address debtAsset,
        address testUser,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal {
        IPool pool = IPool(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.POOL : SparkLend.POOL);

        deal(collateralAsset, testUser, collateralAmount);

        vm.prank(testUser);
        IERC20(collateralAsset).approve(address(pool), type(uint256).max);

        // Set Reserve frozen to false.
        if (block.chainid == ChainIdUtils.Gnosis()) {
            vm.startPrank(Gnosis.AMB_EXECUTOR);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, false);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(debtAsset,       false);
            vm.stopPrank();
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, false);
        }

        vm.startPrank(testUser);

        pool.supply(collateralAsset, collateralAmount, testUser, 0);
        pool.borrow(debtAsset,       debtAmount,       2,          0, testUser);

        vm.stopPrank();

        // Set Reserve frozen to true.
        if (block.chainid == ChainIdUtils.Gnosis()) {
            vm.startPrank(Gnosis.AMB_EXECUTOR);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, true);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(debtAsset,       true);
            vm.stopPrank();
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, true);
        }
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token != Gnosis.EURE) {
            super.deal(token, to, amount);
            return;
        }
        DealUtils.patchedDeal(token, to, amount);
    }

}

contract SparkEthereum_20260129_SpellTests is SpellTests {

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xc9ff605003A1b389980f650e1aEFA1ef25C8eE32;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1769005086;  // 2026-01-21T14:18:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;
    }

    function test_ETHEREUM_sparkTreasury_foundationGrant() external onChain(ChainIdUtils.Ethereum()) {
        uint256 proxyBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);

        assertEq(proxyBalanceBefore,      30_389_488.445801365846236778e18);
        assertEq(foundationBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               proxyBalanceBefore - FOUNDATION_GRANT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
    }

}
