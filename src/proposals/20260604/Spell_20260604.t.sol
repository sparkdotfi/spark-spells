// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { DataTypes } from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

contract SparkEthereum_20260604_SLLTests is SparkLiquidityLayerTests {

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1778600481;  // 2026-05-12T15:41:21Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

}

contract SparkEthereum_20260604_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1778600481;  // 2026-05-12T15:41:21Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_sparkLend_btcEModeUpdate() external onChain(ChainIdUtils.Ethereum()) {
        IPool pool = IPool(SparkLend.POOL);

        DataTypes.EModeCategory memory eModeBefore = pool.getEModeCategoryData(3);

        assertEq(eModeBefore.ltv,                  85_00);
        assertEq(eModeBefore.liquidationThreshold, 90_00);
        assertEq(eModeBefore.liquidationBonus,     102_00);
        assertEq(eModeBefore.priceSource,          address(0));
        assertEq(eModeBefore.label,                'BTC');

        _executeAllPayloadsAndBridges();

        DataTypes.EModeCategory memory eModeAfter = pool.getEModeCategoryData(3);

        assertEq(eModeAfter.ltv,                  1);
        assertEq(eModeAfter.liquidationThreshold, 1);
        assertEq(eModeAfter.liquidationBonus,     101_00);
        assertEq(eModeAfter.priceSource,          eModeBefore.priceSource);
        assertEq(eModeAfter.label,                eModeBefore.label);
    }

    function test_ETHEREUM_sparkLend_wethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WETH, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WETH, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WETH, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WETH, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_wstethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WSTETH, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WSTETH, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WSTETH, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WSTETH, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_weethCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WEETH, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WEETH, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WEETH, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WEETH, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_wbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WBTC, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WBTC, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_cbbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.CBBTC, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.CBBTC, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 5_000, 200, 12 hours);
        _assertBorrowCapConfig(Ethereum.LBTC, 500,   50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 200, 4 hours);
        _assertBorrowCapConfig(Ethereum.LBTC, 1,      0,   0);
    }

}

contract SparkEthereum_20260604_SpellTests is SpellTests {

    uint256 internal constant SPK_BUYBACKS_AMOUNT = 326_945e18;

    constructor() {
        _spellId   = 20260604;
        _blockDate = 1778600481;  // 2026-05-12T15:41:21Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0x84c5E704F7918812BA878ea7Ddbb1365876697C2;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 almOpsBalanceBefore     = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore, 36_899_113.913977620254401020e18);
        assertEq(almOpsBalanceBefore,     0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore - SPK_BUYBACKS_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
