// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Vm, VmSafe } from "forge-std/Vm.sol";

import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { Bridge }                from "lib/xchain-helpers/src/testing/Bridge.sol";
import { CCTPV2BridgeTesting }   from "lib/xchain-helpers/src/testing/bridges/CCTPV2BridgeTesting.sol";
import { CCTPForwarder }         from "lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { DomainHelpers }         from "lib/xchain-helpers/src/testing/Domain.sol";
import { RecordedLogs }          from "lib/xchain-helpers/src/testing/utils/RecordedLogs.sol";
import { ArbitrumBridgeTesting } from "lib/xchain-helpers/src/testing/bridges/ArbitrumBridgeTesting.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { IPositionManagerLike } from "src/interfaces/Interfaces.sol";

interface IAccessControlsLike {

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

    event Start();

    event Stop();

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

    function getMaxChange(address rateLimits) external view returns (uint256);

    function hasUserRole(address usr, uint8 role) external view returns (bool);

    function hop(address rateLimits) external view returns (uint256);

    function isControllerActionEnabled(bytes32 key, address controller) external view returns (bool);

    function maxChange(address rateLimits) external view returns (uint256);

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

    function removeIntegrations(bytes32[] calldata ids) external;

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IERC4626Like {

    function balanceOf(address account) external view returns (uint256);

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

interface ISafeLike {

    function getOwners() external view returns (address[] memory);

    function getThreshold() external view returns (uint256);

}

interface ITimelockLike {

    error EnforcedPause();

    error TimelockUnexpectedOperationState(bytes32 id, bytes32 state);

    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    event Paused(address account);

    function CANCELLER_ROLE() external view returns (bytes32);

    function EXECUTOR_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function PROPOSER_ROLE() external view returns (bytes32);

    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[]   calldata payloads,
        bytes32            predecessor,
        bytes32            salt
    ) external payable;

    function getMinDelay() external view returns (uint256);

    function getOperationsCount() external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[]   calldata payloads,
        bytes32            predecessor,
        bytes32            salt
    ) external pure returns (bytes32);

    function isOperationReady(bytes32 id) external view returns (bool);

    function paused() external view returns (bool);

    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[]   calldata payloads,
        bytes32            predecessor,
        bytes32            salt,
        uint256            delay
    ) external;

    function unpause() external;

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

contract SparkEthereum_20261105_SLLTests is SparkLiquidityLayerTests {

    using DomainHelpers       for *;
    using CCTPV2BridgeTesting for Bridge;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    // Base PAU Administered Agent addresses

    address internal constant SOTER_FREEZER_MULTISIG = 0x747BF29B189e2a070a921Af7Cf65681E3d5F5967;
    address internal constant SOTER_GRANTOR_MULTISIG = 0x97EC6398e5dD047BA3223cFC017bFC6436Ac3Fe7;

    // PAS

    address internal constant PAS_BEAM_STATE   = 0x29840a8519013F483d94781b5C1671b552A109e1;
    address internal constant PAS_CBEAM        = 0x492aae70E59551768BAF3c7159d3f951B6ed76Fe;
    address internal constant PAS_CONFIGURATOR = 0x458Acd38fD749F6325039e63e8Bc496dBc286D11;
    address internal constant PAS_CORE_COUNCIL = 0x148eF923d764CBdc1597CcADBbbC66499C1A1432;
    address internal constant PAS_DEPLOYER     = 0xD6A9F61AcC8241760DFbbbb84f81986835c84477;
    address internal constant PAS_TIMELOCK     = 0x2ACADc011b4fc13072F92231D1216c16deac5188;

    uint8 internal constant PAS_ROLE_DELAYED   = 1;  // BeamState actions routed through the Timelock
    uint8 internal constant PAS_ROLE_IMMEDIATE = 2;  // BeamState actions the Core Council can call directly

    uint256 internal constant PAS_HOP             = 16 hours;
    uint256 internal constant PAS_MAX_CHANGE      = 1.2e18;
    uint256 internal constant TIMELOCK_MIN_DELAY  = 14 days;

    bytes32 internal constant CCTP_FACET_ID = "CCTP_FACET";

    constructor() {
        _spellId   = 20261105;
        _blockDate = 1793262597;  // Oct-29-2026 08:29:57 +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Base()].payload     = 0x9D65941254A167B844F48FA29fa987783886D82a;
        chainData[ChainIdUtils.Ethereum()].payload = 0x9C3991A36aE899c7b267208bad2cC1237BE36F5b;
    }

    // Ethereum tests

    function test_ETHEREUM_sll_onboardBridgeUSDC_OUSD() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            Ethereum.BRIDGE_USDC_DEPOSIT
        );

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : Ethereum.BRIDGE_USDC_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_onboardBridgeOUSD_USDC() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.OUSD,
            Ethereum.BRIDGE_OUSD_DEPOSIT
        );

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, transferKey, 5_000_000e6, 200_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.OUSD,
            destination    : Ethereum.BRIDGE_OUSD_DEPOSIT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_onboardUniswapV4OUSDUSDS() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  OUSD_USDS_POOL_ID));
        bytes32 withdrawKey = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), OUSD_USDS_POOL_ID));
        bytes32 swapKey     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     OUSD_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(OUSD_USDS_POOL_ID)))), 0);

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, depositKey,  0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, withdrawKey, 0, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, swapKey,     0, 0);

        ( int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing ) = controller.uniswapV4TickLimits(OUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(OUSD_USDS_POOL_ID)))), 0.999e18);

        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, depositKey,  10_000_000e18,     50_000_000e18 / uint256(1 days));
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, withdrawKey, type(uint256).max, 0);
        _assertRateLimit(Ethereum.ALM_RATE_LIMITS, swapKey,     5_000_000e18,      100_000_000e18 / uint256(1 days));

        ( _tickLowerMin, _tickUpperMax, _maxTickSpacing ) = controller.uniswapV4TickLimits(OUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   276_314);
        assertEq(_tickUpperMax,   276_334);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4LPIntegration(UniswapV4LPE2ETestParams({
            ctx           : _getSparkLiquidityLayerContext(),
            poolId        : OUSD_USDS_POOL_ID,
            asset0        : Ethereum.OUSD,
            asset1        : Ethereum.USDS,
            depositAmount : 1_000_000e18,
            depositKey    : depositKey,
            withdrawKey   : withdrawKey
        }));
    }

    function test_ETHEREUM_sll_uniswapV4OUSDUSDS_swap() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 swapKey = keccak256(abi.encode(MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_UNISWAP_V4_SWAP(), OUSD_USDS_POOL_ID));

        _executeAllPayloadsAndBridges();

        _testUniswapV4SwapIntegration(UniswapV4SwapE2ETestParams({
            ctx           : _getSparkLiquidityLayerContext(),
            poolId        : OUSD_USDS_POOL_ID,
            asset0        : Ethereum.OUSD,
            asset1        : Ethereum.USDS,
            seedLiquidity : 2_000_000e18,
            swapAmount    : 1_000_000e18,
            swapKey       : swapKey
        }));
    }

    function test_ETHEREUM_sll_uniswapV4OUSDUSDS_poolKey() external onChain(ChainIdUtils.Ethereum()) {
        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(OUSD_USDS_POOL_ID));

        assertEq(Currency.unwrap(poolKey.currency0), Ethereum.OUSD);
        assertEq(Currency.unwrap(poolKey.currency1), Ethereum.USDS);
        assertEq(poolKey.fee,                        5);  // 0.0005%
        assertEq(poolKey.tickSpacing,                1);
        assertEq(address(poolKey.hooks),             address(0));

        assertEq(keccak256(abi.encode(poolKey)), OUSD_USDS_POOL_ID);
    }

    // Base tests

    function test_BASE_sll_beaconRoleTransfer() external onChain(ChainIdUtils.Base()) {
        IBeaconLike beacon = IBeaconLike(Base.SPARK_BEACON);

        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE),           1);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Base.SKY_GOV_RELAY),  false);

        _executeAllPayloadsAndBridges();

        assertEq(beacon.getRoleMemberCount(DEFAULT_ADMIN_ROLE),           1);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), false);
        assertEq(beacon.hasRole(DEFAULT_ADMIN_ROLE, Base.SKY_GOV_RELAY),  true);
    }

    function test_BASE_sll_parallelPAU_grantPASConfigurator() external onChain(ChainIdUtils.Base()) {
        IAccessControlsLike accessControls = IAccessControlsLike(Base.PAU_ACCESS_CONTROLS);
        IRateLimitsLike     rateLimits     = IRateLimitsLike(Base.PAU_RATELIMITS);

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),           1);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),    false);

        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),    false);

        _executeAllPayloadsAndBridges();

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),           2);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),    true);

        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR), true);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR),    true);
    }

    function test_BASE_sll_parallelPAU_roles() external onChain(ChainIdUtils.Base()) {
        IAdministeredAgentLike administeredAgent = IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT);
        IALMProxyLike          almProxy          = IALMProxyLike(Base.ALM_PROXY);

        bytes32 controllerRole = almProxy.CONTROLLER();

        // ALMProxy roles

        assertEq(almProxy.hasRole(controllerRole, Base.ALM_CONTROLLER), true);
        assertEq(almProxy.hasRole(controllerRole, Base.PAU_CONTROLLER), false);

        // PAU Administered Agent roles

        assertEq(administeredAgent.adminCount(), 1);
        assertEq(administeredAgent.getAdmin(0),  Base.SPARK_EXECUTOR);

        assertEq(administeredAgent.actorCount(), 1);
        assertEq(administeredAgent.getActor(0),  Base.ALM_RELAYER_MULTISIG);

        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.getGrantor(0),  Base.PAU_GRANTOR_MULTISIG);

        assertEq(administeredAgent.revokerCount(), 1);
        assertEq(administeredAgent.getRevoker(0),  Base.ALM_FREEZER_MULTISIG);

        _executeAllPayloadsAndBridges();

        // ALMProxy roles

        assertEq(almProxy.hasRole(controllerRole, Base.ALM_CONTROLLER), true);
        assertEq(almProxy.hasRole(controllerRole, Base.PAU_CONTROLLER), true);

        // PAU Administered Agent roles

        assertEq(administeredAgent.adminCount(), 1);
        assertEq(administeredAgent.getAdmin(0),  Base.SPARK_EXECUTOR);

        assertEq(administeredAgent.actorCount(), 2);
        assertEq(administeredAgent.getActor(0),  Base.ALM_RELAYER_MULTISIG);
        assertEq(administeredAgent.getActor(1),  Base.PLANNER_WALLET);

        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.getGrantor(0),  SOTER_GRANTOR_MULTISIG);

        assertEq(administeredAgent.revokerCount(), 2);
        assertEq(administeredAgent.getRevoker(0),  Base.ALM_FREEZER_MULTISIG);
        assertEq(administeredAgent.getRevoker(1),  SOTER_FREEZER_MULTISIG);
    }

    function test_BASE_sll_parallelPAU_roles_events() external onChain(ChainIdUtils.Base()) {
        bytes32 controllerRole = IALMProxyLike(Base.ALM_PROXY).CONTROLLER();

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

            if      (logs[i].emitter == Base.ALM_PROXY)      almProxyLogs[almProxyCount++]     = logs[i];
            else if (logs[i].emitter == Base.PAU_RATELIMITS) rateLimitsLogs[rateLimitsCount++] = logs[i];
        }

        assertEq(almProxyCount,   1);
        assertEq(rateLimitsCount, 1);

        assertEq(almProxyLogs[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(almProxyLogs[0].topics[1],                            controllerRole);
        assertEq(address(uint160(uint256(almProxyLogs[0].topics[2]))), Base.PAU_CONTROLLER);
        assertEq(address(uint160(uint256(almProxyLogs[0].topics[3]))), Base.SPARK_EXECUTOR);

        assertEq(rateLimitsLogs[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(rateLimitsLogs[0].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(rateLimitsLogs[0].topics[2]))), PAS_CONFIGURATOR);
        assertEq(address(uint160(uint256(rateLimitsLogs[0].topics[3]))), Base.SPARK_EXECUTOR);

        assertEq(IAccessControl(Base.ALM_PROXY).hasRole(controllerRole, Base.PAU_CONTROLLER), true);
        assertEq(IAccessControl(Base.ALM_PROXY).hasRole(controllerRole, Base.SPARK_EXECUTOR), false);
    }

    function test_BASE_sll_pauCctpV2_onboarding() external onChain(ChainIdUtils.Base()) {
        IControllerLike controller = IControllerLike(Base.PAU_CONTROLLER);

        _assertRateLimit(Base.PAU_RATELIMITS, controller.cctp_toCCTPRateLimitKey(), 0, 0);

        _assertRateLimit(
            Base.PAU_RATELIMITS,
            controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );

        ( bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate )
            = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(mintRecipient, bytes32(0));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);

        _executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, controller.cctp_toCCTPRateLimitKey());

        _assertRateLimit(
            Base.PAU_RATELIMITS,
            controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );

        ( mintRecipient, minFeeCapRate, maxFeeCapRate )
            = controller.cctp_getDomainParameters(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(mintRecipient, bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
        assertEq(minFeeCapRate, 0);
        assertEq(maxFeeCapRate, 0);
    }

    function test_BASE_sll_pauCctpV2_rateLimitEnforced() external onChain(ChainIdUtils.Base()) {
        _executeAllPayloadsAndBridges();

        vm.prank(Base.ALM_RELAYER_MULTISIG);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).call(
            Base.PAU_CONTROLLER,
            abi.encodeCall
            (IForeignControllerFullLike.cctp_transfer,
            (5_000_000e6 + 1, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );
    }

    function test_BASE_pasConfigurator_state() external onChain(ChainIdUtils.Base()) {
        assertEq(IConfiguratorLike(PAS_CONFIGURATOR).beamState(), PAS_BEAM_STATE);
    }

    function test_BASE_beamState_stopped() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.stopped(), false);

        VmSafe.EthGetLogs[] memory startLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Start.selector);
        VmSafe.EthGetLogs[] memory stopLogs  = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Stop.selector);

        assertEq(startLogs.length, 0);
        assertEq(stopLogs.length,  0);
    }

    function test_BASE_beamState_wards() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // BeamState admin: Sky governance only

        assertEq(beamState.wards(Base.SKY_GOV_RELAY), 1);
        assertEq(beamState.wards(PAS_DEPLOYER),           0);

        VmSafe.EthGetLogs[] memory relyLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Rely.selector);
        VmSafe.EthGetLogs[] memory denyLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.Deny.selector);

        assertEq(relyLogs.length, 2);
        assertEq(denyLogs.length, 1);

        assertEq(relyLogs[0].topics[0],                            IBeamStateLike.Rely.selector);
        assertEq(address(uint160(uint256(relyLogs[0].topics[1]))), PAS_DEPLOYER);

        assertEq(relyLogs[1].topics[0],                            IBeamStateLike.Rely.selector);
        assertEq(address(uint160(uint256(relyLogs[1].topics[1]))), Base.SKY_GOV_RELAY);

        assertEq(denyLogs[0].topics[0],                            IBeamStateLike.Deny.selector);
        assertEq(address(uint160(uint256(denyLogs[0].topics[1]))), PAS_DEPLOYER);
    }

    function test_BASE_beamState_userRoles() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // BeamState user roles: Timelock has delayed role, Core Council has immediate role.

        assertEq(beamState.hasUserRole(PAS_TIMELOCK,     PAS_ROLE_DELAYED), true);
        assertEq(beamState.hasUserRole(PAS_CORE_COUNCIL, PAS_ROLE_DELAYED), false);

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

    function test_BASE_beamState_actionRoles() external onChain(ChainIdUtils.Base()) {
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

    function test_BASE_beamState_rateLimits() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.rateLimits(Base.PAU_RATELIMITS), 1);

        VmSafe.EthGetLogs[] memory addRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddRateLimits.selector);
        VmSafe.EthGetLogs[] memory delRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelRateLimits.selector);

        assertEq(addRateLimitsLogs.length, 1);
        assertEq(delRateLimitsLogs.length, 0);

        assertEq(addRateLimitsLogs[0].topics[0],                            IBeamStateLike.AddRateLimits.selector);
        assertEq(address(uint160(uint256(addRateLimitsLogs[0].topics[1]))), Base.PAU_RATELIMITS);
    }

    function test_BASE_beamState_controllers() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.controllers(Base.PAU_CONTROLLER), 1);

        VmSafe.EthGetLogs[] memory addControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddController.selector);
        VmSafe.EthGetLogs[] memory delControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelController.selector);

        assertEq(addControllerLogs.length, 1);
        assertEq(delControllerLogs.length, 0);

        assertEq(addControllerLogs[0].topics[0],                            IBeamStateLike.AddController.selector);
        assertEq(address(uint160(uint256(addControllerLogs[0].topics[1]))), Base.PAU_CONTROLLER);
    }

    function test_BASE_beamState_cBeams() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.cBeams(PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory addCBeamLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddCBeam.selector);
        VmSafe.EthGetLogs[] memory delCBeamLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelCBeam.selector);

        assertEq(addCBeamLogs.length, 1);
        assertEq(delCBeamLogs.length, 0);

        assertEq(addCBeamLogs[0].topics[0],                            IBeamStateLike.AddCBeam.selector);
        assertEq(address(uint160(uint256(addCBeamLogs[0].topics[1]))), PAS_CBEAM);
    }

    function test_BASE_beamState_rateLimitsCBeams() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.rateLimitsCBeams(Base.PAU_RATELIMITS, PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory setCBeamForRateLimitsLogs   = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetCBeamForRateLimits.selector);
        VmSafe.EthGetLogs[] memory unsetCBeamForRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.UnsetCBeamForRateLimits.selector);

        assertEq(setCBeamForRateLimitsLogs.length,   1);
        assertEq(unsetCBeamForRateLimitsLogs.length, 0);

        assertEq(setCBeamForRateLimitsLogs[0].topics[0],                            IBeamStateLike.SetCBeamForRateLimits.selector);
        assertEq(address(uint160(uint256(setCBeamForRateLimitsLogs[0].topics[1]))), Base.PAU_RATELIMITS);
        assertEq(address(uint160(uint256(setCBeamForRateLimitsLogs[0].topics[2]))), PAS_CBEAM);
    }

    function test_BASE_beamState_controllersCBeams() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.controllersCBeams(Base.PAU_CONTROLLER, PAS_CBEAM), 1);

        VmSafe.EthGetLogs[] memory setCBeamForControllerLogs   = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetCBeamForController.selector);
        VmSafe.EthGetLogs[] memory unsetCBeamForControllerLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.UnsetCBeamForController.selector);

        assertEq(setCBeamForControllerLogs.length,   1);
        assertEq(unsetCBeamForControllerLogs.length, 0);

        assertEq(setCBeamForControllerLogs[0].topics[0],                            IBeamStateLike.SetCBeamForController.selector);
        assertEq(address(uint160(uint256(setCBeamForControllerLogs[0].topics[1]))), Base.PAU_CONTROLLER);
        assertEq(address(uint160(uint256(setCBeamForControllerLogs[0].topics[2]))), PAS_CBEAM);
    }

    function test_BASE_beamState_initRateLimits() external onChain(ChainIdUtils.Base()) {
        VmSafe.EthGetLogs[] memory addInitRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddInitRateLimits.selector);
        VmSafe.EthGetLogs[] memory delInitRateLimitsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelInitRateLimits.selector);

        assertEq(addInitRateLimitsLogs.length, 0);
        assertEq(delInitRateLimitsLogs.length, 0);
    }

    function test_BASE_beamState_initControllerActions() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike  beamState  = IBeamStateLike(PAS_BEAM_STATE);
        IControllerLike controller = IControllerLike(Base.PAU_CONTROLLER);

        // The only pre-approved controller action is removing the CCTP facet
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        assertEq(beamState.isControllerActionEnabled(keccak256(abi.encodeCall(controller.removeIntegrations, (ids))), Base.PAU_CONTROLLER), true);

        VmSafe.EthGetLogs[] memory addInitControllerActionsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.AddInitControllerActions.selector);
        VmSafe.EthGetLogs[] memory delInitControllerActionsLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.DelInitControllerActions.selector);

        assertEq(addInitControllerActionsLogs.length, 1);
        assertEq(delInitControllerActionsLogs.length, 0);

        assertEq(addInitControllerActionsLogs[0].topics[0],                            IBeamStateLike.AddInitControllerActions.selector);
        assertEq(addInitControllerActionsLogs[0].topics[1],                            bytes32(keccak256(abi.encodeCall(controller.removeIntegrations, (ids)))));
        assertEq(address(uint160(uint256(addInitControllerActionsLogs[0].topics[2]))), Base.PAU_CONTROLLER);
    }

    function test_BASE_beamState_hop() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.hop(address(0)),              PAS_HOP);
        assertEq(beamState.hop(Base.PAU_RATELIMITS), 0);

        assertEq(beamState.getHop(address(0)),              PAS_HOP);
        assertEq(beamState.getHop(Base.PAU_RATELIMITS), PAS_HOP);

        VmSafe.EthGetLogs[] memory setHopLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetHop.selector);

        assertEq(setHopLogs.length, 1);
        assertEq(setHopLogs[0].topics[0],                            IBeamStateLike.SetHop.selector);
        assertEq(address(uint160(uint256(setHopLogs[0].topics[1]))), address(0));  // Zero address for default
        assertEq(abi.decode(setHopLogs[0].data, (uint256)),          PAS_HOP);
    }

    function test_BASE_beamState_maxChange() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        assertEq(beamState.maxChange(address(0)),          PAS_MAX_CHANGE);
        assertEq(beamState.maxChange(Base.PAU_RATELIMITS), 0);

        assertEq(beamState.getMaxChange(address(0)),          PAS_MAX_CHANGE);
        assertEq(beamState.getMaxChange(Base.PAU_RATELIMITS), PAS_MAX_CHANGE);

        VmSafe.EthGetLogs[] memory setMaxChangeLogs = _getEvents(block.chainid, PAS_BEAM_STATE, IBeamStateLike.SetMaxChange.selector);

        assertEq(setMaxChangeLogs.length, 1);
        assertEq(setMaxChangeLogs[0].topics[0],                            IBeamStateLike.SetMaxChange.selector);
        assertEq(address(uint160(uint256(setMaxChangeLogs[0].topics[1]))), address(0));  // Zero address for default
        assertEq(abi.decode(setMaxChangeLogs[0].data, (uint256)),          PAS_MAX_CHANGE);
    }

    function test_BASE_timelock_state() external onChain(ChainIdUtils.Base()) {
        ITimelockLike timelock = ITimelockLike(PAS_TIMELOCK);

        assertEq(timelock.getMinDelay(),        TIMELOCK_MIN_DELAY);
        assertEq(timelock.paused(),             true);
        assertEq(timelock.getOperationsCount(), 0);

        assertEq(timelock.hasRole(DEFAULT_ADMIN_ROLE, Base.SKY_GOV_RELAY), true);
        assertEq(timelock.hasRole(DEFAULT_ADMIN_ROLE, PAS_DEPLOYER),       false);

        assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(),  PAS_CORE_COUNCIL), true);
        assertEq(timelock.hasRole(timelock.CANCELLER_ROLE(), PAS_CORE_COUNCIL), true);
        assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(),  address(0)),       true);  // Anyone can execute

        assertEq(timelock.hasRole(timelock.PAUSER_ROLE(), PAS_DEPLOYER), false);
    }

    function test_BASE_timelock_events() external onChain(ChainIdUtils.Base()) {
        ITimelockLike timelock = ITimelockLike(PAS_TIMELOCK);

        bytes32 pauserRole = timelock.PAUSER_ROLE();

        VmSafe.EthGetLogs[] memory allEvents = _getEvents(block.chainid, PAS_TIMELOCK, bytes32(0));

        assertEq(allEvents.length, 12);

        assertEq(allEvents[0].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[0].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(allEvents[0].topics[2]))), PAS_TIMELOCK);
        assertEq(address(uint160(uint256(allEvents[0].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[1].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[1].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(allEvents[1].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(allEvents[1].topics[3]))), PAS_DEPLOYER);

        ( uint256 oldDuration, uint256 newDuration ) = abi.decode(allEvents[2].data, (uint256, uint256));

        assertEq(allEvents[2].topics[0], ITimelockLike.MinDelayChange.selector);
        assertEq(oldDuration,            0);
        assertEq(newDuration,            TIMELOCK_MIN_DELAY);

        assertEq(allEvents[3].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(allEvents[3].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(allEvents[3].topics[2]))), PAS_TIMELOCK);
        assertEq(address(uint160(uint256(allEvents[3].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[4].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[4].topics[1],                            timelock.EXECUTOR_ROLE());
        assertEq(address(uint160(uint256(allEvents[4].topics[2]))), address(0));  // Anyone can execute
        assertEq(address(uint160(uint256(allEvents[4].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[5].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[5].topics[1],                            timelock.PROPOSER_ROLE());
        assertEq(address(uint160(uint256(allEvents[5].topics[2]))), PAS_CORE_COUNCIL);
        assertEq(address(uint160(uint256(allEvents[5].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[6].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[6].topics[1],                            timelock.CANCELLER_ROLE());
        assertEq(address(uint160(uint256(allEvents[6].topics[2]))), PAS_CORE_COUNCIL);
        assertEq(address(uint160(uint256(allEvents[6].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[7].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[7].topics[1],                            pauserRole);
        assertEq(address(uint160(uint256(allEvents[7].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(allEvents[7].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[8].topics[0],                   ITimelockLike.Paused.selector);
        assertEq(abi.decode(allEvents[8].data, (address)), PAS_DEPLOYER);

        assertEq(allEvents[9].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(allEvents[9].topics[1],                            pauserRole);
        assertEq(address(uint160(uint256(allEvents[9].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(allEvents[9].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[10].topics[0],                            IAccessControl.RoleGranted.selector);
        assertEq(allEvents[10].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(allEvents[10].topics[2]))), Base.SKY_GOV_RELAY);
        assertEq(address(uint160(uint256(allEvents[10].topics[3]))), PAS_DEPLOYER);

        assertEq(allEvents[11].topics[0],                            IAccessControl.RoleRevoked.selector);
        assertEq(allEvents[11].topics[1],                            DEFAULT_ADMIN_ROLE);
        assertEq(address(uint160(uint256(allEvents[11].topics[2]))), PAS_DEPLOYER);
        assertEq(address(uint160(uint256(allEvents[11].topics[3]))), PAS_DEPLOYER);
    }

    function test_BASE_beamState_setHop_onlyTimelock() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);
        ITimelockLike  timelock  = ITimelockLike(PAS_TIMELOCK);

        assertEq(beamState.actionsRoles(IBeamStateLike.setHop.selector), bytes32(uint256(1) << PAS_ROLE_DELAYED));

        vm.prank(PAS_CORE_COUNCIL);
        vm.expectRevert("BeamState/role-not-authorized");
        beamState.setHop(Base.PAU_RATELIMITS, 1 hours);

        assertEq(beamState.getHop(Base.PAU_RATELIMITS), PAS_HOP);

        // The Core Council proposes the same call through the Timelock
        address[] memory targets  = new address[](1);
        uint256[] memory values   = new uint256[](1);
        bytes[]   memory payloads = new bytes[](1);

        targets[0]  = PAS_BEAM_STATE;
        payloads[0] = abi.encodeCall(beamState.setHop, (Base.PAU_RATELIMITS, 1 hours));

        bytes32 id = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));

        // Assert scheduleBatch reverts before unpausing.
        vm.expectRevert(ITimelockLike.EnforcedPause.selector);
        vm.prank(PAS_CORE_COUNCIL);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), TIMELOCK_MIN_DELAY);

        // Unpause the Timelock
        assertEq(timelock.paused(), true);

        vm.prank(Base.SKY_GOV_RELAY);
        timelock.unpause();

        assertEq(timelock.paused(), false);

        // The Core Council schedules the call through the Timelock
        vm.prank(PAS_CORE_COUNCIL);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), TIMELOCK_MIN_DELAY);

        assertEq(timelock.isOperationReady(id), false);

        // Skip to just before the delay. The operation is still Waiting.
        skip(TIMELOCK_MIN_DELAY - 1);

        // Still Waiting. execute requires Ready, encoded as bit 2 (1 << OperationState.Ready).
        vm.expectRevert(abi.encodeWithSelector(
            ITimelockLike.TimelockUnexpectedOperationState.selector,
            id,
            bytes32(uint256(1 << 2))
        ));
        timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));

        // Skip to the end of the delay
        skip(1);

        assertEq(timelock.isOperationReady(id), true);

        assertEq(beamState.getHop(Base.PAU_RATELIMITS), PAS_HOP);
        assertEq(beamState.getHop(address(0)),          PAS_HOP);

        // Execution is permissionless, the Timelock is the caller into BeamState
        timelock.executeBatch(targets, values, payloads, bytes32(0), bytes32(0));

        assertEq(beamState.getHop(Base.PAU_RATELIMITS), 1 hours);
        assertEq(beamState.getHop(address(0)),          PAS_HOP);  // Default is untouched
    }

    function test_BASE_beamState_delCBeam_onlyCouncil() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike beamState = IBeamStateLike(PAS_BEAM_STATE);

        // delCBeam is an IMMEDIATE action: the Core Council calls it directly, the Timelock is not authorized
        assertEq(beamState.actionsRoles(IBeamStateLike.delCBeam.selector), bytes32(uint256(1) << PAS_ROLE_IMMEDIATE));

        assertEq(beamState.cBeams(PAS_CBEAM), 1);

        // The Timelock only holds the DELAYED role, so it cannot call it
        vm.prank(PAS_TIMELOCK);
        vm.expectRevert("BeamState/role-not-authorized");
        beamState.delCBeam(PAS_CBEAM);

        assertEq(beamState.cBeams(PAS_CBEAM), 1);

        // The Core Council removes the cBEAM directly, with no delay
        vm.prank(PAS_CORE_COUNCIL);
        beamState.delCBeam(PAS_CBEAM);

        assertEq(beamState.cBeams(PAS_CBEAM), 0);
    }

    function test_BASE_beamState_unsetCBeam_revokesConfiguratorAccess() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike    beamState    = IBeamStateLike(PAS_BEAM_STATE);
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Base.PAU_CONTROLLER);

        bytes32 toDomainKey = controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        bytes memory removeCctpFacet = abi.encodeCall(controller.removeIntegrations, (ids));

        _executeAllPayloadsAndBridges();

        // Assert both unsetCBeamForRateLimits and unsetCBeamForController are IMMEDIATE and that the Timelock's calls to each revert

        assertEq(beamState.actionsRoles(IBeamStateLike.unsetCBeamForRateLimits.selector), bytes32(uint256(1) << PAS_ROLE_IMMEDIATE));
        assertEq(beamState.actionsRoles(IBeamStateLike.unsetCBeamForController.selector), bytes32(uint256(1) << PAS_ROLE_IMMEDIATE));

        vm.expectRevert("BeamState/role-not-authorized");
        vm.prank(PAS_TIMELOCK);
        beamState.unsetCBeamForRateLimits(Base.PAU_RATELIMITS, PAS_CBEAM);

        vm.expectRevert("BeamState/role-not-authorized");
        vm.prank(PAS_TIMELOCK);
        beamState.unsetCBeamForController(Base.PAU_CONTROLLER, PAS_CBEAM);

        // cBEAM still succeeds with setRateLimit after delCBeam

        assertEq(beamState.cBeams(PAS_CBEAM),                                     1);
        assertEq(beamState.rateLimitsCBeams(Base.PAU_RATELIMITS, PAS_CBEAM),  1);
        assertEq(beamState.controllersCBeams(Base.PAU_CONTROLLER, PAS_CBEAM), 1);

        vm.prank(PAS_CORE_COUNCIL);
        beamState.delCBeam(PAS_CBEAM);

        assertEq(beamState.cBeams(PAS_CBEAM),                                     0);
        assertEq(beamState.rateLimitsCBeams(Base.PAU_RATELIMITS, PAS_CBEAM),  1);
        assertEq(beamState.controllersCBeams(Base.PAU_CONTROLLER, PAS_CBEAM), 1);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        // The Core Council unsets the cBEAM on the rate limits: setRateLimit is rejected

        assertEq(beamState.rateLimitsCBeams(Base.PAU_RATELIMITS, PAS_CBEAM), 1);

        vm.expectEmit(PAS_BEAM_STATE);
        emit IBeamStateLike.UnsetCBeamForRateLimits(Base.PAU_RATELIMITS, PAS_CBEAM);
        vm.prank(PAS_CORE_COUNCIL);
        beamState.unsetCBeamForRateLimits(Base.PAU_RATELIMITS, PAS_CBEAM);

        assertEq(beamState.rateLimitsCBeams(Base.PAU_RATELIMITS, PAS_CBEAM), 0);

        vm.expectRevert("Configurator/not-authorized-ratelimits-cBeam");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 500_000e6, uint256(500_000e6) / 1 days);

        // Rate limit left as the cBEAM last set it
        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(1_000_000e6) / 1 days);

        // The Core Council unsets the cBEAM on the controller: callControllerAction is rejected

        assertEq(beamState.controllersCBeams(Base.PAU_CONTROLLER, PAS_CBEAM), 1);

        vm.expectEmit(PAS_BEAM_STATE);
        emit IBeamStateLike.UnsetCBeamForController(Base.PAU_CONTROLLER, PAS_CBEAM);
        vm.prank(PAS_CORE_COUNCIL);
        beamState.unsetCBeamForController(Base.PAU_CONTROLLER, PAS_CBEAM);

        assertEq(beamState.controllersCBeams(Base.PAU_CONTROLLER, PAS_CBEAM), 0);

        vm.expectRevert("Configurator/not-authorized-controller-cBeam");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);
    }

    function test_BASE_pasConfigurator_setRateLimit() external onChain(ChainIdUtils.Base()) {
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Base.PAU_CONTROLLER);

        bytes32 toCctpKey   = controller.cctp_toCCTPRateLimitKey();
        bytes32 toDomainKey = controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        // PAS Configurator is not admin on the PAU RateLimits, therefore this reverts
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            PAS_CONFIGURATOR,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, toCctpKey);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        // Only the cBEAM can go through the Configurator
        vm.expectRevert("Configurator/not-authorized-ratelimits-cBeam");
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 0, 0);

        // CBeam can only set rate limits for keys that are already registered
        vm.expectRevert("Configurator/exceeds-max-amount");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, keccak256("NEW_KEY"), 1, 0);

        // If the key is unlimited, the configurator cannot set it to a limited amount
        vm.expectRevert("Configurator/unlimited-incorrect-params");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toCctpKey, 1_000_000e6, 0);

        // Setting the cctp -> CCTP rate limit to unlimited works
        vm.expectEmit(address(configurator));
        emit IConfiguratorLike.SetRateLimit(Base.PAU_RATELIMITS, toCctpKey, type(uint256).max, 0);
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toCctpKey, type(uint256).max, 0);

        _assertUnlimitedRateLimit(Base.PAU_RATELIMITS, toCctpKey);

        assertEq(configurator.zzz(Base.PAU_RATELIMITS, toDomainKey), 0);

        // Decreases apply immediately and do not consume the hop
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(10_000_000e6) / 1 days);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 1_000_000e6, uint256(10_000_000e6) / 1 days, 1_000_000e6, block.timestamp);

        assertEq(configurator.zzz(Base.PAU_RATELIMITS, toDomainKey), 0);

        // Increases are capped at maxChange (1.2x) of the current values
        uint256 maxAmountCeiling = 1_000_000e6 * PAS_MAX_CHANGE / 1e18;
        uint256 slopeCeiling     = uint256(10_000_000e6) / 1 days * PAS_MAX_CHANGE / 1e18;

        vm.expectRevert("Configurator/exceeds-max-amount");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        vm.expectRevert("Configurator/exceeds-max-slope");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling, slopeCeiling + 1);

        // First increase is allowed right away (hop timer starts at 0)
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling, slopeCeiling);

        assertEq(configurator.zzz(Base.PAU_RATELIMITS, toDomainKey), block.timestamp);

        // Next increase has to wait for the hop
        vm.expectRevert("Configurator/increment-too-soon");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        skip(PAS_HOP - 1);

        vm.expectRevert("Configurator/increment-too-soon");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        skip(1);

        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, maxAmountCeiling + 1, slopeCeiling);

        assertEq(configurator.zzz(Base.PAU_RATELIMITS, toDomainKey), block.timestamp);
    }

    function test_BASE_sll_pasConfigurator_callControllerAction() external onChain(ChainIdUtils.Base()) {
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Base.PAU_CONTROLLER);
        IBeaconLike       beacon       = IBeaconLike(Base.SPARK_BEACON);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        // The only pre-approved action is removing the CCTP facet from the PAU Controller (emergency stop)
        bytes memory removeCctpFacet = abi.encodeCall(controller.removeIntegrations, (ids));

        // Configurator is not admin on the PAU AccessControls yet, so the controller rejects it
        vm.expectRevert("Configurator/call-failed");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);

        _executeAllPayloadsAndBridges();

        IControllerLike.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length,                 1);
        assertEq(integrations[0].id,                  CCTP_FACET_ID);
        assertEq(integrations[0].config.facet,        Base.CCTP_FACET);
        assertEq(integrations[0].config.wires.length, 10);

        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, Base.CCTP_FACET);
        assertEq(beacon.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet,     Base.CCTP_FACET);
        // Anyone can't call the controller action, only cBeam can
        vm.expectRevert("Configurator/not-authorized-controller-cBeam");
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);

        // Only whitelisted actions can be called by cBeam
        vm.expectRevert("Configurator/not-valid-data");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, abi.encodeCall(controller.updateIntegrations, (ids)));

        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);

        assertEq(controller.integrations().length,                 0);
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,        address(0));
        assertEq(controller.getConfig(CCTP_FACET_ID).wires.length, 0);

        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, address(0));
    }

    function test_BASE_beamState_stop() external onChain(ChainIdUtils.Base()) {
        IBeamStateLike    beamState    = IBeamStateLike(PAS_BEAM_STATE);
        IConfiguratorLike configurator = IConfiguratorLike(PAS_CONFIGURATOR);
        IControllerLike   controller   = IControllerLike(Base.PAU_CONTROLLER);

        bytes32 toDomainKey = controller.cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = CCTP_FACET_ID;

        bytes memory removeCctpFacet = abi.encodeCall(controller.removeIntegrations, (ids));

        _executeAllPayloadsAndBridges();

        // stop() is IMMEDIATE (Core Council), start() is DELAYED (Timelock)

        assertEq(beamState.actionsRoles(IBeamStateLike.stop.selector),  bytes32(uint256(1) << PAS_ROLE_IMMEDIATE));
        assertEq(beamState.actionsRoles(IBeamStateLike.start.selector), bytes32(uint256(1) << PAS_ROLE_DELAYED));

        assertEq(beamState.stopped(), false);

        // Configurator works while not stopped

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 5_000_000e6, uint256(50_000_000e6) / 1 days);

        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 4_000_000e6, uint256(40_000_000e6) / 1 days);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 4_000_000e6, uint256(40_000_000e6) / 1 days);

        // The Timelock cannot stop

        assertEq(beamState.stopped(), false);

        vm.prank(PAS_TIMELOCK);
        vm.expectRevert("BeamState/role-not-authorized");
        beamState.stop();

        assertEq(beamState.stopped(), false);

        // The Core Council stops directly, with no delay

        vm.expectEmit(PAS_BEAM_STATE);
        emit IBeamStateLike.Stop();
        vm.prank(PAS_CORE_COUNCIL);
        beamState.stop();

        assertEq(beamState.stopped(), true);

        // Both Configurator entry points are blocked

        vm.expectRevert("Configurator/stopped");
        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 3_000_000e6, uint256(30_000_000e6) / 1 days);

        vm.expectRevert("Configurator/stopped");
        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);

        // The Core Council cannot start again: that goes through the Timelock or a BeamState ward

        assertEq(beamState.stopped(), true);

        vm.expectRevert("BeamState/role-not-authorized");
        vm.prank(PAS_CORE_COUNCIL);
        beamState.start();

        assertEq(beamState.stopped(), true);

        vm.expectEmit(PAS_BEAM_STATE);
        emit IBeamStateLike.Start();
        vm.prank(PAS_TIMELOCK);
        beamState.start();

        assertEq(beamState.stopped(), false);

        // Configurator works again

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 4_000_000e6, uint256(40_000_000e6) / 1 days);

        vm.prank(PAS_CBEAM);
        configurator.setRateLimit(Base.PAU_RATELIMITS, toDomainKey, 3_000_000e6, uint256(30_000_000e6) / 1 days);

        _assertRateLimit(Base.PAU_RATELIMITS, toDomainKey, 3_000_000e6, uint256(30_000_000e6) / 1 days);

        assertEq(controller.integrations().length,                                                1);
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,                                       Base.CCTP_FACET);
        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, Base.CCTP_FACET);

        vm.prank(PAS_CBEAM);
        configurator.callControllerAction(Base.PAU_CONTROLLER, removeCctpFacet);

        assertEq(controller.integrations().length,                                                0);
        assertEq(controller.getConfig(CCTP_FACET_ID).facet,                                       address(0));
        assertEq(controller.getDispatch(IForeignControllerFullLike.cctp_transfer.selector).facet, address(0));
    }

}

contract SparkEthereum_20261105_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20261105;
        _blockDate = 1793262597;  // Oct-29-2026 08:29:57 +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Base()].payload     = 0x9D65941254A167B844F48FA29fa987783886D82a;
        chainData[ChainIdUtils.Ethereum()].payload = 0x9C3991A36aE899c7b267208bad2cC1237BE36F5b;
    }

}

contract SparkEthereum_20261105_SpellTests is SpellTests {

    address internal constant SOTER_FREEZER_MULTISIG = 0x747BF29B189e2a070a921Af7Cf65681E3d5F5967;
    address internal constant SOTER_GRANTOR_MULTISIG = 0x97EC6398e5dD047BA3223cFC017bFC6436Ac3Fe7;

    address internal constant SOTER_FREEZER_OWNER_1 = 0x4d30c1B366d0dEeb82F55503c334156FeC543B17;
    address internal constant SOTER_FREEZER_OWNER_2 = 0x3481E4035409fC3a033c07D5461BED853207F517;
    address internal constant SOTER_FREEZER_OWNER_3 = 0x1aF016f8286F55E241Efd52Cf0FEEDbB257169C9;
    address internal constant SOTER_FREEZER_OWNER_4 = 0xB1aD1F6A80051658C2ba938621A7a83DEB0d324C;
    address internal constant SOTER_FREEZER_OWNER_5 = 0x52A8305f29f85bEc5fa6eE78B87Ddd2218d8E12E;

    address internal constant SOTER_GRANTOR_OWNER_1 = 0xd144625c5B1b261c7E7468dbae442088B9dAee65;
    address internal constant SOTER_GRANTOR_OWNER_2 = 0x30634F700B4C281AfbB956e77f5E189f6f49bD2A;
    address internal constant SOTER_GRANTOR_OWNER_3 = 0xd96FA1087f0CddC8dCbA53E96afBcc83cc6c82B7;
    address internal constant SOTER_GRANTOR_OWNER_4 = 0x99E4A36dA8c62a6bEACe0BAaa6cdB042a5EaB58d;
    address internal constant SOTER_GRANTOR_OWNER_5 = 0x0457f48919816092E5ba57f0014a104b085EC837;

    constructor() {
        _spellId   = 20261105;
        _blockDate = 1793262597;  // Oct-29-2026 08:29:57 +UTC
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Base()].payload     = 0x9D65941254A167B844F48FA29fa987783886D82a;
        chainData[ChainIdUtils.Ethereum()].payload = 0x9C3991A36aE899c7b267208bad2cC1237BE36F5b;
    }

    // Base tests

    function test_BASE_sll_soterMultisigs_threshold() external onChain(ChainIdUtils.Base()) {
        assertEq(ISafeLike(SOTER_FREEZER_MULTISIG).getThreshold(), 2);

        address[] memory freezerOwners = ISafeLike(SOTER_FREEZER_MULTISIG).getOwners();

        assertEq(freezerOwners.length, 5);
        assertEq(freezerOwners[0],     SOTER_FREEZER_OWNER_1);
        assertEq(freezerOwners[1],     SOTER_FREEZER_OWNER_2);
        assertEq(freezerOwners[2],     SOTER_FREEZER_OWNER_3);
        assertEq(freezerOwners[3],     SOTER_FREEZER_OWNER_4);
        assertEq(freezerOwners[4],     SOTER_FREEZER_OWNER_5);

        assertEq(ISafeLike(SOTER_GRANTOR_MULTISIG).getThreshold(), 3);

        address[] memory grantorOwners = ISafeLike(SOTER_GRANTOR_MULTISIG).getOwners();

        assertEq(grantorOwners.length, 5);
        assertEq(grantorOwners[0],     SOTER_GRANTOR_OWNER_1);
        assertEq(grantorOwners[1],     SOTER_GRANTOR_OWNER_2);
        assertEq(grantorOwners[2],     SOTER_GRANTOR_OWNER_3);
        assertEq(grantorOwners[3],     SOTER_GRANTOR_OWNER_4);
        assertEq(grantorOwners[4],     SOTER_GRANTOR_OWNER_5);
    }

}
