// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { VmSafe }   from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

import { IMetaMorpho, MarketParams, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ICurvePoolLike, ISparkVaultV2Like } from "../interfaces/Interfaces.sol";

import { ChainIdUtils }  from "../libraries/ChainIdUtils.sol";
import { MorphoHelpers } from "../libraries/MorphoHelpers.sol";
import { SLLHelpers }    from "../libraries/SLLHelpers.sol";

import {
    IATokenLike,
    ICurvePoolLike,
    ICurveStableswapFactoryLike,
    IERC20Like,
    IFarmLike,
    IMapleStrategyLike,
    IPoolManagerLike,
    IPSMLike,
    IPSM3Like,
    ISparkVaultV2Like,
    ISuperstateTokenLike,
    ISUSDELike,
    ISyrupLike,
    IWithdrawalManagerLike
} from "../interfaces/Interfaces.sol";

import { SpellRunner } from "./SpellRunner.sol";

// TODO: expand on this on https://github.com/marsfoundation/spark-spells/issues/65
abstract contract SparkLiquidityLayerTests is SpellRunner {

    enum Category {
        AAVE,
        BUIDL,
        CCTP_GENERAL,
        CCTP,
        CENTRIFUGE,
        CORE,
        CURVE_LP,
        CURVE_SWAP,
        ERC4626,
        ETHENA,
        FARM,
        MAPLE,
        PSM,
        SPARK_VAULT_V2,
        SUPERSTATE,
        PSM3,
        SUPERSTATE_USCC,
        TREASURY,
        TRANSFER_ASSET
    }

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

    struct CCTPE2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    cctp;
        uint256                    transferAmount;
        bytes32                    transferKey;
        uint32                     cctpId;
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

    struct PSM3E2ETestParams {
        SparkLiquidityLayerContext ctx;
        address                    psm3;
        address                    asset;
        uint256                    depositAmount;
        bytes32                    depositKey;
        bytes32                    withdrawKey;
        uint256                    tolerance;
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

    struct SLLIntegration {
        string   label;
        Category category;
        address  integration;
        bytes32  entryId;
        bytes32  entryId2;
        bytes32  exitId;
        bytes32  exitId2;
        bytes    extraData;
    }

    using DomainHelpers for Domain;

    // TODO: Put in registry
    address internal constant ARKIS                = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant ANCHORAGE            = 0x49506C3Aa028693458d6eE816b2EC28522946872;
    address internal constant AAVE_ATOKEN_USDC     = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address internal constant AAVE_CORE_AUSDT      = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    address internal constant AAVE_ETH_LIDO_USDS   = 0x09AA30b182488f769a9824F15E6Ce58591Da4781;
    address internal constant AAVE_ETH_USDC        = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant AAVE_ETH_USDS        = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address internal constant BASE_MORPHO_TOKEN    = 0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842;
    address internal constant BASE_SPARK_MULTISIG  = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address internal constant BUIDL_DEPOSIT        = 0xD1917664bE3FdAea377f6E8D5BF043ab5C3b1312;
    address internal constant BUIDL_REDEEM         = 0x8780Dd016171B91E4Df47075dA0a947959C34200;
    address internal constant B2C2                 = 0xa29E963992597B21bcDCaa969d571984869C4FF5;
    address internal constant CURVE_PYUSDUSDC      = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address internal constant CURVE_PYUSDUSDS      = 0xA632D59b9B804a956BfaA9b48Af3A1b74808FC1f;
    address internal constant FLUID_SUSDS_ARBITRUM = 0x3459fcc94390C3372c0F7B4cD3F8795F0E5aFE96;
    address internal constant MORPHO_TOKEN         = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address internal constant MORPHO_USDC_BC       = 0x56A76b428244a50513ec81e225a293d128fd581D;
    address internal constant SPARK_MULTISIG       = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address internal constant SYRUP                = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;
    address internal constant USCC_DEPOSIT         = 0xDB48AC0802F9A79145821A5430349cAff6d676f7;
    address internal constant USDE_ATOKEN          = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
    address internal constant USDS_ATOKEN          = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;
    address internal constant USDS_SPK_FARM        = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    uint256 internal constant START_BLOCK = 21029247;

    // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
    //   1.000000003022265980097387650
    uint256 internal constant TEN_PCT_APY = 1.000000003022265980097387650e27;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_E2E_sparkLiquidityLayerCrossChainSetup() external {
        _runE2ESLLCrossChainTestForAllDomains({ isPostExecution: false });

        _executeAllPayloadsAndBridges();

        _runE2ESLLCrossChainTestForAllDomains({ isPostExecution: true });
    }

    function test_ETHEREUM_E2E_sparkLiquidityLayer() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext({ isPostExecution: false });

        bytes32[]        memory rateLimitKeys = _getRateLimitKeys({ isPostExecution: false });
        SLLIntegration[] memory integrations  = _getPreExecutionIntegrations();

        _checkRateLimitKeys(integrations, rateLimitKeys);

        for (uint256 i = 0; i < integrations.length; ++i) {
            _runSLLE2ETests(ctx, integrations[i]);
        }

        vm.recordLogs();  // Used to get events from rate limits after execution

        _executeMainnetPayload();

        rateLimitKeys = _getRateLimitKeys({ isPostExecution: true });
        integrations  = _getPostExecutionIntegrations(integrations);

        ctx = _getSparkLiquidityLayerContext({ isPostExecution: true });

        _checkRateLimitKeys(integrations, rateLimitKeys);

        for (uint256 i = 0; i < integrations.length; ++i) {
            _runSLLE2ETests(ctx, integrations[i]);
        }
    }

    function test_ARBITRUM_E2E_sparkLiquidityLayer() external {
        _runSLLE2ETestsForDomain(ChainIdUtils.ArbitrumOne());
    }

    function test_AVALANCHE_E2E_sparkLiquidityLayer() external {
        _runSLLE2ETestsForDomain(ChainIdUtils.Avalanche());
    }

    function test_BASE_E2E_sparkLiquidityLayer() external {
        _runSLLE2ETestsForDomain(ChainIdUtils.Base());
    }

    function test_OPTIMISM_E2E_sparkLiquidityLayer() external {
        _runSLLE2ETestsForDomain(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_E2E_sparkLiquidityLayer() external {
        _runSLLE2ETestsForDomain(ChainIdUtils.Unichain());
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _setControllerUpgrade(uint256 chainId, address prevController, address newController) internal {
        chainData[chainId].prevController = prevController;
        chainData[chainId].newController  = newController;
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

        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            MainnetController(ctx.controller).LIMIT_4626_DEPOSIT(),
            vault
        );

        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
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
        // Using 100 instead of 1 to avoid share validation issue.
        try IMetaMorpho(p.vault).feeRecipient() {
            address asset = IERC4626(p.vault).asset();
            deal(asset, address(p.ctx.proxy), 100);
            vm.prank(p.ctx.relayer);
            MainnetController(p.ctx.controller).depositERC4626(p.vault, 100);
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

        uint256 acceptableDust = 2;

        // TODO: Figure out how to make this more robust, this is from Fluid because of very small amounts
        if (startingAssets > acceptableDust && startingShares > acceptableDust) {
            // Assert value accrual
            assertGt(vault.convertToAssets(vault.balanceOf(address(p.ctx.proxy))), startingAssets - acceptableDust);
            assertGt(vault.balanceOf(address(p.ctx.proxy)),                        startingShares - acceptableDust);
        } else {
            assertGe(vault.convertToAssets(vault.balanceOf(address(p.ctx.proxy))), startingAssets);
            assertGe(vault.balanceOf(address(p.ctx.proxy)),                        startingShares);
        }
    }

    function _testAaveOnboarding(
        address aToken,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        address underlying = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        MainnetController controller = MainnetController(ctx.controller);

        // Note: Aave signature is the same for mainnet and foreign
        deal(underlying, address(ctx.proxy), expectedDepositAmount);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  aToken);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), aToken);

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

        address pool = IATokenLike(p.vault).POOL();

        // Withdraw funds to avoid supply caps getting hit
        if (IAToken(p.vault).balanceOf(address(p.ctx.proxy)) > 0) {
            uint256 maxWithdrawAmount =
                IAToken(p.vault).balanceOf(address(p.ctx.proxy)) > asset.balanceOf(p.vault)
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

        assertEq(asset.allowance(address(p.ctx.proxy), pool), 0);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey),  depositLimit - p.depositAmount);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);

        assertApproxEqAbs(
            IERC20(p.vault).balanceOf(address(p.ctx.proxy)),
            startingATokenBalance + p.depositAmount,
            p.tolerance
        );

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

        // Assert at least 0.3% interest accrued (3.6% APY)
        assertGe(
            syrup.convertToAssets(v.shares) - v.positionAssets,
            v.positionAssets * 0.003e18 / 1e18
        );

        /********************************************/
        /*** Step 4: Request redemption of shares ***/
        /********************************************/

        address withdrawalManager = poolManager.withdrawalManager();

        v.totalEscrowedShares = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(withdrawalManager),    v.totalEscrowedShares);
        assertEq(syrup.balanceOf(address(p.ctx.proxy)), v.startingShares + v.shares);

        assertEq(syrup.allowance(address(p.ctx.proxy), withdrawalManager), 0);

        vm.prank(p.ctx.relayer);
        controller.requestMapleRedemption(address(syrup), v.shares);

        assertEq(syrup.balanceOf(withdrawalManager),    v.totalEscrowedShares + v.shares);
        assertEq(syrup.balanceOf(address(p.ctx.proxy)), v.startingShares);

        assertEq(syrup.allowance(address(p.ctx.proxy), withdrawalManager), 0);

        /***************************************************/
        /*** Step 5: Process redemption and check result ***/
        /***************************************************/

        skip(1 days);  // Warp to simulate redemption being processed

        v.withdrawAmount = syrup.convertToAssets(v.shares);

        // Need to process withdrawals for all shares, including existing users in the WM.
        uint256 totalShares         = IWithdrawalManagerLike(withdrawalManager).totalShares();
        uint256 remainingWithdrawal = syrup.convertToAssets(totalShares);

        vm.startPrank(poolManager.poolDelegate());

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

        IWithdrawalManagerLike(withdrawalManager).processRedemptions(totalShares);

        vm.stopPrank();

        // Assert at least 0.3% of value was generated (3.6% APY) (approximated because of extra day)
        assertGe(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount * 1.003e18 / 1e18);
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

        vars.swapKey     = RateLimitHelpers.makeAddressKey(vars.controller.LIMIT_CURVE_SWAP(),     pool);
        vars.depositKey  = RateLimitHelpers.makeAddressKey(vars.controller.LIMIT_CURVE_DEPOSIT(),  pool);
        vars.withdrawKey = RateLimitHelpers.makeAddressKey(vars.controller.LIMIT_CURVE_WITHDRAW(), pool);

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

            vars.withdrawAmounts[0] =
                vars.lpBalance *
                vars.pool.balances(0) *
                (maxSlippage + 0.001e18) /
                vars.pool.get_virtual_price() /
                vars.pool.totalSupply();

            vars.withdrawAmounts[1] =
                vars.lpBalance *
                vars.pool.balances(1) *
                (maxSlippage + 0.001e18) /
                vars.pool.get_virtual_price() /
                vars.pool.totalSupply();

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

        if (v.depositLimit > 0) {
            IRateLimits.RateLimitData memory data = p.ctx.rateLimits.getRateLimitData(
                RateLimitHelpers.makeAddressKey(
                    MainnetController(p.ctx.controller).LIMIT_CURVE_SWAP(),
                    p.pool
                )
            );

            assertGt(data.maxAmount, 0);
        }

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

        address pocket = IPSMLike(p.psm).pocket();

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

        skip(10 days);  // Recharge rate limits

        IERC20 asset = IERC20(p.asset);

        uint256 transferLimit   = p.ctx.rateLimits.getCurrentRateLimit(p.transferKey);
        uint256 transferAmount1 = p.transferAmount / 4;
        uint256 transferAmount2 = p.transferAmount - transferAmount1;

        uint256 destinationBalance = asset.balanceOf(p.destination);

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
        assertEq(asset.balanceOf(p.destination),        destinationBalance);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit);

        vm.prank(p.ctx.relayer);
        controller.transferAsset(address(asset), p.destination, transferAmount1);

        if (address(asset) == Ethereum.USCC && p.destination == Ethereum.USCC) {
            assertEq(asset.balanceOf(p.destination), 0);  // USCC is burned on transfer to USCC
        } else {
            assertEq(asset.balanceOf(p.destination), destinationBalance + transferAmount1);
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
            assertEq(asset.balanceOf(p.destination), destinationBalance + transferAmount1 + transferAmount2);
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

        uint256 depositLimit = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);

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

        assertApproxEqAbs(vault.assetsOf(user), p.userVaultAmount, p.tolerance);

        // TODO: Update this once the spell is live
        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        try vault.setVsr(1.000000001547125957863212448e27) {
        } catch {
            vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
            try vault.setVsr(1.000000001547125957863212448e27) {
            } catch {
                vm.prank(Avalanche.ALM_PROXY_FREEZABLE);
                vault.setVsr(1.000000001547125957863212448e27);
            }
        }

        skip(1 days);

        assertEq(asset.balanceOf(user),           0);
        assertEq(asset.balanceOf(address(vault)), assetBalanceVault + p.userVaultAmount);

        assertEq(vault.totalSupply(),   vaultTotalSupply + shares);
        assertEq(vault.balanceOf(user), shares);
        assertGt(vault.assetsOf(user),  p.userVaultAmount);

        vm.prank(user);
        vault.redeem(shares, user, user);

        assertGt(asset.balanceOf(user),           p.userVaultAmount);
        assertLt(asset.balanceOf(address(vault)), assetBalanceVault);

        assertEq(vault.totalSupply(),   vaultTotalSupply);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.assetsOf(user),  0);
    }

    function _testPSM3Integration(PSM3E2ETestParams memory p) internal {
        IPSM3Like psm   = IPSM3Like(p.psm3);
        IERC20    asset = IERC20(p.asset);

        skip(1 days);

        deal(address(asset), address(p.ctx.proxy), p.depositAmount);

        uint256 depositLimit  = p.ctx.rateLimits.getCurrentRateLimit(p.depositKey);
        uint256 withdrawLimit = p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey);

        bool unlimitedDeposit  = depositLimit == type(uint256).max;
        bool unlimitedWithdraw = withdrawLimit == type(uint256).max;

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        if (!unlimitedDeposit) {
            vm.prank(p.ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            ForeignController(p.ctx.controller).depositPSM(address(asset), depositLimit + 1);
        }

        /****************************************************/
        /*** Step 2: Deposit and check resulting position ***/
        /****************************************************/

        uint256 assetBalancePSM = asset.balanceOf(address(psm));
        uint256 startingShares  = psm.shares(address(p.ctx.proxy));
        uint256 startingAssets  = psm.convertToAssets(p.asset, startingShares);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);  // Set by deal
        assertEq(asset.balanceOf(address(psm)),         assetBalancePSM);

        assertEq(psm.shares(address(p.ctx.proxy)),             startingShares);
        assertEq(psm.convertToAssets(p.asset, startingShares), startingAssets);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit);

        vm.prank(p.ctx.relayer);
        uint256 shares = ForeignController(p.ctx.controller).depositPSM(address(asset), p.depositAmount);

        if (!unlimitedDeposit) {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit - p.depositAmount);
        } else {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), type(uint256).max);
        }

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(asset.balanceOf(address(psm)),         assetBalancePSM + p.depositAmount);

        assertEq(psm.shares(address(p.ctx.proxy)), startingShares + shares);

        assertApproxEqAbs(
            psm.convertToAssets(p.asset, startingShares + shares),
            startingAssets + p.depositAmount,
            p.tolerance
        );

        /*************************************************/
        /*** Step 3: Warp to check rate limit recharge ***/
        /*************************************************/

        skip(10 days);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), depositLimit);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.depositKey), p.ctx.rateLimits.getRateLimitData(p.depositKey).maxAmount);

        /*****************************************************/
        /*** Step 4: Withdraw and check resulting position ***/
        /*****************************************************/

        assetBalancePSM = asset.balanceOf(address(psm));
        startingShares  = psm.shares(address(p.ctx.proxy));
        startingAssets  = psm.convertToAssets(p.asset, startingShares);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(asset.balanceOf(address(psm)),         assetBalancePSM);

        assertEq(psm.shares(address(p.ctx.proxy)),             startingShares);
        assertEq(psm.convertToAssets(p.asset, startingShares), startingAssets);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit);

        vm.prank(p.ctx.relayer);
        shares = ForeignController(p.ctx.controller).withdrawPSM(address(asset), p.depositAmount);

        assertEq(asset.balanceOf(address(p.ctx.proxy)), p.depositAmount);
        assertEq(asset.balanceOf(address(psm)),         assetBalancePSM - p.depositAmount);

        uint256 sharesBurned = startingShares - psm.shares(address(p.ctx.proxy));

        assertApproxEqAbs(
            psm.convertToAssets(p.asset, sharesBurned),
            p.depositAmount,
            p.tolerance
        );

        if (!unlimitedWithdraw) {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit - p.depositAmount);
        } else {
            assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), type(uint256).max);
        }

        /**************************************************/
        /*** Step 5: Warp to check rate limit recharge ***/
        /**************************************************/

        skip(10 days);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), withdrawLimit);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.withdrawKey), p.ctx.rateLimits.getRateLimitData(p.withdrawKey).maxAmount);
    }

    function _testCCTPIntegration(CCTPE2ETestParams memory p) internal {
        // NOTE: MainnetController and ForeignController share the same CCTP interfaces
        ///      so this works for both.

        skip(10 days);  // Recharge ratelimits

        IERC20 usdc = IERC20(address(MainnetController(p.ctx.controller).usdc()));

        deal(address(usdc), address(p.ctx.proxy), p.transferAmount);

        uint256 transferLimit = p.ctx.rateLimits.getCurrentRateLimit(p.transferKey);

        /********************************/
        /*** Step 1: Check rate limit ***/
        /********************************/

        vm.prank(p.ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(p.ctx.controller).transferUSDCToCCTP(transferLimit + 1, p.cctpId);

        /**************************************************/
        /*** Step 2: Transfer and check resulting state ***/
        /**************************************************/

        uint256 totalSupply = usdc.totalSupply();

        assertEq(usdc.balanceOf(address(p.ctx.proxy)), p.transferAmount);
        assertEq(usdc.totalSupply(),                   totalSupply);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit);

        vm.prank(p.ctx.relayer);
        MainnetController(p.ctx.controller).transferUSDCToCCTP(p.transferAmount, p.cctpId);

        assertEq(usdc.balanceOf(address(p.ctx.proxy)), 0);
        assertEq(usdc.totalSupply(),                   totalSupply - p.transferAmount);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit - p.transferAmount);

        /**************************************************/
        /*** Step 3: Warp to check rate limit recharge ***/
        /**************************************************/

        skip(10 days);

        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), transferLimit);
        assertEq(p.ctx.rateLimits.getCurrentRateLimit(p.transferKey), p.ctx.rateLimits.getRateLimitData(p.transferKey).maxAmount);

    }

    function _getEvents(uint256 chainId, address target, bytes32 topic0) internal returns (VmSafe.EthGetLogs[] memory logs) {
        return _getEvents(chainId, target, topic0, 0);
    }

    function _getEvents(uint256 chainId, address target, bytes32 topic0, uint256 retryCount) internal returns (VmSafe.EthGetLogs[] memory logs) {
        string memory apiKey = vm.envString("ETHERSCAN_API_KEY_SPELLS");

        require(retryCount < 4, "Etherscan API returned non-success status");

        string[] memory inputs = new string[](8);
        inputs[0] = "curl";
        inputs[1] = "-s";
        inputs[2] = "--request";
        inputs[3] = "GET";
        inputs[4] = "--url";
        inputs[5] = string(
            abi.encodePacked(
                "https://api.etherscan.io/v2/api?",
                "chainid=",
                vm.toString(chainId),
                "&module=logs&action=getLogs",
                "&fromBlock=0",
                "&toBlock=latest",
                "&address=",
                vm.toString(target),
                "&topic0=",
                vm.toString(topic0),
                "&page=1",
                "&offset=1000",
                "&apikey=",
                apiKey
            )
        );
        inputs[6] = "--header";
        inputs[7] = "accept: application/json";

        string memory response;

        for (uint256 i; i < 10; i++) {
            response = string(vm.ffi(inputs));

            if (_isEqual(vm.parseJsonString(response, string(abi.encodePacked(".message"))), "NOTOK")) {
                vm.sleep(1000);  // Prevent rate limiting from Etherscan (5 calls/second)
                continue;
            }

            break;
        }

        // Get Result Array Length
        uint256 i = 0;
        for(; i < 1000; i++) {
            try vm.parseJsonAddress(response, string(abi.encodePacked(".result[", vm.toString(i), "].address"))) {
            } catch {
                logs = new VmSafe.EthGetLogs[](i);
                break;
            }
        }

        for(uint256 j; j < i; ++j) {
            // Set unused fields to 0 to save computation
            logs[j] = VmSafe.EthGetLogs({
                emitter:          vm.parseJsonAddress(response,      string(abi.encodePacked(".result[", vm.toString(j), "].address"))),
                topics:           vm.parseJsonBytes32Array(response, string(abi.encodePacked(".result[", vm.toString(j), "].topics"))),
                data:             vm.parseJsonBytes(response,        string(abi.encodePacked(".result[", vm.toString(j), "].data"))),
                blockNumber:      uint64(0),
                blockHash:        bytes32(0),
                transactionHash:  bytes32(0),
                transactionIndex: uint64(0),
                logIndex:         uint8(0),
                removed:          false
            });
        }
    }

    function _testControllerUpgrade(address oldController, address newController) internal {
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

        assertEq(controller.hasRole(relayerRole, ctx.relayer),                            false);
        assertEq(controller.hasRole(relayerRole, Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), false);  // Address same on all chains
        assertEq(controller.hasRole(freezerRole, ctx.freezer),                            false);

        if (block.chainid == ChainIdUtils.Ethereum()) {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(address(0)));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),    SLLHelpers.addrToBytes32(address(0)));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  0);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS), 0);

            // New maxSlippages
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDC),  0);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDE),  0);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDS),  0);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDT),  0);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_PRIME_USDS), 0);

            assertEq(controller.maxSlippages(SparkLend.DAI_SPTOKEN),      0);
            assertEq(controller.maxSlippages(SparkLend.PYUSD_SPTOKEN),    0);
            assertEq(controller.maxSlippages(SparkLend.WETH_SPTOKEN),     0);
            assertEq(controller.maxSlippages(SparkLend.USDC_SPTOKEN),     0);
            assertEq(controller.maxSlippages(SparkLend.USDS_SPTOKEN),     0);
            assertEq(controller.maxSlippages(SparkLend.USDT_SPTOKEN),     0);

            // New maxExchangeRates
            assertEq(controller.maxExchangeRates(Ethereum.FLUID_SUSDS),          0);
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_DAI_1),   0);
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDC_BC), 0);
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDS),    0);
            assertEq(controller.maxExchangeRates(Ethereum.SUSDE),                0);
            assertEq(controller.maxExchangeRates(Ethereum.SUSDS),                0);
            assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDC),           0);
            assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDT),           0);

        } else {
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(address(0)));

            if (block.chainid == ChainIdUtils.ArbitrumOne()) {
                assertEq(controller.maxSlippages(Arbitrum.ATOKEN_USDC), 0);

                assertEq(controller.maxExchangeRates(Arbitrum.FLUID_SUSDS), 0);
            } else if (block.chainid == ChainIdUtils.Avalanche()) {
                assertEq(controller.maxSlippages(Avalanche.ATOKEN_CORE_USDC), 0);
            } else if (block.chainid == ChainIdUtils.Base()) {
                assertEq(controller.maxSlippages(Base.ATOKEN_USDC), 0);

                assertEq(controller.maxExchangeRates(Base.MORPHO_VAULT_SUSDC), 0);
                assertEq(controller.maxExchangeRates(Base.FLUID_SUSDS),        0);
            }
        }

        _executeAllPayloadsAndBridges();

        assertEq(ctx.proxy.hasRole(controllerRole, oldController), false);
        assertEq(ctx.proxy.hasRole(controllerRole, newController), true);

        assertEq(ctx.rateLimits.hasRole(controllerRole, oldController), false);
        assertEq(ctx.rateLimits.hasRole(controllerRole, newController), true);

        assertEq(controller.hasRole(relayerRole, ctx.relayer),                            true);
        assertEq(controller.hasRole(relayerRole, Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), true);  // Address same on all chains
        assertEq(controller.hasRole(freezerRole, ctx.freezer),                            true);

        if (block.chainid == ChainIdUtils.Ethereum()) {
            _assertOldControllerEvents(oldController);

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(Base.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),    SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY));

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),    MainnetController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE));

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0.9990e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  0.9985e18);
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS), 0.998e18);

            assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), MainnetController(oldController).maxSlippages(Ethereum.CURVE_SUSDSUSDT));
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC), MainnetController(oldController).maxSlippages(Ethereum.CURVE_PYUSDUSDC));
            assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),  MainnetController(oldController).maxSlippages(Ethereum.CURVE_USDCUSDT));
            assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS), MainnetController(oldController).maxSlippages(Ethereum.CURVE_PYUSDUSDS));

            // New maxSlippages
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDC),  0.99999e18);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDE),  0.99999e18);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDS),  0.99999e18);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDT),  0.99999e18);
            assertEq(controller.maxSlippages(Ethereum.ATOKEN_PRIME_USDS), 0.99999e18);

            assertEq(controller.maxSlippages(SparkLend.DAI_SPTOKEN),   0.99999e18);
            assertEq(controller.maxSlippages(SparkLend.PYUSD_SPTOKEN), 0.99999e18);
            assertEq(controller.maxSlippages(SparkLend.WETH_SPTOKEN),  0.99999e18);
            assertEq(controller.maxSlippages(SparkLend.USDC_SPTOKEN),  0.99999e18);
            assertEq(controller.maxSlippages(SparkLend.USDS_SPTOKEN),  0.99999e18);
            assertEq(controller.maxSlippages(SparkLend.USDT_SPTOKEN),  0.99999e18);

            // New maxExchangeRates
            assertEq(controller.maxExchangeRates(Ethereum.FLUID_SUSDS),          1e37);  // 1e37 is 10e18 * 1e36 / 1e18
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_DAI_1),   1e37);
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDC_BC), 1e25);  // 1e25 is 10e6 * 1e36 / 1e18
            assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDS),    1e37);
            assertEq(controller.maxExchangeRates(Ethereum.SUSDE),                1e37);
            assertEq(controller.maxExchangeRates(Ethereum.SUSDS),                1e37);
            assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDC),           1e37);
            assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDT),           1e37);
        } else {
            VmSafe.EthGetLogs[] memory slippageLogs = _getEvents(block.chainid, oldController, ForeignController.MaxSlippageSet.selector);
            VmSafe.EthGetLogs[] memory cctpLogs     = _getEvents(block.chainid, oldController, ForeignController.MintRecipientSet.selector);
            VmSafe.EthGetLogs[] memory lzLogs       = _getEvents(block.chainid, oldController, ForeignController.LayerZeroRecipientSet.selector);

            if (block.chainid == ChainIdUtils.ArbitrumOne()) {
                assertEq(controller.maxSlippages(Arbitrum.ATOKEN_USDC), 0.99999e18);

                assertEq(controller.maxExchangeRates(Arbitrum.FLUID_SUSDS), 1e37);
            } else if (block.chainid == ChainIdUtils.Avalanche()) {
                assertEq(controller.maxSlippages(Avalanche.ATOKEN_CORE_USDC), 0.99999e18);
            } else if (block.chainid == ChainIdUtils.Base()) {
                assertEq(controller.maxSlippages(Base.ATOKEN_USDC), 0.99999e18);

                assertEq(controller.maxExchangeRates(Base.MORPHO_VAULT_SUSDC), 1e25);
                assertEq(controller.maxExchangeRates(Base.FLUID_SUSDS),        1e37);
            }

            assertEq(slippageLogs.length, 0);
            assertEq(cctpLogs.length,     1);
            assertEq(lzLogs.length,       0);

            assertEq(uint32(uint256(cctpLogs[0].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY));
            assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), ForeignController(oldController).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM));
        }
    }

    function _assertOldControllerEvents(address _oldController) internal {
        MainnetController oldController = MainnetController(_oldController);

        VmSafe.EthGetLogs[] memory slippageLogs  = _getEvents(block.chainid, _oldController, MainnetController.MaxSlippageSet.selector);
        VmSafe.EthGetLogs[] memory cctpLogs      = _getEvents(block.chainid, _oldController, MainnetController.MintRecipientSet.selector);
        VmSafe.EthGetLogs[] memory layerZeroLogs = _getEvents(block.chainid, _oldController, MainnetController.LayerZeroRecipientSet.selector);

        assertEq(slippageLogs.length,  4);
        assertEq(cctpLogs.length,      5);
        assertEq(layerZeroLogs.length, 0);

        assertEq(address(uint160(uint256(slippageLogs[0].topics[1]))), Ethereum.CURVE_SUSDSUSDT);
        assertEq(address(uint160(uint256(slippageLogs[1].topics[1]))), Ethereum.CURVE_PYUSDUSDC);
        assertEq(address(uint160(uint256(slippageLogs[2].topics[1]))), Ethereum.CURVE_USDCUSDT);
        assertEq(address(uint160(uint256(slippageLogs[3].topics[1]))), Ethereum.CURVE_PYUSDUSDS);

        assertEq(oldController.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);
        assertEq(oldController.maxSlippages(Ethereum.CURVE_USDCUSDT),  0.9985e18);
        assertEq(oldController.maxSlippages(Ethereum.CURVE_PYUSDUSDC), 0.9990e18);
        assertEq(oldController.maxSlippages(Ethereum.CURVE_PYUSDUSDS), 0.998e18);

        assertEq(uint32(uint256(cctpLogs[0].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        assertEq(uint32(uint256(cctpLogs[1].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        assertEq(uint32(uint256(cctpLogs[2].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        assertEq(uint32(uint256(cctpLogs[3].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);
        assertEq(uint32(uint256(cctpLogs[4].topics[1])), CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);

        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         SLLHelpers.addrToBytes32(Base.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),    SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY));
    }

    function _testE2ESLLCrossChainForDomain(
        uint256           domainId,
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
        } else if (domainId == ChainIdUtils.Avalanche()) {
            domainUsdc   = IERC20(Avalanche.USDC);
            domainPsm3   = address(0);
            domainCctpId = CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE;
        } else {
            revert("SLL/unknown domain");
        }

        IERC20 usdc = IERC20(Ethereum.USDC);

        uint256 mainnetUsdcProxyBalance = usdc.balanceOf(Ethereum.ALM_PROXY);

        // --- Step 1: Mint and bridge 10m USDC to Base ---

        uint256 usdcAmount = 10_000_000e6;

        vm.startPrank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, domainCctpId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);

        chainData[domainId].domain.selectFork();

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        address domainAlmProxy = address(ctx.proxy);

        uint256 domainUsdcProxyBalance = domainUsdc.balanceOf(domainAlmProxy);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance);

        // FIXME: this is a workaround for the storage/fork issue (https://github.com/foundry-rs/foundry/issues/10296), switch back to _relayMessageOverBridges() when fixed
        //_relayMessageOverBridges();
        CCTPBridgeTesting.relayMessagesToDestination(bridge, true);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);

        if (domainPsm3 != address(0)) {
            uint256 domainUsdcPsmBalance = domainUsdc.balanceOf(domainPsm3);

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
        }

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

        vm.startPrank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance);
    }

    function _testMorphoVaultCreation(
        address               asset,
        string         memory name,
        string         memory symbol,
        MarketParams[] memory markets,
        uint256[]      memory caps,
        uint256               vaultFee,
        uint256               initialDeposit,
        uint256               sllDepositMax,
        uint256               sllDepositSlope
    )
        internal
    {
        require(markets.length == caps.length, "Markets and caps length mismatch");

        // TODO: make constant.
        bytes32 createMetaMorphoSig = keccak256("CreateMetaMorpho(address,address,address,uint256,address,string,string,bytes32)");

        // Start the recorder
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        VmSafe.Log[] memory allLogs = RecordedLogs.getLogs();

        // TODO: make below loop a getter with a return to make this all cleaner. Possibly incorporating the zero check.
        address vault;

        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics[0] == createMetaMorphoSig) {
                vault = address(uint160(uint256(allLogs[i].topics[1])));
                break;
            }
        }

        require(vault != address(0), "Vault not found");

        assertEq(IMetaMorpho(vault).asset(),                                    asset);
        assertEq(IMetaMorpho(vault).name(),                                     name);
        assertEq(IMetaMorpho(vault).symbol(),                                   symbol);
        assertEq(IMetaMorpho(vault).timelock(),                                 1 days);
        assertEq(IMetaMorpho(vault).isAllocator(Ethereum.ALM_RELAYER_MULTISIG), true);
        assertEq(IMetaMorpho(vault).supplyQueueLength(),                        1);
        assertEq(IMetaMorpho(vault).owner(),                                    Ethereum.SPARK_PROXY);
        assertEq(IMetaMorpho(vault).feeRecipient(),                             Ethereum.ALM_PROXY);
        assertEq(IMetaMorpho(vault).fee(),                                      vaultFee);

        for (uint256 i = 0; i < markets.length; ++i) {
            MorphoHelpers.assertMorphoCap(vault, markets[i], caps[i]);
        }

        assertEq(
            Id.unwrap(IMetaMorpho(vault).supplyQueue(0)),
            Id.unwrap(MarketParamsLib.id(SLLHelpers.morphoIdleMarket(asset)))
        );

        MorphoHelpers.assertMorphoCap(vault, SLLHelpers.morphoIdleMarket(asset), type(uint184).max);

        assertEq(IMetaMorpho(vault).totalAssets(),    initialDeposit);
        assertEq(IERC20(vault).balanceOf(address(1)), initialDeposit * 1e18 / 10 ** IERC20Metadata(asset).decimals());

        if (sllDepositMax == 0 || sllDepositSlope == 0) return;

        _testERC4626Onboarding(vault, sllDepositMax / 10, sllDepositMax, sllDepositSlope, 10, true);
    }

    function _testVaultConfiguration(
        address asset,
        string  memory name,
        string  memory symbol,
        uint64  rho,
        address vault_,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositCap,
        uint256 amount
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ISparkVaultV2Like vault = ISparkVaultV2Like(vault_);

        bytes32 takeKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_SPARK_VAULT_TAKE(),
            vault_
        );
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            vault.asset(),
            vault_
        );

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),         true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Ethereum.ALM_PROXY),           false);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        0);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         0);

        assertEq(vault.asset(),      asset);
        assertEq(vault.name(),       name);
        assertEq(vault.decimals(),   IERC20Metadata(vault.asset()).decimals());
        assertEq(vault.symbol(),     symbol);
        assertEq(vault.rho(),        rho);
        assertEq(vault.chi(),        uint192(1e27));
        assertEq(vault.vsr(),        1e27);
        assertEq(vault.minVsr(),     1e27);
        assertEq(vault.maxVsr(),     1e27);
        assertEq(vault.depositCap(), 0);
        assertLt(vault.rho(),        block.timestamp);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 0);

        _executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),         true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Ethereum.ALM_PROXY),           true);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        1);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         1);

        assertEq(vault.minVsr(),     minVsr);
        assertEq(vault.maxVsr(),     maxVsr);
        assertEq(vault.depositCap(), depositCap);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        vm.startPrank(Ethereum.ALM_PROXY_FREEZABLE);

        vm.expectRevert("SparkVault/vsr-too-low");
        vault.setVsr(minVsr - 1);

        vault.setVsr(minVsr);

        vm.expectRevert("SparkVault/vsr-too-high");
        vault.setVsr(maxVsr + 1);

        vault.setVsr(maxVsr);

        vm.stopPrank();

        uint256 initialChi = vault.nowChi();

        vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
        vault.setVsr(TEN_PCT_APY);

        skip(1 days);

        assertGt(vault.nowChi(), initialChi);

        _testSparkVaultV2Integration(SparkVaultV2E2ETestParams({
            ctx:             ctx,
            vault:           vault_,
            takeKey:         takeKey,
            transferKey:     transferKey,
            takeAmount:      amount,
            transferAmount:  amount,
            userVaultAmount: amount,
            tolerance:       10
        }));
    }

    /**********************************************************************************************/
    /*** Test runners                                                                           ***/
    /**********************************************************************************************/

    function _runE2ESLLCrossChainTestForAllDomains(bool isPostExecution) internal {
        SparkLiquidityLayerContext memory ctxMainnet = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum());

        string memory prefix = isPostExecution ? "POST EXECUTION" : "PRE EXECUTION";

        console2.log(prefix, "E2E cross chain tests starting");

        for (uint256 i = 0; i < allChains.length; ++i) {
            if (allChains[i] == ChainIdUtils.Ethereum() || allChains[i] == ChainIdUtils.Gnosis()) continue;

            console2.log("Testing cross chain setup for", ChainIdUtils.toDomainString(allChains[i]));

            uint256 domainChainId = chainData[allChains[i]].domain.chain.chainId;

            SparkLiquidityLayerContext memory domainCtx = _getSparkLiquidityLayerContext(domainChainId);

            _testE2ESLLCrossChainForDomain(
                domainChainId,
                MainnetController(isPostExecution ? ctxMainnet.controller : ctxMainnet.prevController),
                ForeignController(isPostExecution ? domainCtx.controller  : domainCtx.prevController)
            );
        }
    }

    // TODO: MDL, this function should be broken up into one function per test.
    function _runSLLE2ETests(
        SparkLiquidityLayerContext memory ctx,
        SLLIntegration             memory integration
    )
        internal
    {
        uint256 snapshot = vm.snapshot();

        // TODO: Alphabetical order
        if (integration.category == Category.AAVE) {
            console2.log("Running SLL E2E test for", integration.label);

            address asset         = IAToken(integration.integration).UNDERLYING_ASSET_ADDRESS();
            uint256 depositAmount = (asset == Ethereum.WETH ? 1_000 : 5_000_000) * 10 ** IERC20Like(asset).decimals();

            _testAaveIntegration(E2ETestParams({
                ctx:           ctx,
                vault:         integration.integration,
                depositAmount: depositAmount,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.ERC4626) {
            console2.log("Running SLL E2E test for", integration.label);

            uint256 decimals = IERC20Metadata(IERC4626(integration.integration).asset()).decimals();

            _testERC4626Integration(E2ETestParams({
                ctx:           ctx,
                vault:         integration.integration,
                depositAmount: 1 * 10 ** decimals,  // Lower to avoid supply cap issues (TODO: Fix)
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CCTP_GENERAL) {
            console2.log("Running SLL E2E test for", integration.label);

            // Must be set to infinite
            assertEq(
                IRateLimits(ctx.rateLimits).getCurrentRateLimit(integration.entryId),
                type(uint256).max
            );
        }

        else if (integration.category == Category.CURVE_LP) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCurveLPIntegration(CurveLPE2ETestParams({
                ctx:            ctx,
                pool:           integration.integration,
                asset0:         ICurvePoolLike(integration.integration).coins(0),
                asset1:         ICurvePoolLike(integration.integration).coins(1),
                depositAmount:  1_000_000e18,  // Amount across both assets
                depositKey:     integration.entryId,
                withdrawKey:    integration.exitId,
                tolerance:      10
            }));
        }

        else if (integration.category == Category.CURVE_SWAP) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCurveSwapIntegration(CurveSwapE2ETestParams({
                ctx:            ctx,
                pool:           integration.integration,
                asset0:         ICurvePoolLike(integration.integration).coins(0),
                asset1:         ICurvePoolLike(integration.integration).coins(1),
                swapAmount:     1e18,  // Normalized to 18 decimals (TODO: Figure out how to raise, getting slippage reverts)
                swapKey:        integration.entryId
            }));
        }

        else if (integration.category == Category.MAPLE) {
            console2.log("Running SLL E2E test for", integration.label);

            _testMapleIntegration(MapleE2ETestParams({
                ctx:           ctx,
                vault:         integration.integration,
                depositAmount: 1_000_000e6,
                depositKey:    integration.entryId,
                redeemKey:     integration.exitId,
                withdrawKey:   integration.exitId2,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.PSM) {
            console2.log("Running SLL E2E test for", integration.label);

            _testPSMIntegration(PSMSwapE2ETestParams({
                ctx:        ctx,
                psm:        integration.integration,
                swapAmount: 100_000_000e6,
                swapKey:    integration.entryId
            }));
        }

        else if (integration.category == Category.FARM) {
            console2.log("Running SLL E2E test for", integration.label);

            _testFarmIntegration(FarmE2ETestParams({
                ctx:           ctx,
                farm:          integration.integration,
                depositAmount: 100_000_000e6,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId
            }));
        }

        else if (integration.category == Category.ETHENA) {
            console2.log("Running SLL E2E test for", integration.label);

            _testEthenaIntegration(EthenaE2ETestParams({
                ctx:           ctx,
                depositAmount: 1_000_000e6,
                mintKey:       integration.entryId,
                depositKey:    integration.entryId2,
                cooldownKey:   integration.exitId,
                burnKey:       integration.exitId2,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CORE) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCoreIntegration(CoreE2ETestParams({
                ctx:        ctx,
                mintAmount: 100_000_000e6,
                burnAmount: 50_000_000e6,
                mintKey:    integration.entryId
            }));
        }

        else if (integration.category == Category.CENTRIFUGE) {
            console2.log("Skipping SLL E2E test for", integration.label, "[DEPRECATED] due to protocol upgrade");
        }

        else if (integration.category == Category.BUIDL) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address depositDestination,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address, address));

            _testBUIDLIntegration(BUIDLE2ETestParams({
                ctx:                 ctx,
                depositAsset:        depositAsset,
                depositDestination:  depositDestination,
                depositAmount:       100_000_000e6,
                depositKey:          integration.entryId,
                withdrawAsset:       withdrawAsset,
                withdrawDestination: withdrawDestination,
                withdrawAmount:      100_000_000e6,
                withdrawKey:         integration.exitId
            }));
        }

        else if (integration.category == Category.TRANSFER_ASSET) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address asset,
                address destination
            ) = abi.decode(integration.extraData, (address, address));

            _testTransferAssetIntegration(TransferAssetE2ETestParams({
                ctx:            ctx,
                asset:          asset,
                destination:    destination,
                transferKey:    integration.entryId,
                transferAmount: 100_000 * 10 ** IERC20Metadata(asset).decimals()
            }));
        }

        else if (integration.category == Category.SUPERSTATE) {
            console2.log("Skipping SLL E2E test for", integration.label, "[DEPRECATED] due to protocol upgrade");
        }

        else if (integration.category == Category.SUPERSTATE_USCC) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address depositDestination,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address, address));

            _testSuperstateUsccIntegration(SuperstateUsccE2ETestParams({
                ctx:                 ctx,
                depositAsset:        depositAsset,
                depositDestination:  depositDestination,
                depositAmount:       1_000_000e6,
                depositKey:          integration.entryId,
                withdrawAsset:       withdrawAsset,
                withdrawDestination: withdrawDestination,
                withdrawAmount:      1_000_000e6,
                withdrawKey:         integration.exitId
            }));
        }

        else if (integration.category == Category.SPARK_VAULT_V2) {
            console2.log("Running SLL E2E test for", integration.label);

            address asset = ISparkVaultV2Like(integration.integration).asset();

            uint256 amount          = address(asset) == Ethereum.WETH ? 1_000 : 10_000_000;
            uint256 decimals        = IERC20Metadata(asset).decimals();
            uint256 userVaultAmount = (address(asset) == Ethereum.WETH ? 1_000 : 1_000_000) * 10 ** decimals;

            if (userVaultAmount > ISparkVaultV2Like(integration.integration).maxDeposit(address(this))) {
                uint256 depositCap = ISparkVaultV2Like(integration.integration).depositCap();

                // NOTE Setting Cap to 2 * userVaultAmount because totalAssets > depositCap due to rewards when calculating maxDeposit()
                vm.prank(Ethereum.SPARK_PROXY);
                ISparkVaultV2Like(integration.integration).setDepositCap(depositCap + 2 * userVaultAmount);
            }

            _testSparkVaultV2Integration(SparkVaultV2E2ETestParams({
                ctx:             ctx,
                vault:           integration.integration,
                takeKey:         integration.entryId,
                transferKey:     integration.exitId,
                takeAmount:      amount * 10 ** decimals,
                transferAmount:  amount * 10 ** decimals,
                userVaultAmount: userVaultAmount,
                tolerance:       10
            }));
        }

        else if (integration.category == Category.PSM3) {
            console2.log("Running SLL E2E test for", integration.label);

            address asset = abi.decode(integration.extraData, (address));

            _testPSM3Integration(PSM3E2ETestParams({
                ctx:           ctx,
                psm3:          integration.integration,
                asset:         asset,
                depositAmount: 10_000_000 * 10 ** IERC20Metadata(asset).decimals(),
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CCTP) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCCTPIntegration(CCTPE2ETestParams({
                ctx:            ctx,
                cctp:           integration.integration,
                transferAmount: 50_000_000e6,
                transferKey:    integration.entryId,
                cctpId:         abi.decode(integration.extraData, (uint32))
            }));
        }

        else {
            console2.log("NOT running SLL E2E test for", integration.label);
        }

        vm.revertTo(snapshot);
    }

    // TODO: Rename to _runSLLE2ETestsFor and take log init and execution function calls as parameters, execute mainnet as well
    function _runSLLE2ETestsForDomain(uint256 chainId) internal onChain(chainId) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext({ isPostExecution: false });

        bytes32[]        memory rateLimitKeys = _getRateLimitKeys({ isPostExecution: false });
        SLLIntegration[] memory integrations  = _getPreExecutionIntegrations();

        _checkRateLimitKeys(integrations, rateLimitKeys);

        for (uint256 i = 0; i < integrations.length; ++i) {
            _runSLLE2ETests(ctx, integrations[i]);
        }

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        chainData[chainId].domain.selectFork();

        rateLimitKeys = _getRateLimitKeys({ isPostExecution: true });
        integrations  = _getPostExecutionIntegrations(integrations);

        _checkRateLimitKeys(integrations, rateLimitKeys);

        ctx = _getSparkLiquidityLayerContext({ isPostExecution: true });

        for (uint256 i = 0; i < integrations.length; ++i) {
            _runSLLE2ETests(ctx, integrations[i]);
        }
    }

    /**********************************************************************************************/
    /*** Data populating helper functions                                                       ***/
    /**********************************************************************************************/

    function _getRateLimitKeys(bool isPostExecution) internal returns (bytes32[] memory rateLimitKeys) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IRateLimits.RateLimitDataSet.selector;

        address rateLimits = address(_getSparkLiquidityLayerContext().rateLimits);

        VmSafe.EthGetLogs[] memory allLogs = _getEvents(block.chainid, rateLimits, topics[0]);

        rateLimitKeys = new bytes32[](0);

        // Collect unique keys from topics[1] (`key`)
        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics.length <= 1) continue;

            ( uint256 maxAmount, , , ) = abi.decode(allLogs[i].data, (uint256,uint256,uint256,uint256));

            // If the last event has a max amount of 0, remove the key and
            // consider the rate limit as offboarded
            rateLimitKeys = maxAmount == 0
                ? _removeIfContaining(rateLimitKeys, allLogs[i].topics[1])
                : _appendIfNotContaining(rateLimitKeys, allLogs[i].topics[1]);
        }

        // Collects all new logs from rate limits after spell is executed
        if (isPostExecution) {
            VmSafe.Log[] memory newLogs = vm.getRecordedLogs();

            for (uint256 i = 0; i < newLogs.length; ++i) {
                if (newLogs[i].topics[0] != IRateLimits.RateLimitDataSet.selector) continue;

                ( uint256 maxAmount, , , ) = abi.decode(newLogs[i].data, (uint256,uint256,uint256,uint256));

                // If the last event has a max amount of 0, remove the key and
                // consider the rate limit as offboarded
                rateLimitKeys = maxAmount == 0
                    ? _removeIfContaining(rateLimitKeys, newLogs[i].topics[1])
                    : _appendIfNotContaining(rateLimitKeys, newLogs[i].topics[1]);
            }
        }
    }

    function _getPreExecutionIntegrationsMainnet() internal view returns (SLLIntegration[] memory integrations) {
        integrations = new SLLIntegration[](44);

        integrations[0]  = _createAaveIntegration("AAVE-CORE_AUSDT",    AAVE_CORE_AUSDT);
        integrations[1]  = _createAaveIntegration("AAVE-DAI_SPTOKEN",   SparkLend.DAI_SPTOKEN);
        integrations[2]  = _createAaveIntegration("AAVE-ETH_LIDO_USDS", AAVE_ETH_LIDO_USDS);
        integrations[3]  = _createAaveIntegration("AAVE-ETH_USDC",      AAVE_ETH_USDC);
        integrations[4]  = _createAaveIntegration("AAVE-ETH_USDS",      AAVE_ETH_USDS);
        integrations[5]  = _createAaveIntegration("AAVE-PYUSD_SPTOKEN", SparkLend.PYUSD_SPTOKEN);
        integrations[6]  = _createAaveIntegration("AAVE-SPETH",         SparkLend.WETH_SPTOKEN);
        integrations[7]  = _createAaveIntegration("AAVE-USDC_SPTOKEN",  SparkLend.USDC_SPTOKEN); // SparkLend
        integrations[8]  = _createAaveIntegration("AAVE-USDE_ATOKEN",   USDE_ATOKEN);
        integrations[9]  = _createAaveIntegration("AAVE-USDS_SPTOKEN",  SparkLend.USDS_SPTOKEN);
        integrations[10] = _createAaveIntegration("AAVE-USDT_SPTOKEN",  SparkLend.USDT_SPTOKEN);

        integrations[11] = _createCctpGeneralIntegration("CCTP_GENERAL");

        integrations[12] = _createCctpIntegration("CCTP-ARBITRUM_ONE", CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        integrations[13] = _createCctpIntegration("CCTP-AVALANCHE",    CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);
        integrations[14] = _createCctpIntegration("CCTP-BASE",         CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        integrations[15] = _createCctpIntegration("CCTP-OPTIMISM",     CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        integrations[16] = _createCctpIntegration("CCTP-UNICHAIN",     CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);

        integrations[17] = _createCoreIntegration("CORE-USDS", Ethereum.USDS);

        integrations[18] = _createCurveLpIntegration("CURVE_LP-PYUSDUSDS", Ethereum.CURVE_PYUSDUSDS);
        integrations[19] = _createCurveLpIntegration("CURVE_LP-SUSDSUSDT", Ethereum.CURVE_SUSDSUSDT);

        integrations[20] = _createCurveSwapIntegration("CURVE_SWAP-PYUSDUSDC", Ethereum.CURVE_PYUSDUSDC);
        integrations[21] = _createCurveSwapIntegration("CURVE_SWAP-PYUSDUSDS", Ethereum.CURVE_PYUSDUSDS);
        integrations[22] = _createCurveSwapIntegration("CURVE_SWAP-SUSDSUSDT", Ethereum.CURVE_SUSDSUSDT);
        integrations[23] = _createCurveSwapIntegration("CURVE_SWAP-USDCUSDT",  Ethereum.CURVE_USDCUSDT);

        integrations[24] = _createERC4626Integration("ERC4626-MORPHO_USDC_BC",     MORPHO_USDC_BC);
        integrations[25] = _createERC4626Integration("ERC4626-MORPHO_VAULT_DAI_1", Ethereum.MORPHO_VAULT_DAI_1);
        integrations[26] = _createERC4626Integration("ERC4626-MORPHO_VAULT_USDS",  Ethereum.MORPHO_VAULT_USDS);
        integrations[27] = _createERC4626Integration("ERC4626-SUSDS",              Ethereum.SUSDS);
        integrations[28] = _createERC4626Integration("ERC4626-FLUID_SUSDS",        Ethereum.FLUID_SUSDS);  // TODO: Fix FluidLiquidityError

        integrations[29] = _createEthenaIntegration("ETHENA-SUSDE", Ethereum.SUSDE);

        integrations[30] = _createFarmIntegration("FARM-USDS_SPK_FARM", USDS_SPK_FARM);

        integrations[31] = _createMapleIntegration("MAPLE-SYRUP_USDC", Ethereum.SYRUP_USDC);
        integrations[32] = _createMapleIntegration("MAPLE-SYRUP_USDT", Ethereum.SYRUP_USDT);

        integrations[33] = _createPsmIntegration("PSM-USDS", Ethereum.PSM);

        integrations[34] = _createTransferAssetIntegration("REWARDS_TRANSFER-MORPHO_TOKEN", MORPHO_TOKEN, SPARK_MULTISIG);
        integrations[35] = _createTransferAssetIntegration("REWARDS_TRANSFER-SYRUP",        SYRUP,        SPARK_MULTISIG);

        integrations[36] = _createSparkVaultV2Integration("SPARK_VAULT_V2-SPETH",  Ethereum.SPARK_VAULT_V2_SPETH);
        integrations[37] = _createSparkVaultV2Integration("SPARK_VAULT_V2-SPUSDC", Ethereum.SPARK_VAULT_V2_SPUSDC);
        integrations[38] = _createSparkVaultV2Integration("SPARK_VAULT_V2-SPUSDT", Ethereum.SPARK_VAULT_V2_SPUSDT);

        integrations[39] = _createSuperstateIntegration("SUPERSTATE-USTB", Ethereum.USDC, Ethereum.USTB, Ethereum.USTB);

        integrations[40] = _createSuperstateUsccIntegration("SUPERSTATE_TRANSFER-USCC", Ethereum.USDC, Ethereum.USCC, USCC_DEPOSIT, Ethereum.USCC);

        integrations[41] = _createTransferAssetIntegration("B2C2_TRANSFER-USDC",  Ethereum.USDC,  B2C2);
        integrations[42] = _createTransferAssetIntegration("B2C2_TRANSFER-USDT",  Ethereum.USDT,  B2C2);
        integrations[43] = _createTransferAssetIntegration("B2C2_TRANSFER-PYUSD", Ethereum.PYUSD, B2C2);
    }

    function _getPreExecutionIntegrationsBasicPsm3(
        address psm,
        address usdc,
        address usds,
        address susds
    )
        internal view returns (SLLIntegration[] memory integrations)
    {
        integrations = new SLLIntegration[](5);

        integrations[0] = _createPsm3Integration("PSM3-USDC",  psm, usdc);
        integrations[1] = _createPsm3Integration("PSM3-USDS",  psm, usds);
        integrations[2] = _createPsm3Integration("PSM3-SUSDS", psm, susds);

        integrations[3] = _createCctpIntegration("CCTP-ETHEREUM", CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        integrations[4] = _createCctpGeneralIntegration("CCTP_GENERAL");

        return integrations;
    }

    function _getPreExecutionIntegrationsArbitrumOne() internal view returns (SLLIntegration[] memory integrations) {
        SLLIntegration[] memory basicIntegrations = _getPreExecutionIntegrationsBasicPsm3(Arbitrum.PSM3, Arbitrum.USDC, Arbitrum.USDS, Arbitrum.SUSDS);

        integrations = new SLLIntegration[](basicIntegrations.length + 2);

        for (uint256 i = 0; i < basicIntegrations.length; ++i) {
            integrations[i] = basicIntegrations[i];
        }

        integrations[5] = _createERC4626Integration("ERC4626-FLUID_SUSDS", FLUID_SUSDS_ARBITRUM);

        integrations[6] = _createAaveIntegration("AAVE-ATOKEN_USDC", Arbitrum.ATOKEN_USDC);

        return integrations;
    }

    function _getPreExecutionIntegrationsBase() internal view returns (SLLIntegration[] memory integrations) {
        SLLIntegration[] memory basicIntegrations = _getPreExecutionIntegrationsBasicPsm3(Base.PSM3, Base.USDC, Base.USDS, Base.SUSDS);

        integrations = new SLLIntegration[](basicIntegrations.length + 4);

        for (uint256 i = 0; i < basicIntegrations.length; ++i) {
            integrations[i] = basicIntegrations[i];
        }

        integrations[5] = _createERC4626Integration("ERC4626-MORPHO_VAULT_SUSDC", Base.MORPHO_VAULT_SUSDC);
        integrations[6] = _createERC4626Integration("ERC4626-FLUID_SUSDS",        Base.FLUID_SUSDS);

        integrations[7] = _createAaveIntegration("AAVE-ATOKEN_USDC", Base.ATOKEN_USDC);

        integrations[8] = _createTransferAssetIntegration("REWARDS_TRANSFER-MORPHO_TOKEN", BASE_MORPHO_TOKEN, BASE_SPARK_MULTISIG);

        return integrations;
    }

    function _getPreExecutionIntegrationsAvalanche() internal view returns (SLLIntegration[] memory integrations) {
        integrations = new SLLIntegration[](4);

        integrations[0] = _createCctpIntegration("CCTP-ETHEREUM", CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        integrations[1] = _createCctpGeneralIntegration("CCTP_GENERAL");

        integrations[2] = _createSparkVaultV2Integration("SPARK_VAULT_V2-SPUSDC", Avalanche.SPARK_VAULT_V2_SPUSDC);

        integrations[3] = _createAaveIntegration("AAVE-ATOKEN_USDC", AAVE_ATOKEN_USDC);

        return integrations;
    }

    // TODO: Use domain specific helper function naming here
    function _getPreExecutionIntegrations() internal view returns (SLLIntegration[] memory integrations) {
        if (block.chainid == ChainIdUtils.Avalanche()) {
            return _getPreExecutionIntegrationsAvalanche();
        }

        if (block.chainid == ChainIdUtils.ArbitrumOne()) {
            return _getPreExecutionIntegrationsArbitrumOne();
        }

        if (block.chainid == ChainIdUtils.Base()) {
            return _getPreExecutionIntegrationsBase();
        }

        if (block.chainid == ChainIdUtils.Ethereum()) {
            return _getPreExecutionIntegrationsMainnet();
        }

        if (block.chainid == ChainIdUtils.Optimism()) {
            return _getPreExecutionIntegrationsBasicPsm3(Optimism.PSM3, Optimism.USDC, Optimism.USDS, Optimism.SUSDS);
        }

        if (block.chainid == ChainIdUtils.Unichain()) {
            return _getPreExecutionIntegrationsBasicPsm3(Unichain.PSM3, Unichain.USDC, Unichain.USDS, Unichain.SUSDS);
        }

        revert("Invalid chainId");
    }

    function _getPostExecutionIntegrationsNoChange(SLLIntegration[] memory integrations)
        internal pure returns (SLLIntegration[] memory newIntegrations)
    {
        newIntegrations = new SLLIntegration[](integrations.length);

        for (uint256 i = 0; i < integrations.length; ++i) {
            newIntegrations[i] = integrations[i];
        }
    }

    function _getPostExecutionIntegrations(
        SLLIntegration[] memory integrations
    )
        internal view returns (SLLIntegration[] memory newIntegrations)
    {
        newIntegrations = new SLLIntegration[](integrations.length);

        if (block.chainid == ChainIdUtils.Ethereum()) {
            return _getPostExecutionIntegrationsMainnet(integrations);
        }

        // TODO: Use a function selector getter here to dynamically call the correct helper function based on chainId.
        if (
            block.chainid == ChainIdUtils.ArbitrumOne() ||
            block.chainid == ChainIdUtils.Avalanche() ||
            block.chainid == ChainIdUtils.Base() ||
            block.chainid == ChainIdUtils.Optimism() ||
            block.chainid == ChainIdUtils.Unichain()
        ) {
            return _getPostExecutionIntegrationsNoChange(integrations);
        }

        revert("Invalid chainId");
    }

    function _getPostExecutionIntegrationsMainnet(
        SLLIntegration[] memory integrations
    ) internal view returns (SLLIntegration[] memory newIntegrations) {
        newIntegrations = new SLLIntegration[](integrations.length + 3);

        for (uint256 i = 0; i < integrations.length; ++i) {
            newIntegrations[i] = integrations[i];
        }

        newIntegrations[newIntegrations.length - 3] = _createTransferAssetIntegration("ANCHORAGE_TRANSFER-USDC", Ethereum.USDC, ANCHORAGE);
        newIntegrations[newIntegrations.length - 2] = _createERC4626Integration("ERC4626-ARKIS-USDC", ARKIS);
        newIntegrations[newIntegrations.length - 1] = _createSparkVaultV2Integration("SPARK_VAULT_V2-SPPYUSD", Ethereum.SPARK_VAULT_V2_SPPYUSD);
    }

    /**********************************************************************************************/
    /*** Data processing helper functions                                                       ***/
    /**********************************************************************************************/

    function _createAaveIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.AAVE,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_AAVE_DEPOSIT(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_AAVE_WITHDRAW(), integration),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createBuidlIntegration(
        string  memory label,
        address        assetIn,
        address        assetOut,
        address        depositDestination,
        address        withdrawDestination
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.BUIDL,
            integration: assetOut,  // Default to assetOut for transferAsset type integrations because this is the LP token
            entryId:     RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn,  depositDestination),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination),
            exitId2:     bytes32(0),
            extraData:   abi.encode(assetIn, depositDestination, assetOut, withdrawDestination)
        });
    }

    function _createCctpIntegration(
        string  memory label,
        uint32         cctpId
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.CCTP,
            integration: address(uint160(cctpId)),  // Unique ID
            entryId:     RateLimitHelpers.makeUint32Key(mainnetController.LIMIT_USDC_TO_DOMAIN(), cctpId),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   abi.encode(cctpId)
        });
    }

    function _createCctpGeneralIntegration(string  memory label) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.CCTP_GENERAL,
            integration: address(0),
            entryId:     mainnetController.LIMIT_USDC_TO_CCTP(),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createCoreIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.CORE,
            integration: integration,
            entryId:     mainnetController.LIMIT_USDS_MINT(),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createCurveLpIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.CURVE_LP,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_CURVE_DEPOSIT(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_CURVE_WITHDRAW(), integration),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createCurveSwapIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.CURVE_SWAP,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_CURVE_SWAP(), integration),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createERC4626Integration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.ERC4626,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), integration),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createEthenaIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.ETHENA,
            integration: integration,
            entryId:     mainnetController.LIMIT_USDE_MINT(),
            entryId2:    RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), integration),
            exitId:      mainnetController.LIMIT_SUSDE_COOLDOWN(),
            exitId2:     mainnetController.LIMIT_USDE_BURN(),
            extraData:   ""
        });
    }

    function _createFarmIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.FARM,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_FARM_DEPOSIT(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_FARM_WITHDRAW(), integration),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createMapleIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.MAPLE,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_MAPLE_REDEEM(),  integration),
            exitId2:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), integration),
            extraData:   ""
        });
    }

    function _createPsmIntegration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.PSM,
            integration: integration,
            entryId:     mainnetController.LIMIT_USDS_TO_USDC(),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createPsm3Integration(
        string  memory label,
        address        integration,
        address        asset
    ) internal view returns (SLLIntegration memory) {
        ForeignController foreignController = ForeignController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.PSM3,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(foreignController.LIMIT_PSM_DEPOSIT(),  asset),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressKey(foreignController.LIMIT_PSM_WITHDRAW(), asset),
            exitId2:     bytes32(0),
            extraData:   abi.encode(asset)
        });
    }

    function _createTransferAssetIntegration(
        string  memory label,
        address        asset,
        address        depositDestination
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.TRANSFER_ASSET,
            integration: asset,
            entryId:     RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), asset, depositDestination),
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   abi.encode(asset, depositDestination)
        });
    }

    function _createSparkVaultV2Integration(
        string  memory label,
        address        integration
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.SPARK_VAULT_V2,
            integration: integration,
            entryId:     RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_SPARK_VAULT_TAKE(), integration),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), ISparkVaultV2Like(integration).asset(), integration),
            exitId2:     bytes32(0),
            extraData:   ""
        });
    }

    function _createSuperstateIntegration(
        string  memory label,
        address        assetIn,
        address        assetOut,
        address        withdrawDestination
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.SUPERSTATE,
            integration: assetOut,  // Default to assetOut for transferAsset type integrations because this is the LP token
            entryId:     mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE(),
            entryId2:    bytes32(0),
            exitId:      keccak256("LIMIT_SUPERSTATE_REDEEM"),  // Have to use hash because this function was removed
            exitId2:     RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination),
            extraData:   abi.encode(assetIn, assetOut, withdrawDestination)
        });
    }

    function _createSuperstateUsccIntegration(
        string  memory label,
        address        assetIn,
        address        assetOut,
        address        depositDestination,
        address        withdrawDestination
    ) internal view returns (SLLIntegration memory) {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        return SLLIntegration({
            label:       label,
            category:    Category.SUPERSTATE_USCC,
            integration: assetOut,  // Default to assetOut for transferAsset type integrations because this is the LP
            entryId:     RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn, depositDestination),
            entryId2:    bytes32(0),
            exitId:      RateLimitHelpers.makeAddressAddressKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination),
            exitId2:     bytes32(0),
            extraData:   abi.encode(assetIn, depositDestination, assetOut, withdrawDestination)
        });
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _getSparkLiquidityLayerContext(uint256 chainId) internal view returns (SparkLiquidityLayerContext memory ctx) {
        if (chainId == ChainIdUtils.Ethereum()) {
            ctx = SparkLiquidityLayerContext(
                Ethereum.ALM_CONTROLLER,
                address(0),
                IALMProxy(Ethereum.ALM_PROXY),
                IRateLimits(Ethereum.ALM_RATE_LIMITS),
                Ethereum.ALM_RELAYER_MULTISIG,
                Ethereum.ALM_FREEZER_MULTISIG
            );
        } else if (chainId == ChainIdUtils.Base()) {
            ctx = SparkLiquidityLayerContext(
                Base.ALM_CONTROLLER,
                address(0),
                IALMProxy(Base.ALM_PROXY),
                IRateLimits(Base.ALM_RATE_LIMITS),
                Base.ALM_RELAYER,
                Base.ALM_FREEZER
            );
        } else if (chainId == ChainIdUtils.ArbitrumOne()) {
            ctx = SparkLiquidityLayerContext(
                Arbitrum.ALM_CONTROLLER,
                address(0),
                IALMProxy(Arbitrum.ALM_PROXY),
                IRateLimits(Arbitrum.ALM_RATE_LIMITS),
                Arbitrum.ALM_RELAYER,
                Arbitrum.ALM_FREEZER
            );
        } else if (chainId == ChainIdUtils.Optimism()) {
            ctx = SparkLiquidityLayerContext(
                Optimism.ALM_CONTROLLER,
                address(0),
                IALMProxy(Optimism.ALM_PROXY),
                IRateLimits(Optimism.ALM_RATE_LIMITS),
                Optimism.ALM_RELAYER,
                Optimism.ALM_FREEZER
            );
        } else if (chainId == ChainIdUtils.Unichain()) {
            ctx = SparkLiquidityLayerContext(
                Unichain.ALM_CONTROLLER,
                address(0),
                IALMProxy(Unichain.ALM_PROXY),
                IRateLimits(Unichain.ALM_RATE_LIMITS),
                Unichain.ALM_RELAYER,
                Unichain.ALM_FREEZER
            );
        } else if (chainId == ChainIdUtils.Avalanche()) {
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
        if (chainData[chainId].prevController != address(0)) {
            ctx.prevController = chainData[chainId].prevController;
            ctx.controller     = chainData[chainId].newController;
        } else {
            ctx.prevController = ctx.controller;
        }
    }

    function _getSparkLiquidityLayerContext() internal view returns (SparkLiquidityLayerContext memory) {
        return _getSparkLiquidityLayerContext(block.chainid);
    }

    function _getSparkLiquidityLayerContext(bool isPostExecution) internal view returns (SparkLiquidityLayerContext memory ctx) {
        ctx = _getSparkLiquidityLayerContext(block.chainid);

        // Use the existing controller for all tests if spell hasn't executed yet
        if (isPostExecution) return ctx;

        ctx.controller = ctx.prevController;
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

    function _checkRateLimitKeys(SLLIntegration[] memory integrations, bytes32[] memory rateLimitKeys) internal pure {
        for (uint256 i = 0; i < integrations.length; ++i) {
            require(
                integrations[i].entryId  != bytes32(0) ||
                integrations[i].entryId2 != bytes32(0) ||
                integrations[i].exitId   != bytes32(0) ||
                integrations[i].exitId2  != bytes32(0),
                "Empty integration"
            );

            if (integrations[i].entryId != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].entryId);
            }

            if (integrations[i].entryId2 != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].entryId2);
            }

            if (integrations[i].exitId != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].exitId);
            }

            if (integrations[i].exitId2 != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].exitId2);
            }
        }

        assertTrue(rateLimitKeys.length == 0, "Rate limit keys not fully covered");
    }

    function _appendIfNotContaining(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        if (_contains(array, value)) return array;

        newArray = new bytes32[](array.length + 1);

        for (uint256 i = 0; i < array.length; ++i) {
            newArray[i] = array[i];
        }

        newArray[array.length] = value;
    }

    function _contains(bytes32[] memory array, bytes32 value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; ++i) {
            if (array[i] == value) return true;
        }

        return false;
    }

    function _removeAndReturnFound(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray, bool found) {
        // Assume `array` was built using `_appendIfNotContaining`.
        newArray = new bytes32[](array.length - 1);

        uint256 writeIndex = 0;

        for (uint256 readIndex = 0; readIndex < array.length; ++readIndex) {
            if (array[readIndex] == value) continue;

            // If we are about to write past the end of the new array, it means we've never found the value,
            // so we can return the original array.
            if (writeIndex == newArray.length) return (array, false);

            newArray[writeIndex++] = array[readIndex];
        }

        return (newArray, true);
    }

    function _remove(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        bool found;
        (newArray, found) = _removeAndReturnFound(array, value);
        assertTrue(found, "Value not found in array");
    }

    function _removeIfContaining(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        ( newArray, ) = _removeAndReturnFound(array, value);
    }

}
