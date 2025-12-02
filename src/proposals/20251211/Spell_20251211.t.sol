// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";

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

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant AVALANCHE_ALM_PROXY_FREEZABLE = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;
    address internal constant BASE_ALM_PROXY_FREEZABLE      = 0xCBA0C0a2a0B6Bb11233ec4EA85C5bFfea33e724d;
    address internal constant ETHEREUM_ALM_PROXY_FREEZABLE  = 0x9Ad87668d49ab69EEa0AF091de970EF52b0D5178;
    address internal constant SPARK_VAULT_V2_SPPYUSD        = 0x80128DbB9f07b93DDE62A6daeadb69ED14a7D354;

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

    function test_ETHEREUM_sparkVaultsV2_configureSPPYUSD() external onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.PYUSD,
            name:       "Spark Savings PYUSD",
            symbol:     "spPYUSD",
            rho:        1764599075,
            vault_:     SPARK_VAULT_V2_SPPYUSD,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 250_000_000e6,
            amount:     1_000_000e6
        });
    }

    function test_ETHEREUM_roleChanges() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxy         proxy       = IALMProxy(ETHEREUM_ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like spUSDCvault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like spUSDTvault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like spETHvault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Ethereum.ALM_RELAYER_MULTISIG));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG));
        assertFalse(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Ethereum.ALM_FREEZER_MULTISIG));

        assertTrue(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertTrue(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertTrue(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_OPS_MULTISIG));

        assertFalse(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), ETHEREUM_ALM_PROXY_FREEZABLE));
        assertFalse(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), ETHEREUM_ALM_PROXY_FREEZABLE));
        assertFalse(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   ETHEREUM_ALM_PROXY_FREEZABLE));

        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(ETHEREUM_ALM_PROXY_FREEZABLE));
        assertFalse(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(ETHEREUM_ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Ethereum.ALM_RELAYER_MULTISIG));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG));
        assertTrue(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Ethereum.ALM_FREEZER_MULTISIG));

        assertFalse(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertFalse(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));
        assertFalse(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   Ethereum.ALM_OPS_MULTISIG));

        assertTrue(spUSDCvault.hasRole(spUSDCvault.SETTER_ROLE(), ETHEREUM_ALM_PROXY_FREEZABLE));
        assertTrue(spUSDTvault.hasRole(spUSDTvault.SETTER_ROLE(), ETHEREUM_ALM_PROXY_FREEZABLE));
        assertTrue(spETHvault.hasRole(spETHvault.SETTER_ROLE(),   ETHEREUM_ALM_PROXY_FREEZABLE));
    
        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).isAllocator(ETHEREUM_ALM_PROXY_FREEZABLE));
        assertTrue(IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).isAllocator(ETHEREUM_ALM_PROXY_FREEZABLE));
    }

    function test_AVALANCHE_roleUpdates() external onChain(ChainIdUtils.Avalanche()) {
        IALMProxy         proxy = IALMProxy(AVALANCHE_ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER2));
        assertFalse(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Avalanche.ALM_FREEZER));

        assertTrue(vault.hasRole(vault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));

        assertFalse(vault.hasRole(vault.SETTER_ROLE(), AVALANCHE_ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER2));
        assertTrue(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Avalanche.ALM_FREEZER));

        assertFalse(vault.hasRole(vault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG));

        assertTrue(vault.hasRole(vault.SETTER_ROLE(), AVALANCHE_ALM_PROXY_FREEZABLE));
    }

    function test_BASE_roleUpdates() external onChain(ChainIdUtils.Base()) {
        IALMProxy proxy = IALMProxy(BASE_ALM_PROXY_FREEZABLE);

        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER));
        assertFalse(proxy.hasRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER2));
        assertFalse(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Base.ALM_FREEZER));

        assertFalse(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(BASE_ALM_PROXY_FREEZABLE));

        _executeAllPayloadsAndBridges();

        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER));
        assertTrue(proxy.hasRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER2));
        assertTrue(proxy.hasRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Base.ALM_FREEZER));

        assertTrue(IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).isAllocator(BASE_ALM_PROXY_FREEZABLE));
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

        assertEq(spDaiBalanceBefore,  355_997_143.466638232280558708e18);
        assertEq(spUsdsBalanceBefore, 549_084_070.848804689610030281e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 17_949.997576019611612844e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 22_771.1195233143918119e18);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore           = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION);

        assertEq(sparkUsdsBalanceBefore,           32_097_248.445801365846236778e18);
        assertEq(foundationUsdsBalanceBefore,      0);
        assertEq(assetFoundationUsdsBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkUsdsBalanceBefore - AMOUNT_TO_ASSET_FOUNDATION - AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationUsdsBalanceBefore + AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION),             assetFoundationUsdsBalanceBefore + AMOUNT_TO_ASSET_FOUNDATION);
    }

}
