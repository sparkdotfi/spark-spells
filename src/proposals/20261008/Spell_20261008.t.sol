// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC4626 }   from 'forge-std/interfaces/IERC4626.sol';
import { Vm, VmSafe } from "forge-std/Vm.sol";

import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { Bridge, BridgeType }    from "lib/xchain-helpers/src/testing/Bridge.sol";
import { CCTPV2BridgeTesting }   from "lib/xchain-helpers/src/testing/bridges/CCTPV2BridgeTesting.sol";
import { CCTPForwarder }         from "lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { DomainHelpers }         from "lib/xchain-helpers/src/testing/Domain.sol";
import { RecordedLogs }          from "lib/xchain-helpers/src/testing/utils/RecordedLogs.sol";
import { ArbitrumBridgeTesting } from "lib/xchain-helpers/src/testing/bridges/ArbitrumBridgeTesting.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

interface IAccessControlsLike {

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

interface IAdministeredAgentLike {

    function call(address target, bytes memory data) external;

    function adminCount() external view returns (uint256);

    function getActor(uint256 index) external view returns (address);

    function getAdmin(uint256 index) external view returns (address);

    function actorCount() external view returns (uint256);

    function grantorCount() external view returns (uint256);

    function getGrantor(uint256 index) external view returns (address);

    function revokerCount() external view returns (uint256);

    function getRevoker(uint256 index) external view returns (address);

}

interface IALMProxyLike {

    function CONTROLLER() external returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IBeaconLike {

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function getDispatch(bytes4 callSelector) external view returns (IControllerLike.Dispatch memory);

}

interface IBeamStateLike {

    event AddCBeam(address indexed cBeam);

    event AddController(address indexed controller);

    event AddInitControllerActions(bytes32 indexed key, address indexed controller);

    event AddInitRateLimits(bytes32 indexed key, address indexed rateLimits, uint256 maxAmount, uint256 slope);

    event AddRateLimits(address indexed rateLimits);

    event DelCBeam(address indexed cBeam);

    event DelController(address indexed controller);

    event DelInitControllerActions(bytes32 indexed key, address indexed controller);

    event DelInitRateLimits(bytes32 indexed key, address indexed rateLimits);

    event DelRateLimits(address indexed rateLimits);

    event Deny(address indexed usr);

    event Rely(address indexed usr);

    event SetCBeamForController(address indexed controller, address indexed cBeam);

    event SetCBeamForRateLimits(address indexed rateLimits, address indexed cBeam);

    event SetHop(address indexed rateLimits, uint256 value);

    event SetMaxChange(address indexed rateLimits, uint256 value);

    event SetRoleAction(uint8 indexed role, bytes4 indexed sig, bool enabled);

    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);

    event UnsetCBeamForController(address indexed controller, address indexed cBeam);

    event UnsetCBeamForRateLimits(address indexed rateLimits, address indexed cBeam);

    function actionsRoles(bytes4 sig) external view returns (bytes32);

    function addCBeam(address cBeam) external;

    function addController(address controller) external;

    function addInitControllerActions(bytes calldata data, address controller) external returns (bytes32 key);

    function addInitRateLimits(bytes32 key, address rateLimits, uint256 maxAmount, uint256 slope) external;

    function addRateLimits(address rateLimits) external;

    function cBeams(address cBeam) external view returns (uint256);

    function controllers(address controller) external view returns (uint256);

    function controllersCBeams(address controller, address cBeam) external view returns (uint256);

    function delCBeam(address cBeam) external;

    function delController(address controller) external;

    function delInitControllerActions(bytes32 key, address controller) external;

    function delInitRateLimits(bytes32 key, address rateLimits) external;

    function delRateLimits(address rateLimits) external;

    function getHop(address rateLimits) external view returns (uint256);

    function getInitRateLimits(bytes32 key, address rateLimits)
        external
        view
        returns (uint256 maxAmount, uint256 slope);

    function getMaxChange(address rateLimits) external view returns (uint256);

    function hasUserRole(address usr, uint8 role) external view returns (bool);

    function isControllerActionEnabled(bytes32 key, address controller) external view returns (bool);

    function rateLimits(address rateLimits) external view returns (uint256);

    function rateLimitsCBeams(address rateLimits, address cBeam) external view returns (uint256);

    function setCBeamForController(address controller, address cBeam) external;

    function setCBeamForRateLimits(address rateLimits, address cBeam) external;

    function setHop(address rateLimits, uint256 value) external;

    function setMaxChange(address rateLimits, uint256 value) external;

    function start() external;

    function stop() external;

    function stopped() external view returns (bool);

    function unsetCBeamForController(address controller, address cBeam) external;

    function unsetCBeamForRateLimits(address rateLimits, address cBeam) external;

    function wards(address usr) external view returns (uint256);

}

interface IConfiguratorLike {

    event CallControllerAction(address indexed controller, bytes data);

    event SetRateLimit(address indexed rateLimits, bytes32 indexed key, uint256 maxAmount, uint256 slope);

    function beamState() external view returns (address);

    function callControllerAction(address controller, bytes calldata data) external returns (bytes memory);

    function setRateLimit(address rateLimits, bytes32 key, uint256 maxAmount, uint256 slope) external;

    function zzz(address rateLimits, bytes32 key) external view returns (uint256);

}

interface IControllerLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    struct Config {
        address facet;
        Wire[]  wires;
    }

    struct Dispatch {
        address facet;
        bytes4  delegateSelector;
    }

    struct Integration {
        bytes32 id;
        Config  config;
    }

    event IntegrationRemoved(bytes32 indexed id);

    function accessControls() external view returns (address);

    function beacon() external view returns (address);

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 recipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_toCCTPRateLimitKey() external pure returns (bytes32 key);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

    function getConfig(bytes32 integrationId) external view returns (Config memory);

    function getDispatch(bytes4 callSelector) external view returns (Dispatch memory);

    function integrations() external view returns (Integration[] memory);

    function rateLimits() external view returns (address);

    function removeIntegrations(bytes32[] calldata ids) external;

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IERC4626Like {

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

}

interface IForeignControllerFullLike {

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate) external;

    function cctp_toCCTPRateLimitKey() external view returns (bytes32);

    function cctp_getToDomainRateLimitKey(uint32 domainId) external view returns (bytes32);

    function sparkVault_getTakeRateLimitKey(address sparkVault) external view returns (bytes32);

    function sparkVault_take(address sparkVault, uint256 assetAmount) external;

    function transferAsset_getTransferRateLimitKey(address asset, address destination) external view returns (bytes32);

    function transferAsset_transfer(address asset, address destination, uint256 amount) external;

}

interface IRateLimitsLike {

    function getCurrentRateLimit(bytes32 key) external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface ISavingsIntentsLike {

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function fulfill(address account, address vault, uint256 requestId) external;

    function request(
        address vault,
        uint256 shares,
        address recipient,
        uint256 deadline
    ) external returns (uint256 requestId);

    function RELAYER() external view returns (bytes32 relayer);

    function vaultConfig(address vault)
        external
        view
        returns (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        );

    function vaultRequestCount(address vault) external view returns (uint256 requestCount);

    function withdrawRequests(address account, address vault)
        external
        view
        returns (
            uint256 requestId,
            uint256 shares,
            address recipient,
            uint256 deadline
        );

}

interface ISparkVaultV2Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function setVsr(uint256 vsr) external;

}

interface ITimelockLike {

    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    event Paused(address account);

    event Unpaused(address account);

    function CANCELLER_ROLE() external view returns (bytes32);

    function EXECUTOR_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function PROPOSER_ROLE() external view returns (bytes32);

    function getMinDelay() external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function paused() external view returns (bool);

}

interface ITokenBridgeLike {

    function escrow() external returns (address);

}

interface IMainnetControllerFullLike {

    function erc4626_deposit(address token, uint256 amount, uint256 minSharesOut) external;

    function erc4626_redeem(address token, uint256 shares, uint256 minAssetsOut) external;

    function erc4626_getDepositRateLimitKey(address token, address asset) external view returns (bytes32);

    function erc4626_getWithdrawRateLimitKey(address token) external view returns (bytes32);

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate) external;

    function cctp_toCCTPRateLimitKey() external view returns (bytes32);

    function cctp_getToDomainRateLimitKey(uint32 domainId) external view returns (bytes32);

}

contract SparkEthereum_20261008_SLLTests is SparkLiquidityLayerTests {

    using DomainHelpers       for *;
    using CCTPV2BridgeTesting for Bridge;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // SUSDS transfer amount
    uint256 internal constant SUSDS_TRANSFER_AMOUNT = 100_000_000e18;

    // PAS

    address internal constant PAS_BEAM_STATE   = 0x11CFefeA67B18de9046a6250555D438854fFEEDa;
    address internal constant PAS_CBEAM        = 0x492aae70E59551768BAF3c7159d3f951B6ed76Fe;
    address internal constant PAS_CONFIGURATOR = 0xd11Dc57F3eF23bb7b3142588a461F68460a7C474;
    address internal constant PAS_CORE_COUNCIL = 0x148eF923d764CBdc1597CcADBbbC66499C1A1432;
    address internal constant PAS_DEPLOYER     = 0x6547c342ED83b6dEEf9Ac7525fc1196F7Bfa5A4D;
    address internal constant PAS_TIMELOCK     = 0x66d3653e66F7edb973549CFA3b46F22298B8f983;

    uint8 internal constant PAS_ROLE_DELAYED   = 1;  // BeamState actions routed through the Timelock
    uint8 internal constant PAS_ROLE_IMMEDIATE = 2;  // BeamState actions the Core Council can call directly

    uint256 internal constant PAS_HOP        = 16 hours;
    uint256 internal constant PAS_MAX_CHANGE = 1.2e18;
    uint256 internal constant PAS_MIN_DELAY  = 14 days;

    bytes32 internal constant CCTP_FACET_ID = "CCTP_FACET";

    // Arbitrum PAU Administered Agent addresses

    address internal constant SPARK_HOT_WALLET       = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address
    address internal constant SOTER_GRANTOR_MULTISIG = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address
    address internal constant SOTER_FREEZER_MULTISIG = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address

    // XLayer CCTP round trip test setup

    uint32 internal constant CCTP_V2_DOMAIN_ID_ETHEREUM = CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 internal constant CCTP_V2_DOMAIN_ID_XLAYER   = 37;

    IAdministeredAgentLike     internal xlayerAgent;
    IForeignControllerFullLike internal xlayerController;
    IRateLimitsLike            internal xlayerRateLimits;
    ISparkVaultV2Like          internal spusdc;
    IERC20                     internal xlayerUsdc;

    IAdministeredAgentLike     internal mainnetAgent;
    IMainnetControllerFullLike internal mainnetController;
    IRateLimitsLike            internal mainnetRateLimits;
    IERC4626Like               internal susdc;
    IERC20                     internal usdc;

    address internal user;

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1790753409;  // Sep-30-2026 07:30:09 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        // XLayer CCTP round trip test setup
        xlayerAgent      = IAdministeredAgentLike(XLayer.SPUSDC_PAU_ADMINISTERED_AGENT);
        xlayerController = IForeignControllerFullLike(XLayer.SPUSDC_PAU_CONTROLLER);
        xlayerRateLimits = IRateLimitsLike(XLayer.SPUSDC_PAU_RATELIMITS);
        spusdc           = ISparkVaultV2Like(XLayer.SPARK_VAULT_V2_SPUSDC);
        xlayerUsdc       = IERC20(XLayer.USDC);

        mainnetAgent      = IAdministeredAgentLike(Ethereum.SPUSDC_PAU_ADMINISTERED_AGENT);
        mainnetController = IMainnetControllerFullLike(Ethereum.SPUSDC_PAU_CONTROLLER);
        mainnetRateLimits = IRateLimitsLike(Ethereum.SPUSDC_PAU_RATELIMITS);
        susdc             = IERC4626Like(Ethereum.SUSDC);
        usdc              = IERC20(Ethereum.USDC);

        user = makeAddr("user");

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

    // Arbitrum tests

    function test_ARBITRUM_sll_removeExcessLiquidity() external onChain(ChainIdUtils.ArbitrumOne()) {
        uint256 arbUsdsBalanceBefore = IERC20(Arbitrum.USDS).balanceOf(Arbitrum.ALM_PROXY);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 ethUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        RecordedLogs.init();

        assertEq(arbUsdsBalanceBefore, 99_326_272.779060900054294080e18);
        assertEq(ethUsdsBalanceBefore, 2.028165914747884461e18);

        assertEq(IERC20(Arbitrum.USDS).allowance(Arbitrum.ALM_PROXY, Arbitrum.TOKEN_BRIDGE), 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Arbitrum.USDS).allowance(Arbitrum.ALM_PROXY, Arbitrum.TOKEN_BRIDGE), 0);

        // Arbitrum ALM proxy sent the tokens to the bridge (burned on L2)
        assertEq(IERC20(Arbitrum.USDS).balanceOf(Arbitrum.ALM_PROXY), 0);

        // Relay L2->L1
        ArbitrumBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.ArbitrumOne()].bridges[0], false);

        // Ethereum ALM proxy received the withdrawn tokens
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY), ethUsdsBalanceBefore + arbUsdsBalanceBefore);
    }

    function test_ARBITRUM_sll_parallelPAU_roles() external onChain(ChainIdUtils.ArbitrumOne()) {
        bytes32 controllerRole = IALMProxyLike(Arbitrum.ALM_PROXY).CONTROLLER();

        IAdministeredAgentLike administeredAgent = IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT);
        IAccessControlsLike    accessControls    = IAccessControlsLike(Arbitrum.PAU_ACCESS_CONTROLS);
        IRateLimitsLike        rateLimits        = IRateLimitsLike(Arbitrum.PAU_RATELIMITS);
        IBeaconLike            beacon            = IBeaconLike(Arbitrum.SPARK_BEACON);

        // ALMProxy roles

        assertEq(IALMProxyLike(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.ALM_CONTROLLER), true);
        assertEq(IALMProxyLike(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.PAU_CONTROLLER), false);

        // PAU Administered Agent roles

        assertEq(administeredAgent.adminCount(), 1);
        assertEq(administeredAgent.getAdmin(0),  Arbitrum.SPARK_EXECUTOR);

        assertEq(administeredAgent.actorCount(), 1);
        assertEq(administeredAgent.getActor(0),  Arbitrum.ALM_RELAYER_MULTISIG);

        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.getGrantor(0),  Arbitrum.PAU_GRANTOR_MULTISIG);

        assertEq(administeredAgent.revokerCount(), 1);
        assertEq(administeredAgent.getRevoker(0),  Arbitrum.ALM_FREEZER_MULTISIG);

        // PAS Configurator roles

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),               1);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),        false);

        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),        false);

        // Beacon

        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE),               1);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), true);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SKY_GOV_RELAY),  false);

        _executeAllPayloadsAndBridges();

        // ALMProxy roles

        assertEq(IALMProxyLike(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.ALM_CONTROLLER), true);
        assertEq(IALMProxyLike(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.PAU_CONTROLLER), true);

        // PAU Administered Agent roles

        assertEq(administeredAgent.adminCount(), 1);
        assertEq(administeredAgent.getAdmin(0),  Arbitrum.SPARK_EXECUTOR);

        assertEq(administeredAgent.actorCount(), 2);
        assertEq(administeredAgent.getActor(0),  Arbitrum.ALM_RELAYER_MULTISIG);
        assertEq(administeredAgent.getActor(1),  SPARK_HOT_WALLET);

        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.getGrantor(0),  SOTER_GRANTOR_MULTISIG);

        assertEq(administeredAgent.revokerCount(), 2);
        assertEq(administeredAgent.getRevoker(0),  Arbitrum.ALM_FREEZER_MULTISIG);
        assertEq(administeredAgent.getRevoker(1),  SOTER_FREEZER_MULTISIG);

        // PAS Configurator roles

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),               2);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),        true);

        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),        true);

        // Beacon

        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE),               1);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR), false);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SKY_GOV_RELAY),  true);
    }

    function test_ARBITRUM_sll_parallelPAU_roles_events() external onChain(ChainIdUtils.ArbitrumOne()) {
        bytes32 controllerRole = IALMProxyLike(Arbitrum.ALM_PROXY).CONTROLLER();

        vm.recordLogs();

        _executeAllPayloadsAndBridges();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log[] memory almProxyLogs   = new Vm.Log[](logs.length);
        Vm.Log[] memory rateLimitsLogs = new Vm.Log[](logs.length);

        // Get only the RoleGranted and RoleRevoked events from ALMProxy and PAU RateLimits
        uint256 almProxyCount;
        uint256 rateLimitsCount;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            if (
                logs[i].topics[0] != IAccessControl.RoleGranted.selector &&
                logs[i].topics[0] != IAccessControl.RoleRevoked.selector
            ) continue;

            if      (logs[i].emitter == Arbitrum.ALM_PROXY)      almProxyLogs[almProxyCount++]     = logs[i];
            else if (logs[i].emitter == Arbitrum.PAU_RATELIMITS) rateLimitsLogs[rateLimitsCount++] = logs[i];
        }

        assertEq(almProxyCount,   3);
        assertEq(rateLimitsCount, 1);

        assertEq(almProxyLogs[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(almProxyLogs[0].topics[1],                            controllerRole);
        assertEq(address(uint160(uint256(almProxyLogs[0].topics[2]))), Arbitrum.PAU_CONTROLLER);
        assertEq(address(uint160(uint256(almProxyLogs[0].topics[3]))), Arbitrum.SPARK_EXECUTOR);

        assertEq(almProxyLogs[1].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(almProxyLogs[1].topics[1],                            controllerRole);
        assertEq(address(uint160(uint256(almProxyLogs[1].topics[2]))), Arbitrum.SPARK_EXECUTOR);
        assertEq(address(uint160(uint256(almProxyLogs[1].topics[3]))), Arbitrum.SPARK_EXECUTOR);

        assertEq(almProxyLogs[2].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(almProxyLogs[2].topics[1],                            controllerRole);
        assertEq(address(uint160(uint256(almProxyLogs[2].topics[2]))), Arbitrum.SPARK_EXECUTOR);
        assertEq(address(uint160(uint256(almProxyLogs[2].topics[3]))), Arbitrum.SPARK_EXECUTOR);

        assertEq(rateLimitsLogs[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(rateLimitsLogs[0].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(rateLimitsLogs[0].topics[2]))), PAS_CONFIGURATOR);
        assertEq(address(uint160(uint256(rateLimitsLogs[0].topics[3]))), Arbitrum.SPARK_EXECUTOR);

        assertEq(IAccessControl(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.PAU_CONTROLLER), true);
        assertEq(IAccessControl(Arbitrum.ALM_PROXY).hasRole(controllerRole, Arbitrum.SPARK_EXECUTOR), false);
    }

    function test_ARBITRUM_sll_pauCctpV2_onboarding() external onChain(ChainIdUtils.ArbitrumOne()) {
        IControllerLike controller = IControllerLike(Arbitrum.PAU_CONTROLLER);

        _assertRateLimit(Arbitrum.PAU_RATELIMITS, controller.cctp_toCCTPRateLimitKey(),                                0, 0);
        _assertRateLimit(Arbitrum.PAU_RATELIMITS, controller.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM), 0, 0);

        ( bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate )
            = controller.cctp_getDomainParameters(CCTP_V2_DOMAIN_ID_ETHEREUM);

        assertEq(mintRecipient, bytes32(0));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(Arbitrum.PAU_RATELIMITS, controller.cctp_toCCTPRateLimitKey());

        _assertRateLimit(
            Arbitrum.PAU_RATELIMITS,
            controller.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );

        ( mintRecipient, minFeeCapRate, maxFeeCapRate )
            = controller.cctp_getDomainParameters(CCTP_V2_DOMAIN_ID_ETHEREUM);

        assertEq(mintRecipient, bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);
    }

    function test_ARBITRUM_pasConfigurator_state() external onChain(ChainIdUtils.ArbitrumOne()) {
        assertEq(IConfiguratorLike(PAS_CONFIGURATOR).beamState(), PAS_BEAM_STATE);
    }

    function test_ARBITRUM_beamState_stopped() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.stopped(), false);
    }

    function test_ARBITRUM_beamState_wards() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // BeamState admin: Sky governance only

        assertEq(beamState.wards(Arbitrum.SKY_GOV_RELAY), 1);
        assertEq(beamState.wards(PAS_DEPLOYER),           0);

        VmSafe.EthGetLogs[] memory relyLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Rely.selector);
        VmSafe.EthGetLogs[] memory denyLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Deny.selector);

        assertEq(relyLogs.length, 2);
        assertEq(denyLogs.length, 1);

        assertEq(relyLogs[0].topics[0],                            IBeamStateLike.Rely.selector);
        assertEq(address(uint160(uint256(relyLogs[0].topics[1]))), PAS_DEPLOYER);

        assertEq(relyLogs[1].topics[0],                            IBeamStateLike.Rely.selector);
        assertEq(address(uint160(uint256(relyLogs[1].topics[1]))), Arbitrum.SKY_GOV_RELAY);

        assertEq(denyLogs[0].topics[0],                            IBeamStateLike.Deny.selector);
        assertEq(address(uint160(uint256(denyLogs[0].topics[1]))), PAS_DEPLOYER);
    }

    function test_ARBITRUM_beamState_userRoles() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // BeamState user roles: Timelock has delayed role, Core Council has immediate role.

        assertEq(beamState.hasUserRole(PAS_TIMELOCK,     PAS_ROLE_DELAYED),   true);
        assertEq(beamState.hasUserRole(PAS_CORE_COUNCIL, PAS_ROLE_DELAYED),   false);

        assertEq(beamState.hasUserRole(PAS_TIMELOCK,     PAS_ROLE_IMMEDIATE), false);
        assertEq(beamState.hasUserRole(PAS_CORE_COUNCIL, PAS_ROLE_IMMEDIATE), true);

        VmSafe.EthGetLogs[] memory userRoleLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetUserRole.selector);

        assertEq(userRoleLogs.length, 2);

        assertEq(userRoleLogs[0].topics[0],                            IBeamStateLike.SetUserRole.selector);
        assertEq(address(uint160(uint256(userRoleLogs[0].topics[1]))), PAS_TIMELOCK);
        assertEq(uint8(uint256(userRoleLogs[0].topics[2])),            PAS_ROLE_DELAYED);
        assertEq(abi.decode(userRoleLogs[0].data, (bool)),             true);

        assertEq(userRoleLogs[1].topics[0],                            IBeamStateLike.SetUserRole.selector);
        assertEq(address(uint160(uint256(userRoleLogs[1].topics[1]))), PAS_CORE_COUNCIL);
        assertEq(uint8(uint256(userRoleLogs[1].topics[2])),            PAS_ROLE_IMMEDIATE);
        assertEq(abi.decode(userRoleLogs[1].data, (bool)),             true);
    }

    function test_ARBITRUM_beamState_actionRoles() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // BeamState action roles

        bytes4[18] memory actionSigs = [  // First 8 are for DELAYED role, next 10 are for IMMEDIATE role.
            IBeamStateLike.start.selector,
            IBeamStateLike.setHop.selector,
            IBeamStateLike.setMaxChange.selector,
            IBeamStateLike.addRateLimits.selector,
            IBeamStateLike.addController.selector,
            IBeamStateLike.addCBeam.selector,
            IBeamStateLike.addInitRateLimits.selector,
            IBeamStateLike.addInitControllerActions.selector,
            IBeamStateLike.stop.selector,
            IBeamStateLike.delRateLimits.selector,
            IBeamStateLike.delController.selector,
            IBeamStateLike.delCBeam.selector,
            IBeamStateLike.setCBeamForRateLimits.selector,
            IBeamStateLike.unsetCBeamForRateLimits.selector,
            IBeamStateLike.setCBeamForController.selector,
            IBeamStateLike.unsetCBeamForController.selector,
            IBeamStateLike.delInitRateLimits.selector,
            IBeamStateLike.delInitControllerActions.selector
        ];

        VmSafe.EthGetLogs[] memory roleActionLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetRoleAction.selector);

        assertEq(roleActionLogs.length, 18);

        // First 8 actions are for DELAYED role
        for (uint256 i = 0; i < 8; i++) {
            assertEq(beamState.actionsRoles(actionSigs[i]), bytes32(uint256(1) << PAS_ROLE_DELAYED));

            assertEq(roleActionLogs[i].topics[0],                 IBeamStateLike.SetRoleAction.selector);
            assertEq(uint8(uint256(roleActionLogs[i].topics[1])), PAS_ROLE_DELAYED);
            assertEq(roleActionLogs[i].topics[2],                 bytes32(actionSigs[i]));
            assertEq(abi.decode(roleActionLogs[i].data, (bool)),  true);
        }

        // Next 10 actions are for IMMEDIATE role
        for (uint256 i = 8; i < 18; i++) {
            assertEq(beamState.actionsRoles(actionSigs[i]), bytes32(uint256(1) << PAS_ROLE_IMMEDIATE));

            assertEq(roleActionLogs[i].topics[0],                 IBeamStateLike.SetRoleAction.selector);
            assertEq(uint8(uint256(roleActionLogs[i].topics[1])), PAS_ROLE_IMMEDIATE);
            assertEq(roleActionLogs[i].topics[2],                 bytes32(actionSigs[i]));
            assertEq(abi.decode(roleActionLogs[i].data, (bool)),  true);
        }
    }

    function test_ARBITRUM_beamState_rateLimits() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.rateLimits(Arbitrum.PAU_RATELIMITS), 1);

        VmSafe.EthGetLogs[] memory addRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddRateLimits.selector);
        VmSafe.EthGetLogs[] memory delRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelRateLimits.selector);

        assertEq(addRateLimitsLogs.length, 1);
        assertEq(delRateLimitsLogs.length, 0);

        assertEq(addRateLimitsLogs[0].topics[0],                            IBeamStateLike.AddRateLimits.selector);
        assertEq(address(uint160(uint256(addRateLimitsLogs[0].topics[1]))), Arbitrum.PAU_RATELIMITS);
    }

    function test_ARBITRUM_beamState_controllers() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.controllers(Arbitrum.PAU_CONTROLLER), 1);

        VmSafe.EthGetLogs[] memory addControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddController.selector);
        VmSafe.EthGetLogs[] memory delControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelController.selector);

        assertEq(addControllerLogs.length, 1);
        assertEq(delControllerLogs.length, 0);

        assertEq(addControllerLogs[0].topics[0],                            IBeamStateLike.AddController.selector);
        assertEq(address(uint160(uint256(addControllerLogs[0].topics[1]))), Arbitrum.PAU_CONTROLLER);
    }

    function test_ARBITRUM_beamState_cBeams() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

         assertEq(beamState.cBeams(PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory addCBeamLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddCBeam.selector);
        VmSafe.EthGetLogs[] memory delCBeamLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelCBeam.selector);

        assertEq(addCBeamLogs.length, 1);
        assertEq(delCBeamLogs.length, 0);

        assertEq(addCBeamLogs[0].topics[0],                            IBeamStateLike.AddCBeam.selector);
        assertEq(address(uint160(uint256(addCBeamLogs[0].topics[1]))), PAS_CBEAM);
    }

    function test_ARBITRUM_beamState_rateLimitsCBeams() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.rateLimitsCBeams(Arbitrum.PAU_RATELIMITS, PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory setCBeamForRateLimitsLogs   = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetCBeamForRateLimits.selector);
        VmSafe.EthGetLogs[] memory unsetCBeamForRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.UnsetCBeamForRateLimits.selector);

        assertEq(setCBeamForRateLimitsLogs.length,   1);
        assertEq(unsetCBeamForRateLimitsLogs.length, 0);

        assertEq(setCBeamForRateLimitsLogs[0].topics[0],                            IBeamStateLike.SetCBeamForRateLimits.selector);
        assertEq(address(uint160(uint256(setCBeamForRateLimitsLogs[0].topics[1]))), Arbitrum.PAU_RATELIMITS);
        assertEq(address(uint160(uint256(setCBeamForRateLimitsLogs[0].topics[2]))), PAS_CBEAM);
    }

    function test_ARBITRUM_beamState_controllersCBeams() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.controllersCBeams(Arbitrum.PAU_CONTROLLER, PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory setCBeamForControllerLogs   = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetCBeamForController.selector);
        VmSafe.EthGetLogs[] memory unsetCBeamForControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.UnsetCBeamForController.selector);

        assertEq(setCBeamForControllerLogs.length,   1);
        assertEq(unsetCBeamForControllerLogs.length, 0);

        assertEq(setCBeamForControllerLogs[0].topics[0],                            IBeamStateLike.SetCBeamForController.selector);
        assertEq(address(uint160(uint256(setCBeamForControllerLogs[0].topics[1]))), Arbitrum.PAU_CONTROLLER);
        assertEq(address(uint160(uint256(setCBeamForControllerLogs[0].topics[2]))), PAS_CBEAM);
    }

    function test_ARBITRUM_beamState_initRateLimits() external onChain(ChainIdUtils.ArbitrumOne()) {
        VmSafe.EthGetLogs[] memory addInitRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddInitRateLimits.selector);
        VmSafe.EthGetLogs[] memory delInitRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelInitRateLimits.selector);

        assertEq(addInitRateLimitsLogs.length, 0);
        assertEq(delInitRateLimitsLogs.length, 0);
    }

    function test_ARBITRUM_beamState_initControllerActions() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike  beamState  = IBeamStateLike(PAS_BEAM_STATE);
        IControllerLike controller = IControllerLike(Arbitrum.PAU_CONTROLLER);
        ITimelockLike   timelock   = ITimelockLike(PAS_TIMELOCK);

        // The only pre-approved controller action is removing the CCTP facet
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        assertEq(beamState.isControllerActionEnabled(keccak256(abi.encodeCall(controller.removeIntegrations, (ids))), Arbitrum.PAU_CONTROLLER), true);

        VmSafe.EthGetLogs[] memory addInitControllerActionsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddInitControllerActions.selector);
        VmSafe.EthGetLogs[] memory delInitControllerActionsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelInitControllerActions.selector);

        assertEq(addInitControllerActionsLogs.length, 1);
        assertEq(delInitControllerActionsLogs.length, 0);

        assertEq(addInitControllerActionsLogs[0].topics[0],                            IBeamStateLike.AddInitControllerActions.selector);
        assertEq(addInitControllerActionsLogs[0].topics[1],                            bytes32(keccak256(abi.encodeCall(controller.removeIntegrations, (ids)))));
        assertEq(address(uint160(uint256(addInitControllerActionsLogs[0].topics[2]))), Arbitrum.PAU_CONTROLLER);
    }

    function test_ARBITRUM_beamState_hop() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.getHop(Arbitrum.PAU_RATELIMITS), PAS_HOP);

        VmSafe.EthGetLogs[] memory setHopLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetHop.selector);

        assertEq(setHopLogs.length, 1);
        assertEq(setHopLogs[0].topics[0],                            IBeamStateLike.SetHop.selector);
        assertEq(address(uint160(uint256(setHopLogs[0].topics[1]))), address(0));  // Zero address for default
        assertEq(abi.decode(setHopLogs[0].data, (uint256)),          PAS_HOP);
    }

    function test_ARBITRUM_beamState_maxChange() external onChain(ChainIdUtils.ArbitrumOne()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.getMaxChange(Arbitrum.PAU_RATELIMITS), PAS_MAX_CHANGE);

        VmSafe.EthGetLogs[] memory setMaxChangeLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetMaxChange.selector);

        assertEq(setMaxChangeLogs.length, 1);
        assertEq(setMaxChangeLogs[0].topics[0],                            IBeamStateLike.SetMaxChange.selector);
        assertEq(address(uint160(uint256(setMaxChangeLogs[0].topics[1]))), address(0));  // Zero address for default
        assertEq(abi.decode(setMaxChangeLogs[0].data, (uint256)),          PAS_MAX_CHANGE);
    }

    function test_ARBITRUM_timelock_state() external onChain(ChainIdUtils.ArbitrumOne()) {
        ITimelockLike timelock = ITimelockLike(PAS_TIMELOCK);

        assertEq(timelock.getMinDelay(), PAS_MIN_DELAY);
        assertEq(timelock.paused(),      true);

        assertEq(timelock.hasRole(DEFAULT_ADMIN_ROLE, Arbitrum.SKY_GOV_RELAY), true);
        assertEq(timelock.hasRole(DEFAULT_ADMIN_ROLE, PAS_DEPLOYER),           false);

        assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(),  PAS_CORE_COUNCIL), true);
        assertEq(timelock.hasRole(timelock.CANCELLER_ROLE(), PAS_CORE_COUNCIL), true);
        assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(),  address(0)),       true);  // Anyone can execute
    }

    function test_ARBITRUM_timelock_events() external onChain(ChainIdUtils.ArbitrumOne()) {
        ITimelockLike timelock = ITimelockLike(PAS_TIMELOCK);

        bytes32 executorRole  = timelock.EXECUTOR_ROLE();
        bytes32 proposerRole  = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 pauserRole    = timelock.PAUSER_ROLE();

        assertEq(_getEvents(block.chainid, PAS_TIMELOCK, bytes32(0)).length, 12);  // 12 events in total

        // Role grants

        VmSafe.EthGetLogs[] memory roleGrantedLogs = _getEvents(block.chainid, PAS_TIMELOCK, IAccessControl.RoleGranted.selector);

        assertEq(roleGrantedLogs.length, 7);

        assertEq(roleGrantedLogs[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[0].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(roleGrantedLogs[0].topics[2]))), PAS_TIMELOCK);
        assertEq(address(uint160(uint256(roleGrantedLogs[0].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[1].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[1].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(roleGrantedLogs[1].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(roleGrantedLogs[1].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[2].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[2].topics[1],                            executorRole);
        assertEq(address(uint160(uint256(roleGrantedLogs[2].topics[2]))), address(0));  // Anyone can execute
        assertEq(address(uint160(uint256(roleGrantedLogs[2].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[3].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[3].topics[1],                            proposerRole);
        assertEq(address(uint160(uint256(roleGrantedLogs[3].topics[2]))), PAS_CORE_COUNCIL);
        assertEq(address(uint160(uint256(roleGrantedLogs[3].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[4].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[4].topics[1],                            cancellerRole);
        assertEq(address(uint160(uint256(roleGrantedLogs[4].topics[2]))), PAS_CORE_COUNCIL);
        assertEq(address(uint160(uint256(roleGrantedLogs[4].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[5].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[5].topics[1],                            pauserRole);
        assertEq(address(uint160(uint256(roleGrantedLogs[5].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(roleGrantedLogs[5].topics[3]))), PAS_DEPLOYER);

        assertEq(roleGrantedLogs[6].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(roleGrantedLogs[6].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(roleGrantedLogs[6].topics[2]))), Arbitrum.SKY_GOV_RELAY);
        assertEq(address(uint160(uint256(roleGrantedLogs[6].topics[3]))), PAS_DEPLOYER);

        // Role revocations

        VmSafe.EthGetLogs[] memory roleRevokedLogs = _getEvents(block.chainid, PAS_TIMELOCK, IAccessControl.RoleRevoked.selector);

        assertEq(roleRevokedLogs.length, 3);

        assertEq(roleRevokedLogs[0].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(roleRevokedLogs[0].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(roleRevokedLogs[0].topics[2]))), PAS_TIMELOCK);
        assertEq(address(uint160(uint256(roleRevokedLogs[0].topics[3]))), PAS_DEPLOYER);

        assertEq(roleRevokedLogs[1].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(roleRevokedLogs[1].topics[1],                            pauserRole);
        assertEq(address(uint160(uint256(roleRevokedLogs[1].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(roleRevokedLogs[1].topics[3]))), PAS_DEPLOYER);

        assertEq(roleRevokedLogs[2].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(roleRevokedLogs[2].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(roleRevokedLogs[2].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(roleRevokedLogs[2].topics[3]))), PAS_DEPLOYER);

        // Min delay set once by the constructor

        VmSafe.EthGetLogs[] memory minDelayChangeLogs = _getEvents(block.chainid, PAS_TIMELOCK, ITimelockLike.MinDelayChange.selector);

        assertEq(minDelayChangeLogs.length, 1);

        ( uint256 oldDuration, uint256 newDuration ) = abi.decode(minDelayChangeLogs[0].data, (uint256, uint256));

        assertEq(minDelayChangeLogs[0].topics[0], ITimelockLike.MinDelayChange.selector);
        assertEq(oldDuration,                     0);
        assertEq(newDuration,                     PAS_MIN_DELAY);

        // Paused by the deployer

        VmSafe.EthGetLogs[] memory pausedLogs = _getEvents(block.chainid, PAS_TIMELOCK, ITimelockLike.Paused.selector);

        assertEq(pausedLogs.length, 1);

        assertEq(pausedLogs[0].topics[0],                     ITimelockLike.Paused.selector);
        assertEq(abi.decode(pausedLogs[0].data, (address)),   PAS_DEPLOYER);

        assertEq(_getEvents(block.chainid, PAS_TIMELOCK, ITimelockLike.Unpaused.selector).length, 0);
    }

    function test_ARBITRUM_pasConfigurator_setRateLimit() external onChain(ChainIdUtils.ArbitrumOne()) {
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Arbitrum.PAU_CONTROLLER);

        bytes32 toCctpKey   = controller.cctp_toCCTPRateLimitKey();
        bytes32 toDomainKey = controller.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM);

        // PAS Configurator is not admin on the PAU RateLimits, therfore this reverts
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            PAS_CONFIGURATOR,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(Arbitrum.PAU_RATELIMITS, toCctpKey);

        _assertRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        // Only the cBEAM can go through the Configurator
        vm.expectRevert("Configurator/not-authorized-ratelimits-cBeam");
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 0, 0);

        // CBeam can only set rate limits for keys that are already registered
        vm.expectRevert("Configurator/exceeds-max-amount");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, keccak256("NEW_KEY"), 1, 0);

        // If the key is unlimited, the configurator cannot set it to a limited amount
        vm.expectRevert("Configurator/unlimited-incorrect-params");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toCctpKey, 1_000_000e6, 0);

        // Setting the cctp -> CCTP rate limit to unlimited works
        vm.prank(PAS_CBEAM);
        vm.expectEmit(PAS_CONFIGURATOR);
        emit IConfiguratorLike.SetRateLimit(Arbitrum.PAU_RATELIMITS, toCctpKey, type(uint256).max, 0);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toCctpKey, type(uint256).max, 0);

        _assertUnlimitedRateLimit(Arbitrum.PAU_RATELIMITS, toCctpKey);

        // Decreases apply immediately and do not consume the hop
        vm.prank(PAS_CBEAM);
        vm.expectEmit(PAS_CONFIGURATOR);
        emit IConfiguratorLike.SetRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(10_000_000e6) / 1 days);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(10_000_000e6) / 1 days);

        _assertRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(10_000_000e6) / 1 days, 1_000_000e6, block.timestamp);

        assertEq(configurator.zzz(Arbitrum.PAU_RATELIMITS, toDomainKey), 0);

        // Increases are capped at maxChange (1.2x) of the current values
        uint256 maxAmountCeiling = 1_000_000e6 * PAS_MAX_CHANGE / 1e18;
        uint256 slopeCeiling     = uint256(10_000_000e6) / 1 days * PAS_MAX_CHANGE / 1e18;

        vm.prank(PAS_CBEAM);
        vm.expectRevert("Configurator/exceeds-max-amount");
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        vm.prank(PAS_CBEAM);
        vm.expectRevert("Configurator/exceeds-max-slope");
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling, slopeCeiling + 1);

        // First increase is allowed right away (hop timer starts at 0)
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling, slopeCeiling);

        assertEq(configurator.zzz(Arbitrum.PAU_RATELIMITS, toDomainKey), block.timestamp);

        // Next increase has to wait for the hop
        vm.prank(PAS_CBEAM);
        vm.expectRevert("Configurator/increment-too-soon");
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        skip(PAS_HOP - 1);

        vm.prank(PAS_CBEAM);
        vm.expectRevert("Configurator/increment-too-soon");
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        skip(1);

        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Arbitrum.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        assertEq(configurator.zzz(Arbitrum.PAU_RATELIMITS, toDomainKey), block.timestamp);
    }

    function test_ARBITRUM_sll_pasConfigurator_callControllerAction() external onChain(ChainIdUtils.ArbitrumOne()) {
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Arbitrum.PAU_CONTROLLER);
        IBeaconLike       beacon       = IBeaconLike(Arbitrum.SPARK_BEACON);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        // The only pre-approved action is removing the CCTP facet from the PAU Controller (emergency stop)
        bytes memory removeCctpFacet = abi.encodeCall(controller.removeIntegrations, (ids));

        // Configurator is not admin on the PAU AccessControls yet, so the controller rejects it
        vm.expectRevert("Configurator/call-failed");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Arbitrum.PAU_CONTROLLER, removeCctpFacet);

        _executeAllPayloadsAndBridges();

        IControllerLike.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length,                 1);
        assertEq(integrations[0].id,                  CCTP_FACET_ID);
        assertEq(integrations[0].config.facet,        Arbitrum.CCTP_FACET);
        assertEq(integrations[0].config.wires.length, 10);

        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, Arbitrum.CCTP_FACET);
        assertEq(beacon.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet,     Arbitrum.CCTP_FACET);

        vm.expectRevert("Configurator/not-authorized-controller-cBeam");
        configurator.callControllerAction(Arbitrum.PAU_CONTROLLER, removeCctpFacet);

        vm.expectRevert("Configurator/not-valid-data");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Arbitrum.PAU_CONTROLLER, abi.encodeCall(controller.updateIntegrations, (ids)));

        vm.expectEmit(Arbitrum.PAU_CONTROLLER);
        emit IControllerLike.IntegrationRemoved(CCTP_FACET_ID);
        vm.expectEmit(PAS_CONFIGURATOR);
        emit IConfiguratorLike.CallControllerAction(Arbitrum.PAU_CONTROLLER, removeCctpFacet);
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Arbitrum.PAU_CONTROLLER, removeCctpFacet);

        assertEq(controller.integrations().length,                 0);
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,        address(0));
        assertEq(controller.getConfig(CCTP_FACET_ID).wires.length, 0);

        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, address(0));
    }

    // XLayer tests

    function test_XLAYER_sll_cctp_e2e_roundTrip() external onChain(ChainIdUtils.XLayer()) {
        Bridge storage bridge = chainData[ChainIdUtils.XLayer()].bridges[2];

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        // Step 1: User deposits USDC into spUSDC on X Layer.

        deal(address(xlayerUsdc), user, 1_000_000e6);

        uint256 spUsdcBalanceBefore = xlayerUsdc.balanceOf(address(spusdc));
        uint256 spUsdcSupplyBefore  = spusdc.totalSupply();
        uint256 spUsdcAssetsBefore  = spusdc.totalAssets();

        assertEq(spUsdcBalanceBefore, 1_834_873.434447e6);
        assertEq(spUsdcSupplyBefore,  1_834_010.235962e6);
        assertEq(spUsdcAssetsBefore,  1_835_340.522841e6);

        assertEq(xlayerUsdc.balanceOf(user), 1_000_000e6);
        assertEq(spusdc.balanceOf(user),     0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        uint256 userShares = spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(userShares,             999_275.182527e6);
        assertEq(spusdc.balanceOf(user), userShares);
        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 1_000_000e6);
        assertEq(spusdc.totalSupply(),   spUsdcSupplyBefore + userShares);

        assertEq(xlayerUsdc.balanceOf(user),            0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore + 1_000_000e6);

        // Step 2: Relayer takes the USDC out of spUSDC into the ALMProxy on X Layer.

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc))),
            type(uint256).max
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.sparkVault_take, (address(spusdc), 1_000_000e6))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc))), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             spUsdcBalanceBefore);
        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 1_000_000e6);

        // Step 3: Relayer bridges the USDC to Ethereum with CCTP V2 (burn on X Layer).

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM)),
            10_000_000e6
        );

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, CCTP_V2_DOMAIN_ID_ETHEREUM, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM)),
            9_000_000e6
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(xlayerUsdc.totalSupply(),                          xlayerUsdcSupply - 1_000_000e6);

        // Step 4: Relay the message to Ethereum.

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 mainnetUsdcSupply = usdc.totalSupply();

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);

        bridge.relayMessagesToSource(true);

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 1_000_000e6);
        assertEq(usdc.totalSupply(),                            mainnetUsdcSupply + 1_000_000e6);

        // Step 5: Relayer deposits the USDC into sUSDC.

        bytes32 depositKey  = mainnetController.erc4626_getDepositRateLimitKey(Ethereum.SUSDC, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDC);

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        uint256 expectedShares = susdc.convertToShares(1_000_000e6);

        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_deposit, (Ethereum.SUSDC, 1_000_000e6, expectedShares))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY),  0);
        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), expectedShares);

        assertApproxEqAbs(susdc.convertToAssets(expectedShares), 1_000_000e6, 1);  // Share rounding

        // Step 6: Yield accrues in sUSDC.

        skip(1 days);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        skip(1 days);
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 usdcWithYield = susdc.convertToAssets(expectedShares);

        assertEq(usdcWithYield, 1_000_096.900979e6);

        // Step 7: Relayer withdraws from sUSDC by redeeming every share.

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_redeem, (Ethereum.SUSDC, expectedShares, usdcWithYield))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY),  usdcWithYield);

        // Step 8: Relayer bridges the USDC back to X Layer with CCTP V2 (burn on Ethereum).

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_XLAYER)),
            10_000_000e6
        );

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, CCTP_V2_DOMAIN_ID_XLAYER, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_XLAYER)),
            10_000_000e6 - usdcWithYield
        );

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(usdc.totalSupply(),                            mainnetUsdcSupply + 1_000_000e6 - usdcWithYield);

        // Step 9: Relay the message to X Layer.

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        bridge.relayMessagesToDestination(true);

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), usdcWithYield);
        assertEq(xlayerUsdc.totalSupply(),                          xlayerUsdcSupply - 1_000_000e6 + usdcWithYield);

        // Step 10: Relayer transfers the USDC, yield included, back into spUSDC.

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc))),
            type(uint256).max
        );

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.transferAsset_transfer, (address(xlayerUsdc), address(spusdc), usdcWithYield))
        );

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc))),
            type(uint256).max
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             spUsdcBalanceBefore + usdcWithYield);

        // Step 11: User redeems.
        assertEq(spusdc.totalAssets(), spUsdcAssetsBefore + usdcWithYield + 177.846293e6);  // 177.846293e6 accrued from yield on existing balance

        vm.prank(user);
        spusdc.redeem(userShares, user, user);

        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 177.846294e6);
        assertEq(spusdc.totalSupply(),   spUsdcSupplyBefore);
        assertEq(spusdc.balanceOf(user), 0);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield - 1); // Rounding
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore + 1); // Rounding
    }

}

contract SparkEthereum_20261008_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1790753409;  // Sep-30-2026 07:30:09 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

}

contract SparkEthereum_20261008_SpellTests is SpellTests {

    using DomainHelpers       for *;
    using CCTPV2BridgeTesting for Bridge;

    uint32 internal constant CCTP_V2_DOMAIN_ID_ETHEREUM = CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM;
    uint32 internal constant CCTP_V2_DOMAIN_ID_XLAYER   = 37;

    IAdministeredAgentLike     internal xlayerAgent;
    IForeignControllerFullLike internal xlayerController;
    IRateLimitsLike            internal xlayerRateLimits;
    ISparkVaultV2Like          internal spusdc;
    IERC20                     internal xlayerUsdc;

    IAdministeredAgentLike     internal mainnetAgent;
    IMainnetControllerFullLike internal mainnetController;
    IRateLimitsLike            internal mainnetRateLimits;
    IERC4626Like               internal susdc;
    IERC20                     internal usdc;

    ISavingsIntentsLike internal savingsVaultIntents;

    address internal user;

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1790753409;  // Sep-30-2026 07:30:09 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        // XLayer intent round trip tests setup
        xlayerAgent      = IAdministeredAgentLike(XLayer.SPUSDC_PAU_ADMINISTERED_AGENT);
        xlayerController = IForeignControllerFullLike(XLayer.SPUSDC_PAU_CONTROLLER);
        xlayerRateLimits = IRateLimitsLike(XLayer.SPUSDC_PAU_RATELIMITS);
        spusdc           = ISparkVaultV2Like(XLayer.SPARK_VAULT_V2_SPUSDC);
        xlayerUsdc       = IERC20(XLayer.USDC);

        savingsVaultIntents = ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS);

        mainnetAgent      = IAdministeredAgentLike(Ethereum.SPUSDC_PAU_ADMINISTERED_AGENT);
        mainnetController = IMainnetControllerFullLike(Ethereum.SPUSDC_PAU_CONTROLLER);
        mainnetRateLimits = IRateLimitsLike(Ethereum.SPUSDC_PAU_RATELIMITS);
        susdc             = IERC4626Like(Ethereum.SUSDC);
        usdc              = IERC20(Ethereum.USDC);

        user = makeAddr("user");

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

    // XLayer tests

    function test_XLAYER_savingsIntents_grantRole() external onChain(ChainIdUtils.XLayer()) {
        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.RELAYER()), 1);

        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(), XLayer.ALM_RELAYER_MULTISIG),          true);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(), XLayer.SPUSDC_PAU_ADMINISTERED_AGENT), false);

        _executeAllPayloadsAndBridges();

        assertEq(savingsVaultIntents.getRoleMemberCount(savingsVaultIntents.RELAYER()), 2);

        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(), XLayer.ALM_RELAYER_MULTISIG),          true);
        assertEq(savingsVaultIntents.hasRole(savingsVaultIntents.RELAYER(), XLayer.SPUSDC_PAU_ADMINISTERED_AGENT), true);
    }

    function test_XLAYER_savingsIntents_spUSDC_updateVaultConfig() external onChain(ChainIdUtils.XLayer()) {
        (
            bool    whitelisted,
            uint256 minIntentAssets,
            uint256 maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(address(spusdc));

        assertEq(whitelisted,     false);
        assertEq(minIntentAssets, 0);
        assertEq(maxIntentAssets, 0);

        _executeAllPayloadsAndBridges();

        (
            whitelisted,
            minIntentAssets,
            maxIntentAssets
        ) = savingsVaultIntents.vaultConfig(address(spusdc));

        assertEq(whitelisted,     true);
        assertEq(minIntentAssets, 1_000_000e6);
        assertEq(maxIntentAssets, 500_000_000e6);
    }

    function test_XLAYER_savingsIntents_spUSDC_e2e() external onChain(ChainIdUtils.XLayer()) {
        Bridge storage bridge = chainData[ChainIdUtils.XLayer()].bridges[2];

        // Execute spell payload
        _executeAllPayloadsAndBridges();

        // Step 1: User deposits USDC into spUSDC on X Layer.

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        deal(address(xlayerUsdc), user, 1_000_000e6);

        uint256 spUsdcBalanceBefore = xlayerUsdc.balanceOf(address(spusdc));
        uint256 spUsdcSupplyBefore  = spusdc.totalSupply();
        uint256 spUsdcAssetsBefore  = spusdc.totalAssets();

        assertEq(spUsdcBalanceBefore, 1_834_873.434447e6);
        assertEq(spUsdcSupplyBefore,  1_834_010.235962e6);
        assertEq(spUsdcAssetsBefore,  1_835_340.522841e6);

        assertEq(xlayerUsdc.balanceOf(user), 1_000_000e6);
        assertEq(spusdc.balanceOf(user),     0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        uint256 userShares = spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(userShares,             999_275.182527e6);
        assertEq(spusdc.balanceOf(user), userShares);
        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 1_000_000e6);
        assertEq(spusdc.totalSupply(),   spUsdcSupplyBefore + userShares);

        assertEq(xlayerUsdc.balanceOf(user),            0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore + 1_000_000e6);

        // Step 2: Relayer takes the USDC out of spUSDC into the ALMProxy on X Layer.

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc))),
            type(uint256).max
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.sparkVault_take, (address(spusdc), 1_000_000e6))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc))), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             spUsdcBalanceBefore);
        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 1_000_000e6);

        // Step 3: Relayer bridges the USDC to Ethereum with CCTP V2 (burn on X Layer).

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM)),
            10_000_000e6
        );

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, CCTP_V2_DOMAIN_ID_ETHEREUM, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_ETHEREUM)),
            9_000_000e6
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(xlayerUsdc.totalSupply(),                          xlayerUsdcSupply - 1_000_000e6);

        // Relay message to Ethereum

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 mainnetUsdcSupply = usdc.totalSupply();

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);

        bridge.relayMessagesToSource(true);

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 1_000_000e6);
        assertEq(usdc.totalSupply(),                            mainnetUsdcSupply + 1_000_000e6);

        // Step 4: Relayer deposits the USDC into sUSDC.

        bytes32 depositKey  = mainnetController.erc4626_getDepositRateLimitKey(Ethereum.SUSDC, Ethereum.USDC);
        bytes32 withdrawKey = mainnetController.erc4626_getWithdrawRateLimitKey(Ethereum.SUSDC);

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        uint256 expectedShares = susdc.convertToShares(1_000_000e6);

        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_deposit, (Ethereum.SUSDC, 1_000_000e6, expectedShares))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY),  0);
        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), expectedShares);

        assertApproxEqAbs(susdc.convertToAssets(expectedShares), 1_000_000e6, 1);  // Share rounding

        // Step 5: Yield accrues in sUSDC.

        skip(1 days);

        chainData[ChainIdUtils.XLayer()].domain.selectFork();
        skip(1 days);
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 usdcWithYield = susdc.convertToAssets(expectedShares);

        assertEq(usdcWithYield, 1_000_096.900979e6);

        // Step 6: User creates a savings intent request for spUSDC

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        assertEq(spusdc.balanceOf(user),                userShares);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore); // Withdrawing all 1M shares of user is not possible without intent

        assertEq(savingsVaultIntents.vaultRequestCount(address(spusdc)), 0);

        vm.startPrank(user);
        spusdc.approve(address(savingsVaultIntents), userShares);

        uint256 requestId = savingsVaultIntents.request({
            vault     : address(spusdc),
            shares    : userShares,
            recipient : user,
            deadline  : block.timestamp + 2 days
        });
        vm.stopPrank();

        assertEq(requestId,                                              1);
        assertEq(savingsVaultIntents.vaultRequestCount(address(spusdc)), 1);

        // Step 7: Relayer withdraws USDC from sUSDC by redeeming every share.

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.erc4626_redeem, (Ethereum.SUSDC, expectedShares, usdcWithYield))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(depositKey),  type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        assertEq(susdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY),  usdcWithYield);

        // Step 8: Relayer bridges USDC back to X Layer with CCTP V2 (burn on Ethereum).

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_XLAYER)),
            10_000_000e6
        );

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, CCTP_V2_DOMAIN_ID_XLAYER, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTP_V2_DOMAIN_ID_XLAYER)),
            10_000_000e6 - usdcWithYield
        );

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(usdc.totalSupply(),                            mainnetUsdcSupply + 1_000_000e6 - usdcWithYield);

        // Relay the message to X Layer.

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        bridge.relayMessagesToDestination(true);

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), usdcWithYield);
        assertEq(xlayerUsdc.totalSupply(),                          xlayerUsdcSupply - 1_000_000e6 + usdcWithYield);

        // Step 9: Relayer transfers the USDC into spUSDC

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc))),
            type(uint256).max
        );

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.transferAsset_transfer, (address(xlayerUsdc), address(spusdc), usdcWithYield))
        );

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc))),
            type(uint256).max
        );

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             spUsdcBalanceBefore + usdcWithYield);

        // Step 10: Relayer fulfills the savings intent request

        _assertWithdrawRequests(user, address(spusdc), 1, userShares, user, block.timestamp + 2 days);

        assertEq(savingsVaultIntents.vaultRequestCount(address(spusdc)), 1);

        assertEq(spusdc.totalAssets(), spUsdcAssetsBefore + usdcWithYield + 177.846293e6);  // 177.846293e6 accrued from yield on existing balance

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(savingsVaultIntents),
            abi.encodeCall(savingsVaultIntents.fulfill, (user, address(spusdc), requestId))
        );

        _assertWithdrawRequests(user, address(spusdc), 0, 0, address(0), 0); // Request is fulfilled

        assertEq(savingsVaultIntents.vaultRequestCount(address(spusdc)), 1);

        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 177.846294e6);
        assertEq(spusdc.totalSupply(),   spUsdcSupplyBefore);
        assertEq(spusdc.balanceOf(user), 0);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield - 1); // Rounding
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore + 1); // Rounding
    }

    function _assertWithdrawRequests(
        address account,
        address vault,
        uint256 requestIdExpected,
        uint256 sharesExpected,
        address recipientExpected,
        uint256 deadlineExpected
    ) internal {
        (
            uint256 requestId,
            uint256 shares,
            address recipient,
            uint256 deadline
        ) = savingsVaultIntents.withdrawRequests(account, vault);

        assertEq(requestId, requestIdExpected);
        assertEq(shares,    sharesExpected);
        assertEq(recipient, recipientExpected);
        assertEq(deadline,  deadlineExpected);
    }

}
