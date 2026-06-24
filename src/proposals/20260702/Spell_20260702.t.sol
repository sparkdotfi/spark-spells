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

    address internal constant ARBITRUM_SPARK_VAULT_V2_SPUSDT = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;
    address internal constant ARBITRUM_USDT                  = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address internal constant ARBITRUM_ALM_PROXY_FREEZABLE   = 0x4eE67c8Db1BAa6ddE99d936C7D313B5d31e8fa38;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 internal constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782228626;  // Jun-23-2026 3:30:26 PM +UTC
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

    function test_ARBITRUM_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.ArbitrumOne()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(ARBITRUM_ALM_PROXY_FREEZABLE);

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
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

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
            vault_:     ARBITRUM_SPARK_VAULT_V2_SPUSDT,
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
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        ARBITRUM_ALM_PROXY_FREEZABLE), false);
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

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 0);

        _executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR),      true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        ARBITRUM_ALM_PROXY_FREEZABLE), true);
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

        vm.prank(ARBITRUM_ALM_PROXY_FREEZABLE);
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
        vm.startPrank(ARBITRUM_ALM_PROXY_FREEZABLE);

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
        ISparkVaultV2Like vault         = ISparkVaultV2Like(ARBITRUM_SPARK_VAULT_V2_SPUSDT);

        Bridge storage lzBridge = _getLZBridge(ChainIdUtils.ArbitrumOne());

        address user   = makeAddr("user");
        uint256 amount = 1_000_000e6;

        // ================================================================================
        // STEP 1: User deposits USDT0 into spUSDT on Arbitrum
        // ================================================================================

        uint256 vaultUsdt0Before = usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT);

        deal(ARBITRUM_USDT, user, amount);

        assertEq(usdt0Arbitrum.balanceOf(user),                           amount);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before);

        vm.startPrank(user);
        SafeERC20.safeIncreaseAllowance(usdt0Arbitrum, ARBITRUM_SPARK_VAULT_V2_SPUSDT, amount);
        uint256 userShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(usdt0Arbitrum.balanceOf(user),                           0);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before + amount);

        // ================================================================================
        // STEP 2: SLL takes USDT0 from spUSDT into ALMProxy on Arbitrum
        // ================================================================================

        uint256 arbProxyUsdt0Before = usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Before);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before + amount);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.takeFromSparkVault(ARBITRUM_SPARK_VAULT_V2_SPUSDT, amount);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Before + amount);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before);

        // ================================================================================
        // STEP 3: USDT0 transferred to USDT0 OFT on Arbitrum (Arbitrum → Mainnet bridge)
        // ================================================================================

        uint64 sentNonce1 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT)))
        ) + 1;

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Before + amount);

        deal(Arbitrum.ALM_RELAYER_MULTISIG, 1 ether);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.transferTokenLayerZero{value: 1 ether}(
            USDT0_OFT_ARBITRUM,
            amount,
            LZ_EID_ETHEREUM
        );

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Before);

        // ================================================================================
        // STEP 4: Relay message to Mainnet — USDT arrives in ALMProxy on Mainnet
        // ================================================================================

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethProxyUsdtBefore = usdt.balanceOf(Ethereum.ALM_PROXY);
        uint256 ethOFTUsdtBefore   = usdt.balanceOf(USDT_OFT);

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtBefore);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtBefore);

        _skipLZPendingNonces(
            USDT_OFT,
            LZ_ENDPOINT_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM))),
            sentNonce1
        );

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        LZBridgeTesting.relayMessagesToSource(lzBridge, true, USDT0_OFT_ARBITRUM, USDT_OFT);

        // Now on Ethereum fork
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtBefore + amount);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtBefore - amount);

        // ================================================================================
        // STEP 5: USDT transferred to USDT OFT on Mainnet (Mainnet → Arbitrum bridge)
        // ================================================================================

        uint64 sentNonce2 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT_OFT,
            LZ_ENDPOINT_ARBITRUM,
            bytes32(uint256(uint160(USDT0_OFT_ARBITRUM)))
        ) + 1;

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtBefore + amount);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtBefore - amount);

        deal(Ethereum.ALM_RELAYER_MULTISIG, 1 ether);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.transferTokenLayerZero{value: 1 ether}(
            USDT_OFT,
            amount,
            LZ_ENDPOINT_ARBITRUM
        );

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtBefore);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtBefore);

        // ================================================================================
        // STEP 6: Relay message to Arbitrum — USDT0 received in Arbitrum ALMProxy
        // ================================================================================

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Before);

        _skipLZPendingNonces(
            USDT0_OFT_ARBITRUM,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT))),
            sentNonce2
        );

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(lzBridge, true, USDT_OFT, USDT0_OFT_ARBITRUM);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY), arbProxyUsdt0Before + amount);

        // ================================================================================
        // STEP 7: USDT0 transferAsset into spUSDT vault
        // ================================================================================

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Before + amount);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        foreignController.transferAsset(ARBITRUM_USDT, ARBITRUM_SPARK_VAULT_V2_SPUSDT, amount);

        assertEq(usdt0Arbitrum.balanceOf(Arbitrum.ALM_PROXY),             arbProxyUsdt0Before);
        assertEq(usdt0Arbitrum.balanceOf(ARBITRUM_SPARK_VAULT_V2_SPUSDT), vaultUsdt0Before + amount);
    }

}

contract SparkEthereum_20260702_SparklendTests is SparklendTests {

    address internal constant OLD_USDC_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;
    address internal constant NEW_USDC_IRM = 0xDE99e49E9e42B1d8490C38926e6C9A79010e6eF2;

    constructor() {
        _spellId   = 20260702;
        _blockDate = 1782228626;  // Jun-23-2026 3:30:26 PM +UTC
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
        _blockDate = 1782228626;  // Jun-23-2026 3:30:26 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xe08BD6D9016EAC522903FC68c80F809664C2692A;
        // chainData[ChainIdUtils.Optimism()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // chainData[ChainIdUtils.Unichain()].payload = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
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

}
