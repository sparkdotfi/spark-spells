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
    IALMProxy   proxy;
    IRateLimits rateLimits;
    address     relayer;
    address     freezer;
}

// TODO: expand on this on https://github.com/marsfoundation/spark-spells/issues/65
abstract contract SparkLiquidityLayerTests is SpellRunner {

    using DomainHelpers for Domain;

    address private constant ALM_RELAYER_BACKUP = 0x8Cc0Cb0cfB6B7e548cfd395B833c05C346534795;

    /**********************************************************************************************/
    /*** State loading helpers                                                                  ***/
    /**********************************************************************************************/

    function _getSparkLiquidityLayerContext() internal view returns(SparkLiquidityLayerContext memory ctx) {
        ChainId currentChain = ChainIdUtils.fromUint(block.chainid);
        if (currentChain == ChainIdUtils.Ethereum()) {
            ctx = SparkLiquidityLayerContext(
                Ethereum.ALM_CONTROLLER,
                IALMProxy(Ethereum.ALM_PROXY),
                IRateLimits(Ethereum.ALM_RATE_LIMITS),
                Ethereum.ALM_RELAYER,
                Ethereum.ALM_FREEZER
            );
        } else if (currentChain == ChainIdUtils.Base()) {
            ctx = SparkLiquidityLayerContext(
                Base.ALM_CONTROLLER,
                IALMProxy(Base.ALM_PROXY),
                IRateLimits(Base.ALM_RATE_LIMITS),
                Base.ALM_RELAYER,
                Base.ALM_FREEZER
            );
        } else if (currentChain == ChainIdUtils.ArbitrumOne()) {
            ctx = SparkLiquidityLayerContext(
                Arbitrum.ALM_CONTROLLER,
                IALMProxy(Arbitrum.ALM_PROXY),
                IRateLimits(Arbitrum.ALM_RATE_LIMITS),
                Arbitrum.ALM_RELAYER,
                Arbitrum.ALM_FREEZER
            );
        } else {
            revert("SLL/executing on unknown chain");
        }
    }

    // Needs to be overridden the test contract for upgrades
    function _getLatestControllers() internal pure virtual returns (address, address, address) {
        return (
            Ethereum.ALM_CONTROLLER,
            Base.ALM_CONTROLLER,
            Arbitrum.ALM_CONTROLLER
        );
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

        // TODO: Fix "Nonce already used" error when using 10_000_000e6
        uint256 usdcAmount = 1_000_000e6;

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

    function test_E2E_sparkLiquidityLayerCrossChainSetup() public{
        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(Ethereum.ALM_CONTROLLER),
            ForeignController(Arbitrum.ALM_CONTROLLER)
        );

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(Ethereum.ALM_CONTROLLER),
            ForeignController(Base.ALM_CONTROLLER)
        );

        executeAllPayloadsAndBridges();

        // Load the latest controllers (will return the same values if not overridden)
        (
            address updatedMainnetController,
            address updatedArbController,
            address updatedBaseController
        ) = _getLatestControllers();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(updatedMainnetController),
            ForeignController(updatedArbController)
        );

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(updatedMainnetController),
            ForeignController(updatedBaseController)
        );
    }

}
