// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ISyrupLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IDssVestLike {
    event Init(uint256 indexed id, address indexed usr);
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);

    function accrued(uint256) external view returns (uint256);
    function bgn(uint256) external view returns (uint256);
    function cap() external view returns (uint256);
    function clf(uint256) external view returns (uint256);
    function czar() external view returns (address);
    function gem() external view returns (address);
    function ids() external view returns (uint256);
    function fin(uint256) external view returns (uint256);
    function mgr(uint256) external view returns (address);
    function rxd(uint256) external view returns (uint256);
    function res(uint256) external view returns (uint256);
    function tot(uint256) external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function usr(uint256) external view returns (address);
    function valid(uint256) external view returns (bool);
    function vest(uint256) external;
    function wards(address) external view returns (uint256);
}

contract SparkEthereum_20260212_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant DEPLOYER  = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;
    address internal constant DSS_VEST  = 0x6Bad07722818Ceff1deAcc33280DbbFdA4939A09;
    address internal constant VEST_USER = 0xEFF097C5CC7F63e9537188FE381D1360158c1511;

    uint256 internal constant SPK_VESTING_AMOUNT = 1_200_000_000e18;

    constructor() {
        _spellId   = 20260212;
        _blockDate = 1770100525;  // 2026-02-03T06:35:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xa091BeD493C27efaa4D6e06e32684eCa0325adcA;

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

    function test_ETHEREUM_dssVest_events() external onChain(ChainIdUtils.Ethereum()) {
        VmSafe.EthGetLogs[] memory allLogs = _getEvents(block.chainid, DSS_VEST, bytes32(0));

        assertEq(allLogs.length, 3);

        assertEq32(allLogs[0].topics[0], IDssVestLike.Rely.selector);
        assertEq32(allLogs[1].topics[0], IDssVestLike.Rely.selector);
        assertEq32(allLogs[2].topics[0], IDssVestLike.Deny.selector);

        assertEq(address(uint160(uint256(allLogs[0].topics[1]))), DEPLOYER);
        assertEq(address(uint160(uint256(allLogs[1].topics[1]))), Ethereum.SPARK_PROXY);
        assertEq(address(uint160(uint256(allLogs[2].topics[1]))), DEPLOYER);

        vm.recordLogs();

        _executeMainnetPayload();  // Have to use this to properly load logs on mainnet

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](2);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter != DSS_VEST) continue;

            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq(newLogs.length, 2);

        // File event

        assertEq32(newLogs[0].topics[0], IDssVestLike.File.selector);
        assertEq32(newLogs[0].topics[1], bytes32("cap"));

        assertEq(abi.decode(newLogs[0].data, (uint256)), SPK_VESTING_AMOUNT / (4 * 365 days));

        // Init event

        assertEq32(newLogs[1].topics[0], IDssVestLike.Init.selector);

        assertEq(uint256(newLogs[1].topics[1]),                   1);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), VEST_USER);
    }

}

contract SparkEthereum_20260212_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260212;
        _blockDate = 1770100525;  // 2026-02-03T06:35:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xa091BeD493C27efaa4D6e06e32684eCa0325adcA;
    }

}

contract SparkEthereum_20260212_SpellTests is SpellTests {

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 78_394e18;

    address internal constant DEPLOYER  = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;
    address internal constant DSS_VEST  = 0x6Bad07722818Ceff1deAcc33280DbbFdA4939A09;
    address internal constant VEST_USER = 0xEFF097C5CC7F63e9537188FE381D1360158c1511;

    uint256 internal constant SPK_VESTING_AMOUNT = 1_200_000_000e18;
    uint256 internal constant VEST_START         = 1750147200;  // 2025-06-17T08:00:00Z

    constructor() {
        _spellId   = 20260212;
        _blockDate = 1770100525;  // 2026-02-03T06:35:25Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xa091BeD493C27efaa4D6e06e32684eCa0325adcA;
    }

    function test_ETHEREUM_sparkTreasury_grovePayment() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 groveBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.GROVE_SUBDAO_PROXY);

        assertEq(sparkBalanceBefore, 36_360_827.445801365846236778e18);
        assertEq(groveBalanceBefore, 1_792_513e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),        sparkBalanceBefore - GROVE_PAYMENT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.GROVE_SUBDAO_PROXY), groveBalanceBefore + GROVE_PAYMENT_AMOUNT);
    }

    function test_ETHEREUM_dssVest() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 spk = IERC20(Ethereum.SPK);

        IDssVestLike dssVest = IDssVestLike(DSS_VEST);

        assertEq(dssVest.wards(DEPLOYER),             0);
        assertEq(dssVest.wards(Ethereum.SPARK_PROXY), 1);
        assertEq(dssVest.czar(),                      Ethereum.SPARK_PROXY);
        assertEq(dssVest.gem(),                       Ethereum.SPK);

        assertEq(dssVest.cap(), 0);
        assertEq(dssVest.ids(), 0);

        _executeAllPayloadsAndBridges();

        assertEq(dssVest.wards(DEPLOYER),             0);
        assertEq(dssVest.wards(Ethereum.SPARK_PROXY), 1);
        assertEq(dssVest.czar(),                      Ethereum.SPARK_PROXY);
        assertEq(dssVest.gem(),                       Ethereum.SPK);

        assertEq(dssVest.cap(), SPK_VESTING_AMOUNT / (4 * 365 days));
        assertEq(dssVest.ids(), 1);

        uint256 vestingId = 1;

        assertEq(dssVest.tot(vestingId),   SPK_VESTING_AMOUNT);
        assertEq(dssVest.bgn(vestingId),   VEST_START);
        assertEq(dssVest.clf(vestingId),   VEST_START + 365 days);
        assertEq(dssVest.fin(vestingId),   VEST_START + 4 * 365 days);
        assertEq(dssVest.mgr(vestingId),   Ethereum.SPARK_PROXY);
        assertEq(dssVest.usr(vestingId),   VEST_USER);
        assertEq(dssVest.valid(vestingId), true);
        assertEq(dssVest.res(vestingId),   0);

        // Warp to before cliff, assert zero, then after cliff claim, assert balance and state changes.

        vm.warp(VEST_START + 365 days - 1);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT,
            userBalance         : 0,
            sparkProxyAllowance : SPK_VESTING_AMOUNT,
            accrued             : 299_999_990.487062404870624048e18,
            unpaid              : 0,
            rxd                 : 0
        });

        dssVest.vest(vestingId);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT,
            userBalance         : 0,
            sparkProxyAllowance : SPK_VESTING_AMOUNT,
            accrued             : 299_999_990.487062404870624048e18,
            unpaid              : 0,
            rxd                 : 0
        });

        vm.warp(VEST_START + 365 days);

        uint256 claimedAmount1 = SPK_VESTING_AMOUNT / 4;

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT,
            userBalance         : 0,
            sparkProxyAllowance : SPK_VESTING_AMOUNT,
            accrued             : claimedAmount1,
            unpaid              : claimedAmount1,
            rxd                 : 0
        });

        dssVest.vest(vestingId);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT - claimedAmount1,
            userBalance         : claimedAmount1,
            sparkProxyAllowance : SPK_VESTING_AMOUNT - claimedAmount1,
            accrued             : claimedAmount1,
            unpaid              : 0,
            rxd                 : claimedAmount1
        });

        // Claim again in a month, assert balance and state changes.

        vm.warp(VEST_START + 365 days + 30 days);

        uint256 claimedAmount2 = SPK_VESTING_AMOUNT * 30 days / (4 * 365 days);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT - claimedAmount1,
            userBalance         : claimedAmount1,
            sparkProxyAllowance : SPK_VESTING_AMOUNT - claimedAmount1,
            accrued             : claimedAmount1 + claimedAmount2,
            unpaid              : claimedAmount2,
            rxd                 : claimedAmount1
        });

        dssVest.vest(vestingId);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT - claimedAmount1 - claimedAmount2,
            userBalance         : claimedAmount1 + claimedAmount2,
            sparkProxyAllowance : SPK_VESTING_AMOUNT - claimedAmount1 - claimedAmount2,
            accrued             : claimedAmount1 + claimedAmount2,
            unpaid              : 0,
            rxd                 : claimedAmount1 + claimedAmount2
        });

        // Warp to the end, claim, assert balance and state changes.

        vm.warp(VEST_START + 4 * 365 days);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : SPK_VESTING_AMOUNT - claimedAmount1 - claimedAmount2,
            userBalance         : claimedAmount1 + claimedAmount2,
            sparkProxyAllowance : SPK_VESTING_AMOUNT - claimedAmount1 - claimedAmount2,
            accrued             : SPK_VESTING_AMOUNT,
            unpaid              : SPK_VESTING_AMOUNT - claimedAmount1 - claimedAmount2,
            rxd                 : claimedAmount1 + claimedAmount2
        });

        dssVest.vest(vestingId);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : 0,
            userBalance         : SPK_VESTING_AMOUNT,
            sparkProxyAllowance : 0,
            accrued             : SPK_VESTING_AMOUNT,
            unpaid              : 0,
            rxd                 : SPK_VESTING_AMOUNT
        });

        // Warp past the end

        vm.warp(VEST_START + 4 * 365 days + 1 days);

        _assertVestingState({
            vestingId           : vestingId,
            sparkProxyBalance   : 0,
            userBalance         : SPK_VESTING_AMOUNT,
            sparkProxyAllowance : 0,
            accrued             : SPK_VESTING_AMOUNT,
            unpaid              : 0,
            rxd                 : SPK_VESTING_AMOUNT
        });
    }

    function _assertVestingState(
        uint256 vestingId,
        uint256 sparkProxyBalance,
        uint256 userBalance,
        uint256 sparkProxyAllowance,
        uint256 accrued,
        uint256 unpaid,
        uint256 rxd
    )
        internal view
    {
        IERC20       spk     = IERC20(Ethereum.SPK);
        IDssVestLike dssVest = IDssVestLike(DSS_VEST);

        assertEq(spk.balanceOf(Ethereum.SPARK_PROXY), sparkProxyBalance);
        assertEq(spk.balanceOf(VEST_USER),            userBalance);

        assertEq(spk.allowance(Ethereum.SPARK_PROXY, DSS_VEST), sparkProxyAllowance);

        assertEq(dssVest.accrued(vestingId), accrued);
        assertEq(dssVest.unpaid(vestingId),  unpaid);
        assertEq(dssVest.rxd(vestingId),     rxd);
    }

}
