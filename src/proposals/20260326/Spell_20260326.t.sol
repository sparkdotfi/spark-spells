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

contract SparkEthereum_20260326_SLLTests is SparkLiquidityLayerTests {

    address internal constant ANCHORAGE_USAT_USDT = 0x49506C3Aa028693458d6eE816b2EC28522946872;
    address internal constant USAT                = 0x07041776f5007ACa2A54844F50503a18A72A8b68;

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773645479;  // 2026-03-16T07:17:59Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_sll_anchorageUSAT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            USAT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : USAT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_anchorageUSDT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

}

contract SparkEthereum_20260326_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773645479;  // 2026-03-16T07:17:59Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

}

contract SparkEthereum_20260326_SpellTests is SpellTests {

    address internal constant SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT = 0xEabCb8C0346Ac072437362f1692706BA5768A911;

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT       = 414_215e18;

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773645479;  // 2026-03-16T07:17:59Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkProxyBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 opsMultisigBalanceBefore     = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_OPS_MULTISIG);
        uint256 assetFoundationBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT);

        assertEq(sparkProxyBalanceBefore,      36_722_470.91397762025440102e18);
        assertEq(foundationBalanceBefore,      0);
        assertEq(opsMultisigBalanceBefore,     0);
        assertEq(assetFoundationBalanceBefore, 55_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(
            IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),
            sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - USDS_SPK_BUYBACK_AMOUNT
        );

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),     foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_OPS_MULTISIG),              opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION_GRANT_RECIPIENT), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
