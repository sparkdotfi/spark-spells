// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ILayerZero, MessagingFee, SendParam } from "spark-alm-controller/src/interfaces/ILayerZero.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPool }               from "sparklend-v1-core/interfaces/IPool.sol";
import { IScaledBalanceToken } from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }                                from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests, ILZEndpointExtended } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }                                    from "src/test-harness/SpellTests.sol";

import { OptionsBuilder } from "lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";

import { Bridge, BridgeType } from "xchain-helpers/testing/Bridge.sol";
import { LZBridgeTesting }    from "xchain-helpers/testing/bridges/LZBridgeTesting.sol";

import {
    IALMProxyFreezableLike,
    IMorphoVaultLike,
    IPositionManagerLike,
    ISparkVaultV2Like 
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260702_SLLTests is SparkLiquidityLayerTests {

    using DomainHelpers for Domain;
    using OptionsBuilder for bytes;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782209490;  // Jun-23-2026 10:11:30 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xe08BD6D9016EAC522903FC68c80F809664C2692A;
        // chainData[ChainIdUtils.Optimism()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Unichain()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
    }

    function test_BASE_sll_removeExcessLiquidity() external onChain(ChainIdUtils.Base()) {
        // Prevent other OP chain spells from running so their L2 SentMessage logs don't
        // interfere with the Base bridge relay (all OP chains share 0x4200...0007 as L2 messenger)
        chainData[ChainIdUtils.Optimism()].payload = address(0);
        chainData[ChainIdUtils.Unichain()].payload = address(0);

        uint256 baseUsdsBalanceBefore  = IERC20(Base.USDS).balanceOf(Base.ALM_PROXY);
        uint256 baseSusdsBalanceBefore = IERC20(Base.SUSDS).balanceOf(Base.ALM_PROXY);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.Base()].domain.selectFork();

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        // Base ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Base.USDS).balanceOf(Base.ALM_PROXY),  0);
        assertEq(IERC20(Base.SUSDS).balanceOf(Base.ALM_PROXY), 0);

        // Relay L2->L1 OP bridge messages to Ethereum (simulates the 7-day withdrawal finalization)
        OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.Base()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY),  ethUsdsBalanceBefore  + baseUsdsBalanceBefore);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY), ethSusdsBalanceBefore + baseSusdsBalanceBefore);
    }

    function test_UNICHAIN_sll_removeExcessLiquidity() external onChain(ChainIdUtils.Unichain()) {
        // Prevent other OP chain spells from running so their L2 SentMessage logs don't
        // interfere with the Unichain bridge relay (all OP chains share 0x4200...0007 as L2 messenger)
        chainData[ChainIdUtils.Base()].payload     = address(0);
        chainData[ChainIdUtils.Optimism()].payload = address(0);

        uint256 unichainUsdsBalanceBefore  = IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY);
        uint256 unichainSusdsBalanceBefore = IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.Unichain()].domain.selectFork();

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        // Unichain ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY),  0);
        assertEq(IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY), 0);

        // Relay L2->L1 OP bridge messages to Ethereum
        OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.Unichain()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY),  ethUsdsBalanceBefore  + unichainUsdsBalanceBefore);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY), ethSusdsBalanceBefore + unichainSusdsBalanceBefore);
    }

    function test_ETHEREUM_sll_bridgeUSDT0ToArbitrum() external onChain(ChainIdUtils.Ethereum()) {
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController mainnetController   = MainnetController(ctx.controller);

        _testLayerZeroBridgeUSDT0ToArbitrum(mainnetController, ctx);
    }

    function _testLayerZeroBridgeUSDT0ToArbitrum(
        MainnetController                 mainnetController,
        SparkLiquidityLayerContext memory ctx
    )
        internal onChain(ChainIdUtils.Ethereum())
    {
        IERC20 usdt          = IERC20(Ethereum.USDT);
        IERC20 usdt0Arbitrum = IERC20(USDT0_ARBITRUM);

        uint256 bridgeAmount = 1_000_000e6;

        bytes32 key = keccak256(abi.encode(
            mainnetController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            LZ_ENDPOINT_ARBITRUM
        ));

        assertEq(ctx.rateLimits.getRateLimitData(key).maxAmount, 5_000_000e6);
        assertEq(ctx.rateLimits.getRateLimitData(key).slope,     uint256(50_000_000e6) / 1 days);

        assertEq(
            mainnetController.layerZeroRecipients(LZ_ENDPOINT_ARBITRUM),
            bytes32(uint256(uint160(Arbitrum.ALM_PROXY)))
        );

        // --- Step 1: Bridge USDT from Ethereum to Arbitrum ---

        uint256 usdtProxyBalanceBefore = usdt.balanceOf(Ethereum.ALM_PROXY);
        uint256 usdtOFTBalanceBefore   = usdt.balanceOf(USDT_OFT);

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        uint256 usdt0ArbitrumProxyBalanceBefore = usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        deal(Ethereum.USDT, Ethereum.ALM_PROXY, bridgeAmount);
        deal(ctx.relayer, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        SendParam memory sendParams = SendParam({
            dstEid       : LZ_ENDPOINT_ARBITRUM,
            to           : mainnetController.layerZeroRecipients(LZ_ENDPOINT_ARBITRUM),
            amountLD     : bridgeAmount,
            minAmountLD  : bridgeAmount,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });
        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        uint64 sentNonce = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT_OFT,
            LZ_ENDPOINT_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM)))
        ) + 1;

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),        bridgeAmount);
        assertEq(usdt.balanceOf(USDT_OFT),                  usdtOFTBalanceBefore);
        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        vm.prank(ctx.relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            bridgeAmount,
            LZ_ENDPOINT_ARBITRUM
        );

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),        0);
        assertEq(usdt.balanceOf(USDT_OFT),                  usdtOFTBalanceBefore + bridgeAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 5_000_000e6 - bridgeAmount);

        // --- Step 2: Relay message to Arbitrum and verify USDT0 arrived ---

        Bridge storage bridge = _getLZBridge(ChainIdUtils.ArbitrumOne());

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), usdt0ArbitrumProxyBalanceBefore);

        _skipLZPendingNonces(
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT))),
            sentNonce
        );

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(bridge, true, USDT_OFT, USDT0_OFT_ARBITRUM);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), usdt0ArbitrumProxyBalanceBefore + bridgeAmount);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // --- Step 3: Verify rate limit refills after 1 day ---

        skip(1 days + 1 seconds);

        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 5_000_000e6);
    }

    function test_OPTIMISM_sll_removeExcessLiquidity() external onChain(ChainIdUtils.Optimism()) {
        // Prevent other OP chain spells from running so their L2 SentMessage logs don't
        // interfere with the Optimism bridge relay (all OP chains share 0x4200...0007 as L2 messenger)
        chainData[ChainIdUtils.Base()].payload     = address(0);
        chainData[ChainIdUtils.Unichain()].payload = address(0);

        uint256 optimismUsdsBalanceBefore  = IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY);
        uint256 optimismSusdsBalanceBefore = IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.Optimism()].domain.selectFork();

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        // Optimism ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY),  0);
        assertEq(IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY), 0);

        // Relay L2->L1 OP bridge messages to Ethereum (simulates the 7-day withdrawal finalization)
        OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.Optimism()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY),  ethUsdsBalanceBefore  + optimismUsdsBalanceBefore);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY), ethSusdsBalanceBefore + optimismSusdsBalanceBefore);
    }

}

contract SparkEthereum_20260702_SparklendTests is SparklendTests {

    address internal constant OLD_USDC_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;
    address internal constant NEW_USDC_IRM = 0xDE99e49E9e42B1d8490C38926e6C9A79010e6eF2;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782209490;  // Jun-23-2026 10:11:30 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xe08BD6D9016EAC522903FC68c80F809664C2692A;
        // chainData[ChainIdUtils.Optimism()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Unichain()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
    }

    function test_ETHEREUM_sparkLend_usdcIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDC_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0125e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDC_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.98e27
        });
        _testRateTargetKinkIRMUpdate("USDC", oldParams, newParams);
    }

}

contract SparkEthereum_20260702_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782209490;  // Jun-23-2026 10:11:30 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xe08BD6D9016EAC522903FC68c80F809664C2692A;
        // chainData[ChainIdUtils.Optimism()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Unichain()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
    }

}
