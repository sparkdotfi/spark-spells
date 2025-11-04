// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import {
    IPoolAddressesProvider,
    RateTargetBaseInterestRateStrategy
} from "sparklend-advanced/src/RateTargetBaseInterestRateStrategy.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";
import { MorphoTests }              from "src/test-harness/MorphoTests.sol";

import {
    ISparkVaultV2Like,
    ITargetKinkIRMLike,
    ITargetBaseIRMLike,
    ICustomIRMLike,
    IRateSourceLike
} from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20251113_SLLTests is SparkLiquidityLayerTests {

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_ETHEREUM_sll_sparkLendUsdcRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.USDC_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.USDC_SPTOKEN);

        _assertRateLimit(depositKey,  100_000_000e6,     50_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     200_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, Ethereum.USDC_SPTOKEN, 10_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_sparkLendUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.USDT_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.USDT_SPTOKEN);

        _assertRateLimit(depositKey,  100_000_000e6,     100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  100_000_000e6,     200_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, Ethereum.USDT_SPTOKEN, 10_000_000e6, depositKey, withdrawKey, 10));
    }

}

contract SparkEthereum_20251113_SparklendTests is SparklendTests {

    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

    address internal constant PYUSD_IRM_OLD = 0xD3d3BcD8cC1D3d0676Da13F7Fc095497329EC683;
    address internal constant PYUSD_IRM_NEW = 0xDF7dedCfd522B1ee8da2c8526f642745800c8035;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_ETHEREUM_sparkLend_pyusdIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : PYUSD_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.015e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : PYUSD_IRM_NEW,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.02e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.95e27
        });
        _testRateTargetKinkToBaseIRMUpdate("PYUSD", oldParams, newParams);
    }

    function _testRateTargetKinkToBaseIRMUpdate(
        string                  memory symbol,
        RateTargetKinkIRMParams memory oldParams,
        RateTargetBaseIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRMLike(newParams.irm).RATE_SOURCE(), ICustomIRMLike(oldParams.irm).RATE_SOURCE());

        uint256 ssrRateDecimals = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).decimals();

        int256 ssrRate = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).getAPR() * int256(10 ** (27 - ssrRateDecimals));

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configBefore = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + oldParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        oldParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + oldParams.variableRateSlope1Spread),
                variableRateSlope2:            oldParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configBefore.interestRateStrategy).getVariableRateSlope1Spread()), uint256(oldParams.variableRateSlope1Spread));

        _executeAllPayloadsAndBridges();

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configAfter = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             newParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          newParams.variableRateSlope1,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        uint256(ssrRate) + newParams.baseRateSpread,
                variableRateSlope1:            newParams.variableRateSlope1,
                variableRateSlope2:            newParams.variableRateSlope2
            })
        );

        assertEq(ITargetBaseIRMLike(configAfter.interestRateStrategy).getBaseVariableBorrowRateSpread(), newParams.baseRateSpread);

        address expectedIRM = address(new RateTargetBaseInterestRateStrategy(
            IPoolAddressesProvider(address(ctx.poolAddressesProvider)),
            ICustomIRMLike(newParams.irm).RATE_SOURCE(),
            newParams.optimalUsageRatio,
            newParams.baseRateSpread,
            newParams.variableRateSlope1,
            newParams.variableRateSlope2
        ));

        _assertBytecodeMatches(expectedIRM, newParams.irm);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  413_852_826.907635248963156256e18);
        assertEq(spUsdsBalanceBefore, 171_338_343.119011364190523468e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spDaiBalanceBefore + 89_733.707492554224916353e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   spUsdsBalanceBefore + 43_003.135094118145514323e18);
    }

    function test_ETHEREUM_sparkLend_depreciateSUSDSandSDAI() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory susdsConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'sUSDS');
        ReserveConfig memory sdaiConfigBefore  = _findReserveConfigBySymbol(allConfigsBefore, 'sDAI');

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        // SUSDS

        assertEq(susdsConfigBefore.ltv,                  79_00);
        assertEq(susdsConfigBefore.liquidationThreshold, 80_00);
        assertEq(susdsConfigBefore.liquidationBonus,     105_00);

        ReserveConfig memory susdsConfigAfter = susdsConfigBefore;

        susdsConfigAfter.ltv = 0;

        _validateReserveConfig(susdsConfigAfter, allConfigsAfter);

        _assertSupplyCapConfig({
            asset:            Ethereum.SUSDS,
            max:              1,
            gap:              1,
            increaseCooldown: 12 hours
        });

        // SDAI

        assertEq(sdaiConfigBefore.ltv,                  79_00);
        assertEq(sdaiConfigBefore.liquidationThreshold, 80_00);
        assertEq(sdaiConfigBefore.liquidationBonus,     105_00);

        ReserveConfig memory sdaiConfigAfter = sdaiConfigBefore;

        sdaiConfigAfter.ltv = 0;

        _validateReserveConfig(sdaiConfigAfter, allConfigsAfter);

        _assertSupplyCapConfig({
            asset:            Ethereum.SDAI,
            max:              1,
            gap:              1,
            increaseCooldown: 12 hours
        });
    }

}

contract SparkEthereum_20251113_SpellTests is SpellTests {

    using SafeERC20 for IERC20;

    address internal constant GROVE_SUBDAO_PROXY  = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 625_069e18;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 250_000_000e6);
        assertEq(usdtVault.depositCap(), 250_000_000e6);
        assertEq(ethVault.depositCap(),  50_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(usdtVault.depositCap(), 500_000_000e6);
        assertEq(ethVault.depositCap(),  100_000e18);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 425_482_672.814637e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              usdtVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 441_712_918.49959e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              ethVault,
            depositCap:         100_000e18,
            expectedMaxDeposit: 84_629.835138740220858047e18
        });
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(usdcVault.depositCap(), 150_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 250_000_000e6);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         250_000_000e6,
            expectedMaxDeposit: 249_999_997.9e6
        });
    }

    function _test_vault_depositBoundaryLimit(
        ISparkVaultV2Like vault,
        uint256           depositCap,
        uint256           expectedMaxDeposit
    ) internal {
        address asset = vault.asset();

        uint256 maxDeposit = depositCap - vault.totalAssets();

        assertEq(maxDeposit, expectedMaxDeposit);

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        vault.deposit(maxDeposit + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(vault.balanceOf(address(this)), 0);

        deal(asset, address(this), maxDeposit);
        IERC20(asset).safeIncreaseAllowance(address(vault), maxDeposit);

        uint256 shares = vault.deposit(maxDeposit, address(this));

        assertEq(vault.balanceOf(address(this)), shares);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 groveUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(GROVE_SUBDAO_PROXY);

        assertEq(sparkUsdsBalanceBefore, 32_722_317.445801365846236778e18);
        assertEq(groveUsdsBalanceBefore, 1_167_444e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY), sparkUsdsBalanceBefore - GROVE_PAYMENT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(GROVE_SUBDAO_PROXY),   groveUsdsBalanceBefore + GROVE_PAYMENT_AMOUNT);
    }

}

contract SparkEthereum_20251113_MorphoTests is MorphoTests {

    address internal constant ETH        = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    constructor() {
        _spellId   = 20251113;
        _blockDate = "2025-11-04T08:51:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // chainData[ChainIdUtils.Base()].payload      = 0x71059EaAb41D6fda3e916bC9D76cB44E96818654;
    }

    function test_BASE_sparkUSDCVault_onboardEth() external onChain(ChainIdUtils.Base()) {
        _testMorphoCapUpdate({
            vault: Base.MORPHO_VAULT_SUSDC,
            config: MarketParams({
                loanToken:       Base.USDC,
                collateralToken: ETH,
                oracle:          ETH_ORACLE,
                irm:             Base.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            currentCap: 0,
            newCap:     1_000_000_000e18
        });
    }

}
