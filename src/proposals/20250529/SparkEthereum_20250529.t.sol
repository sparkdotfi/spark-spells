// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC20 }   from "forge-std/interfaces/IERC20.sol";

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { ForeignController }     from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }           from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { IALMProxy }             from 'spark-alm-controller/src/interfaces/IALMProxy.sol';
import { MainnetController }     from 'spark-alm-controller/src/MainnetController.sol';
import { RateLimitHelpers }      from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { IPSM3 } from 'spark-psm/src/interfaces/IPSM3.sol';

import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

import { InterestStrategyValues, ReserveConfig }                   from '../../test-harness/ProtocolV3TestBase.sol';
import { ICustomIRM, IRateSource, ITargetBaseIRM, ITargetKinkIRM } from '../../test-harness/SparkEthereumTests.sol';
import { SparkLendContext }                                        from '../../test-harness/SparklendTests.sol';
import { SparkTestBase }                                           from '../../test-harness/SparkTestBase.sol';

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

interface IAuthLike {
    function rely(address usr) external;
}

interface IOptimismTokenBridge {
    function registerToken(address l1Token, address l2Token) external;
    function file(bytes32 what, address data) external;
}

interface IPSMLike {
    function shares(address account) external view returns (uint256);
    function convertToAssetValue(uint256 shares) external view returns (uint256);
}

contract SparkEthereum_20250529Test is SparkTestBase {

    using DomainHelpers for Domain;

    address internal constant CBBTC_USDC_ORACLE = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;
    
    address internal constant DAI_USDS_OLD_IRM  = 0x7729E1CE24d7c4A82e76b4A2c118E328C35E6566;
    address internal constant DAI_USDS_NEW_IRM  = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;
    
    address internal constant DEPLOYER          = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;

    address internal constant PT_SUSDS_14AUG2025            = 0xFfEc096c087C13Cc268497B89A613cACE4DF9A48;
    address internal constant PT_SUSDS_14AUG2025_PRICE_FEED = 0xD7c8498fF648CBB9E79d6470cf7F639e696D27A5;

    constructor() {
        id = "20250529";
    }

    function setUp() public {
        setupDomains("2025-05-22T15:04:00Z");

        deployPayloads();

        chainData[ChainIdUtils.Base()].payload     = 0x08AbA599Bd82e4De7b78516077cDF1CB24788CC1;
        chainData[ChainIdUtils.Ethereum()].payload = 0x86036CE5d2f792367C0AA43164e688d13c5A60A8;
        chainData[ChainIdUtils.Optimism()].payload = 0x08AbA599Bd82e4De7b78516077cDF1CB24788CC1;
        chainData[ChainIdUtils.Unichain()].payload = 0xbF5a7CfaF47fd1Ad75c9C613b1d4C196eE1b4EeF;

        // Mainnet
        vm.startPrank(Ethereum.PAUSE_PROXY);

        // Activate the token bridge for Optimism
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).registerToken(Ethereum.USDS,  Optimism.USDS);
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Optimism.SUSDS);
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).file("escrow", Ethereum.OPTIMISM_ESCROW);

        // Activate the token bridge for Unichain
        IOptimismTokenBridge(Ethereum.UNICHAIN_TOKEN_BRIDGE).registerToken(Ethereum.USDS, Unichain.USDS);
        IOptimismTokenBridge(Ethereum.UNICHAIN_TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Unichain.SUSDS);
        IOptimismTokenBridge(Ethereum.UNICHAIN_TOKEN_BRIDGE).file("escrow", Ethereum.UNICHAIN_ESCROW);

        vm.stopPrank();

        chainData[ChainIdUtils.Optimism()].domain.selectFork();

        // Optimism Sky Core spell configuration
        vm.startPrank(Optimism.SKY_GOV_RELAY);

        IOptimismTokenBridge(Optimism.TOKEN_BRIDGE).registerToken(Ethereum.USDS, Optimism.USDS);
        IOptimismTokenBridge(Optimism.TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Optimism.SUSDS);
        IAuthLike(Optimism.USDS).rely(Optimism.TOKEN_BRIDGE);
        IAuthLike(Optimism.SUSDS).rely(Optimism.TOKEN_BRIDGE);

        vm.stopPrank();

        chainData[ChainIdUtils.Unichain()].domain.selectFork();

        // Unichain Sky Core spell configuration
        vm.startPrank(Unichain.SKY_GOV_RELAY);

        IOptimismTokenBridge(Unichain.TOKEN_BRIDGE).registerToken(Ethereum.USDS, Unichain.USDS);
        IOptimismTokenBridge(Unichain.TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Unichain.SUSDS);
        IAuthLike(Unichain.USDS).rely(Unichain.TOKEN_BRIDGE);
        IAuthLike(Unichain.SUSDS).rely(Unichain.TOKEN_BRIDGE);

        vm.stopPrank();

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    function test_ETHEREUM_optimismCctpConfiguration() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 optimismKey = RateLimitHelpers.makeDomainKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM
        );

        _assertRateLimit(optimismKey, 0, 0);
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM), bytes32(0));

        executeAllPayloadsAndBridges();

        _assertRateLimit(optimismKey, 50_000_000e6, 25_000_000e6 / uint256(1 days));
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM), bytes32(uint256(uint160(Optimism.ALM_PROXY))));
    }

    function test_OPTIMISM_almControllerDeployment() public onChain(ChainIdUtils.Optimism()) {
        // Copied from the init library, but no harm checking this here
        IALMProxy         almProxy   = IALMProxy(Optimism.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Optimism.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Optimism.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(0x0,   Optimism.SPARK_EXECUTOR), true, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, Optimism.SPARK_EXECUTOR), true, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, Optimism.SPARK_EXECUTOR), true, "incorrect-admin-controller");

        assertEq(almProxy.hasRole(0x0,   DEPLOYER), false, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, DEPLOYER), false, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, DEPLOYER), false, "incorrect-admin-controller");

        assertEq(address(controller.proxy()),      Optimism.ALM_PROXY,            "incorrect-almProxy");
        assertEq(address(controller.rateLimits()), Optimism.ALM_RATE_LIMITS,      "incorrect-rateLimits");
        assertEq(address(controller.psm()),        Optimism.PSM3,                 "incorrect-psm");
        assertEq(address(controller.usdc()),       Optimism.USDC,                 "incorrect-usdc");
        assertEq(address(controller.cctp()),       Optimism.CCTP_TOKEN_MESSENGER, "incorrect-cctp");
    }

    function test_OPTIMISM_psm3Deployment() public onChain(ChainIdUtils.Optimism()) {
        // Copied from the init library, but no harm checking this here
        IPSM3 psm = IPSM3(Optimism.PSM3);

        // Verify that the shares are burned (IE owned by the zero address)
        assertGe(psm.shares(address(0)), 1e18, "psm-totalShares-not-seeded");

        assertEq(address(psm.usdc()),  Optimism.USDC,  "psm-incorrect-usdc");
        assertEq(address(psm.usds()),  Optimism.USDS,  "psm-incorrect-usds");
        assertEq(address(psm.susds()), Optimism.SUSDS, "psm-incorrect-susds");

        assertEq(psm.rateProvider(), Optimism.SSR_AUTH_ORACLE, "psm-incorrect-rateProvider");
        assertEq(psm.pocket(),       address(psm),             "psm-incorrect-pocket");
    }

    function test_OPTIMISM_almControllerConfiguration() public onChain(ChainIdUtils.Optimism()) {
        IALMProxy         almProxy   = IALMProxy(Optimism.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Optimism.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Optimism.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Optimism.ALM_CONTROLLER), false, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Optimism.ALM_CONTROLLER), false, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Optimism.ALM_FREEZER),    false, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Optimism.ALM_RELAYER),    false, "incorrect-relayer-controller");

        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Optimism.USDC),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.USDC),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Optimism.USDS),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.USDS),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Optimism.SUSDS), 0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.SUSDS), 0, 0);
        _assertRateLimit(controller.LIMIT_USDC_TO_CCTP(), 0, 0);
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(address(0)))));

        executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Optimism.ALM_CONTROLLER), true, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Optimism.ALM_CONTROLLER), true, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Optimism.ALM_FREEZER),    true, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Optimism.ALM_RELAYER),    true, "incorrect-relayer-controller");

        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(), Optimism.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Optimism.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Optimism.SUSDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Optimism.SUSDS));
        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
    }

    function test_ETHEREUM_OPTIMISM_sparkLiquidityLayerE2E() public onChain(ChainIdUtils.Ethereum()) {
        // Use mainnet timestamp to make PSM3 sUSDS conversion data realistic
        skip(2 days);  // Skip two days ahead to ensure there is enough rate limit capacity
        uint256 mainnetTimestamp = block.timestamp;

        executeAllPayloadsAndBridges();

        IERC20 opSUsds = IERC20(Optimism.SUSDS);
        IERC20 opUsdc  = IERC20(Optimism.USDC);
        IERC20 opUsds  = IERC20(Optimism.USDS);

        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        ForeignController opController      = ForeignController(Optimism.ALM_CONTROLLER);

        uint256 susdsShares        = IERC4626(Ethereum.SUSDS).convertToShares(100_000_000e18);
        uint256 susdsDepositShares = IERC4626(Ethereum.SUSDS).convertToShares(10_000_000e18);

        chainData[ChainIdUtils.Optimism()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(opUsds.balanceOf(Optimism.ALM_PROXY), 100_000_000e18);
        assertEq(opUsds.balanceOf(Optimism.PSM3),      0);

        assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares, 1);  // $100m
        
        assertEq(opSUsds.balanceOf(Optimism.PSM3), 0);

        // --- Step 1: Deposit 10m USDS and 10m sUSDS into the PSM ---

        vm.startPrank(Optimism.ALM_RELAYER);
        opController.depositPSM(Optimism.USDS,  10_000_000e18);
        opController.depositPSM(Optimism.SUSDS, susdsDepositShares);  // $10m
        vm.stopPrank();

        IPSMLike psm = IPSMLike(Optimism.PSM3);

        assertApproxEqAbs(psm.convertToAssetValue(psm.shares(Optimism.ALM_PROXY)), 20_000_000e18, 27);

        assertEq(opUsds.balanceOf(Optimism.ALM_PROXY), 90_000_000e18);
        assertEq(opUsds.balanceOf(Optimism.PSM3),      10_000_000e18);

        assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares - susdsDepositShares, 1);  // $90m
        assertApproxEqAbs(opSUsds.balanceOf(Optimism.PSM3),      susdsDepositShares,               1);  // $10m

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        // --- Step 2: Mint and bridge 10m USDC to Optimism ---

        uint256 usdcAmount = 10_000_000e6;
        uint256 usdcSeed   = 1e6;

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        vm.stopPrank();

        chainData[ChainIdUtils.Optimism()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), 0);
        assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed);

        _relayMessageOverBridges();

        assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), usdcAmount);
        assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed);

        // --- Step 3: Deposit 10m USDC into PSM3 ---

        vm.startPrank(Optimism.ALM_RELAYER);
        opController.depositPSM(Optimism.USDC, usdcAmount);
        vm.stopPrank();

        assertEq(opUsdc.balanceOf(Optimism.ALM_PROXY), 0);
        assertEq(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed + usdcAmount);

        // --- Step 4: Withdraw all assets from PSM3 ---

        vm.startPrank(Optimism.ALM_RELAYER);
        opController.withdrawPSM(Optimism.USDS,  10_000_000e18);
        opController.withdrawPSM(Optimism.SUSDS, susdsDepositShares);  // $10m
        opController.withdrawPSM(Optimism.USDC,  usdcAmount);
        vm.stopPrank();

        assertEq(opUsds.balanceOf(Optimism.PSM3),  0);
        assertEq(opSUsds.balanceOf(Optimism.PSM3), 0);

        assertApproxEqAbs(opUsdc.balanceOf(Optimism.PSM3),      usdcSeed,   1);
        assertApproxEqAbs(opUsdc.balanceOf(Optimism.ALM_PROXY), usdcAmount, 1);

        assertEq(opUsds.balanceOf(Optimism.ALM_PROXY),  100_000_000e18);
        assertApproxEqAbs(opSUsds.balanceOf(Optimism.ALM_PROXY), susdsShares, 1);

        usdcAmount -= 1;  // Rounding

        // --- Step 5: Bridge USDC back to mainnet and burn USDS

        vm.startPrank(Optimism.ALM_RELAYER);
        ForeignController(Optimism.ALM_CONTROLLER).transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        vm.stopPrank();

        assertEq(IERC20(Optimism.USDC).balanceOf(Optimism.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        uint256 usdcPrevBalance = IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY);

        _relayMessageOverBridges();

        assertEq(IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY), usdcPrevBalance + usdcAmount);

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();
    }

    function test_ETHEREUM_unichainCctpConfiguration() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 unichainKey = RateLimitHelpers.makeDomainKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN
        );

        _assertRateLimit(unichainKey, 0, 0);
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN), bytes32(0));

        executeAllPayloadsAndBridges();

        _assertRateLimit(unichainKey, 50_000_000e6, 25_000_000e6 / uint256(1 days));
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN), bytes32(uint256(uint160(Unichain.ALM_PROXY))));
    }

    function test_UNICHAIN_almControllerDeployment() public onChain(ChainIdUtils.Unichain()) {
        // Copied from the init library, but no harm checking this here
        IALMProxy         almProxy   = IALMProxy(Unichain.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Unichain.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Unichain.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(0x0,   Unichain.SPARK_EXECUTOR), true, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, Unichain.SPARK_EXECUTOR), true, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, Unichain.SPARK_EXECUTOR), true, "incorrect-admin-controller");

        assertEq(almProxy.hasRole(0x0,   DEPLOYER), false, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, DEPLOYER), false, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, DEPLOYER), false, "incorrect-admin-controller");

        assertEq(address(controller.proxy()),      Unichain.ALM_PROXY,            "incorrect-almProxy");
        assertEq(address(controller.rateLimits()), Unichain.ALM_RATE_LIMITS,      "incorrect-rateLimits");
        assertEq(address(controller.psm()),        Unichain.PSM3,                 "incorrect-psm");
        assertEq(address(controller.usdc()),       Unichain.USDC,                 "incorrect-usdc");
        assertEq(address(controller.cctp()),       Unichain.CCTP_TOKEN_MESSENGER, "incorrect-cctp");

    }

    function test_UNICHAIN_psm3Deployment() public onChain(ChainIdUtils.Unichain()) {
        // Copied from the init library, but no harm checking this here
        IPSM3 psm = IPSM3(Unichain.PSM3);

        // Verify that the shares are burned (IE owned by the zero address)
        assertGe(psm.shares(address(0)), 1e18, "psm-totalShares-not-seeded");

        assertEq(address(psm.usdc()),  Unichain.USDC,  "psm-incorrect-usdc");
        assertEq(address(psm.usds()),  Unichain.USDS,  "psm-incorrect-usds");
        assertEq(address(psm.susds()), Unichain.SUSDS, "psm-incorrect-susds");

        assertEq(psm.rateProvider(), Unichain.SSR_AUTH_ORACLE, "psm-incorrect-rateProvider");
        assertEq(psm.pocket(),       address(psm),             "psm-incorrect-pocket");
    }

    function test_UNICHAIN_almControllerConfiguration() public onChain(ChainIdUtils.Unichain()) {
        IALMProxy         almProxy   = IALMProxy(Unichain.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Unichain.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Unichain.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Unichain.ALM_CONTROLLER), false, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Unichain.ALM_CONTROLLER), false, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Unichain.ALM_FREEZER),    false, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Unichain.ALM_RELAYER),    false, "incorrect-relayer-controller");

        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Unichain.USDC),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.USDC),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Unichain.USDS),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.USDS),  0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Unichain.SUSDS), 0, 0);
        _assertRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.SUSDS), 0, 0);
        _assertRateLimit(controller.LIMIT_USDC_TO_CCTP(), 0, 0);
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(address(0)))));

        executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Unichain.ALM_CONTROLLER), true, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Unichain.ALM_CONTROLLER), true, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Unichain.ALM_FREEZER),    true, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Unichain.ALM_RELAYER),    true, "incorrect-relayer-controller");

        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(), Unichain.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Unichain.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Unichain.SUSDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Unichain.SUSDS));
        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
    }

    function test_ETHEREUM_UNICHAIN_sparkLiquidityLayerE2E() public onChain(ChainIdUtils.Ethereum()) {
        // Use mainnet timestamp to make PSM3 sUSDS conversion data realistic
        skip(2 days);  // Skip two days ahead to ensure there is enough rate limit capacity
        uint256 mainnetTimestamp = block.timestamp;

        executeAllPayloadsAndBridges();

        IERC20 uniSUsds = IERC20(Unichain.SUSDS);
        IERC20 uniUsdc  = IERC20(Unichain.USDC);
        IERC20 uniUsds  = IERC20(Unichain.USDS);

        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        ForeignController uniController     = ForeignController(Unichain.ALM_CONTROLLER);

        uint256 susdsShares        = IERC4626(Ethereum.SUSDS).convertToShares(100_000_000e18);
        uint256 susdsDepositShares = IERC4626(Ethereum.SUSDS).convertToShares(10_000_000e18);

        chainData[ChainIdUtils.Unichain()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(uniUsds.balanceOf(Unichain.ALM_PROXY), 100_000_000e18);
        assertEq(uniUsds.balanceOf(Unichain.PSM3),      0);

        assertApproxEqAbs(uniSUsds.balanceOf(Unichain.ALM_PROXY), susdsShares, 1);  // $100m
        
        assertEq(uniSUsds.balanceOf(Unichain.PSM3), 0);

        // --- Step 1: Deposit 10m USDS and 10m sUSDS into the PSM ---

        vm.startPrank(Unichain.ALM_RELAYER);
        uniController.depositPSM(Unichain.USDS,  10_000_000e18);
        uniController.depositPSM(Unichain.SUSDS, susdsDepositShares);  // $10m
        vm.stopPrank();

        IPSMLike psm = IPSMLike(Unichain.PSM3);

        assertApproxEqAbs(psm.convertToAssetValue(psm.shares(Unichain.ALM_PROXY)), 20_000_000e18, 27);

        assertEq(uniUsds.balanceOf(Unichain.ALM_PROXY), 90_000_000e18);
        assertEq(uniUsds.balanceOf(Unichain.PSM3),      10_000_000e18);

        assertApproxEqAbs(uniSUsds.balanceOf(Unichain.ALM_PROXY), susdsShares - susdsDepositShares, 1);  // $90m
        assertApproxEqAbs(uniSUsds.balanceOf(Unichain.PSM3),      susdsDepositShares,               1);  // $10m

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        // --- Step 2: Mint and bridge 10m USDC to Unichain ---

        uint256 usdcAmount = 10_000_000e6;
        uint256 usdcSeed   = 1e6;

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);
        vm.stopPrank();

        chainData[ChainIdUtils.Unichain()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(uniUsdc.balanceOf(Unichain.ALM_PROXY), 0);
        assertEq(uniUsdc.balanceOf(Unichain.PSM3),      usdcSeed);

        _relayMessageOverBridges();

        assertEq(uniUsdc.balanceOf(Unichain.ALM_PROXY), usdcAmount);
        assertEq(uniUsdc.balanceOf(Unichain.PSM3),      usdcSeed);

        // --- Step 3: Deposit 10m USDC into PSM3 ---

        vm.startPrank(Unichain.ALM_RELAYER);
        uniController.depositPSM(Unichain.USDC, usdcAmount);
        vm.stopPrank();

        assertEq(uniUsdc.balanceOf(Unichain.ALM_PROXY), 0);
        assertEq(uniUsdc.balanceOf(Unichain.PSM3),      usdcSeed + usdcAmount);

        // --- Step 4: Withdraw all assets from PSM3 ---

        vm.startPrank(Unichain.ALM_RELAYER);
        uniController.withdrawPSM(Unichain.USDS,  10_000_000e18);
        uniController.withdrawPSM(Unichain.SUSDS, susdsDepositShares);  // $10m
        uniController.withdrawPSM(Unichain.USDC,  usdcAmount);
        vm.stopPrank();

        assertEq(uniUsds.balanceOf(Unichain.PSM3),  0);
        assertEq(uniSUsds.balanceOf(Unichain.PSM3), 0);

        assertApproxEqAbs(uniUsdc.balanceOf(Unichain.PSM3),      usdcSeed,   1);
        assertApproxEqAbs(uniUsdc.balanceOf(Unichain.ALM_PROXY), usdcAmount, 1);

        assertEq(uniUsds.balanceOf(Unichain.ALM_PROXY),  100_000_000e18);
        assertApproxEqAbs(uniSUsds.balanceOf(Unichain.ALM_PROXY), susdsShares, 1);

        usdcAmount -= 1;  // Rounding

        // --- Step 5: Bridge USDC back to mainnet and burn USDS

        vm.startPrank(Unichain.ALM_RELAYER);
        ForeignController(Unichain.ALM_CONTROLLER).transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        vm.stopPrank();

        assertEq(IERC20(Unichain.USDC).balanceOf(Unichain.ALM_PROXY), 0);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        uint256 usdcPrevBalance = IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY);

        _relayMessageOverBridges();

        assertEq(IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY), usdcPrevBalance + usdcAmount);

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();
    }

    function test_ETHEREUM_sparkLend_daiIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : DAI_USDS_OLD_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.0075e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.8e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : DAI_USDS_NEW_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0075e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetBaseToKinkIRMUpdate("DAI", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdsIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : DAI_USDS_OLD_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.0075e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.8e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : DAI_USDS_NEW_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.0075e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.8e27
        });
        _testRateTargetBaseToKinkIRMUpdate("USDS", oldParams, newParams);
    }

    function test_BASE_morpho_CBBTCSupplyCap() public onChain(ChainIdUtils.Base()) {
        _testMorphoCapUpdate({
            vault: Base.MORPHO_VAULT_SUSDC,
            config: MarketParams({
                loanToken       : Base.USDC,
                collateralToken : Base.CBBTC,
                oracle          : CBBTC_USDC_ORACLE,
                irm             : Base.MORPHO_DEFAULT_IRM,
                lltv            : 0.86e18
            }),
            currentCap: 500_000_000e6,
            newCap:     1_000_000_000e6
        });
    }

    function test_ETHEREUM_WBTCChanges() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);
        ReserveConfig memory config = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(config.liquidationThreshold, 45_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);
        
        config.liquidationThreshold = 40_00;

        _validateReserveConfig(config, allConfigsAfter);
    }

    function test_ETHEREUM_sllCoreRateLimitIncrease() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdsMintKey       = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_MINT();
        bytes32 swapUSDSToUSDCKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_TO_USDC();
        bytes32 ethenaMintKey     = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDE_MINT();
        bytes32 ethenaBurnKey     = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDE_BURN();
        bytes32 susdeCooldownKey  = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_SUSDE_COOLDOWN();
        
        bytes32 susdeDepositKey   = RateLimitHelpers.makeAssetKey(MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(), Ethereum.SUSDE);
        bytes32 susdeWithdrawKey  = RateLimitHelpers.makeAssetKey(MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(), Ethereum.SUSDE);
        
        _assertRateLimit(usdsMintKey,       200_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapUSDSToUSDCKey, 200_000_000e6,  200_000_000e6 / uint256(1 days));
        _assertRateLimit(ethenaMintKey,     50_000_000e6,   50_000_000e6 / uint256(1 days));
        _assertRateLimit(ethenaBurnKey,     100_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(susdeDepositKey,   100_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(susdeCooldownKey,  500_000_000e18, 250_000_000e18 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertRateLimit(usdsMintKey,       500_000_000e18, 500_000_000e18 / uint256(1 days));
        _assertRateLimit(swapUSDSToUSDCKey, 500_000_000e6,  300_000_000e6 / uint256(1 days));
        _assertRateLimit(ethenaMintKey,     250_000_000e6,  100_000_000e6 / uint256(1 days));
        _assertRateLimit(ethenaBurnKey,     500_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(susdeDepositKey,   250_000_000e18, 100_000_000e18 / uint256(1 days));
        
        _assertUnlimitedRateLimit(susdeCooldownKey);
        _assertUnlimitedRateLimit(susdeWithdrawKey);
    }

    function _testRateTargetBaseToKinkIRMUpdate(
        string                  memory symbol,
        RateTargetBaseIRMParams memory oldParams,
        RateTargetKinkIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRM(newParams.irm).RATE_SOURCE(), ICustomIRM(oldParams.irm).RATE_SOURCE());

        uint256 ssrRate = uint256(IRateSource(ICustomIRM(newParams.irm).RATE_SOURCE()).getAPR());

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider             : address(ctx.poolAddressesProvider),
                optimalUsageRatio             : oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio : 0,
                baseStableBorrowRate          : oldParams.variableRateSlope1,
                stableRateSlope1              : 0,
                stableRateSlope2              : 0,
                baseVariableBorrowRate        : ssrRate + oldParams.baseRateSpread,
                variableRateSlope1            : oldParams.variableRateSlope1,
                variableRateSlope2            : oldParams.variableRateSlope2
            })
        );

        assertEq(ITargetBaseIRM(configBefore.interestRateStrategy).getBaseVariableBorrowRateSpread(), oldParams.baseRateSpread);

        executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider             : address(ctx.poolAddressesProvider),
                optimalUsageRatio             : newParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio : 0,
                baseStableBorrowRate          : ssrRate + uint256(newParams.variableRateSlope1Spread),
                stableRateSlope1              : 0,
                stableRateSlope2              : 0,
                baseVariableBorrowRate        : newParams.baseRate,
                variableRateSlope1            : ssrRate + uint256(newParams.variableRateSlope1Spread),
                variableRateSlope2            : newParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRM(configAfter.interestRateStrategy).getVariableRateSlope1Spread()), uint256(newParams.variableRateSlope1Spread));
    }

    function test_ETHEREUM_OPTIMISM_UNICHAIN_usdsAndSUsdsDistributions() public {
        chainData[ChainIdUtils.Optimism()].domain.selectFork();

        assertEq(IERC4626(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY), 0);
        assertEq(IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY),    0);

        chainData[ChainIdUtils.Unichain()].domain.selectFork();

        assertEq(IERC4626(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY), 0);
        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY),    0);

        executeAllPayloadsAndBridges();

        chainData[ChainIdUtils.Optimism()].domain.selectFork();

        uint256 opSUsdsShares = IERC4626(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        assertEq(IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY), 100_000_000e18);

        chainData[ChainIdUtils.Unichain()].domain.selectFork();

        uint256 unichainSUsdsShares = IERC4626(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY);

        assertEq(IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY), 100_000_000e18);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),  0);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.SPARK_PROXY), 0);

        IERC4626 susds = IERC4626(Ethereum.SUSDS);

        // Rounding on conversion
        assertEq(susds.convertToAssets(opSUsdsShares),       100_000_000e18 - 1);
        assertEq(susds.convertToAssets(unichainSUsdsShares), 100_000_000e18 - 1);
    }

    function test_ETHEREUM_morpho_PTSUSDE14AUG2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDS_14AUG2025,
                oracle:          PT_SUSDS_14AUG2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            currentCap: 0,
            newCap:     500_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:           PT_SUSDS_14AUG2025,
            oracle:       PT_SUSDS_14AUG2025_PRICE_FEED,
            discount:     0.15e18,
            currentPrice: 0.966148454147640792e36
        });
    }

}
