// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC20 }   from "forge-std/interfaces/IERC20.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }     from 'spark-alm-controller/src/MainnetController.sol';
import { ForeignController }     from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }           from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { IALMProxy }             from 'spark-alm-controller/src/interfaces/IALMProxy.sol';
import { RateLimitHelpers }      from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { IPSM3 } from 'spark-psm/src/interfaces/IPSM3.sol';

import { CCTPForwarder }         from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import { SparkTestBase } from 'src/testharness/SparkTestBase.sol';
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

interface DssAutoLineLike {
    function setIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl) external;
    function exec(bytes32 ilk) external;
}

interface IArbitrumTokenBridge {
    function registerToken(address l1Token, address l2Token) external;
    function file(bytes32 what, address data) external;
}

interface IAuthLike {
    function rely(address usr) external;
}

interface IPSMLike {
    function shares(address account) external view returns (uint256);
    function convertToAssetValue(uint256 shares) external view returns (uint256);
}

contract SparkEthereum_20250220Test is SparkTestBase {

    using DomainHelpers for Domain;

    address internal constant AUTO_LINE     = 0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3;
    bytes32 internal constant ALLOCATOR_ILK = "ALLOCATOR-SPARK-A";

    address internal constant DEPLOYER = 0xd1236a6A111879d9862f8374BA15344b6B233Fbd;

    constructor() {
        id = '20250220';
    }

    function setUp() public {
        setupDomains({
            mainnetForkBlock:     21868015,
            baseForkBlock:        26348524,
            gnosisForkBlock:      38037888,
            arbitrumOneForkBlock: 307093406
        });

        deployPayloads();

        chainSpellMetadata[ChainIdUtils.Ethereum()].payload    = 0x9EAa8d72BD731BE8eD71D768a912F6832492071e;
        chainSpellMetadata[ChainIdUtils.Base()].payload        = 0x1e59bBDbd97DDa3E72a65061ecEFEF428F5EFB9a;
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].payload = 0x930e7EFC310F1E62ff3DfC7b60A8FF06d4046887;

        // The following is expected to be in the main spell

        // Mainnet
        vm.startPrank(Ethereum.PAUSE_PROXY);

        // Increase vault to 5b max line, 500m gap
        DssAutoLineLike(AUTO_LINE).setIlk(ALLOCATOR_ILK, 5_000_000_000e45, 500_000_000e45, 24 hours);
        DssAutoLineLike(AUTO_LINE).exec(ALLOCATOR_ILK);

        // Activate the token bridge
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).registerToken(Ethereum.USDS, Arbitrum.USDS);
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Arbitrum.SUSDS);
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).file("escrow", Ethereum.ARBITRUM_ESCROW);

        vm.stopPrank();

        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        // Arbitrum Sky Core spell configuration
        vm.startPrank(Arbitrum.SKY_GOV_RELAY);

        IArbitrumTokenBridge(Arbitrum.TOKEN_BRIDGE).registerToken(Ethereum.USDS, Arbitrum.USDS);
        IArbitrumTokenBridge(Arbitrum.TOKEN_BRIDGE).registerToken(Ethereum.SUSDS, Arbitrum.SUSDS);
        IAuthLike(Arbitrum.USDS).rely(Arbitrum.TOKEN_BRIDGE);
        IAuthLike(Arbitrum.SUSDS).rely(Arbitrum.TOKEN_BRIDGE);

        vm.stopPrank();

        chainSpellMetadata[ChainIdUtils.Ethereum()].domain.selectFork();
    }

    function test_ETHEREUM_weethChanges() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        _assertSupplyCapConfig(Ethereum.WEETH, 200_000, 5_000, 12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WEETH, 500_000, 10_000, 12 hours);
    }

    function test_ETHEREUM_susdsOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _assertERC4626Onboarding({
            vault:                 Ethereum.SUSDS,
            expectedDepositAmount: 50_000_000e18,
            depositMax:            type(uint256).max,
            depositSlope:          0
        });
    }

    function test_BASE_psmRateLimitChanges() public onChain(ChainIdUtils.Base()) {
        bytes32 usdcDepositKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
            Base.USDC
        );
        bytes32 usdcWithdrawKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_WITHDRAW(),
            Base.USDC
        );
        bytes32 usdsDepositKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
            Base.USDS
        );
        bytes32 usdsWithdrawKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_WITHDRAW(),
            Base.USDS
        );
        bytes32 susdsDepositKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
            Base.SUSDS
        );
        bytes32 susdsWithdrawKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_WITHDRAW(),
            Base.SUSDS
        );

        _assertRateLimit(usdcDepositKey,  4_000_000e6,  2_000_000e6  / uint256(1 days));
        _assertRateLimit(usdcWithdrawKey, 7_000_000e6,  2_000_000e6  / uint256(1 days));
        _assertRateLimit(usdsDepositKey,  5_000_000e18, 2_000_000e18 / uint256(1 days));
        _assertRateLimit(susdsDepositKey, 8_000_000e18, 2_000_000e18 / uint256(1 days));

        _assertUnlimitedRateLimit(usdsWithdrawKey);
        _assertUnlimitedRateLimit(susdsWithdrawKey);

        executeAllPayloadsAndBridges();

        _assertRateLimit(usdcDepositKey,  50_000_000e6, 50_000_000e6 / uint256(1 days));
        _assertRateLimit(usdcWithdrawKey, 50_000_000e6, 50_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(usdsDepositKey);
        _assertUnlimitedRateLimit(susdsDepositKey);

        _assertUnlimitedRateLimit(usdsWithdrawKey);
        _assertUnlimitedRateLimit(susdsWithdrawKey);
    }

    function test_ETHEREUM_arbitrumCctpConfiguration() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 arbitrumKey = RateLimitHelpers.makeDomainKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE
        );

        _assertRateLimit(arbitrumKey, 0, 0);
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), bytes32(0));

        executeAllPayloadsAndBridges();

        _assertRateLimit(arbitrumKey, 50_000_000e6, 25_000_000e6 / uint256(1 days));
        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE), bytes32(uint256(uint160(Arbitrum.ALM_PROXY))));
    }

    function test_ARBITRUM_almControllerDeployment() public onChain(ChainIdUtils.ArbitrumOne()) {
        // Copied from the init library, but no harm checking this here
        IALMProxy         almProxy   = IALMProxy(Arbitrum.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(0x0,   Arbitrum.SPARK_EXECUTOR), true, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, Arbitrum.SPARK_EXECUTOR), true, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, Arbitrum.SPARK_EXECUTOR), true, "incorrect-admin-controller");

        assertEq(almProxy.hasRole(0x0,   DEPLOYER), false, "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, DEPLOYER), false, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, DEPLOYER), false, "incorrect-admin-controller");

        assertEq(address(controller.proxy()),      Arbitrum.ALM_PROXY,            "incorrect-almProxy");
        assertEq(address(controller.rateLimits()), Arbitrum.ALM_RATE_LIMITS,      "incorrect-rateLimits");
        assertEq(address(controller.psm()),        Arbitrum.PSM3,                 "incorrect-psm");
        assertEq(address(controller.usdc()),       Arbitrum.USDC,                 "incorrect-usdc");
        assertEq(address(controller.cctp()),       Arbitrum.CCTP_TOKEN_MESSENGER, "incorrect-cctp");

        assertEq(controller.active(), true, "controller-not-active");
    }

    function test_ARBITRUM_psm3Deployment() public onChain(ChainIdUtils.ArbitrumOne()) {
        // Copied from the init library, but no harm checking this here
        IPSM3 psm = IPSM3(Arbitrum.PSM3);

        // Verify that the shares are burned (IE owned by the zero address)
        assertGe(psm.shares(address(0)), 1e18, "psm-totalShares-not-seeded");

        assertEq(address(psm.usdc()),  Arbitrum.USDC,  "psm-incorrect-usdc");
        assertEq(address(psm.usds()),  Arbitrum.USDS,  "psm-incorrect-usds");
        assertEq(address(psm.susds()), Arbitrum.SUSDS, "psm-incorrect-susds");

        assertEq(psm.rateProvider(), Arbitrum.SSR_AUTH_ORACLE, "psm-incorrect-rateProvider");
        assertEq(psm.pocket(),       address(psm),             "psm-incorrect-pocket");
    }

    function test_ARBITRUM_almControllerConfiguration() public onChain(ChainIdUtils.ArbitrumOne()) {
        IALMProxy         almProxy   = IALMProxy(Arbitrum.ALM_PROXY);
        IRateLimits       rateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);

        executeAllPayloadsAndBridges();

        assertEq(almProxy.hasRole(almProxy.CONTROLLER(),     Arbitrum.ALM_CONTROLLER), true, "incorrect-controller-almProxy");
        assertEq(rateLimits.hasRole(rateLimits.CONTROLLER(), Arbitrum.ALM_CONTROLLER), true, "incorrect-controller-rateLimits");
        assertEq(controller.hasRole(controller.FREEZER(),    Arbitrum.ALM_FREEZER),    true, "incorrect-freezer-controller");
        assertEq(controller.hasRole(controller.RELAYER(),    Arbitrum.ALM_RELAYER),    true, "incorrect-relayer-controller");

        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(), Arbitrum.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Arbitrum.USDC),
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Arbitrum.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Arbitrum.USDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_DEPOSIT(),  Arbitrum.SUSDS));
        _assertUnlimitedRateLimit(RateLimitHelpers.makeAssetKey(controller.LIMIT_PSM_WITHDRAW(), Arbitrum.SUSDS));
        _assertUnlimitedRateLimit(controller.LIMIT_USDC_TO_CCTP());
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        assertEq(controller.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
    }

    function test_ETHEREUM_ARBITRUM_sparkLiquidityLayerE2E() public onChain(ChainIdUtils.Ethereum()) {
        // Use mainnet timestamp to make PSM3 sUSDS conversion data realistic
        skip(2 days);  // Skip two days ahead to ensure there is enough rate limit capacity
        uint256 mainnetTimestamp = block.timestamp;

        executeAllPayloadsAndBridges();

        IERC20 arbSUsds = IERC20(Arbitrum.SUSDS);
        IERC20 arbUsdc  = IERC20(Arbitrum.USDC);
        IERC20 arbUsds  = IERC20(Arbitrum.USDS);

        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        ForeignController arbController     = ForeignController(Arbitrum.ALM_CONTROLLER);

        uint256 susdsShares        = IERC4626(Ethereum.SUSDS).convertToShares(100_000_000e18);
        uint256 susdsDepositShares = IERC4626(Ethereum.SUSDS).convertToShares(10_000_000e18);

        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(arbUsds.balanceOf(Arbitrum.ALM_PROXY),  100_000_000e18);
        assertEq(arbUsds.balanceOf(Arbitrum.PSM3),       0);

        assertApproxEqAbs(arbSUsds.balanceOf(Arbitrum.ALM_PROXY), susdsShares, 1);  // $100m
        assertEq(arbSUsds.balanceOf(Arbitrum.PSM3),      0);

        // --- Step 1: Deposit 10m USDS and 10m sUSDS into the PSM ---

        vm.startPrank(Arbitrum.ALM_RELAYER);
        arbController.depositPSM(Arbitrum.USDS,  10_000_000e18);
        arbController.depositPSM(Arbitrum.SUSDS, susdsDepositShares);  // $10m
        vm.stopPrank();

        IPSMLike psm = IPSMLike(Arbitrum.PSM3);

        assertApproxEqAbs(psm.convertToAssetValue(psm.shares(Arbitrum.ALM_PROXY)), 20_000_000e18, 11);

        assertEq(arbUsds.balanceOf(Arbitrum.ALM_PROXY),  90_000_000e18);
        assertEq(arbUsds.balanceOf(Arbitrum.PSM3),       10_000_000e18);

        assertApproxEqAbs(arbSUsds.balanceOf(Arbitrum.ALM_PROXY), susdsShares - susdsDepositShares, 1);  // $90m
        assertApproxEqAbs(arbSUsds.balanceOf(Arbitrum.PSM3),      susdsDepositShares, 1);                // $10m

        chainSpellMetadata[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        // --- Step 2: Mint and bridge 10m USDC to Arbitrum ---

        uint256 usdcAmount = 10_000_000e6;
        uint256 usdcSeed   = 1e6;

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.mintUSDS(usdcAmount * 1e12);
        mainnetController.swapUSDSToUSDC(usdcAmount);
        mainnetController.transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        vm.stopPrank();

        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        assertEq(arbUsdc.balanceOf(Arbitrum.ALM_PROXY), 0);
        assertEq(arbUsdc.balanceOf(Arbitrum.PSM3),      usdcSeed);

        _relayMessageOverBridges();

        assertEq(arbUsdc.balanceOf(Arbitrum.ALM_PROXY), usdcAmount);
        assertEq(arbUsdc.balanceOf(Arbitrum.PSM3),      usdcSeed);

        // --- Step 3: Deposit 10m USDC into PSM3 ---

        vm.startPrank(Arbitrum.ALM_RELAYER);
        arbController.depositPSM(Arbitrum.USDC, usdcAmount);
        vm.stopPrank();

        assertEq(arbUsdc.balanceOf(Arbitrum.ALM_PROXY), 0);
        assertEq(arbUsdc.balanceOf(Arbitrum.PSM3),      usdcSeed + usdcAmount);

        // --- Step 4: Withdraw all assets from PSM3 ---

        vm.startPrank(Arbitrum.ALM_RELAYER);
        arbController.withdrawPSM(Arbitrum.USDS,  10_000_000e18);
        arbController.withdrawPSM(Arbitrum.SUSDS, susdsDepositShares);  // $10m
        arbController.withdrawPSM(Arbitrum.USDC,  usdcAmount);
        vm.stopPrank();

        assertEq(arbUsds.balanceOf(Arbitrum.PSM3),  0);
        assertEq(arbSUsds.balanceOf(Arbitrum.PSM3), 0);

        assertApproxEqAbs(arbUsdc.balanceOf(Arbitrum.PSM3), usdcSeed, 1);

        assertEq(arbUsds.balanceOf(Arbitrum.ALM_PROXY),  100_000_000e18);
        assertApproxEqAbs(arbSUsds.balanceOf(Arbitrum.ALM_PROXY), susdsShares, 1);

        usdcAmount -= 1;  // Rounding
        assertEq(arbUsdc.balanceOf(Arbitrum.ALM_PROXY), usdcAmount);

        // --- Step 5: Bridge USDC back to mainnet and burn USDS

        vm.startPrank(Arbitrum.ALM_RELAYER);
        ForeignController(Arbitrum.ALM_CONTROLLER).transferUSDCToCCTP(usdcAmount, CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM);
        vm.stopPrank();

        assertEq(IERC20(Arbitrum.USDC).balanceOf(Arbitrum.ALM_PROXY), 0);

        chainSpellMetadata[ChainIdUtils.Ethereum()].domain.selectFork();
        vm.warp(mainnetTimestamp);

        uint256 usdcPrevBalance = IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY);

        _relayMessageOverBridges();

        assertEq(IERC20(Ethereum.USDC).balanceOf(Ethereum.ALM_PROXY), usdcPrevBalance + usdcAmount);

        vm.startPrank(Ethereum.ALM_RELAYER);
        mainnetController.swapUSDCToUSDS(usdcAmount);
        mainnetController.burnUSDS(usdcAmount * 1e12);
        vm.stopPrank();
    }

    function test_ETHEREUM_ARBITRUM_BASE_usdsAndSUsdsDistributions() public {
        chainSpellMetadata[ChainIdUtils.Base()].domain.selectFork();

        uint256 startingBaseSUsdsShares = IERC4626(Base.SUSDS).balanceOf(Base.ALM_PROXY);

        executeAllPayloadsAndBridges();

        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        uint256 arbSUsdsShares = IERC4626(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY);

        assertEq(IERC20(Arbitrum.USDS).balanceOf(Arbitrum.ALM_PROXY), 100_000_000e18);

        chainSpellMetadata[ChainIdUtils.Base()].domain.selectFork();

        // Cache value of new sUSDS balance transferred on base after spell execution
        uint256 newBaseSUsdsShares = IERC4626(Base.SUSDS).balanceOf(Base.ALM_PROXY) - startingBaseSUsdsShares;

        chainSpellMetadata[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),  0);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.SPARK_PROXY), 0);

        IERC4626 susds = IERC4626(Ethereum.SUSDS);

        assertEq(susds.convertToAssets(arbSUsdsShares),     100_000_000e18);
        // Rounding on conversion
        assertEq(susds.convertToAssets(newBaseSUsdsShares), 100_000_000e18 - 1);
    }

}
