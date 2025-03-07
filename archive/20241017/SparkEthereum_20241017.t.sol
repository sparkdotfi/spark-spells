// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/SparkTestBase.sol';

interface IMorphoChainlinkOracle {
    function price() external view returns (uint256);
}

interface IMorphoPT {
    function expiry() external view returns (uint256);
}

interface IPot {
    function chi() external view returns (uint256);
    function drip() external returns (uint256);
}

interface IPriceFeed {
    function latestAnswer() external view returns (int256);
}

contract SparkEthereum_20241017Test is SparkEthereumTestBase {

    address internal constant SUSDS            = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant SUSDS_PRICE_FEED = 0x27f3A665c75aFdf43CfbF6B3A859B698f46ef656;

    address internal constant SDAI_OLD_PRICE_FEED = 0xb9E6DBFa4De19CCed908BcbFe1d015190678AB5f;
    address internal constant SDAI_PRICE_FEED     = 0x0c0864837C7e65458aCD3C665222203217019436;

    address internal constant PT_26DEC2024_PRICE_FEED  = 0x81E5E28F33D314e9211885d6f0F4080E755e4595;
    address internal constant PT_SUSDE_26DEC2024       = 0xEe9085fC268F6727d5D4293dBABccF901ffDCC29;
    uint256 internal constant PT_SUSDE_26DEC2024_YIELD = 0.15e18;

    address internal constant PT_27MAR2025_PRICE_FEED  = 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7;
    address internal constant PT_SUSDE_27MAR2025       = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81;
    uint256 internal constant PT_SUSDE_27MAR2025_YIELD = 0.20e18;

    uint256 internal constant ONE_YEAR = 365 days;

    constructor() {
        id = '20241017';
    }

    function setUp() public {
        vm.createSelectFork(getChain('mainnet').rpcUrl, 20962410);  // Oct 14, 2024
        payload = 0xcc3B9e79261A7064A0f734Cc749A8e3762e0a187;

        loadPoolContext(poolAddressesProviderRegistry.getAddressesProvidersList()[0]);
    }

    function testPriceFeeds() public {
        vm.startPrank(Ethereum.AAVE_ORACLE);
        int256 susdsPrice = IPriceFeed(SUSDS_PRICE_FEED).latestAnswer();
        int256 sdaiPrice  = IPriceFeed(SDAI_PRICE_FEED).latestAnswer();

        assertEq(susdsPrice, 1.00450188e8);
        assertEq(sdaiPrice,  1.11322287e8);

        // Remove 19 decimals from the chi values
        assertEq(IPot(SUSDS).chi() / 1e19,        uint256(susdsPrice));
        assertEq(IPot(Ethereum.POT).chi() / 1e19, uint256(sdaiPrice));

        // Drip the pot in the future to update the chi values
        skip(100 days);
        IPot(SUSDS).drip();
        IPot(Ethereum.POT).drip();

        int256 newSusdsPrice = IPriceFeed(SUSDS_PRICE_FEED).latestAnswer();
        int256 newSdaiPrice  = IPriceFeed(SDAI_PRICE_FEED).latestAnswer();

        // Price for both feeds should have increased
        assertGt(newSusdsPrice, susdsPrice);
        assertGt(newSdaiPrice,  sdaiPrice);

        // Remove 19 decimals from the chi values
        assertEq(IPot(SUSDS).chi() / 1e19,        uint256(newSusdsPrice));
        assertEq(IPot(Ethereum.POT).chi() / 1e19, uint256(newSdaiPrice));
    }

    function testValidatePriceFeedChange() public {
        IAaveOracle oracle = IAaveOracle(Ethereum.AAVE_ORACLE);

        assertEq(oracle.getSourceOfAsset(Ethereum.SDAI), SDAI_OLD_PRICE_FEED);
        assertEq(oracle.getAssetPrice(Ethereum.SDAI),    1.11290487e8);

        executePayload(payload);

        assertEq(oracle.getSourceOfAsset(Ethereum.SDAI), SDAI_PRICE_FEED);
        assertEq(oracle.getAssetPrice(Ethereum.SDAI),    1.11322287e8);
    }

    function testCollateralOnboarding() public {
        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);

        assertEq(allConfigsBefore.length, 11);

        _assertSupplyCapConfig({
            asset:            SUSDS,
            max:              0,
            gap:              0,
            increaseCooldown: 0
        });

        _assertBorrowCapConfig({
            asset:            SUSDS,
            max:              0,
            gap:              0,
            increaseCooldown: 0
        });

        executePayload(payload);

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);

        assertEq(allConfigsAfter.length, 12);

        ReserveConfig memory susds = ReserveConfig({
            symbol:                  'sUSDS',
            underlying:               SUSDS,
            aToken:                   address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 18,
            ltv:                      79_00,
            liquidationThreshold:     80_00,
            liquidationBonus:         105_00,
            liquidationProtocolFee:   10_00,
            reserveFactor:            10_00,
            usageAsCollateralEnabled: true,
            borrowingEnabled:         false,
            interestRateStrategy:     _findReserveConfigBySymbol(allConfigsAfter, 'sUSDS').interestRateStrategy,
            stableBorrowRateEnabled:  false,
            isPaused:                 false,
            isActive:                 true,
            isFrozen:                 false,
            isSiloed:                 false,
            isBorrowableInIsolation:  false,
            isFlashloanable:          false,
            supplyCap:                50_000_000,
            borrowCap:                0,
            debtCeiling:              0,
            eModeCategory:            0
        });

        _validateReserveConfig(susds, allConfigsAfter);

        _validateInterestRateStrategy(
            susds.interestRateStrategy,
            susds.interestRateStrategy,
            InterestStrategyValues({
                addressesProvider:             address(poolAddressesProvider),
                optimalUsageRatio:             0.8e27,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          0.02e27,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        0,
                variableRateSlope1:            0.02e27,
                variableRateSlope2:            3e27
            })
        );

        _assertSupplyCapConfig({
            asset:            SUSDS,
            max:              500_000_000,
            gap:              50_000_000,
            increaseCooldown: 12 hours
        });

        _assertBorrowCapConfig({
            asset:            SUSDS,
            max:              0,
            gap:              0,
            increaseCooldown: 0
        });

        // The sUSDS price feed does not have a decimals() function so we validate manually
        IAaveOracle oracle = IAaveOracle(poolAddressesProvider.getPriceOracle());

        require(
            oracle.getSourceOfAsset(SUSDS) == SUSDS_PRICE_FEED,
            '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
        );
    }

    function testMorphoVaults() public {
        MarketParams memory ptUsde26Dec =  MarketParams({
            loanToken:       Ethereum.DAI,
            collateralToken: PT_SUSDE_26DEC2024,
            oracle:          PT_26DEC2024_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.915e18
        });

        MarketParams memory ptUsde27Mar =  MarketParams({
            loanToken:       Ethereum.DAI,
            collateralToken: PT_SUSDE_27MAR2025,
            oracle:          PT_27MAR2025_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.915e18
        });

        _assertMorphoCap(ptUsde26Dec, 0);
        _assertMorphoCap(ptUsde27Mar, 0);

        executePayload(payload);

        _assertMorphoCap(ptUsde26Dec, 0, 100_000_000e18);
        _assertMorphoCap(ptUsde27Mar, 0, 100_000_000e18);

        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).timelock(), 1 days);

        skip(1 days);

        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).acceptCap(ptUsde26Dec);
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).acceptCap(ptUsde27Mar);

        _assertMorphoCap(ptUsde26Dec, 100_000_000e18);
        _assertMorphoCap(ptUsde27Mar, 100_000_000e18);

        // Commented because of an open issue with Foundry with the evm version
        // https://github.com/foundry-rs/foundry/issues/6228
        // NOTE: Can run this test individually after commenting out these assertions with forge t --mt testMorphoVaults -vvv --evm-version cancun

        // uint256 ptUsde26DecPrice = IMorphoChainlinkOracle(PT_26DEC2024_PRICE_FEED).price();
        // uint256 ptUsde27MarPrice = IMorphoChainlinkOracle(PT_27MAR2025_PRICE_FEED).price();

        // assertEq(ptUsde26DecPrice, 0.970544002092846271e36);
        // assertEq(ptUsde27MarPrice, 0.910862322425164891e36);

        // uint256 timeSkip = 60 days;

        // skip(timeSkip);

        // uint256 newPtUsde26DecPrice = IMorphoChainlinkOracle(PT_26DEC2024_PRICE_FEED).price();
        // uint256 newPtUsde27MarPrice = IMorphoChainlinkOracle(PT_27MAR2025_PRICE_FEED).price();

        // // Price for both feeds increases over time
        // assertGt(newPtUsde26DecPrice, ptUsde26DecPrice);
        // assertGt(newPtUsde27MarPrice, ptUsde27MarPrice);

        // uint256 ptUsde26DecYearlyPriceIncrease = (newPtUsde26DecPrice - ptUsde26DecPrice) * ONE_YEAR / (timeSkip);
        // uint256 ptUsde27MarYearlyPriceIncrease = (newPtUsde27MarPrice - ptUsde27MarPrice) * ONE_YEAR / (timeSkip);

        // // Calculated yield should equal the expected one
        // assertApproxEqAbs(ptUsde26DecYearlyPriceIncrease / 1e18, PT_SUSDE_26DEC2024_YIELD, 4);
        // assertApproxEqAbs(ptUsde27MarYearlyPriceIncrease / 1e18, PT_SUSDE_27MAR2025_YIELD, 4);

        // assertLt(IMorphoChainlinkOracle(PT_26DEC2024_PRICE_FEED).price(), 1e36);

        // // Prices on maturity should be 1e36
        // vm.warp(IMorphoPT(PT_SUSDE_26DEC2024).expiry());
        // assertLt(IMorphoChainlinkOracle(PT_27MAR2025_PRICE_FEED).price(), 1e36);
        // assertEq(IMorphoChainlinkOracle(PT_26DEC2024_PRICE_FEED).price(), 1e36);

        // vm.warp(IMorphoPT(PT_SUSDE_27MAR2025).expiry());
        // assertEq(IMorphoChainlinkOracle(PT_27MAR2025_PRICE_FEED).price(), 1e36);

        // skip(ONE_YEAR);

        // // Prices should remain to be 1e36
        // assertEq(IMorphoChainlinkOracle(PT_26DEC2024_PRICE_FEED).price(), 1e36);
        // assertEq(IMorphoChainlinkOracle(PT_27MAR2025_PRICE_FEED).price(), 1e36);
    }

    function testWBTCChanges() public {
        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);

        ReserveConfig memory wbtcConfig = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(wbtcConfig.liquidationThreshold,   75_00);
        assertEq(wbtcConfig.liquidationProtocolFee, 10_00);

        _assertSupplyCapConfig({
            asset:            Ethereum.WBTC,
            max:              10_000,
            gap:              500,
            increaseCooldown: 12 hours
        });

        _assertBorrowCapConfig({
            asset:            Ethereum.WBTC,
            max:              2_000,
            gap:              100,
            increaseCooldown: 12 hours
        });

        executePayload(payload);

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);

        wbtcConfig.liquidationThreshold   = 70_00;
        wbtcConfig.liquidationProtocolFee = 0;

        _validateReserveConfig(wbtcConfig, allConfigsAfter);

        _assertSupplyCapConfig({
            asset:            Ethereum.WBTC,
            max:              5_000,
            gap:              200,
            increaseCooldown: 12 hours
        });

        _assertBorrowCapConfig({
            asset:            Ethereum.WBTC,
            max:              1,
            gap:              1,
            increaseCooldown: 12 hours
        });
    }
}
