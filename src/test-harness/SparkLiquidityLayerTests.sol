// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { VmSafe }   from "forge-std/Vm.sol";

import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";

import { IMetaMorpho } from "metamorpho/interfaces/IMetaMorpho.sol";

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SLLHelpers }            from "../libraries/SLLHelpers.sol";

import {
    ICurvePoolLike,
    ICurveStableswapFactoryLike,
    IFarmLike,
    IMapleStrategyLike,
    IPoolManagerLike,
    IPsmLike,
    ISparkVaultV2Like,
    ISuperstateTokenLike,
    ISUSDELike,
    ISyrupLike,
    IWithdrawalManagerLike
} from "../interfaces/Interfaces.sol";

import { SpellRunner } from "./SpellRunner.sol";

// TODO: MDL, only used by `SparkEthereumTests`.
// TODO: expand on this on https://github.com/marsfoundation/spark-spells/issues/65
abstract contract SparkLiquidityLayerTests is SpellRunner {

    struct BUIDLE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    depositAsset;
        address                    depositDestination;
        uint256                    depositAmount;
        bytes32                    depositKey;
        address                    withdrawAsset;
        address                    withdrawDestination;
        uint256                    withdrawAmount;
        bytes32                    withdrawKey;
    }

    struct CoreE2ETestParams {
        SparkLiquidityLayerContext ctx;
        uint256                    mintAmount;
        uint256                    burnAmount;
        bytes32                    mintKey;
    }

    struct CurveE2ETestVars {
        uint256   depositAmount0;
        uint256   depositAmount1;
        uint256   maxSlippage;
        uint256   depositLimit;
        uint256   withdrawLimit;
        uint256[] rates;
        uint256[] depositAmounts;
        uint256   totalDepositValue;
        uint256   minLPAmount;
        uint256   shares;
        uint256[] withdrawAmounts;
        uint256[] withdrawnTokens;
        uint256   totalWithdrawnValue;
    }

    struct CurveLPE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address pool;
        address asset0;
        address asset1;
        uint256 depositAmount;
        bytes32 depositKey;
        bytes32 withdrawKey;
        uint256 tolerance;
    }

    struct CurveOnboardingVars {
        ICurvePoolLike             pool;
        SparkLiquidityLayerContext ctx;
        MainnetController          prevController;
        MainnetController          controller;
        uint256[]                  depositAmounts;
        uint256                    minLPAmount;
        uint256[]                  withdrawAmounts;
        uint256[]                  rates;
        bytes32                    swapKey;
        bytes32                    depositKey;
        bytes32                    withdrawKey;
        uint256                    minAmountOut;
        uint256                    lpBalance;
        uint256                    smallerMaxSlippage;
    }

    struct CurveSwapE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    pool;
        address                    asset0;
        address                    asset1;
        uint256                    swapAmount;
        bytes32                    swapKey;
    }

    struct E2ETestParams {
        SparkLiquidityLayerContext ctx;
        address vault;
        uint256 depositAmount;
        bytes32 depositKey;
        bytes32 withdrawKey;
        uint256 tolerance;
    }

    struct EthenaE2ETestParams {
        SparkLiquidityLayerContext ctx;
        uint256                    depositAmount;
        bytes32                    mintKey;
        bytes32                    depositKey;
        bytes32                    cooldownKey;
        bytes32                    burnKey;
        uint256                    tolerance;
    }

    struct EthenaE2ETestVars {
        uint256 mintLimit;
        uint256 depositLimit;
        uint256 cooldownLimit;
        uint256 burnLimit;
        uint256 usdeAmount;
        uint256 proxyUsdeBalance;
        uint256 proxyUsdcBalance;
        uint256 startingShares;
        uint256 startingAssets;
        uint256 shares;
    }

    struct FarmE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    farm;
        uint256                    depositAmount;
        bytes32                    depositKey;
        bytes32                    withdrawKey;
    }

    struct MapleE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address vault;
        uint256 depositAmount;
        bytes32 depositKey;
        bytes32 redeemKey;
        bytes32 withdrawKey;
        uint256 tolerance;
    }

    struct MapleE2ETestVars {
        uint256 depositLimit;
        uint256 redeemLimit;
        uint256 withdrawLimit;
        uint256 positionAssets;
        uint256 startingShares;
        uint256 startingAssets;
        uint256 shares;
        uint256 withdrawAmount;
        uint256 totalEscrowedShares;
    }

    struct PSMSwapE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    psm;
        uint256                    swapAmount;
        bytes32                    swapKey;
    }

    struct RateLimitData {
        uint256 maxAmount;
        uint256 slope;
    }

    struct SparkLiquidityLayerContext {
        address     controller;
        address     prevController;  // Only if upgrading
        IALMProxy   proxy;
        IRateLimits rateLimits;
        address     relayer;
        address     freezer;
    }

    struct SparkVaultV2E2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    vault;
        bytes32                    takeKey;
        bytes32                    transferKey;
        uint256                    takeAmount;
        uint256                    transferAmount;
        uint256                    userVaultAmount;
        uint256                    tolerance;
    }

    struct SuperstateE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    vault;
        address                    depositAsset;
        uint256                    depositAmount;
        bytes32                    depositKey;
        address                    withdrawAsset;
        address                    withdrawDestination;
        uint256                    withdrawAmount;
        bytes32                    withdrawKey;
    }

    struct SuperstateUsccE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    depositAsset;
        address                    depositDestination;
        uint256                    depositAmount;
        bytes32                    depositKey;
        address                    withdrawAsset;
        address                    withdrawDestination;
        uint256                    withdrawAmount;
        bytes32                    withdrawKey;
    }

    struct TransferAssetE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    asset;
        address                    destination;
        bytes32                    transferKey;
        uint256                    transferAmount;
    }

    struct VaultTakeE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    asset;
        address                    vault;
        bytes32                    takeKey;
        uint256                    takeAmount;
    }

    using DomainHelpers for Domain;

    address internal constant ALM_RELAYER_BACKUP = 0x8Cc0Cb0cfB6B7e548cfd395B833c05C346534795;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_BASE_E2E_sparkLiquidityLayerCrossChainSetup() external {
        SparkLiquidityLayerContext memory ctxMainnet = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxBase    = _getSparkLiquidityLayerContext(ChainIdUtils.Base());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxBase.prevController)
        );

        _executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Base(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxBase.controller)
        );
    }

    function test_ARBITRUM_E2E_sparkLiquidityLayerCrossChainSetup() external {
        SparkLiquidityLayerContext memory ctxMainnet  = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxArbitrum = _getSparkLiquidityLayerContext(ChainIdUtils.ArbitrumOne());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxArbitrum.prevController)
        );

        _executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.ArbitrumOne(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxArbitrum.controller)
        );
    }

    function test_OPTIMISM_E2E_sparkLiquidityLayerCrossChainSetup() external {
        SparkLiquidityLayerContext memory ctxMainnet  = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxOptimism = _getSparkLiquidityLayerContext(ChainIdUtils.Optimism());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Optimism(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxOptimism.prevController)
        );

        _executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Optimism(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxOptimism.controller)
        );
    }

    function test_UNICHAIN_E2E_sparkLiquidityLayerCrossChainSetup() external {
        SparkLiquidityLayerContext memory ctxMainnet  = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());
        SparkLiquidityLayerContext memory ctxUnichain = _getSparkLiquidityLayerContext(ChainIdUtils.Unichain());

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Unichain(),
            MainnetController(ctxMainnet.prevController),
            ForeignController(ctxUnichain.prevController)
        );

        _executeAllPayloadsAndBridges();

        _testE2ESLLCrossChainForDomain(
            ChainIdUtils.Unichain(),
            MainnetController(ctxMainnet.controller),
            ForeignController(ctxUnichain.controller)
        );
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _setControllerUpgrade(ChainId chain, address prevController, address newController) internal {
        chainData[chain].prevController = prevController;
        chainData[chain].newController  = newController;
    }

    function _testERC4626Onboarding(
        address vault,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        _testERC4626Onboarding(vault, expectedDepositAmount, depositMax, depositSlope, 10, false);
    }

    function _testERC4626Onboarding(
        address vault,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope,
        uint256 tolerance,
        bool    skipInitialCheck
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

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

            _executeAllPayloadsAndBridges();
        }

        _assertRateLimit(depositKey,  depositMax,        depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testERC4626Integration(E2ETestParams(ctx, vault, expectedDepositAmount, depositKey, withdrawKey, tolerance));
    }

    function _handleMorphoFees(E2ETestParams memory p) internal {
        // If the feeRecipient is set, the vault will accrue fees into the ALMProxy during e2e test
        // deposit, causing unexpected behavior. This is a workaround to avoid this.
        try IMetaMorpho(p.vault).feeRecipient() {
            address asset = IERC4626(p.vault).asset();
            deal(asset, address(p.ctx.proxy), 1);
            vm.prank(p.ctx.relayer);
            MainnetController(p.ctx.controller).depositERC4626(p.vault, 1);
        } catch {
            // Do nothing
        }
    }

    function _testERC4626Integration(E2ETestParams memory p) internal {
        _handleMorphoFees(p);

        IERC4626 vault = IERC4626(p.vault);
        IERC20   asset = IERC20(vault.asset());

        deal(address(asset), address(p.ctx.proxy), p.depositAmount);

        uint256 depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        uint256 withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        bool unlimitedDeposit = depositLimit == type(uint256).max;

        // Assert all withdrawals are unlimited
        assertEq(withdrawLimit, type(uint256).max);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        if (!unlimitedDeposit) {
            vm.prank(p.ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            MainnetController(p.ctx.controller).depositERC4626(p.vault, depositLimit + 1);
        }

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);  // Set by deal

        uint256 startingShares = vault.balanceOf(address(p.ctx.proxy));
        uint256 startingAssets = vault.convertToAssets(startingShares);

        vm.prank(p.ctx.relayer);
        uint256 shares = MainnetController(p.ctx.controller).depositERC4626(p.vault, p.depositAmount);

        if (!unlimitedDeposit) {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);
        }

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);

        assertApproxEqAbs(vault.balanceOf(address(p.ctx.proxy)), startingShares + shares, p.tolerance);

        // Assert assets deposited are reflected in position
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(address(p.ctx.proxy))),
            startingAssets + p.depositAmount,
            p.tolerance
        );

        /*************************************************/
        /*** Step 3: Warp to check rate limit recharge ***/
        /*************************************************/

        vm.warp(block.timestamp + 30 days);

        // Assert rate limit recharge
        if (!unlimitedDeposit) {
            assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);
        }

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        /********************************************************************************************************/
        /*** Step 4: Withdraw and check resulting position, ensuring value accrual and appropriate withdrawal ***/
        /********************************************************************************************************/

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).withdrawERC4626(p.vault, p.depositAmount);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);

        // Assert value accrual
        assertGt(vault.convertToAssets(vault.balanceOf(address(p.ctx.proxy))), startingAssets);
        assertGt(vault.balanceOf(address(p.ctx.proxy)),                        startingShares);
    }

    function _testAaveOnboarding(
        address aToken,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

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

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  depositMax,        depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        _testAaveIntegration(E2ETestParams(ctx, aToken, expectedDepositAmount, depositKey, withdrawKey, 10));
    }

    function _testAaveIntegration(E2ETestParams memory p) internal {
        IERC20 asset = IERC20(IAToken(p.vault).UNDERLYING_ASSET_ADDRESS());

        // Withdraw funds to avoid supply caps getting hit
        if (IAToken(p.vault).balanceOf(address(p.ctx.proxy)) > 0) {
            uint256 maxWithdrawAmount = IAToken(p.vault).balanceOf(address(p.ctx.proxy)) > asset.balanceOf(p.vault)
                ? asset.balanceOf(p.vault)
                : IAToken(p.vault).balanceOf(address(p.ctx.proxy));

            // Subtract 10 to avoid rounding issues
            vm.prank(p.ctx.relayer);
            MainnetController(p.ctx.controller).withdrawAave(p.vault, maxWithdrawAmount - 10);
        }

        deal(address(asset), address(p.ctx.proxy), p.depositAmount);

        uint256 depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        uint256 withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        // Assert all withdrawals are unlimited
        assertEq(withdrawLimit, type(uint256).max);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).depositAave(p.vault, depositLimit + 1);

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);  // Set by deal

        uint256 startingATokenBalance = IERC4626(p.vault).balanceOf(address(p.ctx.proxy));

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).depositAave(p.vault, p.depositAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey),  depositLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);

        assertApproxEqAbs(IERC20(p.vault).balanceOf(address(p.ctx.proxy)), startingATokenBalance + p.depositAmount, p.tolerance);

        /*************************************************/
        /*** Step 3: Warp to check rate limit recharge ***/
        /*************************************************/

        vm.warp(block.timestamp + 30 days);

        // Assert rate limit recharge
        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        /********************************************************************************************************/
        /*** Step 4: Withdraw and check resulting position, ensuring value accrual and appropriate withdrawal ***/
        /********************************************************************************************************/

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).withdrawAave(p.vault, p.depositAmount);

        assertEq(asset.balanceOf(address(p.ctx.proxy)),               p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit);

        assertGt(IERC20(p.vault).balanceOf(address(p.ctx.proxy)), startingATokenBalance);
    }

    function _testMapleIntegration(MapleE2ETestParams memory p) internal {
        ISyrupLike syrup = ISyrupLike(p.vault);
        IERC20     asset = IERC20(syrup.asset());

        MainnetController controller  = MainnetController(p.ctx.controller);
        IPoolManagerLike  poolManager = IPoolManagerLike(syrup.manager());

        MapleE2ETestVars memory v;

        deal(address(asset), address(p.ctx.proxy), p.depositAmount);

        v.depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        v.redeemLimit   = p.ctx.rateLimits.getCurrentRateLimit(p.redeemKey);
        v.withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        // Assert all withdrawals and redemption requests are unlimited
        assertEq(v.withdrawLimit, type(uint256).max);
        assertEq(v.redeemLimit,   type(uint256).max);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        controller.depositERC4626(p.vault, v.depositLimit + 1);

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);  // Set by deal

        v.startingShares = syrup.balanceOf(address(p.ctx.proxy));
        v.startingAssets = syrup.convertToAssets(v.startingShares);

        vm.prank(p.ctx.relayer);
        v.shares = controller.depositERC4626(p.vault, p.depositAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - p.depositAmount);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);

        assertApproxEqAbs(syrup.balanceOf(address(p.ctx.proxy)), v.startingShares + v.shares, p.tolerance);

        assertApproxEqAbs(
            syrup.convertToAssets(syrup.balanceOf(address(p.ctx.proxy))),
            v.startingAssets + p.depositAmount,
            p.tolerance
        );

        v.positionAssets = syrup.convertToAssets(v.shares);

        // Assert assets deposited are reflected in new position
        assertApproxEqAbs(v.positionAssets, p.depositAmount, p.tolerance);

        /**********************************************************************/
        /*** Step 3: Warp to check rate limit recharge and interest accrual ***/
        /**********************************************************************/

        vm.warp(block.timestamp + 30 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        // Assert at least 0.4% interest accrued (4.8% APY)
        assertGe(
            syrup.convertToAssets(v.shares) - v.positionAssets,
            v.positionAssets * 0.004e18 / 1e18
        );

        /********************************************/
        /*** Step 4: Request redemption of shares ***/
        /********************************************/

        address withdrawalManager = poolManager.withdrawalManager();

        v.totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(address(withdrawalManager)), v.totalEscrowedShares);
        assertEq(syrup.balanceOf(address(p.ctx.proxy)),       v.startingShares + v.shares);

        assertEq(syrup.allowance(address(p.ctx.proxy), withdrawalManager), 0);

        vm.prank(p.ctx.relayer);
        controller.requestMapleRedemption(address(syrup), v.shares);

        assertEq(syrup.balanceOf(address(withdrawalManager)), v.totalEscrowedShares + v.shares);
        assertEq(syrup.balanceOf(address(p.ctx.proxy)),       v.startingShares);

        assertEq(syrup.allowance(address(p.ctx.proxy), withdrawalManager), 0);

        /***************************************************/
        /*** Step 5: Process redemption and check result ***/
        /***************************************************/

        skip(1 days);  // Warp to simulate redemption being processed

        v.withdrawAmount = syrup.convertToAssets(v.shares);

        vm.startPrank(poolManager.poolDelegate());

        uint256 remainingWithdrawal = v.withdrawAmount;

        // Iterate from the last strategy to the first because the first strategies are loan managers
        // which don't support withdrawFromStrategy
        for (uint256 i = poolManager.strategyListLength() - 1; i > 0; --i) {
            IMapleStrategyLike strategy = IMapleStrategyLike(poolManager.strategyList(i));

            uint256 aum = strategy.assetsUnderManagement();

            if (aum == 0) continue;

            uint256 strategyWithdrawAmount = aum > remainingWithdrawal ? remainingWithdrawal : aum;

            strategy.withdrawFromStrategy(strategyWithdrawAmount);

            remainingWithdrawal -= strategyWithdrawAmount;

            if (remainingWithdrawal == 0) break;
        }

        IWithdrawalManagerLike(withdrawalManager).processRedemptions(v.shares);

        vm.stopPrank();

        // Assert at least 0.4% of value was generated (4.8% APY) (approximated because of extra day)
        assertGe(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount * 1.004e18 / 1e18);
        assertEq(asset.balanceOf(address(p.ctx.proxy)), v.withdrawAmount);

        assertEq(syrup.balanceOf(address(p.ctx.proxy)), v.startingShares);
    }

    // TODO: Refactor to use helpers
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
        require(_isDeployedByFactory(pool), "Pool is not deployed by factory");

        assertGe(IERC20(pool).balanceOf(address(1)), 1e18);

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

        _executeAllPayloadsAndBridges();

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

        // Sanity check on maxSlippage of 20bps
        assertGe(maxSlippage, 0.998e18,  "maxSlippage too low");
        assertLe(maxSlippage, 1e18,      "maxSlippage too high");
    }

    function _testCurveLPIntegration(CurveLPE2ETestParams memory p) internal {
        skip(10 days);  // Recharge rate limits

        CurveE2ETestVars memory v;

        ICurvePoolLike pool = ICurvePoolLike(p.pool);

        v.rates = ICurvePoolLike(p.pool).stored_rates();

        uint256 totalValue = (pool.balances(0) * v.rates[0] + pool.balances(1) * v.rates[1]) / 1e18;

        // Calculate the value of each deposit in USD terms based on existing proportions in the pool
        uint256 deposit0Value = p.depositAmount * (pool.balances(0) * v.rates[0] / totalValue) / 1e18;
        uint256 deposit1Value = p.depositAmount * (pool.balances(1) * v.rates[1] / totalValue) / 1e18;

        // Convert to asset value
        v.depositAmount0 = deposit0Value * 1e36 / (v.rates[0] * 10 ** IERC20Metadata(p.asset0).decimals());
        v.depositAmount1 = deposit1Value * 1e36 / (v.rates[1] * 10 ** IERC20Metadata(p.asset1).decimals());

        // Convert to asset precision (TODO: Simplify mathematically with above)
        v.depositAmount0 = v.depositAmount0 * 10 ** IERC20Metadata(p.asset0).decimals() / 1e18;
        v.depositAmount1 = v.depositAmount1 * 10 ** IERC20Metadata(p.asset1).decimals() / 1e18;

        deal(address(p.asset0), address(p.ctx.proxy), v.depositAmount0);
        deal(address(p.asset1), address(p.ctx.proxy), v.depositAmount1);

        v.depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        v.withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        // Curve rate limits should not be unlimited
        assertTrue(v.depositLimit  != type(uint256).max);
        assertTrue(v.withdrawLimit != type(uint256).max);

        v.maxSlippage = MainnetController(p.ctx.controller).maxSlippages(p.pool);

        v.depositAmounts = new uint256[](2);
        v.depositAmounts[0] = v.depositAmount0;
        v.depositAmounts[1] = v.depositAmount1;

        v.totalDepositValue = (v.depositAmount0 * v.rates[0] + v.depositAmount1 * v.rates[1]) / 1e18;

        v.minLPAmount = v.totalDepositValue * v.maxSlippage / pool.get_virtual_price();

        /****************************************************/
        /*** Step 1: Deposit and check resulting position ***/
        /****************************************************/

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), v.depositAmount0);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), v.depositAmount1);

        uint256 startingLpBalance = pool.balanceOf(address(p.ctx.proxy));

        vm.prank(p.ctx.relayer);
        uint256 shares = MainnetController(p.ctx.controller).addLiquidityCurve(p.pool, v.depositAmounts, v.minLPAmount);

        assertGe(shares, v.minLPAmount);

        totalValue = (pool.balances(0) * v.rates[0] + pool.balances(1) * v.rates[1]) / 1e18;

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - v.totalDepositValue);

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), 0);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), 0);

        assertEq(pool.balanceOf(address(p.ctx.proxy)), startingLpBalance + shares);

        /**************************************************************************************/
        /*** Step 2: Withdraw and check resulting position, ensuring appropriate withdrawal ***/
        /**************************************************************************************/

        // Withdraw slightly above maxSlippage
        v.withdrawAmounts = new uint256[](2);
        v.withdrawAmounts[0] = v.depositAmount0 * (v.maxSlippage + 0.001e18) / 1e18;
        v.withdrawAmounts[1] = v.depositAmount1 * (v.maxSlippage + 0.001e18) / 1e18;

        vm.prank(p.ctx.relayer);
        v.withdrawnTokens = MainnetController(p.ctx.controller).removeLiquidityCurve(p.pool, shares, v.withdrawAmounts);

        assertGe(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), v.withdrawAmounts[0]);
        assertGe(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), v.withdrawAmounts[1]);

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), v.withdrawnTokens[0]);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), v.withdrawnTokens[1]);

        v.totalWithdrawnValue = (v.withdrawnTokens[0] * v.rates[0] + v.withdrawnTokens[1] * v.rates[1]) / 1e18;

        // Ensure that value withdrawn is greater than the value deposited * maxSlippage (18 decimal precision)
        assertGe(v.totalWithdrawnValue, v.totalDepositValue * v.maxSlippage / 1e18);

        assertEq(pool.balanceOf(address(p.ctx.proxy)), startingLpBalance);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), v.withdrawLimit - v.totalWithdrawnValue);

        /************************************/
        /*** Step 3: Recharge rate limits ***/
        /************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), v.withdrawLimit - v.totalWithdrawnValue);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), p.ctx.rateLimits.getRateLimitData(p.withdrawKey).maxAmount);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - v.totalDepositValue);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);
    }

    function _testCurveSwapIntegration(CurveSwapE2ETestParams memory p) internal {
        skip(10 days);  // Recharge rate limits

        uint256[] memory rates = ICurvePoolLike(p.pool).stored_rates();

        uint256 swapAmount = p.swapAmount * 10 ** IERC20Metadata(p.asset0).decimals() / 1e18;
        uint256 swapValue  = swapAmount * rates[0] / 1e18;

        deal(address(p.asset0), address(p.ctx.proxy), swapAmount);
        deal(address(p.asset1), address(p.ctx.proxy), 0);  // Make easier assertions

        uint256 swapLimit = p.ctx.rateLimits.getCurrentRateLimit(p.swapKey);

        uint256 maxSlippage = MainnetController(p.ctx.controller).maxSlippages(p.pool);

        /******************************************************************/
        /*** Step 1: Swap asset0 to asset1 and check resulting position ***/
        /******************************************************************/

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), swapAmount);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), 0);

        uint256 minAmountOut = swapAmount * rates[0] * maxSlippage / rates[1] / 1e18;

        // Swap asset0 to asset1
        vm.prank(p.ctx.relayer);
        uint256 amountOut = MainnetController(p.ctx.controller).swapCurve(
            p.pool,
            0,
            1,
            swapAmount,
            minAmountOut
        );

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), 0);
        assertGe(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), minAmountOut);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), amountOut);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), swapLimit - swapValue);

        /********************************************/
        /*** Step 2: Warp to recharge rate limits ***/
        /********************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), swapLimit - swapValue);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), p.ctx.rateLimits.getRateLimitData(p.swapKey).maxAmount);

        /******************************************************************/
        /*** Step 3: Swap asset1 to asset0 and check resulting position ***/
        /******************************************************************/

        swapAmount = amountOut;
        swapValue  = swapAmount * rates[1] / 1e18;

        minAmountOut = swapAmount * rates[1] * maxSlippage / rates[0] / 1e18;

        vm.prank(p.ctx.relayer);
        amountOut = MainnetController(p.ctx.controller).swapCurve(p.pool, 1, 0, swapAmount, minAmountOut);

        assertEq(IERC20(p.asset0).balanceOf(address(p.ctx.proxy)), amountOut);
        assertEq(IERC20(p.asset1).balanceOf(address(p.ctx.proxy)), 0);

        /********************************************/
        /*** Step 4: Warp to recharge rate limits ***/
        /********************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), swapLimit - swapValue);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), p.ctx.rateLimits.getRateLimitData(p.swapKey).maxAmount);
    }

    function _testPSMIntegration(PSMSwapE2ETestParams memory p) internal {
        skip(10 days);  // Recharge rate limits (TODO: Remove all of these uniformly)

        IERC20 usdc = IERC20(Ethereum.USDC);
        IERC20 usds = IERC20(Ethereum.USDS);

        address pocket = IPsmLike(p.psm).pocket();

        uint256 usdsSwapAmount = p.swapAmount * 1e12;  // Convert USDC to USDS

        deal(address(usds), address(p.ctx.proxy), usdsSwapAmount);  // 2 swaps will be done

        uint256 swapToUsdcLimit = p.ctx.rateLimits.getCurrentRateLimit(p.swapKey);

        assertNotEq(swapToUsdcLimit, type(uint256).max);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).swapUSDSToUSDC(swapToUsdcLimit + 1);

        /**************************************************************/
        /*** Step 2: Swap USDS to USDC and check resulting position ***/
        /**************************************************************/

        uint256 psmUsdcBalance   = usdc.balanceOf(pocket);
        uint256 proxyUsdcBalance = usdc.balanceOf(address(p.ctx.proxy));
        uint256 usdsTotalSupply  = usds.totalSupply();

        assertEq(usdc.balanceOf(address(pocket)),      psmUsdcBalance);
        assertEq(usdc.balanceOf(address(p.ctx.proxy)), proxyUsdcBalance);

        assertEq(usds.totalSupply(),                   usdsTotalSupply);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), usdsSwapAmount);  // Set by deal

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), swapToUsdcLimit);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).swapUSDSToUSDC(p.swapAmount);  // Use USDC precision

        assertEq(usdc.balanceOf(address(pocket)),      psmUsdcBalance   - p.swapAmount);
        assertEq(usdc.balanceOf(address(p.ctx.proxy)), proxyUsdcBalance + p.swapAmount);

        assertEq(usds.totalSupply(),                   usdsTotalSupply - usdsSwapAmount);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), 0);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), swapToUsdcLimit - p.swapAmount);

        /********************************************************/
        /*** Step 3: Warp to recharge rate limits, not to max ***/
        /********************************************************/

        skip(10 minutes);

        uint256 newSwapToUsdcLimit = p.ctx.rateLimits.getCurrentRateLimit(p.swapKey);

        assertGt(newSwapToUsdcLimit, swapToUsdcLimit - p.swapAmount);

        /***************************************************************************************/
        /*** Step 4: Swap 10% of the USDC to USDS and check that the rate limit is increased ***/
        /***************************************************************************************/

        psmUsdcBalance   = usdc.balanceOf(pocket);
        proxyUsdcBalance = usdc.balanceOf(address(p.ctx.proxy));
        usdsTotalSupply  = usds.totalSupply();

        // Do a 10% swap to increase the rate limit without hitting the max
        p.swapAmount   = p.swapAmount / 10;
        usdsSwapAmount = usdsSwapAmount / 10;

        assertEq(usdc.balanceOf(address(pocket)),      psmUsdcBalance);
        assertEq(usdc.balanceOf(address(p.ctx.proxy)), proxyUsdcBalance);

        assertEq(usds.totalSupply(),                   usdsTotalSupply);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), 0);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), newSwapToUsdcLimit);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).swapUSDCToUSDS(p.swapAmount);

        assertEq(usdc.balanceOf(address(pocket)),      psmUsdcBalance   + p.swapAmount);
        assertEq(usdc.balanceOf(address(p.ctx.proxy)), proxyUsdcBalance - p.swapAmount);

        assertEq(usds.totalSupply(),                   usdsTotalSupply + usdsSwapAmount);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), usdsSwapAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), newSwapToUsdcLimit + p.swapAmount);

        /**************************************************/
        /*** Step 5: Warp to recharge rate limits fully ***/
        /**************************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), newSwapToUsdcLimit + p.swapAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.swapKey), p.ctx.rateLimits.getRateLimitData(p.swapKey).maxAmount);
    }

    function _testFarmIntegration(FarmE2ETestParams memory p) internal {
        IERC20 stakingToken = IERC20(IFarmLike(p.farm).stakingToken());
        IERC20 rewardsToken = IERC20(IFarmLike(p.farm).rewardsToken());

        deal(address(stakingToken), address(p.ctx.proxy), p.depositAmount);

        uint256 depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        uint256 withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        // Assert all withdrawals are unlimited
        assertEq(withdrawLimit, type(uint256).max);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).depositToFarm(p.farm, depositLimit + 1);

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        uint256 farmStakingTokenBalance  = stakingToken.balanceOf(p.farm);
        uint256 farmRewardsTokenBalance  = rewardsToken.balanceOf(p.farm);
        uint256 proxyRewardsTokenBalance = rewardsToken.balanceOf(address(p.ctx.proxy));

        assertEq(stakingToken.balanceOf(address(p.ctx.proxy)), p.depositAmount);  // Set by deal
        assertEq(stakingToken.balanceOf(p.farm),               farmStakingTokenBalance);

        assertEq(rewardsToken.balanceOf(p.farm),               farmRewardsTokenBalance);
        assertEq(rewardsToken.balanceOf(address(p.ctx.proxy)), proxyRewardsTokenBalance);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).depositToFarm(p.farm, p.depositAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);

        assertEq(stakingToken.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(stakingToken.balanceOf(p.farm),               farmStakingTokenBalance + p.depositAmount);

        assertEq(rewardsToken.balanceOf(p.farm),               farmRewardsTokenBalance);
        assertEq(rewardsToken.balanceOf(address(p.ctx.proxy)), proxyRewardsTokenBalance);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);

        /*************************************************/
        /*** Step 3: Warp to check rate limit recharge ***/
        /*************************************************/

        vm.warp(block.timestamp + 30 days);

        // Assert rate limit recharge
        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        /********************************************************************************************************/
        /*** Step 4: Withdraw and check resulting position, ensuring value accrual and appropriate withdrawal ***/
        /********************************************************************************************************/

        farmStakingTokenBalance  = stakingToken.balanceOf(p.farm);
        farmRewardsTokenBalance  = rewardsToken.balanceOf(p.farm);
        proxyRewardsTokenBalance = rewardsToken.balanceOf(address(p.ctx.proxy));

        assertEq(stakingToken.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(stakingToken.balanceOf(p.farm),               farmStakingTokenBalance);

        assertEq(rewardsToken.balanceOf(p.farm),               farmRewardsTokenBalance);
        assertEq(rewardsToken.balanceOf(address(p.ctx.proxy)), proxyRewardsTokenBalance);

        uint256 earned = IFarmLike(p.farm).earned(address(p.ctx.proxy));

        assertGe(earned, 0);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).withdrawFromFarm(p.farm, p.depositAmount);

        assertEq(stakingToken.balanceOf(address(p.ctx.proxy)), p.depositAmount);
        assertEq(stakingToken.balanceOf(p.farm),               farmStakingTokenBalance - p.depositAmount);

        assertEq(rewardsToken.balanceOf(p.farm),               farmRewardsTokenBalance  - earned);
        assertEq(rewardsToken.balanceOf(address(p.ctx.proxy)), proxyRewardsTokenBalance + earned);
    }

    function _testEthenaIntegration(EthenaE2ETestParams memory p) internal {
        IERC20 usdc = IERC20(Ethereum.USDC);
        IERC20 usde = IERC20(Ethereum.USDE);

        ISUSDELike susde = ISUSDELike(Ethereum.SUSDE);

        EthenaE2ETestVars memory v;

        deal(address(usdc), address(p.ctx.proxy), p.depositAmount);

        v.mintLimit     = p.ctx.rateLimits.getCurrentRateLimit(p.mintKey);
        v.depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        v.cooldownLimit = p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey);
        v.burnLimit     = p.ctx.rateLimits.getCurrentRateLimit(p.burnKey);

        // Assert cooldown is unlimited
        assertEq(v.cooldownLimit, type(uint256).max);

        // Unstake any existing sUSDE to prevent unexpected behavior
        skip(7 days + 1);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).unstakeSUSDe();

        /*************************************/
        /*** Step 1: Check mint rate limit ***/
        /*************************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).prepareUSDeMint(v.mintLimit + 1);

        /*********************************/
        /*** Step 2: Prepare USDE mint ***/
        /*********************************/

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), v.mintLimit);

        assertEq(usdc.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), 0);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).prepareUSDeMint(p.depositAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), v.mintLimit - p.depositAmount);

        assertEq(usdc.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), p.depositAmount);

        /**********************************************/
        /*** Step 3: Simulate USDE mint from Ethena ***/
        /**********************************************/

        v.usdeAmount = p.depositAmount * 1e12;

        deal(address(usde), Ethereum.ETHENA_MINTER, v.usdeAmount);

        v.proxyUsdeBalance = usde.balanceOf(address(p.ctx.proxy));

        vm.startPrank(Ethereum.ETHENA_MINTER);
        usdc.transferFrom(address(p.ctx.proxy), Ethereum.ETHENA_MINTER, p.depositAmount);
        usde.transfer(address(p.ctx.proxy), v.usdeAmount);
        vm.stopPrank();

        assertEq(usde.balanceOf(address(p.ctx.proxy)),   v.proxyUsdeBalance + v.usdeAmount);
        assertEq(usde.balanceOf(Ethereum.ETHENA_MINTER), 0);  // Balance set by deal so should go to zero

        assertEq(usdc.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), 0);

        /****************************************/
        /*** Step 4: Check deposit rate limit ***/
        /****************************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).depositERC4626(Ethereum.SUSDE, v.depositLimit + 1);

        /****************************************************/
        /*** Step 5: Deposit and check resulting position ***/
        /****************************************************/

        v.proxyUsdeBalance = usde.balanceOf(address(p.ctx.proxy));

        v.startingShares = susde.balanceOf(address(p.ctx.proxy));
        v.startingAssets = susde.convertToAssets(v.startingShares);

        vm.prank(p.ctx.relayer);
        v.shares = MainnetController(p.ctx.controller).depositERC4626(address(susde), v.usdeAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - v.usdeAmount);

        assertEq(usde.balanceOf(address(p.ctx.proxy)), v.proxyUsdeBalance - v.usdeAmount);

        assertApproxEqAbs(susde.balanceOf(address(p.ctx.proxy)), v.startingShares + v.shares, p.tolerance);

        // Assert assets deposited are reflected in position
        assertApproxEqAbs(
            susde.convertToAssets(susde.balanceOf(address(p.ctx.proxy))),
            v.startingAssets + v.usdeAmount,
            p.tolerance
        );

        /******************************************************/
        /*** Step 6: Cooldown sUSDE using shares (snapshot) ***/
        /******************************************************/

        address silo = susde.silo();

        uint256 siloBalance    = usde.balanceOf(silo);
        uint256 underlyingUsde = susde.convertToAssets(v.shares);

        assertEq(susde.balanceOf(address(p.ctx.proxy)), v.startingShares + v.shares);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey), type(uint256).max);

        uint256 snapshot = vm.snapshot();

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).cooldownSharesSUSDe(v.shares);

        assertEq(usde.balanceOf(silo),                  siloBalance + underlyingUsde);
        assertEq(susde.balanceOf(address(p.ctx.proxy)), v.startingShares);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey), type(uint256).max);

        vm.revertTo(snapshot);

        /*********************************************************/
        /*** Step 7: Cooldown sUSDE using assets (same result) ***/
        /*********************************************************/

        assertEq(susde.balanceOf(address(p.ctx.proxy)), v.startingShares + v.shares);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey), type(uint256).max);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).cooldownAssetsSUSDe(underlyingUsde);

        assertEq(usde.balanceOf(silo),                  siloBalance + underlyingUsde);
        assertEq(susde.balanceOf(address(p.ctx.proxy)), v.startingShares);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey), type(uint256).max);

        /**************************************/
        /*** Step 8: Warp and unstake sUSDE ***/
        /**************************************/

        skip(7 days);

        v.proxyUsdeBalance = usde.balanceOf(address(p.ctx.proxy));

        assertEq(usde.balanceOf(address(silo)),        siloBalance + underlyingUsde);
        assertEq(usde.balanceOf(address(p.ctx.proxy)), v.proxyUsdeBalance);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).unstakeSUSDe();

        assertEq(usde.balanceOf(address(silo)),        siloBalance);
        assertEq(usde.balanceOf(address(p.ctx.proxy)), v.proxyUsdeBalance + underlyingUsde);

        /*************************************/
        /*** Step 9: Check burn rate limit ***/
        /*************************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).prepareUSDeBurn(v.burnLimit + 1);

        /**********************************/
        /*** Step 10: Prepare USDE burn ***/
        /**********************************/

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.burnKey), v.burnLimit);

        uint256 usdeAllowance = usde.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER);

        assertEq(usde.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), usdeAllowance);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).prepareUSDeBurn(underlyingUsde);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.burnKey), v.burnLimit - underlyingUsde);

        assertEq(usde.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), underlyingUsde);

        /***********************************************/
        /*** Step 11: Simulate USDE burn from Ethena ***/
        /***********************************************/

        uint256 usdcAmount = underlyingUsde / 1e12;

        deal(address(usdc), Ethereum.ETHENA_MINTER, usdcAmount);

        v.proxyUsdcBalance = usdc.balanceOf(address(p.ctx.proxy));

        vm.startPrank(Ethereum.ETHENA_MINTER);
        usde.transferFrom(address(p.ctx.proxy), Ethereum.ETHENA_MINTER, underlyingUsde);
        usdc.transfer(address(p.ctx.proxy), usdcAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(p.ctx.proxy)),   v.proxyUsdcBalance + usdcAmount);
        assertEq(usdc.balanceOf(Ethereum.ETHENA_MINTER), 0);  // Balance set by deal so should go to zero

        assertEq(usdc.allowance(address(p.ctx.proxy), Ethereum.ETHENA_MINTER), 0);

        /**************************************************/
        /*** Step 12: Warp and recharge all rate limits ***/
        /**************************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), v.mintLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), p.ctx.rateLimits.getRateLimitData(p.mintKey).maxAmount);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), v.depositLimit - v.usdeAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.cooldownKey), type(uint256).max);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.burnKey), v.burnLimit - underlyingUsde);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.burnKey), p.ctx.rateLimits.getRateLimitData(p.burnKey).maxAmount);
    }

    function _testCoreIntegration(CoreE2ETestParams memory p) internal {
        IERC20 usds = IERC20(Ethereum.USDS);

        require(p.mintAmount > p.burnAmount, "Invalid burn amount");

        uint256 totalSupply      = usds.totalSupply();
        uint256 usdsProxyBalance = usds.balanceOf(address(p.ctx.proxy));

        uint256 mintLimit = p.ctx.rateLimits.getCurrentRateLimit(p.mintKey);

        /*************************************/
        /*** Step 1: Check burn rate limit ***/
        /*************************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).mintUSDS(mintLimit + 1);

        /*************************/
        /*** Step 2: Mint USDS ***/
        /*************************/

        assertEq(usds.totalSupply(),                   totalSupply);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), usdsProxyBalance);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), mintLimit);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).mintUSDS(p.mintAmount);

        assertEq(usds.totalSupply(),                   totalSupply      + p.mintAmount);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), usdsProxyBalance + p.mintAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), mintLimit - p.mintAmount);

        /*************************/
        /*** Step 3: Burn USDS ***/
        /*************************/

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).burnUSDS(p.burnAmount);

        assertEq(usds.totalSupply(),                   totalSupply      + p.mintAmount - p.burnAmount);
        assertEq(usds.balanceOf(address(p.ctx.proxy)), usdsProxyBalance + p.mintAmount - p.burnAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), mintLimit - p.mintAmount + p.burnAmount);

        /**************************************************/
        /*** Step 4: Warp and recharge all rate limits ***/
        /**************************************************/

        skip(10 days);

        assertGt(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), mintLimit - p.mintAmount + p.burnAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.mintKey), p.ctx.rateLimits.getRateLimitData(p.mintKey).maxAmount);
    }

    function _testTransferAssetIntegration(TransferAssetE2ETestParams memory p) internal {
        MainnetController controller = MainnetController(p.ctx.controller);

        IERC20 asset = IERC20(p.asset);

        uint256 transferLimit   = p.ctx.rateLimits.getCurrentRateLimit(p.transferKey);
        uint256 transferAmount1 = p.transferAmount / 4;
        uint256 transferAmount2 = p.transferAmount - transferAmount1;

        deal(address(asset), address(p.ctx.proxy), transferAmount1 + transferAmount2);

        bool unlimitedTransfer = transferLimit == type(uint256).max;

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        if (!unlimitedTransfer) {
            vm.prank(p.ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            controller.transferAsset(address(asset), p.destination, transferLimit + 1);
        }

        /*****************************************************/
        /*** Step 2: Transfer and check resulting position ***/
        /*****************************************************/

        assertEq(asset.balanceOf(address(p.ctx.proxy)), transferAmount1 + transferAmount2);
        assertEq(asset.balanceOf(p.destination),        0);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit);

        vm.prank(p.ctx.relayer);
        controller.transferAsset(address(asset), p.destination, transferAmount1);

        if (address(asset) == Ethereum.USCC && p.destination == Ethereum.USCC) {
            assertEq(asset.balanceOf(p.destination), 0);  // USCC is burned on transfer to USCC
        } else {
            assertEq(asset.balanceOf(p.destination), transferAmount1);
        }

        assertEq(asset.balanceOf(address(p.ctx.proxy)), transferAmount2);

        assertEq(
            p.ctx.rateLimits.getCurrentRateLimit(p.transferKey),
            unlimitedTransfer ? transferLimit : transferLimit - transferAmount1
        );

        /*****************************************/
        /*** Step 3: Transfer remaining amount ***/
        /*****************************************/

        vm.prank(p.ctx.relayer);
        controller.transferAsset(address(asset), p.destination, transferAmount2);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);

        if(address(asset) == Ethereum.USCC && p.destination == Ethereum.USCC) {
            assertEq(asset.balanceOf(p.destination), 0);  // USCC is burned on transfer to USCC
        } else {
            assertEq(asset.balanceOf(p.destination), transferAmount1 + transferAmount2);
        }

        assertEq(
            p.ctx.rateLimits.getCurrentRateLimit(p.transferKey),
            unlimitedTransfer ? transferLimit : transferLimit - transferAmount1 - transferAmount2
        );

        /********************************************/
        /*** Step 4: Warp to recharge rate limits ***/
        /********************************************/

        skip(1 days + 1 seconds);  // +1 second due to rounding

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit);  // Should be this for unlimited transfers as well
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), p.ctx.rateLimits.getRateLimitData(p.transferKey).maxAmount);
    }

    function _testBUIDLIntegration(BUIDLE2ETestParams memory p) internal {
        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            p.ctx,
            asset:          p.depositAsset,
            destination:    p.depositDestination,
            transferKey:    p.depositKey,
            transferAmount: p.depositAmount
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            p.ctx,
            asset:          p.withdrawAsset,
            destination:    p.withdrawDestination,
            transferKey:    p.withdrawKey,
            transferAmount: p.withdrawAmount
        }));
    }

    function _testSuperstateIntegration(SuperstateE2ETestParams memory p) internal {
        MainnetController controller = MainnetController(p.ctx.controller);

        deal(address(p.depositAsset), address(p.ctx.proxy), p.depositAmount);

        IERC20               asset = IERC20(p.depositAsset);
        ISuperstateTokenLike token = ISuperstateTokenLike(p.vault);

        uint256 depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        uint256 withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        controller.subscribeSuperstate(depositLimit + 1);

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        ( address sweepDestination, ) = token.supportedStablecoins(address(asset));

        uint256 sweepDestinationBalance = asset.balanceOf(sweepDestination);

        ( uint256 expectedToken, uint256 stablecoinInAmountAfterFee, uint256 feeOnStablecoinInAmount )
            = token.calculateSuperstateTokenOut(p.depositAmount, address(asset));

        uint256 totalSupply = token.totalSupply();

        assertEq(stablecoinInAmountAfterFee, p.depositAmount);
        assertEq(feeOnStablecoinInAmount,    0);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);
        assertEq(asset.balanceOf(sweepDestination),     sweepDestinationBalance);

        assertEq(asset.allowance(address(p.ctx.proxy), address(token)), 0);

        assertEq(token.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(token.totalSupply(),                   totalSupply);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit);

        vm.prank(p.ctx.relayer);
        controller.subscribeSuperstate(p.depositAmount);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(asset.balanceOf(sweepDestination),     sweepDestinationBalance + p.depositAmount);

        assertEq(asset.allowance(address(p.ctx.proxy), address(token)), 0);

        assertEq(token.balanceOf(address(p.ctx.proxy)), expectedToken);
        assertEq(token.totalSupply(),                   totalSupply + expectedToken);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);

        /**************************************************/
        /*** Step 3: Warp and recharge all rate limits ***/
        /**************************************************/

        skip(1 days + 1 seconds);  // +1 second due to rounding

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);
    }

    function _testSuperstateUsccIntegration(SuperstateUsccE2ETestParams memory p) internal {
        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            p.ctx,
            asset:          p.depositAsset,
            destination:    p.depositDestination,
            transferKey:    p.depositKey,
            transferAmount: p.depositAmount
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            p.ctx,
            asset:          p.withdrawAsset,
            destination:    p.withdrawDestination,
            transferKey:    p.withdrawKey,
            transferAmount: p.withdrawAmount
        }));
    }

    function _testVaultTakeIntegration(VaultTakeE2ETestParams memory p) internal {
        MainnetController controller = MainnetController(p.ctx.controller);

        deal(address(p.asset), address(p.vault), p.takeAmount);

        uint256 rateLimit = p.ctx.rateLimits.getCurrentRateLimit(p.takeKey);

        uint256 sparkBalance = IERC20(p.asset).balanceOf(address(p.ctx.proxy));
        uint256 vaultBalance = IERC20(p.asset).balanceOf(p.vault);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.takeKey), rateLimit);

        assertEq(IERC20(p.asset).balanceOf(p.vault),              vaultBalance);
        assertEq(IERC20(p.asset).balanceOf(address(p.ctx.proxy)), sparkBalance);

        vm.prank(p.ctx.relayer);
        controller.takeFromSparkVault(p.vault, p.takeAmount);

        assertEq(IERC20(p.asset).balanceOf(p.vault),              vaultBalance - p.takeAmount);
        assertEq(IERC20(p.asset).balanceOf(address(p.ctx.proxy)), sparkBalance + p.takeAmount);

        if (rateLimit != type(uint256).max) {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.takeKey), rateLimit - p.takeAmount);
        } else {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.takeKey), type(uint256).max);
        }
    }

    function _testSparkVaultV2Integration(SparkVaultV2E2ETestParams memory p) internal {
        ISparkVaultV2Like vault = ISparkVaultV2Like(p.vault);

        // Step 1: Check seeding

        uint256 amount = vault.asset() == Ethereum.WETH ? 0.0001e18 : 1e6;

        assertGe(vault.totalSupply(), amount);
        assertGe(vault.totalAssets(), amount);

        assertEq(vault.balanceOf(address(1)), amount);

        // Step 2: Check SLL take and transfer integrations

        _testVaultTakeIntegration(VaultTakeE2ETestParams({
            ctx:        p.ctx,
            asset:      vault.asset(),
            vault:      p.vault,
            takeKey:    p.takeKey,
            takeAmount: p.takeAmount
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            p.ctx,
            asset:          vault.asset(),
            destination:    p.vault,
            transferKey:    p.transferKey,
            transferAmount: p.transferAmount
        }));

        // Step 3: Check user vault integration

        address user = makeAddr("user");

        IERC20 asset = IERC20(vault.asset());

        deal(address(asset), user, p.userVaultAmount);

        uint256 assetBalanceVault = asset.balanceOf(address(vault));
        uint256 vaultTotalSupply  = vault.totalSupply();

        assertEq(asset.balanceOf(user),           p.userVaultAmount);
        assertEq(asset.balanceOf(address(vault)), assetBalanceVault);

        assertEq(vault.totalSupply(),   vaultTotalSupply);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.assetsOf(user),  0);

        vm.startPrank(user);
        SafeERC20.safeIncreaseAllowance(IERC20(vault.asset()), p.vault, p.userVaultAmount);
        uint256 shares = vault.deposit(p.userVaultAmount, user);
        vm.stopPrank();

        assertEq(asset.balanceOf(user),           0);
        assertEq(asset.balanceOf(address(vault)), assetBalanceVault + p.userVaultAmount);

        assertEq(vault.totalSupply(),   vaultTotalSupply + shares);
        assertEq(vault.balanceOf(user), shares);

        assertApproxEqAbs(vault.assetsOf(user),  p.userVaultAmount, p.tolerance);

        // TODO: Remove this once vaults are live (5% APY)
        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        vault.setVsr(1.000000001547125957863212448e27);

        skip(1 days);

        assertEq(asset.balanceOf(user),           0);
        assertEq(asset.balanceOf(address(vault)), assetBalanceVault + p.userVaultAmount);

        assertEq(vault.totalSupply(),   vaultTotalSupply + shares);
        assertEq(vault.balanceOf(user), shares);
        assertGt(vault.assetsOf(user),  p.userVaultAmount);

        uint256 totalVaultAssets = vault.totalAssets();
        deal(address(asset), p.vault, totalVaultAssets);

        vm.prank(user);
        vault.redeem(shares, user, user);

        assertGt(asset.balanceOf(user),           p.userVaultAmount);
        assertLt(asset.balanceOf(address(vault)), assetBalanceVault);

        assertEq(vault.totalSupply(),   vaultTotalSupply);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.assetsOf(user),  0);
    }

    function _testControllerUpgrade(address oldController, address newController) internal {
        ChainId currentChain = ChainIdUtils.fromUint(block.chainid);

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // Note the functions used are interchangeable with mainnet and foreign controllers
        MainnetController controller = MainnetController(newController);

        bytes32 controllerRole = ctx.proxy.CONTROLLER();
        bytes32 relayerRole    = controller.RELAYER();
        bytes32 freezerRole    = controller.FREEZER();

        assertEq(ctx.proxy.hasRole(controllerRole, oldController), true);
        assertEq(ctx.proxy.hasRole(controllerRole, newController), false);

        assertEq(ctx.rateLimits.hasRole(controllerRole, oldController), true);
        assertEq(ctx.rateLimits.hasRole(controllerRole, newController), false);

        assertEq(controller.hasRole(relayerRole, ctx.relayer),        false);
        assertEq(controller.hasRole(relayerRole, ALM_RELAYER_BACKUP), false);
        assertEq(controller.hasRole(freezerRole, ctx.freezer),        false);

        if (currentChain == ChainIdUtils.Ethereum()) {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(address(0)));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS), 0);
        } else {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(address(0)));
        }

        _executeAllPayloadsAndBridges();

        assertEq(ctx.proxy.hasRole(controllerRole, oldController), false);
        assertEq(ctx.proxy.hasRole(controllerRole, newController), true);

        assertEq(ctx.rateLimits.hasRole(controllerRole, oldController), false);
        assertEq(ctx.rateLimits.hasRole(controllerRole, newController), true);

        assertEq(controller.hasRole(relayerRole, ctx.relayer),        true);
        assertEq(controller.hasRole(relayerRole, ALM_RELAYER_BACKUP), true);
        assertEq(controller.hasRole(freezerRole, ctx.freezer),        true);

        if (currentChain == ChainIdUtils.Ethereum()) {
            _assertOldControllerEvents(oldController);

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(Base.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  0.9985e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0.9990e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS), 0.998e18);  // NOTE: New slippage not in oldController, part of the payload to onboard a new pool.

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), MainnetController(oldController).maxSlippages(Ethereum.CURVE_SUSDSUSDT));
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), MainnetController(oldController).maxSlippages(Ethereum.CURVE_PYUSDUSDC));
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  MainnetController(oldController).maxSlippages(Ethereum.CURVE_USDCUSDT));
        } else {
            bytes32[] memory topics = new bytes32[](1);
            topics[0] = ForeignController.MintRecipientSet.selector;

            VmSafe.EthGetLogs[] memory cctpLogs = vm.eth_getLogs(
                0,
                block.number,
                oldController,
                topics
            );

            assertEq(cctpLogs.length, 1);

            assertEq(uint32(uint256(cctpLogs[0].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), ForeignController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM));
        }
    }

    function _assertOldControllerEvents(address _oldController) internal {
        MainnetController oldController = MainnetController(_oldController);

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = MainnetController.MaxSlippageSet.selector;

        uint256 startBlock = 22218000;

        VmSafe.EthGetLogs[] memory slippageLogs = vm.eth_getLogs(
            startBlock,
            block.number,
            _oldController,
            topics
        );

        topics[0] = MainnetController.MintRecipientSet.selector;
        VmSafe.EthGetLogs[] memory cctpLogs = vm.eth_getLogs(
            startBlock,
            block.number,
            _oldController,
            topics
        );

        topics[0] = MainnetController.LayerZeroRecipientSet.selector;
        VmSafe.EthGetLogs[] memory layerZeroLogs = vm.eth_getLogs(
            startBlock,
            block.number,
            _oldController,
            topics
        );

        assertEq(slippageLogs.length,  5);
        assertEq(cctpLogs.length,      4);
        assertEq(layerZeroLogs.length, 0);

        assertEq(address(uint160(uint256(slippageLogs[0].topics[1]))), Ethereum.CURVE_SUSDSUSDT);
        assertEq(address(uint160(uint256(slippageLogs[1].topics[1]))), Ethereum.CURVE_USDCUSDT);
        assertEq(address(uint160(uint256(slippageLogs[2].topics[1]))), Ethereum.CURVE_PYUSDUSDC);
        assertEq(address(uint160(uint256(slippageLogs[3].topics[1]))), Ethereum.CURVE_SUSDSUSDT);  // Duplicated
        assertEq(address(uint160(uint256(slippageLogs[4].topics[1]))), Ethereum.CURVE_PYUSDUSDC);  // Duplicated

        assertEq(oldController.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);
        assertEq(oldController.maxSlippages(Ethereum.CURVE_USDCUSDT),  0.9985e18);
        assertEq(oldController.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0.9990e18);

        assertEq(uint32(uint256(cctpLogs[0].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        assertEq(uint32(uint256(cctpLogs[1].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        assertEq(uint32(uint256(cctpLogs[2].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        assertEq(uint32(uint256(cctpLogs[3].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);

        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(Base.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));
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
        } else if (domainId == ChainIdUtils.Optimism()) {
            domainUsdc   = IERC20(Optimism.USDC);
            domainPsm3   = Optimism.PSM3;
            domainCctpId = CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM;
        } else if (domainId == ChainIdUtils.Unichain()) {
            domainUsdc   = IERC20(Unichain.USDC);
            domainPsm3   = Unichain.PSM3;
            domainCctpId = CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN;
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
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _getSparkLiquidityLayerContext(ChainId chain) internal view returns (SparkLiquidityLayerContext memory ctx) {
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
        } else if (chain == ChainIdUtils.Avalanche()) {
            ctx = SparkLiquidityLayerContext(
                Avalanche.ALM_CONTROLLER,
                address(0),
                IALMProxy(Avalanche.ALM_PROXY),
                IRateLimits(Avalanche.ALM_RATE_LIMITS),
                Avalanche.ALM_RELAYER,
                Avalanche.ALM_FREEZER
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

    function _getSparkLiquidityLayerContext() internal view returns (SparkLiquidityLayerContext memory) {
        return _getSparkLiquidityLayerContext(ChainIdUtils.fromUint(block.chainid));
    }

    // TODO: MDL, seems like unnecessary overload bloat.
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

    function _isDeployedByFactory(address pool) internal view returns (bool) {
        address impl = ICurveStableswapFactoryLike(Ethereum.CURVE_STABLESWAP_FACTORY).get_implementation_address(pool);
        return impl != address(0);
    }

}
