// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract SparkEthereum_20260924_SLLTests is SparkLiquidityLayerTests {

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 20260924;
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }
        super.deal(token, to, amount);
    }

}

contract SparkEthereum_20260924_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260924;
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

}

contract SparkEthereum_20260924_SpellTests is SpellTests {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 972_485e18;

    constructor() {
        _spellId   = 20260924;
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

    function test_ETHEREUM_sparkTreasury() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore          = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      47_824_927.085806286854722044e18);
        assertEq(foundationBalanceBefore,      2_733_790.0222e18);
        assertEq(assetFoundationBalanceBefore, 155_000e18);
        assertEq(almOpsBalanceBefore,          0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - SPARK_FOUNDATION_GRANT_AMOUNT - SPARK_ASSET_FOUNDATION_GRANT_AMOUNT - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + SPARK_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
    }

}
