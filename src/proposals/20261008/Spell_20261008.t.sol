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

interface ISparkVaultV2Like {

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
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
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

    function test_XLAYER_sll_cctp_e2e_roundTrip() external onChain(ChainIdUtils.XLayer()) {
        Bridge storage bridge = chainData[ChainIdUtils.XLayer()].bridges[2];

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        // Step 0: Set VSR on spUSDC.
        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(spusdc),
            abi.encodeCall(spusdc.setVsr, (1000000001121484774769253326))
        );

        // Step 1: User deposits USDC into spUSDC on X Layer.

        deal(address(xlayerUsdc), user, 1_000_000e6);

        assertEq(xlayerUsdc.balanceOf(user),            1_000_000e6);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1e6);

        assertEq(spusdc.totalAssets(),   1e6);
        assertEq(spusdc.totalSupply(),   1e6);
        assertEq(spusdc.balanceOf(user), 0);

        vm.startPrank(user);
        xlayerUsdc.approve(address(spusdc), 1_000_000e6);
        spusdc.deposit(1_000_000e6, user);
        vm.stopPrank();

        assertEq(xlayerUsdc.balanceOf(user),            0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1_000_000e6 + 1e6);

        assertEq(spusdc.totalAssets(),   1_000_000e6 + 1e6);
        assertEq(spusdc.totalSupply(),   1_000_000e6 + 1e6);
        assertEq(spusdc.balanceOf(user), 1_000_000e6);

        // Step 2: Relayer takes the USDC out of spUSDC into the ALMProxy on X Layer.

        bytes32 takeKey = xlayerController.sparkVault_getTakeRateLimitKey(address(spusdc));

        assertEq(xlayerRateLimits.getCurrentRateLimit(takeKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.sparkVault_take, (address(spusdc), 1_000_000e6))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(takeKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             1e6);
        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 1_000_000e6);

        // Step 3: Relayer bridges the USDC to Ethereum with CCTP V2 (burn on X Layer).

        bytes32 xlayerCctpKey       = xlayerController.cctp_toCCTPRateLimitKey();
        bytes32 xlayerCctpDomainKey = xlayerController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpKey),       type(uint256).max);
        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpDomainKey), 10_000_000e6);

        uint256 xlayerUsdcSupply = xlayerUsdc.totalSupply();

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.cctp_transfer, (1_000_000e6, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_ETHEREUM, 0))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpKey),       type(uint256).max);
        assertEq(xlayerRateLimits.getCurrentRateLimit(xlayerCctpDomainKey), 9_000_000e6);

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

        bytes32 mainnetCctpKey       = mainnetController.cctp_toCCTPRateLimitKey();
        bytes32 mainnetCctpDomainKey = mainnetController.cctp_getToDomainRateLimitKey(CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER);

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpKey),       type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpDomainKey), 10_000_000e6);

        vm.prank(Ethereum.ALM_RELAYER_MULTISIG);
        mainnetAgent.call(
            address(mainnetController),
            abi.encodeCall(mainnetController.cctp_transfer, (usdcWithYield, CCTPv2Forwarder.DOMAIN_ID_CIRCLE_XLAYER, 0))
        );

        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpKey),       type(uint256).max);
        assertEq(mainnetRateLimits.getCurrentRateLimit(mainnetCctpDomainKey), 10_000_000e6 - usdcWithYield);

        assertEq(usdc.balanceOf(Ethereum.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(usdc.totalSupply(),                            mainnetUsdcSupply + 1_000_000e6 - usdcWithYield);

        // Step 9: Relay the message to X Layer.

        chainData[ChainIdUtils.XLayer()].domain.selectFork();

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);

        bridge.relayMessagesToDestination(true);

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), usdcWithYield);
        assertEq(xlayerUsdc.totalSupply(),                          xlayerUsdcSupply - 1_000_000e6 + usdcWithYield);

        // Step 10: Relayer transfers the USDC, yield included, back into spUSDC.

        bytes32 transferKey = xlayerController.transferAsset_getTransferRateLimitKey(address(xlayerUsdc), address(spusdc));

        assertEq(xlayerRateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        vm.prank(XLayer.ALM_RELAYER_MULTISIG);
        xlayerAgent.call(
            address(xlayerController),
            abi.encodeCall(xlayerController.transferAsset_transfer, (address(xlayerUsdc), address(spusdc), usdcWithYield))
        );

        assertEq(xlayerRateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        assertEq(xlayerUsdc.balanceOf(XLayer.SPUSDC_PAU_ALM_PROXY), 0);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)),             usdcWithYield + 1e6);

        // Step 11: User redeems.
        assertEq(spusdc.totalAssets(), usdcWithYield + 1e6 + 96);  // 96 atoms accrued from yield on seeded balance

        vm.prank(user);
        spusdc.redeem(1_000_000e6, user, user);

        assertEq(xlayerUsdc.balanceOf(user),            usdcWithYield);
        assertEq(xlayerUsdc.balanceOf(address(spusdc)), 1e6);

        assertEq(spusdc.totalAssets(),   1e6 + 96);
        assertEq(spusdc.totalSupply(),   1e6);
        assertEq(spusdc.balanceOf(user), 0);
    }

}

contract SparkEthereum_20261008_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

}

contract SparkEthereum_20261008_SpellTests is SpellTests {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 972_485e18;

    constructor() {
        _spellId   = 20261008;
        _blockDate = 1789710827;  // 2026-09-18 05:53:47 UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xdE40689816DA168b0A56f8F22CBD7FfCFA403E6B;
    }

}
