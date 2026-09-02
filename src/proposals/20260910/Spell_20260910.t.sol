// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Gnosis }    from "spark-address-registry/Gnosis.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import {
    IPoolAddressesProvider,
    RateTargetKinkInterestRateStrategy
} from "sparklend-advanced/src/RateTargetKinkInterestRateStrategy.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator }    from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellRunner }              from "src/test-harness/SpellRunner.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract SparkEthereum_20260910_SLLTests is SparkLiquidityLayerTests {

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }
        super.deal(token, to, amount);
    }

    /**********************************************************************************************/
    /*** Ethereum - Offboard Unused Integrations                                                ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateMorphoV1DaiVault() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_DAI_1);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_DAI_1);

        _assertRateLimit(depositKey, 200_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateMorphoV1UsdsVault() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_USDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_USDS);

        _assertRateLimit(depositKey, 200_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAaveCoreUsde() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDE);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDE);

        _assertRateLimit(depositKey, 250_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateEthena() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        // The three Ethena limits are global keys, not wrapped with a venue address.
        bytes32 mintKey     = controller.LIMIT_USDE_MINT();
        bytes32 burnKey     = controller.LIMIT_USDE_BURN();
        bytes32 cooldownKey = controller.LIMIT_SUSDE_COOLDOWN();

        bytes32 susdeDepositKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(), Ethereum.SUSDE);

        _assertRateLimit(mintKey, 250_000_000e6,  100_000_000e6 / uint256(1 days));
        _assertRateLimit(burnKey, 500_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(cooldownKey);

        _assertRateLimit(susdeDepositKey, 250_000_000e18, 100_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(mintKey,         0, 0);
        _assertRateLimit(burnKey,         0, 0);
        _assertRateLimit(cooldownKey,     0, 0);
        _assertRateLimit(susdeDepositKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateMapleSyrupUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.SYRUP_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.SYRUP_USDT);
        bytes32 redeemKey   = RateLimitHelpers.makeAddressKey(controller.LIMIT_MAPLE_REDEEM(),  Ethereum.SYRUP_USDT);

        _assertRateLimit(depositKey, 50_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);
        _assertUnlimitedRateLimit(redeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(redeemKey,   0, 0);
    }

    function test_ETHEREUM_sll_deactivateMapleSyrupUsdc() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.SYRUP_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.SYRUP_USDC);
        bytes32 redeemKey   = RateLimitHelpers.makeAddressKey(controller.LIMIT_MAPLE_REDEEM(),  Ethereum.SYRUP_USDC);

        _assertRateLimit(depositKey, 100_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);
        _assertUnlimitedRateLimit(redeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(redeemKey,   0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurvePyusdUsds() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_PYUSDUSDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_PYUSDUSDS);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_PYUSDUSDS);

        _assertRateLimit(depositKey,  5_000_000e18, 50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 5_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(swapKey,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurvePyusdUsdc() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_PYUSDUSDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_PYUSDUSDC);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_PYUSDUSDC);

        // The deposit and withdraw limits were never configured; only the swap leg is zeroed.
        _assertRateLimit(depositKey,  0,            0);
        _assertRateLimit(withdrawKey, 0,            0);
        _assertRateLimit(swapKey,     5_000_000e18, 100_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveSusdsUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_SUSDSUSDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_SUSDSUSDT);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_SUSDSUSDT);

        _assertRateLimit(depositKey,  5_000_000e18,  20_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 25_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(swapKey,     10_000_000e18, 200_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveUsdcUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_USDCUSDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_USDCUSDT);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_USDCUSDT);

        // The deposit and withdraw limits were zeroed on 2025-04-21; only the swap leg is zeroed.
        _assertRateLimit(depositKey,  0,            0);
        _assertRateLimit(withdrawKey, 0,            0);
        _assertRateLimit(swapKey,     5_000_000e18, 20_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveWeethWethng() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 swapKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(), Ethereum.CURVE_WEETHWETHNG);

        _assertRateLimit(swapKey, 1_000e18, 50_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(swapKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateSuperstate() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 ustbSubscribeKey = controller.LIMIT_SUPERSTATE_SUBSCRIBE();
        bytes32 ustbRedeemKey    = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USTB, Ethereum.USTB);
        // Orphaned storage entry: the v1.10.0 controller does not declare LIMIT_SUPERSTATE_REDEEM.
        bytes32 legacyRedeemKey  = keccak256("LIMIT_SUPERSTATE_REDEEM");
        bytes32 usccSubscribeKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, Ethereum.USCC_DEPOSIT);
        bytes32 usccRedeemKey    = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USCC, Ethereum.USCC);

        _assertRateLimit(ustbSubscribeKey, 300_000_000e6, 100_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(ustbRedeemKey);
        _assertUnlimitedRateLimit(legacyRedeemKey);

        _assertRateLimit(usccSubscribeKey, 100_000_000e6, 50_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(usccRedeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(ustbSubscribeKey, 0, 0);
        _assertRateLimit(ustbRedeemKey,    0, 0);
        _assertRateLimit(legacyRedeemKey,  0, 0);
        _assertRateLimit(usccSubscribeKey, 0, 0);
        _assertRateLimit(usccRedeemKey,    0, 0);
    }

    function test_ETHEREUM_sll_deactivateB2C2() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 usdcKey  = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC,  Ethereum.B2C2_DEPOSIT_ADDRESS);
        bytes32 usdtKey  = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT,  Ethereum.B2C2_DEPOSIT_ADDRESS);
        bytes32 pyusdKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.PYUSD, Ethereum.B2C2_DEPOSIT_ADDRESS);

        _assertRateLimit(usdcKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(usdtKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdcKey,  0, 0);
        _assertRateLimit(usdtKey,  0, 0);
        _assertRateLimit(pyusdKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAnchorageUsdtUsat() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 usdtKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);
        bytes32 usatKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USAT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);
        bytes32 usdcKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);

        _assertRateLimit(usdtKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
        _assertRateLimit(usatKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
        _assertRateLimit(usdcKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdtKey, 0, 0);
        _assertRateLimit(usatKey, 0, 0);

        // The actively used Anchorage USDC leg shares the same destination address and stays
        // untouched.
        _assertRateLimit(usdcKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
    }

    /**********************************************************************************************/
    /*** Ethereum - Onboard Sentora RLUSD Morpho Vaults V2                                      ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_onboardSentoraRlusdVault() external onChain(ChainIdUtils.Ethereum()) {
        _testERC4626Onboarding({
            vault                 : SENTORA_RLUSD_VAULT,
            expectedDepositAmount : 1_000_000e18,
            depositMax            : 10_000_000e18,
            depositSlope          : 100_000_000e18 / uint256(1 days),
            maxSlippage           : 0
        });

        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).maxExchangeRates(SENTORA_RLUSD_VAULT), 3e36);
    }

}

contract SparkEthereum_20260910_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address internal constant OLD_USDT_IRM = 0x4E494988E68e6Fc52309BE4937869e27F0C304AC;
    address internal constant NEW_USDT_IRM = 0x4FA65B096681bD6FeecF78e5D83096bf4A5762A0;

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkLend_deprecateLbtcCollateral() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory lbtcConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'LBTC');

        assertEq(lbtcConfigBefore.ltv,                    74_00);
        assertEq(lbtcConfigBefore.liquidationThreshold,   75_00);
        assertEq(lbtcConfigBefore.liquidationBonus,       108_00);
        assertEq(lbtcConfigBefore.liquidationProtocolFee, 10_00);
        assertEq(lbtcConfigBefore.eModeCategory,          0);
        assertEq(lbtcConfigBefore.isFrozen,               false);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory lbtcConfigAfter = lbtcConfigBefore;

        lbtcConfigAfter.ltv = 0;

        _validateReserveConfig(lbtcConfigAfter, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.005e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.001e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_GNOSIS_sparkLend_completeDeprecation() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        address[5] memory collateralReserves = [Gnosis.WXDAI,    Gnosis.WETH, Gnosis.WSTETH, Gnosis.GNO, Gnosis.SXDAI];
        uint256[5] memory ltvsBefore         = [uint256(0),      70_00,       65_00,         40_00,      70_00];
        uint256[5] memory thresholdsBefore   = [uint256(75_00),  75_00,       72_50,         50_00,      75_00];
        uint256[5] memory bonuses            = [uint256(105_00), 105_00,      108_00,        112_00,     106_00];

        for (uint256 i; i < 5; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(collateralReserves[i]);

            assertEq(config.getLtv(),                    ltvsBefore[i]);
            assertEq(config.getLiquidationThreshold(),   thresholdsBefore[i]);
            assertEq(config.getLiquidationBonus(),       bonuses[i]);
            assertEq(config.getLiquidationProtocolFee(), 10_00);
        }

        assertEq(pool.getConfiguration(Gnosis.WETH).getEModeCategory(),   1);
        assertEq(pool.getConfiguration(Gnosis.WSTETH).getEModeCategory(), 1);

        DataTypes.EModeCategory memory categoryBefore = pool.getEModeCategoryData(1);

        assertEq(categoryBefore.ltv,                  85_00);
        assertEq(categoryBefore.liquidationThreshold, 90_00);
        assertEq(categoryBefore.liquidationBonus,     103_00);

        address[4] memory stablecoinReserves = [Gnosis.USDC, Gnosis.USDT, Gnosis.EURE, Gnosis.USDCE];

        for (uint256 i; i < 4; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(stablecoinReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   0);
            assertEq(config.getLiquidationBonus(),       0);
            assertEq(config.getLiquidationProtocolFee(), 0);
        }

        _executeAllPayloadsAndBridges();

        // 0.01% is raw 1, since PERCENTAGE_FACTOR == 1e4. Bonuses are restated unchanged and
        // the liquidation protocol fee falls to zero.
        for (uint256 i; i < 5; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(collateralReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   1);
            assertEq(config.getLiquidationBonus(),       bonuses[i]);
            assertEq(config.getLiquidationProtocolFee(), 0);
        }

        assertEq(pool.getConfiguration(Gnosis.WETH).getEModeCategory(),   0);
        assertEq(pool.getConfiguration(Gnosis.WSTETH).getEModeCategory(), 0);

        DataTypes.EModeCategory memory categoryAfter = pool.getEModeCategoryData(1);

        assertEq(categoryAfter.ltv,                  85_00);
        assertEq(categoryAfter.liquidationThreshold, 90_00);
        assertEq(categoryAfter.liquidationBonus,     103_00);

        // The four stablecoin reserves are untouched.
        for (uint256 i; i < 4; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(stablecoinReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   0);
            assertEq(config.getLiquidationBonus(),       0);
            assertEq(config.getLiquidationProtocolFee(), 0);
        }
    }

    function test_GNOSIS_sparkLend_positionsLiquidatableAfterDeprecation() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        address user       = makeAddr("gnosisEmodeBorrower");
        address liquidator = makeAddr("gnosisLiquidator");

        // Set up a live category-1 e-mode position before execution. The market has been
        // frozen since 2026-01-29, so the reserves are temporarily unfrozen the same way the
        // January 29, 2026 spell tests did.
        vm.startPrank(Gnosis.AMB_EXECUTOR);
        IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(Gnosis.WSTETH, false);
        IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(Gnosis.WETH,   false);
        IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setSupplyCap(Gnosis.WSTETH, 0);
        vm.stopPrank();

        deal(Gnosis.WSTETH, user, 1e18);

        vm.startPrank(user);
        IERC20(Gnosis.WSTETH).approve(address(pool), 1e18);
        pool.supply(Gnosis.WSTETH, 1e18, user, 0);
        pool.setUserEMode(1);
        pool.borrow(Gnosis.WETH, 0.5e18, 2, 0, user);
        vm.stopPrank();

        vm.startPrank(Gnosis.AMB_EXECUTOR);
        IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(Gnosis.WSTETH, true);
        IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(Gnosis.WETH,   true);
        vm.stopPrank();

        ( , , , , , uint256 healthFactorBefore ) = pool.getUserAccountData(user);
        assertGt(healthFactorBefore, 1e18);

        _executeAllPayloadsAndBridges();

        // The e-mode detach means category 1 no longer overrides the reserve threshold, so
        // the position falls through to the 0.01% reserve-level threshold and the health
        // factor lands far below the 0.95 close-factor threshold: a liquidator can clear the
        // entire position in a single transaction.
        ( , , , , , uint256 healthFactorAfter ) = pool.getUserAccountData(user);
        assertLt(healthFactorAfter, 0.95e18);

        deal(Gnosis.WETH, liquidator, 1e18);

        vm.startPrank(liquidator);
        IERC20(Gnosis.WETH).approve(address(pool), type(uint256).max);
        pool.liquidationCall(Gnosis.WSTETH, Gnosis.WETH, user, type(uint256).max, false);
        vm.stopPrank();

        assertEq(IERC20(Gnosis.WETH_DEBT_TOKEN).balanceOf(user), 0);
    }

}

contract SparkEthereum_20260910_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

}
