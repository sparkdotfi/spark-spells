// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IAToken } from 'sparklend-v1-core/interfaces/IAToken.sol';

import { CCTPForwarder }         from 'xchain-helpers/forwarders/CCTPForwarder.sol';
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { Bridge }                from "xchain-helpers/testing/Bridge.sol";

import { Address }               from '../libraries/Address.sol';
import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SLLHelpers }            from '../libraries/SLLHelpers.sol';

import { SpellRunner } from "./SpellRunner.sol";

import { console } from "forge-std/console.sol";

struct SparkLiquidityLayerContext {
    address     controller;
    address     prevController;  // Only if upgrading
    IALMProxy   proxy;
    IRateLimits rateLimits;
    address     relayer;
    address     freezer;
}

struct RateLimitData {
    uint256 maxAmount;
    uint256 slope;
}

interface ICurvePoolLike is IERC20 {
    function add_liquidity(
        uint256[] memory amounts,
        uint256 minMintAmount,
        address receiver
    ) external;
    function balances(uint256 index) external view returns (uint256);
    function coins(uint256 index) external returns (address);
    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokensOut);
    function get_virtual_price() external view returns (uint256);
    function N_COINS() external view returns (uint256);
    function remove_liquidity(
        uint256 burnAmount,
        uint256[] memory minAmounts,
        address receiver
    ) external;
    function stored_rates() external view returns (uint256[] memory);
}

// TODO: expand on this on https://github.com/marsfoundation/spark-spells/issues/65
abstract contract SparkLiquidityLayerTests is SpellRunner {

    using DomainHelpers for Domain;

    address private constant ALM_RELAYER_BACKUP = 0x8Cc0Cb0cfB6B7e548cfd395B833c05C346534795;

    function setControllerUpgrade(ChainId chain, address prevController, address newController) internal {
        chainData[chain].prevController = prevController;
        chainData[chain].newController  = newController;
    }

    /**********************************************************************************************/
    /*** State loading helpers                                                                  ***/
    /**********************************************************************************************/

    function _getSparkLiquidityLayerContext(ChainId chain) internal view returns(SparkLiquidityLayerContext memory ctx) {
        if (chain == ChainIdUtils.Ethereum()) {
            ctx = SparkLiquidityLayerContext(
                Ethereum.ALM_CONTROLLER,
                address(0),
                IALMProxy(Ethereum.ALM_PROXY),
                IRateLimits(Ethereum.ALM_RATE_LIMITS),
                Ethereum.ALM_RELAYER,
                Ethereum.ALM_FREEZER
            );
        } else if (chain == ChainIdUtils.Base()) {
            ctx = SparkLiquidityLayerContext(
                Base.ALM_CONTROLLER,
                address(0),
                IALMProxy(Base.ALM_PROXY),
                IRateLimits(Base.ALM_RATE_LIMITS),
                Base.ALM_RELAYER,
                Base.ALM_FREEZER
            );
        } else if (chain == ChainIdUtils.ArbitrumOne()) {
            ctx = SparkLiquidityLayerContext(
                Arbitrum.ALM_CONTROLLER,
                address(0),
                IALMProxy(Arbitrum.ALM_PROXY),
                IRateLimits(Arbitrum.ALM_RATE_LIMITS),
                Arbitrum.ALM_RELAYER,
                Arbitrum.ALM_FREEZER
            );
        } else if (chain == ChainIdUtils.Optimism()) {
            ctx = SparkLiquidityLayerContext(
                Optimism.ALM_CONTROLLER,
                address(0),
                IALMProxy(Optimism.ALM_PROXY),
                IRateLimits(Optimism.ALM_RATE_LIMITS),
                Optimism.ALM_RELAYER,
                Optimism.ALM_FREEZER
            );
        } else if (chain == ChainIdUtils.Unichain()) {
            ctx = SparkLiquidityLayerContext(
                Unichain.ALM_CONTROLLER,
                address(0),
                IALMProxy(Unichain.ALM_PROXY),
                IRateLimits(Unichain.ALM_RATE_LIMITS),
                Unichain.ALM_RELAYER,
                Unichain.ALM_FREEZER
            );
        } else {
            revert("SLL/executing on unknown chain");
        }

        // Override if there is controller upgrades
        if (chainData[chain].prevController != address(0)) {
            ctx.prevController = chainData[chain].prevController;
            ctx.controller     = chainData[chain].newController;
        } else {
            ctx.prevController = ctx.controller;
        }
    }

    function _getSparkLiquidityLayerContext() internal view returns(SparkLiquidityLayerContext memory) {
        return _getSparkLiquidityLayerContext(ChainIdUtils.fromUint(block.chainid));
    }

    /**********************************************************************************************/
    /*** Assertion helpers                                                                      ***/
    /**********************************************************************************************/

    function _assertRateLimit(
       bytes32 key,
       RateLimitData memory data
    ) internal view {
        IRateLimits.RateLimitData memory rateLimit = _getSparkLiquidityLayerContext().rateLimits.getRateLimitData(key);
        _assertRateLimit(
            key,
            data.maxAmount,
            data.slope,
            rateLimit.lastAmount,
            rateLimit.lastUpdated
        );
    }

    function _assertRateLimit(
       bytes32 key,
       uint256 maxAmount,
       uint256 slope
    ) internal view {
        IRateLimits.RateLimitData memory rateLimit = _getSparkLiquidityLayerContext().rateLimits.getRateLimitData(key);
        _assertRateLimit(
            key,
            maxAmount,
            slope,
            rateLimit.lastAmount,
            rateLimit.lastUpdated
        );
    }

   function _assertUnlimitedRateLimit(
       bytes32 key
    ) internal view {
        IRateLimits.RateLimitData memory rateLimit = _getSparkLiquidityLayerContext().rateLimits.getRateLimitData(key);
        _assertRateLimit(
            key,
            type(uint256).max,
            0,
            rateLimit.lastAmount,
            rateLimit.lastUpdated
        );
    }

   function _assertRateLimit(
       bytes32 key,
       uint256 maxAmount,
       uint256 slope,
       uint256 lastAmount,
       uint256 lastUpdated
    ) internal view {
        IRateLimits.RateLimitData memory rateLimit = _getSparkLiquidityLayerContext().rateLimits.getRateLimitData(key);
        assertEq(rateLimit.maxAmount,   maxAmount);
        assertEq(rateLimit.slope,       slope);
        assertEq(rateLimit.lastAmount,  lastAmount);
        assertEq(rateLimit.lastUpdated, lastUpdated);

        if (maxAmount != 0 && maxAmount != type(uint256).max) {
            // Do some sanity checks on the slope
            // This is to catch things like forgetting to divide to a per-second time, etc

            // We assume it takes at least 1 hours to recharge to max
            uint256 oneHoursSlope = slope * 1 hours;
            assertLe(oneHoursSlope, maxAmount, "slope range sanity check failed");

            // It shouldn't take more than 30 days to recharge to max
            uint256 monthlySlope = slope * 30 days;
            assertGe(monthlySlope, maxAmount, "slope range sanity check failed");
        }
    }

    /**********************************************************************************************/
    /*** Standardized testing helpers                                                           ***/
    /**********************************************************************************************/

    function _testERC4626Onboarding(
        address vault,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        _testERC4626Onboarding(vault, expectedDepositAmount, depositMax, depositSlope, false);
    }

    function _testERC4626Onboarding(
        address vault,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope,
        bool    skipInitialCheck
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        bool unlimitedDeposit = depositMax == type(uint256).max;

        IERC20 asset = IERC20(IERC4626(vault).asset());

        // Note: ERC4626 signature is the same for mainnet and foreign
        deal(address(asset), address(ctx.proxy), expectedDepositAmount);
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_DEPOSIT(),
            vault
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_WITHDRAW(),
            vault
        );

        if (!skipInitialCheck) {
            _assertRateLimit(depositKey,  0, 0);
            _assertRateLimit(withdrawKey, 0, 0);

            vm.prank(ctx.relayer);
            vm.expectRevert("RateLimits/zero-maxAmount");
            MainnetController(ctx.prevController).depositERC4626(vault, expectedDepositAmount);

            executeAllPayloadsAndBridges();
        }

        _assertRateLimit(depositKey,  depositMax,        depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        if (!unlimitedDeposit) {
            vm.prank(ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            MainnetController(ctx.controller).depositERC4626(vault, depositMax + 1);
        }

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(asset.balanceOf(address(ctx.proxy)), expectedDepositAmount);

        assertEq(IERC4626(vault).convertToAssets(IERC4626(vault).balanceOf(address(ctx.proxy))), 0);

        vm.prank(ctx.relayer);
        uint256 shares = MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(asset.balanceOf(address(ctx.proxy)), 0);

        assertApproxEqAbs(IERC4626(vault).convertToAssets(IERC4626(vault).balanceOf(address(ctx.proxy))), expectedDepositAmount, 10);

        assertEq(IERC4626(vault).balanceOf(address(ctx.proxy)), shares);

        vm.prank(ctx.relayer);
        MainnetController(ctx.controller).withdrawERC4626(vault, expectedDepositAmount / 2);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(asset.balanceOf(address(ctx.proxy)), expectedDepositAmount / 2);

        assertApproxEqAbs(IERC4626(vault).convertToAssets(IERC4626(vault).balanceOf(address(ctx.proxy))), expectedDepositAmount / 2, 10);

        assertApproxEqAbs(IERC4626(vault).balanceOf(address(ctx.proxy)), shares / 2, 10);
    }

    function _testAaveOnboarding(
        address aToken,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bool unlimitedDeposit = depositMax == type(uint256).max;

        IERC20 underlying = IERC20(IAToken(aToken).UNDERLYING_ASSET_ADDRESS());

        MainnetController controller = MainnetController(ctx.controller);

        // Note: Aave signature is the same for mainnet and foreign
        deal(address(underlying), address(ctx.proxy), expectedDepositAmount);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  aToken);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), aToken);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        MainnetController(ctx.prevController).depositAave(aToken, expectedDepositAmount);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  depositMax,        depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        if (!unlimitedDeposit) {
            vm.prank(ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            controller.depositAave(aToken, depositMax + 1);
        }

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        uint256 aTokenBalance = underlying.balanceOf(aToken);

        assertApproxEqAbs(underlying.balanceOf(address(ctx.proxy)), expectedDepositAmount, 1);

        assertEq(IERC20(aToken).balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.depositAave(aToken, expectedDepositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertApproxEqAbs(underlying.balanceOf(aToken),             aTokenBalance + expectedDepositAmount, 1);
        assertApproxEqAbs(underlying.balanceOf(address(ctx.proxy)), 0,                                     1);

        assertApproxEqAbs(IERC20(aToken).balanceOf(address(ctx.proxy)), expectedDepositAmount, 1);

        vm.prank(ctx.relayer);
        controller.withdrawAave(aToken, expectedDepositAmount / 2);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertApproxEqAbs(underlying.balanceOf(address(ctx.proxy)), expectedDepositAmount / 2, 1);

        assertApproxEqAbs(IERC20(aToken).balanceOf(address(ctx.proxy)), expectedDepositAmount / 2, 2);
    }

    struct CurveOnboardingVars {
        ICurvePoolLike pool;
        SparkLiquidityLayerContext ctx;
        MainnetController prevController;
        MainnetController controller;
        uint256[] depositAmounts;
        uint256 minLPAmount;
        uint256[] withdrawAmounts;
        uint256[] rates;
        bytes32 swapKey;
        bytes32 depositKey;
        bytes32 withdrawKey;
        uint256 minAmountOut;
        uint256 lpBalance;
        uint256 smallerMaxSlippage;
    }

    function _testCurveOnboarding(
        address controller,
        address pool,
        uint256 expectedDepositAmountToken0,
        uint256 expectedSwapAmountToken0,
        uint256 maxSlippage,
        RateLimitData memory swapLimit,
        RateLimitData memory depositLimit,
        RateLimitData memory withdrawLimit
    ) internal {
        // Avoid stack too deep
        CurveOnboardingVars memory vars;
        vars.pool  = ICurvePoolLike(pool);
        vars.rates = ICurvePoolLike(pool).stored_rates();

        assertEq(vars.pool.N_COINS(), 2, "Curve pool must have 2 coins");

        vars.ctx        = _getSparkLiquidityLayerContext();
        vars.controller = MainnetController(controller);

        vars.depositAmounts = new uint256[](2);
        vars.depositAmounts[0] = expectedDepositAmountToken0;
        // Derive the second amount to be balanced with the first
        vars.depositAmounts[1] = expectedDepositAmountToken0 * vars.rates[0] / vars.rates[1];

        vars.minLPAmount = (
            vars.depositAmounts[0] * vars.rates[0] +
            vars.depositAmounts[1] * vars.rates[1]
        ) * maxSlippage / 1e18 / vars.pool.get_virtual_price();

        vars.swapKey     = RateLimitHelpers.makeAssetKey(vars.controller.LIMIT_CURVE_SWAP(),     pool);
        vars.depositKey  = RateLimitHelpers.makeAssetKey(vars.controller.LIMIT_CURVE_DEPOSIT(),  pool);
        vars.withdrawKey = RateLimitHelpers.makeAssetKey(vars.controller.LIMIT_CURVE_WITHDRAW(), pool);

        _assertRateLimit(vars.swapKey,     0, 0);
        _assertRateLimit(vars.depositKey,  0, 0);
        _assertRateLimit(vars.withdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(vars.swapKey,     swapLimit);
        _assertRateLimit(vars.depositKey,  depositLimit);
        _assertRateLimit(vars.withdrawKey, withdrawLimit);

        assertEq(vars.controller.maxSlippages(pool), maxSlippage);

        if (depositLimit.maxAmount != 0) {
            // Deposit is enabled
            assertGt(vars.depositAmounts[0], 0);
            assertGt(vars.depositAmounts[1], 0);

            deal(vars.pool.coins(0), address(vars.ctx.proxy), vars.depositAmounts[0]);
            deal(vars.pool.coins(1), address(vars.ctx.proxy), vars.depositAmounts[1]);

            assertEq(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), vars.depositAmounts[0]);
            assertEq(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), vars.depositAmounts[1]);

            vm.prank(vars.ctx.relayer);
            vars.controller.addLiquidityCurve(
                pool,
                vars.depositAmounts,
                vars.minLPAmount
            );

            assertEq(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), 0);
            assertEq(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), 0);

            vars.lpBalance = vars.pool.balanceOf(address(vars.ctx.proxy));
            assertGe(vars.lpBalance, vars.minLPAmount);

            // Withdraw should also be enabled if deposit is enabled
            assertGt(withdrawLimit.maxAmount, 0);

            uint256 snapshot = vm.snapshot();

            // Go slightly above maxSlippage due to rounding
            vars.withdrawAmounts = new uint256[](2);
            vars.withdrawAmounts[0] = vars.lpBalance * vars.pool.balances(0) * (maxSlippage + 0.001e18) / vars.pool.get_virtual_price() / vars.pool.totalSupply();
            vars.withdrawAmounts[1] = vars.lpBalance * vars.pool.balances(1) * (maxSlippage + 0.001e18) / vars.pool.get_virtual_price() / vars.pool.totalSupply();

            vm.prank(vars.ctx.relayer);
            vars.controller.removeLiquidityCurve(
                pool,
                vars.lpBalance,
                vars.withdrawAmounts
            );

            assertEq(vars.pool.balanceOf(address(vars.ctx.proxy)), 0);
            assertGe(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), vars.withdrawAmounts[0]);
            assertGe(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), vars.withdrawAmounts[1]);

            // Ensure that value withdrawn is greater than the value deposited * maxSlippage (18 decimal precision)
            assertGe(
                (vars.withdrawAmounts[0] * vars.rates[0] + vars.withdrawAmounts[1] * vars.rates[1]) / 1e18,
                (vars.depositAmounts[0] * vars.rates[0] + vars.depositAmounts[1] * vars.rates[1]) * maxSlippage / 1e36
            );

            vm.revertTo(snapshot);  // To allow swapping through higher liquidity below
        } else {
            // Deposit is disabled
            assertEq(vars.depositAmounts[0], 0);
            assertEq(vars.depositAmounts[1], 0);

            // Withdraw should also be disabled if deposit is disabled
            assertEq(withdrawLimit.maxAmount, 0);
        }

        deal(vars.pool.coins(0), address(vars.ctx.proxy), expectedSwapAmountToken0);
        vars.minAmountOut = expectedSwapAmountToken0 * vars.rates[0] * maxSlippage / vars.rates[1] / 1e18;

        assertEq(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), expectedSwapAmountToken0);
        assertEq(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), 0);

        vm.prank(vars.ctx.relayer);
        uint256 amountOut = vars.controller.swapCurve(
            pool,
            0,
            1,
            expectedSwapAmountToken0,
            vars.minAmountOut
        );

        assertEq(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), 0);
        assertEq(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), amountOut);
        assertGe(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), vars.minAmountOut);

        // Overwrite minAmountOut based on returned amount to swap back to token0
        vars.minAmountOut = amountOut * vars.rates[1] * maxSlippage / vars.rates[0] / 1e18;

        vm.prank(vars.ctx.relayer);
        amountOut = vars.controller.swapCurve(
            pool,
            1,
            0,
            amountOut,
            vars.minAmountOut
        );

        assertEq(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), amountOut);
        assertGe(IERC20(vars.pool.coins(0)).balanceOf(address(vars.ctx.proxy)), vars.minAmountOut);
        assertEq(IERC20(vars.pool.coins(1)).balanceOf(address(vars.ctx.proxy)), 0);

        // Sanity check on maxSlippage of 15bps
        assertGe(maxSlippage, 0.998e18,  "maxSlippage too low");
        assertLe(maxSlippage, 1e18,      "maxSlippage too high");
    }

    function _testControllerUpgrade(address oldController, address newController) internal {
        ChainId currentChain = ChainIdUtils.fromUint(block.chainid);

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // Note the functions used are interchangable with mainnet and foreign controllers
        MainnetController controller = MainnetController(newController);

        bytes32 CONTROLLER = ctx.proxy.CONTROLLER();
        bytes32 RELAYER    = controller.RELAYER();
        bytes32 FREEZER    = controller.FREEZER();

        assertEq(ctx.proxy.hasRole(CONTROLLER, oldController), true);
        assertEq(ctx.proxy.hasRole(CONTROLLER, newController), false);

        assertEq(ctx.rateLimits.hasRole(CONTROLLER, oldController), true);
        assertEq(ctx.rateLimits.hasRole(CONTROLLER, newController), false);

        assertEq(controller.hasRole(RELAYER, ctx.relayer),        false);
        assertEq(controller.hasRole(RELAYER, ALM_RELAYER_BACKUP), false);
        assertEq(controller.hasRole(FREEZER, ctx.freezer),        false);

        if (currentChain == ChainIdUtils.Ethereum()) {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(address(0)));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0);
        } else {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(address(0)));
        }

        executeAllPayloadsAndBridges();

        assertEq(ctx.proxy.hasRole(CONTROLLER, oldController), false);
        assertEq(ctx.proxy.hasRole(CONTROLLER, newController), true);

        assertEq(ctx.rateLimits.hasRole(CONTROLLER, oldController), false);
        assertEq(ctx.rateLimits.hasRole(CONTROLLER, newController), true);

        assertEq(controller.hasRole(RELAYER, ctx.relayer),        true);
        assertEq(controller.hasRole(RELAYER, ALM_RELAYER_BACKUP), true);
        assertEq(controller.hasRole(FREEZER, ctx.freezer),        true);

        if (currentChain == ChainIdUtils.Ethereum()) {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(Base.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), MainnetController(oldController).maxSlippages(Ethereum.CURVE_SUSDSUSDT));
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), MainnetController(oldController).maxSlippages(Ethereum.CURVE_PYUSDUSDC));
        } else {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY));
        }
    }

    function _testE2ESLLCrossChainForDomain(
        ChainId           domainId,
        MainnetController mainnetController,
        ForeignController foreignController
    )
        internal onChain(ChainIdUtils.Ethereum())
    {
        IERC20  domainUsdc;
        address domainPsm3;
        uint32  domainCctpId;
        Bridge storage bridge = chainData[domainId].bridges[1];

        if (domainId == ChainIdUtils.ArbitrumOne()) {
            domainUsdc   = IERC20(Arbitrum.USDC);
            domainPsm3   = Arbitrum.PSM3;
            domainCctpId = CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE;
        } else if (domainId == ChainIdUtils.Base()) {
            domainUsdc   = IERC20(Base.USDC);
            domainPsm3   = Base.PSM3;
            domainCctpId = CCTPForwarder.DOMAIN_ID_CIRCLE_BASE;
        } else {
            revert("SLL/unknown domain");
        }

        IERC20 usdc = IERC20(Ethereum.USDC);

        uint256 mainnetUsdcProxyBalance = usdc.balanceOf(Ethereum.ALM_PROXY);

        // --- Step 1: Mint and bridge 10m USDC to Base ---

        uint256 usdcAmount = 10_000_000e6;

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, domainCctpId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);

        chainData[domainId].domain.selectFork();

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        address domainAlmProxy = address(ctx.proxy);

        uint256 domainUsdcProxyBalance = domainUsdc.balanceOf(domainAlmProxy);
        uint256 domainUsdcPsmBalance   = domainUsdc.balanceOf(domainPsm3);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);

        // FIXME: this is a workaround for the storage/fork issue (https://github.com/foundry-rs/foundry/issues/10296), switch back to _relayMessageOverBridges() when fixed
        //_relayMessageOverBridges();
        CCTPBridgeTesting.relayMessagesToDestination(bridge, true);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance);

        // --- Step 3: Deposit USDC into PSM3 ---

        vm.prank(ctx.relayer);
        foreignController.depositPSM(address(domainUsdc), usdcAmount);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance + usdcAmount);

        // --- Step 4: Withdraw all assets from PSM3 ---

        vm.prank(ctx.relayer);
        foreignController.withdrawPSM(address(domainUsdc), usdcAmount);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance);

        // --- Step 5: Bridge USDC back to mainnet ---

        skip(1 days);  // Skip 1 day to allow for the rate limit to be refilled

        vm.prank(ctx.relayer);
        foreignController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);

        // FIXME: this is a workaround for the storage/fork issue (https://github.com/foundry-rs/foundry/issues/10296), switch back to _relayMessageOverBridges() when fixed
        //_relayMessageOverBridges();
        CCTPBridgeTesting.relayMessagesToSource(bridge, true);

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance + usdcAmount);

        // --- Step 6: Swap USDC to USDS and burn ---

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);
    }

    /**********************************************************************************************/
    /*** E2E tests to be run on every spell                                                     ***/
    /**********************************************************************************************/

    function test_BASE_E2E_sparkLiquidityLayerCrossChainSetup() public {
        SparkLiquidityLayerContext memory ctxMainnet = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxBase    = _getSparkLiquidityLayerContext(ChainIdUtils.Base());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxBase.prevController)
        );

        executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxBase.controller)
        );
    }

    function test_ARBITRUM_E2E_sparkLiquidityLayerCrossChainSetup() public {
        SparkLiquidityLayerContext memory ctxMainnet  = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxArbitrum = _getSparkLiquidityLayerContext(ChainIdUtils.ArbitrumOne());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxArbitrum.prevController)
        );

        executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxArbitrum.controller)
        );
    }

}
