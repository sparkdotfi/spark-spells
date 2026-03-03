// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { console } from "forge-std/console.sol";

interface IPriceOracleLike {

    function latestAnswer() external view returns (int256);

}

interface ICapAutomatorLike {

    event SetSupplyCapConfig(
        address indexed asset,
        uint256         max,
        uint256         gap,
        uint256         increaseCooldown
    );

    event SetBorrowCapConfig(
        address indexed asset,
        uint256         max,
        uint256         gap,
        uint256         increaseCooldown
    );

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function poolConfigurator() external view returns (address);
    function pool() external view returns (address);
    function UPDATE_ROLE() external view returns (bytes32);

}

contract SparkEthereum_20260312_SLLTests is SparkLiquidityLayerTests {

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0x5c46Fc65855c0C7465a1EA85EEA0B24B601502D3;
    address internal constant NEW_CAP_AUTOMATOR           = 0x4C1341636721b8B687647920B2E9481f3AB1F2eE;

    mapping(address => VmSafe.EthGetLogs) internal lastLogsByAsset;

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772518283;  // 2026-03-03T06:11:23Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xf655F6E7843685BfD8cfA4523d43F2b9922BBd77;
    }

    function test_ETHEREUM_controllerUpgrade() external onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_controllerUpgradeEvents() external onChain(ChainIdUtils.Ethereum()) {
        _testMainnetControllerUpgradeEvents({
            _oldController: Ethereum.ALM_CONTROLLER,
            _newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_capAutomatorUpgrade() external onChain(ChainIdUtils.Ethereum()) {
        ICapAutomatorLike capAutomator = ICapAutomatorLike(NEW_CAP_AUTOMATOR);

        // Check configuration.
        assertEq(capAutomator.hasRole(capAutomator.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),  true);
        assertEq(capAutomator.hasRole(capAutomator.UPDATE_ROLE(), Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(capAutomator.poolConfigurator(),                                                SparkLend.POOL_CONFIGURATOR);
        assertEq(capAutomator.pool(),                                                            SparkLend.POOL);

        // Get all events from old cap automator; keep only the last supply/borrow log per asset.
        VmSafe.EthGetLogs[] memory allSupplyLogs = _getEvents(block.chainid, SparkLend.CAP_AUTOMATOR, ICapAutomatorLike.SetSupplyCapConfig.selector);
        VmSafe.EthGetLogs[] memory allBorrowLogs = _getEvents(block.chainid, SparkLend.CAP_AUTOMATOR, ICapAutomatorLike.SetBorrowCapConfig.selector);

        VmSafe.EthGetLogs[] memory supplyLogs = _lastLogPerAsset(allSupplyLogs);
        VmSafe.EthGetLogs[] memory borrowLogs = _lastLogPerAsset(allBorrowLogs);

        vm.recordLogs();

        _executeMainnetPayload();

        VmSafe.Log[] memory recordedLogs  = vm.getRecordedLogs();
        VmSafe.Log[] memory newSupplyLogs = new VmSafe.Log[](10);
        VmSafe.Log[] memory newBorrowLogs = new VmSafe.Log[](6);

        uint256 j = 0;
        uint256 k = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].topics[0] == ICapAutomatorLike.SetSupplyCapConfig.selector) {
                if (j < supplyLogs.length) {
                    newSupplyLogs[j] = recordedLogs[i];
                }
                j++;
            } else if (recordedLogs[i].topics[0] == ICapAutomatorLike.SetBorrowCapConfig.selector) {
                if (k < borrowLogs.length) {
                    newBorrowLogs[k] = recordedLogs[i];
                }
                k++;
            }
        }

        for (uint256 i = 0; i < newSupplyLogs.length; ++i) {
            bool found = false;

            for (uint256 j = 0; j < supplyLogs.length; ++j) {
                if (newSupplyLogs[i].topics[1] == supplyLogs[j].topics[1]) {
                    assertEq(newSupplyLogs[i].topics[1], supplyLogs[j].topics[1]);
                    assertEq(newSupplyLogs[i].data,      supplyLogs[j].data);

                    found = true;
                    break;
                }
            }

            if (!found) {
                revert("Supply log not found in new logs");
            }
        }
        
        for (uint256 i = 0; i < newBorrowLogs.length; ++i) {
            bool found = false;

            for (uint256 j = 0; j < borrowLogs.length; ++j) {
                if (newBorrowLogs[i].topics[1] == borrowLogs[j].topics[1]) {
                    assertEq(newBorrowLogs[i].topics[1], borrowLogs[j].topics[1]);
                    assertEq(newBorrowLogs[i].data,      borrowLogs[j].data);

                    found = true;
                    break;
                }
            }

            if (!found) {
                revert("Borrow log not found in new logs");
            }
        }
    }

    function _lastLogPerAsset(VmSafe.EthGetLogs[] memory logs) internal returns (VmSafe.EthGetLogs[] memory) {
        address[] memory seenAssets = new address[](logs.length);

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            address asset = address(uint160(uint256(logs[i].topics[1])));

            // console.log("--------------------------------");

            // console.log("asset", asset);
            // console.log(lastLogsByAsset[asset].emitter);
            // console.log("i", i);
            // console.log("count", count);

            // console.log("--------------------------------");

            if (lastLogsByAsset[asset].emitter == address(0)) {
                seenAssets[count] = asset;
                count++;
            }

            lastLogsByAsset[asset] = logs[i];
        }

        VmSafe.EthGetLogs[] memory out = new VmSafe.EthGetLogs[](count);

        for (uint256 i = 0; i < count; ++i) {
            out[i] = lastLogsByAsset[seenAssets[i]];

            delete lastLogsByAsset[seenAssets[i]];
        }

        return out;
    }

}

contract SparkEthereum_20260312_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772518283;  // 2026-03-03T06:11:23Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xf655F6E7843685BfD8cfA4523d43F2b9922BBd77;
    }

}

contract SparkEthereum_20260312_SpellTests is SpellTests {

    address internal constant CBBTC_BTC_ORACLE = 0x64B157212C21097002920D57322B671b88DFcCBC;
    address internal constant WBTC_BTC_ORACLE  = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address internal constant WEETH_ETH_ORACLE = 0x4C805FD3c64B79840d36813Fc90c165bf77bb7E4;
    address internal constant RETH_ETH_ORACLE  = 0xd0B378dA552D06B6D3497e4b5ba2A83418f78d06;

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772518283;  // 2026-03-03T06:11:23Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xf655F6E7843685BfD8cfA4523d43F2b9922BBd77;
    }

    function test_ETHEREUM_sparkTreasury_transfersSparklendDAIAndUSDS() external onChain(ChainIdUtils.Ethereum()) {
        uint256 almProxyDaiBalanceBefore    = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 almProxyUsdsBalanceBefore   = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 sparkProxyDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);
        uint256 sparkProxyUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(almProxyDaiBalanceBefore,    245_340_056.481731623797634139e18);
        assertEq(almProxyUsdsBalanceBefore,   274_287_371.217193777464340217e18);
        assertEq(sparkProxyDaiBalanceBefore,  583_959.969837929750240401e18);
        assertEq(sparkProxyUsdsBalanceBefore, 632_545.148685998716448730e18);

        _executeAllPayloadsAndBridges();

        assertGt(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),  almProxyDaiBalanceBefore + sparkProxyDaiBalanceBefore);
        assertGt(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY), almProxyUsdsBalanceBefore + sparkProxyUsdsBalanceBefore);

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY),  0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY), 0);
    }

    function test_ETHEREUM_killSwitchActivationForCBBTC() external onChain(ChainIdUtils.Ethereum()) {
        // Verify Configuration

        _test_killSwitchActivation({
            oracle       : CBBTC_BTC_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 1.009694948823013023e18
        });
    }

    function test_ETHEREUM_killSwitchActivationForWBTC() external onChain(ChainIdUtils.Ethereum()) {
        _test_killSwitchActivation({
            oracle       : WBTC_BTC_ORACLE,
            threshold    : 0.95e8,
            latestAnswer : 0.99747000e8
        });
    }

    function test_ETHEREUM_killSwitchActivationForWEETH() external onChain(ChainIdUtils.Ethereum()) {
        _test_killSwitchActivation({
            oracle       : WEETH_ETH_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 0.998920714542678451e18
        });
    }

    function test_ETHEREUM_killSwitchActivationForRETH() external onChain(ChainIdUtils.Ethereum()) {
        _test_killSwitchActivation({
            oracle       : RETH_ETH_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 1.000044024386056921e18
        });
    }

    function _test_killSwitchActivation(address oracle, uint256 threshold, int256 latestAnswer) internal {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),               2);
        assertEq(kso.oracleThresholds(oracle), 0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),               6);
        assertEq(kso.oracleThresholds(oracle), threshold);

        // Sanity check the latest answers
        assertEq(IPriceOracleLike(oracle).latestAnswer(), latestAnswer);

        // Should not be able to trigger
        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(oracle);

        // Assert Boundary Condition: price just above threshold
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IPriceOracleLike.latestAnswer.selector),
            abi.encode(int256(threshold) + 1)
        );

        assertEq(IPriceOracleLike(oracle).latestAnswer(), int256(threshold) + 1);

        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(oracle);

        assertEq(kso.triggered(), false);

        // Replace oracle with value at the threshold
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IPriceOracleLike.latestAnswer.selector),
            abi.encode(int256(threshold))
        );

        assertEq(IPriceOracleLike(oracle).latestAnswer(), int256(threshold));

        // Fetch all assets from the pool
        address[] memory reserves = IPool(SparkLend.POOL).getReservesList();

        assertEq(reserves.length, 18);

        assertEq(kso.triggered(), false);

        assertEq(_getBorrowEnabled(reserves[0]),  true);
        assertEq(_getBorrowEnabled(reserves[1]),  false);
        assertEq(_getBorrowEnabled(reserves[2]),  true);
        assertEq(_getBorrowEnabled(reserves[3]),  true);
        assertEq(_getBorrowEnabled(reserves[4]),  true);
        assertEq(_getBorrowEnabled(reserves[5]),  false);
        assertEq(_getBorrowEnabled(reserves[6]),  false);
        assertEq(_getBorrowEnabled(reserves[7]),  true);
        assertEq(_getBorrowEnabled(reserves[8]),  true);
        assertEq(_getBorrowEnabled(reserves[9]),  false);
        assertEq(_getBorrowEnabled(reserves[10]), true);
        assertEq(_getBorrowEnabled(reserves[11]), false);
        assertEq(_getBorrowEnabled(reserves[12]), true);
        assertEq(_getBorrowEnabled(reserves[13]), false);
        assertEq(_getBorrowEnabled(reserves[14]), true);
        assertEq(_getBorrowEnabled(reserves[15]), false);
        assertEq(_getBorrowEnabled(reserves[16]), false);
        assertEq(_getBorrowEnabled(reserves[17]), true);

        kso.trigger(oracle);

        assertEq(kso.triggered(), true);

        console.log("reserves[0]", reserves[0]);
        assertEq(_getBorrowEnabled(reserves[0]),  false);
        console.log("reserves[1]", reserves[1]);
        assertEq(_getBorrowEnabled(reserves[1]),  false);
        console.log("reserves[2]", reserves[2]);
        assertEq(_getBorrowEnabled(reserves[2]),  false);
        console.log("reserves[3]", reserves[3]);
        assertEq(_getBorrowEnabled(reserves[3]),  false);
        console.log("reserves[4]", reserves[4]);
        assertEq(_getBorrowEnabled(reserves[4]),  false);
        console.log("reserves[5]", reserves[5]);
        assertEq(_getBorrowEnabled(reserves[5]),  false);
        console.log("reserves[6]", reserves[6]);
        assertEq(_getBorrowEnabled(reserves[6]),  false);
        console.log("reserves[7]", reserves[7]);
        assertEq(_getBorrowEnabled(reserves[7]),  false);
        console.log("reserves[8]", reserves[8]);
        assertEq(_getBorrowEnabled(reserves[8]),  false);
        console.log("reserves[9]", reserves[9]);
        assertEq(_getBorrowEnabled(reserves[9]),  false);
        console.log("reserves[10]", reserves[10]);
        assertEq(_getBorrowEnabled(reserves[10]), false);
        console.log("reserves[11]", reserves[11]);
        assertEq(_getBorrowEnabled(reserves[11]), false);
        console.log("reserves[12]", reserves[12]);
        assertEq(_getBorrowEnabled(reserves[12]), false);
        console.log("reserves[13]", reserves[13]);
        assertEq(_getBorrowEnabled(reserves[13]), false);
        console.log("reserves[14]", reserves[14]);
        assertEq(_getBorrowEnabled(reserves[14]), true);
        console.log("reserves[15]", reserves[15]);
        assertEq(_getBorrowEnabled(reserves[15]), false);
        console.log("reserves[16]", reserves[16]);
        assertEq(_getBorrowEnabled(reserves[16]), false);
        console.log("reserves[17]", reserves[17]);
        assertEq(_getBorrowEnabled(reserves[17]), false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return ReserveConfiguration.getBorrowingEnabled(
            IPool(SparkLend.POOL).getConfiguration(asset)
        );
    }

}
