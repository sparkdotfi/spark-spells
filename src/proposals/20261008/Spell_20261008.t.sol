// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { Bridge, BridgeType }  from "lib/xchain-helpers/src/testing/Bridge.sol";
import { CCTPv2BridgeTesting } from "lib/xchain-helpers/src/testing/bridges/CCTPv2BridgeTesting.sol";
import { CCTPv2Forwarder }     from "lib/xchain-helpers/src/forwarders/CCTPv2Forwarder.sol";
import { DomainHelpers }       from "lib/xchain-helpers/src/testing/Domain.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

interface IAdministeredAgentLike {

    function call(address target, bytes memory data) external;

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

}

interface ISavingsIntentsLike {

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

interface IERC4626Like {

    function balanceOf(address account) external view returns (uint256);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

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
    using CCTPv2BridgeTesting for Bridge;

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
        _blockDate = 1790264363;  // Sep-24-2026 03:39:23 PM +UTC
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

    // XLayer tests

    function test_XLAYER_sll_cctp_e2e_roundTrip() external onChain(ChainIdUtils.XLayer()) {
        Bridge storage bridge = chainData[ChainIdUtils.XLayer()].bridges[2];

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        // Step 1: User deposits USDC into spUSDC on X Layer.

        deal(address(xlayerUsdc), user, 1_000_000e6);

        uint256 spUsdcBalanceBefore = xlayerUsdc.balanceOf(address(spusdc));
        uint256 spUsdcSupplyBefore  = spusdc.totalSupply();
        uint256 spUsdcAssetsBefore  = spusdc.totalAssets();

        assertEq(spUsdcBalanceBefore, 6.699_882e6);
        assertEq(spUsdcSupplyBefore,  6.699_823e6);
        assertEq(spUsdcAssetsBefore,  6.701_006e6);

        assertEq(xlayerUsdc.balanceOf(user), 1_000_000e6);
        assertEq(spusdc.balanceOf(user),     0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        uint256 userShares = spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(userShares,             999_823.392_959e6);
        assertEq(spusdc.balanceOf(user), userShares);
        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 1_000_000e6 - 1); // Rounding
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
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM)),
            10_000_000e6
        );

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM)),
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
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER)),
            10_000_000e6
        );

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER)),
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
        assertEq(spusdc.totalAssets(), spUsdcAssetsBefore + usdcWithYield + 649);  // 649 atoms accrued from yield on seeded balance

        vm.prank(user);
        spusdc.redeem(userShares, user, user);

        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 649);
        assertEq(spusdc.totalSupply(),   spUsdcSupplyBefore);
        assertEq(spusdc.balanceOf(user), 0);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield - 1); // Rounding
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), spUsdcBalanceBefore + 1); // Rounding
    }

}

contract SparkEthereum_20261008_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1790264363;  // Sep-24-2026 03:39:23 PM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

}

contract SparkEthereum_20261008_SpellTests is SpellTests {

    using DomainHelpers       for *;
    using CCTPv2BridgeTesting for Bridge;

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
        _blockDate = 1790264363;  // Sep-24-2026 03:39:23 PM +UTC
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

    }

    function test_XLAYER_savingsIntents_spUSDC_updateVaultConfig() external onChain(ChainIdUtils.XLayer()) {

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

        assertEq(spUsdcBalanceBefore, 6.699_882e6);
        assertEq(spUsdcSupplyBefore,  6.699_823e6);
        assertEq(spUsdcAssetsBefore,  6.701_006e6);

        assertEq(xlayerUsdc.balanceOf(user), 1_000_000e6);
        assertEq(spusdc.balanceOf(user),     0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        uint256 userShares = spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(userShares,             999_823.392_959e6);
        assertEq(spusdc.balanceOf(user), userShares);
        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 1_000_000e6 - 1); // Rounding
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
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM)),
            10_000_000e6
        );

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            xlayerRateLimits.getCurrentRateLimit(xlayerController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM)),
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
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER)),
            10_000_000e6
        );

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_toCCTPRateLimitKey()), type(uint256).max);

        assertEq(
            mainnetRateLimits.getCurrentRateLimit(mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER)),
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

        assertEq(spusdc.totalAssets(), spUsdcAssetsBefore + usdcWithYield + 649);  // 649 atoms accrued from yield on seeded balance

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(savingsVaultIntents),
            abi.encodeCall(savingsVaultIntents.fulfill, (user, address(spusdc), requestId))
        );

        _assertWithdrawRequests(user, address(spusdc), 0, 0, address(0), 0); // Request is fulfilled

        assertEq(savingsVaultIntents.vaultRequestCount(address(spusdc)), 1);

        assertEq(spusdc.totalAssets(),   spUsdcAssetsBefore + 649);
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
