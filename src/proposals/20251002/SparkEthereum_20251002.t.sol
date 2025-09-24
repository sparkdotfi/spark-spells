// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils }     from 'src/libraries/ChainId.sol';
import { SparkTestBase }    from 'src/test-harness/SparkTestBase.sol';
import { ReserveConfig }    from 'src/test-harness/ProtocolV3TestBase.sol';
import { SparkLendContext } from 'src/test-harness/SparklendTests.sol';

contract SparkEthereum_20251002Test is SparkTestBase {

    address internal constant GROVE_SUBDAO_PROXY = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;
    address internal constant PYUSD              = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant SYRUP              = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;

    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;

    uint256 internal constant AMOUNT_TO_GROVE            = 1_031_866e18;
    uint256 internal constant AMOUNT_TO_SPARK_FOUNDATION = 1_100_000e18;

    constructor() {
        id = "20251002";
    }

    function setUp() public {
        setupDomains("2025-09-24T13:31:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x7B28F4Bdd7208fe80916EBC58611Eb72Fb6A09Ed;
    }

    function test_ETHEREUM_morpho_increasePTUSDE27NovSupplyCap() public onChain(ChainIdUtils.Ethereum()) {
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

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() public onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 2500, 250, 12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 500, 12 hours);
    }

    function test_ETHEREUM_sll_onboardSparklendETH() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding(
            Ethereum.WETH_SPTOKEN,
            1_000e18,
            50_000e18,
            10_000e18 / uint256(1 days)
        );
    }

    function test_ETHEREUM_sll_transferAssetB2C2USDC() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            address(0xdead) // TODO change
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(
            Ethereum.USDC,
            address(0xdead), // TODO change
            Ethereum.ALM_CONTROLLER,
            1_000_000e6,
            1_000_000e6
        );
    }

    function test_ETHEREUM_sll_transferAssetB2C2USDT() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            address(0xdead) // TODO change
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(
            Ethereum.USDT,
            address(0xdead), // TODO change
            Ethereum.ALM_CONTROLLER,
            1_000_000e6,
            1_000_000e6
        );
    }

    function test_ETHEREUM_sll_transferAssetB2C2PYUSD() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAssetDestinationKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            PYUSD,
            address(0xdead) // TODO change
        );

        _assertRateLimit(transferKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(
            PYUSD,
            address(0xdead), // TODO change
            Ethereum.ALM_CONTROLLER,
            1_000_000e6,
            1_000_000e6
        );
    }

    function test_ETHEREUM_sll_transferAssetSYRUP() public onChain(ChainIdUtils.Ethereum()) {
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

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() public onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  404_320_160.818926086778450517e18);
        assertEq(spUsdsBalanceBefore, 592_424_783.583591603436341145e18);

        executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spDaiBalanceBefore + 33_225.584380788531641492e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   spUsdsBalanceBefore + 43_626.185445845175175216e18);
    }

}
