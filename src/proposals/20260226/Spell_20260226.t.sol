// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";
import { Id }           from "metamorpho/interfaces/IMetaMorpho.sol";
import { IMorpho }      from "metamorpho/interfaces/IMetaMorpho.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    ISyrupLike,
    IMorphoVaultV2Like,
    IMorphoLike
} from "src/interfaces/Interfaces.sol";

import { console } from "forge-std/console.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IMorphoMarketV1AdapterV2FactoryLike {
    function createMorphoMarketV1AdapterV2(address vault) external returns (address);
}

contract SparkEthereum_20260226_SLLTests is SparkLiquidityLayerTests {

    using SafeERC20 for IERC20;

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant MORPHO_VAULT_V2_USDT = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;
    address internal constant PAXOS_PYUSD_USDC     = 0x2f7BE67e11A4D621E36f1A8371b0a5Fe16dE6B20;
    address internal constant PAXOS_PYUSD_USDG     = 0x227B1912C2fFE1353EA3A603F1C05F030Cc262Ff;
    address internal constant PAXOS_USDC_PYUSD     = 0xFb1F749024b4544c425f5CAf6641959da31EdF37;
    address internal constant PAXOS_USDG_PYUSD     = 0x035b322D0e79de7c8733CdDA5a7EF8b51a6cfcfa;

    address internal constant ADAPTER_REGISTRY                    = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    address internal constant MORPHO                              = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_V1_ADAPTER_V2_FACTORY = 0x32BB1c0D48D8b1B3363e86eeB9A0300BAd61ccc1;

    constructor() {
        _spellId   = 20260226;
        _blockDate = 1771395565;  // 2026-02-18T06:19:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x42dB2A32C5F99034C90DaC07BF790f738b127e93;

        // Maple onboarding process
        ISyrupLike syrup = ISyrupLike(Ethereum.SYRUP_USDT);

        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(Ethereum.ALM_PROXY);
        booleans[0] = true;

        vm.startPrank(permissionManager.admin());
        permissionManager.setLenderAllowlist(
            syrup.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();
    }

    function test_ETHEREUM_sll_sparkLendUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  SparkLend.USDT_SPTOKEN);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), SparkLend.USDT_SPTOKEN);

        _assertRateLimit(depositKey,  100_000_000e6,     200_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  250_000_000e6,     2_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, SparkLend.USDT_SPTOKEN, 10_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_aaveCoreUsdtRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDT);

        _assertRateLimit(depositKey,  50_000_000e6,      25_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  10_000_000e6,      1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _testAaveIntegration(E2ETestParams(ctx, Ethereum.ATOKEN_CORE_USDT, 10_000_000e6, depositKey, withdrawKey, 10));
    }

    function test_ETHEREUM_sll_syrupUSDTRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            Ethereum.SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
            Ethereum.SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
            Ethereum.SYRUP_USDT
        );

        _assertRateLimit(depositKey, 50_000_000e6, 10_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(redeemKey);
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  25_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(redeemKey, 50_000_000e6, 500_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(withdrawKey);

        _testMapleIntegration(MapleE2ETestParams({
            ctx:           ctx,
            vault:         Ethereum.SYRUP_USDT,
            depositAmount: 1_000_000e6,
            depositKey:    depositKey,
            redeemKey:     redeemKey,
            withdrawKey:   withdrawKey,
            tolerance:     10
        }));
    }

    function test_ETHEREUM_onboardingPaxosUSDC_PYUSD() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            PAXOS_USDC_PYUSD
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : PAXOS_USDC_PYUSD,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingPaxosPYUSD_USDC() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.PYUSD,
            PAXOS_PYUSD_USDC
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 200_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.PYUSD,
            destination    : PAXOS_PYUSD_USDC,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingPaxosPYUSD_USDG() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.PYUSD,
            PAXOS_PYUSD_USDG
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.PYUSD,
            destination    : PAXOS_PYUSD_USDG,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingPaxosUSDG_PYUSD() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDG,
            PAXOS_USDG_PYUSD
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 100_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDG,
            destination    : PAXOS_USDG_PYUSD,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_morphoVaultV2Onboarding() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultV2Like vault = IMorphoVaultV2Like(MORPHO_VAULT_V2_USDT);

        assertEq(vault.asset(),                                       Ethereum.USDT);
        assertEq(vault.isAllocator(Ethereum.ALM_PROXY_FREEZABLE),     false);
        assertEq(vault.owner(),                                       Ethereum.SPARK_PROXY);
        assertEq(vault.curator(),                                     address(0));
        assertEq(vault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG), false);

        assertEq(vault.totalAssets(),                               1e6);
        assertEq(IERC20(address(vault)).balanceOf(address(0xdead)), 1e18);

        _executeAllPayloadsAndBridges();

        assertEq(vault.asset(),                                       Ethereum.USDT);
        assertEq(vault.isAllocator(Ethereum.ALM_PROXY_FREEZABLE),     true);
        assertEq(vault.owner(),                                       Ethereum.SPARK_PROXY);
        assertEq(vault.curator(),                                     Ethereum.MORPHO_CURATOR_MULTISIG);
        assertEq(vault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG), true);

        assertEq(vault.totalAssets(),                               1e6);
        assertEq(IERC20(address(vault)).balanceOf(address(0xdead)), 1e18);

        _testERC4626Onboarding(address(vault), 5_000_000e6, 50_000_000e6, 1_000_000_000e6 / uint256(1 days), 10, true);
    }

    function test_ETHEREUM_morphoVaultV2Functionality() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultV2Like vault = IMorphoVaultV2Like(MORPHO_VAULT_V2_USDT);

        _executeAllPayloadsAndBridges();

        // Step 1: Setup

        bytes32 SUSDS_USDT_MARKET_ID = 0x3274643db77a064abd3bc851de77556a4ad2e2f502f4f0c80845fa8f909ecf0b;
        bytes32 CBBTC_USDT_MARKET_ID = 0x45671fb8d5dea1c4fbca0b8548ad742f6643300eeb8dbd34ad64a658b2b05bca;

        address adapter = _setupVaultWithMarket(MORPHO_VAULT_V2_USDT, SUSDS_USDT_MARKET_ID, true);

        // Setup the CBBTC/USDT market.

        vm.startPrank(Ethereum.MORPHO_CURATOR_MULTISIG);

        MarketParams memory marketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(CBBTC_USDT_MARKET_ID));

        // Configure collateral token caps.
        bytes memory collateralTokenIdData = abi.encode("collateralToken", marketParams.collateralToken);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (collateralTokenIdData, type(uint128).max)));
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (collateralTokenIdData, 1e18)));
        vault.increaseAbsoluteCap(collateralTokenIdData, type(uint128).max);
        vault.increaseRelativeCap(collateralTokenIdData, 1e18);

        // Configure market caps.
        bytes memory marketIdData = abi.encode("this/marketParams", adapter, marketParams);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (marketIdData, type(uint128).max)));
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (marketIdData, 1e18)));
        vault.increaseAbsoluteCap(marketIdData, type(uint128).max);
        vault.increaseRelativeCap(marketIdData, 1e18);

        vm.stopPrank();

        // Step 2: Allocate to the vault ( deposit ).
        vm.startPrank(Ethereum.ALM_PROXY);

        uint256 depositAmount = 500_000_000e6;
        deal(Ethereum.USDT, Ethereum.ALM_PROXY, depositAmount);

        IERC20(Ethereum.USDT).safeIncreaseAllowance(address(vault), depositAmount);
        vault.deposit(depositAmount, Ethereum.ALM_PROXY);

        assertEq(vault.balanceOf(Ethereum.ALM_PROXY), depositAmount * 1e12);

        IMorphoLike.Position memory position = IMorphoLike(Ethereum.MORPHO).position(Id.wrap(SUSDS_USDT_MARKET_ID), adapter);

        console.log("position.supplyShares", position.supplyShares);

        console.log("vault.totalAssets()", IERC20(Ethereum.USDT).balanceOf(address(vault)));
        console.log("adapter balance",     IERC20(Ethereum.USDT).balanceOf(adapter));

        vm.stopPrank();

        // Reallocate into cbbtc/usdt market.
        vm.startPrank(Ethereum.ALM_PROXY_FREEZABLE);

        MarketParams memory susdsMarketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(SUSDS_USDT_MARKET_ID));

        bytes memory data = abi.encode(susdsMarketParams);
        vault.deallocate(adapter, data, depositAmount);

        MarketParams memory cbbtcMarketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(CBBTC_USDT_MARKET_ID));

        data = abi.encode(cbbtcMarketParams);
        vault.allocate(adapter, data, depositAmount);

        vm.stopPrank();

        // try to withdraw (assert that it fails)

        // vm.prank(Ethereum.ALM_PROXY);
        // vault.withdraw(depositAmount, Ethereum.ALM_PROXY, Ethereum.ALM_PROXY);

        // reallocate back to sUSDS/USDT market
        // try to withdraw (assert that it succeeds)
    }

    function _setupVaultWithMarket(address vault_, bytes32 marketId, bool setLiquidityAdapter) internal returns (address adapter) {
        IMorphoVaultV2Like vault = IMorphoVaultV2Like(vault_);

        // Deploy adapter
        adapter = IMorphoMarketV1AdapterV2FactoryLike(MORPHO_MARKET_V1_ADAPTER_V2_FACTORY)
            .createMorphoMarketV1AdapterV2(address(vault));

        vm.startPrank(Ethereum.MORPHO_CURATOR_MULTISIG);

        // Submit all timelocked changes (NO liquidityAdapterAndData yet)
        bytes memory adapterIdData = abi.encode("this", adapter);
        vault.submit(abi.encodeCall(vault.setAdapterRegistry, (ADAPTER_REGISTRY)));
        vault.submit(abi.encodeCall(vault.addAdapter, (adapter)));
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (adapterIdData, type(uint128).max)));
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (adapterIdData, 1e18)));

        // Execute all changes (NO liquidityAdapterAndData yet)
        vault.setAdapterRegistry(ADAPTER_REGISTRY);
        vault.addAdapter(adapter);
        vault.increaseAbsoluteCap(adapterIdData, type(uint128).max);
        vault.increaseRelativeCap(adapterIdData, 1e18);

        vm.stopPrank();

        // Configure market and liquidity adapter BEFORE dead deposit
        _configureMarketAndLiquidityAdapter(address(vault), marketId, adapter, setLiquidityAdapter);
    }

    function _configureMarketAndLiquidityAdapter(address vault_, bytes32 marketId_, address adapter, bool setLiquidityAdapter) internal {
        IMorphoVaultV2Like vault = IMorphoVaultV2Like(vault_);

        // Look up MarketParams from Morpho
        MarketParams memory marketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(marketId_));

        // Set liquidityAdapterAndData with encoded MarketParams
        if (setLiquidityAdapter) {
            bytes memory liquidityData = abi.encode(marketParams);

            vm.prank(Ethereum.MORPHO_CURATOR_MULTISIG);
            vault.submit(abi.encodeCall(vault.setLiquidityAdapterAndData, (adapter, liquidityData)));

            vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
            vault.setLiquidityAdapterAndData(adapter, liquidityData);
        }

        vm.startPrank(Ethereum.MORPHO_CURATOR_MULTISIG);

        // Configure collateral token caps
        bytes memory collateralTokenIdData = abi.encode("collateralToken", marketParams.collateralToken);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (collateralTokenIdData, type(uint128).max)));
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (collateralTokenIdData, 1e18)));
        vault.increaseAbsoluteCap(collateralTokenIdData, type(uint128).max);
        vault.increaseRelativeCap(collateralTokenIdData, 1e18);

        // Configure market caps
        bytes memory marketIdData = abi.encode("this/marketParams", adapter, marketParams);
        vault.submit(abi.encodeCall(vault.increaseAbsoluteCap, (marketIdData, type(uint128).max)));
        vault.submit(abi.encodeCall(vault.increaseRelativeCap, (marketIdData, 1e18)));
        vault.increaseAbsoluteCap(marketIdData, type(uint128).max);
        vault.increaseRelativeCap(marketIdData, 1e18);

        vm.stopPrank();
    }

}

contract SparkEthereum_20260226_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260226;
        _blockDate = 1771395565;  // 2026-02-18T06:19:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x42dB2A32C5F99034C90DaC07BF790f738b127e93;
    }

}

contract SparkEthereum_20260226_SpellTests is SpellTests {

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT     = 571_957e18;

    constructor() {
        _spellId   = 20260226;
        _blockDate = 1771395565;  // 2026-02-18T06:19:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x42dB2A32C5F99034C90DaC07BF790f738b127e93;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkBalanceBefore       = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 opsMultisigBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkBalanceBefore,       36_282_433.445801365846236778e18);
        assertEq(foundationBalanceBefore,  250_000e18);
        assertEq(opsMultisigBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkBalanceBefore - FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_OPS_MULTISIG),          opsMultisigBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
