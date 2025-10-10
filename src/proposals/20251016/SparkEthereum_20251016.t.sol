// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { LZForwarder }           from "xchain-helpers/forwarders/LZForwarder.sol";

import { ChainIdUtils }  from "src/libraries/ChainId.sol";
import { SLLHelpers }    from "src/libraries/SLLHelpers.sol";
import { SparkTestBase } from "src/test-harness/SparkTestBase.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

interface ISparkExecutor {
    function delay() external view returns (uint256);
    function gracePeriod() external view returns (uint256);
}

interface ISparkReceiver {
    function endpoint() external view returns (address);
    function owner() external view returns (address);
    function sourceAuthority() external view returns (bytes32);
    function srcEid() external view returns (uint32);
    function target() external view returns (address);
}

interface IEndpoint {
    function delegates(address) external view returns (address);
}

contract SparkEthereum_20251016Test is SparkTestBase {

    using DomainHelpers for Domain;

    // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
    //   1.000000003022265980097387650
    uint256 internal constant TEN_PCT_APY  = 1.000000003022265980097387650e27;

    address internal constant aAvaUSDC          = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address internal constant AVALANCHE_DEPLOYER = 0x50198eb43ffD192634f741b01E9507A1038d87A0;

    constructor() {
        id = "20251016";
    }

    function setUp() public {
        _setupDomains("2025-10-09T18:19:00Z");

        _deployPayloads();

        chainData[ChainIdUtils.Avalanche()].payload = 0x61Ba24E4735aB76d66EB9771a3888d6c414cd9D7;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0xD1919a5D4d320c07ca55e7936d3C25bE831A9561;
    }

    function test_AVALANCHE_deployConfig() external onChain(ChainIdUtils.Avalanche()) {
        ISparkExecutor executor = ISparkExecutor(Avalanche.SPARK_EXECUTOR);
        ISparkReceiver receiver = ISparkReceiver(Avalanche.SPARK_RECEIVER);

        assertEq(executor.delay(),       0);
        assertEq(executor.gracePeriod(), 7 days);

        assertEq(receiver.owner(),             Avalanche.SPARK_EXECUTOR);
        assertEq(address(receiver.endpoint()), LZForwarder.ENDPOINT_AVALANCHE);
        assertEq(receiver.srcEid(),            LZForwarder.ENDPOINT_ID_ETHEREUM);
        assertEq(receiver.sourceAuthority(),   SLLHelpers.addrToBytes32(Ethereum.SPARK_PROXY));
        assertEq(receiver.target(),            Avalanche.SPARK_EXECUTOR);

        assertEq(
            IEndpoint(LZForwarder.ENDPOINT_AVALANCHE).delegates(Avalanche.SPARK_RECEIVER),
            Avalanche.SPARK_EXECUTOR
        );
    }

    function test_ETHEREUM_sll_disableUnusedProducts() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 jtrsyDeposit = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
            Ethereum.JTRSY_VAULT
        );
        
        bytes32 jtrsyRedeem = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_7540_REDEEM(),
            Ethereum.JTRSY_VAULT
        );

        bytes32 buidlDeposit = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            Ethereum.BUIDLI_DEPOSIT
        );

        bytes32 buidlWithdraw = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.BUIDLI,
            Ethereum.BUIDLI_REDEEM
        );

        assertEq(IERC20(Ethereum.JTRSY).balanceOf(address(ctx.proxy)),  0);
        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(address(ctx.proxy)), 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(jtrsyDeposit),  200_000_000e6);
        assertEq(ctx.rateLimits.getCurrentRateLimit(jtrsyRedeem),   type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlDeposit),  500_000_000e6);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlWithdraw), type(uint256).max);

        _executeAllPayloadsAndBridges();

        assertEq(ctx.rateLimits.getCurrentRateLimit(jtrsyDeposit),  0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(jtrsyRedeem),   0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlDeposit),  0);
        assertEq(ctx.rateLimits.getCurrentRateLimit(buidlWithdraw), 0);

    }

    function test_AVALANCHE_sparkVaultsV2_configureSPUSDC() external onChain(ChainIdUtils.Avalanche()) {
        _testVaultConfiguration({
            asset:      Avalanche.USDC,
            name:       "Spark Savings USDC",
            symbol:     "spUSDC",
            rho:        1759945564,  // Wednesday, October 8, 2025 5:46:04 PM GMT
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

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),   true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Avalanche.ALM_OPS_MULTISIG), false);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Avalanche.ALM_PROXY),        false);

        assertEq(vault.getRoleMemberCount(vault.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()),        0);
        assertEq(vault.getRoleMemberCount(vault.TAKER_ROLE()),         0);

        assertEq(vault.asset(),      asset);
        assertEq(vault.name(),       name);
        assertEq(vault.decimals(),   IERC20Metadata(vault.asset()).decimals());
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

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR),   true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(),        Avalanche.ALM_OPS_MULTISIG), true);
        assertEq(vault.hasRole(vault.TAKER_ROLE(),         Avalanche.ALM_PROXY),        true);

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

    function test_AVALANCHE_sll_onboardAaveUSDC() external onChain(ChainIdUtils.Avalanche()) {
        _testAaveConfiguration(
            aAvaUSDC,
            1_000e6,
            20_000_000e6,
            10_000_000e6 / uint256(1 days)
        );
    }

    // NOTE: Copying _testAaveOnboarding w/o `RateLimits/zero-maxAmount` check.
    function _testAaveConfiguration(
        address aToken,
        uint256 expectedDepositAmount,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        IERC20 underlying = IERC20(IAToken(aToken).UNDERLYING_ASSET_ADDRESS());

        MainnetController controller = MainnetController(ctx.controller);

        // Note: Aave signature is the same for mainnet and foreign
        deal(address(underlying), address(ctx.proxy), expectedDepositAmount);

        bytes32 depositKey  = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_DEPOSIT(),  aToken);
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(controller.LIMIT_AAVE_WITHDRAW(), aToken);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  depositMax,        depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        _testAaveIntegration(E2ETestParams(ctx, aToken, expectedDepositAmount, depositKey, withdrawKey, 10));
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

    function test_ETHEREUM_AVALANCHE_sparkLiquidityLayerE2E() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 avalancheKey = RateLimitHelpers.makeDomainKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE
        );

        bytes32 ethereumKey = RateLimitHelpers.makeDomainKey(
            ForeignController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        _executeAllPayloadsAndBridges();

        IERC20 avaxUsdc = IERC20(Avalanche.USDC);

        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

        // --- Step 1: Mint and bridge 10m USDC to Avalanche ---

        uint256 usdcAmount = 10_000_000e6;

        assertEq(ctx.rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDC_TO_CCTP()), type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(avalancheKey),                           100_000_000e6);

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE);
        vm.stopPrank();

        assertEq(ctx.rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDC_TO_CCTP()), type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(avalancheKey),                           90_000_000e6);

        skip(1 days);  // Refill ratelimit

        assertEq(ctx.rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDC_TO_CCTP()), type(uint256).max);
        assertEq(ctx.rateLimits.getCurrentRateLimit(avalancheKey),                           100_000_000e6);

        chainData[ChainIdUtils.Avalanche()].domain.selectFork();

        ctx = _getSparkLiquidityLayerContext();

        assertEq(avaxUsdc.balanceOf(Avalanche.ALM_PROXY), 0);

        _relayMessageOverBridges();

        assertEq(avaxUsdc.balanceOf(Avalanche.ALM_PROXY), usdcAmount);

        // --- Step 2: Bridge USDC back to mainnet and burn USDS

        assertEq(
            ctx.rateLimits.getCurrentRateLimit(ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_USDC_TO_CCTP()),
            type(uint256).max
        );

        assertEq(ctx.rateLimits.getCurrentRateLimit(ethereumKey), 100_000_000e6);

        vm.prank(Avalanche.ALM_RELAYER);
        ForeignController(Avalanche.ALM_CONTROLLER).transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);

        assertEq(
            ctx.rateLimits.getCurrentRateLimit(ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_USDC_TO_CCTP()),
            type(uint256).max
        );

        assertEq(ctx.rateLimits.getCurrentRateLimit(ethereumKey), 90_000_000e6);

        skip(1 days);  // Refill ratelimits

        assertEq(
            ctx.rateLimits.getCurrentRateLimit(ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_USDC_TO_CCTP()),
            type(uint256).max
        );

        assertEq(ctx.rateLimits.getCurrentRateLimit(ethereumKey), 100_000_000e6);

        assertEq(IERC20(Avalanche.USDC).balanceOf(Avalanche.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        uint256 usdcPrevBalance = IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY);

        _relayMessageOverBridges();

        assertEq(IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY), usdcPrevBalance + usdcAmount);

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();
    }

    function test_ETHEREUM_sll_onboardUSCC() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usccDeposit =  RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            USCC_DEPOSIT
        );

        bytes32 usccWithdraw = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USCC,
            Ethereum.USCC
        );

        _assertRateLimit(usccDeposit,  0, 0);
        _assertRateLimit(usccWithdraw, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usccDeposit, 100_000_000e6, 50_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(usccWithdraw);

        _testSuperstateUsccIntegration(SuperstateUsccE2ETestParams({
            ctx:                 _getSparkLiquidityLayerContext(),
            depositAsset:        Ethereum.USDC,
            depositDestination:  USCC_DEPOSIT,
            depositAmount:       1_000_000e6,
            depositKey:          usccDeposit,
            withdrawAsset:       Ethereum.USCC,
            withdrawDestination: Ethereum.USCC,
            withdrawAmount:      1_000_000e6,
            withdrawKey:         usccWithdraw
        }));
    }

}
