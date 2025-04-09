// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IAToken } from 'sparklend-v1-core/contracts/interfaces/IAToken.sol';

import { CCTPForwarder }         from 'xchain-helpers/forwarders/CCTPForwarder.sol';
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import { Address }               from '../libraries/Address.sol';
import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SLLHelpers }            from '../libraries/SLLHelpers.sol';

import { SpellRunner } from "./SpellRunner.sol";

struct SparkLiquidityLayerContext {
    address     controller;
    address     prevController;  // Only if upgrading
    IALMProxy   proxy;
    IRateLimits rateLimits;
    address     relayer;
    address     freezer;
}

interface ICurvePoolLike {
    function coins(uint256 index) external view returns (address);
}

// TODO: expand on this on https://github.com/marsfoundation/spark-spells/issues/65
abstract contract SparkLiquidityLayerTests is SpellRunner {

    using DomainHelpers for Domain;

    address private constant ALM_RELAYER_BACKUP = 0x8Cc0Cb0cfB6B7e548cfd395B833c05C346534795;

    function setControllerUpgrade(ChainId chain, address prevController, address newController) internal {
        chainSpellMetadata[chain].prevController = prevController;
        chainSpellMetadata[chain].newController  = newController;
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
        } else {
            revert("SLL/executing on unknown chain");
        }

        // Override if there is controller upgrades
        if (chainSpellMetadata[chain].prevController != address(0)) {
            ctx.prevController = chainSpellMetadata[chain].prevController;
            ctx.controller     = chainSpellMetadata[chain].newController;
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

            // We assume it takes at least 1 day to recharge to max
            uint256 dailySlope = slope * 1 days;
            assertLe(dailySlope, maxAmount, "slope range sanity check failed");

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
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        bool unlimitedDeposit = depositMax == type(uint256).max;

        // Note: ERC4626 signature is the same for mainnet and foreign
        deal(IERC4626(vault).asset(), address(ctx.proxy), expectedDepositAmount);
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_DEPOSIT(),
            vault
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_WITHDRAW(),
            vault
        );

        _assertRateLimit(depositKey, 0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, depositMax, depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        if (!unlimitedDeposit) {
            vm.prank(ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            MainnetController(ctx.controller).depositERC4626(vault, depositMax + 1);
        }

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(ctx.relayer);
        MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(ctx.relayer);
        MainnetController(ctx.controller).withdrawERC4626(vault, expectedDepositAmount / 2);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
    }

    // TODO: Add balance assertions to all helper functions
    function _testAaveOnboarding(
        address aToken,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bool unlimitedDeposit = depositMax == type(uint256).max;

        // Note: Aave signature is the same for mainnet and foreign
        deal(IAToken(aToken).UNDERLYING_ASSET_ADDRESS(), address(ctx.proxy), expectedDepositAmount);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  aToken);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), aToken);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.depositAave(aToken, expectedDepositAmount);

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

        vm.prank(ctx.relayer);
        controller.depositAave(aToken, expectedDepositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(ctx.relayer);
        controller.withdrawAave(aToken, expectedDepositAmount / 2);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
    }

    function _testCurveOnboarding(
        address pool,
        uint256 expectedDepositAmountToken1,
        uint256 expectedDepositAmountToken2,
        uint256 maxSlippage,
        uint256 swapMax,
        uint256 swapSlope,
        uint256 depositMax,
        uint256 depositSlope,
        uint256 withdrawMax,
        uint256 withdrawSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.prevController);

        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = expectedDepositAmountToken1;
        depositAmounts[1] = expectedDepositAmountToken2;

        uint256[] memory withdrawAmounts = new uint256[](2);

        uint256 swapAmount = expectedDepositAmountToken1 / 4;
        uint256 lpBurnAmount = 1000;  // Some arbitrary small number

        deal(ICurvePoolLike(pool).coins(0), address(ctx.proxy), expectedDepositAmountToken1);
        deal(ICurvePoolLike(pool).coins(1), address(ctx.proxy), expectedDepositAmountToken2);

        bytes32 swapKey     = RateLimitHelpers.makeAssetKey(controller.LIMIT_CURVE_SWAP(),     pool);
        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_CURVE_DEPOSIT(),  pool);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_CURVE_WITHDRAW(), pool);

        _assertRateLimit(swapKey,     0, 0);
        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        assertEq(controller.maxSlippages(pool), 0);

        /*vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.swapCurve(pool, 0, 1, swapAmount, 0);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.addLiquidityCurve(pool, depositAmounts, maxSlippage);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.removeLiquidityCurve(pool, lpBurnAmount, withdrawAmounts);*/

        executeAllPayloadsAndBridges();

        _assertRateLimit(swapKey,     swapMax,     swapSlope);
        _assertRateLimit(depositKey,  depositMax,  depositSlope);
        _assertRateLimit(withdrawKey, withdrawMax, withdrawSlope);
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

        chainSpellMetadata[domainId].domain.selectFork();

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // NOTE: Using param here because during an upgrade the _sparkLiquidityLayerContext
        //       will return a controller that is out of date.
        ForeignController domainController = ForeignController(foreignController);

        address domainAlmProxy = address(ctx.proxy);

        uint256 domainUsdcProxyBalance = domainUsdc.balanceOf(domainAlmProxy);
        uint256 domainUsdcPsmBalance   = domainUsdc.balanceOf(domainPsm3);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);

        _relayMessageOverBridges();

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance);

        // --- Step 3: Deposit USDC into PSM3 ---

        vm.prank(ctx.relayer);
        domainController.depositPSM(address(domainUsdc), usdcAmount);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance + usdcAmount);

        // --- Step 4: Withdraw all assets from PSM3 ---

        vm.prank(ctx.relayer);
        domainController.withdrawPSM(address(domainUsdc), usdcAmount);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);
        assertEq(domainUsdc.balanceOf(domainPsm3),     domainUsdcPsmBalance);

        // --- Step 5: Bridge USDC back to mainnet ---

        vm.prank(ctx.relayer);
        domainController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);

        chainSpellMetadata[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);

        _relayMessageOverBridges();

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
