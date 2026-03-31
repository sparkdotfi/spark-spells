// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20260409_SLLTests is SparkLiquidityLayerTests {

    address internal constant ANCHORAGE_USAT_USDT = 0x49506C3Aa028693458d6eE816b2EC28522946872;

    constructor() {
        _spellId   = 20260409;
        _blockDate = 1774965803;  // 2026-03-31T14:03:23Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload    = ;
        // chainData[ChainIdUtils.ArbitrumOne()].payload = ;
        // chainData[ChainIdUtils.Base()].payload        = ;
    }

    /**********************************************************************************************/
    /*** Ethereum - Deactivate Unused Integrations                                              ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateFluidSusds() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.FLUID_SUSDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.FLUID_SUSDS);

        _assertRateLimit(depositKey,  10_000_000e18,     5_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAavePrimeUsds() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_PRIME_USDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_PRIME_USDS);

        _assertRateLimit(depositKey,  50_000_000e18,     50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAaveCoreUsds() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDS);

        _assertRateLimit(depositKey,  50_000_000e18,     25_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAaveCoreUsdc() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDC);

        _assertRateLimit(depositKey,  50_000_000e6,      25_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    /**********************************************************************************************/
    /*** Ethereum - Configure Aave/SparkLend Integrations                                       ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_aaveCoreUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDT);

        _assertRateLimit(depositKey,  10_000_000e6,      1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, Ethereum.ATOKEN_CORE_USDT, 1_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_sparkLendUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  SparkLend.USDT_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), SparkLend.USDT_SPTOKEN);

        _assertRateLimit(depositKey,  250_000_000e6,     2_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  500_000_000e6,     2_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, SparkLend.USDT_SPTOKEN, 1_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_sparkLendEthRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  SparkLend.WETH_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), SparkLend.WETH_SPTOKEN);

        _assertRateLimit(depositKey,  50_000e18,         10_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  50_000e18,         250_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, SparkLend.WETH_SPTOKEN, 100e18, depositKey, withdrawKey, 10));
    }

    /**********************************************************************************************/
    /*** Ethereum - Maple syrupUSDT Rate Limit Update                                           ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_syrupUsdtRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_4626_DEPOSIT(),
            Ethereum.SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_MAPLE_REDEEM(),
            Ethereum.SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_4626_WITHDRAW(),
            Ethereum.SYRUP_USDT
        );

        _assertRateLimit(depositKey, 25_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(redeemKey,  50_000_000e6, 500_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 50_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(redeemKey);
        _assertUnlimitedRateLimit(withdrawKey);

        _testMapleIntegration(MapleE2ETestParams({
            ctx           : ctx,
            vault         : Ethereum.SYRUP_USDT,
            depositAmount : 1_000_000e6,
            depositKey    : depositKey,
            redeemKey     : redeemKey,
            withdrawKey   : withdrawKey,
            tolerance     : 10
        }));
    }

    /**********************************************************************************************/
    /*** Ethereum - Morpho Blue Chip USDT Vault                                                 ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_morphoUsdtVaultRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_V2_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_V2_USDT);

        _assertRateLimit(depositKey,  50_000_000e6,      1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testERC4626Integration(E2ETestParams(ctx, Ethereum.MORPHO_VAULT_V2_USDT, 1_000_000e6, depositKey, withdrawKey, 10));
    }

    /**********************************************************************************************/
    /*** Ethereum - Curve Pool Configurations                                                   ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_curveWeethWethng() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ctx.controller);

        bytes32 swapKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_CURVE_SWAP(),
            Ethereum.CURVE_WEETHWETHNG
        );

        _assertRateLimit(swapKey, 100e18, 1_000e18 / uint256(1 days));

        assertEq(controller.maxSlippages(Ethereum.CURVE_WEETHWETHNG), 0.9975e18);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(swapKey, 1_000e18, 50_000e18 / uint256(1 days));

        assertEq(controller.maxSlippages(Ethereum.CURVE_WEETHWETHNG), 0.9975e18);

        _testCurveSwapIntegration(CurveSwapE2ETestParams({
            ctx        : ctx,
            pool       : Ethereum.CURVE_WEETHWETHNG,
            asset0     : Ethereum.WETH,
            asset1     : Ethereum.WEETH,
            swapAmount : 10e18,
            swapKey    : swapKey
        }));
    }

    function test_ETHEREUM_sll_curveSusdsUsdt() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_CURVE_DEPOSIT(),
            Ethereum.CURVE_SUSDSUSDT
        );

        bytes32 swapKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_CURVE_SWAP(),
            Ethereum.CURVE_SUSDSUSDT
        );

        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            controller.LIMIT_CURVE_WITHDRAW(),
            Ethereum.CURVE_SUSDSUSDT
        );

        _assertRateLimit(swapKey,     5_000_000e18,  100_000_000e18 / uint256(1 days));
        _assertRateLimit(depositKey,  5_000_000e18,  20_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 25_000_000e18, 100_000_000e18 / uint256(1 days));

        assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(swapKey,     10_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(depositKey,  5_000_000e18,  20_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 25_000_000e18, 100_000_000e18 / uint256(1 days));

        assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);

        _testCurveSwapIntegration(CurveSwapE2ETestParams({
            ctx        : ctx,
            pool       : Ethereum.CURVE_SUSDSUSDT,
            asset0     : Ethereum.SUSDS,
            asset1     : Ethereum.USDT,
            swapAmount : 1_000_000e18,
            swapKey    : swapKey
        }));
    }

    /**********************************************************************************************/
    /*** Ethereum - Anchorage Transfer Asset Rate Limits                                        ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_anchorageUSDT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_anchorageUSAT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USAT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USAT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    /**********************************************************************************************/
    /*** Ethereum - Spark Savings Vault Deposit Caps                                            ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 1_000_000_000e6);
        assertEq(usdtVault.depositCap(), 2_000_000_000e6);
        assertEq(ethVault.depositCap(),  250_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 10_000_000_000e6);
        assertEq(usdtVault.depositCap(), 10_000_000_000e6);
        assertEq(ethVault.depositCap(),  1_000_000e18);

        _testSparkVaultDepositCapBoundary({
            vault:              usdcVault,
            depositCap:         10_000_000_000e6,
            expectedMaxDeposit: 9_588_692_932.754565e6
        });
        _testSparkVaultDepositCapBoundary({
            vault:              usdtVault,
            depositCap:         10_000_000_000e6,
            expectedMaxDeposit: 9_189_811_901.398293e6
        });
        _testSparkVaultDepositCapBoundary({
            vault:              ethVault,
            depositCap:         1_000_000e18,
            expectedMaxDeposit: 983_634.985416955036945334e18
        });
    }

    /**********************************************************************************************/
    /*** Arbitrum - Deactivate Integrations                                                     ***/
    /**********************************************************************************************/

    function test_ARBITRUM_sll_deactivateAaveUsdc() external onChain(ChainIdUtils.ArbitrumOne()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Arbitrum.ATOKEN_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Arbitrum.ATOKEN_USDC);

        _assertRateLimit(depositKey,  30_000_000e6,      15_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ARBITRUM_sll_deactivateFluidSusds() external onChain(ChainIdUtils.ArbitrumOne()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Arbitrum.FLUID_SUSDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Arbitrum.FLUID_SUSDS);

        _assertRateLimit(depositKey,  10_000_000e18,     5_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    /**********************************************************************************************/
    /*** Base - Deactivate Integrations                                                         ***/
    /**********************************************************************************************/

    function test_BASE_sll_deactivateAaveUsdc() external onChain(ChainIdUtils.Base()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Base.ATOKEN_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Base.ATOKEN_USDC);

        _assertRateLimit(depositKey,  50_000_000e6,      25_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_BASE_sll_deactivateFluidSusds() external onChain(ChainIdUtils.Base()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Base.FLUID_SUSDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Base.FLUID_SUSDS);

        _assertRateLimit(depositKey,  10_000_000e18,     5_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

}
