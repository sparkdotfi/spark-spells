// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum }              from 'spark-address-registry/Ethereum.sol';
import { Base }                  from 'spark-address-registry/Base.sol';
import { MainnetController }     from 'spark-alm-controller/src/MainnetController.sol';
import { ForeignController }     from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }           from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { RateLimitHelpers }      from 'spark-alm-controller/src/RateLimitHelpers.sol';
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { IAaveOracle }           from 'sparklend-v1-core/contracts/interfaces/IAaveOracle.sol';
import { IMetaMorpho }           from 'lib/metamorpho/src/interfaces/IMetaMorpho.sol';

import { SparkTestBase } from 'src/SparkTestBase.sol';
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';
import { ReserveConfig } from '../../ProtocolV3TestBase.sol';

interface IPriceAggregatorLike {
    function chronicle()   external returns(address);
    function redstone()    external returns(address);
    function chainlink()   external returns(address);
    function uniswapPool() external returns(address);
    function getAgeThreshold() external returns(uint256);
    function ageThreshold() external returns(uint256);
    function decimals() external returns(uint8);
}

interface IwstETHOracleLike {
    function steth()   external returns(address);
    function ethSource()    external returns(address);
}

interface IweETHOracleLike {
    function weeth()     external returns(address);
    function ethSource() external returns(address);
}

interface IrETHOracleLike {
    function reth()     external returns(address);
    function ethSource() external returns(address);
}

contract SparkEthereum_20250206Test is SparkTestBase {
    using DomainHelpers for Domain;

    address public immutable MAINNET_FLUID_SUSDS_VAULT = 0x2BBE31d63E6813E3AC858C04dae43FB2a72B0D11;
    address public immutable BASE_FLUID_SUSDS_VAULT    = 0xf62e339f21d8018940f188F6987Bcdf02A849619;

    // ETH/USD pricefeed previously used for WETH
    address public immutable AGGOR_ETH_USD_1       = 0xf07ca0e66A798547E4CB3899EC592e1E99Ef6Cb3;
    // ETH/USD pricefeed previously used as the eth price source for wstETH
    address public immutable AGGOR_ETH_USD_2       = 0x00480CD3ed33de45555410BA71b2F932A14b1Cf2;
    // ETH/USD pricefeed previously used as the eth price source for rETH
    address public immutable AGGOR_ETH_USD_3       = 0x69115a2826Eb47FE9DFD1d5CA8D8642697c8b68A;
    // ETH/USD pricefeed previously used as the eth price source for weETH
    address public immutable AGGOR_ETH_USD_4       = 0xb20A1374EfCaFa32F701Ab14316fA2E5b3400eD5;

    // Chronicle_Aggor_ETH_USD, newly deployed
    address public immutable NEW_WETH_PRICEFEED    = 0x2750e4CB635aF1FCCFB10C0eA54B5b5bfC2759b6;
    address public immutable WETH_CHAINLINK_SOURCE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public immutable WETH_CHRONICLE_SOURCE = 0x46ef0071b1E2fF6B42d36e5A177EA43Ae5917f4E;
    address public immutable WETH_REDSTONE_SOURCE  = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    address public immutable WETH_UNISWAP_SOURCE   = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    address public immutable PREVIOUS_CBBTC_PRICEFEED = 0xb9ED698c9569c5abea716D1E64c089610a3768B6;
    address public immutable NEW_CBBTC_PRICEFEED      = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;
    address public immutable CBBTC_CHAINLINK_SOURCE   = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public immutable CBBTC_CHRONICLE_SOURCE   = 0x24C392CDbF32Cf911B258981a66d5541d85269ce;
    address public immutable CBBTC_REDSTONE_SOURCE    = 0xAB7f623fb2F6fea6601D4350FA0E2290663C28Fc;

    address public immutable PREVIOUS_WSTETH_PRICEFEED = 0xf77e132799DBB0d83A4fB7df10DA04849340311A;
    // deployed by Wonderland, pointing to STETH address below and NEW_WETH_PRICEFEED
    address public immutable NEW_WSTETH_PRICEFEED      = 0xE98d51fa014C7Ed68018DbfE6347DE9C3f39Ca39;
    // TODO: not in registry, should be added
    address public immutable STETH                     = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address public immutable PREVIOUS_WEETH_PRICEFEED = 0x28897036f8459bFBa886083dD6b4Ce4d2f14a57F;
    // deployed by Wonderland, pointing to WEETH address in registry and NEW_WETH_PRICEFEED
    address public immutable NEW_WEETH_PRICEFEED      = 0xBE21C54Dff3b2F1708970d185aa5b0eEB70556f1;

    address public immutable PREVIOUS_RETH_PRICEFEED = 0x11af58f13419fD3ce4d3A90372200c80Bc62f140;
    // deployed by Wonderland, pointing to RETH address in registry and NEW_WETH_PRICEFEED
    address public immutable NEW_RETH_PRICEFEED      = 0xFDdf8D19D092839A26b31365c927cA236B5086cf;

    uint256 public immutable ORACLE_AGE_THRESHOLD = 25 hours;
    uint8 public immutable ORACLE_DECIMALS        = 8;

    constructor() {
        id = '20250206';
    }

    function setUp() public {
        setupDomains({
            mainnetForkBlock: 21732103,
            baseForkBlock:    25693427,
            gnosisForkBlock:  38037888
        });

        chainSpellMetadata[ChainIdUtils.Base()].payload     = 0x2DB2f1eE78b4e0ad5AaF44969E2E8f563437f34C;
        chainSpellMetadata[ChainIdUtils.Ethereum()].payload = 0xD5c59b7c1DD8D2663b4c826574ed968B2C8329C0;
    }

    function test_ETHEREUM_SLL_FluidsUSDSOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits rateLimits       = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        uint256 depositAmount        = 1_000_000e18;

        deal(Ethereum.SUSDS, Ethereum.ALM_PROXY, 20 * depositAmount);
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_DEPOSIT(),
            MAINNET_FLUID_SUSDS_VAULT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_WITHDRAW(),
            MAINNET_FLUID_SUSDS_VAULT
        );

        vm.prank(Ethereum.ALM_RELAYER);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.depositERC4626(MAINNET_FLUID_SUSDS_VAULT, depositAmount);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 10_000_000e18, uint256(5_000_000e18) / 1 days);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        vm.prank(Ethereum.ALM_RELAYER);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        controller.depositERC4626(MAINNET_FLUID_SUSDS_VAULT, 10_000_001e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(Ethereum.ALM_RELAYER);
        controller.depositERC4626(MAINNET_FLUID_SUSDS_VAULT, depositAmount);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(Ethereum.ALM_RELAYER);
        controller.withdrawERC4626(MAINNET_FLUID_SUSDS_VAULT, depositAmount);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        // Slope is 5M/day, the deposit amount of 1M should be replenished in a fifth of a day.
        // Wait for half of that, and assert half of the rate limit was replenished.
        skip(1 days / 10);
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18 - depositAmount/2, 5000);
        // Wait for 1 more second to avoid rounding issues
        skip(1 days / 10 + 1);
        assertEq(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18);
    }

    function test_ETHEREUM_Sparklend_WBTCLiquidationThreshold() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);
        ReserveConfig memory wbtcConfig         = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(wbtcConfig.liquidationThreshold, 55_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);
        wbtcConfig.liquidationThreshold        = 50_00;

        _validateReserveConfig(wbtcConfig, allConfigsAfter);
    }

    function test_ETHEREUM_Sparklend_WETH_Pricefeed() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.WETH), AGGOR_ETH_USD_1);

        assertEq(IPriceAggregatorLike(AGGOR_ETH_USD_1).chainlink(),   WETH_CHAINLINK_SOURCE);
        assertEq(IPriceAggregatorLike(AGGOR_ETH_USD_1).chronicle(),   WETH_CHRONICLE_SOURCE);
        assertEq(IPriceAggregatorLike(AGGOR_ETH_USD_1).uniswapPool(), WETH_UNISWAP_SOURCE);

        assertEq(IPriceAggregatorLike(AGGOR_ETH_USD_1).ageThreshold(), ORACLE_AGE_THRESHOLD);
        assertEq(IPriceAggregatorLike(AGGOR_ETH_USD_1).decimals(),     ORACLE_DECIMALS);

        uint256 WETHPrice = oracle.getAssetPrice(Ethereum.WETH);
        // sanity checks on pre-existing price
        assertEq(WETHPrice, 3_104.38063228e8);

        _assertPreviousETHPricefeedBehaviour({
            asset:           Ethereum.WETH,
            chainlinkSource: WETH_CHAINLINK_SOURCE,
            chronicleSource: WETH_CHRONICLE_SOURCE,
            uniswapPool:     WETH_UNISWAP_SOURCE
        });

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 WETHPriceAfter  = oracle.getAssetPrice(Ethereum.WETH);
        assertEq(oracle.getSourceOfAsset(Ethereum.WETH), NEW_WETH_PRICEFEED);
        assertEq(WETHPriceAfter,                         3_110.43126457e8);

        assertEq(IPriceAggregatorLike(NEW_WETH_PRICEFEED).getAgeThreshold(), ORACLE_AGE_THRESHOLD);
        assertEq(IPriceAggregatorLike(NEW_WETH_PRICEFEED).decimals(),        ORACLE_DECIMALS);

        assertEq(IPriceAggregatorLike(NEW_WETH_PRICEFEED).chainlink(), WETH_CHAINLINK_SOURCE);
        assertEq(IPriceAggregatorLike(NEW_WETH_PRICEFEED).chronicle(), WETH_CHRONICLE_SOURCE);
        assertEq(IPriceAggregatorLike(NEW_WETH_PRICEFEED).redstone(),  WETH_REDSTONE_SOURCE);

        _assertNewPricefeedBehaviour({
            asset:           Ethereum.WETH,
            chainlinkSource: WETH_CHAINLINK_SOURCE,
            chronicleSource: WETH_CHRONICLE_SOURCE,
            uniswapPool:     WETH_UNISWAP_SOURCE,
            redstoneSource:  WETH_REDSTONE_SOURCE
        });
    }

    function test_ETHEREUM_Sparklend_wstETH_Pricefeed() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.WSTETH), PREVIOUS_WSTETH_PRICEFEED);

        assertEq(IwstETHOracleLike(PREVIOUS_WSTETH_PRICEFEED).steth(),     STETH);
        assertEq(IwstETHOracleLike(PREVIOUS_WSTETH_PRICEFEED).ethSource(), AGGOR_ETH_USD_2);

        assertEq(IwstETHOracleLike(NEW_WSTETH_PRICEFEED).steth(),     STETH);
        assertEq(IwstETHOracleLike(NEW_WSTETH_PRICEFEED).ethSource(), NEW_WETH_PRICEFEED);

        uint256 WSTETHPrice = oracle.getAssetPrice(Ethereum.WSTETH);
        // sanity checks on pre-existing price
        assertEq(WSTETHPrice,   3_700.88418905e8);

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 WSTETHPriceAfter  = oracle.getAssetPrice(Ethereum.WSTETH);
        assertEq(oracle.getSourceOfAsset(Ethereum.WSTETH), NEW_WSTETH_PRICEFEED);
        assertEq(WSTETHPriceAfter,                         3708.09744413e8);
    }

    function test_ETHEREUM_Sparklend_weETH_Pricefeed() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.WEETH), PREVIOUS_WEETH_PRICEFEED);

        assertEq(IweETHOracleLike(PREVIOUS_WEETH_PRICEFEED).weeth(),     Ethereum.WEETH);
        assertEq(IweETHOracleLike(PREVIOUS_WEETH_PRICEFEED).ethSource(), AGGOR_ETH_USD_4);

        assertEq(IweETHOracleLike(NEW_WEETH_PRICEFEED).weeth(),     Ethereum.WEETH);
        assertEq(IweETHOracleLike(NEW_WEETH_PRICEFEED).ethSource(), NEW_WETH_PRICEFEED);

        // sanity checks on pre-existing price
        uint256 WEETHPrice = oracle.getAssetPrice(Ethereum.WEETH);
        assertEq(WEETHPrice,   3_286.96662440e8);

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 WEETHPriceAfter  = oracle.getAssetPrice(Ethereum.WEETH);
        assertEq(oracle.getSourceOfAsset(Ethereum.WEETH), NEW_WEETH_PRICEFEED);
        assertEq(WEETHPriceAfter,                         3_293.37312822e8);
    }

    function test_ETHEREUM_Sparklend_rETH_Pricefeed() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.RETH), PREVIOUS_RETH_PRICEFEED);

        assertEq(IrETHOracleLike(PREVIOUS_RETH_PRICEFEED).reth(),      Ethereum.RETH);
        assertEq(IrETHOracleLike(PREVIOUS_RETH_PRICEFEED).ethSource(), AGGOR_ETH_USD_3);

        assertEq(IrETHOracleLike(NEW_RETH_PRICEFEED).reth(),      Ethereum.RETH);
        assertEq(IrETHOracleLike(NEW_RETH_PRICEFEED).ethSource(), NEW_WETH_PRICEFEED);

        // sanity checks on pre-existing price
        uint256 RETHPrice = oracle.getAssetPrice(Ethereum.RETH);
        assertEq(RETHPrice, 349960533012);

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 RETHPriceAfter  = oracle.getAssetPrice(Ethereum.RETH);
        assertEq(oracle.getSourceOfAsset(Ethereum.RETH), NEW_RETH_PRICEFEED);
        assertEq(RETHPriceAfter,                         3_506.42628010e8);
    }

    function test_ETHEREUM_Sparklend_cbBTC_Pricefeed() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.CBBTC), PREVIOUS_CBBTC_PRICEFEED);

        assertEq(IPriceAggregatorLike(PREVIOUS_CBBTC_PRICEFEED).chainlink(), CBBTC_CHAINLINK_SOURCE);
        assertEq(IPriceAggregatorLike(PREVIOUS_CBBTC_PRICEFEED).chronicle(), CBBTC_CHRONICLE_SOURCE);

        // can't assert on age threshold since previous oracle didn't implement
        // it, only forwarding the chronicle value with chainlink's decimals
        assertEq(IPriceAggregatorLike(PREVIOUS_CBBTC_PRICEFEED).decimals(), ORACLE_DECIMALS);

        uint256 CBBTCPrice = oracle.getAssetPrice(Ethereum.CBBTC);
        // sanity checks on pre-existing price
        assertEq(CBBTCPrice,   102_238.70000000e8);

        _assertPreviousBTCPricefeedBehaviour({
            asset:           Ethereum.CBBTC,
            chainlinkSource: CBBTC_CHAINLINK_SOURCE,
            chronicleSource: CBBTC_CHRONICLE_SOURCE
        });

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 CBBTCPriceAfter  = oracle.getAssetPrice(Ethereum.CBBTC);
        assertEq(oracle.getSourceOfAsset(Ethereum.CBBTC), NEW_CBBTC_PRICEFEED);
        assertEq(CBBTCPriceAfter,                         102_733.52699733e8);

        assertEq(IPriceAggregatorLike(NEW_CBBTC_PRICEFEED).chainlink(), CBBTC_CHAINLINK_SOURCE);
        assertEq(IPriceAggregatorLike(NEW_CBBTC_PRICEFEED).chronicle(), CBBTC_CHRONICLE_SOURCE);
        assertEq(IPriceAggregatorLike(NEW_CBBTC_PRICEFEED).redstone(),  CBBTC_REDSTONE_SOURCE);

        assertEq(IPriceAggregatorLike(NEW_CBBTC_PRICEFEED).getAgeThreshold(), ORACLE_AGE_THRESHOLD);
        assertEq(IPriceAggregatorLike(NEW_CBBTC_PRICEFEED).decimals(),        ORACLE_DECIMALS);

        _assertNewPricefeedBehaviour({
            asset:           Ethereum.CBBTC,
            chainlinkSource: CBBTC_CHAINLINK_SOURCE,
            chronicleSource: CBBTC_CHRONICLE_SOURCE,
            uniswapPool:     address(0), // not relevant since previous feed didnt use it
            redstoneSource:  CBBTC_REDSTONE_SOURCE
        });
    }


    function test_BASE_SLL_FluidsUSDSOnboarding() public onChain(ChainIdUtils.Base()) {
        ForeignController controller = ForeignController(Base.ALM_CONTROLLER);
        IRateLimits rateLimits       = IRateLimits(Base.ALM_RATE_LIMITS);
        uint256 depositAmount        = 1_000_000e18;

        deal(Base.SUSDS, Base.ALM_PROXY, 20 * depositAmount);
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_DEPOSIT(),
            BASE_FLUID_SUSDS_VAULT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_WITHDRAW(),
            BASE_FLUID_SUSDS_VAULT
        );

        vm.prank(Base.ALM_RELAYER);
        vm.expectRevert("RateLimits/zero-maxAmount");
        controller.depositERC4626(BASE_FLUID_SUSDS_VAULT, depositAmount);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  10_000_000e18, uint256(5_000_000e18) / 1 days);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        vm.prank(Base.ALM_RELAYER);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        controller.depositERC4626(BASE_FLUID_SUSDS_VAULT, 10_000_001e18);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(Base.ALM_RELAYER);
        controller.depositERC4626(BASE_FLUID_SUSDS_VAULT, depositAmount);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        vm.prank(Base.ALM_RELAYER);
        controller.withdrawERC4626(BASE_FLUID_SUSDS_VAULT, depositAmount);

        assertEq(rateLimits.getCurrentRateLimit(depositKey),  10_000_000e18 - depositAmount);
        assertEq(rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);

        // Slope is 5M/day, the deposit amount of 1M should be replenished in a fifth of a day.
        // Wait for half of that, and assert half of the rate limit was replenished.
        skip(1 days / 10);
        assertApproxEqAbs(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18 - depositAmount/2, 5000);
        // Wait for 1 more second to avoid rounding issues
        skip(1 days / 10 + 1);
        assertEq(rateLimits.getCurrentRateLimit(depositKey), 10_000_000e18);
    }

    function test_BASE_IncreaseMorphoTimeout() public onChain(ChainIdUtils.Base()) {
        assertEq(IMetaMorpho(Base.MORPHO_VAULT_SUSDC).timelock(), 0);
        executeAllPayloadsAndBridges();
        assertEq(IMetaMorpho(Base.MORPHO_VAULT_SUSDC).timelock(), 86400);
    }

    function _assertNewPricefeedBehaviour(
        address asset,
        address chainlinkSource,
        address chronicleSource,
        address uniswapPool,
        address redstoneSource
    ) internal {
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);
        // parameter for mocked uniswap calls
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 3600;
        secondsAgo[1] = 0;

        // A normal price query without divergence returns the Chronicle, Redstone and Chainlink median, without calling uniswap
        vm.mockCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            1,               // same as real call
            1_003e8,         // price -- mocked
            block.timestamp, // age, mocked to now to avoid stale price errors 
            block.timestamp, // same as real call
            1                // same as real call
        ));
        vm.expectCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chainlinkSource,   abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300, // roundId from real call
            1_000e8,               // price -- mocked
            block.timestamp,       // age, mocked to now to avoid stale price errors
            block.timestamp,       // age, mocked to now to avoid stale price errors
            129127208515966867300  // roundId from real call
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,           // same as from real call
            1_002e18,       // price -- mocked
            block.timestamp // age, mocked to now to avoid stale price errors
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool, abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_002e8);
        vm.clearMockedCalls();

        // A price query with serious divergence between Chronicle and Chainlink still returns the three source median, without calling uniswap
        vm.mockCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            1,               // same as real call
            3e8,             // price -- mocked
            block.timestamp, // age, mocked to now to avoid stale price errors
            block.timestamp, // age, mocked to now to avoid stale price errors
            1                // same as real call
        ));
        vm.expectCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chainlinkSource,   abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300, // roundId from real call
            1_000e8,               // price -- mocked
            block.timestamp,       // age, mocked to now to avoid stale price errors ,
            block.timestamp,       // age, mocked to now to avoid stale price errors ,
            129127208515966867300  // roundId from real call
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,           // same as from real call
            99_000e18,      // price -- mocked
            block.timestamp // age, mocked to now to avoid stale price errors
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool, abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_000e8);
        vm.clearMockedCalls();
    }

    function _assertPreviousBTCPricefeedBehaviour(
        address asset,
        address chainlinkSource,
        address chronicleSource
    ) internal {
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        // Price queries are forwarded to chronicle
        vm.mockCallRevert(chainlinkSource, abi.encodeWithSignature("latestRoundData()"), bytes('chainlink should not be called'));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("latestAnswer()"), abi.encode(
            1_000e18   // price -- mocked
        ));
        vm.expectCall(chronicleSource,   abi.encodeWithSignature("latestAnswer()"));
        assertEq(oracle.getAssetPrice(asset), 1_000e8);
        vm.clearMockedCalls();
    }

    function _assertPreviousETHPricefeedBehaviour(
        address asset,
        address chainlinkSource,
        address chronicleSource,
        address uniswapPool
    ) internal {
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);
        // parameter for mocked uniswap calls
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 3600;
        secondsAgo[1] = 0;

        // A normal price query without divergence between Chronicle and Chainlink returns the median between the two, without calling uniswap
        vm.mockCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300, // roundId from real call
            1_000e8,               // price -- mocked
            block.timestamp,       // age, mocked to now to avoid stale price errors // same as from real call
            block.timestamp,       // age, mocked to now to avoid stale price errors // same as from real call
            129127208515966867300  // roundId from real call
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,           // same as from real call
            1_002e18,       // price -- mocked
            block.timestamp // age, mocked to now to avoid stale price errors // same as from real call
        ));
        vm.expectCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool,   abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_001e8);
        vm.clearMockedCalls();

        // A price query with serious divergence between Chronicle and Chainlink returns median with the uniswap TWAP as a tiebreaker
        vm.mockCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300, // same as from real call
            100e8,                 // price -- mocked
            block.timestamp,       // age, mocked to now to avoid stale price errors
            block.timestamp,       // age, mocked to now to avoid stale price errors
            129127208515966867300  // same as from real call
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,           // same as from real call
            10_002e18,      // price -- mocked
            block.timestamp // age, mocked to now to avoid stale price errors
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        // hard-coded value from arbitrary invocation, resolves to price below
        vm.mockCall(uniswapPool,       abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes( hex'000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000154f13d8762f0000000000000000000000000000000000000000000000000000154f3ddc23db00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000001ef2d176aa46749b778f6ecad0000000000000000000000000000000000000001ef2d47ebfdebcc9a40a211ad'
        ));
        vm.expectCall(uniswapPool,     abi.encodeWithSignature("observe(uint32[])", secondsAgo));
        assertEq(oracle.getAssetPrice(asset), 3_139.75501600e8);
        vm.clearMockedCalls();
    }

}
