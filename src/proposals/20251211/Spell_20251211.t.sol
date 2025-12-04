// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ISyrupLike,
    ISparkVaultV2Like,
    IALMProxyFreezableLike,
    IMorphoVaultLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20251211_SLLTests is SparkLiquidityLayerTests {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-02T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;

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

    function test_ETHEREUM_onboardingAnchorage() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            ANCHORAGE
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : ANCHORAGE,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingArkis() external onChain(ChainIdUtils.Ethereum()) {
        _testERC4626Onboarding({
            vault                 : ARKIS,
            expectedDepositAmount : 1_000_000e6,
            depositMax            : 5_000_000e6,
            depositSlope          : 5_000_000e6 / uint256(1 days),
            tolerance             : 10,
            skipInitialCheck      : false
        });
    }

    function test_ETHEREUM_sparkVaultsV2_configureSPPYUSD() external onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.PYUSD,
            name:       "Spark Savings PYUSD",
            symbol:     "spPYUSD",
            rho:        1764599075,
            vault_:     Ethereum.SPARK_VAULT_V2_SPPYUSD,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 250_000_000e6,
            amount:     1_000_000e6
        });
    }

    function test_ETHEREUM_roleChanges() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like spUSDCvault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like spUSDTvault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like spETHvault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertTrue(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertTrue(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertTrue(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_OPS_MULTISIG));

        assertFalse(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE));
        assertFalse(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE));
        assertFalse(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_PROXY_FREEZABLE));

        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(Ethereum.ALM_RELAYER_MULTISIG));
        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(Ethereum.ALM_RELAYER_MULTISIG));

        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(Ethereum.ALM_PROXY_FREEZABLE));
        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(Ethereum.ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertEq(spUSDCvault.getRoleMemberCount(spUSDCvault.SETTER_ROLE()), 1);
        assertEq(spUSDTvault.getRoleMemberCount(spUSDTvault.SETTER_ROLE()), 1);
        assertEq(spETHvault.getRoleMemberCount(spETHvault.SETTER_ROLE()),   1);

        assertFalse(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertFalse(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertFalse(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_OPS_MULTISIG));

        assertTrue(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE));
        assertTrue(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE));
        assertTrue(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_PROXY_FREEZABLE));

        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(Ethereum.ALM_RELAYER_MULTISIG));
        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(Ethereum.ALM_RELAYER_MULTISIG));
    
        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(Ethereum.ALM_PROXY_FREEZABLE));
        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(Ethereum.ALM_PROXY_FREEZABLE));
    }

    function test_ETHEREUM_ALM_PROXY_FREEZABLE() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Ethereum.ALM_PROXY_FREEZABLE);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Ethereum.ALM_RELAYER_MULTISIG));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG));
        assertFalse(proxy.hasRole(proxy.FREEZER(),    Ethereum.ALM_FREEZER_MULTISIG));

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Ethereum.SPARK_PROXY);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Ethereum.ALM_RELAYER_MULTISIG));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG));
        assertTrue(proxy.hasRole(proxy.FREEZER(),    Ethereum.ALM_FREEZER_MULTISIG));

        VmSafe.Log[] memory recLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recLogs.length; ++i) {
            if (recLogs[i].topics[0] == RoleGranted.selector) {
                newLogs[j] = recLogs[i];
                j++;
            }
        }

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());
        assertEq32(newLogs[3].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[4].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[5].topics[1], proxy.FREEZER());
        assertEq32(newLogs[6].topics[1], ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Ethereum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Ethereum.ALM_FREEZER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[3].topics[2]))), Avalanche.ALM_RELAYER);
        assertEq(address(uint160(uint256(newLogs[4].topics[2]))), Avalanche.ALM_RELAYER2);
        assertEq(address(uint160(uint256(newLogs[5].topics[2]))), Avalanche.ALM_FREEZER);
        assertEq(address(uint160(uint256(newLogs[6].topics[2]))), Avalanche.ALM_PROXY_FREEZABLE);
    }

    function test_AVALANCHE_roleUpdates() external onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertTrue(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_OPS_MULTISIG));

        assertFalse(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertFalse(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_OPS_MULTISIG));

        assertTrue(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE));

        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()), 1);
    }

    function test_AVALANCHE_ALM_PROXY_FREEZABLE() external onChain(ChainIdUtils.Avalanche()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Avalanche.ALM_PROXY_FREEZABLE);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Avalanche.ALM_RELAYER));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Avalanche.ALM_RELAYER2));
        assertFalse(proxy.hasRole(proxy.FREEZER(),    Avalanche.ALM_FREEZER));

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Avalanche.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Avalanche.ALM_RELAYER));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Avalanche.ALM_RELAYER2));
        assertTrue(proxy.hasRole(proxy.FREEZER(),    Avalanche.ALM_FREEZER));

        VmSafe.Log[] memory recLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recLogs.length; ++i) {
            if (recLogs[i].topics[0] == RoleGranted.selector) {
                newLogs[j] = recLogs[i];
                j++;
            }
        }

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());
        assertEq32(newLogs[3].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[4].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[5].topics[1], proxy.FREEZER());
        assertEq32(newLogs[6].topics[1], ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Ethereum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Ethereum.ALM_FREEZER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[3].topics[2]))), Avalanche.ALM_RELAYER);
        assertEq(address(uint160(uint256(newLogs[4].topics[2]))), Avalanche.ALM_RELAYER2);
        assertEq(address(uint160(uint256(newLogs[5].topics[2]))), Avalanche.ALM_FREEZER);
        assertEq(address(uint160(uint256(newLogs[6].topics[2]))), Avalanche.ALM_PROXY_FREEZABLE);
    }

    function test_BASE_roleUpdates() external onChain(ChainIdUtils.Base()) {
        assertTrue(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(Base.ALM_RELAYER));

        assertFalse(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(Base.ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertFalse(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(Base.ALM_RELAYER));

        assertTrue(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(Base.ALM_PROXY_FREEZABLE));
    }

    function test_BASE_ALM_PROXY_FREEZABLE() external onChain(ChainIdUtils.Base()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Base.ALM_PROXY_FREEZABLE);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Base.ALM_RELAYER));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(), Base.ALM_RELAYER2));
        assertFalse(proxy.hasRole(proxy.FREEZER(),    Base.ALM_FREEZER));

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Base.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Base.ALM_RELAYER));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(), Base.ALM_RELAYER2));
        assertTrue(proxy.hasRole(proxy.FREEZER(),    Base.ALM_FREEZER));

        VmSafe.Log[] memory recLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recLogs.length; ++i) {
            if (recLogs[i].topics[0] == RoleGranted.selector) {
                newLogs[j] = recLogs[i];
                j++;
            }
        }

        assertEq(newLogs.length, 7);

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());
        assertEq32(newLogs[3].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[4].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[5].topics[1], proxy.FREEZER());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Ethereum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Ethereum.ALM_FREEZER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[3].topics[2]))), Avalanche.ALM_RELAYER);
        assertEq(address(uint160(uint256(newLogs[4].topics[2]))), Avalanche.ALM_RELAYER2);
        assertEq(address(uint160(uint256(newLogs[5].topics[2]))), Avalanche.ALM_FREEZER);
    }

}

contract SparkEthereum_20251211_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-02T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;
    }

}

contract SparkEthereum_20251211_SpellTests is SpellTests {

    uint256 internal constant AMOUNT_TO_ASSET_FOUNDATION = 150_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION       = 1_100_000e18;

    address internal constant SPARK_ASSET_FOUNDATION = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-02T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  345_775_075.648347910394560559e18);
        assertEq(spUsdsBalanceBefore, 182_567_680.712149092854209493e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 3_568.313310802219726430e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 1_612.873159374336061895e18);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore           = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION);

        assertEq(sparkUsdsBalanceBefore,           31_639_488.445801365846236778e18);
        assertEq(foundationUsdsBalanceBefore,      510_000e18);
        assertEq(assetFoundationUsdsBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkUsdsBalanceBefore - AMOUNT_TO_ASSET_FOUNDATION - AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationUsdsBalanceBefore + AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION),             assetFoundationUsdsBalanceBefore + AMOUNT_TO_ASSET_FOUNDATION);
    }

}
