// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { ChainIdUtils }         from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    IMorphoVaultLike,
    ISparkVaultV2Like,
    ISyrupLike
} from "src/interfaces/Interfaces.sol";

interface IChainlinkAggregator {
    function latestAnswer() external view returns (int256);
}

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }
    
}

contract SparkEthereum_20260115_SLLTests is SparkLiquidityLayerTests {

    address internal constant PAXOS_PYUSD_DEPOSIT         = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant PAXOS_USDC_DEPOSIT          = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant NATIVE_MARKETS_USDC_DEPOSIT = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

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

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

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
        IERC20(asset).approve(address(vault), maxDeposit);

        uint256 shares = vault.deposit(maxDeposit, address(this));

        assertEq(vault.balanceOf(address(this)), shares);
    }

    function test_ETHEREUM_killSwitchActivationForLBTC() external onChain(ChainIdUtils.Ethereum()) {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),                           2);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE),      0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),                      2);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0.95e8);
        
        // Sanity check the latest answers
        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(),  1.00020160e8);

        // Should not be able to trigger either
        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(LBTC_BTC_ORACLE);

        // Replace both Chainlink aggregators with MockAggregators reporting below
        // threshold prices
        vm.store(
            LBTC_BTC_ORACLE,
            bytes32(uint256(2)),
            bytes32((uint256(uint160(address(new MockAggregator(0.95e8)))) << 16) | 1)
        );

        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 0.95e8);

        assertEq(kso.triggered(), false);

        assertEq(_getBorrowEnabled(Ethereum.DAI),    true);
        assertEq(_getBorrowEnabled(Ethereum.SDAI),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDC),   true);
        assertEq(_getBorrowEnabled(Ethereum.WETH),   true);
        assertEq(_getBorrowEnabled(Ethereum.WSTETH), true);
        assertEq(_getBorrowEnabled(Ethereum.WBTC),   true);
        assertEq(_getBorrowEnabled(Ethereum.GNO),    false);
        assertEq(_getBorrowEnabled(Ethereum.RETH),   true);
        assertEq(_getBorrowEnabled(Ethereum.USDT),   true);
        assertEq(_getBorrowEnabled(Ethereum.LBTC),   true);

        kso.trigger(LBTC_BTC_ORACLE);

        assertEq(kso.triggered(), true);

        assertEq(_getBorrowEnabled(Ethereum.DAI),    false);
        assertEq(_getBorrowEnabled(Ethereum.SDAI),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDC),   false);
        assertEq(_getBorrowEnabled(Ethereum.WETH),   false);
        assertEq(_getBorrowEnabled(Ethereum.WSTETH), false);
        assertEq(_getBorrowEnabled(Ethereum.WBTC),   false);
        assertEq(_getBorrowEnabled(Ethereum.GNO),    false);
        assertEq(_getBorrowEnabled(Ethereum.RETH),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDT),   false);
        assertEq(_getBorrowEnabled(Ethereum.LBTC),   false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return ReserveConfiguration.getBorrowingEnabled(
            IPool(SparkLend.POOL).getConfiguration(asset)
        );
    }

}
