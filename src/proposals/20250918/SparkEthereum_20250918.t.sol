// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base } from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { SparkLiquidityLayerContext } from '../../test-harness/SparkLiquidityLayerTests.sol';
import { SparkTestBase }              from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250918Test is SparkTestBase {

    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;
    address internal constant NEW_ALM_CONTROLLER_BASE     = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;

    address internal constant PT_USDS_SPK_18DEC2025            = 0xA2a420230A5cb045db052E377D20b9c156805b95;
    address internal constant PT_USDS_SPK_18DEC2025_PRICE_FEED = 0x0F9D6c72959d836D4DECdE30Ab0AD836979EFE87;

    constructor() {
        id = "20250918";
    }

    function setUp() public {
        setupDomains("2025-09-10T08:36:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xe7782847eF825FF37662Ef2F426f2D8c5D904121;
    }

    function test_ETHEREUM_morpho_onboardPTUSDSSPK18Dec2025() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_USDS,
            config: MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDS_SPK_18DEC2025,
                oracle:          PT_USDS_SPK_18DEC2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            currentCap: 0,
            newCap:     1_000_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_USDS_SPK_18DEC2025,
            loanToken: Ethereum.USDS,
            oracle:    PT_USDS_SPK_18DEC2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1766016000  // December 18, 2025 12:00:00 AM UTC
        });
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER_ETHEREUM);
    }

    function test_BASE_controllerUpgrade() public onChain(ChainIdUtils.Base()) {
        _testControllerUpgrade(Base.ALM_CONTROLLER, NEW_ALM_CONTROLLER_BASE);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  426_533_971.126578246102965428e18);
        assertEq(spUsdsBalanceBefore, 571_933_609.319213677194335496e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    426_542_116.448272852508728339e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   571_943_578.254251010380121323e18);
    }

}
