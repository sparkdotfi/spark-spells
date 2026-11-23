// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Vm }            from "forge-std/Vm.sol";
import { console2 }      from "forge-std/console2.sol";

import { IERC20 }                   from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 }                 from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IAccessControlEnumerable } from "openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { OptionsBuilder } from "lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { BeaconConfig } from "diamond-pau/src/libraries/BeaconConfig.sol";

import { IController }             from "diamond-pau/src/interfaces/IController.sol";
import { IEnumerableIntegrations } from "diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { IERC4626Controller }       from "diamond-pau/src/facets/erc4626/IERC4626Controller.sol";
import { ILayerZeroController }     from "diamond-pau/src/facets/layer-zero/ILayerZeroController.sol";
import { ILayerZeroFacet }          from "diamond-pau/src/facets/layer-zero/ILayerZeroFacet.sol";
import { ISparkVaultController }    from "diamond-pau/src/facets/spark-vault/ISparkVaultController.sol";
import { ISwapAssetController }     from "diamond-pau/src/facets/swap-asset/ISwapAssetController.sol";
import { ISwapAssetFacet }          from "diamond-pau/src/facets/swap-asset/ISwapAssetFacet.sol";
import { ITransferAssetController } from "diamond-pau/src/facets/transfer-asset/ITransferAssetController.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { EthereumSparkSpUSDTPayload } from "spark-deployments/deployments/20261116-mainnet-spark-spusdt/EthereumSparkSpUSDTPayload.sol";
import { ArbitrumSparkSpUSDTPayload } from "spark-deployments/deployments/20261117-arbitrum-spark-spUSDT/ArbitrumSparkSpUSDTPayload.sol";

import { IALMProxy }                           from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }                         from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ILayerZero, MessagingFee, SendParam } from "spark-alm-controller/src/interfaces/ILayerZero.sol";
import { ForeignController }                   from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController }                   from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }                    from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { LZForwarder }   from "xchain-helpers/forwarders/LZForwarder.sol";

import { Bridge, BridgeType }    from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { LZBridgeTesting }       from "xchain-helpers/testing/bridges/LZBridgeTesting.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function call(address target, bytes memory data) external payable returns (bytes memory result);

    function getIsActor(address account) external view returns (bool);

    function getIsAdmin(address account) external view returns (bool);

    function getIsGrantor(address account) external view returns (bool);

    function getIsRevoker(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

interface ICCTPControllerLike {

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain) external view returns (bytes32);

    function cctp_toCCTPRateLimitKey() external view returns (bytes32);

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate) external;

}

interface ILZEndpointLike {

    function lazyInboundNonce(address receiver, uint32 srcEid, bytes32 sender) external view returns (uint64);

    function outboundNonce(address sender, uint32 dstEid, bytes32 receiver) external view returns (uint64);

}

interface IOFTLike {

    function peers(uint32 eid) external view returns (bytes32 peer);

}

interface IPAUFactoryLike {

    function beacon() external view returns (address);

}

interface ISparkVaultLike is ISparkVaultV2Like {

    function assetsOutstanding() external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

}

// No return value on approve, so it also works with USDT.
interface IUSDTLike {

    function approve(address spender, uint256 amount) external;

}

interface IArbSpUsdtPauControllerLike is
    IController,
    ILayerZeroController,
    ISparkVaultController,
    ITransferAssetController
{}

interface IEthSpUsdtPauControllerLike is
    IController,
    IERC4626Controller,
    ILayerZeroController,
    ISparkVaultController,
    ISwapAssetController,
    ITransferAssetController
{}

interface ISllPauControllerLike is IController, ISwapAssetController {}

abstract contract SpUsdtDeployments is StdAssertions {

    using DomainHelpers for Domain;

    Vm private constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant SKY_BEACON = 0x829dC2b7E94B1954F0764E573f2E0d45Afa28199;

    // Deployment payloads, at the CREATE2 addresses of their Deploy scripts in spark-deployments.
    address internal constant ETHEREUM_SPUSDT_DEPLOYMENT_PAYLOAD = 0x29f66f804F614938c6647BC01C450ef00cC86947;
    address internal constant ARBITRUM_SPUSDT_DEPLOYMENT_PAYLOAD = 0x2C779C7cDD7Bfe6FA363E7ABB5608d23Bc989F1A;

    // Created by EthereumSparkSpUSDTPayload.
    address internal constant ETHEREUM_PLANNER_ADMINISTERED_AGENT = 0x4E9e590e692071304655Dd09007a27fFd6Af672E;
    address internal constant ETHEREUM_SPARK_ADMINISTERED_AGENT   = 0xfE4b2fD27e8232a79485ba8bA8DBFcD9A88f0738;
    address internal constant ETHEREUM_SLL_ADMINISTERED_AGENT     = 0xCFaFEd200FEb635EAeB29c3b7aBCA23aAEf8eB73;

    address internal constant ETHEREUM_SLL_PAU_ACCESS_CONTROLS = 0x39D82b1677a07dfF9eBFA1a448CA1F58982ee253;
    address internal constant ETHEREUM_SLL_PAU_CONTROLLER      = 0x650044537F5d4aab322796426939214096c9445f;
    address internal constant ETHEREUM_SLL_PAU_RATE_LIMITS     = 0xe6eba74b76bb5a00a4bB5285B47F8803daE9cd05;

    address internal constant ETHEREUM_SPUSDT_PAU_ACCESS_CONTROLS = 0x22297Ab738a5F9b3c0B71b1d1e57C235174A2Fa8;
    address internal constant ETHEREUM_SPUSDT_PAU_ALM_PROXY       = 0x2ceF3e65858EE6706FAd66550876412d08342BC8;
    address internal constant ETHEREUM_SPUSDT_PAU_CONTROLLER      = 0xBaA8B6E49a8d0B6D2E8D0F57c0CA9647ce28C236;
    address internal constant ETHEREUM_SPUSDT_PAU_RATE_LIMITS     = 0x960E0E329f2E0AECe5A2e830FFdbD380f2E472Dc;

    // Created by ArbitrumSparkSpUSDTPayload.
    address internal constant ARBITRUM_PLANNER_ADMINISTERED_AGENT = 0xE596c23866EB32C9fb363BC98D5624338BdBB93B;
    address internal constant ARBITRUM_SPARK_ADMINISTERED_AGENT   = 0x5aAFd16909280c551128b5246D039005D38dE6Bb;

    address internal constant ARBITRUM_SPUSDT_PAU_ACCESS_CONTROLS = 0xc77e2989fb75FE03311D12A67AD7d657FD1A7be1;
    address internal constant ARBITRUM_SPUSDT_PAU_ALM_PROXY       = 0xf30dAD25A887a99D01606F117610072F2050ccAD;
    address internal constant ARBITRUM_SPUSDT_PAU_CONTROLLER      = 0xa9B9C17ef1b86438B29FF2A85327d6f9bC19cAB2;
    address internal constant ARBITRUM_SPUSDT_PAU_RATE_LIMITS     = 0xFded8cD8DF316593B5c3e1e216E89F7F8cdCa0e8;

    function _runPreDeploymentPayloads(Domain memory ethereum, Domain memory arbitrum) internal {
        // Ethereum: spUSDT PAU, Spark Liquidity Layer PAU and Administered Agents.

        ethereum.selectFork();

        _deployAt(type(EthereumSparkSpUSDTPayload).creationCode, ETHEREUM_SPUSDT_DEPLOYMENT_PAYLOAD);

        EthereumSparkSpUSDTPayload.Report memory ethReport = EthereumSparkSpUSDTPayload(ETHEREUM_SPUSDT_DEPLOYMENT_PAYLOAD).report();

        assertEq(ethReport.plannerAgent,             ETHEREUM_PLANNER_ADMINISTERED_AGENT);
        assertEq(ethReport.sparkAgent,               ETHEREUM_SPARK_ADMINISTERED_AGENT);
        assertEq(ethReport.sllAgent,                 ETHEREUM_SLL_ADMINISTERED_AGENT);
        assertEq(ethReport.sllPAU_accessControls,    ETHEREUM_SLL_PAU_ACCESS_CONTROLS);
        assertEq(ethReport.sllPAU_controller,        ETHEREUM_SLL_PAU_CONTROLLER);
        assertEq(ethReport.sllPAU_rateLimits,        ETHEREUM_SLL_PAU_RATE_LIMITS);
        assertEq(ethReport.spUSDTPAU_accessControls, ETHEREUM_SPUSDT_PAU_ACCESS_CONTROLS);
        assertEq(ethReport.spUSDTPAU_almProxy,       ETHEREUM_SPUSDT_PAU_ALM_PROXY);
        assertEq(ethReport.spUSDTPAU_controller,     ETHEREUM_SPUSDT_PAU_CONTROLLER);
        assertEq(ethReport.spUSDTPAU_rateLimits,     ETHEREUM_SPUSDT_PAU_RATE_LIMITS);

        // Pre-requirement 9: the Sky Core spell registers SwapAssetFacet on the Sky Beacon before the Spark payload.
        _vm.prank(Ethereum.PAUSE_PROXY);
        BeaconConfig.setSwapAssetIntegration(SKY_BEACON, Ethereum.SWAP_ASSET_FACET);

        // Arbitrum: spUSDT PAU and Administered Agents, on the Spark Beacon of the already executed Beacon payload.

        arbitrum.selectFork();

        assertEq(IPAUFactoryLike(Arbitrum.SPARK_PAU_FACTORY).beacon(), Arbitrum.SPARK_BEACON);

        _deployAt(type(ArbitrumSparkSpUSDTPayload).creationCode, ARBITRUM_SPUSDT_DEPLOYMENT_PAYLOAD);

        ArbitrumSparkSpUSDTPayload.Report memory arbReport = ArbitrumSparkSpUSDTPayload(ARBITRUM_SPUSDT_DEPLOYMENT_PAYLOAD).report();

        assertEq(arbReport.plannerAgent,             ARBITRUM_PLANNER_ADMINISTERED_AGENT);
        assertEq(arbReport.sparkAgent,               ARBITRUM_SPARK_ADMINISTERED_AGENT);
        assertEq(arbReport.spUSDTPAU_accessControls, ARBITRUM_SPUSDT_PAU_ACCESS_CONTROLS);
        assertEq(arbReport.spUSDTPAU_almProxy,       ARBITRUM_SPUSDT_PAU_ALM_PROXY);
        assertEq(arbReport.spUSDTPAU_controller,     ARBITRUM_SPUSDT_PAU_CONTROLLER);
        assertEq(arbReport.spUSDTPAU_rateLimits,     ARBITRUM_SPUSDT_PAU_RATE_LIMITS);

        ethereum.selectFork();
    }

    function _deployAt(bytes memory creationCode, address payload) internal {
        assertEq(payload.code.length, 0, "SpUsdtDeployments/payload-already-deployed");

        _vm.etch(payload, creationCode);

        ( bool success, bytes memory runtimeCode ) = payload.call("");

        assertTrue(success, "SpUsdtDeployments/payload-deployment-failed");

        _vm.etch(payload, runtimeCode);
    }

}

contract SparkEthereum_20261203_SLLTests is SparkLiquidityLayerTests, SpUsdtDeployments {

    using DomainHelpers  for Domain;
    using OptionsBuilder for bytes;

    struct PauLayerZeroTransferParams {
        address plannerAgent;
        address agent;
        address controller;
        address oft;
        address asset;
        uint256 amount;
        uint32  destinationEndpointId;
        uint256 destinationChainId;
        address destinationOft;
        address destinationAsset;
        address destinationReceiver;
        uint32  sourceEndpointId;
        uint256 sourceChainId;
        bytes32 transferKey;
    }

    // X Layer -> Ethereum LayerZero bridge for Item 3 (the harness only wires Ethereum -> X Layer).
    Bridge internal xlayerToEthereumLZBridge;

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        _runPreDeploymentPayloads(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.ArbitrumOne()].domain);

        xlayerToEthereumLZBridge = LZBridgeTesting.init(Bridge({
            bridgeType:                     BridgeType.LZ,
            source:                         chainData[ChainIdUtils.XLayer()].domain,
            destination:                    chainData[ChainIdUtils.Ethereum()].domain,
            sourceCrossChainMessenger:      LZ_ENDPOINT_XLAYER,
            destinationCrossChainMessenger: LZForwarder.ENDPOINT_ETHEREUM,
            lastSourceLogIndex:             0,
            lastDestinationLogIndex:        0,
            extraData:                      abi.encode(LZ_RECEIVE_LIBRARY_XLAYER, LZForwarder.RECEIVE_LIBRARY_ETHEREUM)
        }));

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    /**********************************************************************************************/
    /*** Ethereum                                                                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertSpUsdtPauDeploymentConfig();

        _executeAllPayloadsAndBridges();

        _assertSpUsdtPauDeploymentConfig();
    }

    function test_ETHEREUM_sllPau_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertSllPauDeploymentConfig();

        _executeAllPayloadsAndBridges();

        _assertSllPauDeploymentConfig();
    }

    function test_ETHEREUM_administeredAgents_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertEthereumAgents();

        _executeAllPayloadsAndBridges();

        _assertEthereumAgents();
    }

    function test_ETHEREUM_sparkBeacon_onboardSwapAssetAndLayerZero() external onChain(ChainIdUtils.Ethereum()) {
        IEnumerableIntegrations beacon = IEnumerableIntegrations(Ethereum.SPARK_BEACON);

        assertEq(beacon.integrations().length, 4);

        assertEq(beacon.getConfig(BeaconConfig.CCTP_INTEGRATION).facet,           Ethereum.CCTP_FACET);
        assertEq(beacon.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(beacon.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(beacon.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(beacon.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     address(0));
        assertEq(beacon.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     address(0));

        _assertOnlyRoleMember(Ethereum.SPARK_BEACON, DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        assertEq(beacon.integrations().length, 6);

        assertEq(beacon.getConfig(BeaconConfig.CCTP_INTEGRATION).facet,           Ethereum.CCTP_FACET);
        assertEq(beacon.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(beacon.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(beacon.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(beacon.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     Ethereum.SWAP_ASSET_FACET);
        assertEq(beacon.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     Ethereum.LAYERZERO_FACET);

        _assertIntegration(Ethereum.SPARK_BEACON, BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
        _assertIntegration(Ethereum.SPARK_BEACON, BeaconConfig.buildLayerZeroIntegration(Ethereum.LAYERZERO_FACET));

        _assertOnlyRoleMember(Ethereum.SPARK_BEACON, DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
    }

    function test_ETHEREUM_spUsdtPau_onboardLayerZeroAndSwapAsset() external onChain(ChainIdUtils.Ethereum()) {
        IController controller = IController(ETHEREUM_SPUSDT_PAU_CONTROLLER);

        assertEq(controller.integrations().length, 3); // From Deployment Payload

        assertEq(controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(controller.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     address(0));
        assertEq(controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     address(0));

        _executeAllPayloadsAndBridges();

        assertEq(controller.integrations().length, 5);

        assertEq(controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(controller.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     Ethereum.LAYERZERO_FACET);
        assertEq(controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     Ethereum.SWAP_ASSET_FACET);

        _assertIntegrationEnabled(ETHEREUM_SPUSDT_PAU_CONTROLLER, BeaconConfig.buildLayerZeroIntegration(Ethereum.LAYERZERO_FACET));
        _assertIntegrationEnabled(ETHEREUM_SPUSDT_PAU_CONTROLLER, BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
    }

    function test_ETHEREUM_spUsdt_takerAndSetterRoles() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          Ethereum.ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         Ethereum.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          ETHEREUM_SPUSDT_PAU_ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         ETHEREUM_SPARK_ADMINISTERED_AGENT);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        // Taker can take from the vault

        uint256 vaultBalance = usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT);
        uint256 pauBalance   = usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY);

        assertEq(vaultBalance, 50_599_360.713104e6);
        assertEq(pauBalance,   0);

        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(ISparkVaultController.sparkVault_take, (Ethereum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY),  pauBalance   + 1_000_000e6);

        // Setter can set the vsr

        uint256 maxVsr = spUsdt.maxVsr();

        vm.expectRevert("SparkVault/vsr-out-of-bounds");
        vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
        spUsdt.setVsr(maxVsr);

        assertEq(spUsdt.vsr(), 999);

        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            Ethereum.SPARK_VAULT_V2_SPUSDT,
            abi.encodeCall(ISparkVaultV2Like.setVsr, (maxVsr)),
            0
        );

        assertEq(spUsdt.vsr(), maxVsr);
    }

    function test_ETHEREUM_spUsdtPau_layerZeroRecipients() external onChain(ChainIdUtils.Ethereum()) {
        ILayerZeroController controller = ILayerZeroController(ETHEREUM_SPUSDT_PAU_CONTROLLER);

        // The LayerZero integration is not enabled before the spell (CallSelectorNotWired).
        vm.expectRevert();
        controller.layerZero_getRecipient(LZ_EID_ARBITRUM);

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZero_getRecipient(LZ_EID_ARBITRUM), _toBytes32(ARBITRUM_SPUSDT_PAU_ALM_PROXY));
        assertEq(controller.layerZero_getRecipient(LZ_EID_XLAYER),   _toBytes32(XLayer.ALM_PROXY));
        assertEq(controller.layerZero_getRecipient(LZ_EID_ETHEREUM), bytes32(0));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToArbitrum() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            agent:                 ETHEREUM_SPARK_ADMINISTERED_AGENT,
            controller:            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            oft:                   Ethereum.USDT_OFT,
            asset:                 Ethereum.USDT,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_ARBITRUM,
            destinationChainId:    ChainIdUtils.ArbitrumOne(),
            destinationOft:        USDT0_OFT_ARBITRUM,
            destinationAsset:      USDT0_ARBITRUM,
            destinationReceiver:   ARBITRUM_SPUSDT_PAU_ALM_PROXY,
            sourceEndpointId:      LZ_EID_ETHEREUM,
            sourceChainId:         ChainIdUtils.Ethereum(),
            transferKey:           _spUsdtLayerZeroKey(LZ_EID_ARBITRUM)
        }));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToXLayer() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            agent:                 ETHEREUM_SPARK_ADMINISTERED_AGENT,
            controller:            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            oft:                   Ethereum.USDT_OFT,
            asset:                 Ethereum.USDT,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_XLAYER,
            destinationChainId:    ChainIdUtils.XLayer(),
            destinationOft:        USDT0_OFT_XLAYER,
            destinationAsset:      USDT0_XLAYER,
            destinationReceiver:   XLayer.ALM_PROXY,
            sourceEndpointId:      LZ_EID_ETHEREUM,
            sourceChainId:         ChainIdUtils.Ethereum(),
            transferKey:           _spUsdtLayerZeroKey(LZ_EID_XLAYER)
        }));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroRateLimitEnforced() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        deal(Ethereum.USDT, ETHEREUM_SPUSDT_PAU_ALM_PROXY, 5_000_000e6 + 1);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = ILayerZeroController(ETHEREUM_SPUSDT_PAU_CONTROLLER)
            .layerZero_quoteTransfer(Ethereum.USDT_OFT, 5_000_000e6 + 1, LZ_EID_ARBITRUM);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(ILayerZeroController.layerZero_transfer, (Ethereum.USDT_OFT, 5_000_000e6 + 1, LZ_EID_ARBITRUM)),
            fee.nativeFee
        );
    }

    function test_ETHEREUM_sll_spUsdtRateLimitsZeroed() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 takeKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Ethereum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT);
        bytes32 arbitrumKey = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_ARBITRUM));
        bytes32 xlayerKey   = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_XLAYER));

        assertEq(takeKey,     0x0335f36b87501deed8fd62dd9d0a4b0c149568bf2a7e3dc2ffb0920a60d5ba46);
        assertEq(transferKey, 0xe3efee79202351ad64bb73712079e37726f09bcdd2010725adb10a4b569deb93);
        assertEq(arbitrumKey, 0xba173d875b495d25b0833f1755e783ed5a84785695937e499f2f53ec1e3e1937);
        assertEq(xlayerKey,   0x6772b00614d0e1404832a92273072240560c99d697675853061745ca6a374793);

        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey);

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, arbitrumKey, 5_000_000e6, uint256(50_000_000e6)  / 1 days);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, xlayerKey,   5_000_000e6, uint256(100_000_000e6) / 1 days);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, takeKey,     0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, arbitrumKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, xlayerKey,   0, 0);

        // The Spark Liquidity Layer can no longer take from spUSDT.
        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        controller.takeFromSparkVault(Ethereum.SPARK_VAULT_V2_SPUSDT, 1e6);
    }

    function test_ETHEREUM_spUsdtPau_susdsBacking() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);
        IERC4626        susds  = IERC4626(Ethereum.SUSDS);

        uint256 assetsOutstanding = spUsdt.assetsOutstanding();

        assertEq(assetsOutstanding, spUsdt.totalAssets() - IERC20(Ethereum.USDT).balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT));

        uint256 expectedShares = susds.convertToShares(assetsOutstanding * 1e12);
        uint256 sllShares      = susds.balanceOf(Ethereum.ALM_PROXY);

        assertGe(sllShares,                             expectedShares);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);

        _executeAllPayloadsAndBridges();

        assertEq(susds.balanceOf(Ethereum.ALM_PROXY),            sllShares - expectedShares);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), expectedShares);

        // The spUSDT PAU's sUSDS is worth the USDT owed by the vault, in USDS.
        assertApproxEqAbs(susds.convertToAssets(expectedShares), assetsOutstanding * 1e12, 2);
        assertLe(susds.convertToAssets(expectedShares),          assetsOutstanding * 1e12);

        assertEq(spUsdt.assetsOutstanding(), assetsOutstanding);

        // The transient CONTROLLER grant to the Spark Proxy is revoked.
        assertEq(IALMProxy(Ethereum.ALM_PROXY).hasRole(IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(), Ethereum.SPARK_PROXY), false);
    }

    function test_ETHEREUM_spUsdtPau_susdsWithdrawAndDeposit() external onChain(ChainIdUtils.Ethereum()) {
        IERC4626 susds = IERC4626(Ethereum.SUSDS);
        IERC20   usds  = IERC20(Ethereum.USDS);

        _executeAllPayloadsAndBridges();

        uint256 sharesBefore = susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY);

        assertGt(sharesBefore,                         0);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);

        // Withdraw 1,000,000 USDS from sUSDS to meet withdrawals.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IERC4626Controller.erc4626_withdraw, (Ethereum.SUSDS, 1_000_000e18, type(uint256).max)),
            0
        );

        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_000e18);
        assertApproxEqAbs(susds.convertToAssets(sharesBefore - susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY)), 1_000_000e18, 2);

        // Deposit the USDS back into sUSDS.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IERC4626Controller.erc4626_deposit, (Ethereum.SUSDS, 1_000_000e18, 0)),
            0
        );

        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertApproxEqAbs(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), sharesBefore, 2);
    }

    function test_ETHEREUM_sllPau_onboarding() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxy   almProxy   = IALMProxy(Ethereum.ALM_PROXY);
        IController controller = IController(ETHEREUM_SLL_PAU_CONTROLLER);

        bytes32 controllerRole = almProxy.CONTROLLER();

        assertEq(controllerRole, 0x70546d1c92f8c2132ae23a23f5177aa8526356051c7510df99f50e012d221529);

        assertEq(almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER),     true);
        assertEq(almProxy.hasRole(controllerRole, ETHEREUM_SLL_PAU_CONTROLLER), false);
        assertEq(almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),        false);

        assertEq(controller.integrations().length,                                0);
        assertEq(controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet, address(0));

        // Pre-requirement 9: the integration comes from the Sky Beacon.
        _assertIntegration(SKY_BEACON, BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));

        _executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER),     true);
        assertEq(almProxy.hasRole(controllerRole, ETHEREUM_SLL_PAU_CONTROLLER), true);
        assertEq(almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),        false);

        // SwapAsset is the only integration.
        assertEq(controller.integrations().length, 1);

        _assertIntegrationEnabled(ETHEREUM_SLL_PAU_CONTROLLER, BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
    }

    function test_ETHEREUM_sllPau_swapUsdsForUsdt() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);
        IERC20 usdt = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        // The spUSDT PAU holds USDT taken from the vault; the Spark Liquidity Layer holds idle USDS.
        deal(Ethereum.USDT, ETHEREUM_SPUSDT_PAU_ALM_PROXY, 1_000_000e6);
        deal(Ethereum.USDS, Ethereum.ALM_PROXY,            1_000_000e18);

        uint256 sllUsdt = usdt.balanceOf(Ethereum.ALM_PROXY);

        // The Spark Liquidity Layer swaps 1,000,000 USDS for 1,000,000 USDT from the spUSDT PAU.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            ETHEREUM_SLL_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 1_000_000e18)),
            0
        );

        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            0);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            sllUsdt + 1_000_000e6);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_000e18);
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);

        // Each side consumed its own limit; the opposite direction was already at its maximum.
        assertEq(IRateLimits(ETHEREUM_SLL_PAU_RATE_LIMITS).getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)),       99_000_000e18);
        assertEq(IRateLimits(ETHEREUM_SLL_PAU_RATE_LIMITS).getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)),       100_000_000e6);
        assertEq(IRateLimits(ETHEREUM_SPUSDT_PAU_RATE_LIMITS).getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 99_000_000e6);
        assertEq(IRateLimits(ETHEREUM_SPUSDT_PAU_RATE_LIMITS).getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);

        assertEq(usds.allowance(Ethereum.ALM_PROXY, ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);
    }

    function test_ETHEREUM_sllPau_swapUsdtForUsds() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);
        IERC20 usdt = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        // The spUSDT PAU withdraws the USDS it pays from sUSDS.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IERC4626Controller.erc4626_withdraw, (Ethereum.SUSDS, 1_000_000e18, type(uint256).max)),
            0
        );

        deal(Ethereum.USDT, Ethereum.ALM_PROXY, 1_000_000e6);

        uint256 sllUsds = usds.balanceOf(Ethereum.ALM_PROXY);
        uint256 pauUsdt = usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY);

        // The Spark Liquidity Layer swaps 1,000,000 USDT for 1,000,000 USDS from the spUSDT PAU.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            ETHEREUM_SLL_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDT, Ethereum.USDS, 1_000_000e6)),
            0
        );

        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            sllUsds + 1_000_000e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            0);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), pauUsdt + 1_000_000e6);

        assertEq(IRateLimits(ETHEREUM_SLL_PAU_RATE_LIMITS).getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)),       100_000_000e18);
        assertEq(IRateLimits(ETHEREUM_SLL_PAU_RATE_LIMITS).getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)),       99_000_000e6);
        assertEq(IRateLimits(ETHEREUM_SPUSDT_PAU_RATE_LIMITS).getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);
        assertEq(IRateLimits(ETHEREUM_SPUSDT_PAU_RATE_LIMITS).getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 99_000_000e18);

        assertEq(usdt.allowance(Ethereum.ALM_PROXY, ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);
    }

    function test_ETHEREUM_sllPau_swapRateLimitEnforced() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        deal(Ethereum.USDT, ETHEREUM_SPUSDT_PAU_ALM_PROXY, 101_000_000e6);
        deal(Ethereum.USDS, Ethereum.ALM_PROXY,            101_000_000e18);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            ETHEREUM_SLL_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 100_000_000e18 + 1e12)),
            0
        );

        // 1 USDS and 1 wei cannot be scaled to USDT.
        vm.expectRevert("SwapAssetFacet/precision-loss");
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            ETHEREUM_SLL_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 1e18 + 1)),
            0
        );

        // The spUSDT PAU cannot start a swap: no initiate key is set on it.
        vm.expectRevert("RateLimits/zero-maxAmount");
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            ETHEREUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SLL_PAU_CONTROLLER, Ethereum.USDT, Ethereum.USDS, 1e6)),
            0
        );

        // The full maximum passes.
        _callAsAgent(
            ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            ETHEREUM_SLL_PAU_CONTROLLER,
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 100_000_000e18)),
            0
        );

        assertEq(IERC20(Ethereum.USDT).balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_000e6);
    }

    /**********************************************************************************************/
    /*** Arbitrum                                                                               ***/
    /**********************************************************************************************/

    function test_ARBITRUM_spUsdtPau_deploymentConfig() external onChain(ChainIdUtils.ArbitrumOne()) {
        _assertArbitrumSpUsdtPauDeploymentConfig();

        _executeAllPayloadsAndBridges();

        _assertArbitrumSpUsdtPauDeploymentConfig();
    }

    function test_ARBITRUM_spUsdt_roles() external onChain(ChainIdUtils.ArbitrumOne()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);
        IERC20          usdt0  = IERC20(Arbitrum.USDT0);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          Arbitrum.ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         Arbitrum.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        uint256 vaultBalance = usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);
        uint256 totalAssets  = spUsdt.totalAssets();

        assertEq(usdt0.balanceOf(Arbitrum.ALM_PROXY),            0);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);

        _executeAllPayloadsAndBridges();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          ARBITRUM_SPUSDT_PAU_ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         ARBITRUM_SPARK_ADMINISTERED_AGENT);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        // No funds move.
        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(usdt0.balanceOf(Arbitrum.ALM_PROXY),             0);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  0);

        assertEq(spUsdt.totalAssets(), totalAssets);

        // Setter can set the vsr

        uint256 maxVsr = spUsdt.maxVsr();

        vm.expectRevert();
        vm.prank(Arbitrum.ALM_PROXY_FREEZABLE);
        spUsdt.setVsr(maxVsr);

        _callAsAgent(
            ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            Arbitrum.SPARK_VAULT_V2_SPUSDT,
            abi.encodeCall(ISparkVaultV2Like.setVsr, (maxVsr)),
            0
        );

        assertEq(spUsdt.vsr(), maxVsr);
    }

    function test_ARBITRUM_spUsdtPau_takeAndTransfer() external onChain(ChainIdUtils.ArbitrumOne()) {
        IERC20 usdt0 = IERC20(Arbitrum.USDT0);

        _executeAllPayloadsAndBridges();

        uint256 vaultBalance = usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        assertGe(vaultBalance, 1_000_000e6);

        _callAsAgent(
            ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(ISparkVaultController.sparkVault_take, (Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  1_000_000e6);

        _callAsAgent(
            ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(ITransferAssetController.transferAsset_transfer, (Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  0);
    }

    function test_ARBITRUM_spUsdtPau_layerZeroTransferToEthereum() external onChain(ChainIdUtils.ArbitrumOne()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            agent:                 ARBITRUM_SPARK_ADMINISTERED_AGENT,
            controller:            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            oft:                   Arbitrum.USDT_OFT,
            asset:                 Arbitrum.USDT0,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_ETHEREUM,
            destinationChainId:    ChainIdUtils.Ethereum(),
            destinationOft:        USDT_OFT,
            destinationAsset:      Ethereum.USDT,
            destinationReceiver:   ETHEREUM_SPUSDT_PAU_ALM_PROXY,
            sourceEndpointId:      LZ_EID_ARBITRUM,
            sourceChainId:         ChainIdUtils.ArbitrumOne(),
            transferKey:           _arbSpUsdtLayerZeroKey()
        }));
    }

    function test_ARBITRUM_sll_spUsdtRateLimitsZeroed() external onChain(ChainIdUtils.ArbitrumOne()) {
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);

        bytes32 takeKey      = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey  = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 layerZeroKey = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Arbitrum.USDT_OFT, LZ_EID_ETHEREUM));

        assertEq(takeKey,      0x848f12eb0a19b9a33294615f6ba284a2f74a1d98d218fec1ce52f19e106c9ac2);
        assertEq(transferKey,  0xa55538975929472a1a221101825aabfc029a2d978dc641996bb2804531e2b200);
        assertEq(layerZeroKey, 0x23f1cd7ca8ed176a38e51e824f90a46b2fe2bd4257f06fc61ab930ecd67fea64);

        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, layerZeroKey);

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, takeKey,      0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, transferKey,  0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, layerZeroKey, 0, 0);

        // The legacy recipient is left in place; its route has no limit.
        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        controller.takeFromSparkVault(Arbitrum.SPARK_VAULT_V2_SPUSDT, 1e6);
    }

    /**********************************************************************************************/
    /*** X Layer                                                                                ***/
    /**********************************************************************************************/

    function test_XLAYER_sll_layerZeroRecipient() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(ETHEREUM_SPUSDT_PAU_ALM_PROXY));
    }

    function test_XLAYER_sll_layerZeroTransferToEthereum() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);
        IERC20            usdt       = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 destinationSnapshot      = vm.snapshotState();
        uint256 destinationBalanceBefore = usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        deal(XLayer.USDT0,                XLayer.ALM_PROXY, 1_000_000e6);
        deal(XLayer.ALM_RELAYER_MULTISIG, 1 ether);

        SendParam memory sendParams = SendParam({
            dstEid       : LZ_EID_ETHEREUM,
            to           : controller.layerZeroRecipients(LZ_EID_ETHEREUM),
            amountLD     : 1_000_000e6,
            minAmountLD  : 1_000_000e6,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        MessagingFee memory fee = ILayerZero(USDT0_OFT_XLAYER).quoteSend(sendParams, false);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT_XLAYER).outboundNonce(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, _toBytes32(USDT_OFT)) + 1;

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        controller.transferTokenLayerZero{ value: fee.nativeFee }(USDT0_OFT_XLAYER, 1_000_000e6, LZ_EID_ETHEREUM);

        assertEq(IERC20(XLayer.USDT0).balanceOf(XLayer.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        if (ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER)) >= sentNonce) {
            console2.log("Skipping LZ destination delivery (destination fork ahead of source) for", USDT0_OFT_XLAYER);
        } else {
            _skipLZPendingNonces(USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER), sentNonce);

            assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), destinationBalanceBefore);

            chainData[ChainIdUtils.XLayer()].domain.selectFork();

            LZBridgeTesting.relayMessagesToDestination(xlayerToEthereumLZBridge, true, USDT0_OFT_XLAYER, USDT_OFT);

            // The USDT lands in the Ethereum spUSDT PAU ALM Proxy, not in the Spark Liquidity Layer ALM Proxy.
            assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), destinationBalanceBefore + 1_000_000e6);
        }

        vm.revertToState(destinationSnapshot);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
    }

    function test_XLAYER_spUsdt_rolesUnchanged() external onChain(ChainIdUtils.XLayer()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDT);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          XLayer.ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         XLayer.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, XLayer.SPARK_EXECUTOR);

        _executeAllPayloadsAndBridges();

        _assertOnlyRoleMember(address(spUsdt), takerRole,          XLayer.ALM_PROXY);
        _assertOnlyRoleMember(address(spUsdt), setterRole,         XLayer.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(spUsdt), DEFAULT_ADMIN_ROLE, XLayer.SPARK_EXECUTOR);
    }

    function test_XLAYER_sll_spUsdtRateLimitsUnchanged() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);

        bytes32 takeKey      = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), XLayer.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey  = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), XLayer.USDT0, XLayer.SPARK_VAULT_V2_SPUSDT);
        bytes32 layerZeroKey = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), XLayer.USDT0_OFT, LZ_EID_ETHEREUM));

        assertEq(takeKey,      0x0631157ca01222eff6a884d0082adde6d54a78fb54c94deffc01e72f488e0299);
        assertEq(transferKey,  0xe81b059884c85142a3bac9b2afa6a8f7289537e7aa2d704446d2535b0a06d849);
        assertEq(layerZeroKey, 0x83b84d91df714f1188544c3716582f037ccaaf60c9a43a1a6edefff62dcfa546);

        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, layerZeroKey);

        _executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(XLayer.ALM_RATE_LIMITS, layerZeroKey);
    }

    /**********************************************************************************************/
    /*** Base                                                                                   ***/
    /**********************************************************************************************/

    function test_BASE_sll_pauCctpV2_rateLimit() external onChain(ChainIdUtils.Base()) {
        ICCTPControllerLike controller = ICCTPControllerLike(Base.PAU_CONTROLLER);

        bytes32 domainKey    = controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        bytes32 aggregateKey = controller.cctp_toCCTPRateLimitKey();

        assertEq(domainKey, 0x90b598dae614822d554ec4f627bb5feab505106473a7911f34b36c0b3b9695c7);

        _assertRateLimit(Base.PAU_RATELIMITS, domainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, aggregateKey);

        ( bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate ) = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     _toBytes32(Ethereum.ALM_PROXY));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Base.PAU_RATELIMITS, domainKey, 25_000_000e6, uint256(100_000_000e6) / 1 days);

        assertEq(uint256(100_000_000e6) / 1 days, 1_157_407_407);

        // Unchanged.
        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, aggregateKey);

        ( recipient, minFeeCapRate, maxFeeCapRate ) = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     _toBytes32(Ethereum.ALM_PROXY));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);
    }

    function test_BASE_sll_pauCctpV2_rateLimitEnforced() external onChain(ChainIdUtils.Base()) {
        _executeAllPayloadsAndBridges();

        deal(Base.USDC, Base.ALM_PROXY, 25_000_000e6 + 1, true);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(Base.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).call(
            Base.PAU_CONTROLLER,
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (25_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        // The full maximum reaches the Ethereum Spark Liquidity Layer ALM Proxy.
        _bridgeUSDCToMainnet_pau(25_000_000e6, ChainIdUtils.Base(), Base.PAU_CONTROLLER);
    }

    /**********************************************************************************************/
    /*** E2E                                                                                    ***/
    /**********************************************************************************************/

    address internal user = makeAddr("user");

    IERC20   internal usdt  = IERC20(Ethereum.USDT);
    IERC20   internal usds  = IERC20(Ethereum.USDS);
    IERC20   internal usdt0 = IERC20(Arbitrum.USDT0);
    IERC4626 internal susds = IERC4626(Ethereum.SUSDS);

    ISparkVaultLike internal ethSpUSDT = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);
    ISparkVaultLike internal arbSpUSDT = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);

    IRateLimits internal ethSllPAU_rateLimits    = IRateLimits(ETHEREUM_SLL_PAU_RATE_LIMITS);
    IRateLimits internal ethSpUSDTPAU_rateLimits = IRateLimits(ETHEREUM_SPUSDT_PAU_RATE_LIMITS);
    IRateLimits internal arbSpUSDTPAU_rateLimits = IRateLimits(ARBITRUM_SPUSDT_PAU_RATE_LIMITS);

    // TODO: Add the X Layer path.
    function test_E2E_spUsdtPau_ethereumArbitrumFullFlow() external {
        Domain memory mainnet  = chainData[ChainIdUtils.Ethereum()].domain;
        Domain memory arbitrum = chainData[ChainIdUtils.ArbitrumOne()].domain;

        // Execute the spell: onboards LayerZero and SwapAsset, moves TAKER to the spUSDT PAUs, adds the SLL PAU
        // controller to the SLL ALMProxy and transfers the sUSDS backing to the Ethereum spUSDT PAU.

        _executeAllPayloadsAndBridges();

        mainnet.selectFork();

        // The SLL ALMProxy needs idle USDS and USDT to complete the swaps.
        deal(Ethereum.USDS, Ethereum.ALM_PROXY, 2_000_000e18);
        deal(Ethereum.USDT, Ethereum.ALM_PROXY, 2_000_000e6);

        // spUSDT VSR accrues faster than the sUSDS yield, so the strategy alone does not cover what both users are
        // owed after 1 day. This buffer funds the difference.
        deal(Ethereum.USDT, ETHEREUM_SPUSDT_PAU_ALM_PROXY, 100e6);

        deal(Ethereum.USDT, user, 1_000_000e6);

        vm.deal(Ethereum.PLANNER_WALLET, 1 ether);  // For LayerZero fees

        arbitrum.selectFork();

        deal(Arbitrum.USDT0, user, 1_000_000e6);

        vm.deal(Arbitrum.PLANNER_WALLET, 1 ether);  // For LayerZero fees

        // Discard stale Ethereum -> Arbitrum packets so only this flow's messages are relayed.
        _drainLZPendingPackets(ChainIdUtils.ArbitrumOne());

        // Step 1: User deposits 1_000_000e6 USDT to the Ethereum spUSDT vault

        mainnet.selectFork();

        assertEq(usdt.balanceOf(user),               1_000_000e6);
        assertEq(usdt.balanceOf(address(ethSpUSDT)), 50_599_360.713104e6);

        assertEq(ethSpUSDT.totalAssets(),   302_332_901.380199e6);
        assertEq(ethSpUSDT.totalSupply(),   291_476_338.503053e6);
        assertEq(ethSpUSDT.balanceOf(user), 0);

        vm.startPrank(user);
        IUSDTLike(Ethereum.USDT).approve(address(ethSpUSDT), 1_000_000e6);
        ethSpUSDT.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(usdt.balanceOf(user),               0);
        assertEq(usdt.balanceOf(address(ethSpUSDT)), 51_599_360.713104e6);

        assertEq(ethSpUSDT.totalAssets(), 303_332_901.380198e6);
        assertEq(ethSpUSDT.totalSupply(), 292_440_429.202981e6);

        assertEq(ethSpUSDT.balanceOf(user), 964_090.699928e6);

        // Step 2: User deposits 1_000_000e6 USDT0 to the Arbitrum spUSDT vault

        arbitrum.selectFork();

        assertEq(usdt0.balanceOf(user),               1_000_000e6);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)), 1_053_182.977823e6);

        assertEq(arbSpUSDT.totalAssets(),   1_054_572.604870e6);
        assertEq(arbSpUSDT.totalSupply(),   1_042_378.177040e6);
        assertEq(arbSpUSDT.balanceOf(user), 0);

        vm.startPrank(user);
        IUSDTLike(Arbitrum.USDT0).approve(address(arbSpUSDT), 1_000_000e6);
        arbSpUSDT.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(usdt0.balanceOf(user),               0);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)), 2_053_182.977823e6);

        assertEq(arbSpUSDT.totalAssets(), 2_054_572.604870e6);
        assertEq(arbSpUSDT.totalSupply(), 2_030_814.793187e6);

        assertEq(arbSpUSDT.balanceOf(user), 988_436.616147e6);

        // Step 3: Ethereum Spark Vaults agent (planner agent) takes 1_000_000e6 USDT out of the Ethereum spUSDT vault

        mainnet.selectFork();

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtTakeKey()), type(uint256).max);

        assertEq(usdt.balanceOf(address(ethSpUSDT)),            51_599_360.713104e6);
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 100e6);

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(ISparkVaultController.sparkVault_take, (address(ethSpUSDT), 1_000_000e6))
                )
            )
        );

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtTakeKey()), type(uint256).max);

        assertEq(usdt.balanceOf(address(ethSpUSDT)),            50_599_360.713104e6);
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_100e6);

        // Taking moves idle liquidity out, it does not change the vault's accounting.
        assertEq(ethSpUSDT.totalAssets(), 303_332_901.380198e6);
        assertEq(ethSpUSDT.totalSupply(), 292_440_429.202981e6);

        // Step 4: Arbitrum Spark Vaults agent (planner agent) takes 1_000_000e6 USDT0 out of the Arbitrum spUSDT vault

        arbitrum.selectFork();

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtTakeKey()), type(uint256).max);

        assertEq(usdt0.balanceOf(address(arbSpUSDT)),            2_053_182.977823e6);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);

        vm.prank(Arbitrum.PLANNER_WALLET);
        IAdministeredAgentLike(ARBITRUM_PLANNER_ADMINISTERED_AGENT).call(
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ARBITRUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(ISparkVaultController.sparkVault_take, (address(arbSpUSDT), 1_000_000e6))
                )
            )
        );

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtTakeKey()), type(uint256).max);

        assertEq(usdt0.balanceOf(address(arbSpUSDT)),            1_053_182.977823e6);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 1_000_000e6);

        assertEq(arbSpUSDT.totalAssets(), 2_054_572.604870e6);
        assertEq(arbSpUSDT.totalSupply(), 2_030_814.793187e6);

        // Step 5: Arbitrum Spark Vaults agent (planner agent) bridges 1_000_000e6 USDT0 to the Ethereum spUSDT PAU using
        //         LayerZeroFacet

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtLayerZeroKey()), type(uint256).max);

        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 1_000_000e6);
        assertEq(usdt0.totalSupply(),                            899_127_877.736082e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = ILayerZeroController(ARBITRUM_SPUSDT_PAU_CONTROLLER)
            .layerZero_quoteTransfer(Arbitrum.USDT_OFT, 1_000_000e6, LZ_EID_ETHEREUM);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)) + 1;

        vm.prank(Arbitrum.PLANNER_WALLET);
        IAdministeredAgentLike(ARBITRUM_PLANNER_ADMINISTERED_AGENT).call{ value: fee.nativeFee }(
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ARBITRUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(ILayerZeroController.layerZero_transfer, (Arbitrum.USDT_OFT, 1_000_000e6, LZ_EID_ETHEREUM))
                )
            )
        );

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtLayerZeroKey()), type(uint256).max);

        // USDT0 is burned on Arbitrum.
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt0.totalSupply(),                            898_127_877.736082e6);

        // Step 6: Relay the message to Ethereum

        mainnet.selectFork();

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_100e6);
        assertEq(usdt.balanceOf(Ethereum.USDT_OFT),             3_576_500_417.256819e6);

        // The message can only be delivered if the Ethereum fork is not ahead of the Arbitrum fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT)), sentNonce);

        _skipLZPendingNonces(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT), sentNonce);

        LZBridgeTesting.relayMessagesToSource(_getLZBridge(ChainIdUtils.ArbitrumOne()), true, Arbitrum.USDT_OFT, Ethereum.USDT_OFT);

        // USDT is released from the OFT adapter on Ethereum.
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_100e6);
        assertEq(usdt.balanceOf(Ethereum.USDT_OFT),             3_575_500_417.256819e6);

        // Step 7: SLL agent (planner agent) initiates a swap on the SLL PAU of 2_000_000e18 USDS for 2_000_000e6 USDT,
        //         completed by the spUSDT PAU using SwapAssetFacet

        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_100e6);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            2_000_000e6);
        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            2_000_000e18);

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SLL_PAU_CONTROLLER,
                    abi.encodeCall(
                        ISwapAssetController.swapAsset_initiateSwap,
                        (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 2_000_000e18)
                    )
                )
            )
        );

        // The reverse direction keys increase, already at max so they stay at max.
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)), 98_000_000e18);
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 98_000_000e6);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 100e6);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_000e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            4_000_000e6);
        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            0);

        // Step 8: Ethereum Spark Vaults agent (planner agent) deposits 2_000_000e18 USDS to sUSDS using ERC4626Facet

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtDepositKey()),  type(uint256).max);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtWithdrawKey()), type(uint256).max);


        // The spUSDT PAU already holds the sUSDS backing transferred by the spell.
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY),  2_000_000e18);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 225_395_490.431514946117282037e18);

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(
                        IERC4626Controller.erc4626_deposit,
                        (Ethereum.SUSDS, 2_000_000e18, 1_790_746.595262720224995762e18)
                    )
                )
            )
        );

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtDepositKey()),  type(uint256).max);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtWithdrawKey()), type(uint256).max);

        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY),  0);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 225_395_490.431514946117282037e18 + 1_790_746.595262720224995762e18);

        assertEq(susds.convertToAssets(1_790_746.595262720224995762e18), 1_999_999.999999999999999999e18);  // Rounding

        // Step 9: Skip 1 day on Ethereum and Arbitrum to let sUSDS and both spUSDT vaults accrue yield. A fork switch
        //         does not keep a fork's warped timestamp, so each chain's timestamp is re-applied on every switch.

        skip(1 days);

        uint256 ethTimestamp = block.timestamp;

        arbitrum.selectFork();

        skip(1 days);

        uint256 arbTimestamp = block.timestamp;


        assertEq(arbSpUSDT.convertToAssets(988_436.616147e6), 1_000_114.038487e6);  // Interest owed to the user on Arbitrum

        mainnet.selectFork();
        vm.warp(ethTimestamp);


        assertEq(susds.convertToAssets(1_790_746.595262720224995762e18), 2_000_204.370905504494858259e18);  // Interest accrued
        assertEq(ethSpUSDT.convertToAssets(964_090.699928e6),            1_000_114.038486e6);               // Interest owed to the user on Ethereum

        // Rate limits fully recharged
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)),       100_000_000e18);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);

        // Step 10: Ethereum Spark Vaults agent (planner agent) redeems the sUSDS for 2_000_000e18 USDS + interest using
        //          ERC4626Facet

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtDepositKey()),  type(uint256).max);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtWithdrawKey()), type(uint256).max);

        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY),  0);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 225_395_490.431514946117282037e18 + 1_790_746.595262720224995762e18);

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(
                        IERC4626Controller.erc4626_redeem,
                        (Ethereum.SUSDS, 1_790_746.595262720224995762e18, 2_000_204.370905504494858259e18)
                    )
                )
            )
        );

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtDepositKey()),  type(uint256).max);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtWithdrawKey()), type(uint256).max);

        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY),  2_000_204.370905504494858259e18);
        assertEq(susds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 225_395_490.431514946117282037e18);

        // Step 11: SLL agent (planner agent) initiates a swap on the SLL PAU of USDT + interest for the USDS + interest,
        //          completed by the spUSDT PAU using SwapAssetFacet

        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 100e6);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_204.370905504494858259e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            4_000_000e6);
        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            0);

        // The SLL sends USDT, so the spUSDT PAU sends amountOut * 1e12 USDS, the USDS dust below 1e12 stays in the
        // spUSDT ALMProxy.
        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SLL_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SLL_PAU_CONTROLLER,
                    abi.encodeCall(
                        ISwapAssetController.swapAsset_initiateSwap,
                        (ETHEREUM_SPUSDT_PAU_CONTROLLER, Ethereum.USDT, Ethereum.USDS, 2_000_204.370905e6)
                    )
                )
            )
        );

        // The reverse direction keys increase, already at max so they stay at max.
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDS, Ethereum.USDT)), 100_000_000e18);
        assertEq(ethSllPAU_rateLimits.getCurrentRateLimit(_sllInitiateKey(Ethereum.USDT, Ethereum.USDS)), 97_999_795.629095e6);

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS)), 100_000_000e6);
        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT)), 97_999_795.629095e18);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_304.370905e6);
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0.000000504494858259e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),            1_999_795.629095e6);
        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),            2_000_204.370905e18);

        // Step 12: Ethereum Spark Vaults agent (planner agent) transfers 1_000_000e6 USDT + interest to the Ethereum
        //          spUSDT vault using TransferAssetFacet

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtTransferKey()), type(uint256).max);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 2_000_304.370905e6);
        assertEq(usdt.balanceOf(address(ethSpUSDT)),            50_599_360.713104e6);

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call(
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(
                        ITransferAssetController.transferAsset_transfer,
                        (Ethereum.USDT, address(ethSpUSDT), 1_000_114.038486e6)  // Interest owed to the user on Ethereum
                    )
                )
            )
        );

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtTransferKey()), type(uint256).max);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_190.332419e6);
        assertEq(usdt.balanceOf(address(ethSpUSDT)),            51_599_474.751590e6);

        // Step 13: Ethereum Spark Vaults agent (planner agent) bridges 1_000_000e6 USDT + interest to the Arbitrum
        //          spUSDT PAU using LayerZeroFacet

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtLayerZeroKey(LZ_EID_ARBITRUM)), 5_000_000e6);

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 1_000_190.332419e6);
        assertEq(usdt.balanceOf(Ethereum.USDT_OFT),             3_575_500_417.256819e6);

        ( , fee ) = ILayerZeroController(ETHEREUM_SPUSDT_PAU_CONTROLLER).layerZero_quoteTransfer(Ethereum.USDT_OFT, 1_000_114.038487e6, LZ_EID_ARBITRUM);

        sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT)) + 1;

        vm.prank(Ethereum.PLANNER_WALLET);
        IAdministeredAgentLike(ETHEREUM_PLANNER_ADMINISTERED_AGENT).call{ value: fee.nativeFee }(
            ETHEREUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ETHEREUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(
                        ILayerZeroController.layerZero_transfer,
                        (Ethereum.USDT_OFT, 1_000_114.038487e6, LZ_EID_ARBITRUM)  // Interest owed to the user on Arbitrum
                    )
                )
            )
        );

        assertEq(ethSpUSDTPAU_rateLimits.getCurrentRateLimit(_spUsdtLayerZeroKey(LZ_EID_ARBITRUM)), 5_000_000e6 - 1_000_114.038487e6);

        // USDT is locked in the OFT adapter on Ethereum.
        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 76.293932e6);
        assertEq(usdt.balanceOf(Ethereum.USDT_OFT),             3_576_500_531.295306e6);

        // Step 14: Relay the message to Arbitrum

        arbitrum.selectFork();
        vm.warp(arbTimestamp);

        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt0.totalSupply(),                            898_127_877.736082e6);

        // The message can only be delivered if the Arbitrum fork is not ahead of the Ethereum fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)), sentNonce);

        _skipLZPendingNonces(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT), sentNonce);

        LZBridgeTesting.relayMessagesToDestination(_getLZBridge(ChainIdUtils.ArbitrumOne()), true, Ethereum.USDT_OFT, Arbitrum.USDT_OFT);

        vm.warp(arbTimestamp);

        // USDT0 is minted on Arbitrum.
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 1_000_114.038487e6);
        assertEq(usdt0.totalSupply(),                            899_127_991.774569e6);

        // Step 15: Arbitrum Spark Vaults agent (planner agent) transfers 1_000_000e6 USDT0 + interest to the Arbitrum
        //          spUSDT vault using TransferAssetFacet

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtTransferKey()), type(uint256).max);

        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 1_000_114.038487e6);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)),            1_053_182.977823e6);

        vm.prank(Arbitrum.PLANNER_WALLET);
        IAdministeredAgentLike(ARBITRUM_PLANNER_ADMINISTERED_AGENT).call(
            ARBITRUM_SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    ARBITRUM_SPUSDT_PAU_CONTROLLER,
                    abi.encodeCall(
                        ITransferAssetController.transferAsset_transfer,
                        (Arbitrum.USDT0, address(arbSpUSDT), 1_000_114.038487e6)  // Interest owed to the user on Arbitrum
                    )
                )
            )
        );

        assertEq(arbSpUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdtTransferKey()), type(uint256).max);

        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)),            2_053_297.016310e6);

        // Step 16: User redeems their Ethereum spUSDT deposit and receives the 1_000_000e6 USDT + interest

        mainnet.selectFork();
        vm.warp(ethTimestamp);

        assertEq(usdt.balanceOf(user),               0);
        assertEq(usdt.balanceOf(address(ethSpUSDT)), 51_599_474.751590e6);

        assertEq(ethSpUSDT.totalAssets(),   303_367_493.005435e6);
        assertEq(ethSpUSDT.totalSupply(),   292_440_429.202981e6);
        assertEq(ethSpUSDT.balanceOf(user), 964_090.699928e6);

        vm.prank(user);
        ethSpUSDT.redeem(964_090.699928e6, user, user);

        assertEq(usdt.balanceOf(user),               1_000_114.038486e6);
        assertEq(usdt.balanceOf(address(ethSpUSDT)), 50_599_360.713104e6);

        assertEq(ethSpUSDT.totalAssets(),   302_367_378.966948e6);
        assertEq(ethSpUSDT.totalSupply(),   291_476_338.503053e6);
        assertEq(ethSpUSDT.balanceOf(user), 0);

        // Step 17: User redeems their Arbitrum spUSDT deposit and receives the 1_000_000e6 USDT0 + interest

        arbitrum.selectFork();
        vm.warp(arbTimestamp);

        assertEq(usdt0.balanceOf(user),               0);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)), 2_053_297.016310e6);

        assertEq(arbSpUSDT.totalAssets(),   2_054_806.905222e6);
        assertEq(arbSpUSDT.totalSupply(),   2_030_814.793187e6);
        assertEq(arbSpUSDT.balanceOf(user), 988_436.616147e6);

        vm.prank(user);
        arbSpUSDT.redeem(988_436.616147e6, user, user);

        assertEq(usdt0.balanceOf(user),               1_000_114.038487e6);
        assertEq(usdt0.balanceOf(address(arbSpUSDT)), 1_053_182.977823e6);

        assertEq(arbSpUSDT.totalAssets(),   1_054_692.866735e6);
        assertEq(arbSpUSDT.totalSupply(),   1_042_378.177040e6);
        assertEq(arbSpUSDT.balanceOf(user), 0);

        // The unused buffer and the USDS swap dust on Ethereum, nothing on Arbitrum.
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);

        mainnet.selectFork();

        assertEq(usdt.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 76.293932e6);              // Remaining dust from the buffer deal of 100e6
        assertEq(usds.balanceOf(ETHEREUM_SPUSDT_PAU_ALM_PROXY), 0.000000504494858259e18);  // Remaining USDS swap dust
    }

    function test_E2E_sparkLiquidityLayerCCTPCrossChainSetup() external override {
        _runCrossChainCctpLegsForAllDomains({ isPostExecution: false });

        _executeAllPayloadsAndBridges();

        _runCrossChainCctpLegsForAllDomains({ isPostExecution: true });
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    // Mirrors `_runE2ESLLCrossChainTestForAllDomains`, plus `_clearLogs()` after each domain's leg.
    function _runCrossChainCctpLegsForAllDomains(bool isPostExecution) internal {
        address legacyMainnetController = _getSparkLiquidityLayerContext(ChainIdUtils.Ethereum()).controller;

        for (uint256 i = 0; i < allChains.length; ++i) {
            if (
                allChains[i] == ChainIdUtils.Ethereum() ||
                allChains[i] == ChainIdUtils.Gnosis()   ||
                allChains[i] == ChainIdUtils.XLayer()   ||
                allChains[i] == ChainIdUtils.Robinhood()
            ) continue;

            uint256 domainChainId = chainData[allChains[i]].domain.chain.chainId;

            address legacyDomainController = _getSparkLiquidityLayerContext(domainChainId, isPostExecution).controller;

            _mintUSDSAndSwapToUSDC(1_000_000e6, legacyMainnetController);

            _bridgeUSDCToDomain(1_000_000e6, domainChainId, legacyMainnetController);

            _depositAndWithdrawFromPSM3(1_000_000e6, domainChainId, legacyDomainController);

            if (
                domainChainId == ChainIdUtils.ArbitrumOne() ||
                (isPostExecution && domainChainId == ChainIdUtils.Base())
            ) {
                address pauController = _getSLLPAUContext(domainChainId).controller;

                _bridgeUSDCToMainnet(500_000e6,     domainChainId, legacyDomainController);
                _bridgeUSDCToMainnet_pau(500_000e6, domainChainId, pauController);
            } else {
                _bridgeUSDCToMainnet(1_000_000e6, domainChainId, legacyDomainController);
            }

            _swapUSDCToUSDSAndBurn(1_000_000e6, legacyMainnetController);

            // Every message of this leg has been relayed; drop the accumulated logs.
            chainData[ChainIdUtils.Ethereum()].domain.selectFork();

            _clearLogs();
        }
    }

    function _assertSpUsdtPauDeploymentConfig() internal view {
        IEthSpUsdtPauControllerLike controller = IEthSpUsdtPauControllerLike(ETHEREUM_SPUSDT_PAU_CONTROLLER);

        // Wiring

        assertEq(controller.beacon(),         Ethereum.SPARK_BEACON);
        assertEq(controller.proxy(),          ETHEREUM_SPUSDT_PAU_ALM_PROXY);
        assertEq(controller.rateLimits(),     ETHEREUM_SPUSDT_PAU_RATE_LIMITS);
        assertEq(controller.accessControls(), ETHEREUM_SPUSDT_PAU_ACCESS_CONTROLS);

        // Roles

        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_ACCESS_CONTROLS, DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_ALM_PROXY,       DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_RATE_LIMITS,     DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_ALM_PROXY,       IALMProxy(ETHEREUM_SPUSDT_PAU_ALM_PROXY).CONTROLLER(),   ETHEREUM_SPUSDT_PAU_CONTROLLER);
        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_RATE_LIMITS,     IALMProxy(ETHEREUM_SPUSDT_PAU_RATE_LIMITS).CONTROLLER(), ETHEREUM_SPUSDT_PAU_CONTROLLER);
        _assertOnlyRoleMember(ETHEREUM_SPUSDT_PAU_ACCESS_CONTROLS, ALLOCATOR_ROLE,                                          ETHEREUM_SPARK_ADMINISTERED_AGENT);

        // Integrations enabled at deployment

        assertEq(controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);

        assertEq(controller.getConfig(BeaconConfig.CCTP_INTEGRATION).facet, address(0));

        // Rate limits

        _assertUnlimitedRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtDepositKey());
        _assertUnlimitedRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtWithdrawKey());
        _assertUnlimitedRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtTakeKey());
        _assertUnlimitedRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtTransferKey());

        _assertRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtLayerZeroKey(LZ_EID_ARBITRUM), 5_000_000e6, uint256(50_000_000e6)  / 1 days);
        _assertRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtLayerZeroKey(LZ_EID_XLAYER),   5_000_000e6, uint256(100_000_000e6) / 1 days);

        _assertRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtCompleteKey(Ethereum.USDT, Ethereum.USDS), 100_000_000e6,  uint256(1_000_000_000e6)  / 1 days);
        _assertRateLimit(ETHEREUM_SPUSDT_PAU_RATE_LIMITS, _spUsdtCompleteKey(Ethereum.USDS, Ethereum.USDT), 100_000_000e18, uint256(1_000_000_000e18) / 1 days);

        // No initiate key, so the spUSDT PAU cannot start a swap.
        _assertRateLimit(
            ETHEREUM_SPUSDT_PAU_RATE_LIMITS,
            ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getInitiateSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, ETHEREUM_SLL_PAU_CONTROLLER, Ethereum.USDS),
            0,
            0
        );

        // sUSDS maximum exchange rate: erc4626_setMaxExchangeRate(sUSDS, 1, 1e40).
        assertEq(controller.erc4626_getMaxExchangeRate(Ethereum.SUSDS), 1e40 * controller.erc4626_EXCHANGE_RATE_PRECISION());
    }

    function _assertSllPauDeploymentConfig() internal view {
        IController controller = IController(ETHEREUM_SLL_PAU_CONTROLLER);

        // Wiring: the Sky Beacon and the existing Spark Liquidity Layer ALM Proxy.

        assertEq(controller.beacon(),         SKY_BEACON);
        assertEq(controller.proxy(),          Ethereum.ALM_PROXY);
        assertEq(controller.rateLimits(),     ETHEREUM_SLL_PAU_RATE_LIMITS);
        assertEq(controller.accessControls(), ETHEREUM_SLL_PAU_ACCESS_CONTROLS);

        // Roles

        _assertOnlyRoleMember(ETHEREUM_SLL_PAU_ACCESS_CONTROLS, DEFAULT_ADMIN_ROLE,                                   Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(ETHEREUM_SLL_PAU_RATE_LIMITS,     DEFAULT_ADMIN_ROLE,                                   Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(ETHEREUM_SLL_PAU_RATE_LIMITS,     IALMProxy(ETHEREUM_SLL_PAU_RATE_LIMITS).CONTROLLER(), ETHEREUM_SLL_PAU_CONTROLLER);
        _assertOnlyRoleMember(ETHEREUM_SLL_PAU_ACCESS_CONTROLS, ALLOCATOR_ROLE,                                       ETHEREUM_SLL_ADMINISTERED_AGENT);

        // Rate limits

        _assertRateLimit(ETHEREUM_SLL_PAU_RATE_LIMITS, _sllInitiateKey(Ethereum.USDS, Ethereum.USDT), 100_000_000e18, uint256(500_000_000e18) / 1 days);
        _assertRateLimit(ETHEREUM_SLL_PAU_RATE_LIMITS, _sllInitiateKey(Ethereum.USDT, Ethereum.USDS), 100_000_000e6,  uint256(500_000_000e6)  / 1 days);
    }

    function _assertEthereumAgents() internal view {
        _assertAgent({
            agent    : ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actor    : Ethereum.PLANNER_WALLET,
            revoker1 : Ethereum.SPARK_LOW_THRESHOLD_MULTISIG,
            revoker2 : address(0),
            grantor  : Ethereum.SPARK_MEDIUM_THRESHOLD_MULTISIG
        });

        _assertAgent({
            agent    : ETHEREUM_SPARK_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actor    : ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            revoker1 : Ethereum.SPARK_LOW_THRESHOLD_MULTISIG,
            revoker2 : Ethereum.SOTER_REVOKER_MULTISIG,
            grantor  : Ethereum.SOTER_GRANTOR_MULTISIG
        });

        _assertAgent({
            agent    : ETHEREUM_SLL_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actor    : ETHEREUM_PLANNER_ADMINISTERED_AGENT,
            revoker1 : Ethereum.SPARK_LOW_THRESHOLD_MULTISIG,
            revoker2 : Ethereum.SOTER_REVOKER_MULTISIG,
            grantor  : Ethereum.SOTER_GRANTOR_MULTISIG
        });
    }

    function _assertArbitrumSpUsdtPauDeploymentConfig() internal view {
        IArbSpUsdtPauControllerLike controller = IArbSpUsdtPauControllerLike(ARBITRUM_SPUSDT_PAU_CONTROLLER);

        // Wiring

        assertEq(controller.beacon(),         Arbitrum.SPARK_BEACON);
        assertEq(controller.proxy(),          ARBITRUM_SPUSDT_PAU_ALM_PROXY);
        assertEq(controller.rateLimits(),     ARBITRUM_SPUSDT_PAU_RATE_LIMITS);
        assertEq(controller.accessControls(), ARBITRUM_SPUSDT_PAU_ACCESS_CONTROLS);

        // Roles

        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_ACCESS_CONTROLS, DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);
        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_ALM_PROXY,       DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);
        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_RATE_LIMITS,     DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_ALM_PROXY,       IALMProxy(ARBITRUM_SPUSDT_PAU_ALM_PROXY).CONTROLLER(),   ARBITRUM_SPUSDT_PAU_CONTROLLER);
        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_RATE_LIMITS,     IALMProxy(ARBITRUM_SPUSDT_PAU_RATE_LIMITS).CONTROLLER(), ARBITRUM_SPUSDT_PAU_CONTROLLER);
        _assertOnlyRoleMember(ARBITRUM_SPUSDT_PAU_ACCESS_CONTROLS, ALLOCATOR_ROLE,                                          ARBITRUM_SPARK_ADMINISTERED_AGENT);

        _assertAgent({
            agent    : ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            admin    : Arbitrum.SPARK_EXECUTOR,
            actor    : Arbitrum.PLANNER_WALLET,
            revoker1 : Arbitrum.SPARK_LOW_THRESHOLD_MULTISIG,
            revoker2 : address(0),
            grantor  : Arbitrum.SPARK_MEDIUM_THRESHOLD_MULTISIG
        });

        _assertAgent({
            agent    : ARBITRUM_SPARK_ADMINISTERED_AGENT,
            admin    : Arbitrum.SPARK_EXECUTOR,
            actor    : ARBITRUM_PLANNER_ADMINISTERED_AGENT,
            revoker1 : Arbitrum.SPARK_LOW_THRESHOLD_MULTISIG,
            revoker2 : Arbitrum.SOTER_REVOKER_MULTISIG,
            grantor  : Arbitrum.SOTER_GRANTOR_MULTISIG
        });

        // Integrations: SparkVault, TransferAsset and LayerZero only.

        assertEq(controller.integrations().length, 3);

        _assertIntegrationEnabled(ARBITRUM_SPUSDT_PAU_CONTROLLER, BeaconConfig.buildSparkVaultIntegration(Arbitrum.SPARK_VAULT_FACET));
        _assertIntegrationEnabled(ARBITRUM_SPUSDT_PAU_CONTROLLER, BeaconConfig.buildTransferAssetIntegration(Arbitrum.TRANSFER_ASSET_FACET));
        _assertIntegrationEnabled(ARBITRUM_SPUSDT_PAU_CONTROLLER, BeaconConfig.buildLayerZeroIntegration(Arbitrum.LAYER_ZERO_FACET));

        // Rate limits, all unlimited.

        assertEq(
            controller.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT),
            RateLimitHelpers.makeAddressKey(keccak256("LIMIT_SPARK_VAULT_TAKE"), Arbitrum.SPARK_VAULT_V2_SPUSDT)
        );

        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATE_LIMITS, controller.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT));
        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATE_LIMITS, _arbSpUsdtTransferKey());
        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATE_LIMITS, _arbSpUsdtLayerZeroKey());

        // LayerZero recipient: the Ethereum spUSDT PAU.

        assertEq(IOFTLike(Arbitrum.USDT_OFT).peers(LZ_EID_ETHEREUM), _toBytes32(Ethereum.USDT_OFT));

        assertEq(controller.layerZero_getRecipient(LZ_EID_ETHEREUM), _toBytes32(ETHEREUM_SPUSDT_PAU_ALM_PROXY));
        assertEq(controller.layerZero_getRecipient(LZ_EID_XLAYER),   bytes32(0));
    }

    function _assertAgent(
        address agent,
        address admin,
        address actor,
        address revoker1,
        address revoker2,
        address grantor
    ) internal view {
        IAdministeredAgentLike administeredAgent = IAdministeredAgentLike(agent);

        assertEq(administeredAgent.adminCount(),          1);
        assertEq(administeredAgent.getIsAdmin(admin),     true);
        assertEq(administeredAgent.actorCount(),          1);
        assertEq(administeredAgent.getIsActor(actor),     true);
        assertEq(administeredAgent.grantorCount(),        1);
        assertEq(administeredAgent.getIsGrantor(grantor), true);

        assertEq(administeredAgent.revokerCount(),         revoker2 == address(0) ? 1 : 2);
        assertEq(administeredAgent.getIsRevoker(revoker1), true);

        if (revoker2 != address(0)) assertEq(administeredAgent.getIsRevoker(revoker2), true);
    }

    // Asserts the integration's config on a Beacon or a Controller.
    function _assertIntegration(address target, IEnumerableIntegrations.Integration memory expected) internal view {
        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations(target).getConfig(expected.id);

        assertEq(config.facet,        expected.config.facet);
        assertEq(config.wires.length, expected.config.wires.length);

        for (uint256 i = 0; i < config.wires.length; ++i) {
            assertEq(bytes32(config.wires[i].callSelector),     bytes32(expected.config.wires[i].callSelector));
            assertEq(bytes32(config.wires[i].delegateSelector), bytes32(expected.config.wires[i].delegateSelector));
        }
    }

    // Asserts the integration's config on a Controller and that every call selector dispatches to the facet.
    function _assertIntegrationEnabled(address controller, IEnumerableIntegrations.Integration memory expected) internal view {
        _assertIntegration(controller, expected);

        for (uint256 i = 0; i < expected.config.wires.length; ++i) {
            IEnumerableIntegrations.Dispatch memory dispatch = IController(controller).getDispatch(expected.config.wires[i].callSelector);

            assertEq(dispatch.facet,                     expected.config.facet);
            assertEq(bytes32(dispatch.delegateSelector), bytes32(expected.config.wires[i].delegateSelector));
        }
    }

    function _assertOnlyRoleMember(address target, bytes32 role, address account) internal view {
        assertEq(IAccessControlEnumerable(target).getRoleMemberCount(role), 1);
        assertEq(IAccessControlEnumerable(target).getRoleMember(role, 0),   account);
    }

    // The facets' pure key getters, so the keys can be read before the spell enables the integrations.
    function _sllInitiateKey(address assetOut, address assetIn) internal pure returns (bytes32) {
        return ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getInitiateSwapRateLimitKey(assetOut, ETHEREUM_SPUSDT_PAU_ALM_PROXY, ETHEREUM_SPUSDT_PAU_CONTROLLER, assetIn);
    }

    function _spUsdtCompleteKey(address assetOut, address assetIn) internal pure returns (bytes32) {
        return ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getCompleteSwapRateLimitKey(assetOut, Ethereum.ALM_PROXY, assetIn);
    }

    function _spUsdtLayerZeroKey(uint32 destinationEndpointId) internal pure returns (bytes32) {
        bytes32 peer = destinationEndpointId == LZ_EID_ARBITRUM ? _toBytes32(Arbitrum.USDT_OFT) : _toBytes32(XLayer.USDT0_OFT);

        return ILayerZeroFacet(Ethereum.LAYERZERO_FACET).getTransferRateLimitKey(Ethereum.USDT_OFT, peer, destinationEndpointId, Ethereum.USDT);
    }

    function _spUsdtDepositKey() internal view returns (bytes32) {
        return IERC4626Controller(ETHEREUM_SPUSDT_PAU_CONTROLLER).erc4626_getDepositRateLimitKey(Ethereum.SUSDS, Ethereum.USDS);
    }

    function _spUsdtWithdrawKey() internal view returns (bytes32) {
        return IERC4626Controller(ETHEREUM_SPUSDT_PAU_CONTROLLER).erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS);
    }

    function _spUsdtTakeKey() internal view returns (bytes32) {
        return ISparkVaultController(ETHEREUM_SPUSDT_PAU_CONTROLLER).sparkVault_getTakeRateLimitKey(Ethereum.SPARK_VAULT_V2_SPUSDT);
    }

    function _spUsdtTransferKey() internal view returns (bytes32) {
        return ITransferAssetController(ETHEREUM_SPUSDT_PAU_CONTROLLER).transferAsset_getTransferRateLimitKey(Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdtTakeKey() internal view returns (bytes32) {
        return ISparkVaultController(ARBITRUM_SPUSDT_PAU_CONTROLLER).sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdtTransferKey() internal view returns (bytes32) {
        return ITransferAssetController(ARBITRUM_SPUSDT_PAU_CONTROLLER).transferAsset_getTransferRateLimitKey(Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdtLayerZeroKey() internal view returns (bytes32) {
        return ILayerZeroController(ARBITRUM_SPUSDT_PAU_CONTROLLER).layerZero_getTransferRateLimitKey(
            Arbitrum.USDT_OFT,
            _toBytes32(Ethereum.USDT_OFT),
            LZ_EID_ETHEREUM,
            Arbitrum.USDT0
        );
    }

    // Planner hot wallet -> Spark Planner Administered Agent -> `agent` -> `target`. The hot wallet is the same EOA on
    // Ethereum and Arbitrum.
    function _callAsAgent(
        address        plannerAgent,
        address        agent,
        address        target,
        bytes   memory data,
        uint256        value
    ) internal returns (bytes memory) {
        vm.deal(Ethereum.PLANNER_WALLET, value);

        vm.prank(Ethereum.PLANNER_WALLET);
        return IAdministeredAgentLike(plannerAgent).call{ value: value }(
            agent,
            abi.encodeCall(IAdministeredAgentLike.call, (target, data))
        );
    }

    // Mirrors `_runLayerZeroTransferE2E` for a Diamond PAU: the transfer is made through the Administered Agents.
    function _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams memory p) internal {
        chainData[p.sourceChainId].domain.selectFork();

        IRateLimits rateLimits = IRateLimits(IController(p.controller).rateLimits());

        address proxy = IController(p.controller).proxy();

        uint256 transferLimit = rateLimits.getCurrentRateLimit(p.transferKey);

        _drainLZPendingPackets(p.destinationChainId);

        chainData[p.destinationChainId].domain.selectFork();

        uint256 destinationSnapshot      = vm.snapshotState();
        uint256 destinationBalanceBefore = IERC20(p.destinationAsset).balanceOf(p.destinationReceiver);

        chainData[p.sourceChainId].domain.selectFork();

        deal(p.asset, proxy, p.amount);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = ILayerZeroController(p.controller)
            .layerZero_quoteTransfer(p.oft, p.amount, p.destinationEndpointId);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(p.oft, p.destinationEndpointId, _toBytes32(p.destinationOft)) + 1;

        _callAsAgent(
            p.plannerAgent,
            p.agent,
            p.controller,
            abi.encodeCall(ILayerZeroController.layerZero_transfer, (p.oft, p.amount, p.destinationEndpointId)),
            fee.nativeFee
        );

        assertEq(IERC20(p.asset).balanceOf(proxy), 0);

        assertEq(
            rateLimits.getCurrentRateLimit(p.transferKey),
            transferLimit == type(uint256).max ? type(uint256).max : transferLimit - p.amount
        );

        chainData[p.destinationChainId].domain.selectFork();

        if (ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(p.destinationOft, p.sourceEndpointId, _toBytes32(p.oft)) >= sentNonce) {
            console2.log("Skipping LZ destination delivery (destination fork ahead of source) for", p.oft);
        } else {
            _skipLZPendingNonces(p.destinationOft, p.sourceEndpointId, _toBytes32(p.oft), sentNonce);

            assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore);

            chainData[p.sourceChainId].domain.selectFork();

            LZBridgeTesting.relayMessagesToDestination(_getLZBridge(p.destinationChainId), true, p.oft, p.destinationOft);

            assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore + p.amount);
        }

        vm.revertToState(destinationSnapshot);

        chainData[p.sourceChainId].domain.selectFork();
    }

    function _toBytes32(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

}

contract SparkEthereum_20261203_SparklendTests is SparklendTests, SpUsdtDeployments {

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        _runPreDeploymentPayloads(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.ArbitrumOne()].domain);
    }

}

contract SparkEthereum_20261203_SpellTests is SpellTests, SpUsdtDeployments {

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        _runPreDeploymentPayloads(chainData[ChainIdUtils.Ethereum()].domain, chainData[ChainIdUtils.ArbitrumOne()].domain);
    }

    function test_ETHEREUM_sparkTreasury_buyback() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore  = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 opsMultisigBalanceBefore = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,  48_995_094.205806286854722044e18);
        assertEq(opsMultisigBalanceBefore, 552_142.342558330054342171e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore  - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
    }

}
