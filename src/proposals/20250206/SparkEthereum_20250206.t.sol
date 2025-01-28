// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum }              from 'spark-address-registry/Ethereum.sol';
import { Base }                  from 'spark-address-registry/Base.sol';
import { MainnetController }     from 'spark-alm-controller/src/MainnetController.sol';
import { ForeignController }     from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }           from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { RateLimitHelpers }      from 'spark-alm-controller/src/RateLimitHelpers.sol';
import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { DataTypes }             from 'sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol';
import { IAaveOracle }           from 'sparklend-v1-core/contracts/interfaces/IAaveOracle.sol';
import { IMetaMorpho }           from 'lib/metamorpho/src/interfaces/IMetaMorpho.sol';

import { SparkTestBase } from 'src/SparkTestBase.sol';
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';
import { ReserveConfig } from '../../ProtocolV3TestBase.sol';

contract SparkEthereum_20250206Test is SparkTestBase {
    using DomainHelpers for Domain;

    address public immutable MAINNET_FLUID_SUSDS_VAULT = 0x2BBE31d63E6813E3AC858C04dae43FB2a72B0D11;
    address public immutable BASE_FLUID_SUSDS_VAULT    = 0xf62e339f21d8018940f188F6987Bcdf02A849619;

    address public immutable PREVIOUS_WETH_PRICEFEED = 0xf07ca0e66A798547E4CB3899EC592e1E99Ef6Cb3;
    address public immutable NEW_WETH_PRICEFEED      = 0x2750e4CB635aF1FCCFB10C0eA54B5b5bfC2759b6;
    address public immutable WETH_CHAINLINK_SOURCE   = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public immutable WETH_CHRONICLE_SOURCE   = 0x46ef0071b1E2fF6B42d36e5A177EA43Ae5917f4E;
    address public immutable WETH_REDSTONE_SOURCE    = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
    address public immutable WETH_UNISWAP_SOURCE     = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    constructor() {
        id = '20250206';
    }

    function setUp() public {
        setupDomains({
            mainnetForkBlock: 21717490,
            baseForkBlock:    25607987,
            gnosisForkBlock:  38037888
        });

        deployPayloads();
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

        assertEq(oracle.getSourceOfAsset(Ethereum.WETH), PREVIOUS_WETH_PRICEFEED);

        uint256 WETHPrice = oracle.getAssetPrice(Ethereum.WETH);
        // sanity checks on pre-existing price
        assertEq(WETHPrice,   3_081.90250000e8);

        _assertPreviousPricefeedBehaviour({
            asset: Ethereum.WETH,
            chainlinkSource: WETH_CHAINLINK_SOURCE,
            chronicleSource: WETH_CHRONICLE_SOURCE,
            uniswapPool: WETH_UNISWAP_SOURCE
        });

        executeAllPayloadsAndBridges();

        // sanity check on new price
        uint256 WETHPriceAfter  = oracle.getAssetPrice(Ethereum.WETH);
        assertEq(oracle.getSourceOfAsset(Ethereum.WETH), NEW_WETH_PRICEFEED);
        assertEq(WETHPriceAfter,  3_078.82000000e8);

        _assertNewPricefeedBehaviour({
            asset: Ethereum.WETH,
            chainlinkSource: WETH_CHAINLINK_SOURCE,
            chronicleSource: WETH_CHRONICLE_SOURCE,
            uniswapPool: WETH_UNISWAP_SOURCE,
            redstoneSource: WETH_REDSTONE_SOURCE
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

        _assertRateLimit(depositKey, 10_000_000e18, uint256(5_000_000e18) / 1 days);
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

    // TODO: question, is the timeout local to the USDC asset or global to the vault? 
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
            1,          // same as real call
            1_003e8,    // price -- mocked
            1738000379, // same as real call
            1738000379, // same as real call
            1           // same as real call
        ));
        vm.expectCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chainlinkSource,   abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300 ,
            1_000e8 , // price -- mocked
            1738000480 ,
            1738000499 ,
            129127208515966867300
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,      // same as from real call
            1_002e18,  // price -- mocked
            1737996515 // same as from real call
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool, abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_002e8);
        vm.clearMockedCalls();

        // A price query with serious divergence between Chronicle and Chainlink still returns the three source median, without calling uniswap
        vm.mockCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            1,          // same as real call
            3e8,        // price -- mocked
            1738000379, // same as real call
            1738000379, // same as real call
            1           // same as real call
        ));
        vm.expectCall(redstoneSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chainlinkSource,   abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300 ,
            1_000e8 , // price -- mocked
            1738000480 ,
            1738000499 ,
            129127208515966867300
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,      // same as from real call
            99_000e18, // price -- mocked
            1737996515 // same as from real call
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool, abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_000e8);
        vm.clearMockedCalls();
    }

    function _assertPreviousPricefeedBehaviour(
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
            129127208515966867300 ,
            1_000e8 , // price -- mocked
            1738000480 ,
            1738000499 ,
            129127208515966867300
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,      // same as from real call
            1_002e18,   // price -- mocked
            1737996515 // same as from real call
        ));
        vm.expectCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"));
        vm.mockCallRevert(uniswapPool,   abi.encodeWithSignature("observe(uint32[])", secondsAgo), bytes("uniswap should not be called"));
        assertEq(oracle.getAssetPrice(asset), 1_001e8);
        vm.clearMockedCalls();

        // A price query with serious divergence between Chronicle and Chainlink returns median with the uniswap TWAP as a tiebreaker
        vm.mockCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"),abi.encode(
            129127208515966867300, // same as from real call
            100e8,                 // price -- mocked
            1738000480,            // same as from real call
            1738000499,            // same as from real call
            129127208515966867300  // same as from real call
        ));
        vm.expectCall(chainlinkSource, abi.encodeWithSignature("latestRoundData()"));
        vm.mockCall(chronicleSource,   abi.encodeWithSignature("tryReadWithAge()"),abi.encode(
            true,      // same as from real call
            10_002e18, // price -- mocked
            1737996515 // same as from real call
        ));
        vm.expectCall(chronicleSource, abi.encodeWithSignature("tryReadWithAge()"));
        // not mocking this since mocked values above guarantee the uniswap pricefeed is the middle one
        vm.expectCall(uniswapPool,     abi.encodeWithSignature("observe(uint32[])", secondsAgo));
        assertEq(oracle.getAssetPrice(asset), 3_085.28998500e8);
        vm.clearMockedCalls();
    }

}
