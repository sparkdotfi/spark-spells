// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils }  from 'src/libraries/ChainId.sol';
import { SparkTestBase } from 'src/test-harness/SparkTestBase.sol';

import { SparkVault } from "lib/spark-vaults-v2/src/SparkVault.sol";

interface INetworkRegistry {
    function isEntity(address entity_) external view returns (bool);
}

interface IOperatorRegistry {
    function isEntity(address entity_) external view returns (bool);
}

interface IOptInService {
    function isOptedIn(address who, address where) external view returns (bool);
}

interface INetworkMiddlewareService {
    function middleware(address network) external view returns (address);
    function setMiddleware(address middleware) external;
}

interface INetworkRestakeDelegator {
    function hasRole(bytes32 role, address account) external returns (bool);
    function hook() external returns (address);
    function networkLimit(bytes32 subnetwork) external returns (uint256);
    function operatorNetworkShares(bytes32 subnetwork, address operator) external view returns (uint256);
    function OPERATOR_NETWORK_SHARES_SET_ROLE() external returns (bytes32);
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);
}

interface ISparkVaultV2 {
    function asset() external view returns (address);
    function chi() external view returns (uint192);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function depositCap() external view returns (uint256);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function minVsr() external view returns (uint256);
    function maxVsr() external view returns (uint256);
    function name() external view returns (string memory);
    function nowChi() external view returns (uint256);
    function rho() external view returns (uint64);
    function SETTER_ROLE() external view returns (bytes32);
    function setVsr(uint256 newVsr) external;
    function symbol() external view returns (string memory);
    function TAKER_ROLE() external view returns (bytes32);
    function vsr() external view returns (uint256);
}

interface IStakedSPK {
    function activeStake() external view returns (uint256);

    function deposit(
        address onBehalfOf,
        uint256 amount
    ) external returns (uint256 depositedAmount, uint256 mintedShares);
}

interface IVetoSlasher {
    function executeSlash(uint256 slashIndex, bytes calldata hints) external returns (uint256 slashedAmount);

    function NETWORK_MIDDLEWARE_SERVICE() external returns (address);

    function requestSlash(
        bytes32 subnetwork,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes calldata hints
    ) external returns (uint256 slashIndex);

    function slashableStake(
        bytes32 subnetwork,
        address operator,
        uint48 captureTimestamp,
        bytes memory hints
    ) external view returns (uint256);
}

contract SparkEthereum_20251002Test is SparkTestBase {

    uint256 internal constant FIVE_PCT_APY = 1.000000001547125957863212448e27;
    uint256 internal constant TEN_PCT_APY  = 1.000000003022265980097387650e27;

    address internal constant GROVE_SUBDAO_PROXY = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;
    address internal constant PYUSD              = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant SYRUP              = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;

    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;

    uint256 internal constant AMOUNT_TO_GROVE            = 1_031_866e18;
    uint256 internal constant AMOUNT_TO_SPARK_FOUNDATION = 1_100_000e18;

    // Symbiotic addresses
    address constant NETWORK_DELEGATOR = 0x2C5bF9E8e16716A410644d6b4979d74c1951952d;
    address constant NETWORK_REGISTRY  = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
    address constant OPERATOR_REGISTRY = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;
    address constant RESET_HOOK        = 0xC3B87BbE976f5Bfe4Dc4992ae4e22263Df15ccBE;
    address constant STAKED_SPK_VAULT  = 0xc6132FAF04627c8d05d6E759FAbB331Ef2D8F8fD;
    address constant VETO_SLASHER      = 0x4BaaEB2Bf1DC32a2Fb2DaA4E7140efb2B5f8cAb7;

    error NotNetworkMiddleware();

    constructor() {
        id = "20251002";
    }

    function setUp() public {
        setupDomains("2025-09-24T13:31:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x7B28F4Bdd7208fe80916EBC58611Eb72Fb6A09Ed;
    }

    function test_ETHEREUM_sparkMorphoVault_increasePTUSDE27NovSupplyCap() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_USDS,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDE_27NOV2025,
                oracle:          PT_USDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 500_000_000e18,
            newCap:     1_000_000_000e18
        });
    }

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() public onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 2500, 250, 12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 500, 12 hours);
    }

    function test_ETHEREUM_sparkLend_reserveFactor() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory usdc = _findReserveConfigBySymbol(allConfigsBefore, 'USDC');
        ReserveConfig memory usdt = _findReserveConfigBySymbol(allConfigsBefore, 'USDT');

        assertEq(usdc.reserveFactor, 10_00);
        assertEq(usdt.reserveFactor, 10_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        usdc.reserveFactor = 1_00;
        usdt.reserveFactor = 1_00;

        _validateReserveConfig(usdc, allConfigsAfter);
        _validateReserveConfig(usdt, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  446_756_954.903747305236702025e18);
        assertEq(spUsdsBalanceBefore, 533_866_585.285220791565254216e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spDaiBalanceBefore + 9_402.155256707448903492e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   spUsdsBalanceBefore + 12_633.767612739349578615e18);
    }

    function test_debug() public onChain(ChainIdUtils.Ethereum()) {
        vm.etch(Ethereum.SPARK_VAULT_V2_IMPL, address(new SparkVault()).code);
        executeAllPayloadsAndBridges();
    }

    function test_ETHEREUM_sparkVaultsV2_configureSPUSDC() public onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.USDC,
            name:       "Spark Savings USDC",
            symbol:     "spUSDC",
            rho:        1758286595,
            vault_:     Ethereum.SPARK_VAULT_V2_SPUSDC,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 50_000_000e6,
            amount:     1_000_000e6
        });
    }

    function test_ETHEREUM_sparkVaultsV2_configureSPUSDT() public onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.USDT,
            name:       "Spark Savings USDT",
            symbol:     "spUSDT",
            rho:        1758288359,
            vault_:     Ethereum.SPARK_VAULT_V2_SPUSDT,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 50_000_000e6,
            amount:     1_000_000e6
        });
    }

    function test_ETHEREUM_sparkVaultsV2_configureSPETH() public onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.WETH,
            name:       "Spark Savings ETH",
            symbol:     "spETH",
            rho:        1758289979,
            vault_:     Ethereum.SPARK_VAULT_V2_SPETH,
            minVsr:     1e27,
            maxVsr:     FIVE_PCT_APY,
            depositCap: 10_000e18,
            amount:     1_000e18
        });
    }

    function _testVaultConfiguration(
        address asset,
        string  memory name,
        string  memory symbol,
        uint64  rho,
        address vault_,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositCap,
        uint256 amount
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ISparkVaultV2 vault = ISparkVaultV2(vault_);

        bytes32 takeKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_SPARK_VAULT_TAKE(),
            vault_
        );
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            vault.asset(),
            vault_
        );

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),      true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_OPS_MULTISIG), false);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Ethereum.ALM_PROXY),        false);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        0);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         0);

        assertEq(vault.asset(),      asset);
        assertEq(vault.name(),       name);
        assertEq(vault.symbol(),     symbol);
        assertEq(vault.rho(),        rho);
        assertEq(vault.chi(),        uint192(1e27));
        assertEq(vault.vsr(),        1e27);
        assertEq(vault.minVsr(),     1e27);
        assertEq(vault.maxVsr(),     1e27);
        assertEq(vault.depositCap(), 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), 0);

        executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),      true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_OPS_MULTISIG), true);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Ethereum.ALM_PROXY),        true);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        1);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         1);

        assertEq(vault.minVsr(),     minVsr);
        assertEq(vault.maxVsr(),     maxVsr);
        assertEq(vault.depositCap(), depositCap);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        uint256 initialChi = vault.nowChi();

        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        vault.setVsr(FIVE_PCT_APY);

        skip(1 days);

        assertGt(vault.nowChi(), initialChi);

        _testVaultTakeIntegration({
            asset:      vault.asset(),
            vault:      vault_,
            rateLimit:  type(uint256).max,
            takeAmount: amount
        });

        _testTransferAssetIntegration({
            token:             vault.asset(),
            destination:       vault_,
            controller_:       Ethereum.ALM_CONTROLLER,
            expectedRateLimit: type(uint256).max,
            transferAmount:    amount
        });
    }

    function test_ETHEREUM_sll_onboardSparklendETH() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding(
            Ethereum.WETH_SPTOKEN,
            1_000e18,
            50_000e18,
            10_000e18 / uint256(1 days)
        );
    }

    function test_ETHEREUM_claimAaveRewards() public onChain(ChainIdUtils.Ethereum()) {
        uint256 aUSDSBalanceBefore = IERC20(Ethereum.ATOKEN_CORE_USDS).balanceOf(Ethereum.ALM_PROXY);

        assertEq(aUSDSBalanceBefore, 0.003722350232385604e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.ATOKEN_CORE_USDS).balanceOf(Ethereum.ALM_PROXY), 243_167.547362527277079545e18);
    }

    function test_ETHEREUM_sll_addTransferAssetRateLimitForSYRUP() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            SYRUP,
            Ethereum.ALM_OPS_MULTISIG
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 200_000e18, 200_000e18 / uint256(1 days));

        _testTransferAssetIntegration(
            SYRUP,
            Ethereum.ALM_OPS_MULTISIG,
            Ethereum.ALM_CONTROLLER,
            200_000e18,
            200_000e18
        );
    }

    function test_ETHEREUM_usdsTransfers() public onChain(ChainIdUtils.Ethereum()) {
        uint256 foundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION);
        uint256 groveUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(GROVE_SUBDAO_PROXY);
        uint256 sparkUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(sparkUsdsBalanceBefore,      32_163_684.945801365846236778e18);
        assertEq(foundationUsdsBalanceBefore, 292_388.004e18);
        assertEq(groveUsdsBalanceBefore,      30_654e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),      sparkUsdsBalanceBefore - AMOUNT_TO_GROVE - AMOUNT_TO_SPARK_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION), foundationUsdsBalanceBefore + AMOUNT_TO_SPARK_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(GROVE_SUBDAO_PROXY),        groveUsdsBalanceBefore + AMOUNT_TO_GROVE);
    }

    function test_ETHEREUM_symbioticConfiguration() public onChain(ChainIdUtils.Ethereum()) {
        address NETWORK   = Ethereum.SPARK_PROXY;
        address OWNER     = Ethereum.SPARK_PROXY;
        address OPERATOR  = Ethereum.SPARK_PROXY;

        INetworkRestakeDelegator delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);
        INetworkRegistry networkRegistry   = INetworkRegistry(NETWORK_REGISTRY);
        IOperatorRegistry operatorRegistry = IOperatorRegistry(OPERATOR_REGISTRY);

        bytes32 subnetwork = bytes32(uint256(uint160(NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        assertEq(networkRegistry.isEntity(Ethereum.SPARK_PROXY), false);

        assertEq(delegator.networkLimit(subnetwork),                    0);
        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 0);
        assertEq(delegator.hook(),                                      address(0));

        assertEq(
            delegator.hasRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), RESET_HOOK),
            false
        );

        assertEq(operatorRegistry.isEntity(Ethereum.SPARK_PROXY), false);

        assertEq(
            IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).isOptedIn(Ethereum.SPARK_PROXY, NETWORK),
            false
        );
        assertEq(
            IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).isOptedIn(Ethereum.SPARK_PROXY, STAKED_SPK_VAULT),
            false
        );

        executeAllPayloadsAndBridges();

        assertEq(networkRegistry.isEntity(Ethereum.SPARK_PROXY), true);

        assertEq(delegator.networkLimit(subnetwork),                    type(uint256).max);
        assertEq(delegator.operatorNetworkShares(subnetwork, OPERATOR), 1e18);
        assertEq(delegator.hook(),                                      RESET_HOOK);

        assertEq(
            delegator.hasRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), RESET_HOOK),
            true
        );

        assertEq(operatorRegistry.isEntity(Ethereum.SPARK_PROXY), true);

        assertEq(
            IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).isOptedIn(Ethereum.SPARK_PROXY, NETWORK),
            true
        );
        assertEq(
            IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).isOptedIn(Ethereum.SPARK_PROXY, STAKED_SPK_VAULT),
            true
        );

        _testSlashingIsDisabledUnlessMiddlewareIsSet();
    }

    function _testSlashingIsDisabledUnlessMiddlewareIsSet() public {
        address alice      = makeAddr("alice");
        address bob        = makeAddr("bob");
        address NETWORK    = Ethereum.SPARK_PROXY;
        address OPERATOR   = Ethereum.SPARK_PROXY;
        address MIDDLEWARE = makeAddr("middleware");

        IERC20 spk           = IERC20(Ethereum.SPK);
        IStakedSPK stSpk     = IStakedSPK(Ethereum.STSPK);
        IVetoSlasher slasher = IVetoSlasher(VETO_SLASHER);

        INetworkMiddlewareService middlewareService = INetworkMiddlewareService(slasher.NETWORK_MIDDLEWARE_SERVICE());

        bytes32 subnetwork = bytes32(uint256(uint160(NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        uint256 ACTIVE_STAKE = stSpk.activeStake();

        // --- Step 1: Deposit 10m SPK to stSPK as two users

        deal(address(spk), alice, 6_000_000e18);
        deal(address(spk), bob,   4_000_000e18);

        vm.startPrank(alice);
        spk.approve(address(stSpk), 6_000_000e18);
        stSpk.deposit(alice, 6_000_000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        spk.approve(address(stSpk), 4_000_000e18);
        stSpk.deposit(bob, 4_000_000e18);
        vm.stopPrank();

        uint48 depositTimestamp = uint48(block.timestamp);

        skip(24 hours);  // Warp 24 hours

        // --- Step 2: Request a slash of all staked SPK (show that network limit is hit)

        uint48 captureTimestamp = uint48(block.timestamp - 1 seconds);  // Can't capture current timestamp and above

        // Demonstrate that the slashable stake increases with new deposits
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp - 1, ""), 0);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, depositTimestamp,     ""), ACTIVE_STAKE + 10_000_000e18);
        assertEq(slasher.slashableStake(subnetwork, OPERATOR, captureTimestamp,     ""), ACTIVE_STAKE + 10_000_000e18);

        // There is no middleware, so slashing is impossible
        assertEq(middlewareService.middleware(NETWORK), address(0));

        vm.prank(NETWORK);
        vm.expectRevert(NotNetworkMiddleware.selector);
        slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        // Show how it would work if middleware was set
        vm.prank(NETWORK);
        middlewareService.setMiddleware(MIDDLEWARE);

        // Its now possible
        assertEq(middlewareService.middleware(NETWORK), MIDDLEWARE);

        vm.prank(MIDDLEWARE);
        uint256 slashIndex = slasher.requestSlash(subnetwork, OPERATOR, 10_000_000e18, captureTimestamp, "");

        skip(3 days + 1);

        vm.prank(MIDDLEWARE);
        slasher.executeSlash(slashIndex, "");
    }

}
