// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Vm, VmSafe } from "forge-std/Vm.sol";

import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";
import { XLayer }    from "spark-address-registry/XLayer.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { CCTPV2BridgeTesting }   from "xchain-helpers/testing/bridges/CCTPV2BridgeTesting.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";
import { SLLHelpers }   from "src/libraries/SLLHelpers.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    IMorphoVaultV2FactoryLike,
    IMorphoVaultV2Like,
    ISparkVaultV2Like
} from "src/interfaces/Interfaces.sol";

interface IAdministeredAgentLike {

    function call(address target, bytes memory data) external payable returns (bytes memory result);

}

// Diamond PAU controller (spUSDC PAU on X-Layer).
interface IControllerLike {

    struct Dispatch {
        address facet;
        bytes4  delegateSelector;
    }

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    struct Config {
        address facet;
        Wire[]  wires;
    }

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain) external view returns (bytes32);

    function erc4626_deposit(address token, uint256 amount, uint256 minSharesOut) external returns (uint256 shares);

    function erc4626_getDepositRateLimitKey(address token, address asset) external view returns (bytes32);

    function erc4626_getMaxExchangeRate(address token) external view returns (uint256);

    function erc4626_getWithdrawRateLimitKey(address token) external view returns (bytes32);

    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function erc4626_withdraw(address token, uint256 amount, uint256 maxSharesIn) external returns (uint256 shares);

    function getConfig(bytes32 integrationId) external view returns (Config memory);

    function getDispatch(bytes4 callSelector) external view returns (Dispatch memory);

}

interface IPSM3Like {

    function convertToAssetValue(uint256 shares) external view returns (uint256);

    function shares(address account) external view returns (uint256);

    function totalShares() external view returns (uint256);

}

abstract contract Spell_20261119_Common {

    using DomainHelpers for Domain;

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant NEW_ALM_CONTROLLER       = 0xc953972Cd006d1f12686fd7185c6D443b15900Cd;
    address internal constant XLAYER_MORPHO_VAULT_USDC = 0x3F2C1Abd139ECc99892034edCCBbcF5e1696a1bE;  // TODO deploy

    address internal constant XLAYER_MORPHO_VAULT_V2_FACTORY = 0x63D6eAc0d16D57dd131D9023ADb060277d3237d7;

    function _deployStandIns(Domain memory ethereum, Domain memory xlayer) internal {
        xlayer.selectFork();

        if (XLAYER_MORPHO_VAULT_USDC.code.length == 0) {
            address vault = IMorphoVaultV2FactoryLike(XLAYER_MORPHO_VAULT_V2_FACTORY).createVaultV2(
                XLayer.SPARK_EXECUTOR,
                XLayer.USDC,
                bytes32(0)
            );

            require(vault == XLAYER_MORPHO_VAULT_USDC, "UNEXPECTED STAND-IN VAULT ADDRESS");
        }

        ethereum.selectFork();
    }

}

contract SparkEthereum_20261119_SLLTests is SparkLiquidityLayerTests, Spell_20261119_Common {

    using DomainHelpers for Domain;

    bytes32 internal constant ERC4626_FACET_ID = "ERC4626_FACET";

    mapping(uint256 chainId => uint256 timestamp) internal forkTimestamp;

    constructor() {
        _spellId   = 20261119;
        _blockDate = 1794235200;  // Nov-09-2026 02:40:00 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        _deployStandIns(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.XLayer()].domain);

        _recordForkTimestamps();

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = NEW_ALM_CONTROLLER;
    }

    function _recordForkTimestamps() internal {
        for (uint256 i; i < allChains.length; ++i) {
            chainData[allChains[i]].domain.selectFork();

            forkTimestamp[allChains[i]] = block.timestamp;
        }

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    function _warpToForkBlock(uint256 chainId) internal {
        vm.warp(forkTimestamp[chainId]);
    }

    /**********************************************************************************************/
    /*** Item 1: Upgrade the ALM controller to MainnetController v1.11.0                        ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_controllerUpgrade() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController oldController = MainnetController(Ethereum.ALM_CONTROLLER);
        MainnetController newController = MainnetController(NEW_ALM_CONTROLLER);

        bytes32 controllerRole = ctx.proxy.CONTROLLER();
        bytes32 relayerRole    = newController.RELAYER();
        bytes32 freezerRole    = newController.FREEZER();

        // Constructor wiring of the new controller, checked again by MainnetControllerInit.upgradeController.
        assertEq(newController.hasRole(newController.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY), true);

        assertEq(address(newController.proxy()),      Ethereum.ALM_PROXY);
        assertEq(address(newController.rateLimits()), Ethereum.ALM_RATE_LIMITS);
        assertEq(address(newController.vault()),      Ethereum.ALLOCATOR_VAULT);
        assertEq(address(newController.psm()),        Ethereum.PSM);
        assertEq(address(newController.daiUsds()),    Ethereum.DAI_USDS);

        assertEq(newController.cctp(), Ethereum.CCTP_TOKEN_MESSENGER);     // CCTP V2 TokenMessengerV2
        assertEq(oldController.cctp(), Ethereum.CCTP_TOKEN_MESSENGER_V1);  // CCTP V1 TokenMessenger

        assertEq(newController.cctpMaxFeeRate(), 0);

        assertEq(ctx.proxy.hasRole(controllerRole, address(oldController)), true);
        assertEq(ctx.proxy.hasRole(controllerRole, address(newController)), false);

        assertEq(ctx.rateLimits.hasRole(controllerRole, address(oldController)), true);
        assertEq(ctx.rateLimits.hasRole(controllerRole, address(newController)), false);

        assertEq(newController.hasRole(relayerRole, ctx.relayer),                            false);
        assertEq(newController.hasRole(relayerRole, Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(newController.hasRole(freezerRole, ctx.freezer),                            false);

        _assertNewControllerConfig(newController, false);

        _executeAllPayloadsAndBridges();

        assertEq(ctx.proxy.hasRole(controllerRole, address(oldController)), false);
        assertEq(ctx.proxy.hasRole(controllerRole, address(newController)), true);

        assertEq(ctx.rateLimits.hasRole(controllerRole, address(oldController)), false);
        assertEq(ctx.rateLimits.hasRole(controllerRole, address(newController)), true);

        assertEq(newController.hasRole(relayerRole, ctx.relayer),                            true);
        assertEq(newController.hasRole(relayerRole, Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(newController.hasRole(freezerRole, ctx.freezer),                            true);

        assertEq(newController.cctpMaxFeeRate(), 0);

        _assertNewControllerConfig(newController, true);

        // Every migrated value equals the one on the old controller.
        _assertSameControllerConfig(oldController, newController);
    }

    function test_ETHEREUM_sll_controllerUpgradeEvents() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController oldController = MainnetController(Ethereum.ALM_CONTROLLER);
        MainnetController newController = MainnetController(NEW_ALM_CONTROLLER);

        vm.recordLogs();

        _executeMainnetPayload();

        VmSafe.Log[] memory newLogs = vm.getRecordedLogs();

        _assertMigratedSlippageEvents(oldController, newController, newLogs);

        _assertMigratedExchangeRateEvents(oldController, newController, newLogs);

        _assertMigratedTickLimitsEvents(oldController, newController, newLogs);

        _assertMigratedMintRecipientEvents(oldController, newController, newLogs);

        _assertMigratedLayerZeroEvents(oldController, newController, newLogs);

        _assertMigratedOtcEvents(oldController, newController, newLogs);
    }

    function _assertMigratedSlippageEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldLogs = _getEvents(block.chainid, address(oldController), MainnetController.MaxSlippageSet.selector);

        assertEq(oldLogs.length, 27);

        // 27 old events, but CURVE_SUSDSUSDT and CURVE_WEETHWETHNG were set twice.
        assertEq(_countEvents(newLogs, address(newController), MainnetController.MaxSlippageSet.selector), 25);


        for (uint256 i; i < oldLogs.length; ++i) {
            address pool = _toAddress(oldLogs[i].topics[1]);

            ( uint256 count, bytes memory data ) = _findEvents(newLogs, address(newController), MainnetController.MaxSlippageSet.selector, oldLogs[i].topics[1]);

            assertEq(count,                            1);
            assertEq(abi.decode(data, (uint256)),      oldController.maxSlippages(pool));
            assertEq(newController.maxSlippages(pool), oldController.maxSlippages(pool));

            assertTrue(newController.maxSlippages(pool) != 0);
        }
    }

    function _assertMigratedExchangeRateEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldLogs = _getEvents(block.chainid, address(oldController), MainnetController.MaxExchangeRateSet.selector);

        assertEq(oldLogs.length, 12);

        assertEq(_countEvents(newLogs, address(newController), MainnetController.MaxExchangeRateSet.selector), 12);

        for (uint256 i; i < oldLogs.length; ++i) {
            address token = _toAddress(oldLogs[i].topics[1]);

            ( uint256 count, bytes memory data ) = _findEvents(newLogs, address(newController), MainnetController.MaxExchangeRateSet.selector, oldLogs[i].topics[1]);

            assertEq(count,                                 1);
            assertEq(abi.decode(data, (uint256)),           oldController.maxExchangeRates(token));
            assertEq(newController.maxExchangeRates(token), oldController.maxExchangeRates(token));

            assertTrue(newController.maxExchangeRates(token) != 0);
        }
    }

    function _assertMigratedTickLimitsEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldLogs = _getEvents(block.chainid, address(oldController), MainnetController.UniswapV4TickLimitsSet.selector);

        assertEq(oldLogs.length, 5);

        assertEq(_countEvents(newLogs, address(newController), MainnetController.UniswapV4TickLimitsSet.selector), 5);

        for (uint256 i; i < oldLogs.length; ++i) {
            bytes32 poolId = oldLogs[i].topics[1];

            ( int24 oldTickLower, int24 oldTickUpper, uint24 oldMaxTickSpacing ) = oldController.uniswapV4TickLimits(poolId);

            assertTrue(oldMaxTickSpacing != 0);

            {
                ( uint256 count, bytes memory data ) = _findEvents(newLogs, address(newController), MainnetController.UniswapV4TickLimitsSet.selector, poolId);

                ( int24 tickLower, int24 tickUpper, uint24 maxTickSpacing ) = abi.decode(data, (int24, int24, uint24));

                assertEq(count,          1);
                assertEq(tickLower,      oldTickLower);
                assertEq(tickUpper,      oldTickUpper);
                assertEq(maxTickSpacing, oldMaxTickSpacing);
            }

            _assertUniswapV4TickLimits(newController, poolId, oldTickLower, oldTickUpper, oldMaxTickSpacing);
        }
    }

    function _assertMigratedMintRecipientEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldLogs = _getEvents(block.chainid, address(oldController), MainnetController.MintRecipientSet.selector);

        assertEq(oldLogs.length, 5);

        assertEq(_countEvents(newLogs, address(newController), MainnetController.MintRecipientSet.selector), 5);

        for (uint256 i; i < oldLogs.length; ++i) {
            uint32 domain = uint32(uint256(oldLogs[i].topics[1]));

            ( uint256 count, ) = _findEvents(newLogs, address(newController), MainnetController.MintRecipientSet.selector, oldLogs[i].topics[1]);

            assertEq(count,                                1);
            assertEq(newController.mintRecipients(domain), oldController.mintRecipients(domain));

            assertEq(newController.mintRecipients(domain) != bytes32(0), true);
        }
    }

    function _assertMigratedLayerZeroEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldLogs = _getEvents(block.chainid, address(oldController), MainnetController.LayerZeroRecipientSet.selector);

        assertEq(oldLogs.length, 2);

        assertEq(_countEvents(newLogs, address(newController), MainnetController.LayerZeroRecipientSet.selector), 2);

        for (uint256 i; i < oldLogs.length; ++i) {
            uint32 endpointId = uint32(uint256(oldLogs[i].topics[1]));

            ( uint256 count, bytes memory data ) = _findEvents(newLogs, address(newController), MainnetController.LayerZeroRecipientSet.selector, oldLogs[i].topics[1]);

            assertEq(count,                                         1);
            assertEq(abi.decode(data, (bytes32)),                   oldController.layerZeroRecipients(endpointId));
            assertEq(newController.layerZeroRecipients(endpointId), oldController.layerZeroRecipients(endpointId));

            assertTrue(newController.layerZeroRecipients(endpointId) != bytes32(0));
        }
    }

    function _assertMigratedOtcEvents(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs
    ) internal {
        VmSafe.EthGetLogs[] memory oldBufferLogs    = _getEvents(block.chainid, address(oldController), MainnetController.OTCBufferSet.selector);
        VmSafe.EthGetLogs[] memory oldWhitelistLogs = _getEvents(block.chainid, address(oldController), MainnetController.OTCWhitelistedAssetSet.selector);

        assertEq(oldBufferLogs.length,    1);
        assertEq(oldWhitelistLogs.length, 2);

        for (uint256 i; i < oldBufferLogs.length; ++i) {
            _assertMigratedOtcExchange(oldController, newController, newLogs, oldBufferLogs[i].topics[1]);
        }

        for (uint256 i = 0; i < oldWhitelistLogs.length; ++i) {
            address exchange = _toAddress(oldWhitelistLogs[i].topics[1]);
            address asset    = _toAddress(oldWhitelistLogs[i].topics[2]);

            assertEq(newController.otcWhitelistedAssets(exchange, asset), oldController.otcWhitelistedAssets(exchange, asset));
            assertEq(newController.otcWhitelistedAssets(exchange, asset), true);
        }
    }

    function _assertMigratedOtcExchange(
        MainnetController   oldController,
        MainnetController   newController,
        VmSafe.Log[] memory newLogs,
        bytes32             exchangeTopic
    ) internal view {
        address exchange = _toAddress(exchangeTopic);

        ( address oldBuffer, uint256 oldRechargeRate18,,, ) = oldController.otcs(exchange);

        {
            ( uint256 count, ) = _findEvents(newLogs, address(newController), MainnetController.OTCBufferSet.selector, exchangeTopic);

            assertEq(count, 1);
        }

        {
            ( uint256 count, bytes memory data ) = _findEvents(newLogs, address(newController), MainnetController.OTCRechargeRateSet.selector, exchangeTopic);

            ( , uint256 emittedRechargeRate18 ) = abi.decode(data, (uint256, uint256));

            assertEq(count,                 1);
            assertEq(emittedRechargeRate18, oldRechargeRate18);
        }

        ( address newBuffer, uint256 newRechargeRate18, uint256 sent18, uint256 sentTimestamp, uint256 claimed18 ) = newController.otcs(exchange);

        assertEq(newBuffer,         oldBuffer);
        assertEq(newRechargeRate18, oldRechargeRate18);

        assertEq(sent18,        0);
        assertEq(sentTimestamp, 0);
        assertEq(claimed18,     0);

        assertEq(newBuffer != address(0), true);
    }

    /**********************************************************************************************/
    /*** Items 2, 3 and 4: Ethereum USDC routes to OP Mainnet, Unichain and Avalanche           ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_closeDeprecatedCctpRoutes() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController oldController = MainnetController(Ethereum.ALM_CONTROLLER);
        MainnetController newController = MainnetController(NEW_ALM_CONTROLLER);

        bytes32 domainKey = oldController.LIMIT_USDC_TO_DOMAIN();

        bytes32 avalancheKey = RateLimitHelpers.makeUint32Key(domainKey, CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);
        bytes32 optimismKey  = RateLimitHelpers.makeUint32Key(domainKey, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        bytes32 unichainKey  = RateLimitHelpers.makeUint32Key(domainKey, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, avalancheKey, 100_000_000e6, uint256(50_000_000e6)  / 1 days);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, optimismKey,  50_000_000e6,  uint256(25_000_000e6)  / 1 days);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, unichainKey,  50_000_000e6,  uint256(25_000_000e6)  / 1 days);

        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, newController.LIMIT_USDC_TO_CCTP());

        // Before the upgrade the mint recipients live on the old controller only; the spell copies them over.
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE), SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),  SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
        assertEq(oldController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),  SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));

        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE), bytes32(0));
        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),  bytes32(0));
        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),  bytes32(0));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, avalancheKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, optimismKey,  0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, unichainKey,  0, 0);

        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, newController.LIMIT_USDC_TO_CCTP());

        // Mint recipients stay set for continuity, but no USDC can be sent to the deprecated domains.
        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE), SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY));
        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),  SLLHelpers.addrToBytes32(Optimism.ALM_PROXY));
        assertEq(newController.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),  SLLHelpers.addrToBytes32(Unichain.ALM_PROXY));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        newController.transferUSDCToCCTP(1, CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        newController.transferUSDCToCCTP(1, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        newController.transferUSDCToCCTP(1, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);
    }

    /**********************************************************************************************/
    /*** Item 2: Deprecate the Spark Liquidity Layer on OP Mainnet                              ***/
    /**********************************************************************************************/

    function test_OPTIMISM_sll_returnExcessLiquidity() external onChain(ChainIdUtils.Optimism()) {
        ForeignController controller = ForeignController(Optimism.ALM_CONTROLLER);
        IPSM3Like         psm3       = IPSM3Like(Optimism.PSM3);

        // The pinned PSM3 amounts follow the SSR oracle at the fork timestamp.
        _warpToForkBlock(ChainIdUtils.Optimism());

        // Prevent the other OP-stack payloads from running so their L2 SentMessage logs don't interfere with the
        // Optimism bridge relay.
        chainData[ChainIdUtils.Unichain()].payload = address(0);

        // Pre-configuration 1: the relayer withdraws the PSM3 position and returns the USDC to Ethereum before the
        // spell. USDS and sUSDS stay in the ALM Proxy for the spell to bridge.
        assertEq(IERC20(Optimism.USDC).balanceOf(Optimism.ALM_PROXY),  0);
        assertEq(IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY),  0);
        assertEq(IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY), 0);

        assertEq(psm3.shares(Optimism.ALM_PROXY), 2_404_434.857373491180842050e18);

        vm.startPrank(Optimism.ALM_RELAYER_MULTISIG);

        controller.withdrawPSM(Optimism.USDC,  type(uint256).max);
        controller.withdrawPSM(Optimism.USDS,  type(uint256).max);
        controller.withdrawPSM(Optimism.SUSDS, type(uint256).max);

        controller.transferUSDCToCCTP(
            IERC20(Optimism.USDC).balanceOf(Optimism.ALM_PROXY),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.stopPrank();

        uint256 optimismUsdsBalanceBefore  = IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY);
        uint256 optimismSusdsBalanceBefore = IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        assertEq(IERC20(Optimism.USDC).balanceOf(Optimism.ALM_PROXY), 0);
        assertEq(optimismUsdsBalanceBefore,                           1.518165e18);
        assertEq(optimismSusdsBalanceBefore,                          1_342_240.2227999340820027e18);

        assertEq(psm3.shares(Optimism.ALM_PROXY),              0);
        assertEq(psm3.convertToAssetValue(psm3.totalShares()), 1.035666343713915981e18);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.Optimism()].domain.selectFork();

        _executeAllPayloadsAndBridges();

        // Optimism ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY),  0);
        assertEq(IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY), 0);

        // Relay L2->L1 OP bridge messages to Ethereum.
        OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.Optimism()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens.

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY),  ethUsdsBalanceBefore  + optimismUsdsBalanceBefore);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY), ethSusdsBalanceBefore + optimismSusdsBalanceBefore);
    }

    function test_OPTIMISM_sll_deprecate() external onChain(ChainIdUtils.Optimism()) {
        IALMProxy         almProxy   = IALMProxy(Optimism.ALM_PROXY);
        ForeignController controller = ForeignController(Optimism.ALM_CONTROLLER);

        bytes32 controllerRole = almProxy.CONTROLLER();

        _assertOpStackRateLimits(Optimism.ALM_RATE_LIMITS, controller, Optimism.USDC, Optimism.USDS, Optimism.SUSDS, false);

        assertEq(almProxy.hasRole(controllerRole, Optimism.SPARK_EXECUTOR), false);
        assertEq(almProxy.hasRole(controllerRole, Optimism.ALM_CONTROLLER), true);

        _assertForeignControllerRoles(controller, Optimism.ALM_RELAYER_MULTISIG, Optimism.ALM_BACKSTOP_RELAYER_MULTISIG, Optimism.ALM_FREEZER_MULTISIG);

        _executeAllPayloadsAndBridges();

        _assertOpStackRateLimits(Optimism.ALM_RATE_LIMITS, controller, Optimism.USDC, Optimism.USDS, Optimism.SUSDS, true);

        assertEq(almProxy.hasRole(controllerRole, Optimism.SPARK_EXECUTOR), false);
        assertEq(almProxy.hasRole(controllerRole, Optimism.ALM_CONTROLLER), true);

        // The relayer, backstop relayer and freezer roles are not changed; with every limit at zero they can move nothing.
        _assertForeignControllerRoles(controller, Optimism.ALM_RELAYER_MULTISIG, Optimism.ALM_BACKSTOP_RELAYER_MULTISIG, Optimism.ALM_FREEZER_MULTISIG);
    }

    /**********************************************************************************************/
    /*** Item 3: Deprecate the Spark Liquidity Layer on Unichain                                ***/
    /**********************************************************************************************/

    function test_UNICHAIN_sll_returnExcessLiquidity() external onChain(ChainIdUtils.Unichain()) {
        ForeignController controller = ForeignController(Unichain.ALM_CONTROLLER);
        IPSM3Like         psm3       = IPSM3Like(Unichain.PSM3);

        // The pinned PSM3 amounts follow the SSR oracle at the fork timestamp.
        _warpToForkBlock(ChainIdUtils.Unichain());

        // Prevent the other OP-stack payloads from running so their L2 SentMessage logs don't interfere with the
        // Unichain bridge relay.
        chainData[ChainIdUtils.Optimism()].payload = address(0);

        // Pre-configuration 1: the relayer withdraws the PSM3 position and returns the USDC to Ethereum before the
        // spell. USDS and sUSDS stay in the ALM Proxy for the spell to bridge.
        assertEq(IERC20(Unichain.USDC).balanceOf(Unichain.ALM_PROXY),  0);
        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY),  0);
        assertEq(IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY), 0);

        assertEq(psm3.shares(Unichain.ALM_PROXY), 110_076.825641224779736448e18);

        vm.startPrank(Unichain.ALM_RELAYER_MULTISIG);

        controller.withdrawPSM(Unichain.USDC,  type(uint256).max);
        controller.withdrawPSM(Unichain.USDS,  type(uint256).max);
        controller.withdrawPSM(Unichain.SUSDS, type(uint256).max);

        controller.transferUSDCToCCTP(
            IERC20(Unichain.USDC).balanceOf(Unichain.ALM_PROXY),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        vm.stopPrank();

        uint256 unichainUsdsBalanceBefore  = IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY);
        uint256 unichainSusdsBalanceBefore = IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY);

        assertEq(IERC20(Unichain.USDC).balanceOf(Unichain.ALM_PROXY), 0);

        assertEq(unichainUsdsBalanceBefore,  0.02e18);
        assertEq(unichainSusdsBalanceBefore, 66_802.321075043559685732e18);

        assertEq(psm3.shares(Unichain.ALM_PROXY),              0);
        assertEq(psm3.convertToAssetValue(psm3.totalShares()), 1.039935169166606327e18);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.Unichain()].domain.selectFork();

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        // Unichain ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY),  0);
        assertEq(IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY), 0);

        // Relay L2->L1 OP bridge messages to Ethereum.
        OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.Unichain()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens.

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY),  ethUsdsBalanceBefore  + unichainUsdsBalanceBefore);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY), ethSusdsBalanceBefore + unichainSusdsBalanceBefore);
    }

    function test_UNICHAIN_sll_deprecate() external onChain(ChainIdUtils.Unichain()) {
        IALMProxy         almProxy   = IALMProxy(Unichain.ALM_PROXY);
        ForeignController controller = ForeignController(Unichain.ALM_CONTROLLER);

        bytes32 controllerRole = almProxy.CONTROLLER();

        _assertOpStackRateLimits(Unichain.ALM_RATE_LIMITS, controller, Unichain.USDC, Unichain.USDS, Unichain.SUSDS, false);

        assertEq(almProxy.hasRole(controllerRole, Unichain.SPARK_EXECUTOR), false);
        assertEq(almProxy.hasRole(controllerRole, Unichain.ALM_CONTROLLER), true);

        _assertForeignControllerRoles(controller, Unichain.ALM_RELAYER_MULTISIG, Unichain.ALM_BACKSTOP_RELAYER_MULTISIG, Unichain.ALM_FREEZER_MULTISIG);

        _executeAllPayloadsAndBridges();

        // Unichain ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY),  0);
        assertEq(IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY), 0);

        _assertOpStackRateLimits(Unichain.ALM_RATE_LIMITS, controller, Unichain.USDC, Unichain.USDS, Unichain.SUSDS, true);

        assertEq(almProxy.hasRole(controllerRole, Unichain.SPARK_EXECUTOR), false);
        assertEq(almProxy.hasRole(controllerRole, Unichain.ALM_CONTROLLER), true);

        // The relayer, backstop relayer and freezer roles are not changed; with every limit at zero they can move nothing.
        _assertForeignControllerRoles(controller, Unichain.ALM_RELAYER_MULTISIG, Unichain.ALM_BACKSTOP_RELAYER_MULTISIG, Unichain.ALM_FREEZER_MULTISIG);
    }

    /**********************************************************************************************/
    /*** Item 4: Deprecate Avalanche                                                            ***/
    /**********************************************************************************************/

    function test_AVALANCHE_sll_deprecate() external onChain(ChainIdUtils.Avalanche()) {
        ForeignController controller = ForeignController(Avalanche.ALM_CONTROLLER);
        IERC20            usdc       = IERC20(Avalanche.USDC);

        bytes32 domainKey   = RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        bytes32 takeKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Avalanche.SPARK_VAULT_V2_SPUSDC);
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), Avalanche.USDC, Avalanche.SPARK_VAULT_V2_SPUSDC);
        bytes32 cctpKey     = controller.LIMIT_USDC_TO_CCTP();

        _assertRateLimit(Avalanche.ALM_RATE_LIMITS, domainKey, 100_000_000e6, uint256(50_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(Avalanche.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(Avalanche.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(Avalanche.ALM_RATE_LIMITS, cctpKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Avalanche.ALM_RATE_LIMITS, domainKey, 0, 0);
        _assertRateLimit(Avalanche.ALM_RATE_LIMITS, takeKey,   0, 0);

        _assertUnlimitedRateLimit(Avalanche.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(Avalanche.ALM_RATE_LIMITS, cctpKey);

        deal(address(usdc), Avalanche.ALM_PROXY, 100e6);

        // No USDC can leave to Ethereum and no USDC can be taken from spUSDC.
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Avalanche.ALM_RELAYER_MULTISIG);
        controller.transferUSDCToCCTP(1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Avalanche.ALM_RELAYER_MULTISIG);
        controller.takeFromSparkVault(Avalanche.SPARK_VAULT_V2_SPUSDC, 1);

        // USDC can still be moved into spUSDC for its holders.
        uint256 vaultBalanceBefore = usdc.balanceOf(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(vaultBalanceBefore,                  443_205.909611e6);
        assertEq(usdc.balanceOf(Avalanche.ALM_PROXY), 100e6);

        vm.prank(Avalanche.ALM_RELAYER_MULTISIG);
        controller.transferAsset(Avalanche.USDC, Avalanche.SPARK_VAULT_V2_SPUSDC, 100e6);

        assertEq(usdc.balanceOf(Avalanche.SPARK_VAULT_V2_SPUSDC), vaultBalanceBefore + 100e6);
        assertEq(usdc.balanceOf(Avalanche.ALM_PROXY),             0);
    }

    function test_AVALANCHE_sparkVaultV2_closeSpUsdc() external onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like spUsdc = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);
        IERC20            usdc   = IERC20(Avalanche.USDC);

        address user = makeAddr("user");

        assertEq(spUsdc.depositCap(), 500_000_000e6);
        assertEq(spUsdc.minVsr(),     1e27);
        assertEq(spUsdc.maxVsr(),     TEN_PCT_APY);
        assertEq(spUsdc.vsr(),        1.000000001182641576793209935e27);

        // The setter fixes the rate at 0%.
        vm.prank(Avalanche.ALM_PROXY_FREEZABLE);
        spUsdc.setVsr(1e27);

        // A holder deposits while deposits are still open.
        deal(address(usdc), user, 1_000e6);

        vm.startPrank(user);
        usdc.approve(address(spUsdc), 1_000e6);
        uint256 shares = spUsdc.deposit(1_000e6, user);
        vm.stopPrank();

        uint256 userAssets = spUsdc.assetsOf(user);

        assertEq(userAssets, 1_000e6 - 1);

        _executeAllPayloadsAndBridges();

        assertEq(spUsdc.depositCap(), 0);
        assertEq(spUsdc.minVsr(),     1e27);
        assertEq(spUsdc.maxVsr(),     1e27);
        assertEq(spUsdc.vsr(),        1e27);

        assertEq(spUsdc.maxDeposit(user), 0);

        // The rate can no longer be raised above 0%.
        vm.expectRevert("SparkVault/vsr-too-high");
        vm.prank(Avalanche.ALM_PROXY_FREEZABLE);
        spUsdc.setVsr(1e27 + 1);

        // Deposits are closed.
        deal(address(usdc), user, 1e6);

        vm.startPrank(user);
        usdc.approve(address(spUsdc), 1e6);
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        spUsdc.deposit(1e6, user);
        vm.stopPrank();

        // At 0% the holder's assets do not grow, and the holder can still redeem in full.
        skip(30 days);

        assertEq(spUsdc.assetsOf(user), userAssets);

        vm.prank(user);
        assertEq(spUsdc.redeem(shares, user, user), userAssets);

        assertEq(spUsdc.balanceOf(user), 0);
        assertEq(usdc.balanceOf(user),   1e6 + userAssets);
    }

    /**********************************************************************************************/
    /*** Item 6: Onboard the Spark-curated Morpho USDC vault to the spUSDC PAU on X-Layer       ***/
    /**********************************************************************************************/

    function test_XLAYER_sll_onboardMorphoVault() external onChain(ChainIdUtils.XLayer()) {
        IControllerLike    controller = IControllerLike(XLayer.SPUSDC_PAU_CONTROLLER);
        IMorphoVaultV2Like vault      = IMorphoVaultV2Like(XLAYER_MORPHO_VAULT_USDC);

        assertEq(IMorphoVaultV2FactoryLike(XLAYER_MORPHO_VAULT_V2_FACTORY).isVaultV2(address(vault)), true);

        assertEq(vault.asset(), XLayer.USDC);
        assertEq(vault.owner(), XLayer.SPARK_EXECUTOR);

        // Same derivation as ERC4626Facet.getDepositRateLimitKey / getWithdrawRateLimitKey.
        bytes32 depositKey  = RateLimitHelpers.makeAddressAddressKey(keccak256("LIMIT_4626_DEPOSIT"), XLayer.USDC, address(vault));
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(keccak256("LIMIT_4626_WITHDRAW"), address(vault));

        assertEq(controller.getDispatch(IControllerLike.erc4626_deposit.selector).facet,            address(0));
        assertEq(controller.getDispatch(IControllerLike.erc4626_withdraw.selector).facet,           address(0));
        assertEq(controller.getDispatch(IControllerLike.erc4626_setMaxExchangeRate.selector).facet, address(0));

        assertEq(controller.getConfig(ERC4626_FACET_ID).facet, address(0));

        _assertRateLimit(XLayer.SPUSDC_PAU_RATELIMITS, depositKey,  0, 0);
        _assertRateLimit(XLayer.SPUSDC_PAU_RATELIMITS, withdrawKey, 0, 0);

        _assertSpUsdcPauCctpRouteUnchanged(controller);

        _executeAllPayloadsAndBridges();

        _assertDispatch(controller, IControllerLike.erc4626_deposit.selector,            "deposit(address,uint256,uint256)");
        _assertDispatch(controller, IControllerLike.erc4626_withdraw.selector,           "withdraw(address,uint256,uint256)");
        _assertDispatch(controller, IControllerLike.erc4626_setMaxExchangeRate.selector, "setMaxExchangeRate(address,uint256,uint256)");

        IControllerLike.Config memory config = controller.getConfig(ERC4626_FACET_ID);

        assertEq(config.facet,        XLayer.ERC4626_FACET);
        assertEq(config.wires.length, 9);

        assertEq(controller.erc4626_getDepositRateLimitKey(address(vault), XLayer.USDC), depositKey);
        assertEq(controller.erc4626_getWithdrawRateLimitKey(address(vault)),             withdrawKey);

        _assertRateLimit(XLayer.SPUSDC_PAU_RATELIMITS, depositKey, 15_000_000e6, uint256(10_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(XLayer.SPUSDC_PAU_RATELIMITS, withdrawKey);

        assertEq(controller.erc4626_getMaxExchangeRate(address(vault)), 3e24);  // 3 USDC (6 decimals) per whole share (18 decimals), 1e36 precision

        _assertSpUsdcPauCctpRouteUnchanged(controller);
    }

    function test_XLAYER_sll_morphoVault_depositAndWithdraw() external onChain(ChainIdUtils.XLayer()) {
        IControllerLike        controller = IControllerLike(XLayer.SPUSDC_PAU_CONTROLLER);
        IAdministeredAgentLike agent      = IAdministeredAgentLike(XLayer.SPUSDC_PAU_ADMINISTERED_AGENT);
        IRateLimits            rateLimits = IRateLimits(XLayer.SPUSDC_PAU_RATELIMITS);
        IMorphoVaultV2Like     vault      = IMorphoVaultV2Like(XLAYER_MORPHO_VAULT_USDC);
        IERC20                 usdc       = IERC20(XLayer.USDC);

        _executeAllPayloadsAndBridges();

        bytes32 depositKey  = controller.erc4626_getDepositRateLimitKey(address(vault), XLayer.USDC);
        bytes32 withdrawKey = controller.erc4626_getWithdrawRateLimitKey(address(vault));

        deal(address(usdc), XLayer.SPUSDC_PAU_ALM_PROXY, 5_000_000e6 + 1);

        uint256 vaultAssetsBefore = vault.totalAssets();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  15_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(vault.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        // The deposit limit is enforced.
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        agent.call(address(controller), abi.encodeCall(controller.erc4626_deposit, (address(vault), 15_000_000e6 + 1, 0)));

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        agent.call(address(controller), abi.encodeCall(controller.erc4626_deposit, (address(vault), 1_000_000e6, 0)));

        uint256 shares = vault.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY);

        assertGt(shares, 0);

        assertApproxEqAbs(vault.convertToAssets(shares), 1_000_000e6, 1);

        assertEq(usdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 4_000_000e6 + 1);
        assertEq(vault.totalAssets(),                         vaultAssetsBefore + 1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  14_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        // The position can be withdrawn without a limit, and the deposit limit is restored.
        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        agent.call(address(controller), abi.encodeCall(controller.erc4626_withdraw, (address(vault), 1_000_000e6, type(uint256).max)));

        assertEq(usdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 5_000_000e6 + 1);
        assertEq(vault.totalAssets(),                         vaultAssetsBefore);

        assertApproxEqAbs(vault.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0, 1e12);  // Rounding dust at most

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  15_000_000e6);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
    }

    /**********************************************************************************************/
    /*** Generic E2E overrides for the deprecated domains                                       ***/
    /**********************************************************************************************/

    function test_AVALANCHE_E2E_sparkLiquidityLayer() external override {
        _runSLLE2ETestsForDeprecatedDomain(ChainIdUtils.Avalanche());
    }

    function test_OPTIMISM_E2E_sparkLiquidityLayer() external override {
        _runSLLE2ETestsForDeprecatedDomain(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_E2E_sparkLiquidityLayer() external override {
        _runSLLE2ETestsForDeprecatedDomain(ChainIdUtils.Unichain());
    }

    function test_E2E_sparkLiquidityLayerCCTPCrossChainSetup() external override {
        _runE2ESLLCrossChainTestForAllDomains({ isPostExecution: false });

        _executeAllPayloadsAndBridges();

        // After the upgrade USDC leaves Ethereum over CCTP V2 and only the live domains can receive it.
        address mainnetController = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum(), true).controller;

        uint256[2] memory liveDomains = [ChainIdUtils.ArbitrumOne(), ChainIdUtils.Base()];

        for (uint256 i = 0; i < liveDomains.length; ++i) {
            uint256 domainChainId = liveDomains[i];

            address domainController = _getSparkLiquidityLayerContext(domainChainId, true).controller;
            address pauController    = _getSLLPAUContext(domainChainId).controller;

            chainData[ChainIdUtils.Ethereum()].domain.selectFork();

            _mintUSDSAndSwapToUSDC(1_000_000e6, mainnetController);

            _bridgeUSDCToDomainV2(1_000_000e6, domainChainId, mainnetController);

            _depositAndWithdrawFromPSM3(1_000_000e6, domainChainId, domainController);

            _bridgeUSDCToMainnet(500_000e6,     domainChainId, domainController);
            _bridgeUSDCToMainnet_pau(500_000e6, domainChainId, pauController);

            _swapUSDCToUSDSAndBurn(1_000_000e6, mainnetController);
        }

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        _assertCctpRouteClosed(mainnetController, CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);
        _assertCctpRouteClosed(mainnetController, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        _assertCctpRouteClosed(mainnetController, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    function _countEvents(VmSafe.Log[] memory logs, address emitter, bytes32 topic0)
        internal pure returns (uint256 count)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == topic0) count++;
        }
    }

    function _assertNewControllerConfig(MainnetController controller, bool migrated) internal view {
        uint256 m = migrated ? 1 : 0;

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),    migrated ? SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY) : bytes32(0));
        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),     migrated ? SLLHelpers.addrToBytes32(Optimism.ALM_PROXY)  : bytes32(0));
        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), migrated ? SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY)  : bytes32(0));
        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE),         migrated ? SLLHelpers.addrToBytes32(Base.ALM_PROXY)      : bytes32(0));
        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),     migrated ? SLLHelpers.addrToBytes32(Unichain.ALM_PROXY)  : bytes32(0));

        // 1e36 precision, assets per share: 10 USDC per 1e18 share is 1e25, 10 of an 18-decimal asset is 1e37.
        assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDC_BC),          m * 1e25);
        assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_DAI_1),            m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_USDS),             m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.SUSDS),                         m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.FLUID_SUSDS),                   m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.SUSDE),                         m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDC),                    m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.SYRUP_USDT),                    m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.ARKIS_VAULT),                   m * 1e37);
        assertEq(controller.maxExchangeRates(Ethereum.MORPHO_VAULT_V2_USDT),          m * 1e30);
        assertEq(controller.maxExchangeRates(MORPHO_VAULT_V2_USDT),                   m * 1e30);
        assertEq(controller.maxExchangeRates(Ethereum.SENTORA_RLUSD_MORPHO_VAULT_V2), m * 3e36);

        assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDC),  m * 0.99999e18);
        assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDE),  m * 0.99999e18);
        assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDS),  m * 0.99999e18);
        assertEq(controller.maxSlippages(Ethereum.ATOKEN_CORE_USDT),  m * 0.99999e18);
        assertEq(controller.maxSlippages(Ethereum.ATOKEN_PRIME_USDS), m * 0.99999e18);

        assertEq(controller.maxSlippages(SparkLend.DAI_SPTOKEN),   m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.USDC_SPTOKEN),  m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.USDS_SPTOKEN),  m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.USDT_SPTOKEN),  m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.PYUSD_SPTOKEN), m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.WETH_SPTOKEN),  m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.USDG_SPTOKEN),  m * 0.99999e18);
        assertEq(controller.maxSlippages(SparkLend.RLUSD_SPTOKEN), m * 0.99999e18);

        assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDC),   m * 0.999e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_USDCUSDT),    m * 0.9985e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_PYUSDUSDS),   m * 0.998e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT),   m * 0.9975e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_WEETHWETHNG), m * 0.9975e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_USDCRLUSD),   m * 0.999e18);

        assertEq(controller.maxSlippages(address(uint160(uint256(PYUSD_USDS_POOL_ID)))), m * 0.999e18);
        assertEq(controller.maxSlippages(address(uint160(uint256(USDT_USDS_POOL_ID)))),  m * 0.998e18);
        assertEq(controller.maxSlippages(address(uint160(uint256(USDS_USDG_POOL_ID)))),  m * 0.999e18);
        assertEq(controller.maxSlippages(address(uint160(uint256(RLUSD_USDS_POOL_ID)))), m * 0.999e18);
        assertEq(controller.maxSlippages(address(uint160(uint256(OUSD_USDS_POOL_ID)))),  m * 0.999e18);

        assertEq(controller.maxSlippages(BINANCE_EXCHANGE), m * 0.998e18);

        if (migrated) {
            _assertUniswapV4TickLimits(controller, PYUSD_USDS_POOL_ID, 276_314,  276_334,  10);
            _assertUniswapV4TickLimits(controller, USDT_USDS_POOL_ID,  276_304,  276_344,  10);
            _assertUniswapV4TickLimits(controller, USDS_USDG_POOL_ID,  -276_334, -276_314, 10);
            _assertUniswapV4TickLimits(controller, RLUSD_USDS_POOL_ID, -10,      10,       10);
            _assertUniswapV4TickLimits(controller, OUSD_USDS_POOL_ID,  276_314,  276_334,  10);
        } else {
            _assertUniswapV4TickLimits(controller, PYUSD_USDS_POOL_ID, 0, 0, 0);
            _assertUniswapV4TickLimits(controller, USDT_USDS_POOL_ID,  0, 0, 0);
            _assertUniswapV4TickLimits(controller, USDS_USDG_POOL_ID,  0, 0, 0);
            _assertUniswapV4TickLimits(controller, RLUSD_USDS_POOL_ID, 0, 0, 0);
            _assertUniswapV4TickLimits(controller, OUSD_USDS_POOL_ID,  0, 0, 0);
        }

        assertEq(controller.layerZeroRecipients(LZ_EID_ARBITRUM), migrated ? SLLHelpers.addrToBytes32(Arbitrum.ALM_PROXY) : bytes32(0));
        assertEq(controller.layerZeroRecipients(LZ_EID_XLAYER),   migrated ? SLLHelpers.addrToBytes32(XLayer.ALM_PROXY)   : bytes32(0));

        ( address otcBuffer, uint256 rechargeRate18, uint256 sent18, uint256 sentTimestamp, uint256 claimed18 )
            = controller.otcs(BINANCE_EXCHANGE);

        assertEq(otcBuffer,      migrated ? Ethereum.BINANCE_OTC_BUFFER : address(0));
        assertEq(rechargeRate18, m * (uint256(50_000e18) / 1 days));
        assertEq(sent18,         0);
        assertEq(sentTimestamp,  0);
        assertEq(claimed18,      0);

        assertEq(controller.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDT), migrated);
        assertEq(controller.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDC), migrated);
    }

    function _assertSameControllerConfig(MainnetController oldController, MainnetController newController) internal view {
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.MORPHO_VAULT_USDC_BC);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.MORPHO_VAULT_DAI_1);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.MORPHO_VAULT_USDS);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.SUSDS);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.FLUID_SUSDS);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.SUSDE);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.SYRUP_USDC);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.SYRUP_USDT);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.ARKIS_VAULT);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.MORPHO_VAULT_V2_USDT);
        _assertSameMaxExchangeRate(oldController, newController, MORPHO_VAULT_V2_USDT);
        _assertSameMaxExchangeRate(oldController, newController, Ethereum.SENTORA_RLUSD_MORPHO_VAULT_V2);

        _assertSameMaxSlippage(oldController, newController, Ethereum.ATOKEN_CORE_USDC);
        _assertSameMaxSlippage(oldController, newController, Ethereum.ATOKEN_CORE_USDE);
        _assertSameMaxSlippage(oldController, newController, Ethereum.ATOKEN_CORE_USDS);
        _assertSameMaxSlippage(oldController, newController, Ethereum.ATOKEN_CORE_USDT);
        _assertSameMaxSlippage(oldController, newController, Ethereum.ATOKEN_PRIME_USDS);

        _assertSameMaxSlippage(oldController, newController, SparkLend.DAI_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.USDC_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.USDS_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.USDT_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.PYUSD_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.WETH_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.USDG_SPTOKEN);
        _assertSameMaxSlippage(oldController, newController, SparkLend.RLUSD_SPTOKEN);

        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_PYUSDUSDC);
        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_USDCUSDT);
        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_PYUSDUSDS);
        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_SUSDSUSDT);
        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_WEETHWETHNG);
        _assertSameMaxSlippage(oldController, newController, Ethereum.CURVE_USDCRLUSD);

        _assertSameMaxSlippage(oldController, newController, address(uint160(uint256(PYUSD_USDS_POOL_ID))));
        _assertSameMaxSlippage(oldController, newController, address(uint160(uint256(USDT_USDS_POOL_ID))));
        _assertSameMaxSlippage(oldController, newController, address(uint160(uint256(USDS_USDG_POOL_ID))));
        _assertSameMaxSlippage(oldController, newController, address(uint160(uint256(RLUSD_USDS_POOL_ID))));
        _assertSameMaxSlippage(oldController, newController, address(uint160(uint256(OUSD_USDS_POOL_ID))));

        _assertSameMaxSlippage(oldController, newController, BINANCE_EXCHANGE);

        _assertSameUniswapV4TickLimits(oldController, newController, PYUSD_USDS_POOL_ID);
        _assertSameUniswapV4TickLimits(oldController, newController, USDT_USDS_POOL_ID);
        _assertSameUniswapV4TickLimits(oldController, newController, USDS_USDG_POOL_ID);
        _assertSameUniswapV4TickLimits(oldController, newController, RLUSD_USDS_POOL_ID);
        _assertSameUniswapV4TickLimits(oldController, newController, OUSD_USDS_POOL_ID);

        assertEq(newController.layerZeroRecipients(LZ_EID_ARBITRUM), oldController.layerZeroRecipients(LZ_EID_ARBITRUM));
        assertEq(newController.layerZeroRecipients(LZ_EID_XLAYER),   oldController.layerZeroRecipients(LZ_EID_XLAYER));

        ( address oldBuffer, uint256 oldRechargeRate18,,, ) = oldController.otcs(BINANCE_EXCHANGE);
        ( address newBuffer, uint256 newRechargeRate18,,, ) = newController.otcs(BINANCE_EXCHANGE);

        assertEq(newBuffer,         oldBuffer);
        assertEq(newRechargeRate18, oldRechargeRate18);

        assertEq(newController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDT), oldController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDT));
        assertEq(newController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDC), oldController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDC));
    }

    function _assertSameMaxExchangeRate(MainnetController oldController, MainnetController newController, address vault) internal view {
        assertEq(newController.maxExchangeRates(vault), oldController.maxExchangeRates(vault));
    }

    function _assertSameMaxSlippage(MainnetController oldController, MainnetController newController, address pool) internal view {
        assertEq(newController.maxSlippages(pool), oldController.maxSlippages(pool));
    }

    function _assertSameUniswapV4TickLimits(MainnetController oldController, MainnetController newController, bytes32 poolId) internal view {
        ( int24 oldTickLower, int24 oldTickUpper, uint24 oldMaxTickSpacing ) = oldController.uniswapV4TickLimits(poolId);

        _assertUniswapV4TickLimits(newController, poolId, oldTickLower, oldTickUpper, oldMaxTickSpacing);
    }

    function _assertUniswapV4TickLimits(
        MainnetController controller,
        bytes32           poolId,
        int24             expectedTickLower,
        int24             expectedTickUpper,
        uint24            expectedMaxTickSpacing
    ) internal view {
        ( int24 tickLower, int24 tickUpper, uint24 maxTickSpacing ) = controller.uniswapV4TickLimits(poolId);

        assertEq(tickLower,      expectedTickLower);
        assertEq(tickUpper,      expectedTickUpper);
        assertEq(maxTickSpacing, expectedMaxTickSpacing);
    }

    function _assertOpStackRateLimits(
        address           rateLimits,
        ForeignController controller,
        address           usdc,
        address           usds,
        address           susds,
        bool              deprecated
    ) internal view {
        bytes32 psmDepositKey  = controller.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey = controller.LIMIT_PSM_WITHDRAW();

        bytes32 cctpKey   = controller.LIMIT_USDC_TO_CCTP();
        bytes32 domainKey = RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        if (deprecated) {
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  usdc),  0, 0);
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  usds),  0, 0);
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  susds), 0, 0);
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, usdc),  0, 0);
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, usds),  0, 0);
            _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, susds), 0, 0);

            _assertRateLimit(rateLimits, cctpKey,   0, 0);
            _assertRateLimit(rateLimits, domainKey, 0, 0);

            return;
        }

        _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  usdc), 50_000_000e6, uint256(50_000_000e6) / 1 days);
        _assertRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, usdc), 50_000_000e6, uint256(50_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  usds));
        _assertUnlimitedRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmDepositKey,  susds));
        _assertUnlimitedRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, usds));
        _assertUnlimitedRateLimit(rateLimits, RateLimitHelpers.makeAddressKey(psmWithdrawKey, susds));

        _assertUnlimitedRateLimit(rateLimits, cctpKey);

        _assertRateLimit(rateLimits, domainKey, 50_000_000e6, uint256(25_000_000e6) / 1 days);
    }

    function _assertDispatch(IControllerLike controller, bytes4 callSelector, string memory facetSignature) internal view {
        IControllerLike.Dispatch memory dispatch = controller.getDispatch(callSelector);

        assertEq(dispatch.facet,            XLayer.ERC4626_FACET);
        assertEq(dispatch.delegateSelector, bytes4(keccak256(bytes(facetSignature))));
    }

    function _assertForeignControllerRoles(
        ForeignController controller,
        address           relayer,
        address           backstopRelayer,
        address           freezer
    ) internal view {
        assertEq(controller.hasRole(controller.RELAYER(), relayer),         true);
        assertEq(controller.hasRole(controller.RELAYER(), backstopRelayer), true);
        assertEq(controller.hasRole(controller.FREEZER(), freezer),         true);
    }

    function _assertSpUsdcPauCctpRouteUnchanged(IControllerLike controller) internal view {
        ( bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate )
            = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     SLLHelpers.addrToBytes32(Ethereum.SPUSDC_PAU_ALM_PROXY));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _assertRateLimit(
            XLayer.SPUSDC_PAU_RATELIMITS,
            controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            10_000_000e6,
            uint256(250_000_000e6) / 1 days
        );
    }

    function _assertCctpRouteClosed(address controller, uint32 domain) internal {
        IRateLimits rateLimits = MainnetController(controller).rateLimits();

        assertEq(
            rateLimits.getCurrentRateLimit(RateLimitHelpers.makeUint32Key(MainnetController(controller).LIMIT_USDC_TO_DOMAIN(), domain)),
            0
        );

        deal(Ethereum.USDC, Ethereum.ALM_PROXY, 1);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        MainnetController(controller).transferUSDCToCCTP(1, domain);
    }

    // Same as _bridgeUSDCToDomain, relayed over the CCTP V2 bridge that MainnetController v1.11.0 sends on.
    function _bridgeUSDCToDomainV2(uint256 usdcAmount, uint256 domainId, address controller) internal {
        ( IERC20 domainUsdc, uint32 domainCctpId, uint256 bridgeIndex ) = _getCctpV2DomainParams(domainId);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        _syncMainnetTimestamp();

        _transferUSDCToCCTPV2(usdcAmount, domainCctpId, controller);

        chainData[domainId].domain.selectFork();

        address domainAlmProxy = address(_getSparkLiquidityLayerContext().proxy);

        uint256 domainUsdcProxyBalance = domainUsdc.balanceOf(domainAlmProxy);

        CCTPV2BridgeTesting.relayMessagesToDestination(chainData[domainId].bridges[bridgeIndex], true);

        assertEq(domainUsdc.balanceOf(domainAlmProxy), domainUsdcProxyBalance + usdcAmount);
    }

    function _getCctpV2DomainParams(uint256 domainId)
        internal pure returns (IERC20 domainUsdc, uint32 domainCctpId, uint256 bridgeIndex)
    {
        if (domainId == ChainIdUtils.ArbitrumOne()) {
            return ( IERC20(Arbitrum.USDC), CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE, 3 );
        }

        if (domainId == ChainIdUtils.Base()) {
            return ( IERC20(Base.USDC), CCTPForwarder.DOMAIN_ID_CIRCLE_BASE, 2 );
        }

        revert("SLL/unknown domain");
    }

    function _transferUSDCToCCTPV2(uint256 usdcAmount, uint32 domainCctpId, address controller) internal {
        IERC20      usdc       = IERC20(Ethereum.USDC);
        IRateLimits rateLimits = MainnetController(controller).rateLimits();

        bytes32 cctpKey   = MainnetController(controller).LIMIT_USDC_TO_CCTP();
        bytes32 domainKey = RateLimitHelpers.makeUint32Key(MainnetController(controller).LIMIT_USDC_TO_DOMAIN(), domainCctpId);

        uint256 cctpLimit   = rateLimits.getCurrentRateLimit(cctpKey);
        uint256 domainLimit = rateLimits.getCurrentRateLimit(domainKey);

        uint256 mainnetUsdcProxyBalance = usdc.balanceOf(Ethereum.ALM_PROXY);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        MainnetController(controller).transferUSDCToCCTP(usdcAmount, domainCctpId);

        assertEq(usdc.balanceOf(Ethereum.ALM_PROXY), mainnetUsdcProxyBalance - usdcAmount);

        assertEq(
            rateLimits.getCurrentRateLimit(cctpKey),
            cctpLimit != type(uint256).max ? cctpLimit - usdcAmount : type(uint256).max
        );
        assertEq(
            rateLimits.getCurrentRateLimit(domainKey),
            domainLimit != type(uint256).max ? domainLimit - usdcAmount : type(uint256).max
        );
    }

    function _runSLLE2ETestsForDeprecatedDomain(uint256 chainId) internal onChain(chainId) {
        // Pre-execution: the generic coverage is unchanged.
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext({ isPostExecution: false });

        bytes32[]        memory rateLimitKeys = _getRateLimitKeys({ isPostExecution: false });
        SLLIntegration[] memory integrations  = _getPreExecutionIntegrations();

        for (uint256 i = 0; i < integrations.length; ++i) {
            rateLimitKeys = _removeAll(rateLimitKeys, _runSLLE2ETests(ctx, integrations[i]));
        }

        assertEq(rateLimitKeys.length, 0, "Rate limit keys not fully covered");

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        chainData[chainId].domain.selectFork();

        // Post-execution: every zeroed key left the catalog, every rate-limited action reverts, and the keys that
        // stay live are the only ones left.
        rateLimitKeys = _getRateLimitKeys({ isPostExecution: true });
        ctx           = _getSparkLiquidityLayerContext({ isPostExecution: true });

        for (uint256 i = 0; i < integrations.length; ++i) {
            rateLimitKeys = _removeAll(rateLimitKeys, _assertDeprecatedIntegration(ctx, integrations[i]));
        }

        assertEq(rateLimitKeys.length, 0, "Rate limit keys not fully covered");
    }

    function _assertDeprecatedIntegration(
        SparkLiquidityLayerContext memory ctx,
        SLLIntegration             memory integration
    )
        internal returns (bytes32[] memory liveKeys)
    {
        ForeignController controller = ForeignController(ctx.controller);

        address rateLimits = address(ctx.rateLimits);

        if (integration.category == Category.PSM3) {
            address asset = abi.decode(integration.extraData, (address));

            _assertRateLimit(rateLimits, integration.entryId, 0, 0);
            _assertRateLimit(rateLimits, integration.exitId,  0, 0);

            vm.expectRevert("RateLimits/zero-maxAmount");
            vm.prank(ctx.relayer);
            controller.depositPSM(asset, 1);

            vm.expectRevert("RateLimits/zero-maxAmount");
            vm.prank(ctx.relayer);
            controller.withdrawPSM(asset, 1);

            return liveKeys;
        }

        if (integration.category == Category.CCTP) {
            _assertRateLimit(rateLimits, integration.entryId, 0, 0);

            vm.expectRevert("RateLimits/zero-maxAmount");
            vm.prank(ctx.relayer);
            controller.transferUSDCToCCTP(1, abi.decode(integration.extraData, (uint32)));

            return liveKeys;
        }

        if (integration.category == Category.CCTP_GENERAL) {
            if (block.chainid != ChainIdUtils.Avalanche()) {
                _assertRateLimit(rateLimits, integration.entryId, 0, 0);

                return liveKeys;
            }

            // Stays unlimited on Avalanche: every per-domain key is zero.
            _assertUnlimitedRateLimit(rateLimits, integration.entryId);

            liveKeys    = new bytes32[](1);
            liveKeys[0] = integration.entryId;

            return liveKeys;
        }

        if (integration.category == Category.SPARK_VAULT_V2) {
            ISparkVaultV2Like vault = ISparkVaultV2Like(integration.integration);

            _assertRateLimit(rateLimits, integration.entryId, 0, 0);

            _assertUnlimitedRateLimit(rateLimits, integration.exitId);

            vm.expectRevert("RateLimits/zero-maxAmount");
            vm.prank(ctx.relayer);
            controller.takeFromSparkVault(integration.integration, 1);

            // USDC can still be transferred into the vault for its holders.
            return _testTransferAssetIntegration(TransferAssetE2ETestParams({
                ctx:            ctx,
                asset:          vault.asset(),
                destination:    integration.integration,
                transferKey:    integration.exitId,
                transferAmount: 100_000e6
            }));
        }

        revert("Unexpected integration on a deprecated domain");
    }

    function _findEvents(
        VmSafe.Log[] memory logs,
        address             emitter,
        bytes32             topic0,
        bytes32             topic1
    )
        internal pure returns (uint256 count, bytes memory data)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != emitter)   continue;
            if (logs[i].topics[0] != topic0)  continue;
            if (logs[i].topics[1] != topic1)  continue;

            count++;
            data = logs[i].data;
        }
    }

    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

}

contract SparkEthereum_20261119_SparklendTests is SparklendTests, Spell_20261119_Common {

    constructor() {
        _spellId   = 20261119;
        _blockDate = 1794235200;  // Nov-09-2026 02:40:00 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        _deployStandIns(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.XLayer()].domain);

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = NEW_ALM_CONTROLLER;
    }

}

contract SparkEthereum_20261119_SpellTests is SpellTests, Spell_20261119_Common {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    constructor() {
        _spellId   = 20261119;
        _blockDate = 1794235200;  // Nov-09-2026 02:40:00 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        _deployStandIns(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.XLayer()].domain);

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = NEW_ALM_CONTROLLER;
    }

    /**********************************************************************************************/
    /*** Item 7: December 2026 grants                                                           ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkTreasury() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      48_995_094.205806286854722044e18);
        assertEq(foundationBalanceBefore,      3_797_220.8122e18);
        assertEq(assetFoundationBalanceBefore, 245_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - SPARK_FOUNDATION_GRANT_AMOUNT - SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + SPARK_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
