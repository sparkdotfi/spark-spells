// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { SparkLiquidityLayerContext } from '../../test-harness/SparkLiquidityLayerTests.sol';
import { SparkTestBase }              from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250904Test is SparkTestBase {

    uint256 internal constant USDS_AMOUNT_TO_SPARK_FOUNDATION = 800_000e18;

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;
    address internal constant PT_SUSDE_27NOV2025            = 0xe6A934089BBEe34F832060CE98848359883749B3;
    address internal constant PT_SUSDE_27NOV2025_PRICE_FEED = 0xd46F66D7Fc5aD6f54b9B62D36B9A4d99f3Cca451;
    address internal constant WSTETH_PRICE_FEED             = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

    // address internal constant CURVE_PYUSDUSDC = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    // address internal constant USDE_ATOKEN     = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;

    address internal constant GROVE_ALM_PROXY  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant SPARK_FOUNDATION = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;

    constructor() {
        id = "20250904";
    }

    function setUp() public {
        setupDomains("2025-09-09T16:09:00Z");

        deployPayloads();

        chainData[ChainIdUtils.Ethereum()].payload = 0xe7782847eF825FF37662Ef2F426f2D8c5D904121;
    }

    function test_ETHEREUM_transferUSDSToFoundation() public onChain(ChainIdUtils.Ethereum()) {
        uint256 foundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_FOUNDATION);
        uint256 sparkUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(sparkUsdsBalanceBefore,      21_937_923.925801365846236778e18);
        assertEq(foundationUsdsBalanceBefore, 49_944.004e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY), sparkUsdsBalanceBefore - USDS_AMOUNT_TO_SPARK_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(SPARK_FOUNDATION),     foundationUsdsBalanceBefore + USDS_AMOUNT_TO_SPARK_FOUNDATION);
    }

    function test_ETHEREUM_morpho_onboardPTUSDE27Nov2025() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_USDS,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDE_27NOV2025,
                oracle:          PT_USDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     500_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_USDE_27NOV2025,
            loanToken: Ethereum.USDS,
            oracle:    PT_USDE_27NOV2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1764201600  // November 27, 2025 12:00:00 AM UTC
        });
    }

    function test_ETHEREUM_morpho_onboardPTSUSDE27Nov2025() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_USDS,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SUSDE_27NOV2025,
                oracle:          PT_SUSDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     500_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_SUSDE_27NOV2025,
            loanToken: Ethereum.USDS,
            oracle:    PT_SUSDE_27NOV2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1764201600  // November 27, 2025 12:00:00 AM UTC
        });
    }

    function test_ETHEREUM_transferBuildIToGrove() public onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkBuidlIBalanceBefore = IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY);
        uint256 groveBuidlIBalanceBefore = IERC20(Ethereum.BUIDLI).balanceOf(GROVE_ALM_PROXY);

        assertEq(sparkBuidlIBalanceBefore, 900_612.89e6);
        assertEq(groveBuidlIBalanceBefore, 459_654_480.61e6);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY), 0);
        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(GROVE_ALM_PROXY),    groveBuidlIBalanceBefore + sparkBuidlIBalanceBefore);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(spDaiBalanceBefore,  1.100431958657483361e18);
        assertEq(spUsdsBalanceBefore, 1.011885312467426036e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY),  544_557.070290529283364277e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY), 588_859.302421241251901482e18);
    }

    function test_ETHEREUM_sll_onboardUsde() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding(
            USDE_ATOKEN,
            1_000_000e18,
            250_000_000e18,
            100_000_000e18 / uint256(1 days)
        );
    }

    function test_ETHEREUM_sll_updateCurveSwapLimitAndMaxSlippage() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ctx.controller);

        bytes32 pyusdUsdcCurveSwapKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_CURVE_SWAP(),
            CURVE_PYUSDUSDC
        );

        bytes32 susdsUsdtCurveSwapKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_CURVE_SWAP(),
            Ethereum.CURVE_SUSDSUSDT
        );

        _assertRateLimit(pyusdUsdcCurveSwapKey, 5_000_000e18, 25_000_000e18 / uint256(1 days));
        _assertRateLimit(susdsUsdtCurveSwapKey, 5_000_000e18, 20_000_000e18 / uint256(1 days));

        assertEq(controller.maxSlippages(CURVE_PYUSDUSDC),          0.9995e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9985e18);

        executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(CURVE_PYUSDUSDC),          0.9990e18);
        assertEq(controller.maxSlippages(Ethereum.CURVE_SUSDSUSDT), 0.9975e18);

        _assertRateLimit(pyusdUsdcCurveSwapKey, 5_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(susdsUsdtCurveSwapKey, 5_000_000e18, 100_000_000e18 / uint256(1 days));
    }

    function test_ETHEREUM_sll_updateRateLimits() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdtDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
            Ethereum.USDT_SPTOKEN
        );

        bytes32 pyusdDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
            Ethereum.PYUSD_SPTOKEN
        );

        _assertRateLimit(usdtDepositKey,  100_000_000e6, 50_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdDepositKey, 50_000_000e6,  25_000_000e6 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertRateLimit(usdtDepositKey,  100_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdDepositKey, 100_000_000e6, 100_000_000e6 / uint256(1 days));
    }

    function test_ETHEREUM_morpho_createNewMorphoVault() public onChain(ChainIdUtils.Ethereum()) {
        MarketParams[] memory markets = new MarketParams[](2);
        uint256[] memory caps = new uint256[](2);

        markets[0] = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.CBBTC,
            oracle:          CBBTC_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        caps[0] = 500_000_000e6;

        markets[1] = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.WSTETH,
            oracle:          WSTETH_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        caps[1] = 500_000_000e6;

        _testMorphoVaultCreation({
            asset:           Ethereum.USDC,
            name:            "Spark Blue Chip USDC Vault",
            symbol:          "sparkUSDCbc",
            markets:         markets,
            caps:            caps,
            vaultFee:        0.01e18,
            initialDeposit:  1e6,
            sllDepositMax:   50_000_000e6,
            sllDepositSlope: 25_000_000e6 / uint256(1 days)
        });
    }

}
