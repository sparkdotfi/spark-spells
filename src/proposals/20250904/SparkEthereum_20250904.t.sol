// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { ReserveConfig }              from '../../test-harness/ProtocolV3TestBase.sol';
import { SparkLendContext }           from '../../test-harness/SparklendTests.sol';
import { SparkLiquidityLayerContext } from '../../test-harness/SparkLiquidityLayerTests.sol';
import { SparkTestBase }              from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250904Test is SparkTestBase {

    address internal constant USDS_ATOKEN     = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;

    uint256 internal constant USDS_AMOUNT_TO_SPARK_FOUNDATION = 800_000e18;

    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x20Cea639A895c3c85dce326dc6A736508C310B4b;
    address internal constant PT_SUSDE_27NOV2025            = 0xe6A934089BBEe34F832060CE98848359883749B3;
    address internal constant PT_SUSDE_27NOV2025_PRICE_FEED = 0x098fA1fcB5Ed89Bffb2d6876857764fc14837DB5;

    address internal constant GROVE_ALM_PROXY  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant SPARK_FOUNDATION = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;

    constructor() {
        id = "20250904";
    }

    function setUp() public {
        setupDomains("2025-08-26T15:50:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xa57d3ea3aBAbD57Ed1a1d91CD998a68FB490B95E;
    }

    function test_BASE_spark_morphoUSDCVaultFee() public onChain(ChainIdUtils.Base()) {
        assertEq(IMetaMorpho(Base.MORPHO_VAULT_SUSDC).fee(), 0.1e18);

        executeAllPayloadsAndBridges();

        assertEq(IMetaMorpho(Base.MORPHO_VAULT_SUSDC).fee(), 0.01e18);
    }

    function test_ETHEREUM_transferUSDSToFoundation() public onChain(ChainIdUtils.Ethereum()) {
        uint256 foundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_FOUNDATION);
        uint256 sparkUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(sparkUsdsBalanceBefore,      21_937_923.925801365846236778e18);
        assertEq(foundationUsdsBalanceBefore, 800_000e18);

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
        uint256 sparkBuidlIbalanceBefore  = IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY);
        uint256 grovekBuidlIbalanceBefore = IERC20(Ethereum.BUIDLI).balanceOf(GROVE_ALM_PROXY);

        assertEq(sparkBuidlIbalanceBefore,  900_612.89e6);
        assertEq(grovekBuidlIbalanceBefore, 509_244_730.54e6);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY), 0);
        assertEq(IERC20(Ethereum.BUIDLI).balanceOf(GROVE_ALM_PROXY),    grovekBuidlIbalanceBefore + sparkBuidlIbalanceBefore);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_ATOKEN).balanceOf(Ethereum.SPARK_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(USDS_ATOKEN).balanceOf(Ethereum.SPARK_PROXY);

        assertEq(spDaiBalanceBefore,  0);
        assertEq(spUsdsBalanceBefore, 1.011195037668297593e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_ATOKEN).balanceOf(Ethereum.SPARK_PROXY), 0);
        assertEq(IERC20(USDS_ATOKEN).balanceOf(Ethereum.SPARK_PROXY),         spUsdsBalanceBefore + 537_775.726095122943628121e18);
    }

}
