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

contract SparkEthereum_20260312_SLLTests is SparkLiquidityLayerTests {

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

}

contract SparkEthereum_20260312_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

}

contract SparkEthereum_20260312_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260312;
        _blockDate = 1772785277;  // 2026-03-06T08:21:17Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
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

}
