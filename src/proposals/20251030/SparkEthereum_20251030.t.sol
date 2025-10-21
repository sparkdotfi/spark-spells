// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { LZForwarder }           from "xchain-helpers/forwarders/LZForwarder.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import { ChainIdUtils } from "src/libraries/ChainId.sol";
import { SLLHelpers }   from "src/libraries/SLLHelpers.sol";

import { MorphoTests }              from "src/test-harness/MorphoTests.sol";
import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellRunner }              from "src/test-harness/SpellRunner.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { IERC20Like, ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20251016_GenericTests is SpellRunner {

    constructor() {
        _spellId   = 20251016;
        _blockDate = "2025-10-10T17:44:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
    }

}

contract SparkEthereum_20251030_SLLTests is SparkLiquidityLayerTests {

    address internal constant ARBITRUM_NEW_ALM_CONTROLLER = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;
    address internal constant OPTIMISM_NEW_ALM_CONTROLLER = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
    address internal constant UNICHAIN_NEW_ALM_CONTROLLER = 0x7CD6EC14785418aF694efe154E7ff7d9ba99D99b;

    address internal constant SYRUP_USDT = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-20T15:17:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Optimism()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Unichain()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
    }

    function test_ARBITRUM_controllerUpgrade() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testControllerUpgrade({
            oldController: Arbitrum.ALM_CONTROLLER,
            newController: ARBITRUM_NEW_ALM_CONTROLLER
        });
    }

    function test_OPTIMISM_controllerUpgrade() public onChain(ChainIdUtils.Optimism()) {
        _testControllerUpgrade({
            oldController: Optimism.ALM_CONTROLLER,
            newController: OPTIMISM_NEW_ALM_CONTROLLER
        });
    }

    function test_UNICHAIN_controllerUpgrade() public onChain(ChainIdUtils.Unichain()) {
        _testControllerUpgrade({
            oldController: Unichain.ALM_CONTROLLER,
            newController: UNICHAIN_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_onboardSyrupUSDT() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
            SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
            SYRUP_USDT
        );

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(redeemKey),   0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), 0);

        _executeAllPayloadsAndBridges();

        _testMapleIntegration(MapleE2ETestParams({
            ctx:           ctx,
            vault:         SYRUP_USDT,
            depositAmount: 1_000_000e6,
            depositKey:    depositKey,
            redeemKey:     redeemKey,
            withdrawKey:   withdrawKey,
            tolerance:     10
        }));
    }

}

contract SparkEthereum_20251016_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20251016;
        _blockDate = "2025-10-10T17:44:00Z";
    }

    function test_ETHEREUM_sparkLend_cbbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDT, 500_000_000, 100_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 450_000_000, 50_000_000,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDT, 5_000_000_000, 1_000_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 5_000_000_000, 200_000_000,  12 hours);
    }

}

contract SparkEthereum_20251016_MorphoTests is MorphoTests {

    constructor() {
        _spellId   = 20251016;
        _blockDate = "2025-10-10T17:44:00Z";
    }

}

contract SparkEthereum_20251016_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20251016;
        _blockDate = "2025-10-10T17:44:00Z";
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Avalanche()].payload = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        chainData[ChainIdUtils.Ethereum()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
    }

}
