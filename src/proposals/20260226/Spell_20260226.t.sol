// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

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
    IMorphoVaultV2Like
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20260226_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant PAXOS_PYUSD_USDC = 0x2f7BE67e11A4D621E36f1A8371b0a5Fe16dE6B20;
    address internal constant PAXOS_PYUSD_USDG = 0x227B1912C2fFE1353EA3A603F1C05F030Cc262Ff;
    address internal constant PAXOS_USDC_PYUSD = 0xFb1F749024b4544c425f5CAf6641959da31EdF37;
    address internal constant PAXOS_USDG_PYUSD = 0x035b322D0e79de7c8733CdDA5a7EF8b51a6cfcfa;

    constructor() {
        _spellId   = 20260226;
        _blockDate = 1771226481;  // 2026-02-16T07:21:21Z
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
        _assertRateLimit(withdrawKey, 50_000_000e6, 500_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(redeemKey);

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

    function test_ETHEREUM_morphoVaultV2Creation() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 createVaultV2Sig = keccak256("CreateVaultV2(address,address,bytes32,address)");

        // Start the recorder
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        VmSafe.Log[] memory allLogs = RecordedLogs.getLogs();

        address vault_addr;

        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics[0] == createVaultV2Sig) {
                vault_addr = address(uint160(uint256(allLogs[i].topics[3])));
                break;
            }
        }

        require(vault_addr != address(0), "Vault not found");

        IMorphoVaultV2Like vault = IMorphoVaultV2Like(vault_addr);

        assertEq(vault.asset(),                                       Ethereum.USDT);
        assertEq(vault.isAllocator(Ethereum.ALM_PROXY),               true);
        assertEq(vault.owner(),                                       Ethereum.SPARK_PROXY);
        assertEq(vault.curator(),                                     Ethereum.MORPHO_CURATOR_MULTISIG);
        assertEq(vault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG), true);

        assertEq(vault.totalAssets(),                          1e6);
        assertEq(IERC20(address(vault)).balanceOf(address(1)), 1e18);

        _testERC4626Onboarding(address(vault), 5_000_000e6, 50_000_000e6, 1_000_000_000e6 / uint256(1 days), 10, true);
    }

}

contract SparkEthereum_20260226_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260226;
        _blockDate = 1771226481;  // 2026-02-16T07:21:21Z
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
        _blockDate = 1771226481;  // 2026-02-16T07:21:21Z
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
        assertEq(foundationBalanceBefore,  400_000e18);
        assertEq(opsMultisigBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkBalanceBefore - FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_OPS_MULTISIG),          opsMultisigBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
