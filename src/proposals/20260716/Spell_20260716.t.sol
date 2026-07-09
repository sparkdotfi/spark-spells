// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { console } from "forge-std/console.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Robinhood } from "spark-address-registry/Robinhood.sol";
import { XLayer }    from "spark-address-registry/XLayer.sol";

import { IALMProxy }                           from "spark-alm-controller/src/interfaces/IALMProxy.sol";
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
import { DealUtils }    from "src/libraries/DealUtils.sol";

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
    ISyrupLike,
    IERC20Like
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260716_SLLTests is SparkLiquidityLayerTests {

    using DomainHelpers for Domain;
    using OptionsBuilder for bytes;

    address internal constant ETHEREUM_PAXOS_USDG_DEPOSIT  = 0xf752cF318dfF2C01575c98741AA52e7a34d873Fd;
    address internal constant OLD_FREEZER_RELAYER          = 0x59C85fe4385403e93877e48e5521f2F02B150359;
    address internal constant OLD_MORPHO_VAULT_V2_USDT     = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;
    address internal constant ROBINHOOD_PAXOS_USDG_DEPOSIT = 0x17C0F5345d1144fdF670D14719077be3842E5087;
    address internal constant ROBINHOOD_SPUSDG_SETTER      = 0x59C85fe4385403e93877e48e5521f2F02B150359;

    // > bc -l <<< 'scale=27; e( l(1.05)/(60 * 60 * 24 * 365) )'
    //   1.000000001547125957863212167
    uint256 internal constant FIVE_PCT_APY = 1.000000001547125957863212167e27;

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783581356;  // Jul-9-2026 7:15:56 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xcc7529473B850103524905D3914470898aDe8747;
        // chainData[ChainIdUtils.Robinhood()].payload = 0xcc7529473B850103524905D3914470898aDe8747;
    }

    function test_ETHEREUM_sll_deactivateOldMorphoUsdtVault() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  OLD_MORPHO_VAULT_V2_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), OLD_MORPHO_VAULT_V2_USDT);

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ROBINHOOD_controllerRoleChanges() external onChain(ChainIdUtils.Robinhood()) {
        ForeignController controller = ForeignController(Robinhood.ALM_CONTROLLER);

        assertEq(controller.getRoleMemberCount(controller.FREEZER()), 1);

        assertEq(controller.hasRole(controller.FREEZER(), Robinhood.ALM_FREEZER_MULTISIG), false);
        assertEq(controller.hasRole(controller.FREEZER(), OLD_FREEZER_RELAYER),            true);

        assertEq(controller.getRoleMemberCount(controller.RELAYER()), 2);

        assertEq(controller.hasRole(controller.RELAYER(), Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(controller.hasRole(controller.RELAYER(), Robinhood.ALM_RELAYER_MULTISIG),          true);
        assertEq(controller.hasRole(controller.RELAYER(), OLD_FREEZER_RELAYER),                     true);

        _executeAllPayloadsAndBridges();

        assertEq(controller.getRoleMemberCount(controller.FREEZER()), 1);

        assertEq(controller.hasRole(controller.FREEZER(), Robinhood.ALM_FREEZER_MULTISIG), true);
        assertEq(controller.hasRole(controller.FREEZER(), OLD_FREEZER_RELAYER),            false);

        assertEq(controller.getRoleMemberCount(controller.RELAYER()), 2);

        assertEq(controller.hasRole(controller.RELAYER(), Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(controller.hasRole(controller.RELAYER(), Robinhood.ALM_RELAYER_MULTISIG),          true);
        assertEq(controller.hasRole(controller.RELAYER(), OLD_FREEZER_RELAYER),                     false);
    }

    function test_ROBINHOOD_sll_enableUsdgTransferToPaxosDeposit() external onChain(ChainIdUtils.Robinhood()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            ForeignController(Robinhood.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Robinhood.USDG,
            ROBINHOOD_PAXOS_USDG_DEPOSIT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Robinhood.USDG,
            destination    : ROBINHOOD_PAXOS_USDG_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 50_000_000e6
        }));
    }

    function test_ETHEREUM_sll_enableUsdgTransferToPaxosDeposit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDG,
            ETHEREUM_PAXOS_USDG_DEPOSIT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDG,
            destination    : ETHEREUM_PAXOS_USDG_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 50_000_000e6
        }));
    }

    function test_XLAYER_sll_spUSDT_usdt0RoundTrip() external onChain(ChainIdUtils.XLayer()) {
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        ForeignController foreignController = ForeignController(XLayer.ALM_CONTROLLER);
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

        IERC20            usdt0XLayer = IERC20(USDT0_XLAYER);
        IERC20            usdt        = IERC20(Ethereum.USDT);
        ISparkVaultV2Like vault       = ISparkVaultV2Like(XLayer.SPARK_VAULT_V2_SPUSDT);

        Bridge storage lzBridge = _getLZBridge(ChainIdUtils.XLayer());

        address user   = makeAddr("user");
        uint256 amount = 1_000_000e6;

        // ================================================================================
        // STEP 1: Setter sets VSR to 5% APY
        // ================================================================================

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        IALMProxyFreezableLike(XLayer.ALM_PROXY_FREEZABLE).doCall(XLayer.SPARK_VAULT_V2_SPUSDT, abi.encodeCall(ISparkVaultV2Like.setVsr, (FIVE_PCT_APY)));

        // ================================================================================
        // STEP 2: User deposits USDT0 into spUSDT on XLayer
        // ================================================================================

        uint256 vaultUsdt0Starting = usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT);

        deal(USDT0_XLAYER, user, amount);

        assertEq(usdt0XLayer.balanceOf(user),                         amount);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        vm.startPrank(user);
        SafeERC20.safeIncreaseAllowance(usdt0XLayer, XLayer.SPARK_VAULT_V2_SPUSDT, amount);
        uint256 userShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(usdt0XLayer.balanceOf(user),                         0);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount);

        // ================================================================================
        // STEP 3: SLL takes USDT0 from spUSDT into ALMProxy on XLayer
        // ================================================================================

        uint256 xLayerProxyUsdt0Starting = usdt0XLayer.balanceOf(XLayer.ALM_PROXY);

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY),             xLayerProxyUsdt0Starting);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        foreignController.takeFromSparkVault(XLayer.SPARK_VAULT_V2_SPUSDT, amount);

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY),             xLayerProxyUsdt0Starting + amount);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        // ================================================================================
        // STEP 4: USDT0 transferred to USDT0 OFT on XLayer (XLayer → Mainnet bridge)
        // ================================================================================

        uint64 sentNonce1 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT0_OFT_XLAYER,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT)))
        ) + 1;

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY), xLayerProxyUsdt0Starting + amount);

        deal(XLayer.ALM_RELAYER_MULTISIG, 0.1 ether);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        foreignController.transferTokenLayerZero{value: 0.1 ether}(
            USDT0_OFT_XLAYER,
            amount,
            LZ_EID_ETHEREUM
        );

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY), xLayerProxyUsdt0Starting);

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
            LZ_EID_XLAYER,
            bytes32(uint256(uint160(USDT0_OFT_XLAYER))),
            sentNonce1
        );

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        LZBridgeTesting.relayMessagesToSource(lzBridge, true, USDT0_OFT_XLAYER, USDT_OFT);

        // `LZBridgeTesting.relayMessagesToSource` ended on the Ethereum as the selected fork.
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting - amount);

        // ================================================================================
        // STEP 6: Warp 10 days, deal additional $2k into mainnet ALMProxy
        // ================================================================================

        uint256 interest = 2_000e6;  // $2k covers real 10-day interest at 5% APY (~$1338)

        skip(10 days);

        // Also warp XLayer fork so the vault's VSR accrues over the same 10 days
        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        skip(10 days);
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        deal(Ethereum.USDT, Ethereum.ALM_PROXY, ethProxyUsdtStarting + amount + interest);

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount + interest);

        // ================================================================================
        // STEP 7: USDT transferred to USDT OFT on Mainnet (Mainnet → XLayer bridge)
        // ================================================================================

        uint64 sentNonce2 = ILZEndpointExtended(LZ_ENDPOINT).outboundNonce(
            USDT_OFT,
            LZ_EID_XLAYER,
            bytes32(uint256(uint160(USDT0_OFT_XLAYER)))
        ) + 1;

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting + amount + interest);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting - amount);

        deal(Ethereum.ALM_RELAYER_MULTISIG, 0.1 ether);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.transferTokenLayerZero{value: 0.1 ether}(
            USDT_OFT,
            amount + interest,
            LZ_EID_XLAYER
        );

        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY), ethProxyUsdtStarting);
        assertEq(usdt.balanceOf(USDT_OFT),           ethOFTUsdtStarting + interest);

        // ================================================================================
        // STEP 8: Relay message to XLayer — USDT0 received in XLayer ALMProxy
        // ================================================================================

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY), xLayerProxyUsdt0Starting);

        _skipLZPendingNonces(
            USDT0_OFT_XLAYER,
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(USDT_OFT))),
            sentNonce2
        );

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(lzBridge, true, USDT_OFT, USDT0_OFT_XLAYER);

        // `LZBridgeTesting.relayMessagesToDestination` ended on the XLayer as the selected fork.
        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY), xLayerProxyUsdt0Starting + amount + interest);

        // ================================================================================
        // STEP 9: USDT0 transferAsset into spUSDT vault
        // ================================================================================

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY),             xLayerProxyUsdt0Starting + amount + interest);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        foreignController.transferAsset(USDT0_XLAYER, XLayer.SPARK_VAULT_V2_SPUSDT, amount + interest);

        assertEq(usdt0XLayer.balanceOf(XLayer.ALM_PROXY),             xLayerProxyUsdt0Starting);
        assertEq(usdt0XLayer.balanceOf(XLayer.SPARK_VAULT_V2_SPUSDT), vaultUsdt0Starting + amount + interest);

        // ================================================================================
        // STEP 10: User redeems all shares, gets more assets out
        // ================================================================================

        assertEq(usdt0XLayer.balanceOf(user), 0);
        assertEq(vault.balanceOf(user),       userShares);

        vm.prank(user);
        vault.redeem(userShares, user, user);

        // 1m + 10 days of interest at 5% APY
        // bc -l <<< 'scale=27; e( l(1.000000001547125957863212448)*(60*60*24*10) )'
        // 1.001337610630706965933736950
        assertEq(usdt0XLayer.balanceOf(user), 1_001_337.610630e6);
        assertEq(vault.balanceOf(user),       0);
    }

    function test_ROBINHOOD_sll_spUSDGPaxosRoundTrip() external onChain(ChainIdUtils.Robinhood()) {
        _executeAllPayloadsAndBridges();

        ForeignController foreignController = ForeignController(Robinhood.ALM_CONTROLLER);
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

        IERC20            usdgRobinhood = IERC20(Robinhood.USDG);
        IERC20            usdgMainnet   = IERC20(Ethereum.USDG);
        ISparkVaultV2Like vault         = ISparkVaultV2Like(Robinhood.SPARK_VAULT_V2_SPUSDG);

        address user     = makeAddr("user");
        uint256 amount   = 1_000_000e6;
        uint256 interest = 2_000e6;

        // ================================================================================
        // STEP 1: Setter sets VSR to 5% APY
        // ================================================================================

        vm.prank(ROBINHOOD_SPUSDG_SETTER);
        vault.setVsr(FIVE_PCT_APY);

        // ================================================================================
        // STEP 2: User deposits USDG into spUSDG on Robinhood
        // ================================================================================

        uint256 vaultUsdgStarting = usdgRobinhood.balanceOf(Robinhood.SPARK_VAULT_V2_SPUSDG);

        if (!DealUtils.patchedDeal(Robinhood.USDG, user, amount)) {
            deal(Robinhood.USDG, user, amount);
        }

        assertEq(usdgRobinhood.balanceOf(user),                            amount);
        assertEq(usdgRobinhood.balanceOf(Robinhood.SPARK_VAULT_V2_SPUSDG), vaultUsdgStarting);

        vm.startPrank(user);
        SafeERC20.safeIncreaseAllowance(usdgRobinhood, Robinhood.SPARK_VAULT_V2_SPUSDG, amount);
        uint256 userShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(usdgRobinhood.balanceOf(user),                            0);
        assertEq(usdgRobinhood.balanceOf(Robinhood.SPARK_VAULT_V2_SPUSDG), vaultUsdgStarting + amount);

        // ================================================================================
        // STEP 3: Controller takes USDG from spUSDG into ALMProxy on Robinhood
        // ================================================================================

        uint256 robinhoodProxyUsdgStarting = usdgRobinhood.balanceOf(Robinhood.ALM_PROXY);

        vm.prank(Robinhood.ALM_RELAYER_MULTISIG);
        foreignController.takeFromSparkVault(Robinhood.SPARK_VAULT_V2_SPUSDG, amount);

        assertEq(usdgRobinhood.balanceOf(Robinhood.ALM_PROXY),             robinhoodProxyUsdgStarting + amount);
        assertEq(usdgRobinhood.balanceOf(Robinhood.SPARK_VAULT_V2_SPUSDG), vaultUsdgStarting);

        // ================================================================================
        // STEP 4: Controller uses transferAsset to send USDG to the Paxos deposit address on Robinhood
        // ================================================================================

        uint256 robinhoodPaxosUsdgStarting = usdgRobinhood.balanceOf(ROBINHOOD_PAXOS_USDG_DEPOSIT);

        vm.prank(Robinhood.ALM_RELAYER_MULTISIG);
        foreignController.transferAsset(Robinhood.USDG, ROBINHOOD_PAXOS_USDG_DEPOSIT, amount);

        assertEq(usdgRobinhood.balanceOf(Robinhood.ALM_PROXY),          robinhoodProxyUsdgStarting);
        assertEq(usdgRobinhood.balanceOf(ROBINHOOD_PAXOS_USDG_DEPOSIT), robinhoodPaxosUsdgStarting + amount);

        // ================================================================================
        // STEP 5: Paxos redeems the Robinhood-side USDG off-chain — deal the transferred
        //         amount onto the Mainnet ALMProxy to simulate settlement
        // ================================================================================

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 mainnetProxyUsdgStarting = usdgMainnet.balanceOf(Ethereum.ALM_PROXY);

        deal(Ethereum.USDG, Ethereum.ALM_PROXY, mainnetProxyUsdgStarting + amount);

        assertEq(usdgMainnet.balanceOf(Ethereum.ALM_PROXY), mainnetProxyUsdgStarting + amount);

        // ================================================================================
        // STEP 6: Warp 10 days, deal additional $2k interest into the Mainnet ALMProxy
        // ================================================================================

        skip(10 days);

        // Also warp the Robinhood fork so the vault's VSR accrues over the same 10 days
        chainData[ChainIdUtils.Robinhood()].domain.selectFork();
        skip(10 days);
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        deal(Ethereum.USDG, Ethereum.ALM_PROXY, mainnetProxyUsdgStarting + amount + interest);

        assertEq(usdgMainnet.balanceOf(Ethereum.ALM_PROXY), mainnetProxyUsdgStarting + amount + interest);

        // ================================================================================
        // STEP 7: Mainnet ALMProxy uses transferAsset to send USDG to the Paxos deposit
        //         address on Mainnet
        // ================================================================================

        uint256 mainnetPaxosUsdgStarting = usdgMainnet.balanceOf(ETHEREUM_PAXOS_USDG_DEPOSIT);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetController.transferAsset(Ethereum.USDG, ETHEREUM_PAXOS_USDG_DEPOSIT, amount + interest);

        assertEq(usdgMainnet.balanceOf(Ethereum.ALM_PROXY),          mainnetProxyUsdgStarting);
        assertEq(usdgMainnet.balanceOf(ETHEREUM_PAXOS_USDG_DEPOSIT), mainnetPaxosUsdgStarting + amount + interest);

        // ================================================================================
        // STEP 8: Paxos redeems the Mainnet-side USDG off-chain — deal the amount + interest
        //         back onto the Robinhood ALMProxy to simulate settlement back to Robinhood
        // ================================================================================

        chainData[ChainIdUtils.Robinhood()].domain.selectFork();

        if (!DealUtils.patchedDeal(Robinhood.USDG, Robinhood.ALM_PROXY, robinhoodProxyUsdgStarting + amount + interest)) {
            deal(Robinhood.USDG, Robinhood.ALM_PROXY, robinhoodProxyUsdgStarting + amount + interest);
        }

        assertEq(usdgRobinhood.balanceOf(Robinhood.ALM_PROXY), robinhoodProxyUsdgStarting + amount + interest);

        // ================================================================================
        // STEP 9: Foreign controller on Robinhood uses transferAsset to send the USDG back
        //         into the spUSDG vault
        // ================================================================================

        vm.prank(Robinhood.ALM_RELAYER_MULTISIG);
        foreignController.transferAsset(Robinhood.USDG, Robinhood.SPARK_VAULT_V2_SPUSDG, amount + interest);

        assertEq(usdgRobinhood.balanceOf(Robinhood.ALM_PROXY),             robinhoodProxyUsdgStarting);
        assertEq(usdgRobinhood.balanceOf(Robinhood.SPARK_VAULT_V2_SPUSDG), vaultUsdgStarting + amount + interest);

        // ================================================================================
        // STEP 10: User redeems all shares, gets more assets out due to accrued interest
        // ================================================================================

        assertEq(usdgRobinhood.balanceOf(user), 0);
        assertEq(vault.balanceOf(user),         userShares);

        vm.prank(user);
        vault.redeem(userShares, user, user);

        // 1m + 10 days of interest at 5% APY
        // bc -l <<< 'scale=27; e( l(1.000000001547125957863212167)*(60*60*24*10) )'
        // 1.001337610630706965933736950
        assertEq(usdgRobinhood.balanceOf(user), 1_001_337.610629e6);
        assertEq(vault.balanceOf(user),         0);
    }

    function test_XLAYER_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.XLayer()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(XLayer.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     XLayer.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     XLayer.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       XLayer.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), XLayer.SPARK_EXECUTOR),                true);

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     XLayer.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     XLayer.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       XLayer.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), XLayer.SPARK_EXECUTOR),                true);
    }

    function test_Robinhood_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Robinhood()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Robinhood.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Robinhood.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Robinhood.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Robinhood.SPARK_EXECUTOR),                true);

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Robinhood.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(),     Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),       Robinhood.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Robinhood.SPARK_EXECUTOR),                true);
    }

}

contract SparkEthereum_20260716_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783581356;  // Jul-9-2026 7:15:56 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xcc7529473B850103524905D3914470898aDe8747;
        // chainData[ChainIdUtils.Robinhood()].payload = 0xcc7529473B850103524905D3914470898aDe8747;
    }

}

contract SparkEthereum_20260716_SpellTests is SpellTests {

    address internal constant GROVE_ALM_PROXY    = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant PAXOS_USDG_DEPOSIT = 0xf752cF318dfF2C01575c98741AA52e7a34d873Fd;
    address internal constant USDT_OFT           = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;

    uint256 internal constant ANCHORAGE_FEES_AMOUNT         = 500_000e18;
    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;
    uint256 internal constant GROVE_SYRUP_USDC_AMOUNT       = 85_943_747.637271e6;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant INCENTIVES_AMOUNT             = 2_000_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 64_231e18;

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783581356;  // Jul-9-2026 7:15:56 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xcc7529473B850103524905D3914470898aDe8747;
        // chainData[ChainIdUtils.Robinhood()].payload = 0xcc7529473B850103524905D3914470898aDe8747;
    }

    function test_ETHEREUM_sll_transferUsdsToGrove() external onChain(ChainIdUtils.Ethereum()) {
        IERC20     usds  = IERC20(Ethereum.USDS);
        ISyrupLike syrup = ISyrupLike(Ethereum.SYRUP_USDC);

        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);
        IALMProxy         almProxy   = IALMProxy(Ethereum.ALM_PROXY);

        uint256 expectedUsdsAmount = syrup.convertToAssets(GROVE_SYRUP_USDC_AMOUNT) * 1e12;

        assertEq(expectedUsdsAmount, 100_781_916.482416e18);

        uint256 almProxyUsdsBalanceBefore = usds.balanceOf(Ethereum.ALM_PROXY);
        uint256 groveUsdsBalanceBefore    = usds.balanceOf(GROVE_ALM_PROXY);

        assertEq(almProxyUsdsBalanceBefore, 0);
        assertEq(groveUsdsBalanceBefore,    0);

        assertEq(controller.hasRole(controller.RELAYER(), Ethereum.SPARK_PROXY), false);
        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),  Ethereum.SPARK_PROXY), false);

        _executeAllPayloadsAndBridges();

        assertEq(controller.hasRole(controller.RELAYER(), Ethereum.SPARK_PROXY), false);
        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),  Ethereum.SPARK_PROXY), false);

        assertEq(usds.balanceOf(Ethereum.ALM_PROXY), almProxyUsdsBalanceBefore);
        assertEq(usds.balanceOf(GROVE_ALM_PROXY),    groveUsdsBalanceBefore + expectedUsdsAmount);
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore             = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore             = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore        = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore                 = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,             39_309_297.249708907368137212e18);
        assertEq(foundationBalanceBefore,             311_390.0222e18);
        assertEq(assetFoundationBalanceBefore,        155_000e18);
        assertEq(almOpsBalanceBefore,                 0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT - INCENTIVES_AMOUNT - ANCHORAGE_FEES_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT + INCENTIVES_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT + ANCHORAGE_FEES_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
