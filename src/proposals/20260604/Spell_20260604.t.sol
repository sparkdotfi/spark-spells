// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    IALMProxyFreezableLike,
    IMorphoVaultLike,
    IPositionManagerLike,
    ISparkVaultV2Like 
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260604_SLLTests is SparkLiquidityLayerTests {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    address internal constant NEW_AVALANCHE_ALM_PROXY_FREEZABLE = 0x93c81ADc7F98FdBC8C7a15eCBeD312c8F6adbcB3;
    address internal constant NEW_BASE_ALM_PROXY_FREEZABLE      = 0x92d7B06e5844e67174AE9E86bdCb06428482DDF9;
    address internal constant NEW_ETHEREUM_ALM_PROXY_FREEZABLE  = 0xe5c6318456a7Cb6f74f93B4eee4616dB5fcef699;

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1779171198;  // 2026-05-19T06:13:18Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Base()].payload      = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_updateAnchorageRateLimits() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT
        );

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : ANCHORAGE,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_uniswapUsdtUsdsRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 swapAssetKey = RateLimitHelpers.makeBytes32Key(
            controller.LIMIT_UNISWAP_V4_SWAP(),
            USDT_USDS_POOL_ID
        );

        _assertRateLimit(swapAssetKey, 5_000_000e18, 50_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(swapAssetKey, 25_000_000e18, 250_000_000e18 / uint256(1 days));

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(USDT_USDS_POOL_ID));

        _testUniswapV4SwapIntegration(UniswapV4SwapE2ETestParams({
            ctx:           ctx,
            poolId:        USDT_USDS_POOL_ID,
            asset0:        Currency.unwrap(poolKey.currency0),
            asset1:        Currency.unwrap(poolKey.currency1),
            seedLiquidity: 2_000_000e18,
            swapAmount:    1_000_000e18,  // Amount for each swap direction
            swapKey:       swapAssetKey
        }));
    }

    function test_ETHEREUM_sparkVaultSetterRoleChanges() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like spUsdc  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like spUsdt  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like spEth   = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);
        ISparkVaultV2Like spPyusd = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPPYUSD);

        bytes32 SETTER_ROLE = spUsdc.SETTER_ROLE();

        assertEq(spUsdc.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(spUsdt.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(spEth.hasRole(SETTER_ROLE,   Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(spPyusd.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), true);

        assertEq(spUsdc.hasRole(SETTER_ROLE,  NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);
        assertEq(spUsdt.hasRole(SETTER_ROLE,  NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);
        assertEq(spEth.hasRole(SETTER_ROLE,   NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);
        assertEq(spPyusd.hasRole(SETTER_ROLE, NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(spUsdc.getRoleMemberCount(SETTER_ROLE), 1);
        assertEq(spUsdt.getRoleMemberCount(SETTER_ROLE), 1);
        assertEq(spEth.getRoleMemberCount(SETTER_ROLE),  1);
        assertEq(spPyusd.getRoleMemberCount(SETTER_ROLE), 1);

        assertEq(spUsdc.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(spUsdt.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(spEth.hasRole(SETTER_ROLE,   Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(spPyusd.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), false);

        assertEq(spUsdc.hasRole(SETTER_ROLE,  NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
        assertEq(spUsdt.hasRole(SETTER_ROLE,  NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
        assertEq(spEth.hasRole(SETTER_ROLE,   NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
        assertEq(spPyusd.hasRole(SETTER_ROLE, NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
    }

    function test_ETHEREUM_morphoVaultAllocatorRoleChanges() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultLike morphoUsdc = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC);
        IMorphoVaultLike morphoUsds = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS);

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);

        assertEq(morphoUsdc.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);
        assertEq(morphoUsds.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), false);

        assertEq(morphoUsdc.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
        assertEq(morphoUsds.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);
    }

    function test_ETHEREUM_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(NEW_ETHEREUM_ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Ethereum.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Ethereum.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),                   true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Ethereum.SPARK_PROXY);

        vm.recordLogs();

        _executeMainnetPayload();  // Have to use this to properly load logs on mainnet

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Ethereum.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Ethereum.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),                   true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](3);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[1].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Ethereum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Ethereum.ALM_FREEZER_MULTISIG);
    }

    function test_AVALANCHE_sparkVaultSetterRoleChanges() external onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE),     true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(), NEW_AVALANCHE_ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE),     false);
        assertEq(vault.hasRole(vault.SETTER_ROLE(), NEW_AVALANCHE_ALM_PROXY_FREEZABLE), true);

        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()), 1);
    }

    function test_AVALANCHE_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Avalanche()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(NEW_AVALANCHE_ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Avalanche.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Avalanche.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Avalanche.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),                true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Avalanche.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Avalanche.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Avalanche.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Avalanche.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),                true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[1].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Avalanche.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Avalanche.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Avalanche.ALM_FREEZER_MULTISIG);
    }

    function test_BASE_morphoVaultAllocatorRoleChanges() external onChain(ChainIdUtils.Base()) {
        IMorphoVaultLike morphoUsdc = IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC);

        assertEq(morphoUsdc.isAllocator(Base.ALM_PROXY_FREEZABLE),     true);
        assertEq(morphoUsdc.isAllocator(NEW_BASE_ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdc.isAllocator(Base.ALM_PROXY_FREEZABLE),     false);
        assertEq(morphoUsdc.isAllocator(NEW_BASE_ALM_PROXY_FREEZABLE), true);
    }

    function test_BASE_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Base()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(NEW_BASE_ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Base.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Base.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Base.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Base.SPARK_EXECUTOR),                true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Base.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Base.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Base.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Base.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Base.SPARK_EXECUTOR),                true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[1].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Base.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Base.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Base.ALM_FREEZER_MULTISIG);
    }

}

contract SparkEthereum_20260604_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1779171198;  // 2026-05-19T06:13:18Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Base()].payload      = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_sparkLend_wethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WETH, 2_000_000, 150_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.WETH, 1_000_000, 20_000,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WETH, uint48(ReserveConfiguration.MAX_VALID_SUPPLY_CAP), 100_000, 4 hours);
        _assertBorrowCapConfig(Ethereum.WETH, uint48(ReserveConfiguration.MAX_VALID_BORROW_CAP), 10_000,  4 hours);
    }

    function test_ETHEREUM_sparkLend_wstethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WSTETH, 2_000_000, 50_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.WSTETH, 1,         1,      12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WSTETH, uint48(ReserveConfiguration.MAX_VALID_SUPPLY_CAP), 50_000, 4 hours);
        _assertBorrowCapConfig(Ethereum.WSTETH, 1,                                                 1,      0);
    }

    function test_ETHEREUM_sparkLend_weethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WEETH, 500_000, 10_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.WEETH, 0,       0,      0);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WEETH, 500_000, 10_000, 4 hours);
        _assertBorrowCapConfig(Ethereum.WEETH, 1,       1,      0);
    }

    function test_ETHEREUM_sparkLend_wbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WBTC, 30_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 1,      1,   12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WBTC, 50_000, 500, 4 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 50_000, 100, 4 hours);
    }

    function test_ETHEREUM_sparkLend_cbbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.CBBTC, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 10_000, 50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.CBBTC, 50_000, 500, 4 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 50_000, 100, 4 hours);
    }

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 5_000, 200, 12 hours);
        _assertBorrowCapConfig(Ethereum.LBTC, 0,     0,   0);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 200, 4 hours);
        _assertBorrowCapConfig(Ethereum.LBTC, 1,      1,   0);
    }

    function test_ETHEREUM_sparkLend_reserveFactor() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot("", ctx.pool);

        ReserveConfig memory usdc = _findReserveConfigBySymbol(allConfigsBefore, "USDC");
        ReserveConfig memory usdt = _findReserveConfigBySymbol(allConfigsBefore, "USDT");

        assertEq(usdc.reserveFactor, 1_00);
        assertEq(usdt.reserveFactor, 1_00);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot("", ctx.pool);

        usdc.reserveFactor = 10_00;
        usdt.reserveFactor = 10_00;

        _validateReserveConfig(usdc, allConfigsAfter);
        _validateReserveConfig(usdt, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_updateParamsForDeprecatedAssets() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory rsethConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'rsETH');
        ReserveConfig memory ezethConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'ezETH');
        ReserveConfig memory tbtcConfigBefore  = _findReserveConfigBySymbol(allConfigsBefore, 'tBTC');
        ReserveConfig memory rethConfigBefore  = _findReserveConfigBySymbol(allConfigsBefore, 'rETH');

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory rsethConfigAfter = rsethConfigBefore;

        rsethConfigAfter.ltv                  = 0;
        rsethConfigAfter.liquidationThreshold = 70_00;

        ReserveConfig memory ezethConfigAfter = ezethConfigBefore;

        ezethConfigAfter.ltv                  = 0;
        ezethConfigAfter.liquidationThreshold = 70_00;

        ReserveConfig memory tbtcConfigAfter = tbtcConfigBefore;

        tbtcConfigAfter.ltv                  = 0;
        tbtcConfigAfter.liquidationThreshold = 70_00;

        ReserveConfig memory rethConfigAfter = rethConfigBefore;

        rethConfigAfter.liquidationThreshold = 70_00;

        _validateReserveConfig(rsethConfigAfter, allConfigsAfter);
        _validateReserveConfig(ezethConfigAfter, allConfigsAfter);
        _validateReserveConfig(tbtcConfigAfter,  allConfigsAfter);
        _validateReserveConfig(rethConfigAfter,  allConfigsAfter);
    }

}

contract SparkEthereum_20260604_SpellTests is SpellTests {

    uint256 internal constant SPK_BUYBACKS_AMOUNT = 663_354e18;

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1779171198;  // 2026-05-19T06:13:18Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Base()].payload      = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 almOpsBalanceBefore     = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore, 37_022_794.249708907368137212e18);
        assertEq(almOpsBalanceBefore,     0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore - SPK_BUYBACKS_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
