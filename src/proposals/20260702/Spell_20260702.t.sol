// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test }   from "forge-std/Test.sol";
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

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
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

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

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
    ISparkVaultV2Like,
    IERC20Like
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260702_SLLTests is SparkLiquidityLayerTests {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    using DomainHelpers for Domain;
    using OptionsBuilder for bytes;

    address internal constant ARBITRUM_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    // > bc -l <<< 'scale=27; e( l(1.05)/(60 * 60 * 24 * 365) )'
    //   1.000000001547125957863212167
    uint256 internal constant FIVE_PCT_APY = 1.000000001547125957863212167e27;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 internal constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782454872;  // Jun-26-2026 6:21:12 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.ArbitrumOne()].payload = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        chainData[ChainIdUtils.Avalanche()].payload   = 0x011A115b5498B85b3d12245A3a7296F77325B5C3;
        chainData[ChainIdUtils.Base()].payload        = 0x93c81ADc7F98FdBC8C7a15eCBeD312c8F6adbcB3;
        chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
        chainData[ChainIdUtils.Optimism()].payload    = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;
        chainData[ChainIdUtils.Unichain()].payload    = 0x32F5820F1a67419bD46e0F973B85AB0E0f17b62a;
    }

    function test_BASE_sll_removeExcessLiquidity() external onChain(ChainIdUtils.Base()) {
        // Prevent other OP chain spells from running so their L2 SentMessage logs don't
        // interfere with the Base bridge relay (all OP chains share 0x4200...0007 as L2 messenger)
        chainData[ChainIdUtils.Optimism()].payload = address(0);
        chainData[ChainIdUtils.Unichain()].payload = address(0);

        uint256 baseUsdsBalanceBefore  = IERC20(Base.USDS).balanceOf(Base.ALM_PROXY);
        uint256 baseSusdsBalanceBefore = IERC20(Base.SUSDS).balanceOf(Base.ALM_PROXY);

        assertEq(baseUsdsBalanceBefore,  146_550_618.210418117475041461e18);
        assertEq(baseSusdsBalanceBefore, 191_958_411.108646346259425604e18);

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

        assertEq(unichainUsdsBalanceBefore,  99_990_828.814818609701977623e18);
        assertEq(unichainSusdsBalanceBefore, 94_737_866.160999974496590936e18);

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
            LZ_EID_ARBITRUM
        ));

        assertEq(ctx.rateLimits.getRateLimitData(key).maxAmount, 5_000_000e6);
        assertEq(ctx.rateLimits.getRateLimitData(key).slope,     uint256(50_000_000e6) / 1 days);

        assertEq(
            mainnetController.layerZeroRecipients(LZ_EID_ARBITRUM),
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
            dstEid       : LZ_EID_ARBITRUM,
            to           : mainnetController.layerZeroRecipients(LZ_EID_ARBITRUM),
            amountLD     : bridgeAmount,
            minAmountLD  : bridgeAmount,
            extraOptions : options,
            composeMsg   : "",
            oftCmd       : ""
        });
        MessagingFee memory fee = ILayerZero(USDT_OFT).quoteSend(sendParams, false);

        uint64 sentNonce = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT_OFT,
            LZ_EID_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM)))
        ) + 1;

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),      bridgeAmount);
        assertEq(usdt.balanceOf(USDT_OFT),                usdtOFTBalanceBefore);
        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 5_000_000e6);

        vm.prank(ctx.relayer);
        mainnetController.transferTokenLayerZero{value: fee.nativeFee}(
            USDT_OFT,
            bridgeAmount,
            LZ_EID_ARBITRUM
        );

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),      0);
        assertEq(usdt.balanceOf(USDT_OFT),                usdtOFTBalanceBefore + bridgeAmount);
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

        // `LZBridgeTesting.relayMessagesToDestination` ended on the Arbitrum as the selected fork.
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), usdt0ArbitrumProxyBalanceBefore + bridgeAmount);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // --- Step 3: Verify rate limit refills after 1 day ---

        skip(1 days + 1 seconds);

        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 5_000_000e6);
    }

    function test_ETHEREUM_sll_lzRateLimits() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController mainnetController   = MainnetController(ctx.controller);

        bytes32 key = keccak256(abi.encode(
            mainnetController.LIMIT_LAYERZERO_TRANSFER(),
            USDT_OFT,
            LZ_EID_ARBITRUM
        ));

        assertEq(ctx.rateLimits.getRateLimitData(key).maxAmount, 0);
        assertEq(ctx.rateLimits.getRateLimitData(key).slope,     0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(key),        0);

        assertEq(mainnetController.layerZeroRecipients(LZ_EID_ARBITRUM), bytes32(0));

        _executeAllPayloadsAndBridges();

        assertEq(ctx.rateLimits.getRateLimitData(key).maxAmount, 5_000_000e6);
        assertEq(ctx.rateLimits.getRateLimitData(key).slope,     uint256(50_000_000e6) / 1 days);
        assertEq(ctx.rateLimits.getCurrentRateLimit(key),        5_000_000e6);

        assertEq(
            mainnetController.layerZeroRecipients(LZ_EID_ARBITRUM),
            bytes32(uint256(uint160(Arbitrum.ALM_PROXY)))
        );
    }

    function test_ARBITRUM_sll_lzRateLimits() external onChain(ChainIdUtils.ArbitrumOne()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        ForeignController foreignController   = ForeignController(ctx.controller);

        bytes32 key = keccak256(abi.encode(
            foreignController.LIMIT_LAYERZERO_TRANSFER(),
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM
        ));

        assertEq(ctx.rateLimits.getCurrentRateLimit(key), 0);

        assertEq(foreignController.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(0));

        _executeAllPayloadsAndBridges();

        assertEq(ctx.rateLimits.getCurrentRateLimit(key), type(uint256).max);

        assertEq(
            foreignController.layerZeroRecipients(LZ_EID_ETHEREUM),
            bytes32(uint256(uint160(Ethereum.ALM_PROXY)))
        );
    }

    function test_OPTIMISM_sll_removeExcessLiquidity() external onChain(ChainIdUtils.Optimism()) {
        // Prevent other OP chain spells from running so their L2 SentMessage logs don't
        // interfere with the Optimism bridge relay (all OP chains share 0x4200...0007 as L2 messenger)
        chainData[ChainIdUtils.Base()].payload     = address(0);
        chainData[ChainIdUtils.Unichain()].payload = address(0);

        uint256 optimismUsdsBalanceBefore  = IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY);
        uint256 optimismSusdsBalanceBefore = IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        assertEq(optimismUsdsBalanceBefore,  100_304_256.586332342515511286e18);
        assertEq(optimismSusdsBalanceBefore, 182_561_888.353827758745421790e18);

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

    function test_ARBITRUM_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.ArbitrumOne()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Arbitrum.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Arbitrum.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Arbitrum.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Arbitrum.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR),                true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Arbitrum.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Arbitrum.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Arbitrum.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Arbitrum.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR),                true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](recordedLogs.length);

        uint256 validIndex = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[validIndex] = recordedLogs[i];
            validIndex++;
        }

        assertEq(validIndex, 3);  // RoleGranted was only called three times on the ALMProxyFreezable contract, rest of newLogs is empty

        assertEq32(newLogs[0].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[1].topics[1], proxy.ALLOCATOR_ROLE());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER_ROLE());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Arbitrum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Arbitrum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Arbitrum.ALM_FREEZER_MULTISIG);
    }

    function test_ARBITRUM_sparkVaultV2_configureSPUSDT() external onChain(ChainIdUtils.ArbitrumOne()) {
        _testVaultConfiguration({
            asset:      ARBITRUM_USDT,
            name:       "Spark Savings USDT",
            symbol:     "spUSDT",
            rho:        1782227880,
            vault_:     Arbitrum.SPARK_VAULT_V2_SPUSDT,
            minVsr:     1e27,
            maxVsr:     SIX_PCT_APY,
            depositCap: 250_000_000e6,
            amount:     1_000_000e6
        });
    }

    function _testVaultConfiguration(
        address asset,
        string  memory name,
        string  memory symbol,
        uint64  rho,
        address vault_,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositCap,
        uint256 amount
    ) internal override {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ISparkVaultV2Like vault = ISparkVaultV2Like(vault_);

        bytes32 takeKey = RateLimitHelpers.makeAddressKey(
            ForeignController(Arbitrum.ALM_CONTROLLER).LIMIT_SPARK_VAULT_TAKE(),
            vault_
        );
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            ForeignController(Arbitrum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            vault.asset(),
            vault_
        );

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR),      true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Arbitrum.ALM_PROXY_FREEZABLE), false);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Arbitrum.ALM_PROXY),           false);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        0);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         0);

        assertEq(vault.asset(),      asset);
        assertEq(vault.name(),       name);
        assertEq(vault.decimals(),   IERC20Like(vault.asset()).decimals());
        assertEq(vault.symbol(),     symbol);
        assertEq(vault.rho(),        rho);
        assertEq(vault.chi(),        uint192(1e27));
        assertEq(vault.vsr(),        1e27);
        assertEq(vault.minVsr(),     1e27);
        assertEq(vault.maxVsr(),     1e27);
        assertEq(vault.depositCap(), 0);

        assertLt(vault.rho(), block.timestamp);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 0);

        assertEq(vault.balanceOf(address(1)), 0);
        assertEq(vault.totalSupply(),         0);

        _executeAllPayloadsAndBridges();

        assertEq(vault.balanceOf(address(1)), 1e6);
        assertEq(vault.totalSupply(),         1e6);

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR),      true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Arbitrum.ALM_PROXY_FREEZABLE), true);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Arbitrum.ALM_PROXY),           true);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        1);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         1);

        assertEq(vault.minVsr(),     minVsr);
        assertEq(vault.maxVsr(),     maxVsr);
        assertEq(vault.depositCap(), depositCap);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        _testSetterIntegration(vault, minVsr, maxVsr);

        uint256 initialChi = vault.nowChi();

        vm.prank(Arbitrum.ALM_PROXY_FREEZABLE);
        vault.setVsr(SIX_PCT_APY);

        skip(1 days);

        assertGt(vault.nowChi(), initialChi);

        _testSparkVaultV2Integration(SparkVaultV2E2ETestParams({
            ctx:             ctx,
            vault:           vault_,
            takeKey:         takeKey,
            transferKey:     transferKey,
            takeAmount:      amount,
            transferAmount:  amount,
            userVaultAmount: amount,
            tolerance:       10
        }));
    }

    function _testSetterIntegration(ISparkVaultV2Like vault, uint256 minVsr, uint256 maxVsr) internal {
        vm.startPrank(Arbitrum.ALM_PROXY_FREEZABLE);

        vm.expectRevert("SparkVault/vsr-too-low");
        vault.setVsr(minVsr - 1);

        vault.setVsr(minVsr);

        vm.expectRevert("SparkVault/vsr-too-high");
        vault.setVsr(maxVsr + 1);

        vault.setVsr(maxVsr);

        vm.stopPrank();
    }

    function test_ARBITRUM_sll_spUSDT_usdt0RoundTrip() external onChain(ChainIdUtils.ArbitrumOne()) {
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        ForeignController foreignController = ForeignController(Arbitrum.ALM_CONTROLLER);
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

        IERC20            usdt0Arbitrum = IERC20(ARBITRUM_USDT);
        IERC20            usdt          = IERC20(Ethereum.USDT);
        ISparkVaultV2Like vault         = ISparkVaultV2Like(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        Bridge storage lzBridge = _getLZBridge(ChainIdUtils.ArbitrumOne());

        address user   = makeAddr("user");
        uint256 amount = 1_000_000e6;

        // ================================================================================
        // STEP 1: Setter sets VSR to 5% APY
        // ================================================================================

        vm.prank(Arbitrum.ALM_PROXY_FREEZABLE);
        vault.setVsr(FIVE_PCT_APY);

        // ================================================================================
        // STEP 2: User deposits USDT0 into spUSDT on Arbitrum
        // ================================================================================

        uint256 vaultUsdt0Starting = usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        deal(ARBITRUM_USDT, user, amount);

        assertEq(usdt0Arbitrum.balanceOf(user),                           amount);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        vm.startPrank(user);
        SafeERC20.safeIncreaseAllowance(usdt0Arbitrum, Arbitrum.SPARK_VAULT_V2_SPUSDT, amount);
        uint256 userShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(usdt0Arbitrum.balanceOf(user),                           0);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount);

        // ================================================================================
        // STEP 3: SLL takes USDT0 from spUSDT into ALMProxy on Arbitrum
        // ================================================================================

        uint256 arbProxyUsdt0Starting = usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Starting);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.takeFromSparkVault(Arbitrum.SPARK_VAULT_V2_SPUSDT, amount);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Starting + amount);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        // ================================================================================
        // STEP 4: USDT0 transferred to USDT0 OFT on Arbitrum (Arbitrum → Mainnet bridge)
        // ================================================================================

        uint64 sentNonce1 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT)))
        ) + 1;

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Starting + amount);

        deal(Arbitrum.ALM_RELAYER_MULTISIG, 0.1 ether);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.transferTokenLayerZero{value: 0.1 ether}(
            USDT0_OFT_ARBITRUM,
            amount,
            LZ_EID_ETHEREUM
        );

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Starting);

        // ================================================================================
        // STEP 5: Relay message to Mainnet — USDT arrives in ALMProxy on Mainnet
        // ================================================================================

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethProxyUsdtStarting = usdt.balanceOf(Ethereum.ALM_PROXY);
        uint256 ethOFTUsdtStarting   = usdt.balanceOf(USDT_OFT);

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting);

        _skipLZPendingNonces(
            USDT_OFT,
            LZ_EID_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM))),
            sentNonce1
        );

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        LZBridgeTesting.relayMessagesToSource(lzBridge, true, USDT0_OFT_ARBITRUM, USDT_OFT);

        // `LZBridgeTesting.relayMessagesToSource` ended on the Ethereum as the selected fork.
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting - amount);

        // ================================================================================
        // STEP 6: Warp 10 days, deal additional $2k into mainnet ALMProxy
        // ================================================================================

        uint256 interest = 2_000e6;  // $2k covers real 10-day interest at 5% APY (~$1338)

        skip(10 days);

        // Also warp Arbitrum fork so the vault's VSR accrues over the same 10 days
        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        skip(10 days);
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        deal(Ethereum.USDT, Ethereum.ALM_PROXY, ethProxyUsdtStarting + amount + interest);

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount + interest);

        // ================================================================================
        // STEP 7: USDT transferred to USDT OFT on Mainnet (Mainnet → Arbitrum bridge)
        // ================================================================================

        uint64 sentNonce2 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT_OFT,
            LZ_EID_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM)))
        ) + 1;

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount + interest);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting - amount);

        deal(Ethereum.ALM_RELAYER_MULTISIG, 0.1 ether);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.transferTokenLayerZero{value: 0.1 ether}(
            USDT_OFT,
            amount + interest,
            LZ_EID_ARBITRUM
        );

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting + interest);

        // ================================================================================
        // STEP 8: Relay message to Arbitrum — USDT0 received in Arbitrum ALMProxy
        // ================================================================================

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Starting);

        _skipLZPendingNonces(
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT))),
            sentNonce2
        );

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(lzBridge, true, USDT_OFT, USDT0_OFT_ARBITRUM);

        // `LZBridgeTesting.relayMessagesToDestination` ended on the Arbitrum as the selected fork.
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Starting + amount + interest);

        // ================================================================================
        // STEP 9: USDT0 transferAsset into spUSDT vault
        // ================================================================================

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Starting + amount + interest);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.transferAsset(ARBITRUM_USDT, Arbitrum.SPARK_VAULT_V2_SPUSDT, amount + interest);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Starting);
        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount + interest);

        // ================================================================================
        // STEP 10: User redeems all shares, gets more assets out
        // ================================================================================

        assertEq(usdt0Arbitrum.balanceOf(user), 0);
        assertEq(vault.balanceOf(user),         userShares);

        vm.prank(user);
        vault.redeem(userShares, user, user);

        // 1m + 10 days of interest at 5% APY
        // bc -l <<< 'scale=27; e( l(1.000000001547125957863212448)*(60*60*24*10) )'
        // 1.001337610630706965933736950
        assertEq(usdt0Arbitrum.balanceOf(user), 1_001_337.610630e6);
        assertEq(vault.balanceOf(user),         0);
    }

}

contract SparkEthereum_20260702_SparklendTests is SparklendTests {

    address internal constant OLD_USDC_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;
    address internal constant NEW_USDC_IRM = 0xDE99e49E9e42B1d8490C38926e6C9A79010e6eF2;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782454872;  // Jun-26-2026 6:21:12 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.ArbitrumOne()].payload = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        chainData[ChainIdUtils.Avalanche()].payload   = 0x011A115b5498B85b3d12245A3a7296F77325B5C3;
        chainData[ChainIdUtils.Base()].payload        = 0x93c81ADc7F98FdBC8C7a15eCBeD312c8F6adbcB3;
        chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
        chainData[ChainIdUtils.Optimism()].payload    = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;
        chainData[ChainIdUtils.Unichain()].payload    = 0x32F5820F1a67419bD46e0F973B85AB0E0f17b62a;
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
        _blockDate = 1782454872;  // Jun-26-2026 6:21:12 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.ArbitrumOne()].payload = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        chainData[ChainIdUtils.Avalanche()].payload   = 0x011A115b5498B85b3d12245A3a7296F77325B5C3;
        chainData[ChainIdUtils.Base()].payload        = 0x93c81ADc7F98FdBC8C7a15eCBeD312c8F6adbcB3;
        chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
        chainData[ChainIdUtils.Optimism()].payload    = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;
        chainData[ChainIdUtils.Unichain()].payload    = 0x32F5820F1a67419bD46e0F973B85AB0E0f17b62a;
    }

    function test_AVALANCHE_bridgeConfiguration() external onChain(ChainIdUtils.Avalanche()) {
        IExecutor executor = IExecutor(Avalanche.SPARK_EXECUTOR);

        assertEq(executor.delay(),                                                       0);
        assertEq(executor.gracePeriod(),                                                 7 days);
        assertEq(executor.hasRole(executor.GUARDIAN_ROLE(), Avalanche.ALM_OPS_MULTISIG), false);

        _executeAllPayloadsAndBridges();

        assertEq(executor.delay(),                                                       3 days);
        assertEq(executor.gracePeriod(),                                                 7 days);
        assertEq(executor.hasRole(executor.GUARDIAN_ROLE(), Avalanche.ALM_OPS_MULTISIG), true);
    }

    function test_AVALANCHE_timelock() external onChain(ChainIdUtils.Avalanche()) {
        _executeAllPayloadsAndBridges();

        IExecutor executor = IExecutor(Avalanche.SPARK_EXECUTOR);

        assertEq(executor.delay(), 3 days);

        address[] memory targets           = new address[](1);
        uint256[] memory values            = new uint256[](1);
        string[]  memory signatures        = new string[](1);
        bytes[]   memory calldatas         = new bytes[](1);
        bool[]    memory withDelegatecalls = new bool[](1);

        targets[0]    = address(executor);
        signatures[0] = "receiveFunds()";

        uint256 firstId = executor.actionsSetCount();

        // Step 1: Prank as receiver, call queue
        vm.prank(Avalanche.SPARK_RECEIVER);
        executor.queue(targets, values, signatures, calldatas, withDelegatecalls);

        assertEq(uint256(executor.getCurrentState(firstId)), uint256(IExecutor.ActionsSetState.Queued));

        // Step 2: Prank as multisig (guardian), call cancel
        vm.prank(Avalanche.ALM_OPS_MULTISIG);
        executor.cancel(firstId);

        assertEq(uint256(executor.getCurrentState(firstId)), uint256(IExecutor.ActionsSetState.Canceled));

        // Step 3: Warp to execution time — can't execute (cancelled)
        vm.warp(block.timestamp + 3 days);

        vm.expectRevert(abi.encodeWithSignature("OnlyQueuedActions()"));
        executor.execute(firstId);

        // Step 4: Prank as receiver, call queue again
        uint256 secondId = executor.actionsSetCount();

        vm.prank(Avalanche.SPARK_RECEIVER);
        executor.queue(targets, values, signatures, calldatas, withDelegatecalls);

        assertEq(uint256(executor.getCurrentState(secondId)), uint256(IExecutor.ActionsSetState.Queued));

        // Step 5: Warp 1 second before execution time
        vm.warp(block.timestamp + 3 days - 1);

        vm.expectRevert(abi.encodeWithSignature("TimelockNotFinished()"));
        executor.execute(secondId);

        // Step 6: Warp to exactly execution time
        vm.warp(block.timestamp + 3 days);
        executor.execute(secondId);

        assertEq(uint256(executor.getCurrentState(secondId)), uint256(IExecutor.ActionsSetState.Executed));
    }

}

interface IOptimismPortalLike {
    struct WithdrawalTransaction {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes   data;
    }
    function disputeGameFinalityDelaySeconds() external view returns (uint256);
    function finalizedWithdrawals(bytes32 withdrawalHash) external view returns (bool);
    function finalizeWithdrawalTransactionExternalProof(WithdrawalTransaction memory tx_, address proofSubmitter) external;
    function proofMaturityDelaySeconds() external view returns (uint256);
    function provenWithdrawals(bytes32 withdrawalHash, address proofSubmitter)
        external view returns (address disputeGameProxy, uint64 timestamp);
}

interface IDisputeGameLike {
    function createdAt() external view returns (uint64);
    function maxClockDuration() external view returns (uint64);
    function resolvedAt() external view returns (uint64);
    function status() external view returns (uint8);
}

// Tests finalization of the six USDS/sUSDS withdrawals to the Ethereum ALM Proxy from the
// July 2, 2026 payload executions, proven by 0x62B5...7205 on Jul 6, 2026 19:51-19:52 UTC.
//
// Payload execution txs (L2):
// - Base:     0x7b8e692e523eca62aaad95e04e279ad7d8c31b38c0694af18f1a0635f54323ae
// - Optimism: 0x216a9de9b07a0c954dd797b6abf95c4ed0af6b1ba0f5156d0c40533fb656a16e
// - Unichain: 0x33f66feba68e407fd92e5b4c46da5a53389096a5a6b9c40b8909f1a57986edda
//
// Prove txs (mainnet):
// - Base USDS:      0x473d73a86c352eb5690ed034ec99fe23a990884b7fe596fa371a171955435027
// - Base sUSDS:     0x0f55a595c183f91c518e67e8e1bae9c5fc57d42d2d2c83211e78d0a59ec14661
// - Optimism USDS:  0x95b914217bfa5c73b31b0e7aa5618794f8525e4eaef7eb58adc96b1f671f9e28
// - Optimism sUSDS: 0x4f57a0203810361240b0f5d4510f51d5cdec3a5d289d5da2f7fec33d8002cdbb
// - Unichain USDS:  0x9e09f9774b6aee5893154a2f0a07b6d73690d2f42c05a993f956d4094bdd3d5f
// - Unichain sUSDS: 0xdde1db47b774480c6047df42daf05791dd88026acae959557a9b922c2207ab76
contract SparkEthereum_20260702_USDSTransfers is Test {

    IOptimismPortalLike internal constant BASE_PORTAL     = IOptimismPortalLike(0x49048044D57e1C92A77f79988d21Fa8fAF74E97e);
    IOptimismPortalLike internal constant OPTIMISM_PORTAL = IOptimismPortalLike(0xbEb5Fc579115071764c7423A4f12eDde41f106Ed);
    IOptimismPortalLike internal constant UNICHAIN_PORTAL = IOptimismPortalLike(0x0bd48f6B86a26D3a217d0Fa6FfE2B491B956A7a2);

    // Address that proved the withdrawals. finalizeWithdrawalTransaction looks up the
    // proof under msg.sender, so it must also finalize.
    address internal constant WITHDRAWAL_PROVER = 0x62B5262D3639eA5A8ec0D8Aa442f1135ecF77205;

    // WithdrawalProven withdrawalHashes from the prove tx logs
    bytes32 internal constant BASE_USDS_WITHDRAWAL_HASH      = 0x3804fddde5e48a9247ce80e61bf5b6210139109819f60f6d5e5ef9321605af9c;
    bytes32 internal constant BASE_SUSDS_WITHDRAWAL_HASH     = 0xc0cadfd06a8a8f0407e1f259c7bd29463d1de8745dddf370553c324a600b525c;
    bytes32 internal constant OPTIMISM_USDS_WITHDRAWAL_HASH  = 0xa407473cf1802bfb7158fa4f8c2813e406cb7bccac6b317ebf19d06cb3b98094;
    bytes32 internal constant OPTIMISM_SUSDS_WITHDRAWAL_HASH = 0x09bed00a0e906527caa3dcc3285164e3ed03bac8c6bac33862bf90edb9673f4d;
    bytes32 internal constant UNICHAIN_USDS_WITHDRAWAL_HASH  = 0xa3bed448324a1097af0ce4dc09ec9009f996367e85021c1768ed7b983a480476;
    bytes32 internal constant UNICHAIN_SUSDS_WITHDRAWAL_HASH = 0xf50a5f656c3f8fa8f790c673d28ba337b7211a421cf0f06ecc64b3e45ac861ba;

    // Full ALM Proxy balances bridged by the payloads, from the finalizeBridgeERC20
    // calls inside each withdrawal (decoded from the MessagePassed events)
    uint256 internal constant BASE_USDS_AMOUNT      = 146_550_618.210418117475041461e18;
    uint256 internal constant BASE_SUSDS_AMOUNT     = 191_958_411.108646346259425604e18;
    uint256 internal constant OPTIMISM_USDS_AMOUNT  = 100_304_256.586332342515511286e18;
    uint256 internal constant OPTIMISM_SUSDS_AMOUNT = 182_561_888.353827758745421790e18;
    uint256 internal constant UNICHAIN_USDS_AMOUNT  =  99_990_828.814818609701977623e18;
    uint256 internal constant UNICHAIN_SUSDS_AMOUNT =  94_737_866.160999974496590936e18;

    // finalizeWithdrawalTransaction(WithdrawalTransaction) relaying
    // finalizeBridgeERC20(token, remoteToken, from, ALM_PROXY, amount) through each L1
    // messenger. Reconstructed from the prove tx inputs; each hashes to the proven
    // withdrawalHash above.
    bytes internal constant BASE_USDS_FINALIZE_CALLDATA      = hex"8c3152e90000000000000000000000000000000000000000000000000000000000000020000100000000000000000000000000000000000000000000000000000001f4d20000000000000000000000004200000000000000000000000000000000000007000000000000000000000000866e82a600a1414e583f7f13623f1ac5d58b0afa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b000100000000000000000000000000000000000000000000000000000000dff1000000000000000000000000ee44cdb68d618d58f75d9fe0818b640bd7b8a7b7000000000000000000000000a5874756416fa632257eea380cabd2e87ced352a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000dc035d45d973e3ec169d2276ddab16f1e407384f000000000000000000000000820c137fa70c8691f0e44dc420a5e53c168921dc0000000000000000000000002917956eff0b5eaf030abdb4ef4296df775009ca0000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e00000000000000000000000000000000000000000079394ceea0d27def9000b500000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant BASE_SUSDS_FINALIZE_CALLDATA     = hex"8c3152e90000000000000000000000000000000000000000000000000000000000000020000100000000000000000000000000000000000000000000000000000001f4d30000000000000000000000004200000000000000000000000000000000000007000000000000000000000000866e82a600a1414e583f7f13623f1ac5d58b0afa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b000100000000000000000000000000000000000000000000000000000000dff2000000000000000000000000ee44cdb68d618d58f75d9fe0818b640bd7b8a7b7000000000000000000000000a5874756416fa632257eea380cabd2e87ced352a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000a3931d71877c0e7a3148cb7eb4463524fec27fbd0000000000000000000000005875eee11cf8398102fdad704c9e96607675467a0000000000000000000000002917956eff0b5eaf030abdb4ef4296df775009ca0000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e0000000000000000000000000000000000000000009ec8c6514a7f76b23be94400000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant OPTIMISM_USDS_FINALIZE_CALLDATA  = hex"8c3152e900000000000000000000000000000000000000000000000000000000000000200001000000000000000000000000000000000000000000000000000000008463000000000000000000000000420000000000000000000000000000000000000700000000000000000000000025ace71c97b33cc4729cf772ae268934f7ab5fa1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b00010000000000000000000000000000000000000000000000000000000084510000000000000000000000008f41dbf6b8498561ce1d73af16cd9c0d8ee20ba60000000000000000000000003d25b7d486cae1810374d37a48bcf0963c9b80570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000dc035d45d973e3ec169d2276ddab16f1e407384f0000000000000000000000004f13a96ec5c4cf34e442b46bbd98a0791f20edc3000000000000000000000000876664f0c9ff24d1aa355ce9f1680ae1a5bf36fb0000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e00000000000000000000000000000000000000000052f840a5202d9b59f5aff600000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant OPTIMISM_SUSDS_FINALIZE_CALLDATA = hex"8c3152e900000000000000000000000000000000000000000000000000000000000000200001000000000000000000000000000000000000000000000000000000008464000000000000000000000000420000000000000000000000000000000000000700000000000000000000000025ace71c97b33cc4729cf772ae268934f7ab5fa1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b00010000000000000000000000000000000000000000000000000000000084520000000000000000000000008f41dbf6b8498561ce1d73af16cd9c0d8ee20ba60000000000000000000000003d25b7d486cae1810374d37a48bcf0963c9b80570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000a3931d71877c0e7a3148cb7eb4463524fec27fbd000000000000000000000000b5b2dc7fd34c249f4be7fb1fcea07950784229e0000000000000000000000000876664f0c9ff24d1aa355ce9f1680ae1a5bf36fb0000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e0000000000000000000000000000000000000000009702fbcc5e4b32c53187de00000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant UNICHAIN_USDS_FINALIZE_CALLDATA  = hex"8c3152e900000000000000000000000000000000000000000000000000000000000000200001000000000000000000000000000000000000000000000000000000000e4500000000000000000000000042000000000000000000000000000000000000070000000000000000000000009a3d64e386c18cb1d6d5179a9596a4b5736e98a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b0001000000000000000000000000000000000000000000000000000000000d8d000000000000000000000000a13152006d0216fe4627a0d3b006087a6a55d752000000000000000000000000df0535a4c96c9cd8921d8fec92a7680b281681d20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000dc035d45d973e3ec169d2276ddab16f1e407384f0000000000000000000000007e10036acc4b56d4dfca3b77810356ce52313f9c000000000000000000000000345e368fccd62266b3f5f37c9a131fd1c39f58690000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e00000000000000000000000000000000000000000052b5e1b105015ef4d9fe1700000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes internal constant UNICHAIN_SUSDS_FINALIZE_CALLDATA = hex"8c3152e900000000000000000000000000000000000000000000000000000000000000200001000000000000000000000000000000000000000000000000000000000e4600000000000000000000000042000000000000000000000000000000000000070000000000000000000000009a3d64e386c18cb1d6d5179a9596a4b5736e98a6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c27a800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001e4d764ad0b0001000000000000000000000000000000000000000000000000000000000d8e000000000000000000000000a13152006d0216fe4627a0d3b006087a6a55d752000000000000000000000000df0535a4c96c9cd8921d8fec92a7680b281681d20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007a12000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e40166a07a000000000000000000000000a3931d71877c0e7a3148cb7eb4463524fec27fbd000000000000000000000000a06b10db9f390990364a3984c04fadf1c13691b5000000000000000000000000345e368fccd62266b3f5f37c9a131fd1c39f58690000000000000000000000001601843c5e9bc251a3272907010afa41fa18347e0000000000000000000000000000000000000000004e5d8603f28e42f99f5c5800000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public {
        // Fork at the block of the last prove tx (Unichain sUSDS), so all six proofs exist
        // and the test stays valid after the real finalizes land on mainnet
        vm.createSelectFork(getChain("mainnet").rpcUrl, 25_475_707);
    }

    function test_USDSTransfers_base_fromProver() public {
        _testFinalizationFromProver(BASE_PORTAL, BASE_USDS_WITHDRAWAL_HASH,  BASE_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  BASE_USDS_AMOUNT,  1_783_453_872);  // Jul 7, 2026, 19:51:12 UTC
        _testFinalizationFromProver(BASE_PORTAL, BASE_SUSDS_WITHDRAWAL_HASH, BASE_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, BASE_SUSDS_AMOUNT, 1_783_453_884);  // Jul 7, 2026, 19:51:24 UTC
    }

    function test_USDSTransfers_base_externalProof() public {
        _testFinalizationExternalProof(BASE_PORTAL, BASE_USDS_WITHDRAWAL_HASH,  BASE_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  BASE_USDS_AMOUNT,  1_783_453_872);  // Jul 7, 2026, 19:51:12 UTC
        _testFinalizationExternalProof(BASE_PORTAL, BASE_SUSDS_WITHDRAWAL_HASH, BASE_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, BASE_SUSDS_AMOUNT, 1_783_453_884);  // Jul 7, 2026, 19:51:24 UTC
    }

    function test_USDSTransfers_optimism_fromProver() public {
        _testFinalizationFromProver(OPTIMISM_PORTAL, OPTIMISM_USDS_WITHDRAWAL_HASH,  OPTIMISM_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  OPTIMISM_USDS_AMOUNT,  1_783_972_296);  // Jul 13, 2026, 19:51:36 UTC
        _testFinalizationFromProver(OPTIMISM_PORTAL, OPTIMISM_SUSDS_WITHDRAWAL_HASH, OPTIMISM_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, OPTIMISM_SUSDS_AMOUNT, 1_783_972_332);  // Jul 13, 2026, 19:52:12 UTC
    }

    function test_USDSTransfers_optimism_externalProof() public {
        _testFinalizationExternalProof(OPTIMISM_PORTAL, OPTIMISM_USDS_WITHDRAWAL_HASH,  OPTIMISM_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  OPTIMISM_USDS_AMOUNT,  1_783_972_296);  // Jul 13, 2026, 19:51:36 UTC
        _testFinalizationExternalProof(OPTIMISM_PORTAL, OPTIMISM_SUSDS_WITHDRAWAL_HASH, OPTIMISM_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, OPTIMISM_SUSDS_AMOUNT, 1_783_972_332);  // Jul 13, 2026, 19:52:12 UTC
    }

    function test_USDSTransfers_unichain_fromProver() public {
        _testFinalizationFromProver(UNICHAIN_PORTAL, UNICHAIN_USDS_WITHDRAWAL_HASH,  UNICHAIN_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  UNICHAIN_USDS_AMOUNT,  1_783_972_344);  // Jul 13, 2026, 19:52:24 UTC
        _testFinalizationFromProver(UNICHAIN_PORTAL, UNICHAIN_SUSDS_WITHDRAWAL_HASH, UNICHAIN_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, UNICHAIN_SUSDS_AMOUNT, 1_783_972_356);  // Jul 13, 2026, 19:52:36 UTC
    }

    function test_USDSTransfers_unichain_externalProof() public {
        _testFinalizationExternalProof(UNICHAIN_PORTAL, UNICHAIN_USDS_WITHDRAWAL_HASH,  UNICHAIN_USDS_FINALIZE_CALLDATA,  Ethereum.USDS,  UNICHAIN_USDS_AMOUNT,  1_783_972_344);  // Jul 13, 2026, 19:52:24 UTC
        _testFinalizationExternalProof(UNICHAIN_PORTAL, UNICHAIN_SUSDS_WITHDRAWAL_HASH, UNICHAIN_SUSDS_FINALIZE_CALLDATA, Ethereum.SUSDS, UNICHAIN_SUSDS_AMOUNT, 1_783_972_356);  // Jul 13, 2026, 19:52:36 UTC
    }

    // Finalize from the proving address with the exact calldata of the real transaction
    // (finalizeWithdrawalTransaction looks up the proof under msg.sender)
    function _testFinalizationFromProver(
        IOptimismPortalLike portal,
        bytes32             withdrawalHash,
        bytes memory        finalizeCalldata,
        address             token,
        uint256             amount,
        uint256             finalizableTimestamp
    )
        internal
    {
        _warpToFinalizable(portal, withdrawalHash, finalizableTimestamp);

        uint256 balanceBefore = IERC20(token).balanceOf(Ethereum.ALM_PROXY);

        vm.prank(WITHDRAWAL_PROVER);
        ( bool success, ) = address(portal).call(finalizeCalldata);
        assertTrue(success);

        _assertFinalized(portal, withdrawalHash, token, balanceBefore, amount);
    }

    // Finalize from an unrelated address, referencing the prover's proof
    function _testFinalizationExternalProof(
        IOptimismPortalLike portal,
        bytes32             withdrawalHash,
        bytes memory        finalizeCalldata,
        address             token,
        uint256             amount,
        uint256             finalizableTimestamp
    )
        internal
    {
        _warpToFinalizable(portal, withdrawalHash, finalizableTimestamp);

        uint256 balanceBefore = IERC20(token).balanceOf(Ethereum.ALM_PROXY);

        // Decode the WithdrawalTransaction out of the finalizeWithdrawalTransaction calldata
        bytes memory finalizeArgs = new bytes(finalizeCalldata.length - 4);
        for (uint256 i; i < finalizeArgs.length; ++i) {
            finalizeArgs[i] = finalizeCalldata[i + 4];
        }

        vm.prank(makeAddr("user"));
        portal.finalizeWithdrawalTransactionExternalProof(
            abi.decode(finalizeArgs, (IOptimismPortalLike.WithdrawalTransaction)),
            WITHDRAWAL_PROVER
        );

        _assertFinalized(portal, withdrawalHash, token, balanceBefore, amount);
    }

    function _warpToFinalizable(
        IOptimismPortalLike portal,
        bytes32             withdrawalHash,
        uint256             finalizableTimestamp
    )
        internal
    {
        ( address disputeGame, uint64 provenTimestamp ) = portal.provenWithdrawals(withdrawalHash, WITHDRAWAL_PROVER);

        // The dispute games were still IN_PROGRESS at the fork block, so mock resolution
        // as DEFENDER_WINS at the earliest possible time (createdAt + maxClockDuration).
        // The proof maturity delay is then the binding constraint, making
        // finalizableTimestamp the earliest real-world finalization time assuming timely
        // game resolution. Base's ZK validity game (type 621) has no challenge clock —
        // maxClockDuration() reverts — so its earliest resolution is createdAt.
        uint64 resolvedAt = IDisputeGameLike(disputeGame).createdAt();
        try IDisputeGameLike(disputeGame).maxClockDuration() returns (uint64 maxClockDuration) {
            resolvedAt += maxClockDuration;
        } catch {}

        vm.mockCall(disputeGame, abi.encodeWithSelector(IDisputeGameLike.status.selector),     abi.encode(uint8(2)));  // DEFENDER_WINS
        vm.mockCall(disputeGame, abi.encodeWithSelector(IDisputeGameLike.resolvedAt.selector), abi.encode(resolvedAt));

        assertEq(portal.finalizedWithdrawals(withdrawalHash), false);

        // Check finalizableTimestamp is the earliest time past both the proof maturity
        // delay (from prove time) and the dispute game finality delay (from game
        // resolution time), then warp to it
        uint256 proofMaturedAt = provenTimestamp + portal.proofMaturityDelaySeconds();
        uint256 gameMaturedAt  = resolvedAt + portal.disputeGameFinalityDelaySeconds();

        assertEq(finalizableTimestamp, (proofMaturedAt > gameMaturedAt ? proofMaturedAt : gameMaturedAt) + 1);

        vm.warp(finalizableTimestamp);
    }

    function _assertFinalized(
        IOptimismPortalLike portal,
        bytes32             withdrawalHash,
        address             token,
        uint256             balanceBefore,
        uint256             amount
    )
        internal view
    {
        assertEq(portal.finalizedWithdrawals(withdrawalHash), true);

        assertEq(IERC20(token).balanceOf(Ethereum.ALM_PROXY), balanceBefore + amount);
    }

}
