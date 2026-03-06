// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IACLManager } from 'aave-v3-core/contracts/interfaces/IACLManager.sol';

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { IScaledBalanceToken }  from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

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

    function supplyCapConfigs(address asset) external view returns (uint256 max, uint256 gap, uint256 increaseCooldown, uint256 lastUpdateBlock, uint256 lastIncreaseTime);

    function borrowCapConfigs(address asset) external view returns (uint256 max, uint256 gap, uint256 increaseCooldown, uint256 lastUpdateBlock, uint256 lastIncreaseTime);

    function UPDATE_ROLE() external view returns (bytes32);

}

interface ICBBTCRatioOracleLike {

    function btcUSDFeed() external view returns (address);

    function cbbtcUSDFeed() external view returns (address);

}

interface IWEETHRatioOracleLike {

    function weeth() external view returns (address);

    function weethETHFeed() external view returns (address);

}

interface IRETHRatioOracleLike {

    function reth() external view returns (address);

    function rethETHFeed() external view returns (address);

}

contract SparkEthereum_20260312_SLLTests is SparkLiquidityLayerTests {

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0x5c46Fc65855c0C7465a1EA85EEA0B24B601502D3;
    address internal constant NEW_CAP_AUTOMATOR           = 0x4C1341636721b8B687647920B2E9481f3AB1F2eE;

    mapping(address => VmSafe.EthGetLogs) internal lastLogsByAsset;

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
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

        assertEq(IACLManager(SparkLend.ACL_MANAGER).isRiskAdmin(SparkLend.CAP_AUTOMATOR), true);
        assertEq(IACLManager(SparkLend.ACL_MANAGER).isRiskAdmin(NEW_CAP_AUTOMATOR),       false);

        // Get all events from old cap automator; keep only the last supply/borrow log per asset.
        VmSafe.EthGetLogs[] memory allSupplyLogs = _getEvents(block.chainid, SparkLend.CAP_AUTOMATOR, ICapAutomatorLike.SetSupplyCapConfig.selector);
        VmSafe.EthGetLogs[] memory allBorrowLogs = _getEvents(block.chainid, SparkLend.CAP_AUTOMATOR, ICapAutomatorLike.SetBorrowCapConfig.selector);

        assertEq(allSupplyLogs.length, 28);

        _assertSupplyCapLogs(allSupplyLogs[0],  Ethereum.RETH,   true);
        _assertSupplyCapLogs(allSupplyLogs[1],  Ethereum.SDAI,   false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[2],  Ethereum.WBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[3],  Ethereum.WETH,   true);
        _assertSupplyCapLogs(allSupplyLogs[4],  Ethereum.WSTETH, true);
        _assertSupplyCapLogs(allSupplyLogs[5],  Ethereum.WBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[6],  Ethereum.WBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[7],  Ethereum.WEETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[8],  Ethereum.WEETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[9],  Ethereum.CBBTC,  true);
        _assertSupplyCapLogs(allSupplyLogs[10], Ethereum.SUSDS,  false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[11], Ethereum.WBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[12], Ethereum.CBBTC,  true);
        _assertSupplyCapLogs(allSupplyLogs[13], Ethereum.WSTETH, true);
        _assertSupplyCapLogs(allSupplyLogs[14], Ethereum.WEETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[15], Ethereum.LBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[16], Ethereum.TBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[17], Ethereum.EZETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[18], Ethereum.RSETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[19], Ethereum.USDC,   false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[20], Ethereum.RSETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[21], Ethereum.USDT,   false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[22], Ethereum.EZETH,  true);
        _assertSupplyCapLogs(allSupplyLogs[23], Ethereum.PYUSD,  false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[24], Ethereum.USDT,   false);  // Removed
        _assertSupplyCapLogs(allSupplyLogs[25], Ethereum.LBTC,   true);
        _assertSupplyCapLogs(allSupplyLogs[26], Ethereum.CBBTC,  true);
        _assertSupplyCapLogs(allSupplyLogs[27], Ethereum.TBTC,   true);

        assertEq(allBorrowLogs.length, 20);

        _assertBorrowCapLogs(allBorrowLogs[0],  Ethereum.RETH,   true);
        _assertBorrowCapLogs(allBorrowLogs[1],  Ethereum.USDC,   false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[2],  Ethereum.USDT,   false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[3],  Ethereum.WBTC,   true);
        _assertBorrowCapLogs(allBorrowLogs[4],  Ethereum.WETH,   true);
        _assertBorrowCapLogs(allBorrowLogs[5],  Ethereum.WSTETH, true);
        _assertBorrowCapLogs(allBorrowLogs[6],  Ethereum.WETH,   true);
        _assertBorrowCapLogs(allBorrowLogs[7],  Ethereum.CBBTC,  true);
        _assertBorrowCapLogs(allBorrowLogs[8],  Ethereum.WBTC,   true);
        _assertBorrowCapLogs(allBorrowLogs[9],  Ethereum.WSTETH, true);
        _assertBorrowCapLogs(allBorrowLogs[10], Ethereum.WSTETH, true);
        _assertBorrowCapLogs(allBorrowLogs[11], Ethereum.TBTC,   true);
        _assertBorrowCapLogs(allBorrowLogs[12], Ethereum.USDC,   false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[13], Ethereum.USDT,   false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[14], Ethereum.PYUSD,  false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[15], Ethereum.WSTETH, true);
        _assertBorrowCapLogs(allBorrowLogs[16], Ethereum.RETH,   true);
        _assertBorrowCapLogs(allBorrowLogs[17], Ethereum.USDT,   false);  // Removed
        _assertBorrowCapLogs(allBorrowLogs[18], Ethereum.CBBTC,  true);
        _assertBorrowCapLogs(allBorrowLogs[19], Ethereum.TBTC,   true);

        VmSafe.EthGetLogs[] memory supplyLogs = _lastLogPerAsset(allSupplyLogs);
        VmSafe.EthGetLogs[] memory borrowLogs = _lastLogPerAsset(allBorrowLogs);

        assertEq(supplyLogs.length, 15);

        _assertSupplyCapLogs(supplyLogs[0],  Ethereum.RETH,   true);
        _assertSupplyCapLogs(supplyLogs[1],  Ethereum.SDAI,   false);  // Removed
        _assertSupplyCapLogs(supplyLogs[2],  Ethereum.WBTC,   true);
        _assertSupplyCapLogs(supplyLogs[3],  Ethereum.WETH,   true);
        _assertSupplyCapLogs(supplyLogs[4],  Ethereum.WSTETH, true);
        _assertSupplyCapLogs(supplyLogs[5],  Ethereum.WEETH,  true);
        _assertSupplyCapLogs(supplyLogs[6],  Ethereum.CBBTC,  true);
        _assertSupplyCapLogs(supplyLogs[7],  Ethereum.SUSDS,  false);  // Removed
        _assertSupplyCapLogs(supplyLogs[8],  Ethereum.LBTC,   true);
        _assertSupplyCapLogs(supplyLogs[9],  Ethereum.TBTC,   true);
        _assertSupplyCapLogs(supplyLogs[10], Ethereum.EZETH,  true);
        _assertSupplyCapLogs(supplyLogs[11], Ethereum.RSETH,  true);
        _assertSupplyCapLogs(supplyLogs[12], Ethereum.USDC,   false);  // Removed
        _assertSupplyCapLogs(supplyLogs[13], Ethereum.USDT,   false);  // Removed
        _assertSupplyCapLogs(supplyLogs[14], Ethereum.PYUSD,  false);  // Removed

        assertEq(borrowLogs.length, 9);

        _assertBorrowCapLogs(borrowLogs[0], Ethereum.RETH,   true);
        _assertBorrowCapLogs(borrowLogs[1], Ethereum.USDC,   false);  // Removed
        _assertBorrowCapLogs(borrowLogs[2], Ethereum.USDT,   false);  // Removed
        _assertBorrowCapLogs(borrowLogs[3], Ethereum.WBTC,   true);
        _assertBorrowCapLogs(borrowLogs[4], Ethereum.WETH,   true);
        _assertBorrowCapLogs(borrowLogs[5], Ethereum.WSTETH, true);
        _assertBorrowCapLogs(borrowLogs[6], Ethereum.CBBTC,  true);
        _assertBorrowCapLogs(borrowLogs[7], Ethereum.TBTC,   true);
        _assertBorrowCapLogs(borrowLogs[8], Ethereum.PYUSD,  false);  // Removed

        vm.recordLogs();

        _executeMainnetPayload();

        assertEq(IACLManager(SparkLend.ACL_MANAGER).isRiskAdmin(SparkLend.CAP_AUTOMATOR), false);
        assertEq(IACLManager(SparkLend.ACL_MANAGER).isRiskAdmin(NEW_CAP_AUTOMATOR),       true);

        address[] memory reserves = IPool(SparkLend.POOL).getReservesList();

        assertEq(reserves.length, 18);

        for (uint256 i = 0; i < reserves.length; ++i) {
            if (
               reserves[i] != Ethereum.DAI   &&  // Supply cap NA
               reserves[i] != Ethereum.GNO   &&  // Supply cap NA
               reserves[i] != Ethereum.SDAI  &&  // Supply cap 1
               reserves[i] != Ethereum.SUSDS &&  // Supply cap 1
               reserves[i] != Ethereum.USDS  &&  // Supply cap NA
               reserves[i] != Ethereum.USDC  &&  // Supply cap 68b
               reserves[i] != Ethereum.USDT  &&  // Supply cap 68b
               reserves[i] != Ethereum.PYUSD     // Supply cap 68b
            ) {
                ( uint256 max, , , , ) = ICapAutomatorLike(NEW_CAP_AUTOMATOR).supplyCapConfigs(reserves[i]);
                assertTrue(max > 0);
            }

            if (
                reserves[i] != Ethereum.DAI   &&  // Borrow cap NA
                reserves[i] != Ethereum.WEETH &&  // Borrow cap NA (not borrowable)
                reserves[i] != Ethereum.GNO   &&  // Borrow cap NA (frozen)
                reserves[i] != Ethereum.SDAI  &&  // Borrow cap NA (not borrowable)
                reserves[i] != Ethereum.USDC  &&  // Borrow cap 68b
                reserves[i] != Ethereum.SUSDS &&  // Borrow cap NA (not borrowable)
                reserves[i] != Ethereum.USDS  &&  // Borrow cap NA
                reserves[i] != Ethereum.USDT  &&  // Supply cap 68b
                reserves[i] != Ethereum.LBTC  &&  // Borrow cap NA (not borrowable)
                reserves[i] != Ethereum.EZETH &&  // Borrow cap NA (not borrowable, frozen)
                reserves[i] != Ethereum.RSETH &&  // Borrow cap NA (not borrowable, frozen)
                reserves[i] != Ethereum.PYUSD     // Borrow cap 68b
            ) {
                ( uint256 max, , , , ) = ICapAutomatorLike(NEW_CAP_AUTOMATOR).borrowCapConfigs(reserves[i]);
                assertTrue(max > 0);
            }
        }

        VmSafe.Log[] memory recordedLogs  = vm.getRecordedLogs();
        VmSafe.Log[] memory newSupplyLogs = new VmSafe.Log[](10);
        VmSafe.Log[] memory newBorrowLogs = new VmSafe.Log[](6);

        uint256 j = 0;
        uint256 k = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if      (recordedLogs[i].topics[0] == ICapAutomatorLike.SetSupplyCapConfig.selector) newSupplyLogs[j++] = recordedLogs[i];
            else if (recordedLogs[i].topics[0] == ICapAutomatorLike.SetBorrowCapConfig.selector) newBorrowLogs[k++] = recordedLogs[i];
        }

        assertEq(j, newSupplyLogs.length, "Unexpected number of new supply cap logs");
        assertEq(k, newBorrowLogs.length, "Unexpected number of new borrow cap logs");

        for (uint256 i = 0; i < newSupplyLogs.length; ++i) {
            bool found = false;

            for (uint256 j = 0; j < supplyLogs.length; ++j) {
                if (newSupplyLogs[i].topics[1] == supplyLogs[j].topics[1]) {
                    assertEq(newSupplyLogs[i].data, supplyLogs[j].data);

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
                    assertEq(newBorrowLogs[i].data, borrowLogs[j].data);

                    found = true;
                    break;
                }
            }

            if (!found) {
                revert("Borrow log not found in new logs");
            }
        }

        _checkSupplyCapSet(Ethereum.DAI,    false);
        _checkSupplyCapSet(Ethereum.SDAI,   false);
        _checkSupplyCapSet(Ethereum.USDC,   false);
        _checkSupplyCapSet(Ethereum.WETH,   true);
        _checkSupplyCapSet(Ethereum.WSTETH, true);
        _checkSupplyCapSet(Ethereum.WBTC,   true);
        _checkSupplyCapSet(Ethereum.GNO,    false);
        _checkSupplyCapSet(Ethereum.RETH,   true);
        _checkSupplyCapSet(Ethereum.USDT,   false);
        _checkSupplyCapSet(Ethereum.WEETH,  true);
        _checkSupplyCapSet(Ethereum.CBBTC,  true);
        _checkSupplyCapSet(Ethereum.SUSDS,  false);
        _checkSupplyCapSet(Ethereum.USDS,   false);
        _checkSupplyCapSet(Ethereum.LBTC,   true);
        _checkSupplyCapSet(Ethereum.TBTC,   true);
        _checkSupplyCapSet(Ethereum.EZETH,  true);
        _checkSupplyCapSet(Ethereum.RSETH,  true);
        _checkSupplyCapSet(Ethereum.PYUSD,  false);

        _checkBorrowCapSet(Ethereum.DAI,    false);
        _checkBorrowCapSet(Ethereum.SDAI,   false);
        _checkBorrowCapSet(Ethereum.USDC,   false);
        _checkBorrowCapSet(Ethereum.WETH,   true);
        _checkBorrowCapSet(Ethereum.WSTETH, true);
        _checkBorrowCapSet(Ethereum.WBTC,   true);
        _checkBorrowCapSet(Ethereum.GNO,    false);
        _checkBorrowCapSet(Ethereum.RETH,   true);
        _checkBorrowCapSet(Ethereum.USDT,   false);
        _checkBorrowCapSet(Ethereum.WEETH,  false);
        _checkBorrowCapSet(Ethereum.CBBTC,  true);
        _checkBorrowCapSet(Ethereum.SUSDS,  false);
        _checkBorrowCapSet(Ethereum.USDS,   false);
        _checkBorrowCapSet(Ethereum.LBTC,   false);
        _checkBorrowCapSet(Ethereum.TBTC,   true);
        _checkBorrowCapSet(Ethereum.EZETH,  false);
        _checkBorrowCapSet(Ethereum.RSETH,  false);
        _checkBorrowCapSet(Ethereum.PYUSD,  false);
    }

    function _checkSupplyCapSet(address asset, bool isLive) internal {
        ( uint256 oldMax, , , , ) = ICapAutomatorLike(SparkLend.CAP_AUTOMATOR).supplyCapConfigs(asset);
        ( uint256 newMax, , , , ) = ICapAutomatorLike(NEW_CAP_AUTOMATOR).supplyCapConfigs(asset);

        assertTrue(isLive ? newMax > 0 : newMax == 0);  // Check against current status to see if removed
        assertTrue(oldMax == newMax);
    }

    function _checkBorrowCapSet(address asset, bool isLive) internal {
        ( uint256 oldMax, , , , ) = ICapAutomatorLike(SparkLend.CAP_AUTOMATOR).borrowCapConfigs(asset);
        ( uint256 newMax, , , , ) = ICapAutomatorLike(NEW_CAP_AUTOMATOR).borrowCapConfigs(asset);

        assertTrue(isLive ? newMax > 0 : newMax == 0);  // Check against current status to see if removed
        assertTrue(oldMax == newMax);
    }

    function _lastLogPerAsset(VmSafe.EthGetLogs[] memory logs) internal returns (VmSafe.EthGetLogs[] memory) {
        address[] memory seenAssets = new address[](logs.length);

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            address asset = address(uint160(uint256(logs[i].topics[1])));

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

    function _assertSupplyCapLogs(VmSafe.EthGetLogs memory log, address asset, bool isLive) internal {
        assertEq(address(uint160(uint256(log.topics[1]))), asset);

        ( uint256 max, , , , ) = ICapAutomatorLike(SparkLend.CAP_AUTOMATOR).supplyCapConfigs(asset);

        assertTrue(isLive ? max > 0 : max == 0);  // Check against current status to see if removed
    }

    function _assertBorrowCapLogs(VmSafe.EthGetLogs memory log, address asset, bool isLive) internal {
        assertEq(address(uint160(uint256(log.topics[1]))), asset);

        ( uint256 max, , , , ) = ICapAutomatorLike(SparkLend.CAP_AUTOMATOR).borrowCapConfigs(asset);

        assertTrue(isLive ? max > 0 : max == 0);  // Check against current status to see if removed
    }

}

contract SparkEthereum_20260312_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath           for uint256;

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0x5c46Fc65855c0C7465a1EA85EEA0B24B601502D3;
    address internal constant NEW_CAP_AUTOMATOR           = 0x4C1341636721b8B687647920B2E9481f3AB1F2eE;

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_CapAutomator() external override onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runCapAutomatorTests(SparkLend.CAP_AUTOMATOR);

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runCapAutomatorTests(NEW_CAP_AUTOMATOR);
    }

    function _runCapAutomatorTests(address capAutomator) internal {
        address[] memory reserves = _getSparkLendContext().pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            _testAutomatedCapsUpdate(capAutomator, reserves[i]);
        }
    }

    function _testAutomatedCapsUpdate(address capAutomator, address asset) internal {
        SparkLendContext      memory ctx               = _getSparkLendContext();
        DataTypes.ReserveData memory reserveDataBefore = ctx.pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

        ICapAutomator capAutomator = ICapAutomator(capAutomator);

        ( , , , , uint48 supplyCapLastIncreaseTime ) = capAutomator.supplyCapConfigs(asset);
        ( , , , , uint48 borrowCapLastIncreaseTime ) = capAutomator.borrowCapConfigs(asset);

        vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
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
                10 ** IERC20(reserveDataAfter.aTokenAddress).decimals();

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
                10 ** IERC20(reserveDataAfter.variableDebtTokenAddress).decimals();

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

}

contract SparkEthereum_20260312_SpellTests is SpellTests {

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0x5c46Fc65855c0C7465a1EA85EEA0B24B601502D3;

    address internal constant CBBTC_BTC_RATIO_ORACLE    = 0x64B157212C21097002920D57322B671b88DFcCBC;
    address internal constant WBTC_BTC_CHAINLINK_ORACLE = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address internal constant WEETH_ETH_RATIO_ORACLE    = 0x4C805FD3c64B79840d36813Fc90c165bf77bb7E4;
    address internal constant RETH_ETH_RATIO_ORACLE     = 0xd0B378dA552D06B6D3497e4b5ba2A83418f78d06;

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_sparkTreasury_transfersSparklendDAIAndUSDS() external onChain(ChainIdUtils.Ethereum()) {
        uint256 almProxyDaiBalanceBefore    = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 almProxyUsdsBalanceBefore   = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 sparkProxyDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);
        uint256 sparkProxyUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(almProxyDaiBalanceBefore,    245_531_514.384201562795143844e18);
        assertEq(almProxyUsdsBalanceBefore,   99_354_825.194645187484186885e18);
        assertEq(sparkProxyDaiBalanceBefore,  584_142.478111589321521540e18);
        assertEq(sparkProxyUsdsBalanceBefore, 632_732.341636574112694088e18);

        _executeAllPayloadsAndBridges();

        assertGt(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),  almProxyDaiBalanceBefore + sparkProxyDaiBalanceBefore);
        assertGt(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY), almProxyUsdsBalanceBefore + sparkProxyUsdsBalanceBefore);

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY),  0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY), 0);
    }

    function test_ETHEREUM_killSwitchActivationForCBBTC() external onChain(ChainIdUtils.Ethereum()) {
        // Verify Configuration
        ICBBTCRatioOracleLike cbbtcRatioOracle = ICBBTCRatioOracleLike(CBBTC_BTC_RATIO_ORACLE);

        assertEq(cbbtcRatioOracle.btcUSDFeed(),   0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        assertEq(cbbtcRatioOracle.cbbtcUSDFeed(), 0x2665701293fCbEB223D11A08D826563EDcCE423A);

        _test_killSwitchActivation({
            oracle       : CBBTC_BTC_RATIO_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 1.007763761671557448e18
        });
    }

    function test_ETHEREUM_killSwitchActivationForWBTC() external onChain(ChainIdUtils.Ethereum()) {
        _test_killSwitchActivation({
            oracle       : WBTC_BTC_CHAINLINK_ORACLE,
            threshold    : 0.95e8,
            latestAnswer : 0.99761e8
        });
    }

    function test_ETHEREUM_killSwitchActivationForWEETH() external onChain(ChainIdUtils.Ethereum()) {
        // Verify Configuration
        IWEETHRatioOracleLike weethRatioOracle = IWEETHRatioOracleLike(WEETH_ETH_RATIO_ORACLE);

        assertEq(weethRatioOracle.weeth(),        Ethereum.WEETH);
        assertEq(weethRatioOracle.weethETHFeed(), 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22);

        _test_killSwitchActivation({
            oracle       : WEETH_ETH_RATIO_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 0.999593486146659469e18
        });
    }

    function test_ETHEREUM_killSwitchActivationForRETH() external onChain(ChainIdUtils.Ethereum()) {
        // Verify Configuration
        IRETHRatioOracleLike rethRatioOracle = IRETHRatioOracleLike(RETH_ETH_RATIO_ORACLE);

        assertEq(rethRatioOracle.reth(),        Ethereum.RETH);
        assertEq(rethRatioOracle.rethETHFeed(), 0x536218f9E9Eb48863970252233c8F271f554C2d0);

        _test_killSwitchActivation({
            oracle       : RETH_ETH_RATIO_ORACLE,
            threshold    : 0.95e18,
            latestAnswer : 0.999857924990777832e18
        });
    }

    function _test_killSwitchActivation(address oracle, uint256 threshold, int256 latestAnswer) internal {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),             2);
        assertEq(kso.oracleThresholds(oracle), 0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),             6);
        assertEq(kso.oracleThresholds(oracle), threshold);

        assertLt(threshold / uint256(latestAnswer), 10);  // Same order of magnitude
        assertLt(uint256(latestAnswer) / threshold, 10);  // Same order of magnitude

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

        assertEq(_getBorrowEnabled(reserves[0]),  false);
        assertEq(_getBorrowEnabled(reserves[1]),  false);
        assertEq(_getBorrowEnabled(reserves[2]),  false);
        assertEq(_getBorrowEnabled(reserves[3]),  false);
        assertEq(_getBorrowEnabled(reserves[4]),  false);
        assertEq(_getBorrowEnabled(reserves[5]),  false);
        assertEq(_getBorrowEnabled(reserves[6]),  false);
        assertEq(_getBorrowEnabled(reserves[7]),  false);
        assertEq(_getBorrowEnabled(reserves[8]),  false);
        assertEq(_getBorrowEnabled(reserves[9]),  false);
        assertEq(_getBorrowEnabled(reserves[10]), false);
        assertEq(_getBorrowEnabled(reserves[11]), false);
        assertEq(_getBorrowEnabled(reserves[12]), false);
        assertEq(_getBorrowEnabled(reserves[13]), false);
        assertEq(_getBorrowEnabled(reserves[14]), true);  // Frozen/Paused reserves are skipped in the killswitch.

        // Check that reserve[14] is frozen/paused.
        DataTypes.ReserveConfigurationMap memory config = IPool(SparkLend.POOL).getConfiguration(reserves[14]);
        assertEq(ReserveConfiguration.getPaused(config), false);
        assertEq(ReserveConfiguration.getFrozen(config), true);

        assertEq(_getBorrowEnabled(reserves[15]), false);
        assertEq(_getBorrowEnabled(reserves[16]), false);
        assertEq(_getBorrowEnabled(reserves[17]), false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return ReserveConfiguration.getBorrowingEnabled(
            IPool(SparkLend.POOL).getConfiguration(asset)
        );
    }

}
