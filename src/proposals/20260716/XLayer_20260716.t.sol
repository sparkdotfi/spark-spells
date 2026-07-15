// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { ALMProxy }          from "spark-alm-controller/src/ALMProxy.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimits }        from "spark-alm-controller/src/RateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IRateLimits } from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

import { OptimismForwarder } from "xchain-helpers/forwarders/OptimismForwarder.sol";

import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

/**********************************************************************************************/
/*** XLayer deployment tests (ported from the xlayer-deployment repo)                       ***/
/*** Standalone fork tests — independent of the spell execution context.                    ***/
/**********************************************************************************************/

interface IXLayerReceiver {

    function l1Authority() external view returns (address);

    function target() external view returns (address);

}

interface IXLayerALMProxyFreezable {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

contract XLayerConfigTests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant RELAYER_ROLE       = keccak256("RELAYER");
    bytes32 internal constant FREEZER_ROLE       = keccak256("FREEZER");
    bytes32 internal constant CONTROLLER_ROLE    = keccak256("CONTROLLER");

    address internal constant ALM_PROXY    = XLayer.ALM_PROXY;
    address internal constant CONTROLLER   = XLayer.ALM_CONTROLLER;
    address internal constant RATE_LIMITS  = XLayer.ALM_RATE_LIMITS;
    address internal constant SPUSDT_VAULT = XLayer.SPARK_VAULT_V2_SPUSDT;

    address internal constant DEPLOYER  = 0x23d43f3189Ab9CEBfFcC0352C0490387e3105FB3;
    address internal constant FREEZER   = XLayer.ALM_FREEZER_MULTISIG;
    address internal constant EXECUTOR  = XLayer.SPARK_EXECUTOR;
    address internal constant RECEIVER  = XLayer.SPARK_RECEIVER;
    address internal constant RELAYER_1 = XLayer.ALM_RELAYER_MULTISIG;
    address internal constant RELAYER_2 = XLayer.ALM_BACKSTOP_RELAYER_MULTISIG;
    address internal constant SETTER    = XLayer.ALM_PROXY_FREEZABLE;

    address internal constant USDT                = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;
    address internal constant USDT_OFT            = 0x94BCCa6bdfd6A61817Ab0E960bFedE4984505554;
    address internal constant SPARK_VAULT_V2_IMPL = XLayer.SPARK_VAULT_V2_IMPL;

    ALMProxy          internal almProxy;
    ForeignController internal controller;
    RateLimits        internal rateLimits;
    ISparkVaultV2Like internal spusdtVault;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 internal constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    function setUp() public {
        vm.createSelectFork("https://rpc.xlayer.tech", 64662930);

        almProxy    = ALMProxy(payable(ALM_PROXY));
        controller  = ForeignController(CONTROLLER);
        rateLimits  = RateLimits(RATE_LIMITS);
        spusdtVault = ISparkVaultV2Like(SPUSDT_VAULT);
    }

    function test_postDeployState() external view {
        // ALMProxy/RateLimits roles
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR),   true);
        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    CONTROLLER), true);

        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR),   true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    CONTROLLER), true);

        // Controller roles
        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, EXECUTOR),  true);
        assertEq(controller.hasRole(FREEZER_ROLE,       FREEZER),   true);
        assertEq(controller.hasRole(RELAYER_ROLE,       RELAYER_1), true);
        assertEq(controller.hasRole(RELAYER_ROLE,       RELAYER_2), true);

        assertEq(controller.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(controller.getRoleMemberCount(FREEZER_ROLE),       1);
        assertEq(controller.getRoleMemberCount(RELAYER_ROLE),       2);

        // Spark Savings USDT Vault roles
        assertEq(spusdtVault.hasRole(DEFAULT_ADMIN_ROLE,        EXECUTOR),  true);
        assertEq(spusdtVault.hasRole(spusdtVault.SETTER_ROLE(), SETTER),    true);
        assertEq(spusdtVault.hasRole(spusdtVault.TAKER_ROLE(),  ALM_PROXY), true);

        assertEq(spusdtVault.getRoleMemberCount(spusdtVault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(spusdtVault.getRoleMemberCount(spusdtVault.SETTER_ROLE()),        1);
        assertEq(spusdtVault.getRoleMemberCount(spusdtVault.TAKER_ROLE()),         1);

        // DEPLOYER has no roles on ALMProxy, RateLimits, Controller or Spark Vault.
        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    DEPLOYER), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER), false);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    DEPLOYER), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER), false);

        assertEq(controller.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER), false);
        assertEq(controller.hasRole(FREEZER_ROLE,       DEPLOYER), false);
        assertEq(controller.hasRole(RELAYER_ROLE,       DEPLOYER), false);

        assertEq(spusdtVault.hasRole(DEFAULT_ADMIN_ROLE,        DEPLOYER), false);
        assertEq(spusdtVault.hasRole(spusdtVault.SETTER_ROLE(), DEPLOYER), false);
        assertEq(spusdtVault.hasRole(spusdtVault.TAKER_ROLE(),  DEPLOYER), false);

        IXLayerALMProxyFreezable almProxyFreezable = IXLayerALMProxyFreezable(SETTER);

        assertEq(almProxyFreezable.hasRole(almProxyFreezable.DEFAULT_ADMIN_ROLE(), DEPLOYER), false);
        assertEq(almProxyFreezable.hasRole(almProxyFreezable.ALLOCATOR_ROLE(),     DEPLOYER), false);
        assertEq(almProxyFreezable.hasRole(almProxyFreezable.FREEZER_ROLE(),       DEPLOYER), false);
    }

    function test_vault_config() external view {
        assertEq(spusdtVault.asset(),             USDT);
        assertEq(spusdtVault.name(),              "Spark Savings USDT");
        assertEq(spusdtVault.symbol(),            "spUSDT");
        assertEq(spusdtVault.decimals(),          6);
        assertEq(spusdtVault.maxVsr(),            SIX_PCT_APY);
        assertEq(spusdtVault.depositCap(),        750_000_000e6);
        assertEq(spusdtVault.getImplementation(), SPARK_VAULT_V2_IMPL);
        assertEq(spusdtVault.rho(),               1783422453);
        assertEq(spusdtVault.chi(),               1e27);
        assertEq(spusdtVault.vsr(),               1e27);
        assertEq(spusdtVault.minVsr(),            1e27);

        // Vault is seeded to address(1)
        assertEq(spusdtVault.balanceOf(address(1)), 1e6);
    }

    function test_rateLimits_config() external view {
        bytes32 takeKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), address(spusdtVault));

        IRateLimits.RateLimitData memory rateLimit = rateLimits.getRateLimitData(takeKey);

        assertEq(rateLimit.maxAmount, type(uint256).max);
        assertEq(rateLimit.slope,     0);

        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), USDT, address(spusdtVault));

        rateLimit = rateLimits.getRateLimitData(transferKey);

        assertEq(rateLimit.maxAmount, type(uint256).max);
        assertEq(rateLimit.slope,     0);

        bytes32 layerZeroTransferKey = keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), USDT_OFT, LZ_EID_ETHEREUM));

        rateLimit = rateLimits.getRateLimitData(layerZeroTransferKey);

        assertEq(rateLimit.maxAmount, type(uint256).max);
        assertEq(rateLimit.slope,     0);
    }

    function test_controller_config() external view {
        assertEq(address(controller.proxy()),      ALM_PROXY);
        assertEq(address(controller.rateLimits()), RATE_LIMITS);
        assertEq(address(controller.psm()),        address(0));
        assertEq(address(controller.usdc()),       address(0));
        assertEq(address(controller.cctp()),       address(0));

        // LayerZero Receipient Configuration

        assertEq(controller.layerZeroRecipients(LZ_EID_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
    }

    function test_executor_config() external view {
        assertEq(IExecutor(EXECUTOR).delay(),       0);
        assertEq(IExecutor(EXECUTOR).gracePeriod(), 7 days);

        // Role Assertions

        assertEq(IExecutor(EXECUTOR).hasRole(DEFAULT_ADMIN_ROLE,                    DEPLOYER), false);
        assertEq(IExecutor(EXECUTOR).hasRole(DEFAULT_ADMIN_ROLE,                    EXECUTOR), true);
        assertEq(IExecutor(EXECUTOR).hasRole(IExecutor(EXECUTOR).SUBMISSION_ROLE(), RECEIVER), true);
    }

    function test_receiver_config() external view {
        assertEq(IXLayerReceiver(RECEIVER).l1Authority(), Ethereum.SPARK_PROXY);
        assertEq(IXLayerReceiver(RECEIVER).target(),      EXECUTOR);
    }

    function test_almProxyFreezable_config() external view {
        IXLayerALMProxyFreezable proxy = IXLayerALMProxyFreezable(SETTER);

        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), EXECUTOR), true);

        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(), RELAYER_1), false);
        assertEq(proxy.hasRole(proxy.ALLOCATOR_ROLE(), RELAYER_2), false);
        assertEq(proxy.hasRole(proxy.FREEZER_ROLE(),   FREEZER),   false);
    }

}

contract XLayerE2ETests is Test {

    address internal constant ALM_PROXY    = XLayer.ALM_PROXY;
    address internal constant CONTROLLER   = XLayer.ALM_CONTROLLER;
    address internal constant EXECUTOR     = XLayer.SPARK_EXECUTOR;
    address internal constant RATE_LIMITS  = XLayer.ALM_RATE_LIMITS;
    address internal constant RELAYER_1    = XLayer.ALM_RELAYER_MULTISIG;
    address internal constant SETTER       = XLayer.ALM_PROXY_FREEZABLE;
    address internal constant SPUSDT_VAULT = XLayer.SPARK_VAULT_V2_SPUSDT;

    address internal constant USDT = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;

    address internal USER = makeAddr("user1");

    ALMProxy          internal almProxy;
    ForeignController internal controller;
    RateLimits        internal rateLimits;
    ISparkVaultV2Like internal spusdtVault;

    // > bc -l <<< 'scale=27; e( l(1.01)/(60 * 60 * 24 * 365) )'
    //   1.000000000315522921573372069
    uint256 internal constant ONE_PCT_APY = 1.000000000315522921573372069e27;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 internal constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    function setUp() public {
        vm.createSelectFork("https://rpc.xlayer.tech", 64662930);

        almProxy    = ALMProxy(payable(ALM_PROXY));
        controller  = ForeignController(CONTROLLER);
        rateLimits  = RateLimits(RATE_LIMITS);
        spusdtVault = ISparkVaultV2Like(SPUSDT_VAULT);
    }

    function test_boundary_depositCap() external {
        IERC20 usdt = IERC20(USDT);

        uint256 depositCap = 750_000_000e6;

        deal(USDT, USER, depositCap);

        vm.startPrank(USER);
        SafeERC20.safeIncreaseAllowance(usdt, SPUSDT_VAULT, depositCap);
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        spusdtVault.deposit(depositCap, USER);
        vm.stopPrank();

        deal(USDT, USER, depositCap - 1e6);

        assertEq(usdt.balanceOf(USER),        depositCap - 1e6);
        assertEq(spusdtVault.totalAssets(),   1e6);
        assertEq(spusdtVault.totalSupply(),   1e6);
        assertEq(spusdtVault.balanceOf(USER), 0);

        vm.startPrank(USER);
        SafeERC20.safeIncreaseAllowance(usdt, SPUSDT_VAULT, depositCap - 1e6);
        spusdtVault.deposit(depositCap - 1e6, USER);
        vm.stopPrank();

        assertEq(usdt.balanceOf(USER),        0);
        assertEq(spusdtVault.totalAssets(),   depositCap);
        assertEq(spusdtVault.totalSupply(),   depositCap);
        assertEq(spusdtVault.balanceOf(USER), depositCap - 1e6);
    }

    function test_settingVsr_failsAboveMaxVsrBoundary() external {
        assertEq(spusdtVault.maxVsr(), SIX_PCT_APY);

        vm.expectRevert("SparkVault/vsr-too-high");
        vm.prank(SETTER);
        spusdtVault.setVsr(SIX_PCT_APY + 1);

        vm.prank(SETTER);
        spusdtVault.setVsr(SIX_PCT_APY);
    }

    function _assertUnlimitedRateLimit(
       bytes32 key
    ) internal view {
        IRateLimits.RateLimitData memory rateLimit = rateLimits.getRateLimitData(key);

        assertEq(rateLimit.maxAmount, type(uint256).max);
        assertEq(rateLimit.slope,     0);
    }

}

interface IL1Executor {

    function exec(address target, bytes calldata args) external payable returns (bytes memory out);

}

interface ISparkVaultLike {

    function maxVsr() external view returns (uint256);

    function minVsr() external view returns (uint256);

    function setVsrBounds(uint256 minVsr_, uint256 maxVsr_) external;

}

contract SetVsrBoundsPayload {

    address public immutable vault;
    uint256 public immutable newMinVsr;
    uint256 public immutable newMaxVsr;

    constructor(address _vault, uint256 _newMinVsr, uint256 _newMaxVsr) {
        vault     = _vault;
        newMinVsr = _newMinVsr;
        newMaxVsr = _newMaxVsr;
    }

    function execute() external {
        ISparkVaultLike(vault).setVsrBounds(newMinVsr, newMaxVsr);
    }

}

contract XLayerCrosschainPayload {

    address public immutable targetPayload;
    address public immutable bridgeReceiver;

    constructor(address _targetPayload, address _bridgeReceiver) {
        targetPayload  = _targetPayload;
        bridgeReceiver = _bridgeReceiver;
    }

    function execute() external {
        OptimismForwarder.sendMessageL1toL2(
            OptimismForwarder.L1_CROSS_DOMAIN_XLAYER,
            bridgeReceiver,
            _encodeCrosschainExecutionMessage(),
            1_000_000
        );
    }

    function _encodeCrosschainExecutionMessage() internal view returns (bytes memory) {
        address[] memory targets = new address[](1);
        targets[0] = targetPayload;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        string[] memory signatures = new string[](1);
        signatures[0] = 'execute()';

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        bool[] memory withDelegatecalls = new bool[](1);
        withDelegatecalls[0] = true;

        return abi.encodeWithSelector(
            IExecutor.queue.selector,
            targets,
            values,
            signatures,
            calldatas,
            withDelegatecalls
        );
    }

}

contract XLayerCrosschainE2ETests is Test {

    using DomainHelpers         for Domain;
    using OptimismBridgeTesting for Bridge;

    // Ethereum mainnet governance contracts
    address constant L1_EXECUTOR    = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;
    address constant L1_PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    // XLayer deployed contracts
    address constant EXECUTOR        = XLayer.SPARK_EXECUTOR;
    address constant BRIDGE_RECEIVER = XLayer.SPARK_RECEIVER;
    address constant SPUSDT_VAULT    = XLayer.SPARK_VAULT_V2_SPUSDT;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    // > bc -l <<< 'scale=27; e( l(1.03)/(60 * 60 * 24 * 365) )'
    //   1.000000000936749144827786671
    uint256 constant THREE_PCT_APY = 1.000000000936749144827786671e27;

    Domain mainnet;
    Domain xlayer;
    Bridge bridge;

    function setUp() public {
        mainnet = DomainHelpers.createFork(getChain("mainnet"));

        setChain("xlayer", ChainData({
            name:    "X Layer",
            chainId: 196,
            rpcUrl:  "https://rpc.xlayer.tech"
        }));

        xlayer = DomainHelpers.createFork(getChain("xlayer"));

        mainnet.selectFork();

        bridge = OptimismBridgeTesting.createNativeBridge(mainnet, xlayer);
    }

    function test_crosschainE2E_setVsrBounds() public {
        // Step 1: Deploy the payload on XLayer that will call setVsrBounds when executed

        xlayer.selectFork();

        SetVsrBoundsPayload xlayerPayload = new SetVsrBoundsPayload(
            SPUSDT_VAULT,
            1e27,
            THREE_PCT_APY
        );

        // Step 2: Deploy the crosschain payload on mainnet that sends the message through the bridge

        mainnet.selectFork();

        XLayerCrosschainPayload crosschainPayload = new XLayerCrosschainPayload(
            address(xlayerPayload),
            BRIDGE_RECEIVER
        );

        // Step 3: L1_PAUSE_PROXY triggers L1_EXECUTOR to execute the crosschain payload.

        vm.prank(L1_PAUSE_PROXY);
        IL1Executor(Ethereum.SPARK_PROXY).exec(
            address(crosschainPayload),
            abi.encodeWithSelector(XLayerCrosschainPayload.execute.selector)
        );

        // Step 4: Relay the message to XLayer

        bridge.relayMessagesToDestination(true);

        // Step 5: Advance past the Executor's delay

        skip(0);  // Executor delay is 0

        // Step 6: Execute the queued message.

        assertEq(ISparkVaultLike(SPUSDT_VAULT).minVsr(), 1e27);
        assertEq(ISparkVaultLike(SPUSDT_VAULT).maxVsr(), SIX_PCT_APY);

        IExecutor(EXECUTOR).execute(0);  // Execute the first action in the set.

        assertEq(ISparkVaultLike(SPUSDT_VAULT).minVsr(), 1e27);
        assertEq(ISparkVaultLike(SPUSDT_VAULT).maxVsr(), THREE_PCT_APY);
    }

}
