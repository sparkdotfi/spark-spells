// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ChainIdUtils }                              from 'src/libraries/ChainId.sol';
import { SparkLiquidityLayerContext, RateLimitData } from 'src/test-harness/SparkLiquidityLayerTests.sol';
import { SparkTestBase }                             from 'src/test-harness/SparkTestBase.sol';

interface IFarmLike {
    function balanceOf(address account) external view returns (uint256);
}

contract SparkEthereum_20250918Test is SparkTestBase {

    address internal constant CURVE_PYUSDUSDS             = 0xA632D59b9B804a956BfaA9b48Af3A1b74808FC1f;
    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;
    address internal constant USDS_SPK_FARM               = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    address internal constant PT_USDS_SPK_18DEC2025            = 0xA2a420230A5cb045db052E377D20b9c156805b95;
    address internal constant PT_USDS_SPK_18DEC2025_PRICE_FEED = 0x0F9D6c72959d836D4DECdE30Ab0AD836979EFE87;

    address internal constant NEW_ALM_CONTROLLER_BASE     = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
    address internal constant MORPHO_TOKEN_BASE           = 0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842;
    address internal constant SPARK_MULTISIG_BASE         = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;

    constructor() {
        id = "20250918";
    }

    function setUp() public {
        setupDomains("2025-09-10T08:36:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xe7782847eF825FF37662Ef2F426f2D8c5D904121;
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER_ETHEREUM);
    }

    function test_ETHEREUM_cctpRateLimits() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(NEW_ALM_CONTROLLER_ETHEREUM);

        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),
            200_000_000e6,
            500_000_000e6 / uint256(1 days)
        );
    }

    function test_ETHEREUM_sll_onboardUsdsSpkFarm() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(NEW_ALM_CONTROLLER_ETHEREUM);

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(NEW_ALM_CONTROLLER_ETHEREUM).LIMIT_FARM_DEPOSIT(),
            USDS_SPK_FARM
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(NEW_ALM_CONTROLLER_ETHEREUM).LIMIT_FARM_WITHDRAW(),
            USDS_SPK_FARM
        );

        IERC20 underlying = IERC20(Ethereum.USDS);

        uint256 expectedDepositAmount = 1_000_000e18;

        deal(address(underlying), address(ctx.proxy), expectedDepositAmount);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  250_000_000e18,    50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        assertEq(IFarmLike(USDS_SPK_FARM).balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.depositToFarm(USDS_SPK_FARM, expectedDepositAmount);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  250_000_000e18 - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(IFarmLike(USDS_SPK_FARM).balanceOf(address(ctx.proxy)), expectedDepositAmount);
        assertEq(underlying.balanceOf(address(ctx.proxy)),               0);

        vm.prank(ctx.relayer);
        controller.withdrawFromFarm(USDS_SPK_FARM, expectedDepositAmount / 2);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  250_000_000e18 - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(IFarmLike(USDS_SPK_FARM).balanceOf(address(ctx.proxy)), expectedDepositAmount / 2);
        assertEq(underlying.balanceOf(address(ctx.proxy)),               expectedDepositAmount / 2);
    }

    function test_ETHEREUM_curvePoolOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testCurveOnboarding({
            controller:                  NEW_ALM_CONTROLLER_ETHEREUM,
            pool:                        CURVE_PYUSDUSDS,
            expectedDepositAmountToken0: 1e6,
            expectedSwapAmountToken0:    1e6,
            maxSlippage:                 0.998e18,
            swapLimit:                   RateLimitData(5_000_000e18, 50_000_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(5_000_000e18, 50_000_000e18 / uint256(1 days)),
            withdrawLimit:               RateLimitData(5_000_000e18, 100_000_000e18 / uint256(1 days))
        });
    }

    function test_ETHEREUM_morpho_onboardPTUSDSSPK18Dec2025() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_USDS,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDS_SPK_18DEC2025,
                oracle:          PT_USDS_SPK_18DEC2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            currentCap: 0,
            newCap:     1_000_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_USDS_SPK_18DEC2025,
            loanToken: Ethereum.USDS,
            oracle:    PT_USDS_SPK_18DEC2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1766016000  // December 18, 2025 12:00:00 AM UTC
        });
    }

    function test_ETHEREUM_sparkLend_usdtCapAutomatorUpdates() public onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDT, 500_000_000, 100_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 450_000_000, 50_000_000,  12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDT, 5_000_000_000, 1_000_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 5_000_000_000, 200_000_000,  12 hours);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  426_533_971.126578246102965428e18);
        assertEq(spUsdsBalanceBefore, 571_933_609.319213677194335496e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    426_542_116.448272852508728339e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   571_943_578.254251010380121323e18);
    }

    function test_BASE_controllerUpgrade() public onChain(ChainIdUtils.Base()) {
        _testControllerUpgrade(Base.ALM_CONTROLLER, NEW_ALM_CONTROLLER_BASE);
    }

    function test_BASE_cctpRateLimits() public onChain(ChainIdUtils.Base()) {
        ForeignController controller = ForeignController(NEW_ALM_CONTROLLER_BASE);

        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            200_000_000e6,
            500_000_000e6 / uint256(1 days)
        );
    }

    function test_ETHEREUM_spark_morphoTransferLimit() public onChain(ChainIdUtils.Base()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(NEW_ALM_CONTROLLER_BASE);

        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            ForeignController(NEW_ALM_CONTROLLER_BASE).LIMIT_ASSET_TRANSFER(),
            MORPHO_TOKEN_BASE,
            SPARK_MULTISIG_BASE
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 100_000e18, 100_000e18 / uint256(1 days));

        deal(MORPHO_TOKEN_BASE, Base.ALM_PROXY, 200_000e18);

        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(SPARK_MULTISIG_BASE),     0);
        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(Base.ALM_PROXY), 200_000e18);

        vm.prank(ctx.relayer);
        controller.transferAsset(MORPHO_TOKEN_BASE, SPARK_MULTISIG_BASE, 100_000e18);

        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(SPARK_MULTISIG_BASE),     100_000e18);
        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(Base.ALM_PROXY), 100_000e18);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey),    0);

        skip(1 days + 1 seconds);  // +1 second due to rounding

        vm.prank(ctx.relayer);
        controller.transferAsset(MORPHO_TOKEN_BASE, SPARK_MULTISIG_BASE, 100_000e18);

        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(SPARK_MULTISIG_BASE),     200_000e18);
        assertEq(IERC20(MORPHO_TOKEN_BASE).balanceOf(Base.ALM_PROXY), 0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey),    0);

        skip(1 days + 1 seconds);  // +1 second due to rounding

        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 100_000e18);
    }

}
