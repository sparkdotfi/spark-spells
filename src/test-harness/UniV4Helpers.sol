// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";
import { TickMath } from "spark-alm-controller/lib/uniswap-v4-core/src/libraries/TickMath.sol";
import { PoolId }   from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolId.sol";

import { LiquidityAmounts } from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/LiquidityAmounts.sol";
import { Actions }          from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { IV4Router }        from "spark-alm-controller/lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { IStateViewLike, IPositionManagerLike } from "../interfaces/Interfaces.sol";

import { SparkLiquidityLayerTests } from "./SparkLiquidityLayerTests.sol";

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

abstract contract UniV4Helpers is SparkLiquidityLayerTests {

    uint256 internal constant _V4_SWAP = 0x10;

    address internal constant _STATE_VIEW = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    function _testUniswapV4LimitOrder(bytes32 poolId) internal {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

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

        // If both conditions are true the rate limits need to be replenished in order to do the second swap.
        if (placeLimitOrderSellToken0 && placeLimitOrderSellToken1) {
            IRateLimits.RateLimitData memory depositRateLimit = controller.rateLimits().getRateLimitData(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(), poolId))
            );

            uint256 maxDepositTime = depositRateLimit.maxAmount / depositRateLimit.slope;

            IRateLimits.RateLimitData memory withdrawRateLimit = controller.rateLimits().getRateLimitData(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), poolId))
            );

            uint256 maxWithdrawTime = withdrawRateLimit.slope == 0
                ? 0
                : withdrawRateLimit.maxAmount / withdrawRateLimit.slope;

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

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

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
            amount0Max : uint128(amount0),
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

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

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
            amount1Max : uint128(amount1)
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
                poolKey         : poolKey,
                zeroForOne      : currencyIn == poolKey.currency0,
                amountOut       : amountOut,
                amountInMaximum : uint128(amountInMaximum),
                hookData        : bytes("")
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
        MainnetController(Ethereum.ALM_CONTROLLER).decreaseLiquidityUniswapV4({
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
