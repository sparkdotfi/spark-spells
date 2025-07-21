// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams, Id } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Base }     from 'spark-address-registry/Base.sol';

import { ForeignController } from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }       from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { MainnetController } from 'spark-alm-controller/src/MainnetController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { SLLHelpers } from '../../SparkPayloadEthereum.sol';

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { ReserveConfig }    from '../../test-harness/ProtocolV3TestBase.sol';
import { SparkLendContext } from '../../test-harness/SparklendTests.sol';
import { SparkTestBase }    from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250724Test is SparkTestBase {

    address internal constant GROVE_ALM_PROXY                  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant LIQUIDATION_MULTISIG             = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address internal constant PT_SPK_USDS_25SEP2025            = 0xC347584b415715B1b66774B2899Fef2FD3b56d6e;
    address internal constant PT_SPK_USDS_25SEP2025_PRICE_FEED = 0xaA31f21E3d23bF3A8F401E670171b0DA10F8466f;
    address internal constant SPARK_USDS_VAULT                 = 0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597;

    constructor() {
        id = "20250724";
    }

    function setUp() public {
        setupDomains("2025-07-16T13:51:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x74e1ba852C864d689562b5977EedCB127fDE0C9F;
    }

    function test_ETHEREUM_WBTCChanges() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);
        ReserveConfig memory config = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(config.liquidationThreshold, 40_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        config.liquidationThreshold = 35_00;

        _validateReserveConfig(config, allConfigsAfter);
    }

    function test_BASE_morphoRateLimitChanges() public onChain(ChainIdUtils.Base()) {
        bytes32 morphoUsdcVaultDepositKey = RateLimitHelpers.makeAssetKey(
            ForeignController(Base.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            Base.MORPHO_VAULT_SUSDC
        );

        _assertRateLimit(morphoUsdcVaultDepositKey, 50_000_000e6, 25_000_000e6 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertRateLimit(morphoUsdcVaultDepositKey, 100_000_000e6, 50_000_000e6 / uint256(1 days));
    }

    function test_ETHEREUM_transferEthToMultisig() public onChain(ChainIdUtils.Ethereum()) {
        uint256 balanceBefore = IERC20(Ethereum.WETH_ATOKEN).balanceOf(Ethereum.TREASURY);

        assertGe(balanceBefore, 500e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.WETH_ATOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.WETH_ATOKEN).balanceOf(LIQUIDATION_MULTISIG), balanceBefore);
    }

    function test_ETHEREUM_transferTokensToGrove() public onChain(ChainIdUtils.Ethereum()) {
        uint256 buidlIbalanceBefore = IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY);
        uint256 jtrsyBalanceBefore  = IERC20(Ethereum.JTRSY).balanceOf(Ethereum.ALM_PROXY);

        assertGe(buidlIbalanceBefore, 800_000_000e6);
        assertGe(jtrsyBalanceBefore,  370_000_000e6);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY), 0);
        assertEq(IERC20(Ethereum.JTRSY).balanceOf(Ethereum.ALM_PROXY),  0);
        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(GROVE_ALM_PROXY),    buidlIbalanceBefore);
        assertEq(IERC20(Ethereum.JTRSY).balanceOf(GROVE_ALM_PROXY),     jtrsyBalanceBefore);
    }

    function test_ETHEREUM_morpho_PTSPKUSDS25SEP2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: SPARK_USDS_VAULT,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SPK_USDS_25SEP2025,
                oracle:          PT_SPK_USDS_25SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            currentCap: 0,
            newCap:     500_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_SPK_USDS_25SEP2025,
            loanToken: Ethereum.USDS,
            oracle:    PT_SPK_USDS_25SEP2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1758758400  // Thursday, September 25, 2025 12:00:00 AM UTC
        });
    }

    function test_ETHEREUM_SLL_MorphoSparkUSDSOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits rateLimits       = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        uint256 depositAmount        = 1_000_000e18;

        deal(Ethereum.USDS, Ethereum.ALM_PROXY, 20 * depositAmount);
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_DEPOSIT(),
            SPARK_USDS_VAULT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_WITHDRAW(),
            SPARK_USDS_VAULT
        );

        assertEq(IMetaMorpho(SPARK_USDS_VAULT).isAllocator(Ethereum.ALM_RELAYER), false);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        vm.prank(Ethereum.ALM_RELAYER);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.depositERC4626(SPARK_USDS_VAULT, depositAmount);

        executeAllPayloadsAndBridges();

        assertEq(IMetaMorpho(SPARK_USDS_VAULT).isAllocator(Ethereum.ALM_RELAYER), true);

        _assertRateLimit(depositKey,  200_000_000e18,    uint256(100_000_000e18) / 1 days);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        vm.prank(Ethereum.ALM_RELAYER);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        controller.depositERC4626(SPARK_USDS_VAULT, 200_000_001e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  200_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        MarketParams memory idleMarket = SLLHelpers.morphoIdleMarket(Ethereum.USDS);
        MarketParams memory ptMarket   = MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SPK_USDS_25SEP2025,
                oracle:          PT_SPK_USDS_25SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            });

        skip(1 days);

        IMetaMorpho(SPARK_USDS_VAULT).acceptCap(
            idleMarket
        );
        IMetaMorpho(SPARK_USDS_VAULT).acceptCap(
            ptMarket
        );

        Id[] memory ids = new Id[](2);
        ids[0] = MarketParamsLib.id(ptMarket);
        ids[1] = MarketParamsLib.id(idleMarket);

        vm.startPrank(Ethereum.ALM_RELAYER);
        IMetaMorpho(SPARK_USDS_VAULT).setSupplyQueue(ids);
        controller.depositERC4626(SPARK_USDS_VAULT, depositAmount);
        vm.stopPrank();

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  200_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(Ethereum.ALM_RELAYER);
        controller.withdrawERC4626(SPARK_USDS_VAULT, 1e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  200_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        skip(1 days);
        assertEq(rateLimits.getCurrentRateLimit(depositKey), 200_000_000e18);
    }

}
