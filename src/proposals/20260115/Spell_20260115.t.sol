// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { VmSafe }   from "forge-std/Vm.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

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

contract SparkEthereum_20260115_SLLTests is SparkLiquidityLayerTests {

    address internal constant PAXOS_PYUSD_DEPOSIT         = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant PAXOS_USDC_DEPOSIT          = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant NATIVE_MARKETS_USDC_DEPOSIT = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    constructor() {
        _spellId   = 20260115;
        _blockDate = "2025-12-05T20:22:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        // chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;

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

    function test_ETHEREUM_onboardingPaxosPYUSD() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.PYUSD,
            PAXOS_PYUSD_DEPOSIT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.PYUSD,
            destination    : PAXOS_PYUSD_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingPaxosUSDC() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            PAXOS_USDC_DEPOSIT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : PAXOS_USDC_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingNativeMarketsUSDC() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            NATIVE_MARKETS_USDC_DEPOSIT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : NATIVE_MARKETS_USDC_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

}

contract SparkEthereum_20260115_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260115;
        _blockDate = "2025-12-05T20:22:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        // chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;
    }

}

contract SparkEthereum_20260115_SpellTests is SpellTests {

    uint256 internal constant AMOUNT_TO_ASSET_FOUNDATION = 150_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION       = 1_100_000e18;

    address internal constant SPARK_ASSET_FOUNDATION = 0xEabCb8C0346Ac072437362f1692706BA5768A911;

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-05T20:22:00Z";
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  332_002_039.178521473742590212e18);
        assertEq(spUsdsBalanceBefore, 136_251_424.780206889676968590e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 15_756.779034768510527762e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 6_401.767666973662845681e18);
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 250_000_000e6);
        assertEq(ethVault.depositCap(),  50_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(ethVault.depositCap(),  100_000e18);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 416_135_998.065359e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              ethVault,
            depositCap:         100_000e18,
            expectedMaxDeposit: 89_699.926630313941789731e18
        });
    }

}
