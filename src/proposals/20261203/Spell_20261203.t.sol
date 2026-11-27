// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { StdAssertions } from "../../../lib/forge-std/src/StdAssertions.sol";
import { Vm }            from "../../../lib/forge-std/src/Vm.sol";
import { console2 }      from "../../../lib/forge-std/src/console2.sol";

import { IERC20 }                   from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 }                 from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IAccessControl }           from "../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControlEnumerable } from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { OptionsBuilder } from "../../../lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { BeaconConfig } from "../../../lib/diamond-pau/src/libraries/BeaconConfig.sol";

import { IController }             from "../../../lib/diamond-pau/src/interfaces/IController.sol";
import { IEnumerableIntegrations } from "../../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { IERC4626Controller }       from "../../../lib/diamond-pau/src/facets/erc4626/IERC4626Controller.sol";
import { ILayerZeroController }     from "../../../lib/diamond-pau/src/facets/layer-zero/ILayerZeroController.sol";
import { ILayerZeroFacet }          from "../../../lib/diamond-pau/src/facets/layer-zero/ILayerZeroFacet.sol";
import { ISparkVaultController }    from "../../../lib/diamond-pau/src/facets/spark-vault/ISparkVaultController.sol";
import { ISwapAssetController }     from "../../../lib/diamond-pau/src/facets/swap-asset/ISwapAssetController.sol";
import { ISwapAssetFacet }          from "../../../lib/diamond-pau/src/facets/swap-asset/ISwapAssetFacet.sol";
import { ITransferAssetController } from "../../../lib/diamond-pau/src/facets/transfer-asset/ITransferAssetController.sol";

import { Ethereum as SkyEthereum } from "../../../lib/sky-pau-registry/src/Ethereum.sol";

import { Arbitrum } from "../../../lib/spark-address-registry/src/Arbitrum.sol";
import { Base }     from "../../../lib/spark-address-registry/src/Base.sol";
import { Ethereum } from "../../../lib/spark-address-registry/src/Ethereum.sol";
import { XLayer }   from "../../../lib/spark-address-registry/src/XLayer.sol";

import { IALMProxy }                           from "../../../lib/spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }                         from "../../../lib/spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ILayerZero, MessagingFee, SendParam } from "../../../lib/spark-alm-controller/src/interfaces/ILayerZero.sol";
import { ForeignController }                   from "../../../lib/spark-alm-controller/src/ForeignController.sol";
import { MainnetController }                   from "../../../lib/spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }                    from "../../../lib/spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "../../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { LZForwarder }   from "../../../lib/xchain-helpers/src/forwarders/LZForwarder.sol";

import { Bridge, BridgeType }    from "../../../lib/xchain-helpers/src/testing/Bridge.sol";
import { Domain, DomainHelpers } from "../../../lib/xchain-helpers/src/testing/Domain.sol";
import { LZBridgeTesting }       from "../../../lib/xchain-helpers/src/testing/bridges/LZBridgeTesting.sol";
import { RecordedLogs }          from "../../../lib/xchain-helpers/src/testing/utils/RecordedLogs.sol";

import { ChainIdUtils } from "../../libraries/ChainIdUtils.sol";

import { SparklendTests }           from "../../test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "../../test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "../../test-harness/SpellTests.sol";

import { IALMProxyFreezableLike, IStarGuardLike, ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function call(address target, bytes memory data) external payable returns (bytes memory result);

    function getActor(uint256 index) external view returns (address);

    function getIsActor(address account) external view returns (bool);

    function getIsAdmin(address account) external view returns (bool);

    function getIsGrantor(address account) external view returns (bool);

    function getIsRevoker(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

interface IBeamStateLike {

    function addCBeam(address cBeam) external;

    function addController(address controller) external;

    function addInitControllerActions(bytes calldata data, address controller) external returns (bytes32 key);

    function addRateLimits(address rateLimits) external;

    function cBeams(address cBeam) external view returns (uint256);

    function controllers(address controller) external view returns (uint256);

    function controllersCBeams(address controller, address cBeam) external view returns (uint256);

    function getHop(address rateLimits) external view returns (uint256);

    function getMaxChange(address rateLimits) external view returns (uint256);

    function isControllerActionEnabled(bytes32 key, address controller) external view returns (bool);

    function rateLimits(address rateLimits) external view returns (uint256);

    function rateLimitsCBeams(address rateLimits, address cBeam) external view returns (uint256);

    function setCBeamForController(address controller, address cBeam) external;

    function setCBeamForRateLimits(address rateLimits, address cBeam) external;

    function stopped() external view returns (bool);

    function wards(address usr) external view returns (uint256);

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

interface IConfiguratorLike {

    event CallControllerAction(address indexed controller, bytes data);

    event SetRateLimit(address indexed rateLimits, bytes32 indexed key, uint256 maxAmount, uint256 slope);

    function beamState() external view returns (address);

    function callControllerAction(address controller, bytes calldata data) external returns (bytes memory);

    function setRateLimit(address rateLimits, bytes32 key, uint256 maxAmount, uint256 slope) external;

    function zzz(address rateLimits, bytes32 key) external view returns (uint256);

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

contract SparkEthereum_20261203_SLLTests is SparkLiquidityLayerTests {

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

    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // Sky Ethereum PAS.
    address internal constant SKY_PAS_BEAM_STATE   = 0x1A1879E66547F90bfF87D45A5b0335950E019E02;
    address internal constant SKY_PAS_CBEAM        = 0x492aae70E59551768BAF3c7159d3f951B6ed76Fe;  // Spark Operator Multisig
    address internal constant SKY_PAS_CONFIGURATOR = 0xb7E61Df6CAb0A51E9A5dab1A7DD3f942dDe5b929;

    uint256 internal constant SKY_PAS_HOP        = 16 hours;
    uint256 internal constant SKY_PAS_MAX_CHANGE = 1.2e18;

    // X Layer -> Ethereum LayerZero bridge for Item 3 (the harness only wires Ethereum -> X Layer).
    Bridge internal xlayerToEthereumLZBridge;

    mapping(uint256 chainId => uint256 timestamp) internal forkTimestamp;

    IERC20   internal eth_usdt     = IERC20(Ethereum.USDT);
    IERC20   internal eth_usds     = IERC20(Ethereum.USDS);
    IERC4626 internal eth_susds    = IERC4626(Ethereum.SUSDS);
    IERC20   internal arb_usdt0    = IERC20(Arbitrum.USDT0);
    IERC20   internal xlayer_usdt0 = IERC20(XLayer.USDT0);

    ISparkVaultLike internal eth_spUsdt    = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);
    ISparkVaultLike internal arb_spUsdt    = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);
    ISparkVaultLike internal xlayer_spUsdt = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDT);

    IEnumerableIntegrations internal eth_sparkBeacon = IEnumerableIntegrations(Ethereum.SPARK_BEACON);

    IALMProxy         internal eth_legacy_almProxy      = IALMProxy(Ethereum.ALM_PROXY);
    MainnetController internal eth_legacy_controller    = MainnetController(Ethereum.ALM_CONTROLLER);
    ForeignController internal arb_legacy_controller    = ForeignController(Arbitrum.ALM_CONTROLLER);
    ForeignController internal xlayer_legacy_controller = ForeignController(XLayer.ALM_CONTROLLER);
    IRateLimits       internal xlayer_legacy_rateLimits = IRateLimits(XLayer.ALM_RATE_LIMITS);

    address               internal eth_sllPau_accessControls = Ethereum.SLL_PAU_ACCESS_CONTROLS;
    ISllPauControllerLike internal eth_sllPau_controller     = ISllPauControllerLike(Ethereum.SLL_PAU_CONTROLLER);
    IRateLimits           internal eth_sllPau_rateLimits     = IRateLimits(Ethereum.SLL_PAU_RATE_LIMITS);

    address                     internal eth_spUSDTPAU_accessControls = Ethereum.SPUSDT_PAU_ACCESS_CONTROLS;
    address                     internal eth_spUSDTPAU_almProxy       = Ethereum.SPUSDT_PAU_ALM_PROXY;
    IEthSpUsdtPauControllerLike internal eth_spUSDTPAU_controller     = IEthSpUsdtPauControllerLike(Ethereum.SPUSDT_PAU_CONTROLLER);
    IRateLimits                 internal eth_spUSDTPAU_rateLimits     = IRateLimits(Ethereum.SPUSDT_PAU_RATE_LIMITS);

    address                     internal arb_spUSDTPAU_accessControls = Arbitrum.SPUSDT_PAU_ACCESS_CONTROLS;
    address                     internal arb_spUSDTPAU_almProxy       = Arbitrum.SPUSDT_PAU_ALM_PROXY;
    IArbSpUsdtPauControllerLike internal arb_spUSDTPAU_controller     = IArbSpUsdtPauControllerLike(Arbitrum.SPUSDT_PAU_CONTROLLER);
    IRateLimits                 internal arb_spUSDTPAU_rateLimits     = IRateLimits(Arbitrum.SPUSDT_PAU_RATE_LIMITS);

    ICCTPControllerLike internal base_sllPau_controller = ICCTPControllerLike(Base.PAU_CONTROLLER);
    IRateLimits         internal base_sllPau_rateLimits = IRateLimits(Base.PAU_RATE_LIMITS);

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795631067;  //Nov-25-2026 06:24:27 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        _recordForkTimestamps();

        _skyCoreSpell();

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

    function _skyCoreSpell() internal {
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // Pre-requirement 9: the Sky Core spell registers SwapAssetFacet on the Sky Beacon before the Spark payload.
        vm.startPrank(Ethereum.PAUSE_PROXY);
        BeaconConfig.setSwapAssetIntegration(SkyEthereum.BEACON, SkyEthereum.SWAP_ASSET_FACET);

        // Pre-requirement 10: the Sky Core spell registers the SLL PAU in the Sky PAS BeamState, with the Spark Operator Multisig as its cBEAM.
        bytes32[] memory swapAssetIds = new bytes32[](1);
        swapAssetIds[0] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        IBeamStateLike(SKY_PAS_BEAM_STATE).addRateLimits(Ethereum.SLL_PAU_RATE_LIMITS);
        IBeamStateLike(SKY_PAS_BEAM_STATE).addController(Ethereum.SLL_PAU_CONTROLLER);
        IBeamStateLike(SKY_PAS_BEAM_STATE).addCBeam(SKY_PAS_CBEAM);
        IBeamStateLike(SKY_PAS_BEAM_STATE).setCBeamForRateLimits(Ethereum.SLL_PAU_RATE_LIMITS, SKY_PAS_CBEAM);
        IBeamStateLike(SKY_PAS_BEAM_STATE).setCBeamForController(Ethereum.SLL_PAU_CONTROLLER, SKY_PAS_CBEAM);
        IBeamStateLike(SKY_PAS_BEAM_STATE).addInitControllerActions(abi.encodeCall(IController.removeIntegrations, (swapAssetIds)), Ethereum.SLL_PAU_CONTROLLER);
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** Ethereum                                                                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertEthereumSpUsdtPauDeploymentConfig();

        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_layerZero_transferKey(LZ_EID_XLAYER), 5_000_000e6, uint256(25_000_000e6) / 1 days);

        _executeAllPayloadsAndBridges();

        _assertEthereumSpUsdtPauDeploymentConfig();

        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_layerZero_transferKey(LZ_EID_XLAYER), 10_000_000e6, uint256(100_000_000e6) / 1 days);
    }

    function test_ETHEREUM_sllPau_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertEthereumSllPauDeploymentConfig();

        // Deployment payload authorizes only the Spark Proxy as the default admin on the SLL PAU.
        _assertOnlyRoleMember(eth_sllPau_accessControls,      DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(address(eth_sllPau_rateLimits), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        _assertEthereumSllPauDeploymentConfig();

        // The spell authorizes the Sky PAS Configurator as a second admin on the SLL PAU.
        address[] memory admins = new address[](2);
        admins[0] = Ethereum.SPARK_PROXY;
        admins[1] = SKY_PAS_CONFIGURATOR;

        _assertRoleMembers(eth_sllPau_accessControls,      DEFAULT_ADMIN_ROLE, admins);
        _assertRoleMembers(address(eth_sllPau_rateLimits), DEFAULT_ADMIN_ROLE, admins);
    }

    function test_ETHEREUM_administeredAgents_deploymentConfig() external onChain(ChainIdUtils.Ethereum()) {
        _assertEthereumAgents();

        _executeAllPayloadsAndBridges();

        _assertEthereumAgents();
    }

    function test_ETHEREUM_sparkBeacon_onboardSwapAssetAndLayerZero() external onChain(ChainIdUtils.Ethereum()) {
        assertEq(eth_sparkBeacon.integrations().length, 4);

        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.CCTP_INTEGRATION).facet,           Ethereum.CCTP_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     address(0));
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     address(0));

        _assertOnlyRoleMember(Ethereum.SPARK_BEACON, DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        assertEq(eth_sparkBeacon.integrations().length, 6);

        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.CCTP_INTEGRATION).facet,           Ethereum.CCTP_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     Ethereum.SWAP_ASSET_FACET);
        assertEq(eth_sparkBeacon.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     Ethereum.LAYERZERO_FACET);

        _assertIntegration(Ethereum.SPARK_BEACON, BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
        _assertIntegration(Ethereum.SPARK_BEACON, BeaconConfig.buildLayerZeroIntegration(Ethereum.LAYERZERO_FACET));

        _assertOnlyRoleMember(Ethereum.SPARK_BEACON, DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
    }

    function test_ETHEREUM_spUsdtPau_onboardLayerZeroAndSwapAsset() external onChain(ChainIdUtils.Ethereum()) {
        assertEq(eth_spUSDTPAU_controller.integrations().length, 3); // From Deployment Payload

        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     address(0));
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     address(0));

        _executeAllPayloadsAndBridges();

        assertEq(eth_spUSDTPAU_controller.integrations().length, 5);

        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.LAYER_ZERO_INTEGRATION).facet,     Ethereum.LAYERZERO_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,     Ethereum.SWAP_ASSET_FACET);

        _assertIntegrationEnabled(address(eth_spUSDTPAU_controller), BeaconConfig.buildLayerZeroIntegration(Ethereum.LAYERZERO_FACET));
        _assertIntegrationEnabled(address(eth_spUSDTPAU_controller), BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
    }

    function test_ETHEREUM_spUsdt_takerAndSetterRoles() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 takerRole  = eth_spUsdt.TAKER_ROLE();
        bytes32 setterRole = eth_spUsdt.SETTER_ROLE();

        _assertOnlyRoleMember(address(eth_spUsdt), takerRole,          Ethereum.ALM_PROXY);
        _assertOnlyRoleMember(address(eth_spUsdt), setterRole,         Ethereum.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(eth_spUsdt), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        _assertOnlyRoleMember(address(eth_spUsdt), takerRole,          eth_spUSDTPAU_almProxy);
        _assertOnlyRoleMember(address(eth_spUsdt), setterRole,         Ethereum.SPARK_ADMINISTERED_AGENT);
        _assertOnlyRoleMember(address(eth_spUsdt), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        // Taker can take from the vault

        uint256 vaultBalance = eth_usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT);
        uint256 pauBalance   = eth_usdt.balanceOf(eth_spUSDTPAU_almProxy);

        assertEq(vaultBalance, 81_751_150.829624e6);
        assertEq(pauBalance,   0);

        // TAKER_ROLE vm.expectRevert for the Ethereum.ALM_PROXY is not asserted because the path is checked
        // in the below test where it reverts in the zero rate limit before the TAKER_ROLE ACL can be hit.

        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SPARK_ADMINISTERED_AGENT,
            address(eth_spUSDTPAU_controller),
            abi.encodeCall(ISparkVaultController.sparkVault_take, (Ethereum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(eth_usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy),         pauBalance   + 1_000_000e6);

        // Setter can set the vsr

        uint256 maxVsr = eth_spUsdt.maxVsr();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                Ethereum.ALM_PROXY_FREEZABLE,
                eth_spUsdt.SETTER_ROLE()
            )
        );

        vm.prank(Ethereum.ALM_PROXY_FREEZABLE);
        eth_spUsdt.setVsr(maxVsr);

        assertEq(eth_spUsdt.vsr(), 1.000000001319814647332759691e27);

        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SPARK_ADMINISTERED_AGENT,
            Ethereum.SPARK_VAULT_V2_SPUSDT,
            abi.encodeCall(ISparkVaultV2Like.setVsr, (maxVsr)),
            0
        );

        assertEq(eth_spUsdt.vsr(), maxVsr);
    }

    function test_ETHEREUM_spUsdtPau_layerZeroRecipients() external onChain(ChainIdUtils.Ethereum()) {
        vm.expectRevert(abi.encodeWithSignature("CallSelectorNotWired(bytes4)", ILayerZeroController.layerZero_getRecipient.selector));
        eth_spUSDTPAU_controller.layerZero_getRecipient(LZ_EID_ARBITRUM);

        _executeAllPayloadsAndBridges();

        assertEq(eth_spUSDTPAU_controller.layerZero_getRecipient(LZ_EID_ARBITRUM), _toBytes32(arb_spUSDTPAU_almProxy));
        assertEq(eth_spUSDTPAU_controller.layerZero_getRecipient(LZ_EID_XLAYER),   _toBytes32(XLayer.ALM_PROXY));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToArbitrum() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          Ethereum.PLANNER_ADMINISTERED_AGENT,
            agent:                 Ethereum.SPARK_ADMINISTERED_AGENT,
            controller:            address(eth_spUSDTPAU_controller),
            oft:                   Ethereum.USDT_OFT,
            asset:                 Ethereum.USDT,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_ARBITRUM,
            destinationChainId:    ChainIdUtils.ArbitrumOne(),
            destinationOft:        USDT0_OFT_ARBITRUM,
            destinationAsset:      USDT0_ARBITRUM,
            destinationReceiver:   arb_spUSDTPAU_almProxy,
            sourceEndpointId:      LZ_EID_ETHEREUM,
            sourceChainId:         ChainIdUtils.Ethereum(),
            transferKey:           _ethSpUsdt_layerZero_transferKey(LZ_EID_ARBITRUM)
        }));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToXLayer() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          Ethereum.PLANNER_ADMINISTERED_AGENT,
            agent:                 Ethereum.SPARK_ADMINISTERED_AGENT,
            controller:            address(eth_spUSDTPAU_controller),
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
            transferKey:           _ethSpUsdt_layerZero_transferKey(LZ_EID_XLAYER)
        }));
    }

    function test_ETHEREUM_sll_legacyRateLimitKeysZeroed() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 takeKey     = RateLimitHelpers.makeAddressKey(eth_legacy_controller.LIMIT_SPARK_VAULT_TAKE(), Ethereum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(eth_legacy_controller.LIMIT_ASSET_TRANSFER(), Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT);
        bytes32 arbitrumKey = keccak256(abi.encode(eth_legacy_controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_ARBITRUM));
        bytes32 xlayerKey   = keccak256(abi.encode(eth_legacy_controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_XLAYER));

        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey);

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, arbitrumKey, 5_000_000e6, uint256(50_000_000e6)  / 1 days);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, xlayerKey,   5_000_000e6, uint256(100_000_000e6) / 1 days);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, takeKey,     0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, arbitrumKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, xlayerKey,   0, 0);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        eth_legacy_controller.takeFromSparkVault(Ethereum.SPARK_VAULT_V2_SPUSDT, 1e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        eth_legacy_controller.transferAsset(Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT, 1e6);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        eth_legacy_controller.transferTokenLayerZero(Ethereum.USDT_OFT, 1e6, LZ_EID_ARBITRUM);

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        eth_legacy_controller.transferTokenLayerZero(Ethereum.USDT_OFT, 1e6, LZ_EID_XLAYER);
    }

    function test_ETHEREUM_spUsdtPau_susdsBacking() external onChain(ChainIdUtils.Ethereum()) {
        _warpToForkBlock(ChainIdUtils.Ethereum());

        uint256 assetsOutstanding = eth_spUsdt.assetsOutstanding();

        assertEq(assetsOutstanding, 193_040_238.777523e6);

        uint256 expectedShares = eth_susds.convertToShares(assetsOutstanding * 1e12);
        uint256 sllShares      = eth_susds.balanceOf(Ethereum.ALM_PROXY);

        assertEq(expectedShares,                              172_728_264.360389296369614933e18);
        assertEq(sllShares,                                   431_418_904.772977443647355485e18);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 0);

        _executeAllPayloadsAndBridges();

        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_susds.balanceOf(Ethereum.ALM_PROXY),     sllShares - expectedShares);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), expectedShares);

        assertEq(eth_spUsdt.assetsOutstanding(), assetsOutstanding);

        assertEq(eth_legacy_almProxy.hasRole(eth_legacy_almProxy.CONTROLLER(), Ethereum.SPARK_PROXY), false);
    }

    function test_ETHEREUM_spUsdtPau_susdsWithdrawAndDeposit() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        uint256 sharesBefore = eth_susds.balanceOf(eth_spUSDTPAU_almProxy);

        assertEq(sharesBefore,                               172_728_264.360389296369614933e18);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0);

        // Withdraw 1,000,000 USDS from sUSDS
        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SPARK_ADMINISTERED_AGENT,
            address(eth_spUSDTPAU_controller),
            abi.encodeCall(IERC4626Controller.erc4626_withdraw, (Ethereum.SUSDS, 1_000_000e18, type(uint256).max)),
            0
        );

        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), sharesBefore - eth_susds.convertToShares(1_000_000e18) - 1);  // Rounding
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  1_000_000e18);

        // Deposit the USDS back into sUSDS
        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SPARK_ADMINISTERED_AGENT,
            address(eth_spUSDTPAU_controller),
            abi.encodeCall(IERC4626Controller.erc4626_deposit, (Ethereum.SUSDS, 1_000_000e18, 0)),
            0
        );

        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  0);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), sharesBefore - 1);  // Rounding
    }

    function test_ETHEREUM_sllPau_onboarding() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 controllerRole = eth_legacy_almProxy.CONTROLLER();

        assertEq(eth_legacy_almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER),        true);
        assertEq(eth_legacy_almProxy.hasRole(controllerRole, address(eth_sllPau_controller)), false);
        assertEq(eth_legacy_almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),           false);

        assertEq(eth_sllPau_controller.integrations().length,                                0);
        assertEq(eth_sllPau_controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet, address(0));

        assertEq(IAccessControlEnumerable(eth_sllPau_accessControls).hasRole(DEFAULT_ADMIN_ROLE,      SKY_PAS_CONFIGURATOR), false);
        assertEq(IAccessControlEnumerable(address(eth_sllPau_rateLimits)).hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), false);

        // Pre-requirement 9: the SwapAsset integration comes from the Sky Beacon
        _assertIntegration(SkyEthereum.BEACON, BeaconConfig.buildSwapAssetIntegration(SkyEthereum.SWAP_ASSET_FACET));

        _executeAllPayloadsAndBridges();

        assertEq(eth_legacy_almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER),        true);
        assertEq(eth_legacy_almProxy.hasRole(controllerRole, address(eth_sllPau_controller)), true);
        assertEq(eth_legacy_almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),           false);

        // SwapAsset is the only integration.
        assertEq(eth_sllPau_controller.integrations().length, 1);

        _assertIntegrationEnabled(address(eth_sllPau_controller), BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));

        // The Sky PAS Configurator is authorized on the SLL PAU.
        assertEq(IAccessControlEnumerable(eth_sllPau_accessControls).hasRole(DEFAULT_ADMIN_ROLE,      SKY_PAS_CONFIGURATOR), true);
        assertEq(IAccessControlEnumerable(address(eth_sllPau_rateLimits)).hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), true);
    }

    function test_ETHEREUM_sllPau_swap() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        deal(Ethereum.USDT, eth_spUSDTPAU_almProxy, 1_000_000e6);
        deal(Ethereum.USDS, Ethereum.ALM_PROXY,     1_000_000e18);

        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     1_000_000e18);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     0);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_000e6);

        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)),       10_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)),       10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);

        assertEq(eth_usds.allowance(Ethereum.ALM_PROXY, eth_spUSDTPAU_almProxy), 0);

        // The Spark Liquidity Layer swaps 1,000,000 USDS for 1,000,000 USDT from the spUSDT PAU.
        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SLL_ADMINISTERED_AGENT,
            address(eth_sllPau_controller),
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (address(eth_spUSDTPAU_controller), Ethereum.USDS, Ethereum.USDT, 1_000_000e18)),
            0
        );

        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     0);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     1_000_000e6);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 1_000_000e18);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 0);

        // Each side consumed its own limit; the opposite direction was already at its maximum.
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)),       9_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)),       10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 9_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);

        assertEq(eth_usds.allowance(Ethereum.ALM_PROXY, eth_spUSDTPAU_almProxy), 0);

        // The Spark Liquidity Layer swaps the 1,000,000 USDT back for 1,000,000 USDS from the spUSDT PAU.
        _callAsAgent(
            Ethereum.ALM_RELAYER_MULTISIG,
            Ethereum.PLANNER_ADMINISTERED_AGENT,
            Ethereum.SLL_ADMINISTERED_AGENT,
            address(eth_sllPau_controller),
            abi.encodeCall(ISwapAssetController.swapAsset_initiateSwap, (address(eth_spUSDTPAU_controller), Ethereum.USDT, Ethereum.USDS, 1_000_000e6)),
            0
        );

        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     1_000_000e18);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     0);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_000e6);

        // Each side consumed its own limit and recharged the opposite direction by the same amount.
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)),       10_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)),       9_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 9_000_000e18);

        assertEq(eth_usdt.allowance(Ethereum.ALM_PROXY, eth_spUSDTPAU_almProxy), 0);
    }

    function test_ETHEREUM_sllPau_grantPASConfigurator() external onChain(ChainIdUtils.Ethereum()) {
        IAccessControlEnumerable accessControls = IAccessControlEnumerable(eth_sllPau_accessControls);
        IAccessControlEnumerable rateLimits     = IAccessControlEnumerable(address(eth_sllPau_rateLimits));

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),            1);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), false);

        assertEq(rateLimits.getRoleMemberCount(DEFAULT_ADMIN_ROLE),            1);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), false);

        _executeAllPayloadsAndBridges();

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),            2);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), true);

        assertEq(rateLimits.getRoleMemberCount(DEFAULT_ADMIN_ROLE),            2);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, SKY_PAS_CONFIGURATOR), true);
    }

    function test_ETHEREUM_pasConfigurator_state() external onChain(ChainIdUtils.Ethereum()) {
        IBeamStateLike beamState = IBeamStateLike(SKY_PAS_BEAM_STATE);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        assertEq(IConfiguratorLike(SKY_PAS_CONFIGURATOR).beamState(), SKY_PAS_BEAM_STATE);

        assertEq(beamState.stopped(),                   false);
        assertEq(beamState.wards(Ethereum.PAUSE_PROXY), 1);

        // Pre-requirement 10: the SLL PAU is registered with the Spark Operator Multisig as its cBEAM,
        // and removing the SwapAsset integration is its only pre-approved controller action.
        assertEq(beamState.rateLimits(address(eth_sllPau_rateLimits)),  1);
        assertEq(beamState.controllers(address(eth_sllPau_controller)), 1);
        assertEq(beamState.cBeams(SKY_PAS_CBEAM),                       1);

        assertEq(beamState.rateLimitsCBeams(address(eth_sllPau_rateLimits), SKY_PAS_CBEAM),  1);
        assertEq(beamState.controllersCBeams(address(eth_sllPau_controller), SKY_PAS_CBEAM), 1);

        assertEq(beamState.isControllerActionEnabled(keccak256(abi.encodeCall(eth_sllPau_controller.removeIntegrations, (ids))), address(eth_sllPau_controller)), true);
        assertEq(beamState.isControllerActionEnabled(keccak256(abi.encodeCall(eth_sllPau_controller.updateIntegrations, (ids))), address(eth_sllPau_controller)), false);

        // The BeamState defaults apply to the SLL PAU rate limits.
        assertEq(beamState.getHop(address(eth_sllPau_rateLimits)),       SKY_PAS_HOP);
        assertEq(beamState.getMaxChange(address(eth_sllPau_rateLimits)), SKY_PAS_MAX_CHANGE);
    }

    function test_ETHEREUM_pasConfigurator_setRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        IConfiguratorLike configurator = IConfiguratorLike(SKY_PAS_CONFIGURATOR);

        address rateLimits = address(eth_sllPau_rateLimits);
        bytes32 key        = _ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT);

        // The Sky PAS Configurator is not admin on the SLL PAU RateLimits yet, so the rate limits reject it.
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            SKY_PAS_CONFIGURATOR,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(rateLimits, key, 10_000_000e18, uint256(200_000_000e18) / 1 days);

        // Only the cBEAM can go through the Configurator.
        vm.expectRevert("Configurator/not-authorized-ratelimits-cBeam");
        configurator.setRateLimit(rateLimits, key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        // The cBEAM can only set rate limits for keys that are already set.
        vm.expectRevert("Configurator/exceeds-max-amount");
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, keccak256("NEW_KEY"), 1, 0);

        assertEq(configurator.zzz(rateLimits, key), 0);

        // Decreases apply immediately and do not consume the hop.
        vm.expectEmit(SKY_PAS_CONFIGURATOR);
        emit IConfiguratorLike.SetRateLimit(rateLimits, key, 5_000_000e18, uint256(100_000_000e18) / 1 days);
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        IRateLimits.RateLimitData memory data = eth_sllPau_rateLimits.getRateLimitData(key);

        assertEq(data.maxAmount, 5_000_000e18);
        assertEq(data.slope,     uint256(100_000_000e18) / 1 days);

        assertEq(configurator.zzz(rateLimits, key), 0);

        // Increases are capped at maxChange (1.2x) of the current values.
        uint256 maxAmountCeiling = 5_000_000e18 * SKY_PAS_MAX_CHANGE / 1e18;
        uint256 slopeCeiling     = uint256(100_000_000e18) / 1 days * SKY_PAS_MAX_CHANGE / 1e18;

        vm.expectRevert("Configurator/exceeds-max-amount");
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling + 1, slopeCeiling);

        vm.expectRevert("Configurator/exceeds-max-slope");
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling, slopeCeiling + 1);

        // The first increase is allowed right away (the hop timer starts at 0).
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling, slopeCeiling);

        _assertRateLimit(rateLimits, key, 6_000_000e18, slopeCeiling);

        assertEq(configurator.zzz(rateLimits, key), block.timestamp);

        // The next increase has to wait for the hop.
        vm.expectRevert("Configurator/increment-too-soon");
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling + 1, slopeCeiling);

        skip(SKY_PAS_HOP - 1);

        vm.expectRevert("Configurator/increment-too-soon");
        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling + 1, slopeCeiling);

        skip(1);

        vm.prank(SKY_PAS_CBEAM);
        configurator.setRateLimit(rateLimits, key, maxAmountCeiling + 1, slopeCeiling);

        _assertRateLimit(rateLimits, key, 6_000_000e18 + 1, slopeCeiling);

        assertEq(configurator.zzz(rateLimits, key), block.timestamp);
    }

    function test_ETHEREUM_pasConfigurator_callControllerAction() external onChain(ChainIdUtils.Ethereum()) {
        IConfiguratorLike configurator = IConfiguratorLike(SKY_PAS_CONFIGURATOR);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        // The only pre-approved action is removing the SwapAsset integration from the SLL PAU controller (emergency stop).
        bytes memory removeSwapAsset = abi.encodeCall(eth_sllPau_controller.removeIntegrations, (ids));

        // The Sky PAS Configurator is not admin on the SLL PAU AccessControls yet, so the controller rejects it.
        vm.expectRevert("Configurator/call-failed");
        vm.prank(SKY_PAS_CBEAM);
        configurator.callControllerAction(address(eth_sllPau_controller), removeSwapAsset);

        _executeAllPayloadsAndBridges();

        assertEq(eth_sllPau_controller.integrations().length, 1);

        _assertIntegrationEnabled(address(eth_sllPau_controller), BeaconConfig.buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));

        assertEq(eth_sllPau_controller.getDispatch(ISwapAssetController.swapAsset_initiateSwap.selector).facet, Ethereum.SWAP_ASSET_FACET);

        // Only the cBEAM can call the controller action.
        vm.expectRevert("Configurator/not-authorized-controller-cBeam");
        configurator.callControllerAction(address(eth_sllPau_controller), removeSwapAsset);

        // Only the pre-approved action can be called by the cBEAM.
        vm.expectRevert("Configurator/not-valid-data");
        vm.prank(SKY_PAS_CBEAM);
        configurator.callControllerAction(address(eth_sllPau_controller), abi.encodeCall(eth_sllPau_controller.updateIntegrations, (ids)));

        vm.expectEmit(SKY_PAS_CONFIGURATOR);
        emit IConfiguratorLike.CallControllerAction(address(eth_sllPau_controller), removeSwapAsset);
        vm.prank(SKY_PAS_CBEAM);
        configurator.callControllerAction(address(eth_sllPau_controller), removeSwapAsset);

        assertEq(eth_sllPau_controller.integrations().length,                                                   0);
        assertEq(eth_sllPau_controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).facet,                    address(0));
        assertEq(eth_sllPau_controller.getConfig(BeaconConfig.SWAP_ASSET_INTEGRATION).wires.length,             0);
        assertEq(eth_sllPau_controller.getDispatch(ISwapAssetController.swapAsset_initiateSwap.selector).facet, address(0));
    }

    function test_ETHEREUM_payloadExecution() external onChain(ChainIdUtils.Ethereum()) {
        uint256 assetsOutstanding = eth_spUsdt.assetsOutstanding();
        uint256 sllSusdsShares    = eth_susds.balanceOf(Ethereum.ALM_PROXY);

        assertEq(assetsOutstanding, 193_040_238.777523e6);
        assertEq(sllSusdsShares,    431_418_904.772977443647355485e18);

        // Prank as the ALM Relayer Multisig and redeem all of the SLL's sUSDS shares.
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        MainnetController(Ethereum.ALM_CONTROLLER).redeemERC4626(Ethereum.SUSDS, sllSusdsShares, 0);

        assertEq(eth_susds.balanceOf(Ethereum.ALM_PROXY), 0);

        // Execute the mainnet payload and expect it to revert because there is no sUSDS shares.
        address payloadAddress = chainData[ChainIdUtils.Ethereum()].payload;

        uint256 bytecodeSize = payloadAddress.code.length;

        bytes32 bytecodeHash;

        assembly {
            let ptr := mload(0x40)

            extcodecopy(payloadAddress, ptr, 0, bytecodeSize)
            bytecodeHash := keccak256(ptr, bytecodeSize)
        }

        vm.prank(Ethereum.PAUSE_PROXY);
        IStarGuardLike(Ethereum.SPARK_STAR_GUARD).plot({
            addr_ : payloadAddress,
            tag_  : bytecodeHash
        });

        vm.mockCall(
            payloadAddress,
            abi.encodeWithSelector(SparkPayloadEthereum.isExecutable.selector),
            abi.encode(true)
        );

        vm.expectRevert(abi.encode("SubProxy/delegatecall-error"));
        IStarGuardLike(Ethereum.SPARK_STAR_GUARD).exec();

        // Prank as the ALM Relayer Multisig and deposit all USDS into sUSDS.
        vm.startPrank(Ethereum.ALM_RELAYER_MULTISIG);
        MainnetController(Ethereum.ALM_CONTROLLER).depositERC4626(Ethereum.SUSDS, eth_usds.balanceOf(Ethereum.ALM_PROXY), 0);
        vm.stopPrank();

        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),      0);
        assertEq(eth_susds.balanceOf(Ethereum.ALM_PROXY),     431_418_904.772977443647355484e18);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 0);

        // Execute the mainnet payload it succeeds.
        address payload = IStarGuardLike(Ethereum.SPARK_STAR_GUARD).exec();

        assertEq(payload, payloadAddress);

        assertEq(eth_susds.balanceOf(Ethereum.ALM_PROXY),     258_690_640.412588147277740551e18);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 172_728_264.360389296369614933e18);
    }

    /**********************************************************************************************/
    /*** Arbitrum                                                                               ***/
    /**********************************************************************************************/

    function test_ARBITRUM_spUsdtPau_deploymentConfig() external onChain(ChainIdUtils.ArbitrumOne()) {
        _assertArbitrumSpUsdtPauDeploymentConfig();

        _executeAllPayloadsAndBridges();

        _assertArbitrumSpUsdtPauDeploymentConfig();
    }

    function test_ARBITRUM_pauAdministeredAgent_actors() external onChain(ChainIdUtils.ArbitrumOne()) {
        IAdministeredAgentLike pauAdministeredAgent = IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT);

        assertEq(pauAdministeredAgent.actorCount(), 2);
        assertEq(pauAdministeredAgent.getActor(0),  Arbitrum.ALM_RELAYER_MULTISIG);
        assertEq(pauAdministeredAgent.getActor(1),  Arbitrum.PLANNER_WALLET);

        _executeAllPayloadsAndBridges();

        assertEq(pauAdministeredAgent.actorCount(), 1);
        assertEq(pauAdministeredAgent.getActor(0),  Arbitrum.PLANNER_ADMINISTERED_AGENT);
    }

    function test_ARBITRUM_spUsdt_roles() external onChain(ChainIdUtils.ArbitrumOne()) {
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        bytes32 takerRole  = arb_spUsdt.TAKER_ROLE();
        bytes32 setterRole = arb_spUsdt.SETTER_ROLE();

        _assertOnlyRoleMember(address(arb_spUsdt), takerRole,          Arbitrum.ALM_PROXY);
        _assertOnlyRoleMember(address(arb_spUsdt), setterRole,         Arbitrum.ALM_PROXY_FREEZABLE);
        _assertOnlyRoleMember(address(arb_spUsdt), DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        uint256 vaultBalance = arb_usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);
        uint256 totalAssets  = arb_spUsdt.totalAssets();

        assertEq(arb_usdt0.balanceOf(Arbitrum.ALM_PROXY),     0);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);

        _executeAllPayloadsAndBridges();

        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        _assertOnlyRoleMember(address(arb_spUsdt), takerRole,          arb_spUSDTPAU_almProxy);
        _assertOnlyRoleMember(address(arb_spUsdt), setterRole,         Arbitrum.SPARK_ADMINISTERED_AGENT);
        _assertOnlyRoleMember(address(arb_spUsdt), DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        // No funds move.
        assertEq(arb_usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(arb_usdt0.balanceOf(Arbitrum.ALM_PROXY),             0);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy),         0);

        assertEq(arb_spUsdt.totalAssets(), totalAssets);

        // Setter can set the vsr

        uint256 maxVsr = arb_spUsdt.maxVsr();

        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                Arbitrum.ALM_PROXY_FREEZABLE,
                arb_spUsdt.SETTER_ROLE()
            )
        );
        vm.prank(Arbitrum.ALM_PROXY_FREEZABLE);
        arb_spUsdt.setVsr(maxVsr);

        _callAsAgent(
            Arbitrum.ALM_RELAYER_MULTISIG,
            Arbitrum.PLANNER_ADMINISTERED_AGENT,
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            Arbitrum.SPARK_VAULT_V2_SPUSDT,
            abi.encodeCall(ISparkVaultV2Like.setVsr, (maxVsr)),
            0
        );

        assertEq(arb_spUsdt.vsr(), maxVsr);
    }

    function test_ARBITRUM_spUsdtPau_takeAndTransfer() external onChain(ChainIdUtils.ArbitrumOne()) {
        _executeAllPayloadsAndBridges();

        uint256 vaultBalance = arb_usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        assertGe(vaultBalance, 1_000_000e6);

        _callAsAgent(
            Arbitrum.ALM_RELAYER_MULTISIG,
            Arbitrum.PLANNER_ADMINISTERED_AGENT,
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            address(arb_spUSDTPAU_controller),
            abi.encodeCall(ISparkVaultController.sparkVault_take, (Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(arb_usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy),         1_000_000e6);

        _callAsAgent(
            Arbitrum.ALM_RELAYER_MULTISIG,
            Arbitrum.PLANNER_ADMINISTERED_AGENT,
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            address(arb_spUSDTPAU_controller),
            abi.encodeCall(ITransferAssetController.transferAsset_transfer, (Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6)),
            0
        );

        assertEq(arb_usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy),         0);
    }

    function test_ARBITRUM_spUsdtPau_layerZeroTransferToEthereum() external onChain(ChainIdUtils.ArbitrumOne()) {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            plannerAgent:          Arbitrum.PLANNER_ADMINISTERED_AGENT,
            agent:                 Arbitrum.SPARK_ADMINISTERED_AGENT,
            controller:            address(arb_spUSDTPAU_controller),
            oft:                   Arbitrum.USDT_OFT,
            asset:                 Arbitrum.USDT0,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_ETHEREUM,
            destinationChainId:    ChainIdUtils.Ethereum(),
            destinationOft:        USDT_OFT,
            destinationAsset:      Ethereum.USDT,
            destinationReceiver:   eth_spUSDTPAU_almProxy,
            sourceEndpointId:      LZ_EID_ARBITRUM,
            sourceChainId:         ChainIdUtils.ArbitrumOne(),
            transferKey:           _arbSpUsdt_layerZero_transferKey()
        }));
    }

    function test_ARBITRUM_sll_spUsdtRateLimitsZeroed() external onChain(ChainIdUtils.ArbitrumOne()) {
        bytes32 takeKey      = RateLimitHelpers.makeAddressKey(arb_legacy_controller.LIMIT_SPARK_VAULT_TAKE(), Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey  = RateLimitHelpers.makeAddressAddressKey(arb_legacy_controller.LIMIT_ASSET_TRANSFER(), Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 layerZeroKey = keccak256(abi.encode(arb_legacy_controller.LIMIT_LAYERZERO_TRANSFER(), Arbitrum.USDT_OFT, LZ_EID_ETHEREUM));

        assertEq(takeKey,      0x848f12eb0a19b9a33294615f6ba284a2f74a1d98d218fec1ce52f19e106c9ac2);
        assertEq(transferKey,  0xa55538975929472a1a221101825aabfc029a2d978dc641996bb2804531e2b200);
        assertEq(layerZeroKey, 0x23f1cd7ca8ed176a38e51e824f90a46b2fe2bd4257f06fc61ab930ecd67fea64);

        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, takeKey);
        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, transferKey);
        _assertUnlimitedRateLimit(Arbitrum.ALM_RATE_LIMITS, layerZeroKey);

        assertEq(arb_legacy_controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, takeKey,      0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, transferKey,  0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, layerZeroKey, 0, 0);

        // The legacy recipient is left in place; its route has no limit.
        assertEq(arb_legacy_controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        arb_legacy_controller.takeFromSparkVault(Arbitrum.SPARK_VAULT_V2_SPUSDT, 1e6);
    }

    /**********************************************************************************************/
    /*** X Layer                                                                                ***/
    /**********************************************************************************************/

    function test_XLAYER_sll_layerZeroRecipient() external onChain(ChainIdUtils.XLayer()) {
        assertEq(xlayer_legacy_controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(Ethereum.ALM_PROXY));

        _executeAllPayloadsAndBridges();

        assertEq(xlayer_legacy_controller.layerZeroRecipients(LZ_EID_ETHEREUM), _toBytes32(eth_spUSDTPAU_almProxy));

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 destinationSnapshot = vm.snapshotState();

        uint256 destinationBalanceBefore = eth_usdt.balanceOf(eth_spUSDTPAU_almProxy);

        assertEq(destinationBalanceBefore, 0);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        deal(XLayer.USDT0, XLayer.ALM_PROXY, 1_000_000e6);

        deal(XLayer.ALM_RELAYER_MULTISIG, 1 ether);

        SendParam memory sendParams = SendParam({
            dstEid       : LZ_EID_ETHEREUM,
            to           : _toBytes32(eth_spUSDTPAU_almProxy),
            amountLD     : 1_000_000e6,
            minAmountLD  : 1_000_000e6,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });
        MessagingFee memory fee = ILayerZero(USDT0_OFT_XLAYER).quoteSend(sendParams, false);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT_XLAYER).outboundNonce(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, _toBytes32(USDT_OFT)) + 1;

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayer_legacy_controller.transferTokenLayerZero{ value: fee.nativeFee }(USDT0_OFT_XLAYER, 1_000_000e6, LZ_EID_ETHEREUM);

        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        _skipLZPendingNonces(USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER), sentNonce);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), destinationBalanceBefore);

        // Relay messages to destination chain.

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(xlayerToEthereumLZBridge, true, USDT0_OFT_XLAYER, USDT_OFT);

        // The USDT0 lands in the Ethereum spUSDT PAU ALM Proxy.

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), destinationBalanceBefore + 1_000_000e6);

        vm.revertToState(destinationSnapshot);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
    }

    /**********************************************************************************************/
    /*** Base                                                                                   ***/
    /**********************************************************************************************/

    function test_BASE_sll_pauCctpV2_rateLimit() external onChain(ChainIdUtils.Base()) {
        bytes32 domainKey    = base_sllPau_controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        bytes32 aggregateKey = base_sllPau_controller.cctp_toCCTPRateLimitKey();

        _assertRateLimit(Base.PAU_RATE_LIMITS, domainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(address(base_sllPau_rateLimits), aggregateKey);

        ( bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate ) = base_sllPau_controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     _toBytes32(Ethereum.ALM_PROXY));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(address(base_sllPau_rateLimits), domainKey, 25_000_000e6, uint256(100_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(Base.PAU_RATE_LIMITS, aggregateKey);

        ( recipient, minFeeCapRate, maxFeeCapRate ) = base_sllPau_controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

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
            address(base_sllPau_controller),
            abi.encodeCall(ICCTPControllerLike.cctp_transfer, (25_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        // The full maximum reaches the Ethereum Spark Liquidity Layer ALM Proxy.
        _bridgeUSDCToMainnet_pau(25_000_000e6, ChainIdUtils.Base(), address(base_sllPau_controller));
    }

    /**********************************************************************************************/
    /*** E2E                                                                                    ***/
    /**********************************************************************************************/

    // The flow needs the spell: it onboards LayerZero and SwapAsset, moves TAKER to the spUSDT PAUs, adds the SLL PAU
    // controller to the SLL ALMProxy and transfers the sUSDS backing to the Ethereum spUSDT PAU.
    function test_E2E_spUsdtPau_ethereumArbitrumXLayerFullFlow() external override {
        _executeAllPayloadsAndBridges();

        _runSpUsdtPauE2E();
    }

    function test_E2E_spUsdtPau_ethereumArbitrumXLayerFullFlow_monolith() external {
        Domain memory mainnet  = chainData[ChainIdUtils.Ethereum()].domain;
        Domain memory arbitrum = chainData[ChainIdUtils.ArbitrumOne()].domain;
        Domain memory xlayer   = chainData[ChainIdUtils.XLayer()].domain;

        address user = makeAddr("user");

        // Execute the spell: onboards LayerZero and SwapAsset, moves TAKER to the spUSDT PAUs, adds the SLL PAU
        // controller to the SLL ALMProxy and transfers the sUSDS backing to the Ethereum spUSDT PAU.

        _warpToForkBlock(ChainIdUtils.Ethereum());

        _executeAllPayloadsAndBridges();

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        // The SLL ALMProxy needs idle USDS and USDT to complete the swaps.
        deal(Ethereum.USDS, Ethereum.ALM_PROXY, 3_000_000e18);
        deal(Ethereum.USDT, Ethereum.ALM_PROXY, 3_000_000e6);

        deal(Ethereum.USDT, user, 1_000_000e6);

        vm.deal(Ethereum.ALM_RELAYER_MULTISIG, 1 ether);  // For LayerZero fees

        arbitrum.selectFork();
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        deal(Arbitrum.USDT0, user, 1_000_000e6);

        vm.deal(Arbitrum.ALM_RELAYER_MULTISIG, 1 ether);  // For LayerZero fees

        // Discard stale Ethereum -> Arbitrum packets so only this flow's messages are relayed.
        _drainLZPendingPackets(ChainIdUtils.ArbitrumOne());

        xlayer.selectFork();
        _warpToForkBlock(ChainIdUtils.XLayer());

        deal(XLayer.USDT0, user, 1_000_000e6);

        vm.deal(XLayer.ALM_RELAYER_MULTISIG, 1 ether);  // For LayerZero fees

        // Discard stale Ethereum -> X Layer packets so only this flow's messages are relayed.
        _drainLZPendingPackets(ChainIdUtils.XLayer());

        // Step 1: Spark Vaults agents (planner agent) set the Ethereum and Arbitrum spUSDT VSR to 3% and the X Layer SLL
        //         relayer (ALM Relayer Multisig) sets the X Layer spUSDT VSR to 3% using the ALMProxyFreezable, below
        //         the sUSDS rate so the strategy covers what the users are owed.

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_spUsdt.vsr(), 1.000000001319814647332759691e27);  // 4.25% APY

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (address(eth_spUsdt), abi.encodeCall(ISparkVaultV2Like.setVsr, (THREE_PCT_VSR)))
            )
        );

        assertEq(eth_spUsdt.vsr(), THREE_PCT_VSR);

        arbitrum.selectFork();
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        assertEq(arb_spUsdt.vsr(), 1.000000001319814647332759691e27);  // 4.25% APY

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Arbitrum.PLANNER_ADMINISTERED_AGENT).call(
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (address(arb_spUsdt), abi.encodeCall(ISparkVaultV2Like.setVsr, (THREE_PCT_VSR)))
            )
        );

        assertEq(arb_spUsdt.vsr(), THREE_PCT_VSR);

        xlayer.selectFork();
        _warpToForkBlock(ChainIdUtils.XLayer());

        assertEq(xlayer_spUsdt.vsr(), 1.000000001319814647332759691e27);  // 4.25% APY

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        IALMProxyFreezableLike(XLayer.ALM_PROXY_FREEZABLE).doCall(
            address(xlayer_spUsdt),
            abi.encodeCall(ISparkVaultV2Like.setVsr, (THREE_PCT_VSR))
        );

        assertEq(xlayer_spUsdt.vsr(), THREE_PCT_VSR);

        // Step 2: User deposits 1_000_000e6 USDT to the Ethereum spUSDT vault

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_usdt.balanceOf(user),                1_000_000e6);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)), 81_751_150.829624e6);

        assertEq(eth_spUsdt.totalAssets(),   274_791_389.607147e6);
        assertEq(eth_spUsdt.totalSupply(),   264_727_444.217203e6);
        assertEq(eth_spUsdt.balanceOf(user), 0);

        vm.startPrank(user);
        IUSDTLike(Ethereum.USDT).approve(address(eth_spUsdt), 1_000_000e6);
        eth_spUsdt.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(eth_usdt.balanceOf(user),                0);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)), 82_751_150.829624e6);

        assertEq(eth_spUsdt.totalAssets(), 275_791_389.607147e6);
        assertEq(eth_spUsdt.totalSupply(), 265_690_820.269835e6);

        assertEq(eth_spUsdt.balanceOf(user), 963_376.052632e6);

        // Step 3: User deposits 1_000_000e6 USDT0 to the Arbitrum spUSDT vault

        arbitrum.selectFork();
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        assertEq(arb_usdt0.balanceOf(user),                1_000_000e6);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)), 1_058_239.025688e6);

        assertEq(arb_spUsdt.totalAssets(),   1_060_411.644530e6);
        assertEq(arb_spUsdt.totalSupply(),   1_047_372.751360e6);
        assertEq(arb_spUsdt.balanceOf(user), 0);

        vm.startPrank(user);
        IUSDTLike(Arbitrum.USDT0).approve(address(arb_spUsdt), 1_000_000e6);
        arb_spUsdt.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(arb_usdt0.balanceOf(user),                0);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)), 2_058_239.025688e6);

        assertEq(arb_spUsdt.totalAssets(), 2_060_411.644530e6);
        assertEq(arb_spUsdt.totalSupply(), 2_035_076.683849e6);

        assertEq(arb_spUsdt.balanceOf(user), 987_703.932489e6);

        // Step 4: User deposits 1_000_000e6 USDT0 to the X Layer spUSDT vault

        xlayer.selectFork();
        _warpToForkBlock(ChainIdUtils.XLayer());

        assertEq(xlayer_usdt0.balanceOf(user),                   1_000_000e6);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 4_762_342.392302e6);

        assertEq(xlayer_spUsdt.totalAssets(),   4_762_686.744768e6);
        assertEq(xlayer_spUsdt.totalSupply(),   4_706_288.281059e6);
        assertEq(xlayer_spUsdt.balanceOf(user), 0);

        vm.startPrank(user);
        IUSDTLike(XLayer.USDT0).approve(address(xlayer_spUsdt), 1_000_000e6);
        xlayer_spUsdt.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(xlayer_usdt0.balanceOf(user),                   0);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 5_762_342.392302e6);

        assertEq(xlayer_spUsdt.totalAssets(), 5_762_686.744767e6);
        assertEq(xlayer_spUsdt.totalSupply(), 5_694_446.548286e6);

        assertEq(xlayer_spUsdt.balanceOf(user), 988_158.267227e6);

        // Step 5: Ethereum Spark Vaults agent (planner agent) takes 1_000_000e6 USDT out of the Ethereum spUSDT vault

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_sparkVault_takeKey()), 10_000_000e6);

        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)),    82_751_150.829624e6);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 0);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(ISparkVaultController.sparkVault_take, (address(eth_spUsdt), 1_000_000e6))
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_sparkVault_takeKey()), 9_000_000e6);

        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)),    81_751_150.829624e6);
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_000e6);

        // Taking moves idle liquidity out, it does not change the vault's accounting.
        assertEq(eth_spUsdt.totalAssets(), 275_791_389.607147e6);
        assertEq(eth_spUsdt.totalSupply(), 265_690_820.269835e6);

        // Step 6: Arbitrum Spark Vaults agent (planner agent) takes 1_000_000e6 USDT0 out of the Arbitrum spUSDT vault

        arbitrum.selectFork();
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_sparkVault_takeKey()), 10_000_000e6);

        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)),    2_058_239.025688e6);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Arbitrum.PLANNER_ADMINISTERED_AGENT).call(
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(arb_spUSDTPAU_controller),
                    abi.encodeCall(ISparkVaultController.sparkVault_take, (address(arb_spUsdt), 1_000_000e6))
                )
            )
        );

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_sparkVault_takeKey()), 9_000_000e6);

        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)),    1_058_239.025688e6);
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 1_000_000e6);

        assertEq(arb_spUsdt.totalAssets(), 2_060_411.644530e6);
        assertEq(arb_spUsdt.totalSupply(), 2_035_076.683849e6);

        // Step 7: Arbitrum Spark Vaults agent (planner agent) bridges 1_000_000e6 USDT0 to the Ethereum spUSDT PAU using
        //         LayerZeroFacet

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_layerZero_transferKey()), 5_000_000e6);

        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 1_000_000e6);
        assertEq(arb_usdt0.totalSupply(),                     1_102_839_331.550136e6);

        ( , ILayerZeroFacet.MessagingFee memory fee ) = arb_spUSDTPAU_controller
            .layerZero_quoteTransfer(Arbitrum.USDT_OFT, 1_000_000e6, LZ_EID_ETHEREUM);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)) + 1;

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Arbitrum.PLANNER_ADMINISTERED_AGENT).call{ value: fee.nativeFee }(
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(arb_spUSDTPAU_controller),
                    abi.encodeCall(ILayerZeroController.layerZero_transfer, (Arbitrum.USDT_OFT, 1_000_000e6, LZ_EID_ETHEREUM))
                )
            )
        );

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_layerZero_transferKey()), 4_000_000e6);

        // USDT0 is burned on Arbitrum.
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);
        assertEq(arb_usdt0.totalSupply(),                     1_101_839_331.550136e6);

        // Step 8: Relay the message to Ethereum

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_000e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_719_462_485.408440e6);

        // The message can only be delivered if the Ethereum fork is not ahead of the Arbitrum fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT)), sentNonce);

        _skipLZPendingNonces(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT), sentNonce);

        LZBridgeTesting.relayMessagesToSource(_getLZBridge(ChainIdUtils.ArbitrumOne()), true, Arbitrum.USDT_OFT, Ethereum.USDT_OFT);

        _warpToForkBlock(ChainIdUtils.Ethereum());

        // USDT is released from the OFT adapter on Ethereum.
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 2_000_000e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_718_462_485.408440e6);

        // Step 9: X Layer SLL relayer (ALM Relayer Multisig) takes 1_000_000e6 USDT0 out of the X Layer spUSDT vault
        //         using the ForeignController

        xlayer.selectFork();
        _warpToForkBlock(ChainIdUtils.XLayer());

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_sparkVault_takeKey()), type(uint256).max);

        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 5_762_342.392302e6);
        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY),       2_828.911808e6);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayer_legacy_controller.takeFromSparkVault(address(xlayer_spUsdt), 1_000_000e6);

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_sparkVault_takeKey()), type(uint256).max);

        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 4_762_342.392302e6);
        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY),       1_002_828.911808e6);

        // Taking moves idle liquidity out, it does not change the vault's accounting.
        assertEq(xlayer_spUsdt.totalAssets(), 5_762_686.744767e6);
        assertEq(xlayer_spUsdt.totalSupply(), 5_694_446.548286e6);

        // Step 10: X Layer SLL relayer (ALM Relayer Multisig) bridges 1_000_000e6 USDT0 to the Ethereum spUSDT PAU
        //          using the ForeignController

        // The Arbitrum -> Ethereum packet is already relayed, discard it so only this flow's X Layer message is relayed.
        _drainLZPendingPacketsToSource(ChainIdUtils.XLayer());

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_layerZero_transferKey()), type(uint256).max);

        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 1_002_828.911808e6);
        assertEq(xlayer_usdt0.totalSupply(),               142_568_626.357877e6);

        uint256 xlayerFee = _xlayerSll_layerZero_quoteTransfer(1_000_000e6);

        sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)) + 1;

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayer_legacy_controller.transferTokenLayerZero{ value: xlayerFee }(USDT0_OFT_XLAYER, 1_000_000e6, LZ_EID_ETHEREUM);

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_layerZero_transferKey()), type(uint256).max);

        // USDT0 is burned on X Layer.
        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 2_828.911808e6);
        assertEq(xlayer_usdt0.totalSupply(),               141_568_626.357877e6);

        // Step 11: Relay the message to Ethereum

        mainnet.selectFork();
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 2_000_000e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_718_462_485.408440e6);

        // The message can only be delivered if the Ethereum fork is not ahead of the X Layer fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(Ethereum.USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER)), sentNonce);

        _skipLZPendingNonces(Ethereum.USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER), sentNonce);

        LZBridgeTesting.relayMessagesToSource(_getLZBridge(ChainIdUtils.XLayer()), true, USDT0_OFT_XLAYER, Ethereum.USDT_OFT);

        _warpToForkBlock(ChainIdUtils.Ethereum());

        // USDT is released from the OFT adapter on Ethereum.
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 3_000_000e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_717_462_485.408440e6);

        // Step 12: SLL agent (planner agent) initiates a swap on the SLL PAU of 3_000_000e18 USDS for 3_000_000e6 USDT,
        //          completed by the spUSDT PAU using SwapAssetFacet

        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 3_000_000e6);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     3_000_000e6);
        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     3_000_000e18);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SLL_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_sllPau_controller),
                    abi.encodeCall(
                        ISwapAssetController.swapAsset_initiateSwap,
                        (address(eth_spUSDTPAU_controller), Ethereum.USDS, Ethereum.USDT, 3_000_000e18)
                    )
                )
            )
        );

        // The reverse direction keys increase, already at max so they stay at max.
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)), 7_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 7_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 0);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 3_000_000e18);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     6_000_000e6);
        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     0);

        // Step 13: Ethereum Spark Vaults agent (planner agent) deposits 3_000_000e18 USDS to sUSDS using ERC4626Facet

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_depositKey()),  type(uint256).max);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_withdrawKey()), type(uint256).max);

        // The spUSDT PAU already holds the sUSDS backing transferred by the spell.
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  3_000_000e18);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 172_728_264.360389296369614933e18);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(
                        IERC4626Controller.erc4626_deposit,
                        (Ethereum.SUSDS, 3_000_000e18, 2_684_335.640914591022095658e18)
                    )
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_depositKey()),  type(uint256).max);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_withdrawKey()), type(uint256).max);

        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  0);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 172_728_264.360389296369614933e18 + 2_684_335.640914591022095658e18);

        assertEq(eth_susds.convertToAssets(2_684_335.640914591022095658e18), 3_000_000e18 - 1);  // Rounding

        // Step 14: Skip 1 day on Ethereum, Arbitrum and X Layer to let sUSDS and all spUSDT vaults accrue yield. A fork
        //          switch does not keep a fork's warped timestamp, so each chain's timestamp is re-applied on every
        //          switch.

        skip(1 days);

        uint256 ethTimestamp = block.timestamp;

        arbitrum.selectFork();
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        skip(1 days);

        uint256 arbTimestamp = block.timestamp;

        assertEq(arb_spUsdt.convertToAssets(987_703.932489e6), 1_000_080.986298e6);  // Interest owed to the user on Arbitrum

        xlayer.selectFork();
        _warpToForkBlock(ChainIdUtils.XLayer());

        skip(1 days);

        uint256 xlayerTimestamp = block.timestamp;

        assertEq(xlayer_spUsdt.convertToAssets(988_158.267227e6), 1_000_080.986298e6);  // Interest owed to the user on X Layer

        mainnet.selectFork();
        vm.warp(ethTimestamp);

        assertEq(eth_susds.convertToAssets(2_684_335.640914591022095658e18), 3_000_306.556358256742287388e18);  // Interest accrued
        assertEq(eth_spUsdt.convertToAssets(963_376.052632e6),               1_000_080.986298e6);               // Interest owed to the user on Ethereum

        // Rate limits fully recharged
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)),       10_000_000e18);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);

        // Step 15: Ethereum Spark Vaults agent (planner agent) redeems the sUSDS for 3_000_000e18 USDS + interest using
        //          ERC4626Facet

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_depositKey()),  type(uint256).max);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_withdrawKey()), type(uint256).max);

        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  0);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 172_728_264.360389296369614933e18 + 2_684_335.640914591022095658e18);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(
                        IERC4626Controller.erc4626_redeem,
                        (Ethereum.SUSDS, 2_684_335.640914591022095658e18, 3_000_306.556358256742287388e18)
                    )
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_depositKey()),  type(uint256).max);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_susds_withdrawKey()), type(uint256).max);

        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy),  3_000_306.556358256742287388e18);
        assertEq(eth_susds.balanceOf(eth_spUSDTPAU_almProxy), 172_728_264.360389296369614933e18);

        // Step 16: SLL agent (planner agent) initiates a swap on the SLL PAU of USDT + interest for the USDS + interest,
        //          completed by the spUSDT PAU using SwapAssetFacet

        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 0);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 3_000_306.556358256742287388e18);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     6_000_000e6);
        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     0);

        // The SLL sends USDT, so the spUSDT PAU sends amountOut * 1e12 USDS, the USDS dust below 1e12 stays in the
        // spUSDT ALMProxy.
        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SLL_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_sllPau_controller),
                    abi.encodeCall(
                        ISwapAssetController.swapAsset_initiateSwap,
                        (address(eth_spUSDTPAU_controller), Ethereum.USDT, Ethereum.USDS, 3_000_306.556358e6)
                    )
                )
            )
        );

        // The reverse direction keys increase, already at max so they stay at max.
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT)), 10_000_000e18);
        assertEq(eth_sllPau_rateLimits.getCurrentRateLimit(_ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS)), 6_999_693.443642e6);

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS)), 10_000_000e6);
        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT)), 6_999_693.443642e18);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 3_000_306.556358e6);
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0.000000256742287388e18);
        assertEq(eth_usdt.balanceOf(Ethereum.ALM_PROXY),     2_999_693.443642e6);
        assertEq(eth_usds.balanceOf(Ethereum.ALM_PROXY),     3_000_306.556358e18);

        // Step 17: Ethereum Spark Vaults agent (planner agent) transfers 1_000_000e6 USDT + interest to the Ethereum
        //          spUSDT vault using TransferAssetFacet

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_transferAsset_transferKey()), 10_000_000e6);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 3_000_306.556358e6);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)),    81_751_150.829624e6);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(
                        ITransferAssetController.transferAsset_transfer,
                        (Ethereum.USDT, address(eth_spUsdt), 1_000_080.986298e6)  // Interest owed to the user on Ethereum
                    )
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_transferAsset_transferKey()), 10_000_000e6 - 1_000_080.986298e6);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 2_000_225.570060e6);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)),    82_751_231.815922e6);

        // Step 18: Ethereum Spark Vaults agent (planner agent) bridges 1_000_000e6 USDT + interest to the Arbitrum
        //          spUSDT PAU using LayerZeroFacet

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_layerZero_transferKey(LZ_EID_ARBITRUM)), 5_000_000e6);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 2_000_225.570060e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_717_462_485.408440e6);

        ( , fee ) = eth_spUSDTPAU_controller.layerZero_quoteTransfer(Ethereum.USDT_OFT, 1_000_080.986298e6, LZ_EID_ARBITRUM);

        sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(Ethereum.USDT_OFT, LZ_EID_ARBITRUM, _toBytes32(Arbitrum.USDT_OFT)) + 1;

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call{ value: fee.nativeFee }(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(
                        ILayerZeroController.layerZero_transfer,
                        (Ethereum.USDT_OFT, 1_000_080.986298e6, LZ_EID_ARBITRUM)  // Interest owed to the user on Arbitrum
                    )
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_layerZero_transferKey(LZ_EID_ARBITRUM)), 5_000_000e6 - 1_000_080.986298e6);

        // USDT is locked in the OFT adapter on Ethereum.
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_144.583762e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_718_462_566.394738e6);

        // Step 19: Relay the message to Arbitrum

        arbitrum.selectFork();
        vm.warp(arbTimestamp);

        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);
        assertEq(arb_usdt0.totalSupply(),                     1_101_839_331.550136e6);

        // The message can only be delivered if the Arbitrum fork is not ahead of the Ethereum fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)), sentNonce);

        _skipLZPendingNonces(Arbitrum.USDT_OFT, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT), sentNonce);

        LZBridgeTesting.relayMessagesToDestination(_getLZBridge(ChainIdUtils.ArbitrumOne()), true, Ethereum.USDT_OFT, Arbitrum.USDT_OFT);

        vm.warp(arbTimestamp);

        // USDT0 is minted on Arbitrum.
        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 1_000_080.986298e6);
        assertEq(arb_usdt0.totalSupply(),                     1_102_839_412.536434e6);

        // Step 20: Arbitrum Spark Vaults agent (planner agent) transfers 1_000_000e6 USDT0 + interest to the Arbitrum
        //          spUSDT vault using TransferAssetFacet

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_transferAsset_transferKey()), 10_000_000e6);

        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 1_000_080.986298e6);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)),    1_058_239.025688e6);

        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Arbitrum.PLANNER_ADMINISTERED_AGENT).call(
            Arbitrum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(arb_spUSDTPAU_controller),
                    abi.encodeCall(
                        ITransferAssetController.transferAsset_transfer,
                        (Arbitrum.USDT0, address(arb_spUsdt), 1_000_080.986298e6)  // Interest owed to the user on Arbitrum
                    )
                )
            )
        );

        assertEq(arb_spUSDTPAU_rateLimits.getCurrentRateLimit(_arbSpUsdt_transferAsset_transferKey()), 10_000_000e6 - 1_000_080.986298e6);

        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)),    2_058_320.011986e6);

        // Step 21: Ethereum Spark Vaults agent (planner agent) bridges 1_000_000e6 USDT + interest to the X Layer
        //          SLL ALMProxy using LayerZeroFacet

        mainnet.selectFork();
        vm.warp(ethTimestamp);

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_layerZero_transferKey(LZ_EID_XLAYER)), 10_000_000e6);

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 1_000_144.583762e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_718_462_566.394738e6);

        ( , fee ) = eth_spUSDTPAU_controller.layerZero_quoteTransfer(Ethereum.USDT_OFT, 1_000_080.986298e6, LZ_EID_XLAYER);

        sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(Ethereum.USDT_OFT, LZ_EID_XLAYER, _toBytes32(USDT0_OFT_XLAYER)) + 1;

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        IAdministeredAgentLike(Ethereum.PLANNER_ADMINISTERED_AGENT).call{ value: fee.nativeFee }(
            Ethereum.SPARK_ADMINISTERED_AGENT,
            abi.encodeCall(
                IAdministeredAgentLike.call,
                (
                    address(eth_spUSDTPAU_controller),
                    abi.encodeCall(
                        ILayerZeroController.layerZero_transfer,
                        (Ethereum.USDT_OFT, 1_000_080.986298e6, LZ_EID_XLAYER)  // Interest owed to the user on X Layer
                    )
                )
            )
        );

        assertEq(eth_spUSDTPAU_rateLimits.getCurrentRateLimit(_ethSpUsdt_layerZero_transferKey(LZ_EID_XLAYER)), 10_000_000e6 - 1_000_080.986298e6);

        // USDT is locked in the OFT adapter on Ethereum.
        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 63.597464e6);
        assertEq(eth_usdt.balanceOf(Ethereum.USDT_OFT),      3_719_462_647.381036e6);

        // Step 22: Relay the message to X Layer

        xlayer.selectFork();
        vm.warp(xlayerTimestamp);

        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 2_828.911808e6);
        assertEq(xlayer_usdt0.totalSupply(),               141_568_626.357877e6);

        // The message can only be delivered if the X Layer fork is not ahead of the Ethereum fork.
        assertLt(ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT)), sentNonce);

        _skipLZPendingNonces(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, _toBytes32(Ethereum.USDT_OFT), sentNonce);

        LZBridgeTesting.relayMessagesToDestination(_getLZBridge(ChainIdUtils.XLayer()), true, Ethereum.USDT_OFT, USDT0_OFT_XLAYER);

        vm.warp(xlayerTimestamp);

        // USDT0 is minted on X Layer.
        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 1_002_909.898106e6);
        assertEq(xlayer_usdt0.totalSupply(),               142_568_707.344175e6);

        // Step 23: X Layer SLL relayer (ALM Relayer Multisig) transfers 1_000_000e6 USDT0 + interest to the X Layer
        //          spUSDT vault using the ForeignController

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_transferAsset_transferKey()), type(uint256).max);

        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY),       1_002_909.898106e6);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 4_762_342.392302e6);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayer_legacy_controller.transferAsset(XLayer.USDT0, address(xlayer_spUsdt), 1_000_080.986298e6);  // Interest owed to the user on X Layer

        assertEq(xlayer_legacy_rateLimits.getCurrentRateLimit(_xlayerSll_transferAsset_transferKey()), type(uint256).max);

        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY),       2_828.911808e6);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 5_762_423.378600e6);

        // Step 24: User redeems their Ethereum spUSDT deposit and receives the 1_000_000e6 USDT + interest

        mainnet.selectFork();
        vm.warp(ethTimestamp);

        assertEq(eth_usdt.balanceOf(user),                0);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)), 82_751_231.815922e6);

        assertEq(eth_spUsdt.totalAssets(),   275_813_724.931102e6);
        assertEq(eth_spUsdt.totalSupply(),   265_690_820.269835e6);
        assertEq(eth_spUsdt.balanceOf(user), 963_376.052632e6);

        vm.prank(user);
        eth_spUsdt.redeem(963_376.052632e6, user, user);

        assertEq(eth_usdt.balanceOf(user),                1_000_080.986298e6);
        assertEq(eth_usdt.balanceOf(address(eth_spUsdt)), 81_751_150.829624e6);

        assertEq(eth_spUsdt.totalAssets(),   274_813_643.944803e6);
        assertEq(eth_spUsdt.totalSupply(),   264_727_444.217203e6);
        assertEq(eth_spUsdt.balanceOf(user), 0);

        // Step 25: User redeems their Arbitrum spUSDT deposit and receives the 1_000_000e6 USDT0 + interest

        arbitrum.selectFork();
        vm.warp(arbTimestamp);

        assertEq(arb_usdt0.balanceOf(user),                0);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)), 2_058_320.011986e6);

        assertEq(arb_spUsdt.totalAssets(),   2_060_578.509643e6);
        assertEq(arb_spUsdt.totalSupply(),   2_035_076.683849e6);
        assertEq(arb_spUsdt.balanceOf(user), 987_703.932489e6);

        vm.prank(user);
        arb_spUsdt.redeem(987_703.932489e6, user, user);

        assertEq(arb_usdt0.balanceOf(user),                1_000_080.986298e6);
        assertEq(arb_usdt0.balanceOf(address(arb_spUsdt)), 1_058_239.025688e6);

        assertEq(arb_spUsdt.totalAssets(),   1_060_497.523344e6);
        assertEq(arb_spUsdt.totalSupply(),   1_047_372.751360e6);
        assertEq(arb_spUsdt.balanceOf(user), 0);

        // Step 26: User redeems their X Layer spUSDT deposit and receives the 1_000_000e6 USDT0 + interest

        xlayer.selectFork();
        vm.warp(xlayerTimestamp);

        assertEq(xlayer_usdt0.balanceOf(user),                   0);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 5_762_423.378600e6);

        assertEq(xlayer_spUsdt.totalAssets(),   5_763_153.443439e6);
        assertEq(xlayer_spUsdt.totalSupply(),   5_694_446.548286e6);
        assertEq(xlayer_spUsdt.balanceOf(user), 988_158.267227e6);

        vm.prank(user);
        xlayer_spUsdt.redeem(988_158.267227e6, user, user);

        assertEq(xlayer_usdt0.balanceOf(user),                   1_000_080.986298e6);
        assertEq(xlayer_usdt0.balanceOf(address(xlayer_spUsdt)), 4_762_342.392302e6);

        assertEq(xlayer_spUsdt.totalAssets(),   4_763_072.457141e6);
        assertEq(xlayer_spUsdt.totalSupply(),   4_706_288.281059e6);
        assertEq(xlayer_spUsdt.balanceOf(user), 0);

        // The sUSDS yield above the spUSDT VSR and the USDS swap dust on Ethereum, nothing on Arbitrum, and the X Layer
        // SLL ALMProxy is back to its pre-flow balance.
        assertEq(xlayer_usdt0.balanceOf(XLayer.ALM_PROXY), 2_828.911808e6);

        arbitrum.selectFork();

        assertEq(arb_usdt0.balanceOf(arb_spUSDTPAU_almProxy), 0);

        mainnet.selectFork();

        assertEq(eth_usdt.balanceOf(eth_spUSDTPAU_almProxy), 63.597464e6);              // sUSDS yield above the spUSDT VSR
        assertEq(eth_usds.balanceOf(eth_spUSDTPAU_almProxy), 0.000000256742287388e18);  // Remaining USDS swap dust
    }

    function _xlayerSll_sparkVault_takeKey() internal view returns (bytes32) {
        return RateLimitHelpers.makeAddressKey(xlayer_legacy_controller.LIMIT_SPARK_VAULT_TAKE(), XLayer.SPARK_VAULT_V2_SPUSDT);
    }

    function _xlayerSll_transferAsset_transferKey() internal view returns (bytes32) {
        return RateLimitHelpers.makeAddressAddressKey(xlayer_legacy_controller.LIMIT_ASSET_TRANSFER(), XLayer.USDT0, XLayer.SPARK_VAULT_V2_SPUSDT);
    }

    function _xlayerSll_layerZero_transferKey() internal view returns (bytes32) {
        return keccak256(abi.encode(xlayer_legacy_controller.LIMIT_LAYERZERO_TRANSFER(), USDT0_OFT_XLAYER, LZ_EID_ETHEREUM));
    }

    // The X Layer legacy controller has no quote function, so the fee is quoted from the OFT with the controller's
    // send parameters.
    function _xlayerSll_layerZero_quoteTransfer(uint256 amount) internal view returns (uint256) {
        SendParam memory sendParams = SendParam({
            dstEid       : LZ_EID_ETHEREUM,
            to           : xlayer_legacy_controller.layerZeroRecipients(LZ_EID_ETHEREUM),
            amountLD     : amount,
            minAmountLD  : 0,
            extraOptions : OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0),
            composeMsg   : "",
            oftCmd       : ""
        });

        return ILayerZero(USDT0_OFT_XLAYER).quoteSend(sendParams, false).nativeFee;
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    function _assertEthereumSpUsdtPauDeploymentConfig() internal view {
        // Wiring

        assertEq(eth_spUSDTPAU_controller.beacon(),         Ethereum.SPARK_BEACON);
        assertEq(eth_spUSDTPAU_controller.proxy(),          eth_spUSDTPAU_almProxy);
        assertEq(eth_spUSDTPAU_controller.rateLimits(),     address(eth_spUSDTPAU_rateLimits));
        assertEq(eth_spUSDTPAU_controller.accessControls(), eth_spUSDTPAU_accessControls);

        // Roles

        _assertOnlyRoleMember(eth_spUSDTPAU_accessControls,      DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(eth_spUSDTPAU_almProxy,            DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);
        _assertOnlyRoleMember(address(eth_spUSDTPAU_rateLimits), DEFAULT_ADMIN_ROLE, Ethereum.SPARK_PROXY);

        _assertOnlyRoleMember(eth_spUSDTPAU_almProxy,            IALMProxy(eth_spUSDTPAU_almProxy).CONTROLLER(), address(eth_spUSDTPAU_controller));
        _assertOnlyRoleMember(address(eth_spUSDTPAU_rateLimits), eth_spUSDTPAU_rateLimits.CONTROLLER(),          address(eth_spUSDTPAU_controller));
        _assertOnlyRoleMember(eth_spUSDTPAU_accessControls,      ALLOCATOR_ROLE,                                 Ethereum.SPARK_ADMINISTERED_AGENT);

        // Integrations enabled at deployment

        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.ERC4626_INTEGRATION).facet,        Ethereum.ERC4626_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.SPARK_VAULT_INTEGRATION).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.TRANSFER_ASSET_INTEGRATION).facet, Ethereum.TRANSFER_ASSET_FACET);

        assertEq(eth_spUSDTPAU_controller.getConfig(BeaconConfig.CCTP_INTEGRATION).facet, address(0));

        // Rate limits

        _assertUnlimitedRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_susds_depositKey());
        _assertUnlimitedRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_susds_withdrawKey());

        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_sparkVault_takeKey(),        10_000_000e6, uint256(200_000_000e6) / 1 days);
        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_transferAsset_transferKey(), 10_000_000e6, uint256(200_000_000e6) / 1 days);

        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_layerZero_transferKey(LZ_EID_ARBITRUM), 5_000_000e6, uint256(25_000_000e6) / 1 days);

        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_swapAsset_completeKey(Ethereum.USDT, Ethereum.USDS), 10_000_000e6,  uint256(200_000_000e6)  / 1 days);
        _assertRateLimit(address(eth_spUSDTPAU_rateLimits), _ethSpUsdt_swapAsset_completeKey(Ethereum.USDS, Ethereum.USDT), 10_000_000e18, uint256(200_000_000e18) / 1 days);

        // No initiate key, so the spUSDT PAU cannot start a swap.
        _assertRateLimit(
            address(eth_spUSDTPAU_rateLimits),
            ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getInitiateSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, address(eth_sllPau_controller), Ethereum.USDS),
            0,
            0
        );

        // sUSDS maximum exchange rate: erc4626_setMaxExchangeRate(sUSDS, 1, 1e40).
        assertEq(eth_spUSDTPAU_controller.erc4626_getMaxExchangeRate(Ethereum.SUSDS), 1e40 * eth_spUSDTPAU_controller.erc4626_EXCHANGE_RATE_PRECISION());
    }

    function _assertEthereumSllPauDeploymentConfig() internal view {
        // Wiring: the Sky Beacon and the existing Spark Liquidity Layer ALM Proxy.

        assertEq(eth_sllPau_controller.beacon(),         SkyEthereum.BEACON);
        assertEq(eth_sllPau_controller.proxy(),          Ethereum.ALM_PROXY);
        assertEq(eth_sllPau_controller.rateLimits(),     address(eth_sllPau_rateLimits));
        assertEq(eth_sllPau_controller.accessControls(), eth_sllPau_accessControls);

        // Roles

        _assertOnlyRoleMember(address(eth_sllPau_rateLimits), eth_sllPau_rateLimits.CONTROLLER(), address(eth_sllPau_controller));
        _assertOnlyRoleMember(eth_sllPau_accessControls,      ALLOCATOR_ROLE,                     Ethereum.SLL_ADMINISTERED_AGENT);

        // Rate limits

        _assertRateLimit(address(eth_sllPau_rateLimits), _ethSll_swapAsset_initiateKey(Ethereum.USDS, Ethereum.USDT), 10_000_000e18, uint256(200_000_000e18) / 1 days);
        _assertRateLimit(address(eth_sllPau_rateLimits), _ethSll_swapAsset_initiateKey(Ethereum.USDT, Ethereum.USDS), 10_000_000e6,  uint256(200_000_000e6)  / 1 days);
    }

    function _assertEthereumAgents() internal view {
        address[] memory actors = new address[](2);
        actors[0] = Ethereum.PLANNER_WALLET;
        actors[1] = Ethereum.ALM_RELAYER_MULTISIG;

        address[] memory revokers = new address[](1);
        revokers[0] = Ethereum.SPARK_LOW_THRESHOLD_MULTISIG;

        _assertAgent({
            agent    : Ethereum.PLANNER_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actors   : actors,
            revokers : revokers,
            grantor  : Ethereum.SPARK_MEDIUM_THRESHOLD_MULTISIG
        });

        actors = new address[](1);
        actors[0] = Ethereum.PLANNER_ADMINISTERED_AGENT;

        revokers = new address[](2);
        revokers[0] = Ethereum.SPARK_LOW_THRESHOLD_MULTISIG;
        revokers[1] = Ethereum.SOTER_REVOKER_MULTISIG;

        _assertAgent({
            agent    : Ethereum.SPARK_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actors   : actors,
            revokers : revokers,
            grantor  : Ethereum.SOTER_GRANTOR_MULTISIG
        });

        _assertAgent({
            agent    : Ethereum.SLL_ADMINISTERED_AGENT,
            admin    : Ethereum.SPARK_PROXY,
            actors   : actors,
            revokers : revokers,
            grantor  : Ethereum.SOTER_GRANTOR_MULTISIG
        });
    }

    function _assertArbitrumSpUsdtPauDeploymentConfig() internal view {
        // Wiring

        assertEq(arb_spUSDTPAU_controller.beacon(),         Arbitrum.SPARK_BEACON);
        assertEq(arb_spUSDTPAU_controller.proxy(),          arb_spUSDTPAU_almProxy);
        assertEq(arb_spUSDTPAU_controller.rateLimits(),     address(arb_spUSDTPAU_rateLimits));
        assertEq(arb_spUSDTPAU_controller.accessControls(), arb_spUSDTPAU_accessControls);

        // Roles

        _assertOnlyRoleMember(arb_spUSDTPAU_accessControls,      DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);
        _assertOnlyRoleMember(arb_spUSDTPAU_almProxy,            DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);
        _assertOnlyRoleMember(address(arb_spUSDTPAU_rateLimits), DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);

        _assertOnlyRoleMember(arb_spUSDTPAU_almProxy,            IALMProxy(arb_spUSDTPAU_almProxy).CONTROLLER(), address(arb_spUSDTPAU_controller));
        _assertOnlyRoleMember(address(arb_spUSDTPAU_rateLimits), arb_spUSDTPAU_rateLimits.CONTROLLER(),          address(arb_spUSDTPAU_controller));
        _assertOnlyRoleMember(arb_spUSDTPAU_accessControls,      ALLOCATOR_ROLE,                                 Arbitrum.SPARK_ADMINISTERED_AGENT);

        address[] memory actors = new address[](2);
        actors[0] = Arbitrum.PLANNER_WALLET;
        actors[1] = Arbitrum.ALM_RELAYER_MULTISIG;

        address[] memory revokers = new address[](1);
        revokers[0] = Arbitrum.SPARK_LOW_THRESHOLD_MULTISIG;

        _assertAgent({
            agent    : Arbitrum.PLANNER_ADMINISTERED_AGENT,
            admin    : Arbitrum.SPARK_EXECUTOR,
            actors   : actors,
            revokers : revokers,
            grantor  : Arbitrum.SPARK_MEDIUM_THRESHOLD_MULTISIG
        });

        actors = new address[](1);
        actors[0] = Arbitrum.PLANNER_ADMINISTERED_AGENT;

        revokers = new address[](2);
        revokers[0] = Arbitrum.SPARK_LOW_THRESHOLD_MULTISIG;
        revokers[1] = Arbitrum.SOTER_REVOKER_MULTISIG;

        _assertAgent({
            agent    : Arbitrum.SPARK_ADMINISTERED_AGENT,
            admin    : Arbitrum.SPARK_EXECUTOR,
            actors   : actors,
            revokers : revokers,
            grantor  : Arbitrum.SOTER_GRANTOR_MULTISIG
        });

        // Integrations: SparkVault, TransferAsset and LayerZero only.

        assertEq(arb_spUSDTPAU_controller.integrations().length, 3);

        _assertIntegrationEnabled(address(arb_spUSDTPAU_controller), BeaconConfig.buildSparkVaultIntegration(Arbitrum.SPARK_VAULT_FACET));
        _assertIntegrationEnabled(address(arb_spUSDTPAU_controller), BeaconConfig.buildTransferAssetIntegration(Arbitrum.TRANSFER_ASSET_FACET));
        _assertIntegrationEnabled(address(arb_spUSDTPAU_controller), BeaconConfig.buildLayerZeroIntegration(Arbitrum.LAYER_ZERO_FACET));

        // Rate limits

        assertEq(
            arb_spUSDTPAU_controller.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT),
            RateLimitHelpers.makeAddressKey(keccak256("LIMIT_SPARK_VAULT_TAKE"), Arbitrum.SPARK_VAULT_V2_SPUSDT)
        );

        _assertRateLimit(
            address(arb_spUSDTPAU_rateLimits),
            arb_spUSDTPAU_controller.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT),
            10_000_000e6,
            uint256(200_000_000e6) / 1 days
        );

        _assertRateLimit(
            address(arb_spUSDTPAU_rateLimits),
            _arbSpUsdt_transferAsset_transferKey(),
            10_000_000e6,
            uint256(200_000_000e6) / 1 days
        );

        _assertRateLimit(
            address(arb_spUSDTPAU_rateLimits),
            _arbSpUsdt_layerZero_transferKey(),
            5_000_000e6,
            uint256(25_000_000e6) / 1 days
        );

        // LayerZero recipient: the Ethereum spUSDT PAU.

        assertEq(IOFTLike(Arbitrum.USDT_OFT).peers(LZ_EID_ETHEREUM), _toBytes32(Ethereum.USDT_OFT));

        assertEq(arb_spUSDTPAU_controller.layerZero_getRecipient(LZ_EID_ETHEREUM), _toBytes32(eth_spUSDTPAU_almProxy));
        assertEq(arb_spUSDTPAU_controller.layerZero_getRecipient(LZ_EID_XLAYER),   bytes32(0));
    }

    function _assertAgent(
        address          agent,
        address          admin,
        address[] memory actors,
        address[] memory revokers,
        address          grantor
    ) internal view {
        IAdministeredAgentLike agent_ = IAdministeredAgentLike(agent);

        assertEq(agent_.adminCount(),      1);
        assertEq(agent_.getIsAdmin(admin), true);

        assertEq(agent_.actorCount(), actors.length);

        for (uint256 i; i < actors.length; ++i) {
            assertEq(agent_.getIsActor(actors[i]), true);
        }

        assertEq(agent_.revokerCount(), revokers.length);

        for (uint256 i; i < revokers.length; ++i) {
            assertEq(agent_.getIsRevoker(revokers[i]), true);
        }

        assertEq(agent_.grantorCount(),        1);
        assertEq(agent_.getIsGrantor(grantor), true);
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

    function _assertRoleMembers(address target, bytes32 role, address[] memory accounts) internal view {
        assertEq(IAccessControlEnumerable(target).getRoleMemberCount(role), accounts.length);

        for (uint256 i; i < accounts.length; ++i) {
            assertEq(IAccessControlEnumerable(target).getRoleMember(role, i), accounts[i]);
        }
    }

    // The facets' pure key getters, so the keys can be read before the spell enables the integrations.
    function _ethSll_swapAsset_initiateKey(address assetOut, address assetIn) internal pure returns (bytes32) {
        return ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getInitiateSwapRateLimitKey(assetOut, Ethereum.SPUSDT_PAU_ALM_PROXY, Ethereum.SPUSDT_PAU_CONTROLLER, assetIn);
    }

    function _ethSpUsdt_swapAsset_completeKey(address assetOut, address assetIn) internal pure returns (bytes32) {
        return ISwapAssetFacet(Ethereum.SWAP_ASSET_FACET).getCompleteSwapRateLimitKey(assetOut, Ethereum.ALM_PROXY, assetIn);
    }

    function _ethSpUsdt_layerZero_transferKey(uint32 destinationEndpointId) internal pure returns (bytes32) {
        bytes32 peer = destinationEndpointId == LZ_EID_ARBITRUM ? _toBytes32(Arbitrum.USDT_OFT) : _toBytes32(XLayer.USDT0_OFT);

        return ILayerZeroFacet(Ethereum.LAYERZERO_FACET).getTransferRateLimitKey(Ethereum.USDT_OFT, peer, destinationEndpointId, Ethereum.USDT);
    }

    function _ethSpUsdt_susds_depositKey() internal view returns (bytes32) {
        return IERC4626Controller(Ethereum.SPUSDT_PAU_CONTROLLER).erc4626_getDepositRateLimitKey(Ethereum.SUSDS, Ethereum.USDS);
    }

    function _ethSpUsdt_susds_withdrawKey() internal view returns (bytes32) {
        return IERC4626Controller(Ethereum.SPUSDT_PAU_CONTROLLER).erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS);
    }

    function _ethSpUsdt_sparkVault_takeKey() internal view returns (bytes32) {
        return ISparkVaultController(Ethereum.SPUSDT_PAU_CONTROLLER).sparkVault_getTakeRateLimitKey(Ethereum.SPARK_VAULT_V2_SPUSDT);
    }

    function _ethSpUsdt_transferAsset_transferKey() internal view returns (bytes32) {
        return ITransferAssetController(Ethereum.SPUSDT_PAU_CONTROLLER).transferAsset_getTransferRateLimitKey(Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdt_sparkVault_takeKey() internal view returns (bytes32) {
        return ISparkVaultController(Arbitrum.SPUSDT_PAU_CONTROLLER).sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdt_transferAsset_transferKey() internal view returns (bytes32) {
        return ITransferAssetController(Arbitrum.SPUSDT_PAU_CONTROLLER).transferAsset_getTransferRateLimitKey(Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT);
    }

    function _arbSpUsdt_layerZero_transferKey() internal view returns (bytes32) {
        return ILayerZeroController(Arbitrum.SPUSDT_PAU_CONTROLLER).layerZero_getTransferRateLimitKey(
            Arbitrum.USDT_OFT,
            _toBytes32(Ethereum.USDT_OFT),
            LZ_EID_ETHEREUM,
            Arbitrum.USDT0
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
            Ethereum.ALM_RELAYER_MULTISIG,
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

        _skipLZPendingNonces(p.destinationOft, p.sourceEndpointId, _toBytes32(p.oft), sentNonce);

        assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore);

        chainData[p.sourceChainId].domain.selectFork();

        LZBridgeTesting.relayMessagesToDestination(_getLZBridge(p.destinationChainId), true, p.oft, p.destinationOft);

        assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore + p.amount);

        vm.revertToState(destinationSnapshot);

        chainData[p.sourceChainId].domain.selectFork();
    }

    function _recordForkTimestamps() internal {
        for (uint256 i; i < allChains.length; ++i) {
            chainData[allChains[i]].domain.selectFork();

            forkTimestamp[allChains[i]] = block.timestamp;
        }

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    // Parallel tests share the fork environments, so a fork switch can pick up a timestamp warped by another test.
    function _warpToForkBlock(uint256 chainId) internal {
        vm.warp(forkTimestamp[chainId]);
    }

}

contract SparkEthereum_20261203_SparklendTests is SparklendTests {

    using DomainHelpers for Domain;

    function setUp() public override {
        super.setUp();

        _skyCoreSpell();
    }

    function _skyCoreSpell() internal {
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // Pre-requirement 9: the Sky Core spell registers SwapAssetFacet on the Sky Beacon before the Spark payload.
        vm.prank(Ethereum.PAUSE_PROXY);
        BeaconConfig.setSwapAssetIntegration(SkyEthereum.BEACON, SkyEthereum.SWAP_ASSET_FACET);
    }

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795631067;  //Nov-25-2026 06:24:27 PM +UTC
    }

}

contract SparkEthereum_20261203_SpellTests is SpellTests {

    using DomainHelpers for Domain;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    function setUp() public override {
        super.setUp();

        _skyCoreSpell();
    }

    function _skyCoreSpell() internal {
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // Pre-requirement 9: the Sky Core spell registers SwapAssetFacet on the Sky Beacon before the Spark payload.
        vm.prank(Ethereum.PAUSE_PROXY);
        BeaconConfig.setSwapAssetIntegration(SkyEthereum.BEACON, SkyEthereum.SWAP_ASSET_FACET);
    }

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795631067;  //Nov-25-2026 06:24:27 PM +UTC
    }

    function test_ETHEREUM_sparkTreasury_buyback() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore  = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 opsMultisigBalanceBefore = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,  52_273_193.205806286854722044e18);
        assertEq(opsMultisigBalanceBefore, 552_142.342558330054342171e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore  - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
    }

}
