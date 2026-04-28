// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";
import { Id }           from "metamorpho/interfaces/IMetaMorpho.sol";
import { IMorpho }      from "metamorpho/interfaces/IMetaMorpho.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    IMorphoVaultV2Like,
    IMorphoLike
} from "src/interfaces/Interfaces.sol";

interface IEndpointV2 {
    function getConfig(address receiver, address uln, uint32 eid, uint32 configType) external view returns (bytes memory);
}

interface IMorphoVaultV2FactoryLike {
    function isVaultV2(address target) external view returns (bool);
}

contract SparkEthereum_20260507_SLLTests is SparkLiquidityLayerTests {

    // the formal properties are documented in the setter functions
    struct UlnConfig {
        uint64    confirmations;
        // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
        uint8     requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNThreshold; // (0, optionalDVNCount]
        address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
        address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
    }

    address internal constant LAYERZERO_ENDPOINT_V2   = 0x1a44076050125825900e736c501f859c50fE728c;

    address internal constant ADAPTER_REGISTRY        = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    address internal constant MORPHO                  = Ethereum.MORPHO;
    address internal constant MORPHO_VAULT_V2_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;

    address internal constant OLD_MORPHO_VAULT_V2_USDT = Ethereum.MORPHO_VAULT_V2_USDT;
    address internal constant NEW_MORPHO_VAULT_V2_USDT = 0xb0c424116172B55CbB6dD3136F5989F7959e5B91;

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1777302000;  // 2026-04-27T15:00:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
        // chainData[ChainIdUtils.Avalanche()].payload = ;
    }

    /**********************************************************************************************/
    /*** Ethereum - Offboard Aave Core USDT                                                     ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateAaveCoreUsdt() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDT);

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    /**********************************************************************************************/
    /*** Avalanche - Offboard Aave USDC                                                         ***/
    /**********************************************************************************************/

    function test_AVALANCHE_sll_deactivateAaveCoreUsdc() external onChain(ChainIdUtils.Avalanche()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Avalanche.ATOKEN_CORE_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Avalanche.ATOKEN_CORE_USDC);

        _assertRateLimit(depositKey,  20_000_000e6,     10_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }
    
    /**********************************************************************************************/
    /*** Avalanche - Update Bridge DVN Configuration                                            ***/
    /**********************************************************************************************/

    function test_AVALANCHE_sll_updateBridgeDvnConfiguration() external onChain(ChainIdUtils.Avalanche()) {
        IEndpointV2 endpoint = IEndpointV2(LAYERZERO_ENDPOINT_V2);

        address receiveUln302 = 0xbf3521d309642FA9B1c91A08609505BA09752c61;

        bytes memory configBytes = endpoint.getConfig(
            Avalanche.SPARK_RECEIVER,
            receiveUln302,
            30101,  // eid 30101 is for Ethereum Mainnet
            2       // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        // Verify the old config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     2,                                          "requiredDVNCount should be 2");
        assertEq(config.optionalDVNCount,     0,                                          "optionalDVNCount should be 0");
        assertEq(config.optionalDVNThreshold, 0,                                          "optionalDVNThreshold should be 0");
        assertEq(config.requiredDVNs.length,  2,                                          "requiredDVNs length should be 2");
        assertEq(config.requiredDVNs[0],      0x962F502A63F5FBeB44DC9ab932122648E8352959, "first DVN should be LayerZero Labs");
        assertEq(config.requiredDVNs[1],      0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc, "second DVN should be Google");
        assertEq(config.optionalDVNs.length,  0,                                          "optionalDVNs length should be 0");

        _executeAllPayloadsAndBridges();

        configBytes = endpoint.getConfig(
            Avalanche.SPARK_RECEIVER,
            receiveUln302,
            30101,  // eid 30101 is for Ethereum Mainnet
            2       // configType 2 is for UlnConfig
        );
        config = abi.decode(configBytes, (UlnConfig));

        // Verify the new config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     0,                                          "requiredDVNCount should be 0");
        assertEq(config.optionalDVNCount,     7,                                          "optionalDVNCount should be 7");
        assertEq(config.optionalDVNThreshold, 4,                                          "optionalDVNThreshold should be 4");
        assertEq(config.requiredDVNs.length,  0,                                          "requiredDVNs length should be 0");
        assertEq(config.optionalDVNs.length,  7,                                          "optionalDVNs length should be 7");
        assertEq(config.optionalDVNs[0],      0x07C05EaB7716AcB6f83ebF6268F8EECDA8892Ba1, "first DVN should be Horizen");
        assertEq(config.optionalDVNs[1],      0x962F502A63F5FBeB44DC9ab932122648E8352959, "second DVN should be LayerZero Labs");
        assertEq(config.optionalDVNs[2],      0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5, "third DVN should be Nethermind");
        assertEq(config.optionalDVNs[3],      0xbe57e9E7d9eB16B92C6383792aBe28D64a18c0F1, "fourth DVN should be Deutsche Telekom");
        assertEq(config.optionalDVNs[4],      0xcC49E6fca014c77E1Eb604351cc1E08C84511760, "fifth DVN should be Canary");
        assertEq(config.optionalDVNs[5],      0xE4193136B92bA91402313e95347c8e9FAD8d27d0, "sixth DVN should be Luganodes");
        assertEq(config.optionalDVNs[6],      0xE94aE34DfCC87A61836938641444080B98402c75, "seventh DVN should be P2P");
    }

    function test_ETHEREUM_sll_updateBridgeDvnConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        IEndpointV2 endpoint = IEndpointV2(LAYERZERO_ENDPOINT_V2);

        address sendUln302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;

        bytes memory configBytes = endpoint.getConfig(
            Ethereum.SPARK_PROXY,
            sendUln302,
            30106,  // eid 30106 is for Avalanche
            2       // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        // Verify the old config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     2,                                          "requiredDVNCount should be 2");
        assertEq(config.optionalDVNCount,     0,                                          "optionalDVNCount should be 0");
        assertEq(config.optionalDVNThreshold, 0,                                          "optionalDVNThreshold should be 0");
        assertEq(config.requiredDVNs.length,  2,                                          "requiredDVNs length should be 2");
        assertEq(config.requiredDVNs[0],      0x589dEDbD617e0CBcB916A9223F4d1300c294236b, "first DVN should be LayerZero Labs");
        assertEq(config.requiredDVNs[1],      0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc, "second DVN should be Google");
        assertEq(config.optionalDVNs.length,  0,                                          "optionalDVNs length should be 0");

        _executeAllPayloadsAndBridges();

        configBytes = endpoint.getConfig(
            Ethereum.SPARK_PROXY,
            sendUln302,
            30106,  // eid 30106 is for Avalanche
            2       // configType 2 is for UlnConfig
        );
        config = abi.decode(configBytes, (UlnConfig));

        // Verify the new config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     0,                                          "requiredDVNCount should be 0");
        assertEq(config.optionalDVNCount,     7,                                          "optionalDVNCount should be 7");
        assertEq(config.optionalDVNThreshold, 4,                                          "optionalDVNThreshold should be 4");
        assertEq(config.requiredDVNs.length,  0,                                          "requiredDVNs length should be 0");
        assertEq(config.optionalDVNs.length,  7,                                          "optionalDVNs length should be 7");
        assertEq(config.optionalDVNs[0],      0x06559EE34D85a88317Bf0bfE307444116c631b67, "first DVN should be P2P");
        assertEq(config.optionalDVNs[1],      0x373a6E5c0C4E89E24819f00AA37ea370917AAfF4, "second DVN should be Deutsche Telekom");
        assertEq(config.optionalDVNs[2],      0x380275805876Ff19055EA900CDb2B46a94ecF20D, "third DVN should be Horizen");
        assertEq(config.optionalDVNs[3],      0x58249a2Ec05c1978bF21DF1f5eC1847e42455CF4, "fourth DVN should be Luganodes");
        assertEq(config.optionalDVNs[4],      0x589dEDbD617e0CBcB916A9223F4d1300c294236b, "fifth DVN should be LayerZero Labs");
        assertEq(config.optionalDVNs[5],      0xa4fE5A5B9A846458a70Cd0748228aED3bF65c2cd, "sixth DVN should be Canary");
        assertEq(config.optionalDVNs[6],      0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5, "seventh DVN should be Nethermind");
    }

    /**********************************************************************************************/
    /*** Ethereum - Onboard new Morpho Vault V2 USDT                                              ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateMorphoVaultV2Usdt() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  OLD_MORPHO_VAULT_V2_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), OLD_MORPHO_VAULT_V2_USDT);

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0,                 0);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);
    }

    function test_ETHEREUM_sll_onboardNewMorphoVaultV2Usdt() external onChain(ChainIdUtils.Ethereum()) {
        _testERC4626Onboarding({
            vault                 : NEW_MORPHO_VAULT_V2_USDT,
            expectedDepositAmount : 10_000_000e6,
            depositMax            : 100_000_000e6,
            depositSlope          : 1_000_000_000e6 / uint256(1 days),
            tolerance             : 10,
            skipInitialCheck      : false
        });
    }

    function test_ETHEREUM_sll_switchMorphoVaultV2Usdt() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultV2Like oldVault = IMorphoVaultV2Like(OLD_MORPHO_VAULT_V2_USDT);
        IMorphoVaultV2Like newVault = IMorphoVaultV2Like(NEW_MORPHO_VAULT_V2_USDT);

        assertEq(IMorphoVaultV2FactoryLike(MORPHO_VAULT_V2_FACTORY).isVaultV2(address(oldVault)), true);
        assertEq(IMorphoVaultV2FactoryLike(MORPHO_VAULT_V2_FACTORY).isVaultV2(address(newVault)), true);

        // Old vault adapter registry is not set, new vault adapter registry is set to the ADAPTER_REGISTRY.
        assertEq(oldVault.adapterRegistry(), address(0));
        assertEq(newVault.adapterRegistry(), ADAPTER_REGISTRY);

        assertEq(oldVault.adaptersLength(), newVault.adaptersLength());
        assertEq(oldVault.asset(),          newVault.asset());
        assertEq(oldVault.curator(),        newVault.curator());
        assertEq(oldVault.decimals(),       newVault.decimals());
        assertEq(oldVault.managementFee(),  newVault.managementFee());
        assertEq(oldVault.name(),           newVault.name());
        assertEq(oldVault.owner(),          newVault.owner());
        assertEq(oldVault.performanceFee(), newVault.performanceFee());
        assertEq(oldVault.symbol(),         newVault.symbol());

        assertEq(oldVault.isAllocator(Ethereum.ALM_PROXY_FREEZABLE),     newVault.isAllocator(Ethereum.ALM_PROXY_FREEZABLE));
        assertEq(oldVault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG), newVault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG));

        // Verify `SetIsSentinel` event emitted only once for new vault.
        VmSafe.EthGetLogs[] memory sentinelLogs = _getEvents(block.chainid, address(newVault), IMorphoVaultV2Like.SetIsSentinel.selector);

        assertEq(sentinelLogs.length,                                  1);
        assertEq(address(uint160(uint256(sentinelLogs[0].topics[1]))), Ethereum.MORPHO_GUARDIAN_MULTISIG);
        assertEq(bool(abi.decode(sentinelLogs[0].data, (bool))),       true);
    }

    /// forge-config: default.isolate = true
    function test_ETHEREUM_sll_morphoVaultV2UsdtE2E() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 SUSDS_USDT_MARKET_ID = 0x3274643db77a064abd3bc851de77556a4ad2e2f502f4f0c80845fa8f909ecf0b;
        bytes32 CBBTC_USDT_MARKET_ID = 0x45671fb8d5dea1c4fbca0b8548ad742f6643300eeb8dbd34ad64a658b2b05bca;

        IMorphoVaultV2Like vault = IMorphoVaultV2Like(NEW_MORPHO_VAULT_V2_USDT);

        address adapter = vault.adapters(0);

        _executeAllPayloadsAndBridges();

        // Step 1: Deposit to the vault.
        uint256 depositAmount = 50_000_000e6;
        deal(Ethereum.USDT, Ethereum.ALM_PROXY, depositAmount);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        _depositERC4626(Ethereum.ALM_CONTROLLER, address(vault), depositAmount);

        assertEq(vault.balanceOf(Ethereum.ALM_PROXY), 49_891_038.082032758623196585e18);

        IMorphoLike.Position memory position = IMorphoLike(Ethereum.MORPHO).position(Id.wrap(SUSDS_USDT_MARKET_ID), adapter);

        assertGe(position.supplyShares, 45_000_000e12);

        assertEq(vault.convertToAssets(vault.balanceOf(Ethereum.ALM_PROXY)), depositAmount + 241);

        vm.warp(block.timestamp + 1 days);

        vault.accrueInterest();

        assertEq(vault.convertToAssets(vault.balanceOf(Ethereum.ALM_PROXY)), depositAmount + 2_389.182391e6);

        // Step 2: Reallocate into cbbtc/usdt market.
        uint256 withdrawAmount = depositAmount;

        MarketParams memory susdsMarketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(SUSDS_USDT_MARKET_ID));
        MarketParams memory cbbtcMarketParams = IMorpho(MORPHO).idToMarketParams(Id.wrap(CBBTC_USDT_MARKET_ID));

        vm.startPrank(Ethereum.ALM_PROXY_FREEZABLE);

        vault.deallocate(adapter, abi.encode(susdsMarketParams), withdrawAmount);
        vault.allocate(adapter,   abi.encode(cbbtcMarketParams), withdrawAmount);

        vm.stopPrank();

        // Step 3: Try to withdraw (fails because there is not enough liquidity in the sUSDS/USDT market anymore)
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        _withdrawERC4626(Ethereum.ALM_CONTROLLER, address(vault), withdrawAmount);

        vm.warp(block.timestamp + 1 days);

        // Step 4: Reallocate back to sUSDS/USDT market.
        vm.startPrank(Ethereum.ALM_PROXY_FREEZABLE);

        vault.deallocate(adapter, abi.encode(cbbtcMarketParams), withdrawAmount);

        vault.allocate(adapter, abi.encode(susdsMarketParams), withdrawAmount);

        vm.stopPrank();

        // Step 5: Do successful withdrawal.
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        _withdrawERC4626(Ethereum.ALM_CONTROLLER, address(vault), withdrawAmount);

        // Assert that Interest Remains after withdrawal.
        assertEq(vault.convertToAssets(vault.balanceOf(Ethereum.ALM_PROXY)), 2_602.279771e6);
    }

}

contract SparkEthereum_20260507_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1777302000;  // 2026-04-27T15:00:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
        // chainData[ChainIdUtils.Avalanche()].payload = ;
    }

    /**********************************************************************************************/
    /*** Ethereum - Update LBTC and WBTC CapAutomator Supply Caps                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 500, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 5_000, 200, 12 hours);
    }

    function test_ETHEREUM_sparkLend_wbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WBTC, 3_000, 500, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WBTC, 30_000, 500, 12 hours);
    }

}

contract SparkEthereum_20260507_SpellTests is SpellTests {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 326_945e18;

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1777302000;  // 2026-04-27T15:00:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
        // chainData[ChainIdUtils.Avalanche()].payload = ;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore          = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      36_899_113.913977620254401020e18);
        assertEq(foundationBalanceBefore,      1_100_000.0095e18);
        assertEq(assetFoundationBalanceBefore, 242_000e18);
        assertEq(almOpsBalanceBefore,          0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
