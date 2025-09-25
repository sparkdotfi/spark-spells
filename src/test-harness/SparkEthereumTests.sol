// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, PendingUint192, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }          from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorphoChainlinkOracleV2 } from "morpho-blue-oracles/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol";

import { PendleSparkLinearDiscountOracle } from "pendle-core-v2-public/oracles/internal/PendleSparkLinearDiscountOracle.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MorphoUpgradableOracle }                                     from "sparklend-advanced/src/MorphoUpgradableOracle.sol";
import { IPoolAddressesProvider, RateTargetKinkInterestRateStrategy } from "sparklend-advanced/src/RateTargetKinkInterestRateStrategy.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { ISparkLendFreezerMom } from "sparklend-freezer/interfaces/ISparkLendFreezerMom.sol";

import { IScaledBalanceToken }             from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";
import { IncentivizedERC20 }               from "sparklend-v1-core/protocol/tokenization/base/IncentivizedERC20.sol";
import { ReserveConfiguration, DataTypes } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }                      from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    IAuthorityLike,
    ICustomIRMLike,
    IExecutableLike,
    IMorphoLike,
    IMorphoOracleFactoryLike,
    IPendleLinearDiscountOracleLike,
    IRateSourceLike,
    ISparkProxyLike,
    ITargetBaseIRMLike,
    ITargetKinkIRMLike
} from "../interfaces/Interfaces.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SLLHelpers }            from "../libraries/SLLHelpers.sol";

import { SparklendTests }           from "./SparklendTests.sol";
import { SparkLiquidityLayerTests } from "./SparkLiquidityLayerTests.sol";

// TODO: MDL, only used by `SparkTestBase`.
/// @dev assertions specific to mainnet
/// TODO: separate tests related to sparklend from the rest (eg: morpho)
///       also separate mainnet-specific sparklend tests from those we should
///       run on Gnosis as well
abstract contract SparkEthereumTests is SparklendTests, SparkLiquidityLayerTests {

    using RecordedLogs for *;

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    struct RateTargetBaseIRMParams {
        address irm;
        uint256 baseRateSpread;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
        uint256 optimalUsageRatio;
    }

    struct RateTargetKinkIRMParams {
        address irm;
        uint256 baseRate;
        int256  variableRateSlope1Spread;
        uint256 variableRateSlope2;
        uint256 optimalUsageRatio;
    }

    struct SparkLendAssetOnboardingParams {
        // General
        string  symbol;
        address tokenAddress;
        address oracleAddress;
        bool    collateralEnabled;

        // IRM Params
        uint256 optimalUsageRatio;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;

        // Borrowing configuration
        bool borrowEnabled;
        bool stableBorrowEnabled;
        bool isolationBorrowEnabled;
        bool siloedBorrowEnabled;
        bool flashloanEnabled;

        // Reserve configuration
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;

        // Supply and borrow caps
        uint48 supplyCap;
        uint48 supplyCapMax;
        uint48 supplyCapGap;
        uint48 supplyCapTtl;
        uint48 borrowCap;
        uint48 borrowCapMax;
        uint48 borrowCapGap;
        uint48 borrowCapTtl;

        // Isolation and emode configurations
        bool    isolationMode;
        uint256 isolationModeDebtCeiling;
        uint256 liquidationProtocolFee;
        uint256 emodeCategory;
    }

    address internal constant MORPHO_ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_FreezerMom() external onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTests();

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runFreezerMomTests();
    }

    function test_ETHEREUM_FreezerMom_Multisig() external onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTestsMultisig();

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runFreezerMomTestsMultisig();
    }

    function test_ETHEREUM_SparkProxyStorage() external onChain(ChainIdUtils.Ethereum()) {
        ISparkProxyLike proxy = ISparkProxyLike(Ethereum.SPARK_PROXY);
        address         ESM   = 0x09e05fF6142F2f9de8B6B65855A1d56B6cfE4c58;

        assertEq(proxy.wards(ESM),                  1);
        assertEq(proxy.wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(address(proxy), 100);
        _executeAllPayloadsAndBridges();

        assertEq(proxy.wards(ESM),                  1);
        assertEq(proxy.wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(address(proxy), 100);
    }

    function test_ETHEREUM_RewardsConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        _runRewardsConfigurationTests();
        _executeAllPayloadsAndBridges();
        _runRewardsConfigurationTests();
    }

    function test_ETHEREUM_CapAutomator() external onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runCapAutomatorTests();

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runCapAutomatorTests();
    }

    function test_ETHEREUM_PayloadsConfigured() external onChain(ChainIdUtils.Ethereum()) {
         for (uint256 i = 0; i < allChains.length; ++i) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);

            if (chainId == ChainIdUtils.Ethereum()) continue;  // Checking only foreign payloads

            address payload = chainData[chainId].payload;

            if (payload == address(0)) continue;

            // A payload is defined for this domain
            // We verify the mainnet spell defines this payload correctly
            address mainnetPayload = _getForeignPayloadFromMainnetSpell(chainId);
            assertEq(mainnetPayload, payload, "Mainnet payload not matching deployed payload");
        }
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _voteAndCast(address _spell) internal {
        IAuthorityLike authority = IAuthorityLike(Ethereum.CHIEF);

        address skyWhale = makeAddr("skyWhale");
        uint256 amount   = 10_000_000_000 ether;

        deal(Ethereum.SKY, skyWhale, amount);

        vm.startPrank(skyWhale);

        IERC20(Ethereum.SKY).approve(address(authority), amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = _spell;

        authority.vote(slate);

        // Min amount of blocks to pass to vote again.
        vm.roll(block.number + 11);

        authority.lift(_spell);

        vm.stopPrank();

        assertEq(authority.hat(), _spell);

        vm.prank(makeAddr("randomUser"));
        IExecutableLike(_spell).execute();
    }

    function _runFreezerMomTestsMultisig() internal {
        ISparkLendFreezerMom freezerMom = ISparkLendFreezerMom(Ethereum.FREEZER_MOM);

        // Sanity checks - cannot call Freezer Mom unless you have the hat or wards access
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeMarket(Ethereum.DAI, true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeAllMarkets(true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseMarket(Ethereum.DAI, true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseAllMarkets(true);

        vm.startPrank(Ethereum.FREEZER_MULTISIG);

        _assertFrozen(Ethereum.DAI,  false);
        _assertFrozen(Ethereum.WETH, false);

        freezerMom.freezeMarket(Ethereum.DAI, true);

        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, false);

        freezerMom.freezeAllMarkets(true);

        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, true);

        _assertPaused(Ethereum.DAI,  false);
        _assertPaused(Ethereum.WETH, false);

        freezerMom.pauseMarket(Ethereum.DAI, true);

        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, false);

        freezerMom.pauseAllMarkets(true);

        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, true);

        vm.stopPrank();
    }

    function _runFreezerMomTests() internal {
        ISparkLendFreezerMom freezerMom = ISparkLendFreezerMom(Ethereum.FREEZER_MOM);

        // Sanity checks - cannot call Freezer Mom unless you have the hat or wards access
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeMarket(Ethereum.DAI, true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeAllMarkets(true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseMarket(Ethereum.DAI, true);

        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseAllMarkets(true);

        _assertFrozen(Ethereum.DAI,  false);
        _assertFrozen(Ethereum.WETH, false);

        _voteAndCast(Ethereum.SPELL_FREEZE_DAI);

        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, false);

        _voteAndCast(Ethereum.SPELL_FREEZE_ALL);

        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, true);

        _assertPaused(Ethereum.DAI,  false);
        _assertPaused(Ethereum.WETH, false);

        _voteAndCast(Ethereum.SPELL_PAUSE_DAI);

        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, false);

        _voteAndCast(Ethereum.SPELL_PAUSE_ALL);

        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, true);
    }

    function _runCapAutomatorTests() internal {
        address[] memory reserves = _getSparkLendContext().pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            _assertAutomatedCapsUpdate(reserves[i]);
        }
    }

    function _assertAutomatedCapsUpdate(address asset) internal {
        SparkLendContext      memory ctx               = _getSparkLendContext();
        DataTypes.ReserveData memory reserveDataBefore = ctx.pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        (,,,,uint48 supplyCapLastIncreaseTime) = capAutomator.supplyCapConfigs(asset);
        (,,,,uint48 borrowCapLastIncreaseTime) = capAutomator.borrowCapConfigs(asset);

        capAutomator.exec(asset);

        DataTypes.ReserveData memory reserveDataAfter = ctx.pool.getReserveData(asset);

        uint256 supplyCapAfter = reserveDataAfter.configuration.getSupplyCap();
        uint256 borrowCapAfter = reserveDataAfter.configuration.getBorrowCap();

        uint48 max;
        uint48 gap;
        uint48 cooldown;

        (max, gap, cooldown,,) = capAutomator.supplyCapConfigs(asset);

        if (max > 0) {
            uint256 currentSupply = (IScaledBalanceToken(reserveDataAfter.aTokenAddress).scaledTotalSupply() + uint256(reserveDataAfter.accruedToTreasury))
                .rayMul(reserveDataAfter.liquidityIndex)
                / 10 ** IERC20(reserveDataAfter.aTokenAddress).decimals();

            uint256 expectedSupplyCap = uint256(max) < currentSupply + uint256(gap)
                ? uint256(max)
                : currentSupply + uint256(gap);

            if (supplyCapLastIncreaseTime + cooldown > block.timestamp && supplyCapBefore < expectedSupplyCap) {
                assertEq(supplyCapAfter, supplyCapBefore);
            } else {
                assertEq(supplyCapAfter, expectedSupplyCap);
            }
        } else {
            assertEq(supplyCapAfter, supplyCapBefore);
        }

        (max, gap, cooldown,,) = capAutomator.borrowCapConfigs(asset);

        if (max > 0) {
            uint256 currentBorrows = IERC20(reserveDataAfter.variableDebtTokenAddress).totalSupply() / 10 ** IERC20(reserveDataAfter.variableDebtTokenAddress).decimals();

            uint256 expectedBorrowCap = uint256(max) < currentBorrows + uint256(gap)
                ? uint256(max)
                : currentBorrows + uint256(gap);

            if (borrowCapLastIncreaseTime + cooldown > block.timestamp && borrowCapBefore < expectedBorrowCap) {
                assertEq(borrowCapAfter, borrowCapBefore);
            } else {
                assertEq(borrowCapAfter, expectedBorrowCap);
            }
        } else {
            assertEq(borrowCapAfter, borrowCapBefore);
        }
    }

    function _testAssetOnboardings(SparkLendAssetOnboardingParams[] memory collaterals) internal {
        SparkLendContext memory ctx              = _getSparkLendContext();
        ReserveConfig[]  memory allConfigsBefore = _createConfigurationSnapshot("", ctx.pool);

        uint256 startingReserveLength = allConfigsBefore.length;

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot("", ctx.pool);

        assertEq(allConfigsAfter.length, startingReserveLength + collaterals.length);

        for (uint256 i = 0; i < collaterals.length; ++i) {
            _testAssetOnboarding(allConfigsAfter, collaterals[i]);
        }
    }

    function _testAssetOnboarding(
        ReserveConfig[]                memory allReserveConfigs,
        SparkLendAssetOnboardingParams memory params
    )
        internal view
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        address irm = _findReserveConfigBySymbol(allReserveConfigs, params.symbol).interestRateStrategy;

        ReserveConfig memory reserveConfig = ReserveConfig({
            symbol:                   params.symbol,
            underlying:               params.tokenAddress,
            aToken:                   address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            variableDebtToken:        address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            stableDebtToken:          address(0),  // Mock, as they don't get validated, because of the "dynamic" deployment on proposal execution
            decimals:                 IERC20(params.tokenAddress).decimals(),
            ltv:                      params.ltv,
            liquidationThreshold:     params.liquidationThreshold,
            liquidationBonus:         params.liquidationBonus,
            liquidationProtocolFee:   params.liquidationProtocolFee,
            reserveFactor:            params.reserveFactor,
            usageAsCollateralEnabled: params.collateralEnabled,
            borrowingEnabled:         params.borrowEnabled,
            interestRateStrategy:     irm,
            stableBorrowRateEnabled:  false,
            isPaused:                 false,
            isActive:                 true,
            isFrozen:                 false,
            isSiloed:                 params.siloedBorrowEnabled,
            isBorrowableInIsolation:  params.isolationBorrowEnabled,
            isFlashloanable:          params.flashloanEnabled,
            supplyCap:                params.supplyCap,
            borrowCap:                params.borrowCap,
            debtCeiling:              params.isolationModeDebtCeiling,
            eModeCategory:            params.emodeCategory
        });

        InterestStrategyValues memory irmParams = InterestStrategyValues({
            addressesProvider:             address(ctx.poolAddressesProvider),
            optimalUsageRatio:             params.optimalUsageRatio,
            optimalStableToTotalDebtRatio: 0,
            baseStableBorrowRate:          params.variableRateSlope1,
            stableRateSlope1:              0,
            stableRateSlope2:              0,
            baseVariableBorrowRate:        params.baseVariableBorrowRate,
            variableRateSlope1:            params.variableRateSlope1,
            variableRateSlope2:            params.variableRateSlope2
        });

        _validateReserveConfig(reserveConfig, allReserveConfigs);
        _validateInterestRateStrategy(irm, irm, irmParams);

        _assertSupplyCapConfig({
            asset:            params.tokenAddress,
            max:              params.supplyCapMax,
            gap:              params.supplyCapGap,
            increaseCooldown: params.supplyCapTtl
        });

        _assertBorrowCapConfig({
            asset:            params.tokenAddress,
            max:              params.borrowCapMax,
            gap:              params.borrowCapGap,
            increaseCooldown: params.borrowCapTtl
        });

        require(
            ctx.priceOracle.getSourceOfAsset(params.tokenAddress) == params.oracleAddress,
            "_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE"
        );
    }

    function _testMorphoCapUpdate(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             newCap
    )
        internal
    {
        _assertMorphoCap(vault, config, currentCap);
        _executeAllPayloadsAndBridges();

        if (newCap > currentCap) {
            // Increases are timelocked
            _assertMorphoCap(vault, config, currentCap, newCap);

            assertEq(IMetaMorpho(vault).timelock(), 1 days);

            skip(1 days);

            IMetaMorpho(vault).acceptCap(config);

            _assertMorphoCap(vault, config, newCap);
        } else {
            // Decreases are immediate
            _assertMorphoCap(vault, config, newCap);
        }

        // Check total assets in the morpho market are greater than 1 unit of the loan token
        ( uint256 totalSupplyAssets_,,,,, ) = IMorphoLike(Ethereum.MORPHO).market(MarketParamsLib.id(config));
        assertGe(totalSupplyAssets_, 10 ** IERC20(config.loanToken).decimals());

        // Check shares of address(1) are greater or equal to 1e6 * 10 ** loanTokenDecimals (1 unit)
        IMorphoLike.Position memory position = IMorphoLike(Ethereum.MORPHO).position(MarketParamsLib.id(config), address(1));
        assertGe(position.supplyShares, 10 ** IERC20(config.loanToken).decimals() * 1e6);
    }

    function _testMorphoPendlePTOracleConfig(
        address pt,
        address loanToken,
        address oracle,
        uint256 discount,
        uint256 maturity
    )
        internal
    {
        IMorphoChainlinkOracleV2        oracle_      = IMorphoChainlinkOracleV2(oracle);
        MorphoUpgradableOracle          baseFeed     = MorphoUpgradableOracle(address(oracle_.BASE_FEED_1()));
        IPendleLinearDiscountOracleLike pendleOracle = IPendleLinearDiscountOracleLike(address(baseFeed.source()));

        // TODO: This assumes loanTokenDecimals >= ptDecimals, fix for the other case.
        uint256 assetConversion = 10 ** (IERC20(loanToken).decimals() - IERC20(pt).decimals());

        assertEq(address(oracle_.BASE_FEED_2()),          address(0));
        assertEq(address(oracle_.BASE_VAULT()),           address(0));
        assertEq(oracle_.BASE_VAULT_CONVERSION_SAMPLE(),  1);
        assertEq(address(oracle_.QUOTE_FEED_1()),         address(0));
        assertEq(address(oracle_.QUOTE_FEED_2()),         address(0));
        assertEq(address(oracle_.QUOTE_VAULT()),          address(0));
        assertEq(oracle_.QUOTE_VAULT_CONVERSION_SAMPLE(), 1);
        assertEq(oracle_.SCALE_FACTOR(),                  1e36 * assetConversion / 10 ** (IERC20(address(baseFeed)).decimals()));
        assertGe(oracle_.price(),                         0.01e36);
        assertLe(oracle_.price(),                         1e36 * assetConversion);

        assertEq(pendleOracle.PT(),                  pt);
        assertEq(pendleOracle.baseDiscountPerYear(), discount);
        assertEq(pendleOracle.maturity(),            maturity);
        assertEq(pendleOracle.getDiscount(365 days), discount);

        assertEq(baseFeed.owner(),           Ethereum.SPARK_PROXY);
        assertEq(address(baseFeed.source()), address(pendleOracle));
        assertEq(baseFeed.decimals(),        pendleOracle.decimals());

        ( , int256 pendlePrice,,, )   = pendleOracle.latestRoundData();
        ( , int256 baseFeedPrice,,, ) = baseFeed.latestRoundData();

        assertEq(baseFeedPrice, pendlePrice);

        uint256 blockTime = block.timestamp;
        uint256 price     = oracle_.price();

        vm.warp(blockTime + 1 days);

        assertApproxEqAbs(uint256(oracle_.price() - price) / 1e18, uint256(0.15e18) / 365, 1);

        vm.warp(maturity - 1 seconds);

        assertLe(oracle_.price(), 1e36 * assetConversion);

        vm.warp(maturity);

        assertEq(oracle_.price(), 1e36 * assetConversion);

        assertTrue(IMorphoOracleFactoryLike(MORPHO_ORACLE_FACTORY).isMorphoChainlinkOracleV2(address(oracle_)));

        address expectedPendleOracle = address(new PendleSparkLinearDiscountOracle(pt, discount));

        _assertBytecodeMatches(expectedPendleOracle, address(pendleOracle));

        address expectedBaseFeed = address(new MorphoUpgradableOracle{salt: bytes32(0)}(Ethereum.SPARK_PROXY, address(pendleOracle)));

        _assertBytecodeMatches(expectedBaseFeed, address(baseFeed));
    }

    function _testRateTargetBaseIRMUpdate(
        string                  memory symbol,
        RateTargetBaseIRMParams memory oldParams,
        RateTargetBaseIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRMLike(newParams.irm).RATE_SOURCE(), ICustomIRMLike(oldParams.irm).RATE_SOURCE());

        uint256 ssrRate = uint256(IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).getAPR());

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          oldParams.variableRateSlope1,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        ssrRate + oldParams.baseRateSpread,
                variableRateSlope1:            oldParams.variableRateSlope1,
                variableRateSlope2:            oldParams.variableRateSlope2
            })
        );

        assertEq(ITargetBaseIRMLike(configBefore.interestRateStrategy).getBaseVariableBorrowRateSpread(), oldParams.baseRateSpread);

        _executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             newParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          newParams.variableRateSlope1,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        ssrRate + newParams.baseRateSpread,
                variableRateSlope1:            newParams.variableRateSlope1,
                variableRateSlope2:            newParams.variableRateSlope2
            })
        );

        assertEq(ITargetBaseIRMLike(configAfter.interestRateStrategy).getBaseVariableBorrowRateSpread(), newParams.baseRateSpread);
    }

    function _testRateTargetKinkIRMUpdate(
        string                  memory symbol,
        RateTargetKinkIRMParams memory oldParams,
        RateTargetKinkIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRMLike(newParams.irm).RATE_SOURCE(), ICustomIRMLike(oldParams.irm).RATE_SOURCE());

        uint256 ssrRateDecimals = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).decimals();

        int256 ssrRate = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).getAPR() * int256(10 ** (27 - ssrRateDecimals));

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + oldParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        oldParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + oldParams.variableRateSlope1Spread),
                variableRateSlope2:            oldParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configBefore.interestRateStrategy).getVariableRateSlope1Spread()), uint256(oldParams.variableRateSlope1Spread));

        _executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             newParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + newParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        newParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + newParams.variableRateSlope1Spread),
                variableRateSlope2:            newParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configAfter.interestRateStrategy).getVariableRateSlope1Spread()), uint256(newParams.variableRateSlope1Spread));

        address expectedIRM = address(new RateTargetKinkInterestRateStrategy(
            IPoolAddressesProvider(address(ctx.poolAddressesProvider)),
            ICustomIRMLike(newParams.irm).RATE_SOURCE(),
            newParams.optimalUsageRatio,
            newParams.baseRate,
            newParams.variableRateSlope1Spread,
            newParams.variableRateSlope2
        ));

        _assertBytecodeMatches(expectedIRM, newParams.irm);
    }

    function _testMorphoVaultCreation(
        address               asset,
        string         memory name,
        string         memory symbol,
        MarketParams[] memory markets,
        uint256[]      memory caps,
        uint256               vaultFee,
        uint256               initialDeposit,
        uint256               sllDepositMax,
        uint256               sllDepositSlope
    )
        internal
    {
        require(markets.length == caps.length, "Markets and caps length mismatch");

        // TODO: make constant.
        bytes32 createMetaMorphoSig = keccak256("CreateMetaMorpho(address,address,address,uint256,address,string,string,bytes32)");

        // Start the recorder
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        VmSafe.Log[] memory allLogs = RecordedLogs.getLogs();

        // TODO: make below loop a getter with a return to make this all cleaner. Possibly incorporating the zero check.
        address vault;

        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics[0] == createMetaMorphoSig) {
                vault = address(uint160(uint256(allLogs[i].topics[1])));
                break;
            }
        }

        require(vault != address(0), "Vault not found");

        assertEq(IMetaMorpho(vault).asset(),                           asset);
        assertEq(IMetaMorpho(vault).name(),                            name);
        assertEq(IMetaMorpho(vault).symbol(),                          symbol);
        assertEq(IMetaMorpho(vault).timelock(),                        1 days);
        assertEq(IMetaMorpho(vault).isAllocator(Ethereum.ALM_RELAYER), true);
        assertEq(IMetaMorpho(vault).supplyQueueLength(),               1);
        assertEq(IMetaMorpho(vault).owner(),                           Ethereum.SPARK_PROXY);
        assertEq(IMetaMorpho(vault).feeRecipient(),                    Ethereum.ALM_PROXY);
        assertEq(IMetaMorpho(vault).fee(),                             vaultFee);

        for (uint256 i = 0; i < markets.length; ++i) {
            _assertMorphoCap(vault, markets[i], caps[i]);
        }

        assertEq(
            Id.unwrap(IMetaMorpho(vault).supplyQueue(0)),
            Id.unwrap(MarketParamsLib.id(SLLHelpers.morphoIdleMarket(asset)))
        );

        _assertMorphoCap(vault, SLLHelpers.morphoIdleMarket(asset), type(uint184).max);

        assertEq(IMetaMorpho(vault).totalAssets(),    initialDeposit);
        assertEq(IERC20(vault).balanceOf(address(1)), initialDeposit * 1e18 / 10 ** IERC20(asset).decimals());

        if (sllDepositMax == 0 || sllDepositSlope == 0) return;

        _testERC4626Onboarding(vault, sllDepositMax / 10, sllDepositMax, sllDepositSlope, 10, true);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _checkStorageSlot(address target, uint256 limit) internal view {
        for (uint256 slot; slot < limit; ++slot) {
            bytes32 result = vm.load(address(target), bytes32(uint256(slot)));
            require(result == bytes32(0), "Slot is not zero");
        }
    }

    function _runRewardsConfigurationTests() internal view {
        SparkLendContext memory ctx      = _getSparkLendContext();
        address[]        memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            DataTypes.ReserveData memory reserveData = ctx.pool.getReserveData(reserves[i]);

            assertEq(address(IncentivizedERC20(reserveData.aTokenAddress).getIncentivesController()),            Ethereum.INCENTIVES);
            assertEq(address(IncentivizedERC20(reserveData.variableDebtTokenAddress).getIncentivesController()), Ethereum.INCENTIVES);
        }
    }

    function _assertFrozen(address asset, bool frozen) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getFrozen(), frozen);
    }

    function _assertPaused(address asset, bool paused) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getPaused(), paused);
    }

    function _assertBorrowCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        (
            uint48 max_,
            uint48 gap_,
            uint48 increaseCooldown_,
            , // lastUpdateBlock
              // lastIncreaseTime
        ) = ICapAutomator(Ethereum.CAP_AUTOMATOR).borrowCapConfigs(asset);

        assertEq(max_,              max);
        assertEq(gap_,              gap);
        assertEq(increaseCooldown_, increaseCooldown);
    }

    function _assertBorrowCapConfigNotSet(address asset) internal view {
        _assertBorrowCapConfig(asset, 0, 0, 0);
    }

    function _assertSupplyCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        (
            uint48 _max,
            uint48 _gap,
            uint48 _increaseCooldown,
            , // lastUpdateBlock
              // lastIncreaseTime
        ) = ICapAutomator(Ethereum.CAP_AUTOMATOR).supplyCapConfigs(asset);

        assertEq(_max,              max);
        assertEq(_gap,              gap);
        assertEq(_increaseCooldown, increaseCooldown);
    }

    function _assertSupplyCapConfigNotSet(address asset) internal view {
        _assertSupplyCapConfig(asset, 0, 0, 0);
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        bool                hasPending,
        uint256             pendingCap
    ) internal view {
        Id id = MarketParamsLib.id(config);

        assertEq(IMetaMorpho(vault).config(id).cap, currentCap);

        PendingUint192 memory pendingCap_ = IMetaMorpho(vault).pendingCap(id);

        if (hasPending) {
            assertEq(pendingCap_.value,   pendingCap);
            assertGt(pendingCap_.validAt, 0);
        } else {
            assertEq(pendingCap_.value,   0);
            assertEq(pendingCap_.validAt, 0);
        }
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             pendingCap
    ) internal view {
        _assertMorphoCap(vault, config, currentCap, true, pendingCap);
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap
    ) internal view {
        _assertMorphoCap(vault, config, currentCap, false, 0);
    }

}
