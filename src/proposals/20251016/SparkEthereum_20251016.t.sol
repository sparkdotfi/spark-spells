// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ChainIdUtils }  from "src/libraries/ChainId.sol";
import { SLLHelpers }    from "src/libraries/SLLHelpers.sol";
import { SparkTestBase } from "src/test-harness/SparkTestBase.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20251002Test is SparkTestBase {

    uint256 internal constant TEN_PCT_APY  = 1.000000003022265980097387650e27;

    address internal constant aAvaxUSDC          = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address internal constant AVALANCHE_DEPLOYER = 0x50198eb43ffD192634f741b01E9507A1038d87A0;

    constructor() {
        id = "20251016";
    }

    function setUp() public {
        _setupDomains("2025-10-08T18:12:00Z");

        _deployPayloads();

        // chainData[ChainIdUtils.Avalanche()].payload = 0xD1919a5D4d320c07ca55e7936d3C25bE831A9561;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0xD1919a5D4d320c07ca55e7936d3C25bE831A9561;
    }

    function test_ETHEREUM_sll_disableUnusedProducts() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 jstryDeposit = RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
                Ethereum.JTRSY_VAULT
            );

        bytes32 buidlDeposit = RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                Ethereum.BUIDLI_DEPOSIT
            );

        assertEq(ctx.rateLimits.getCurrentRateLimit(jstryDeposit), 2e14);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlDeposit), 5e14);

        _executeAllPayloadsAndBridges();

        assertEq(ctx.rateLimits.getCurrentRateLimit(jstryDeposit), 0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlDeposit), 0);
    }

    function test_AVALANCHE_sparkVaultsV2_configureSPUSDC() external onChain(ChainIdUtils.Avalanche()) {
        _testVaultConfiguration({
            asset:      Avalanche.USDC,
            name:       "Spark Savings USDC",
            symbol:     "spUSDC",
            rho:        1759945564,
            vault_:     Avalanche.SPARK_VAULT_V2_SPUSDC,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 50_000_000e6,
            amount:     1_000_000e6
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

        ISparkVaultV2Like vault = ISparkVaultV2Like(vault_);

        bytes32 takeKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_SPARK_VAULT_TAKE(),
            vault_
        );
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            vault.asset(),
            vault_
        );

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),  true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_OPS_MULTISIG), false);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Avalanche.ALM_PROXY),       false);

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

        _executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),  true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Ethereum.ALM_OPS_MULTISIG), true);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Avalanche.ALM_PROXY),       true);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        1);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         1);

        assertEq(vault.minVsr(),     minVsr);
        assertEq(vault.maxVsr(),     maxVsr);
        assertEq(vault.depositCap(), depositCap);

        assertEq(ctx.rateLimits.getCurrentRateLimit(takeKey),     type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(transferKey), type(uint256).max);

        _testSetterIntegration(vault, minVsr, maxVsr);

        uint256 initialChi = vault.nowChi();

        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        vault.setVsr(TEN_PCT_APY);

        skip(1 days);

        assertGt(vault.nowChi(), initialChi);

        _testSparkVaultV2Integration(SparkVaultV2E2ETestParams({
            ctx:             ctx,
            vault:           vault_,
            takeKey:         takeKey,
            transferKey:     transferKey,
            takeAmount:      amount,
            transferAmount:  amount,
            userVaultAmount: amount,
            tolerance:       10
        }));
    }

    function _testSetterIntegration(ISparkVaultV2Like vault, uint256 minVsr, uint256 maxVsr) internal {
        vm.startPrank(Ethereum.ALM_OPS_MULTISIG);

        vm.expectRevert("SparkVault/vsr-too-low");
        vault.setVsr(minVsr - 1);

        vault.setVsr(minVsr);

        vm.expectRevert("SparkVault/vsr-too-high");
        vault.setVsr(maxVsr + 1);

        vault.setVsr(maxVsr);

        vm.stopPrank();
    }

    function test_ETHEREUM_sll_onboardSparklendETH() external onChain(ChainIdUtils.Avalanche()) {
        _testAaveOnboarding(
            aAvaxUSDC,
            1_000e6,
            20_000_000e6,
            10_000_000e6 / uint256(1 days)
        );
    }

    function test_ETHEREUM_avalancheCctpConfiguration() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 avalancheKey = RateLimitHelpers.makeDomainKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE
        );

        _assertRateLimit(avalancheKey, 0, 0);
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE), bytes32(0));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(avalancheKey, 100_000_000e6, 50_000_000e6 / uint256(1 days));
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE), SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY));
    }

    function test_AVALANCHE_almControllerDeployment() public onChain(ChainIdUtils.Avalanche()) {
        // Copied from the init library, but no harm checking this here
        IALMProxy         almProxy   = IALMProxy(Avalanche.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Avalanche.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Avalanche.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(0x0,   Avalanche.SPARK_EXECUTOR), true, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, Avalanche.SPARK_EXECUTOR), true, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, Avalanche.SPARK_EXECUTOR), true, "incorrect-admin-controller");

        assertEq(almProxy.hasRole(0x0,   AVALANCHE_DEPLOYER), false, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, AVALANCHE_DEPLOYER), false, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, AVALANCHE_DEPLOYER), false, "incorrect-admin-controller");

        assertEq(address(controller.proxy()),      Avalanche.ALM_PROXY,            "incorrect-almProxy");
        assertEq(address(controller.rateLimits()), Avalanche.ALM_RATE_LIMITS,      "incorrect-rateLimits");
        assertEq(address(controller.psm()),        address(0),                     "incorrect-psm");
        assertEq(address(controller.usdc()),       Avalanche.USDC,                 "incorrect-usdc");
        assertEq(address(controller.cctp()),       Avalanche.CCTP_TOKEN_MESSENGER, "incorrect-cctp");
    }

    function test_AVALANCHE_almControllerConfiguration() public onChain(ChainIdUtils.Avalanche()) {
        IALMProxy         almProxy   = IALMProxy(Avalanche.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Avalanche.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Avalanche.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Avalanche.ALM_CONTROLLER), false, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Avalanche.ALM_CONTROLLER), false, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Avalanche.ALM_FREEZER),    false, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Avalanche.ALM_RELAYER),    false, "incorrect-relayer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Avalanche.ALM_RELAYER2),   false, "incorrect-relayer-controller");

        _assertRateLimit(controller.LIMIT_USDC_TO_CCTP(), 0, 0);
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(address(0)));

        _executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Avalanche.ALM_CONTROLLER), true, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Avalanche.ALM_CONTROLLER), true, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Avalanche.ALM_FREEZER),    true, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Avalanche.ALM_RELAYER),    true, "incorrect-relayer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Avalanche.ALM_RELAYER2),   true, "incorrect-relayer-controller");

        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            100_000_000e6,
            50_000_000e6 / uint256(1 days)
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY));
    }

    // function test_ETHEREUM_OPTIMISM_sparkLiquidityLayerE2E() public onChain(ChainIdUtils.Ethereum()) {
    //     // Use mainnet timestamp to make PSM3 sUSDS conversion data realistic
    //     skip(2 days);  // Skip two days ahead to ensure there is enough rate limit capacity
    //     uint256 mainnetTimestamp = block.timestamp;

    //     executeAllPayloadsAndBridges();

    //     IERC20 opSUsds = IERC20(Optimism.SUSDS);
    //     IERC20 opUsdc  = IERC20(Optimism.USDC);
    //     IERC20 opUsds  = IERC20(Optimism.USDS);

    //     MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
    //     ForeignController opController      = ForeignController(Optimism.ALM_CONTROLLER);

    //     uint256 susdsShares        = IERC4626(Ethereum.SUSDS).convertToShares(100_000_000e18);
    //     uint256 susdsDepositShares = IERC4626(Ethereum.SUSDS).convertToShares(10_000_000e18);

    //     chainData[ChainIdUtils.Optimism()].domain.selectFork();
    //     vm.warp(mainnetTimestamp);

    //     assertEq(opUsds.balanceOf(Optimism.ALM_PROXY), 100_000_000e18);
    //     assertEq(opUsds.balanceOf(Optimism.PSM3),      0);

    //     assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares, 1);  // $100m
        
    //     assertEq(opSUsds.balanceOf(Optimism.PSM3), 0);

    //     // --- Step 1: Deposit 10m USDS and 10m sUSDS into the PSM ---

    //     vm.startPrank(Optimism.ALM_RELAYER);
    //     opController.depositPSM(Optimism.USDS,  10_000_000e18);
    //     opController.depositPSM(Optimism.SUSDS, susdsDepositShares);  // $10m
    //     vm.stopPrank();

    //     IPSMLike psm = IPSMLike(Optimism.PSM3);

    //     assertApproxEqAbs(psm.convertToAssetValue(psm.shares(Optimism.ALM_PROXY)), 20_000_000e18, 31);

    //     assertEq(opUsds.balanceOf(Optimism.ALM_PROXY), 90_000_000e18);
    //     assertEq(opUsds.balanceOf(Optimism.PSM3),      10_000_000e18);

    //     assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares - susdsDepositShares, 1);  // $90m
    //     assertApproxEqAbs(opSUsds.balanceOf(Optimism.PSM3),      susdsDepositShares,               1);  // $10m

    //     chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    //     vm.warp(mainnetTimestamp);

    //     // --- Step 2: Mint and bridge 10m USDC to Optimism ---

    //     uint256 usdcAmount = 10_000_000e6;
    //     uint256 usdcSeed   = 1e6;

    //     vm.startPrank(Ethereum.ALM_RELAYER);
    //     mainnetController.mintUSDS(usdcAmount * 1e12);
    //     mainnetController.swapUSDSToUSDC(usdcAmount);
    //     mainnetController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
    //     vm.stopPrank();

    //     chainData[ChainIdUtils.Optimism()].domain.selectFork();
    //     vm.warp(mainnetTimestamp);

    //     assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), 0);
    //     assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed);

    //     _relayMessageOverBridges();

    //     assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), usdcAmount);
    //     assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed);

    //     // --- Step 3: Deposit 10m USDC into PSM3 ---

    //     vm.startPrank(Optimism.ALM_RELAYER);
    //     opController.depositPSM(Optimism.USDC, usdcAmount);
    //     vm.stopPrank();

    //     assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), 0);
    //     assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed + usdcAmount);

    //     // --- Step 4: Withdraw all assets from PSM3 ---

    //     vm.startPrank(Optimism.ALM_RELAYER);
    //     opController.withdrawPSM(Optimism.USDS,  10_000_000e18);
    //     opController.withdrawPSM(Optimism.SUSDS, susdsDepositShares);  // $10m
    //     opController.withdrawPSM(Optimism.USDC,  usdcAmount);
    //     vm.stopPrank();

    //     assertEq(opUsds.balanceOf(Optimism.PSM3),  0);
    //     assertEq(opSUsds.balanceOf(Optimism.PSM3), 0);

    //     assertApproxEqAbs(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed,   1);
    //     assertApproxEqAbs(opUsdc.balanceOf(Optimism.ALM_PROXY), usdcAmount, 1);

    //     assertEq(opUsds.balanceOf(Optimism.ALM_PROXY),  100_000_000e18);
    //     assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares, 1);

    //     usdcAmount -= 1;  // Rounding

    //     // --- Step 5: Bridge USDC back to mainnet and burn USDS

    //     vm.startPrank(Optimism.ALM_RELAYER);
    //     ForeignController(Optimism.ALM_CONTROLLER).transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
    //     vm.stopPrank();

    //     assertEq(IERC20(Optimism.USDC).balanceOf(Optimism.ALM_PROXY), 0);

    //     chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    //     vm.warp(mainnetTimestamp);

    //     uint256 usdcPrevBalance = IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY);

    //     _relayMessageOverBridges();

    //     assertEq(IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY), usdcPrevBalance + usdcAmount);

    //     vm.startPrank(Ethereum.ALM_RELAYER);
    //     mainnetController.swapUSDCToUSDS(usdcAmount);
    //     mainnetController.burnUSDS(usdcAmount * 1e12);
    //     vm.stopPrank();
    // }

}
