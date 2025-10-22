// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainId.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { ISparkVaultV2Like, IERC20Like, ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20251030_SLLTests is SparkLiquidityLayerTests {

    address internal constant ARBITRUM_NEW_ALM_CONTROLLER = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;
    address internal constant OPTIMISM_NEW_ALM_CONTROLLER = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
    address internal constant UNICHAIN_NEW_ALM_CONTROLLER = 0x7CD6EC14785418aF694efe154E7ff7d9ba99D99b;

    address internal constant SYRUP_USDT = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-20T15:17:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Optimism()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Unichain()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
    }

    function test_ARBITRUM_controllerUpgrade() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testControllerUpgrade({
            oldController: Arbitrum.ALM_CONTROLLER,
            newController: ARBITRUM_NEW_ALM_CONTROLLER
        });
    }

    function test_OPTIMISM_controllerUpgrade() public onChain(ChainIdUtils.Optimism()) {
        _testControllerUpgrade({
            oldController: Optimism.ALM_CONTROLLER,
            newController: OPTIMISM_NEW_ALM_CONTROLLER
        });
    }

    function test_UNICHAIN_controllerUpgrade() public onChain(ChainIdUtils.Unichain()) {
        _testControllerUpgrade({
            oldController: Unichain.ALM_CONTROLLER,
            newController: UNICHAIN_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_onboardSyrupUSDT() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
            SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
            SYRUP_USDT
        );

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(redeemKey),   0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), 0);

        _executeAllPayloadsAndBridges();

        _testMapleIntegration(MapleE2ETestParams({
            ctx:           ctx,
            vault:         SYRUP_USDT,
            depositAmount: 1_000_000e6,
            depositKey:    depositKey,
            redeemKey:     redeemKey,
            withdrawKey:   withdrawKey,
            tolerance:     10
        }));
    }

}

contract SparkEthereum_20251030_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-22T07:32:00Z";
    }

    function test_ETHEREUM_sparkLend_usdcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDC, 1_000_000_000, 150_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDC, 950_000_000,   50_000_000,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDC, 0, 0, 0);
        _assertBorrowCapConfig(Ethereum.USDC, 0, 0, 0);

        DataTypes.ReserveConfigurationMap memory currentConfig = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDC);

        assertEq(currentConfig.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(currentConfig.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_usdtCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDT, 5_000_000_000, 1_000_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 5_000_000_000, 200_000_000,   12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDT, 0, 0, 0);
        _assertBorrowCapConfig(Ethereum.USDT, 0, 0, 0);

        DataTypes.ReserveConfigurationMap memory currentConfig = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDT);

        assertEq(currentConfig.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(currentConfig.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_pyusdCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(PYUSD, 500_000_000, 50_000_000, 12 hours);
        _assertBorrowCapConfig(PYUSD, 475_000_000, 25_000_000, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(PYUSD, 0, 0, 0);
        _assertBorrowCapConfig(PYUSD, 0, 0, 0);

        DataTypes.ReserveConfigurationMap memory currentConfig = IPool(Ethereum.POOL).getConfiguration(PYUSD);

        assertEq(currentConfig.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(currentConfig.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_cbbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.CBBTC, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.CBBTC, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_tbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.TBTC, 500, 125, 12 hours);
        _assertBorrowCapConfig(Ethereum.TBTC, 250, 25,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.TBTC, 1_000, 125, 12 hours);
        _assertBorrowCapConfig(Ethereum.TBTC, 900,   25,  12 hours);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  404_320_160.818926086778450517e18);
        assertEq(spUsdsBalanceBefore, 592_424_783.583591603436341145e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spDaiBalanceBefore + 33_225.584380788531641492e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   spUsdsBalanceBefore + 43_626.185445845175175216e18);
    }

}

contract SparkEthereum_20251030_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-22T07:32:00Z";
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).depositCap(), 50_000_000e6);
        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).depositCap(), 50_000_000e6);
        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).depositCap(),  10_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).depositCap(), 250_000_000e6);
        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).depositCap(), 250_000_000e6);
        assertEq(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).depositCap(),  50_000e18);
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        assertEq(ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).depositCap(), 50_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).depositCap(), 150_000_000e6);
    }

}
