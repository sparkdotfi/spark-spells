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

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPool }               from "sparklend-v1-core/interfaces/IPool.sol";
import { IScaledBalanceToken } from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

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

interface ICapAutomatorLike {

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function UPDATE_ROLE() external view returns (bytes32);

}

contract SparkEthereum_20260604_SLLTests is SparkLiquidityLayerTests {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1779776905;  // 2026-05-26T06:28:25Z
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

        _assertRateLimit(transferKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : ANCHORAGE,
            transferKey    : transferKey,
            transferAmount : 50_000_000e6
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

    function test_ETHEREUM_increaseUSDSMintRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdsMintKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_MINT();

        _assertRateLimit(usdsMintKey, 500_000_000e18, 500_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdsMintKey, 1_000_000_000e18, 1_000_000_000e18 / uint256(1 days));
    }

    function test_ETHEREUM_increaseSwapUSDSToUSDCRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 swapUSDSToUSDCKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_TO_USDC();

        _assertRateLimit(swapUSDSToUSDCKey, 500_000_000e6, 300_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(swapUSDSToUSDCKey, 1_000_000_000e6, 1_000_000_000e6 / uint256(1 days));
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

    function test_ETHEREUM_roleChanges() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultLike  morphoUsdc   = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC);
        IMorphoVaultLike  morphoUsds   = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS);
        ICapAutomatorLike capAutomator = ICapAutomatorLike(SparkLend.CAP_AUTOMATOR);

        assertEq(capAutomator.hasRole(capAutomator.UPDATE_ROLE(), Ethereum.ALM_PROXY_FREEZABLE),     true);
        assertEq(capAutomator.hasRole(capAutomator.UPDATE_ROLE(), NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);

        assertEq(morphoUsdc.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);
        assertEq(morphoUsds.isAllocator(NEW_ETHEREUM_ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(capAutomator.hasRole(capAutomator.UPDATE_ROLE(), Ethereum.ALM_PROXY_FREEZABLE),     false);
        assertEq(capAutomator.hasRole(capAutomator.UPDATE_ROLE(), NEW_ETHEREUM_ALM_PROXY_FREEZABLE), true);

        assertEq(capAutomator.getRoleMemberCount(capAutomator.UPDATE_ROLE()), 1);

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

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath           for uint256;

    address internal constant NEW_ETHEREUM_ALM_PROXY_FREEZABLE  = 0xe5c6318456a7Cb6f74f93B4eee4616dB5fcef699;

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1779776905;  // 2026-05-26T06:28:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Base()].payload      = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_CapAutomator() external override onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        runCapAutomatorTests(Ethereum.ALM_PROXY_FREEZABLE);

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();

        runCapAutomatorTests(NEW_ETHEREUM_ALM_PROXY_FREEZABLE);
    }

    function runCapAutomatorTests(address almProxyFreezable) internal {
        address[] memory reserves = _getSparkLendContext().pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            testAutomatedCapsUpdate(almProxyFreezable, reserves[i]);
        }
    }

    function testAutomatedCapsUpdate(address almProxyFreezable, address asset) internal {
        SparkLendContext      memory ctx               = _getSparkLendContext();
        DataTypes.ReserveData memory reserveDataBefore = ctx.pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

        ICapAutomator capAutomator = ICapAutomator(SparkLend.CAP_AUTOMATOR);

        ( , , , , uint48 supplyCapLastIncreaseTime ) = capAutomator.supplyCapConfigs(asset);
        ( , , , , uint48 borrowCapLastIncreaseTime ) = capAutomator.borrowCapConfigs(asset);

        vm.prank(almProxyFreezable);
        capAutomator.exec(asset);

        DataTypes.ReserveData memory reserveDataAfter = ctx.pool.getReserveData(asset);

        uint256 supplyCapAfter = reserveDataAfter.configuration.getSupplyCap();
        uint256 borrowCapAfter = reserveDataAfter.configuration.getBorrowCap();

        uint48 max;
        uint48 gap;
        uint48 cooldown;

        ( max, gap, cooldown, , ) = capAutomator.supplyCapConfigs(asset);

        if (max > 0) {
            uint256 currentSupply = (
                    IScaledBalanceToken(reserveDataAfter.aTokenAddress).scaledTotalSupply() +
                    uint256(reserveDataAfter.accruedToTreasury)
                )
                .rayMul(reserveDataAfter.liquidityIndex) /
                10 ** IERC20Metadata(reserveDataAfter.aTokenAddress).decimals();

            uint256 expectedSupplyCap = uint256(max) < currentSupply + uint256(gap)
                ? uint256(max)
                : currentSupply + uint256(gap);

            if (supplyCapLastIncreaseTime + cooldown > block.timestamp && supplyCapBefore < expectedSupplyCap) {
                assertEq(supplyCapAfter, supplyCapBefore);
            } else {
                assertEq(supplyCapAfter, expectedSupplyCap);
            }
        } else {
            assertEq(supplyCapAfter, supplyCapBefore);
        }

        ( max, gap, cooldown, , ) = capAutomator.borrowCapConfigs(asset);

        if (max > 0) {
            uint256 currentBorrows =
                IERC20(reserveDataAfter.variableDebtTokenAddress).totalSupply() /
                10 ** IERC20Metadata(reserveDataAfter.variableDebtTokenAddress).decimals();

            uint256 expectedBorrowCap = uint256(max) < currentBorrows + uint256(gap)
                ? uint256(max)
                : currentBorrows + uint256(gap);

            if (borrowCapLastIncreaseTime + cooldown > block.timestamp && borrowCapBefore < expectedBorrowCap) {
                assertEq(borrowCapAfter, borrowCapBefore);
            } else {
                assertEq(borrowCapAfter, expectedBorrowCap);
            }
        } else {
            assertEq(borrowCapAfter, borrowCapBefore);
        }
    }

    function test_ETHEREUM_btcEmodeBorrowDeprecationE2E() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot("", ctx.pool);

        ReserveConfig memory lbtcConfig  = _findReserveConfigBySymbol(allConfigsBefore, "LBTC");
        ReserveConfig memory cbbtcConfig = _findReserveConfigBySymbol(allConfigsBefore, "cbBTC");

        assertEq(lbtcConfig.eModeCategory,  3);
        assertEq(cbbtcConfig.eModeCategory, 3);

        address user = makeAddr("btcEmodeUser");

        // Supply LBTC as collateral
        _supply(lbtcConfig, ctx.pool, user, 1e8);

        // Set user e-mode to 3
        vm.prank(user);
        ctx.pool.setUserEMode(3);

        assertEq(ctx.pool.getUserEMode(user), 3);

        // Borrow cbBTC (also in emode 3, borrowing enabled)
        _borrow(cbbtcConfig, ctx.pool, user, 0.5e8, false);

        uint256 debtBefore = IERC20(cbbtcConfig.variableDebtToken).balanceOf(user);

        ( , , , , , uint256 healthFactorBefore ) = ctx.pool.getUserAccountData(user);

        _executeAllPayloadsAndBridges();

        // Debt persists after the spell
        uint256 debtAfter = IERC20(cbbtcConfig.variableDebtToken).balanceOf(user);
        assertApproxEqAbs(debtAfter, debtBefore, 1);

        // User's emode setting is unchanged by the spell (only reserve configs change)
        assertEq(ctx.pool.getUserEMode(user), 3);

        // HF drops: LBTC collateral now uses normal LT instead of emode LT (category mismatch)
        ( , , , , , uint256 healthFactorAfter ) = ctx.pool.getUserAccountData(user);
        assertLt(healthFactorAfter, healthFactorBefore);
        assertGt(healthFactorAfter, 1e18);

        // Borrow again with normal LT fails when user emode is set to 3.
        vm.expectRevert(abi.encode("58"));  // INCONSISTENT_EMODE_CATEGORY
        ctx.pool.borrow(Ethereum.CBBTC, 0.1e8, 2, 0, user);

        // Set user emode to 0
        vm.prank(user);
        ctx.pool.setUserEMode(0);

        // Borrow again with normal LT succeeds
        _borrow(cbbtcConfig, ctx.pool, user, 0.1e8, false);

        ( , , , , , uint256 healthFactorAfter2 ) = ctx.pool.getUserAccountData(user);
        assertGt(healthFactorAfter2, 1e18);

        // Repay works as expected
        _repay(cbbtcConfig, ctx.pool, user, 0.6e8, false);

        ( , , , , , uint256 healthFactorAfter3 ) = ctx.pool.getUserAccountData(user);
        assertGt(healthFactorAfter3, healthFactorAfter2);
    }

    function test_ETHEREUM_btcEmodeBorrowPositionLiquidatableAfterDeprecationE2E() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigs = _createConfigurationSnapshot("", ctx.pool);

        ReserveConfig memory lbtcConfig  = _findReserveConfigBySymbol(allConfigs, "LBTC");
        ReserveConfig memory cbbtcConfig = _findReserveConfigBySymbol(allConfigs, "cbBTC");

        address user       = makeAddr("btcEmodeUser");
        address liquidator = makeAddr("liquidator");

        _supply(lbtcConfig, ctx.pool, user, 1e8);

        vm.prank(user);
        ctx.pool.setUserEMode(3);

        DataTypes.EModeCategory memory emodeCategory = ctx.pool.getEModeCategoryData(3);

        uint256 collateralBase = ctx.priceOracle.getAssetPrice(Ethereum.LBTC);  // collateral base value = 1e8 * lbtcPrice / 1e8 = lbtcPrice
        uint256 debtBase       = collateralBase * ((emodeCategory.liquidationThreshold + lbtcConfig.liquidationThreshold) / 2) / 10000;
        uint256 borrowAmount   = debtBase * 1e8 / ctx.priceOracle.getAssetPrice(Ethereum.CBBTC);

        _borrow(cbbtcConfig, ctx.pool, user, borrowAmount, false);

        ( , , , , , uint256 healthFactorBefore ) = ctx.pool.getUserAccountData(user);
        assertGt(healthFactorBefore, 1e18);

        _executeAllPayloadsAndBridges();

        // LBTC no longer in eMode 3 → normal (lower) LT applies → position is under water
        ( , , , , , uint256 healthFactorAfter ) = ctx.pool.getUserAccountData(user);
        assertLt(healthFactorAfter, 1e18);

        // Liquidate the position
        uint256 debtToCover = IERC20(cbbtcConfig.variableDebtToken).balanceOf(user);
        deal(Ethereum.CBBTC, liquidator, debtToCover);

        vm.startPrank(liquidator);
        IERC20(Ethereum.CBBTC).approve(address(ctx.pool), debtToCover);
        ctx.pool.liquidationCall(Ethereum.LBTC, Ethereum.CBBTC, user, debtToCover, false);
        vm.stopPrank();

        assertEq(IERC20(cbbtcConfig.variableDebtToken).balanceOf(user), 0);      // User debt is reduced.
        assertGt(IERC20(Ethereum.LBTC).balanceOf(liquidator),           0.8e8); // Liquidator receives collateral.
    }

    function test_ETHEREUM_sparkLend_deprecateBTCeMode() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot("", ctx.pool);

        ReserveConfig memory cbbtc = _findReserveConfigBySymbol(allConfigsBefore, "cbBTC");
        assertEq(cbbtc.eModeCategory, 3);

        ReserveConfig memory lbtc = _findReserveConfigBySymbol(allConfigsBefore, "LBTC");
        assertEq(lbtc.eModeCategory, 3);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot("", ctx.pool);

        cbbtc.eModeCategory = 0;
        lbtc.eModeCategory  = 0;

        _validateReserveConfig(cbbtc, allConfigsAfter);
        _validateReserveConfig(lbtc,  allConfigsAfter);
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

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WSTETH, uint48(ReserveConfiguration.MAX_VALID_SUPPLY_CAP), 50_000, 4 hours);
    }

    function test_ETHEREUM_sparkLend_weethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WEETH, 500_000, 10_000, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WEETH, 500_000, 10_000, 4 hours);
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
        _blockDate = 1779776905;  // 2026-05-26T06:28:25Z
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
