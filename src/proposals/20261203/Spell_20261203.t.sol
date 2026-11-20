// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Vm } from "forge-std/Vm.sol";

import { console2 } from "forge-std/console2.sol";

import { IERC20 }                   from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 }                 from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IAccessControlEnumerable } from "openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

import { OptionsBuilder } from "lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

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

interface IAdministeredAgentFactoryLike {

    function deploy(address admin, bytes32 salt) external returns (address administeredAgent);

}

// pau-administered-agent v1.0.0 (X Layer).
interface IAdministeredAgentFactoryV1Like {

    function deploy(address admin) external returns (address administeredAgent);

}

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function addActor(address account) external;

    function addAdmin(address account) external;

    function addGrantor(address account) external;

    function addRevoker(address account) external;

    function adminCount() external view returns (uint256);

    function call(address target, bytes memory data) external payable returns (bytes memory result);

    function getActor(uint256 index) external view returns (address);

    function getAdmin(uint256 index) external view returns (address);

    function removeAdmin(address account) external;

}

// Diamond PAU Beacon (diamond-pau v1.16.0).
interface IBeaconLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    struct Config {
        address facet;
        Wire[]  wires;
    }

    function getConfig(bytes32 integrationId) external view returns (Config memory config);

    function setIntegration(bytes32 id, Config calldata config) external;

}

// Diamond PAU controller (diamond-pau v1.16.0).
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

    function accessControls() external view returns (address);

    function beacon() external view returns (address);

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain) external view returns (bytes32);

    function cctp_toCCTPRateLimitKey() external view returns (bytes32);

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate) external;

    function erc4626_deposit(address token, uint256 amount, uint256 minSharesOut) external returns (uint256 shares);

    function erc4626_getDepositRateLimitKey(address token, address asset) external view returns (bytes32);

    function erc4626_getMaxExchangeRate(address token) external view returns (uint256);

    function erc4626_getWithdrawRateLimitKey(address token) external view returns (bytes32);

    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function erc4626_withdraw(address token, uint256 amount, uint256 maxSharesIn) external returns (uint256 shares);

    function getConfig(bytes32 integrationId) external view returns (Config memory);

    function getDispatch(bytes4 callSelector) external view returns (Dispatch memory);

    function layerZero_getRecipient(uint32 destinationEndpointId) external view returns (bytes32);

    function layerZero_getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    ) external view returns (bytes32);

    function layerZero_quoteTransfer(address oft, uint256 amount, uint32 destinationEndpointId)
        external
        view
        returns (SendParam memory sendParams, MessagingFee memory fee);

    function layerZero_transfer(address oft, uint256 amount, uint32 destinationEndpointId) external payable;

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

    function sparkVault_getTakeRateLimitKey(address sparkVault) external view returns (bytes32);

    function sparkVault_take(address sparkVault, uint256 assetAmount) external;

    function swapAsset_getCompleteSwapRateLimitKey(address assetOut, address counterpartyProxy, address assetIn)
        external
        view
        returns (bytes32);

    function swapAsset_getInitiateSwapRateLimitKey(
        address assetOut,
        address counterpartyProxy,
        address counterpartyController,
        address assetIn
    ) external view returns (bytes32);

    function swapAsset_initiateSwap(
        address counterpartyController,
        address assetOut,
        address assetIn,
        uint256 amountOut
    ) external;

    function transferAsset_getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);

    function transferAsset_transfer(address asset, address destination, uint256 amount) external;

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface ILZEndpointLike {

    function lazyInboundNonce(address _receiver, uint32 _srcEid, bytes32 _sender) external view returns (uint64);

    function outboundNonce(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (uint64);

}

interface IOFTLike {

    function peers(uint32 eid) external view returns (bytes32 peer);

}

interface IPAUFactoryLike {

    function deployAccessControls(address admin, bytes32 salt) external returns (address accessControls);

    function deployALMProxy(address admin, bytes32 salt) external returns (address almProxy);

    function deployController(address accessControls, address proxy, address rateLimits, bytes32 salt)
        external
        returns (address controller);

    function deployRateLimits(address admin, bytes32 salt) external returns (address rateLimits);

}

interface ISparkVaultLike is ISparkVaultV2Like {

    function assetsOutstanding() external view returns (uint256);

}

/**
 * @dev Scaffold stand-ins for the contracts in Pre-deployed contracts 1, 2, 4, 5 and 6, which are not deployed yet.
 *      Each is created by the real factory on the fork and then cloned (runtime code + storage) onto the PLACEHOLDER
 *      address the payloads use. Nothing here runs once real code exists at those addresses.
 */
abstract contract SpUsdtPauStandIns {

    Vm private constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER_ROLE    = keccak256("CONTROLLER");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant CCTP_FACET_ID           = "CCTP_FACET";
    bytes32 internal constant ERC4626_FACET_ID        = "ERC4626_FACET";
    bytes32 internal constant LAYER_ZERO_FACET_ID     = "LAYER_ZERO_FACET";
    bytes32 internal constant SPARK_VAULT_FACET_ID    = "SPARK_VAULT_FACET";
    bytes32 internal constant SWAP_ASSET_FACET_ID     = "SWAP_ASSET_FACET";
    bytes32 internal constant TRANSFER_ASSET_FACET_ID = "TRANSFER_ASSET_FACET";

    // PLACEHOLDER: Ethereum spUSDT PAU (Pre-deployed contracts 1), as in SparkEthereum_20261203.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2026120300000000000000000000000000000002;
    address internal constant SPUSDT_PAU_CONTROLLER = 0x2026120300000000000000000000000000000001;
    address internal constant SPUSDT_PAU_RATELIMITS = 0x2026120300000000000000000000000000000003;

    // PLACEHOLDER: Spark Liquidity Layer swap controller (Pre-deployed contracts 2), as in SparkEthereum_20261203.
    address internal constant SLL_SWAP_CONTROLLER = 0x2026120300000000000000000000000000000004;
    address internal constant SLL_SWAP_RATELIMITS = 0x2026120300000000000000000000000000000005;

    // PLACEHOLDER: Ethereum Administered Agents (Pre-deployed contracts 4); the Spark Vaults one is in SparkEthereum_20261203.
    address internal constant SPARK_VAULTS_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000006;
    address internal constant SLL_ADMINISTERED_AGENT          = 0x2026120300000000000000000000000000000007;

    // PLACEHOLDER: Arbitrum spUSDT PAU and Spark Vaults Administered Agent (Pre-deployed contracts 5), as in SparkArbitrumOne_20261203.
    address internal constant ARBITRUM_SPUSDT_PAU_ALM_PROXY            = 0x2026120300000000000000000000000000000012;
    address internal constant ARBITRUM_SPUSDT_PAU_CONTROLLER           = 0x2026120300000000000000000000000000000011;
    address internal constant ARBITRUM_SPUSDT_PAU_RATELIMITS           = 0x2026120300000000000000000000000000000013;
    address internal constant ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000014;

    // PLACEHOLDER: X Layer Spark Vaults Administered Agent (Pre-deployed contracts 6), as in SparkXLayer_20261203.
    address internal constant XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000021;

    address internal constant SKY_BEACON                     = 0x829dC2b7E94B1954F0764E573f2E0d45Afa28199;
    address internal constant SPARK_LOW_THRESHOLD_MULTISIG    = 0xeC7edCD85460018BA71823076343Cd8D1721972b;
    address internal constant SPARK_MEDIUM_THRESHOLD_MULTISIG = 0x71c738C6838A5491d9b9226eCBc2E74794855153;
    address internal constant SPARK_PLANNER_HOT_WALLET        = 0x062cE42caE04c51D04E77e3D64cc8953a2296FfE;

    /**********************************************************************************************/
    /*** Ethereum                                                                               ***/
    /**********************************************************************************************/

    function _deployEthereumStandIns() internal {
        if (SPUSDT_PAU_CONTROLLER.code.length != 0) return;

        IPAUFactoryLike               pauFactory   = IPAUFactoryLike(Ethereum.SPARK_PAU_FACTORY);
        IAdministeredAgentFactoryLike agentFactory = IAdministeredAgentFactoryLike(Ethereum.SPARK_ADMINISTERED_AGENT_FACTORY);

        // Pre-deployed contracts 4: hot wallet -> Spark Planner Administered Agent -> Spark Vaults / SLL Administered Agent.
        //                           Soter Labs revoker and grantor multisigs are TBD and not configured.
        address plannerAgent = agentFactory.deploy(address(this), "SPARK_PLANNER_ADMINISTERED_AGENT");

        _configureAgent(plannerAgent, SPARK_PLANNER_HOT_WALLET, SPARK_LOW_THRESHOLD_MULTISIG, SPARK_MEDIUM_THRESHOLD_MULTISIG, Ethereum.SPARK_PROXY);

        _clone(agentFactory.deploy(address(this), "SPARK_ADMINISTERED_AGENT"), SPARK_VAULTS_ADMINISTERED_AGENT);
        _configureAgent(SPARK_VAULTS_ADMINISTERED_AGENT, plannerAgent, SPARK_LOW_THRESHOLD_MULTISIG, address(0), Ethereum.SPARK_PROXY);

        _clone(agentFactory.deploy(address(this), "SPARK_SLL_ADMINISTERED_AGENT"), SLL_ADMINISTERED_AGENT);
        _configureAgent(SLL_ADMINISTERED_AGENT, plannerAgent, SPARK_LOW_THRESHOLD_MULTISIG, address(0), Ethereum.SPARK_PROXY);

        // Pre-deployed contracts 1: spUSDT PAU from the Spark PAUFactory (Beacon = Spark Beacon).
        address accessControls = pauFactory.deployAccessControls(address(this), "SPARK_SPUSDT_PAU");

        _clone(pauFactory.deployALMProxy(address(this),   "SPARK_SPUSDT_PAU"), SPUSDT_PAU_ALM_PROXY);
        _clone(pauFactory.deployRateLimits(address(this), "SPARK_SPUSDT_PAU"), SPUSDT_PAU_RATELIMITS);
        _clone(
            pauFactory.deployController(accessControls, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_RATELIMITS, "SPARK_SPUSDT_PAU"),
            SPUSDT_PAU_CONTROLLER
        );

        IAccessControlEnumerable(SPUSDT_PAU_ALM_PROXY).grantRole(CONTROLLER_ROLE,  SPUSDT_PAU_CONTROLLER);
        IAccessControlEnumerable(SPUSDT_PAU_RATELIMITS).grantRole(CONTROLLER_ROLE, SPUSDT_PAU_CONTROLLER);
        IAccessControlEnumerable(accessControls).grantRole(ALLOCATOR_ROLE,         SPARK_VAULTS_ADMINISTERED_AGENT);

        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);
        IRateLimits     rateLimits = IRateLimits(SPUSDT_PAU_RATELIMITS);

        bytes32[] memory integrationIds = new bytes32[](3);
        integrationIds[0] = ERC4626_FACET_ID;
        integrationIds[1] = SPARK_VAULT_FACET_ID;
        integrationIds[2] = TRANSFER_ASSET_FACET_ID;

        controller.updateIntegrations(integrationIds);

        rateLimits.setUnlimitedRateLimitData(controller.erc4626_getDepositRateLimitKey(Ethereum.SUSDS, Ethereum.USDS));
        rateLimits.setUnlimitedRateLimitData(controller.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS));
        rateLimits.setUnlimitedRateLimitData(controller.sparkVault_getTakeRateLimitKey(Ethereum.SPARK_VAULT_V2_SPUSDT));
        rateLimits.setUnlimitedRateLimitData(controller.transferAsset_getTransferRateLimitKey(Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT));

        controller.erc4626_setMaxExchangeRate(Ethereum.SUSDS, 1, 1e40);

        _handOverAdmin(accessControls,        Ethereum.SPARK_PROXY);
        _handOverAdmin(SPUSDT_PAU_ALM_PROXY,  Ethereum.SPARK_PROXY);
        _handOverAdmin(SPUSDT_PAU_RATELIMITS, Ethereum.SPARK_PROXY);

        // Pre-deployed contracts 2: a Controller on the existing Spark Liquidity Layer ALM Proxy, wired to the Sky Beacon.
        //                           The Spark factory bakes the Spark Beacon into the immutable, so the clone rewrites it.
        address swapAccessControls = pauFactory.deployAccessControls(address(this), "SPARK_SLL_SWAP_CONTROLLER");

        _clone(pauFactory.deployRateLimits(address(this), "SPARK_SLL_SWAP_CONTROLLER"), SLL_SWAP_RATELIMITS);
        _cloneWithBeacon(
            pauFactory.deployController(swapAccessControls, Ethereum.ALM_PROXY, SLL_SWAP_RATELIMITS, "SPARK_SLL_SWAP_CONTROLLER"),
            SLL_SWAP_CONTROLLER,
            Ethereum.SPARK_BEACON,
            SKY_BEACON
        );

        IAccessControlEnumerable(SLL_SWAP_RATELIMITS).grantRole(CONTROLLER_ROLE, SLL_SWAP_CONTROLLER);
        IAccessControlEnumerable(swapAccessControls).grantRole(ALLOCATOR_ROLE,   SLL_ADMINISTERED_AGENT);

        _handOverAdmin(swapAccessControls,  Ethereum.SPARK_PROXY);
        _handOverAdmin(SLL_SWAP_RATELIMITS, Ethereum.SPARK_PROXY);
    }

    // Pre-requirement 9: Sky Core registers SwapAssetFacet on the Sky Beacon through a Sky executive spell.
    function _registerSwapAssetFacetOnSkyBeacon() internal {
        if (IBeaconLike(SKY_BEACON).getConfig(SWAP_ASSET_FACET_ID).facet != address(0)) return;

        _vm.prank(Ethereum.PAUSE_PROXY);
        IBeaconLike(SKY_BEACON).setIntegration(SWAP_ASSET_FACET_ID, _swapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
    }

    /**********************************************************************************************/
    /*** Arbitrum                                                                               ***/
    /**********************************************************************************************/

    function _deployArbitrumStandIns() internal {
        if (ARBITRUM_SPUSDT_PAU_CONTROLLER.code.length != 0) return;

        IPAUFactoryLike               pauFactory   = IPAUFactoryLike(Arbitrum.SPARK_PAU_FACTORY);
        IAdministeredAgentFactoryLike agentFactory = IAdministeredAgentFactoryLike(Arbitrum.SPARK_ADMINISTERED_AGENT_FACTORY);

        // Pre-deployed contracts 5: the actor of the Spark Vaults Administered Agent is TBD; a Planner agent with the hot wallet is used.
        address plannerAgent = agentFactory.deploy(address(this), "SPARK_PLANNER_ADMINISTERED_AGENT");

        _configureAgent(plannerAgent, SPARK_PLANNER_HOT_WALLET, address(0), address(0), Arbitrum.SPARK_EXECUTOR);

        _clone(agentFactory.deploy(address(this), "SPARK_ADMINISTERED_AGENT"), ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT);
        _configureAgent(ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT, plannerAgent, address(0), address(0), Arbitrum.SPARK_EXECUTOR);

        // Pre-deployed contracts 5: spUSDT PAU from the Arbitrum PAUFactory v1.16.0 (Beacon = new Spark Beacon); no integration
        //                           and no rate limit before the spell.
        address accessControls = pauFactory.deployAccessControls(address(this), "SPARK_SPUSDT_PAU");

        _clone(pauFactory.deployALMProxy(address(this),   "SPARK_SPUSDT_PAU"), ARBITRUM_SPUSDT_PAU_ALM_PROXY);
        _clone(pauFactory.deployRateLimits(address(this), "SPARK_SPUSDT_PAU"), ARBITRUM_SPUSDT_PAU_RATELIMITS);
        _clone(
            pauFactory.deployController(accessControls, ARBITRUM_SPUSDT_PAU_ALM_PROXY, ARBITRUM_SPUSDT_PAU_RATELIMITS, "SPARK_SPUSDT_PAU"),
            ARBITRUM_SPUSDT_PAU_CONTROLLER
        );

        IAccessControlEnumerable(ARBITRUM_SPUSDT_PAU_ALM_PROXY).grantRole(CONTROLLER_ROLE,  ARBITRUM_SPUSDT_PAU_CONTROLLER);
        IAccessControlEnumerable(ARBITRUM_SPUSDT_PAU_RATELIMITS).grantRole(CONTROLLER_ROLE, ARBITRUM_SPUSDT_PAU_CONTROLLER);
        IAccessControlEnumerable(accessControls).grantRole(ALLOCATOR_ROLE,                  ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT);

        _handOverAdmin(accessControls,                 Arbitrum.SPARK_EXECUTOR);
        _handOverAdmin(ARBITRUM_SPUSDT_PAU_ALM_PROXY,  Arbitrum.SPARK_EXECUTOR);
        _handOverAdmin(ARBITRUM_SPUSDT_PAU_RATELIMITS, Arbitrum.SPARK_EXECUTOR);
    }

    /**********************************************************************************************/
    /*** X Layer                                                                                ***/
    /**********************************************************************************************/

    function _deployXLayerStandIns() internal {
        if (XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT.code.length != 0) return;

        IAdministeredAgentFactoryV1Like agentFactory = IAdministeredAgentFactoryV1Like(XLayer.SPARK_ADMINISTERED_AGENT_FACTORY);

        // Pre-deployed contracts 6: the actor of the Spark Vaults Administered Agent is TBD; a Planner agent with the hot wallet is used.
        address plannerAgent = agentFactory.deploy(address(this));

        _configureAgent(plannerAgent, SPARK_PLANNER_HOT_WALLET, address(0), address(0), XLayer.SPARK_EXECUTOR);

        _clone(agentFactory.deploy(address(this)), XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT);
        _configureAgent(XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT, plannerAgent, address(0), address(0), XLayer.SPARK_EXECUTOR);
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    // Wires of BeaconConfig.buildSwapAssetIntegration (diamond-pau v1.16.0), selectors from `cast sig`.
    function _swapAssetIntegration(address facet) internal pure returns (IBeaconLike.Config memory) {
        IBeaconLike.Wire[] memory wires = new IBeaconLike.Wire[](5);

        wires[0] = IBeaconLike.Wire(0x26f3e880, 0x8b7db5c9);  // swapAsset_initiateSwap(address,address,address,uint256)
        wires[1] = IBeaconLike.Wire(0xd55ed608, 0x35c44997);  // swapAsset_completeSwap(address,address,uint256)
        wires[2] = IBeaconLike.Wire(0xd7847453, 0x4053450d);  // swapAsset_getInitiateSwapRateLimitKey(address,address,address,address)
        wires[3] = IBeaconLike.Wire(0x56585018, 0x91163c3e);  // swapAsset_getCompleteSwapRateLimitKey(address,address,address)
        wires[4] = IBeaconLike.Wire(0x8311a395, 0xffa1ad74);  // swapAsset_VERSION()

        return IBeaconLike.Config({ facet: facet, wires: wires });
    }

    function _configureAgent(address agent, address actor, address revoker, address grantor, address admin) internal {
        IAdministeredAgentLike(agent).addActor(actor);

        if (revoker != address(0)) IAdministeredAgentLike(agent).addRevoker(revoker);
        if (grantor != address(0)) IAdministeredAgentLike(agent).addGrantor(grantor);

        IAdministeredAgentLike(agent).addAdmin(admin);
        IAdministeredAgentLike(agent).removeAdmin(address(this));
    }

    function _handOverAdmin(address target, address admin) internal {
        IAccessControlEnumerable(target).grantRole(DEFAULT_ADMIN_ROLE, admin);
        IAccessControlEnumerable(target).renounceRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    function _clone(address source, address target) internal {
        _vm.etch(target, source.code);
        _vm.copyStorage(source, target);
    }

    // Clones a Controller and rewrites its `beacon` immutable (20 bytes embedded in the runtime code).
    function _cloneWithBeacon(address source, address target, address fromBeacon, address toBeacon) internal {
        bytes memory code = source.code;

        bytes20 from = bytes20(fromBeacon);
        bytes20 to   = bytes20(toBeacon);

        uint256 replaced;

        for (uint256 i = 0; i + 20 <= code.length; ++i) {
            bool matches = true;

            for (uint256 j = 0; j < 20; ++j) {
                if (code[i + j] != from[j]) {
                    matches = false;
                    break;
                }
            }

            if (!matches) continue;

            for (uint256 j = 0; j < 20; ++j) code[i + j] = to[j];

            ++replaced;
            i += 19;
        }

        require(replaced != 0, "StandIns/beacon-not-found");

        _vm.etch(target, code);
        _vm.copyStorage(source, target);
    }

}

contract SparkEthereum_20261203_SLLTests is SparkLiquidityLayerTests, SpUsdtPauStandIns {

    using DomainHelpers  for Domain;
    using OptionsBuilder for bytes;

    struct PauLayerZeroTransferParams {
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

    mapping(uint256 chainId => uint256 timestamp) internal forkTimestamp;

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        _recordForkTimestamps();

        _deployStandIns();

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

    function _deployStandIns() internal {
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        _deployEthereumStandIns();
        _registerSwapAssetFacetOnSkyBeacon();

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        _deployArbitrumStandIns();

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        _deployXLayerStandIns();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    /**********************************************************************************************/
    /*** Item 1.1: Spark Beacon integrations                                                    ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkBeacon_swapAssetIntegration() external onChain(ChainIdUtils.Ethereum()) {
        IBeaconLike beacon = IBeaconLike(Ethereum.SPARK_BEACON);

        assertEq(beacon.getConfig(SWAP_ASSET_FACET_ID).facet,        address(0));
        assertEq(beacon.getConfig(SWAP_ASSET_FACET_ID).wires.length, 0);

        _executeAllPayloadsAndBridges();

        IBeaconLike.Config memory config = beacon.getConfig(SWAP_ASSET_FACET_ID);

        assertEq(config.facet,        Ethereum.SWAP_ASSET_FACET);
        assertEq(config.wires.length, 5);

        _assertWire(config.wires[0], 0x26f3e880, 0x8b7db5c9);  // swapAsset_initiateSwap(address,address,address,uint256) -> initiateSwap(address,address,address,uint256)
        _assertWire(config.wires[1], 0xd55ed608, 0x35c44997);  // swapAsset_completeSwap(address,address,uint256) -> completeSwap(address,address,uint256)
        _assertWire(config.wires[2], 0xd7847453, 0x4053450d);  // swapAsset_getInitiateSwapRateLimitKey(address,address,address,address) -> getInitiateSwapRateLimitKey(address,address,address,address)
        _assertWire(config.wires[3], 0x56585018, 0x91163c3e);  // swapAsset_getCompleteSwapRateLimitKey(address,address,address) -> getCompleteSwapRateLimitKey(address,address,address)
        _assertWire(config.wires[4], 0x8311a395, 0xffa1ad74);  // swapAsset_VERSION() -> VERSION()
    }

    function test_ETHEREUM_sparkBeacon_layerZeroIntegration() external onChain(ChainIdUtils.Ethereum()) {
        IBeaconLike beacon = IBeaconLike(Ethereum.SPARK_BEACON);

        assertEq(beacon.getConfig(LAYER_ZERO_FACET_ID).facet,        address(0));
        assertEq(beacon.getConfig(LAYER_ZERO_FACET_ID).wires.length, 0);

        _executeAllPayloadsAndBridges();

        IBeaconLike.Config memory config = beacon.getConfig(LAYER_ZERO_FACET_ID);

        assertEq(config.facet,        Ethereum.LAYERZERO_FACET);
        assertEq(config.wires.length, 6);

        _assertWire(config.wires[0], 0xd59240e0, 0x2c2d8089);  // layerZero_setRecipient(uint32,bytes32) -> setRecipient(uint32,bytes32)
        _assertWire(config.wires[1], 0xdcc2a0d5, 0x67d709d0);  // layerZero_transfer(address,uint256,uint32) -> transfer(address,uint256,uint32)
        _assertWire(config.wires[2], 0xfe60c88e, 0xce36a3fa);  // layerZero_getRecipient(uint32) -> getRecipient(uint32)
        _assertWire(config.wires[3], 0xf70f6819, 0xcbb7a838);  // layerZero_getTransferRateLimitKey(address,bytes32,uint32,address) -> getTransferRateLimitKey(address,bytes32,uint32,address)
        _assertWire(config.wires[4], 0xe27f971d, 0x594568b4);  // layerZero_quoteTransfer(address,uint256,uint32) -> quoteTransfer(address,uint256,uint32)
        _assertWire(config.wires[5], 0x1e3c833f, 0xffa1ad74);  // layerZero_VERSION() -> VERSION()
    }

    function test_ETHEREUM_sparkBeacon_existingIntegrationsUnchanged() external onChain(ChainIdUtils.Ethereum()) {
        IBeaconLike beacon = IBeaconLike(Ethereum.SPARK_BEACON);

        assertEq(beacon.getConfig(CCTP_FACET_ID).facet,           Ethereum.CCTP_FACET);
        assertEq(beacon.getConfig(ERC4626_FACET_ID).facet,        Ethereum.ERC4626_FACET);
        assertEq(beacon.getConfig(SPARK_VAULT_FACET_ID).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(beacon.getConfig(TRANSFER_ASSET_FACET_ID).facet, Ethereum.TRANSFER_ASSET_FACET);

        assertEq(IAccessControlEnumerable(Ethereum.SPARK_BEACON).getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(IAccessControlEnumerable(Ethereum.SPARK_BEACON).getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        assertEq(beacon.getConfig(CCTP_FACET_ID).facet,           Ethereum.CCTP_FACET);
        assertEq(beacon.getConfig(ERC4626_FACET_ID).facet,        Ethereum.ERC4626_FACET);
        assertEq(beacon.getConfig(SPARK_VAULT_FACET_ID).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(beacon.getConfig(TRANSFER_ASSET_FACET_ID).facet, Ethereum.TRANSFER_ASSET_FACET);

        assertEq(IAccessControlEnumerable(Ethereum.SPARK_BEACON).getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(IAccessControlEnumerable(Ethereum.SPARK_BEACON).getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Ethereum.SPARK_PROXY);
    }

    /**********************************************************************************************/
    /*** Item 1.2: PAU integrations                                                             ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_integrations() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);

        assertEq(controller.beacon(),     Ethereum.SPARK_BEACON);
        assertEq(controller.proxy(),      SPUSDT_PAU_ALM_PROXY);
        assertEq(controller.rateLimits(), SPUSDT_PAU_RATELIMITS);

        // Enabled at deployment (Pre-deployed contracts 1).
        assertEq(controller.getConfig(ERC4626_FACET_ID).facet,        Ethereum.ERC4626_FACET);
        assertEq(controller.getConfig(SPARK_VAULT_FACET_ID).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(TRANSFER_ASSET_FACET_ID).facet, Ethereum.TRANSFER_ASSET_FACET);

        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).facet, address(0));
        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).facet, address(0));

        assertEq(controller.getDispatch(0xd59240e0).facet, address(0));  // layerZero_setRecipient(uint32,bytes32)
        assertEq(controller.getDispatch(0x26f3e880).facet, address(0));  // swapAsset_initiateSwap(address,address,address,uint256)

        _executeAllPayloadsAndBridges();

        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).facet,        Ethereum.LAYERZERO_FACET);
        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).wires.length, 6);
        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).facet,        Ethereum.SWAP_ASSET_FACET);
        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).wires.length, 5);

        _assertDispatch(controller, 0xd59240e0, Ethereum.LAYERZERO_FACET, 0x2c2d8089);  // layerZero_setRecipient -> setRecipient
        _assertDispatch(controller, 0xdcc2a0d5, Ethereum.LAYERZERO_FACET, 0x67d709d0);  // layerZero_transfer -> transfer
        _assertDispatch(controller, 0xfe60c88e, Ethereum.LAYERZERO_FACET, 0xce36a3fa);  // layerZero_getRecipient -> getRecipient
        _assertDispatch(controller, 0xf70f6819, Ethereum.LAYERZERO_FACET, 0xcbb7a838);  // layerZero_getTransferRateLimitKey -> getTransferRateLimitKey
        _assertDispatch(controller, 0xe27f971d, Ethereum.LAYERZERO_FACET, 0x594568b4);  // layerZero_quoteTransfer -> quoteTransfer
        _assertDispatch(controller, 0x1e3c833f, Ethereum.LAYERZERO_FACET, 0xffa1ad74);  // layerZero_VERSION -> VERSION

        _assertDispatch(controller, 0x26f3e880, Ethereum.SWAP_ASSET_FACET, 0x8b7db5c9);  // swapAsset_initiateSwap -> initiateSwap
        _assertDispatch(controller, 0xd55ed608, Ethereum.SWAP_ASSET_FACET, 0x35c44997);  // swapAsset_completeSwap -> completeSwap
        _assertDispatch(controller, 0xd7847453, Ethereum.SWAP_ASSET_FACET, 0x4053450d);  // swapAsset_getInitiateSwapRateLimitKey -> getInitiateSwapRateLimitKey
        _assertDispatch(controller, 0x56585018, Ethereum.SWAP_ASSET_FACET, 0x91163c3e);  // swapAsset_getCompleteSwapRateLimitKey -> getCompleteSwapRateLimitKey
        _assertDispatch(controller, 0x8311a395, Ethereum.SWAP_ASSET_FACET, 0xffa1ad74);  // swapAsset_VERSION -> VERSION

        // Unchanged.
        assertEq(controller.getConfig(ERC4626_FACET_ID).facet,        Ethereum.ERC4626_FACET);
        assertEq(controller.getConfig(SPARK_VAULT_FACET_ID).facet,    Ethereum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(TRANSFER_ASSET_FACET_ID).facet, Ethereum.TRANSFER_ASSET_FACET);
    }

    function test_ETHEREUM_sllSwapController_integration() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SLL_SWAP_CONTROLLER);

        // The swap controller takes its integrations from the Sky Beacon (Pre-requirement 9).
        address facet = IBeaconLike(SKY_BEACON).getConfig(SWAP_ASSET_FACET_ID).facet;

        assertTrue(facet != address(0));

        assertEq(controller.beacon(),     SKY_BEACON);
        assertEq(controller.proxy(),      Ethereum.ALM_PROXY);
        assertEq(controller.rateLimits(), SLL_SWAP_RATELIMITS);

        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).facet, address(0));
        assertEq(controller.getDispatch(0x26f3e880).facet,       address(0));  // swapAsset_initiateSwap(address,address,address,uint256)

        _executeAllPayloadsAndBridges();

        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).facet,        facet);
        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).wires.length, 5);

        _assertDispatch(controller, 0x26f3e880, facet, 0x8b7db5c9);  // swapAsset_initiateSwap -> initiateSwap
        _assertDispatch(controller, 0xd55ed608, facet, 0x35c44997);  // swapAsset_completeSwap -> completeSwap
        _assertDispatch(controller, 0xd7847453, facet, 0x4053450d);  // swapAsset_getInitiateSwapRateLimitKey -> getInitiateSwapRateLimitKey
        _assertDispatch(controller, 0x56585018, facet, 0x91163c3e);  // swapAsset_getCompleteSwapRateLimitKey -> getCompleteSwapRateLimitKey
        _assertDispatch(controller, 0x8311a395, facet, 0xffa1ad74);  // swapAsset_VERSION -> VERSION

        // The swap controller carries only this facet.
        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).facet,     address(0));
        assertEq(controller.getConfig(TRANSFER_ASSET_FACET_ID).facet, address(0));
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,           address(0));
    }

    /**********************************************************************************************/
    /*** Item 1.3: spUSDT roles                                                                 ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdt_roles() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        assertEq(takerRole,  0x508ee82d0bdf04e000303ab4f02b172e60c5f2d35b2e559b05bed2cf403bb58b);
        assertEq(setterRole, 0x61c92169ef077349011ff0b1383c894d86c5f0b41d986366b58a6cf31e93beda);

        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   Ethereum.ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   Ethereum.ALM_PROXY_FREEZABLE);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Ethereum.SPARK_PROXY);

        _executeAllPayloadsAndBridges();

        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   SPUSDT_PAU_ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   SPARK_VAULTS_ADMINISTERED_AGENT);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Ethereum.SPARK_PROXY);

        assertEq(spUsdt.hasRole(takerRole,  Ethereum.ALM_PROXY),           false);
        assertEq(spUsdt.hasRole(setterRole, Ethereum.ALM_PROXY_FREEZABLE), false);
    }

    function test_ETHEREUM_spUsdt_configUnchanged() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        _warpToForkBlock(ChainIdUtils.Ethereum());

        uint256 totalAssets = spUsdt.totalAssets();
        uint256 totalSupply = spUsdt.totalSupply();
        uint256 vsr         = spUsdt.vsr();
        uint256 minVsr      = spUsdt.minVsr();
        uint256 maxVsr      = spUsdt.maxVsr();

        assertEq(spUsdt.depositCap(), 4_000_000_000e6);

        _executeAllPayloadsAndBridges();

        // Fork switches during execution can pick up a timestamp leaked by a parallel test; re-pin before time-derived reads.
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(spUsdt.totalAssets(), totalAssets);
        assertEq(spUsdt.totalSupply(), totalSupply);
        assertEq(spUsdt.vsr(),         vsr);
        assertEq(spUsdt.minVsr(),      minVsr);
        assertEq(spUsdt.maxVsr(),      maxVsr);
        assertEq(spUsdt.depositCap(),  4_000_000_000e6);
    }

    /**********************************************************************************************/
    /*** Item 1.4: spUSDT PAU LayerZero limits and recipients                                   ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_layerZeroRateLimits() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);

        // The USDT0 OFT adapter's peers are the USDT0 OFTs on Arbitrum and X Layer.
        bytes32 arbitrumPeer = IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_ARBITRUM);
        bytes32 xlayerPeer   = IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_XLAYER);

        assertEq(arbitrumPeer, bytes32(uint256(uint160(USDT0_OFT_ARBITRUM))));
        assertEq(xlayerPeer,   bytes32(uint256(uint160(USDT0_OFT_XLAYER))));

        // Same derivation as LayerZeroFacet.getTransferRateLimitKey: (token, oft, peer, destination endpoint).
        bytes32 arbitrumKey = keccak256(abi.encode(keccak256("LIMIT_LAYERZERO_TRANSFER"), Ethereum.USDT, Ethereum.USDT_OFT, arbitrumPeer, LZ_EID_ARBITRUM));
        bytes32 xlayerKey   = keccak256(abi.encode(keccak256("LIMIT_LAYERZERO_TRANSFER"), Ethereum.USDT, Ethereum.USDT_OFT, xlayerPeer,   LZ_EID_XLAYER));

        _assertRateLimit(SPUSDT_PAU_RATELIMITS, arbitrumKey, 0, 0);
        _assertRateLimit(SPUSDT_PAU_RATELIMITS, xlayerKey,   0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZero_getTransferRateLimitKey(Ethereum.USDT_OFT, arbitrumPeer, LZ_EID_ARBITRUM, Ethereum.USDT), arbitrumKey);
        assertEq(controller.layerZero_getTransferRateLimitKey(Ethereum.USDT_OFT, xlayerPeer,   LZ_EID_XLAYER,   Ethereum.USDT), xlayerKey);

        _assertRateLimit(SPUSDT_PAU_RATELIMITS, arbitrumKey, 5_000_000e6, uint256(50_000_000e6)  / 1 days);
        _assertRateLimit(SPUSDT_PAU_RATELIMITS, xlayerKey,   5_000_000e6, uint256(100_000_000e6) / 1 days);

        assertEq(uint256(50_000_000e6)  / 1 days, 578_703_703);
        assertEq(uint256(100_000_000e6) / 1 days, 1_157_407_407);
    }

    function test_ETHEREUM_spUsdtPau_layerZeroRecipients() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);

        // The LayerZero facet is not wired before the spell (CallSelectorNotWired).
        vm.expectRevert();
        controller.layerZero_getRecipient(LZ_EID_ARBITRUM);

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZero_getRecipient(LZ_EID_ARBITRUM), bytes32(uint256(uint160(ARBITRUM_SPUSDT_PAU_ALM_PROXY))));
        assertEq(controller.layerZero_getRecipient(LZ_EID_XLAYER),   bytes32(uint256(uint160(XLayer.ALM_PROXY))));
        assertEq(controller.layerZero_getRecipient(LZ_EID_ETHEREUM), bytes32(0));
    }

    /**********************************************************************************************/
    /*** Item 1.5: Spark Liquidity Layer keys zeroed                                            ***/
    /**********************************************************************************************/

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

    /**********************************************************************************************/
    /*** Item 1.6: Swap controller on the Spark Liquidity Layer                                 ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sllSwapController_controllerRole() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxy almProxy = IALMProxy(Ethereum.ALM_PROXY);

        bytes32 controllerRole = almProxy.CONTROLLER();

        assertEq(controllerRole, 0x70546d1c92f8c2132ae23a23f5177aa8526356051c7510df99f50e012d221529);

        assertEq(almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER), true);
        assertEq(almProxy.hasRole(controllerRole, SLL_SWAP_CONTROLLER),     false);
        assertEq(almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),    false);

        _executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(controllerRole, Ethereum.ALM_CONTROLLER), true);
        assertEq(almProxy.hasRole(controllerRole, SLL_SWAP_CONTROLLER),     true);
        assertEq(almProxy.hasRole(controllerRole, Ethereum.SPARK_PROXY),    false);  // Transient grant of 1.8 revoked
    }

    function test_ETHEREUM_sllSwapController_rateLimits() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SLL_SWAP_CONTROLLER);

        // Same derivation as SwapAssetFacet.getInitiateSwapRateLimitKey.
        bytes32 usdsOutKey = keccak256(abi.encode(keccak256("LIMIT_SWAP_ASSET_INITIATE"), Ethereum.USDS, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDT));
        bytes32 usdtOutKey = keccak256(abi.encode(keccak256("LIMIT_SWAP_ASSET_INITIATE"), Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDS));

        _assertRateLimit(SLL_SWAP_RATELIMITS, usdsOutKey, 0, 0);
        _assertRateLimit(SLL_SWAP_RATELIMITS, usdtOutKey, 0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDS, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDT), usdsOutKey);
        assertEq(controller.swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDS), usdtOutKey);

        _assertRateLimit(SLL_SWAP_RATELIMITS, usdsOutKey, 100_000_000e18, uint256(500_000_000e18) / 1 days);
        _assertRateLimit(SLL_SWAP_RATELIMITS, usdtOutKey, 100_000_000e6,  uint256(500_000_000e6)  / 1 days);
    }

    /**********************************************************************************************/
    /*** Item 1.7: Swap limits on the spUSDT PAU                                                ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_swapRateLimits() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);

        // Same derivation as SwapAssetFacet.getCompleteSwapRateLimitKey.
        bytes32 usdtOutKey = keccak256(abi.encode(keccak256("LIMIT_SWAP_ASSET_COMPLETE"), Ethereum.USDT, Ethereum.ALM_PROXY, Ethereum.USDS));
        bytes32 usdsOutKey = keccak256(abi.encode(keccak256("LIMIT_SWAP_ASSET_COMPLETE"), Ethereum.USDS, Ethereum.ALM_PROXY, Ethereum.USDT));

        _assertRateLimit(SPUSDT_PAU_RATELIMITS, usdtOutKey, 0, 0);
        _assertRateLimit(SPUSDT_PAU_RATELIMITS, usdsOutKey, 0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, Ethereum.USDS), usdtOutKey);
        assertEq(controller.swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDS, Ethereum.ALM_PROXY, Ethereum.USDT), usdsOutKey);

        _assertRateLimit(SPUSDT_PAU_RATELIMITS, usdtOutKey, 100_000_000e6,  uint256(1_000_000_000e6)  / 1 days);
        _assertRateLimit(SPUSDT_PAU_RATELIMITS, usdsOutKey, 100_000_000e18, uint256(1_000_000_000e18) / 1 days);

        // No initiate key on the spUSDT PAU, so it cannot start a swap.
        _assertRateLimit(
            SPUSDT_PAU_RATELIMITS,
            keccak256(abi.encode(keccak256("LIMIT_SWAP_ASSET_INITIATE"), Ethereum.USDT, Ethereum.ALM_PROXY, SLL_SWAP_CONTROLLER, Ethereum.USDS)),
            0,
            0
        );
    }

    /**********************************************************************************************/
    /*** Item 1.8: sUSDS backing                                                                ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_susdsBacking() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);
        IERC4626        susds  = IERC4626(Ethereum.SUSDS);

        // `assetsOutstanding` accrues with the vault rate from the fork timestamp.
        _warpToForkBlock(ChainIdUtils.Ethereum());

        uint256 assetsOutstanding = spUsdt.assetsOutstanding();

        assertEq(assetsOutstanding, 251_733_540.667095e6);
        assertEq(assetsOutstanding, spUsdt.totalAssets() - IERC20(Ethereum.USDT).balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT));

        uint256 expectedShares = susds.convertToShares(assetsOutstanding * 1e12);

        assertEq(expectedShares, 225_395_490.431514946117282037e18);

        assertEq(susds.balanceOf(Ethereum.ALM_PROXY),   529_337_328.926854696446482965e18);
        assertEq(susds.balanceOf(SPUSDT_PAU_ALM_PROXY), 0);

        _executeAllPayloadsAndBridges();

        // Fork switches during execution can pick up a timestamp leaked by a parallel test; re-pin before time-derived reads.
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(susds.balanceOf(Ethereum.ALM_PROXY),   529_337_328.926854696446482965e18 - 225_395_490.431514946117282037e18);
        assertEq(susds.balanceOf(SPUSDT_PAU_ALM_PROXY), 225_395_490.431514946117282037e18);

        // The spUSDT PAU's sUSDS is worth the USDT owed by the vault, in USDS.
        assertApproxEqAbs(susds.convertToAssets(expectedShares), assetsOutstanding * 1e12, 2);
        assertLe(susds.convertToAssets(expectedShares),          assetsOutstanding * 1e12);

        assertEq(spUsdt.assetsOutstanding(), assetsOutstanding);
    }

    /**********************************************************************************************/
    /*** Item 1: spUSDT PAU flows                                                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_spUsdtPau_takeAndTransfer() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);
        IRateLimits     rateLimits = IRateLimits(SPUSDT_PAU_RATELIMITS);
        IERC20          usdt       = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        bytes32 takeKey     = controller.sparkVault_getTakeRateLimitKey(Ethereum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey = controller.transferAsset_getTransferRateLimitKey(Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT);

        assertEq(rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        uint256 vaultBalance = usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT);
        uint256 pauBalance   = usdt.balanceOf(SPUSDT_PAU_ALM_PROXY);

        _callAsAgent(
            SPARK_VAULTS_ADMINISTERED_AGENT,
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.sparkVault_take, (Ethereum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6))
        );

        assertEq(usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY),           pauBalance + 1_000_000e6);

        _callAsAgent(
            SPARK_VAULTS_ADMINISTERED_AGENT,
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.transferAsset_transfer, (Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6))
        );

        assertEq(usdt.balanceOf(Ethereum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY),           pauBalance);

        assertEq(rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);
    }

    function test_ETHEREUM_spUsdtPau_susdsWithdrawAndDeposit() external onChain(ChainIdUtils.Ethereum()) {
        IControllerLike controller = IControllerLike(SPUSDT_PAU_CONTROLLER);
        IRateLimits     rateLimits = IRateLimits(SPUSDT_PAU_RATELIMITS);
        IERC4626        susds      = IERC4626(Ethereum.SUSDS);
        IERC20          usds       = IERC20(Ethereum.USDS);

        _executeAllPayloadsAndBridges();

        // Fork switches during execution can pick up a timestamp leaked by a parallel test; re-pin before time-derived reads.
        _warpToForkBlock(ChainIdUtils.Ethereum());

        assertEq(rateLimits.getCurrentRateLimit(controller.erc4626_getDepositRateLimitKey(Ethereum.SUSDS, Ethereum.USDS)), type(uint256).max);
        assertEq(rateLimits.getCurrentRateLimit(controller.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDS)),               type(uint256).max);

        uint256 sharesBefore = susds.balanceOf(SPUSDT_PAU_ALM_PROXY);

        assertGt(sharesBefore, 0);
        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), 0);

        // Redeem sUSDS for 1,000,000 USDS to meet withdrawals.
        _callAsAgent(
            SPARK_VAULTS_ADMINISTERED_AGENT,
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.erc4626_withdraw, (Ethereum.SUSDS, 1_000_000e18, type(uint256).max))
        );

        uint256 sharesRedeemed = sharesBefore - susds.balanceOf(SPUSDT_PAU_ALM_PROXY);

        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), 1_000_000e18);
        assertApproxEqAbs(susds.convertToAssets(sharesRedeemed), 1_000_000e18, 2);

        // Deposit the USDS back into sUSDS.
        _callAsAgent(
            SPARK_VAULTS_ADMINISTERED_AGENT,
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.erc4626_deposit, (Ethereum.SUSDS, 1_000_000e18, 0))
        );

        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), 0);
        assertApproxEqAbs(susds.balanceOf(SPUSDT_PAU_ALM_PROXY), sharesBefore, 2);
    }

    function test_ETHEREUM_sll_swapUsdsForUsdt() external onChain(ChainIdUtils.Ethereum()) {
        IRateLimits sllRateLimits = IRateLimits(SLL_SWAP_RATELIMITS);
        IRateLimits pauRateLimits = IRateLimits(SPUSDT_PAU_RATELIMITS);
        IERC20      usds          = IERC20(Ethereum.USDS);
        IERC20      usdt          = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        bytes32 initiateUsdsOutKey = IControllerLike(SLL_SWAP_CONTROLLER).swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDS, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDT);
        bytes32 initiateUsdtOutKey = IControllerLike(SLL_SWAP_CONTROLLER).swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDS);
        bytes32 completeUsdtOutKey = IControllerLike(SPUSDT_PAU_CONTROLLER).swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, Ethereum.USDS);
        bytes32 completeUsdsOutKey = IControllerLike(SPUSDT_PAU_CONTROLLER).swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDS, Ethereum.ALM_PROXY, Ethereum.USDT);

        // The spUSDT PAU holds USDT taken from the vault; the Spark Liquidity Layer holds idle USDS.
        deal(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, 1_000_000e6);
        deal(Ethereum.USDS, Ethereum.ALM_PROXY,   1_000_000e18);

        uint256 sllUsds = usds.balanceOf(Ethereum.ALM_PROXY);
        uint256 sllUsdt = usdt.balanceOf(Ethereum.ALM_PROXY);
        uint256 pauUsds = usds.balanceOf(SPUSDT_PAU_ALM_PROXY);

        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdsOutKey), 100_000_000e18);
        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdtOutKey), 100_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdtOutKey), 100_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdsOutKey), 100_000_000e18);

        // The Spark Liquidity Layer swaps 1,000,000 USDS for 1,000,000 USDT from the spUSDT PAU.
        _callAsAgent(
            SLL_ADMINISTERED_AGENT,
            SLL_SWAP_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 1_000_000e18))
        );

        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),   sllUsds - 1_000_000e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),   sllUsdt + 1_000_000e6);
        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), pauUsds + 1_000_000e18);
        assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY), 0);

        // Each side consumed its own limit; the opposite direction was already at its maximum.
        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdsOutKey), 99_000_000e18);
        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdtOutKey), 100_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdtOutKey), 99_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdsOutKey), 100_000_000e18);

        assertEq(usds.allowance(Ethereum.ALM_PROXY, SPUSDT_PAU_ALM_PROXY), 0);
    }

    function test_ETHEREUM_sll_swapUsdtForUsds() external onChain(ChainIdUtils.Ethereum()) {
        IRateLimits sllRateLimits = IRateLimits(SLL_SWAP_RATELIMITS);
        IRateLimits pauRateLimits = IRateLimits(SPUSDT_PAU_RATELIMITS);
        IERC20      usds          = IERC20(Ethereum.USDS);
        IERC20      usdt          = IERC20(Ethereum.USDT);

        _warpToForkBlock(ChainIdUtils.Ethereum());

        _executeAllPayloadsAndBridges();

        bytes32 initiateUsdsOutKey = IControllerLike(SLL_SWAP_CONTROLLER).swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDS, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDT);
        bytes32 initiateUsdtOutKey = IControllerLike(SLL_SWAP_CONTROLLER).swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDS);
        bytes32 completeUsdtOutKey = IControllerLike(SPUSDT_PAU_CONTROLLER).swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, Ethereum.USDS);
        bytes32 completeUsdsOutKey = IControllerLike(SPUSDT_PAU_CONTROLLER).swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDS, Ethereum.ALM_PROXY, Ethereum.USDT);

        // The spUSDT PAU redeems sUSDS for the USDS it pays.
        _callAsAgent(
            SPARK_VAULTS_ADMINISTERED_AGENT,
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.erc4626_withdraw, (Ethereum.SUSDS, 1_000_000e18, type(uint256).max))
        );

        deal(Ethereum.USDT, Ethereum.ALM_PROXY, 1_000_000e6);

        uint256 sllUsds = usds.balanceOf(Ethereum.ALM_PROXY);
        uint256 pauUsdt = usdt.balanceOf(SPUSDT_PAU_ALM_PROXY);

        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), 1_000_000e18);

        // The Spark Liquidity Layer swaps 1,000,000 USDT for 1,000,000 USDS from the spUSDT PAU.
        _callAsAgent(
            SLL_ADMINISTERED_AGENT,
            SLL_SWAP_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SPUSDT_PAU_CONTROLLER, Ethereum.USDT, Ethereum.USDS, 1_000_000e6))
        );

        assertEq(usds.balanceOf(Ethereum.ALM_PROXY),   sllUsds + 1_000_000e18);
        assertEq(usdt.balanceOf(Ethereum.ALM_PROXY),   0);
        assertEq(usds.balanceOf(SPUSDT_PAU_ALM_PROXY), 0);
        assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY), pauUsdt + 1_000_000e6);

        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdsOutKey), 100_000_000e18);
        assertEq(sllRateLimits.getCurrentRateLimit(initiateUsdtOutKey), 99_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdtOutKey), 100_000_000e6);
        assertEq(pauRateLimits.getCurrentRateLimit(completeUsdsOutKey), 99_000_000e18);

        assertEq(usdt.allowance(Ethereum.ALM_PROXY, SPUSDT_PAU_ALM_PROXY), 0);
    }

    function test_ETHEREUM_sll_swap_rateLimitEnforced() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        deal(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, 101_000_000e6);
        deal(Ethereum.USDS, Ethereum.ALM_PROXY,   101_000_000e18);

        ( address plannerAgent, address hotWallet ) = _agentActors(SLL_ADMINISTERED_AGENT);

        bytes memory data = abi.encodeCall(IAdministeredAgentLike.call, (
            SLL_SWAP_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 100_000_000e18 + 1e12))
        ));

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(hotWallet);
        IAdministeredAgentLike(plannerAgent).call(SLL_ADMINISTERED_AGENT, data);

        // 1 USDS and 1 wei cannot be scaled to USDT.
        data = abi.encodeCall(IAdministeredAgentLike.call, (
            SLL_SWAP_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 1e18 + 1))
        ));

        vm.expectRevert("SwapAssetFacet/precision-loss");
        vm.prank(hotWallet);
        IAdministeredAgentLike(plannerAgent).call(SLL_ADMINISTERED_AGENT, data);

        // The spUSDT PAU cannot start a swap: no initiate key is set on it.
        ( plannerAgent, hotWallet ) = _agentActors(SPARK_VAULTS_ADMINISTERED_AGENT);

        data = abi.encodeCall(IAdministeredAgentLike.call, (
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SLL_SWAP_CONTROLLER, Ethereum.USDT, Ethereum.USDS, 1e6))
        ));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(hotWallet);
        IAdministeredAgentLike(plannerAgent).call(SPARK_VAULTS_ADMINISTERED_AGENT, data);

        // The full maximum passes.
        _callAsAgent(
            SLL_ADMINISTERED_AGENT,
            SLL_SWAP_CONTROLLER,
            abi.encodeCall(IControllerLike.swapAsset_initiateSwap, (SPUSDT_PAU_CONTROLLER, Ethereum.USDS, Ethereum.USDT, 100_000_000e18))
        );

        assertEq(IERC20(Ethereum.USDT).balanceOf(SPUSDT_PAU_ALM_PROXY), 1_000_000e6);
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToArbitrum() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        bytes32 peer = IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_ARBITRUM);

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            agent:                 SPARK_VAULTS_ADMINISTERED_AGENT,
            controller:            SPUSDT_PAU_CONTROLLER,
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
            transferKey:           IControllerLike(SPUSDT_PAU_CONTROLLER).layerZero_getTransferRateLimitKey(Ethereum.USDT_OFT, peer, LZ_EID_ARBITRUM, Ethereum.USDT)
        }));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroTransferToXLayer() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        bytes32 peer = IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_XLAYER);

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            agent:                 SPARK_VAULTS_ADMINISTERED_AGENT,
            controller:            SPUSDT_PAU_CONTROLLER,
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
            transferKey:           IControllerLike(SPUSDT_PAU_CONTROLLER).layerZero_getTransferRateLimitKey(Ethereum.USDT_OFT, peer, LZ_EID_XLAYER, Ethereum.USDT)
        }));
    }

    function test_ETHEREUM_spUsdtPau_layerZeroRateLimitEnforced() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        deal(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, 5_000_000e6 + 1);

        ( address plannerAgent, address hotWallet ) = _agentActors(SPARK_VAULTS_ADMINISTERED_AGENT);

        ( , MessagingFee memory fee ) = IControllerLike(SPUSDT_PAU_CONTROLLER).layerZero_quoteTransfer(Ethereum.USDT_OFT, 5_000_000e6 + 1, LZ_EID_ARBITRUM);

        vm.deal(hotWallet, fee.nativeFee);

        bytes memory data = abi.encodeCall(IAdministeredAgentLike.call, (
            SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.layerZero_transfer, (Ethereum.USDT_OFT, 5_000_000e6 + 1, LZ_EID_ARBITRUM))
        ));

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        vm.prank(hotWallet);
        IAdministeredAgentLike(plannerAgent).call{ value: fee.nativeFee }(SPARK_VAULTS_ADMINISTERED_AGENT, data);
    }

    /**********************************************************************************************/
    /*** Item 2: Arbitrum                                                                       ***/
    /**********************************************************************************************/

    function test_ARBITRUM_spUsdtPau_integrations() external onChain(ChainIdUtils.ArbitrumOne()) {
        IControllerLike controller = IControllerLike(ARBITRUM_SPUSDT_PAU_CONTROLLER);

        assertEq(controller.beacon(),     Arbitrum.SPARK_BEACON);
        assertEq(controller.proxy(),      ARBITRUM_SPUSDT_PAU_ALM_PROXY);
        assertEq(controller.rateLimits(), ARBITRUM_SPUSDT_PAU_RATELIMITS);

        assertEq(controller.getConfig(SPARK_VAULT_FACET_ID).facet,    address(0));
        assertEq(controller.getConfig(TRANSFER_ASSET_FACET_ID).facet, address(0));
        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).facet,     address(0));

        _executeAllPayloadsAndBridges();

        assertEq(controller.getConfig(SPARK_VAULT_FACET_ID).facet,    Arbitrum.SPARK_VAULT_FACET);
        assertEq(controller.getConfig(TRANSFER_ASSET_FACET_ID).facet, Arbitrum.TRANSFER_ASSET_FACET);
        assertEq(controller.getConfig(LAYER_ZERO_FACET_ID).facet,     Arbitrum.LAYER_ZERO_FACET);

        _assertDispatch(controller, 0x4f985c34, Arbitrum.SPARK_VAULT_FACET,    0x52180208);  // sparkVault_take(address,uint256) -> take(address,uint256)
        _assertDispatch(controller, 0x56ebb17a, Arbitrum.TRANSFER_ASSET_FACET, 0xbeabacc8);  // transferAsset_transfer(address,address,uint256) -> transfer(address,address,uint256)
        _assertDispatch(controller, 0xdcc2a0d5, Arbitrum.LAYER_ZERO_FACET,     0x67d709d0);  // layerZero_transfer(address,uint256,uint32) -> transfer(address,uint256,uint32)
        _assertDispatch(controller, 0xd59240e0, Arbitrum.LAYER_ZERO_FACET,     0x2c2d8089);  // layerZero_setRecipient(uint32,bytes32) -> setRecipient(uint32,bytes32)

        // The other facets registered on the Beacon are not enabled.
        assertEq(controller.getConfig(ERC4626_FACET_ID).facet,    address(0));
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,       address(0));
        assertEq(controller.getConfig(SWAP_ASSET_FACET_ID).facet, address(0));
    }

    function test_ARBITRUM_spUsdt_roles() external onChain(ChainIdUtils.ArbitrumOne()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   Arbitrum.ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   Arbitrum.ALM_PROXY_FREEZABLE);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Arbitrum.SPARK_EXECUTOR);

        _executeAllPayloadsAndBridges();

        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   ARBITRUM_SPUSDT_PAU_ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   Arbitrum.SPARK_EXECUTOR);
    }

    function test_ARBITRUM_spUsdtPau_rateLimits() external onChain(ChainIdUtils.ArbitrumOne()) {
        IControllerLike controller = IControllerLike(ARBITRUM_SPUSDT_PAU_CONTROLLER);

        bytes32 peer = IOFTLike(Arbitrum.USDT_OFT).peers(LZ_EID_ETHEREUM);

        assertEq(peer, bytes32(uint256(uint160(USDT_OFT))));

        // Same derivations as the SparkVault, TransferAsset and LayerZero facets.
        bytes32 takeKey      = RateLimitHelpers.makeAddressKey(keccak256("LIMIT_SPARK_VAULT_TAKE"), Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey  = RateLimitHelpers.makeAddressAddressKey(keccak256("LIMIT_ASSET_TRANSFER"), Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT);
        bytes32 layerZeroKey = keccak256(abi.encode(keccak256("LIMIT_LAYERZERO_TRANSFER"), Arbitrum.USDT0, Arbitrum.USDT_OFT, peer, LZ_EID_ETHEREUM));

        _assertRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, takeKey,      0, 0);
        _assertRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, transferKey,  0, 0);
        _assertRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, layerZeroKey, 0, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT),                                        takeKey);
        assertEq(controller.transferAsset_getTransferRateLimitKey(Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT),                 transferKey);
        assertEq(controller.layerZero_getTransferRateLimitKey(Arbitrum.USDT_OFT, peer, LZ_EID_ETHEREUM, Arbitrum.USDT0),          layerZeroKey);

        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, takeKey);
        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, transferKey);
        _assertUnlimitedRateLimit(ARBITRUM_SPUSDT_PAU_RATELIMITS, layerZeroKey);
    }

    function test_ARBITRUM_spUsdtPau_layerZeroRecipient() external onChain(ChainIdUtils.ArbitrumOne()) {
        IControllerLike controller = IControllerLike(ARBITRUM_SPUSDT_PAU_CONTROLLER);

        // The LayerZero facet is not wired before the spell (CallSelectorNotWired).
        vm.expectRevert();
        controller.layerZero_getRecipient(LZ_EID_ETHEREUM);

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZero_getRecipient(LZ_EID_ETHEREUM), bytes32(uint256(uint160(SPUSDT_PAU_ALM_PROXY))));
        assertEq(controller.layerZero_getRecipient(LZ_EID_XLAYER),   bytes32(0));
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

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, takeKey,      0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, transferKey,  0, 0);
        _assertRateLimit(Arbitrum.ALM_RATE_LIMITS, layerZeroKey, 0, 0);

        // The legacy recipient is left in place; its route has no limit.
        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));

        vm.expectRevert("RateLimits/zero-maxAmount");
        vm.prank(Arbitrum.ALM_RELAYER_MULTISIG);
        controller.takeFromSparkVault(Arbitrum.SPARK_VAULT_V2_SPUSDT, 1e6);
    }

    function test_ARBITRUM_spUsdt_noFundsMove() external onChain(ChainIdUtils.ArbitrumOne()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);
        IERC20          usdt0  = IERC20(Arbitrum.USDT0);

        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        uint256 vaultBalance = usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);
        uint256 totalAssets  = spUsdt.totalAssets();

        assertEq(usdt0.balanceOf(Arbitrum.ALM_PROXY),            0);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY), 0);

        _executeAllPayloadsAndBridges();

        // Fork switches during execution can pick up a timestamp leaked by a parallel test; re-pin before time-derived reads.
        _warpToForkBlock(ChainIdUtils.ArbitrumOne());

        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(usdt0.balanceOf(Arbitrum.ALM_PROXY),             0);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  0);

        assertEq(spUsdt.totalAssets(), totalAssets);
    }

    function test_ARBITRUM_spUsdtPau_takeAndTransfer() external onChain(ChainIdUtils.ArbitrumOne()) {
        IERC20 usdt0 = IERC20(Arbitrum.USDT0);

        _executeAllPayloadsAndBridges();

        uint256 vaultBalance = usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        assertGe(vaultBalance, 1_000_000e6);

        _callAsAgent(
            ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT,
            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.sparkVault_take, (Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6))
        );

        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance - 1_000_000e6);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  1_000_000e6);

        _callAsAgent(
            ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT,
            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            abi.encodeCall(IControllerLike.transferAsset_transfer, (Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT, 1_000_000e6))
        );

        assertEq(usdt0.balanceOf(Arbitrum.SPARK_VAULT_V2_SPUSDT), vaultBalance);
        assertEq(usdt0.balanceOf(ARBITRUM_SPUSDT_PAU_ALM_PROXY),  0);
    }

    function test_ARBITRUM_spUsdtPau_layerZeroTransferToEthereum() external onChain(ChainIdUtils.ArbitrumOne()) {
        _executeAllPayloadsAndBridges();

        bytes32 peer = IOFTLike(Arbitrum.USDT_OFT).peers(LZ_EID_ETHEREUM);

        _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams({
            agent:                 ARBITRUM_SPARK_VAULTS_ADMINISTERED_AGENT,
            controller:            ARBITRUM_SPUSDT_PAU_CONTROLLER,
            oft:                   Arbitrum.USDT_OFT,
            asset:                 Arbitrum.USDT0,
            amount:                1_000_000e6,
            destinationEndpointId: LZ_EID_ETHEREUM,
            destinationChainId:    ChainIdUtils.Ethereum(),
            destinationOft:        USDT_OFT,
            destinationAsset:      Ethereum.USDT,
            destinationReceiver:   SPUSDT_PAU_ALM_PROXY,
            sourceEndpointId:      LZ_EID_ARBITRUM,
            sourceChainId:         ChainIdUtils.ArbitrumOne(),
            transferKey:           IControllerLike(ARBITRUM_SPUSDT_PAU_CONTROLLER).layerZero_getTransferRateLimitKey(Arbitrum.USDT_OFT, peer, LZ_EID_ETHEREUM, Arbitrum.USDT0)
        }));
    }

    /**********************************************************************************************/
    /*** Item 3: X Layer                                                                        ***/
    /**********************************************************************************************/

    function test_XLAYER_sll_layerZeroRecipient() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));

        _executeAllPayloadsAndBridges();

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(uint256(uint160(SPUSDT_PAU_ALM_PROXY))));
    }

    function test_XLAYER_spUsdt_roles() external onChain(ChainIdUtils.XLayer()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDT);

        bytes32 takerRole  = spUsdt.TAKER_ROLE();
        bytes32 setterRole = spUsdt.SETTER_ROLE();

        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   XLayer.ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   XLayer.ALM_PROXY_FREEZABLE);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   XLayer.SPARK_EXECUTOR);

        _executeAllPayloadsAndBridges();

        // TAKER is unchanged.
        assertEq(spUsdt.getRoleMemberCount(takerRole), 1);
        assertEq(spUsdt.getRoleMember(takerRole, 0),   XLayer.ALM_PROXY);

        assertEq(spUsdt.getRoleMemberCount(setterRole), 1);
        assertEq(spUsdt.getRoleMember(setterRole, 0),   XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT);

        assertEq(spUsdt.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(spUsdt.getRoleMember(DEFAULT_ADMIN_ROLE, 0),   XLayer.SPARK_EXECUTOR);
    }

    function test_XLAYER_spUsdt_setVsr() external onChain(ChainIdUtils.XLayer()) {
        ISparkVaultLike spUsdt = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDT);

        _executeAllPayloadsAndBridges();

        uint256 maxVsr = spUsdt.maxVsr();

        ( address plannerAgent, address hotWallet ) = _agentActors(XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT);

        bytes memory data = abi.encodeCall(IAdministeredAgentLike.call, (
            XLayer.SPARK_VAULT_V2_SPUSDT,
            abi.encodeCall(ISparkVaultV2Like.setVsr, (maxVsr))
        ));

        vm.prank(hotWallet);
        IAdministeredAgentLike(plannerAgent).call(XLAYER_SPARK_VAULTS_ADMINISTERED_AGENT, data);

        assertEq(spUsdt.vsr(), maxVsr);
    }

    function test_XLAYER_sll_spUsdtRateLimitsUnchanged() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);

        bytes32 takeKey      = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), XLayer.SPARK_VAULT_V2_SPUSDT);
        bytes32 transferKey  = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), XLayer.USDT0, XLayer.SPARK_VAULT_V2_SPUSDT);
        bytes32 layerZeroKey = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), USDT0_OFT_XLAYER, LZ_EID_ETHEREUM));

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

    function test_XLAYER_sll_layerZeroTransferToEthereum() external onChain(ChainIdUtils.XLayer()) {
        ForeignController controller = ForeignController(XLayer.ALM_CONTROLLER);
        IERC20            usdt0      = IERC20(XLayer.USDT0);
        IERC20            usdt       = IERC20(Ethereum.USDT);

        _executeAllPayloadsAndBridges();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 destinationSnapshot = vm.snapshot();

        uint256 destinationBalanceBefore = usdt.balanceOf(SPUSDT_PAU_ALM_PROXY);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        deal(XLayer.USDT0,               XLayer.ALM_PROXY, 1_000_000e6);
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

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT_XLAYER).outboundNonce(USDT0_OFT_XLAYER, LZ_EID_ETHEREUM, bytes32(uint256(uint160(USDT_OFT)))) + 1;

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        controller.transferTokenLayerZero{ value: fee.nativeFee }(USDT0_OFT_XLAYER, 1_000_000e6, LZ_EID_ETHEREUM);

        assertEq(usdt0.balanceOf(XLayer.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        if (ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(USDT_OFT, LZ_EID_XLAYER, bytes32(uint256(uint160(USDT0_OFT_XLAYER)))) >= sentNonce) {
            console2.log("Skipping LZ destination delivery (destination fork ahead of source) for", USDT0_OFT_XLAYER);
        } else {
            _skipLZPendingNonces(USDT_OFT, LZ_EID_XLAYER, bytes32(uint256(uint160(USDT0_OFT_XLAYER))), sentNonce);

            assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY), destinationBalanceBefore);

            chainData[ChainIdUtils.XLayer()].domain.selectFork();

            LZBridgeTesting.relayMessagesToDestination(xlayerToEthereumLZBridge, true, USDT0_OFT_XLAYER, USDT_OFT);

            // The USDT0 lands in the Ethereum spUSDT PAU ALM Proxy, not in the Spark Liquidity Layer ALM Proxy.
            assertEq(usdt.balanceOf(SPUSDT_PAU_ALM_PROXY), destinationBalanceBefore + 1_000_000e6);
        }

        vm.revertTo(destinationSnapshot);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
    }

    /**********************************************************************************************/
    /*** Item 6: Base                                                                           ***/
    /**********************************************************************************************/

    function test_BASE_sll_pauCctpV2_rateLimit() external onChain(ChainIdUtils.Base()) {
        IControllerLike controller = IControllerLike(Base.PAU_CONTROLLER);

        bytes32 domainKey    = controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        bytes32 aggregateKey = controller.cctp_toCCTPRateLimitKey();

        assertEq(domainKey, 0x90b598dae614822d554ec4f627bb5feab505106473a7911f34b36c0b3b9695c7);

        _assertRateLimit(Base.PAU_RATELIMITS, domainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, aggregateKey);

        ( bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate ) = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Base.PAU_RATELIMITS, domainKey, 25_000_000e6, uint256(100_000_000e6) / 1 days);

        assertEq(uint256(100_000_000e6) / 1 days, 1_157_407_407);

        // Unchanged.
        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, aggregateKey);

        ( recipient, minFeeCapRate, maxFeeCapRate ) = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(recipient,     bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
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
            abi.encodeCall(IControllerLike.cctp_transfer, (25_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        // The full maximum reaches the Ethereum Spark Liquidity Layer ALM Proxy.
        _bridgeUSDCToMainnet_pau(25_000_000e6, ChainIdUtils.Base(), Base.PAU_CONTROLLER);
    }

    /**********************************************************************************************/
    /*** Generic E2E overrides                                                                  ***/
    /**********************************************************************************************/

    // Same flow as the harness test. The recorded-log store is cleared between domain legs: by the last
    // post-execution leg it otherwise holds ~2,300 logs and its re-encoding exceeds the EVM memory limit.
    function test_E2E_sparkLiquidityLayerCCTPCrossChainSetup() external override {
        _runCrossChainCctpLegsForAllDomains({ isPostExecution: false });

        _executeAllPayloadsAndBridges();

        _runCrossChainCctpLegsForAllDomains({ isPostExecution: true });
    }

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

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    // The agents' actor chain (Pre-deployed contracts 4): hot wallet -> Spark Planner Administered Agent -> agent.
    function _agentActors(address agent) internal view returns (address plannerAgent, address hotWallet) {
        plannerAgent = IAdministeredAgentLike(agent).getActor(0);
        hotWallet    = IAdministeredAgentLike(plannerAgent).getActor(0);
    }

    function _callAsAgent(address agent, address target, bytes memory data) internal returns (bytes memory) {
        return _callAsAgent(agent, target, data, 0);
    }

    function _callAsAgent(address agent, address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        ( address plannerAgent, address hotWallet ) = _agentActors(agent);

        vm.deal(hotWallet, hotWallet.balance + value);

        vm.prank(hotWallet);
        return IAdministeredAgentLike(plannerAgent).call{ value: value }(agent, abi.encodeCall(IAdministeredAgentLike.call, (target, data)));
    }

    function _assertDispatch(IControllerLike controller, bytes4 callSelector, address facet, bytes4 delegateSelector) internal view {
        IControllerLike.Dispatch memory dispatch = controller.getDispatch(callSelector);

        assertEq(dispatch.facet,                     facet);
        assertEq(bytes32(dispatch.delegateSelector), bytes32(delegateSelector));
    }

    function _assertWire(IBeaconLike.Wire memory wire, bytes4 callSelector, bytes4 delegateSelector) internal pure {
        assertEq(bytes32(wire.callSelector),     bytes32(callSelector));
        assertEq(bytes32(wire.delegateSelector), bytes32(delegateSelector));
    }

    // Mirrors `_runLayerZeroTransferE2E` for a Diamond PAU: the transfer is made through the Administered Agent.
    function _runSpUsdtPauLayerZeroTransfer(PauLayerZeroTransferParams memory p) internal {
        chainData[p.sourceChainId].domain.selectFork();

        IRateLimits rateLimits = IRateLimits(IControllerLike(p.controller).rateLimits());

        address proxy = IControllerLike(p.controller).proxy();

        uint256 transferLimit = rateLimits.getCurrentRateLimit(p.transferKey);

        _drainLZPendingPackets(p.destinationChainId);

        chainData[p.destinationChainId].domain.selectFork();

        uint256 destinationSnapshot = vm.snapshot();

        uint256 destinationBalanceBefore = IERC20(p.destinationAsset).balanceOf(p.destinationReceiver);

        chainData[p.sourceChainId].domain.selectFork();

        deal(p.asset, proxy, p.amount);

        ( , MessagingFee memory fee ) = IControllerLike(p.controller).layerZero_quoteTransfer(p.oft, p.amount, p.destinationEndpointId);

        uint64 sentNonce = ILZEndpointLike(LZ_ENDPOINT).outboundNonce(p.oft, p.destinationEndpointId, bytes32(uint256(uint160(p.destinationOft)))) + 1;

        _callAsAgent(
            p.agent,
            p.controller,
            abi.encodeCall(IControllerLike.layerZero_transfer, (p.oft, p.amount, p.destinationEndpointId)),
            fee.nativeFee
        );

        assertEq(IERC20(p.asset).balanceOf(proxy), 0);

        assertEq(
            rateLimits.getCurrentRateLimit(p.transferKey),
            transferLimit == type(uint256).max ? type(uint256).max : transferLimit - p.amount
        );

        chainData[p.destinationChainId].domain.selectFork();

        if (ILZEndpointLike(LZ_ENDPOINT).lazyInboundNonce(p.destinationOft, p.sourceEndpointId, bytes32(uint256(uint160(p.oft)))) >= sentNonce) {
            console2.log("Skipping LZ destination delivery (destination fork ahead of source) for", p.oft);
        } else {
            _skipLZPendingNonces(p.destinationOft, p.sourceEndpointId, bytes32(uint256(uint160(p.oft))), sentNonce);

            assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore);

            chainData[p.sourceChainId].domain.selectFork();

            LZBridgeTesting.relayMessagesToDestination(_getLZBridge(p.destinationChainId), true, p.oft, p.destinationOft);

            assertEq(IERC20(p.destinationAsset).balanceOf(p.destinationReceiver), destinationBalanceBefore + p.amount);
        }

        vm.revertTo(destinationSnapshot);

        chainData[p.sourceChainId].domain.selectFork();
    }

}

contract SparkEthereum_20261203_SparklendTests is SparklendTests, SpUsdtPauStandIns {

    using DomainHelpers for Domain;

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        _deployEthereumStandIns();
        _registerSwapAssetFacetOnSkyBeacon();

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        _deployArbitrumStandIns();

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        _deployXLayerStandIns();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

}

contract SparkEthereum_20261203_SpellTests is SpellTests, SpUsdtPauStandIns {

    using DomainHelpers for Domain;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    constructor() {
        _spellId   = 20261203;
        _blockDate = 1795069223;  // Nov-19-2026 06:20:23 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        _deployEthereumStandIns();
        _registerSwapAssetFacetOnSkyBeacon();

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        _deployArbitrumStandIns();

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        _deployXLayerStandIns();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    /**********************************************************************************************/
    /*** Item 5: Transfer USDS for buybacks                                                     ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkTreasury_buyback() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore  = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 opsMultisigBalanceBefore = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,  48_995_094.205806286854722044e18);
        assertEq(opsMultisigBalanceBefore, 552_142.342558330054342171e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);

        assertEq(USDS_SPK_BUYBACK_AMOUNT, 2_681_519e18);
    }

}
