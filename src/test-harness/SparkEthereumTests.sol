// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Address } from '../libraries/Address.sol';

import { IScaledBalanceToken }             from "sparklend-v1-core/contracts/interfaces/IScaledBalanceToken.sol";
import { IncentivizedERC20 }               from 'sparklend-v1-core/contracts/protocol/tokenization/base/IncentivizedERC20.sol';
import { ReserveConfiguration, DataTypes } from 'sparklend-v1-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import { WadRayMath }                      from "sparklend-v1-core/contracts/protocol/libraries/math/WadRayMath.sol";

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

import { IMetaMorpho, MarketParams, PendingUint192, Id } from 'metamorpho/interfaces/IMetaMorpho.sol';
import { MarketParamsLib }                               from 'morpho-blue/src/libraries/MarketParamsLib.sol';
import { IMorphoChainlinkOracleV2 }                      from 'morpho-blue-oracles/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IDefaultInterestRateStrategy } from 'sparklend-v1-core/contracts/interfaces/IDefaultInterestRateStrategy.sol';

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";

import { InterestStrategyValues, ReserveConfig } from 'src/test-harness/ProtocolV3TestBase.sol';

import { SparklendTests, SparkLendContext } from "./SparklendTests.sol";

import {console} from "forge-std/console.sol";

interface IAuthority {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
    function hat() external view returns (address);
    function lock(uint256 amount) external;
    function vote(address[] calldata slate) external;
    function lift(address target) external;
}

interface IExecutable {
    function execute() external;
}

interface ICustomIRM {
    function RATE_SOURCE() external view returns (address);
    function getBaseVariableBorrowRateSpread() external view returns (uint256);
}

interface IRateSource {
    function getAPR() external view returns (int256);
}

interface IPendleLinearDiscountOracle {
    function PT() external view returns (address);
    function baseDiscountPerYear() external view returns (uint256);
}

interface ITargetBaseIRM {
    function getBaseVariableBorrowRateSpread() external view returns (uint256);
}

interface ITargetKinkIRM {
    function getVariableRateSlope1Spread() external view returns (uint256);
}

/// @dev assertions specific to mainnet
/// TODO: separate tests related to sparklend from the rest (eg: morpho)
///       also separate mainnet-specific sparklend tests from those we should
///       run on Gnosis as well
abstract contract SparkEthereumTests is SparklendTests {

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

    function test_ETHEREUM_FreezerMom() public virtual onChain(ChainIdUtils.Ethereum()){
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTests();

        vm.revertTo(snapshot);
        executeAllPayloadsAndBridges();

        _runFreezerMomTests();
    }

    function test_ETHEREUM_FreezerMom_Multisig() public virtual onChain(ChainIdUtils.Ethereum()){
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTestsMultisig();

        vm.revertTo(snapshot);
        executeAllPayloadsAndBridges();

        _runFreezerMomTestsMultisig();
    }

    function test_ETHEREUM_RewardsConfiguration() public onChain(ChainIdUtils.Ethereum()){
        _runRewardsConfigurationTests();

        executeAllPayloadsAndBridges();

        _runRewardsConfigurationTests();
    }

    function test_ETHEREUM_CapAutomator() public onChain(ChainIdUtils.Ethereum()){
        uint256 snapshot = vm.snapshot();

        _runCapAutomatorTests();

        vm.revertTo(snapshot);
        executeAllPayloadsAndBridges();

        _runCapAutomatorTests();
    }

    function test_ETHEREUM_PayloadsConfigured() public onChain(ChainIdUtils.Ethereum()){
         for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);
            if (chainId == ChainIdUtils.Ethereum()) continue;  // Checking only foreign payloads
            address payload = chainData[chainId].payload;
            if (payload != address(0)) {
                // A payload is defined for this domain
                // We verify the mainnet spell defines this payload correctly
                address mainnetPayload = _getForeignPayloadFromMainnetSpell(chainId);
                console.log("mainnetPayload", mainnetPayload);
                console.log("payload", payload);
                assertEq(mainnetPayload, payload, "Mainnet payload not matching deployed payload");
            }
        }
    }

    function _runRewardsConfigurationTests() internal view {
        SparkLendContext memory ctx = _getSparkLendContext();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
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

    function _voteAndCast(address _spell) internal {
        IAuthority authority = IAuthority(Ethereum.CHIEF);

        address skyWhale = makeAddr("skyWhale");
        uint256 amount = 4_000_000_000 ether;

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
        IExecutable(_spell).execute();
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
        SparkLendContext memory ctx = _getSparkLendContext();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            _assertAutomatedCapsUpdate(reserves[i]);
        }
    }

    function _assertAutomatedCapsUpdate(address asset) internal {
        SparkLendContext memory ctx = _getSparkLendContext();
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        DataTypes.ReserveData memory reserveDataBefore = ctx.pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

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

    function _assertBorrowCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.borrowCapConfigs(asset);
        assertEq(_max,              max);
        assertEq(_gap,              gap);
        assertEq(_increaseCooldown, increaseCooldown);
    }

    function _assertBorrowCapConfigNotSet(address asset) internal view {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.borrowCapConfigs(asset);
        assertEq(_max,              0);
        assertEq(_gap,              0);
        assertEq(_increaseCooldown, 0);
    }

    function _assertSupplyCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.supplyCapConfigs(asset);
        assertEq(_max,              max);
        assertEq(_gap,              gap);
        assertEq(_increaseCooldown, increaseCooldown);
    }

    function _assertSupplyCapConfigNotSet(address asset) internal view {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.supplyCapConfigs(asset);
        assertEq(_max,              0);
        assertEq(_gap,              0);
        assertEq(_increaseCooldown, 0);
    }

    function _assertMorphoCap(
        address             _vault,
        MarketParams memory _config,
        uint256             _currentCap,
        bool                _hasPending,
        uint256             _pendingCap
    ) internal view {
        Id id = MarketParamsLib.id(_config);
        assertEq(IMetaMorpho(_vault).config(id).cap, _currentCap);
        PendingUint192 memory pendingCap = IMetaMorpho(_vault).pendingCap(id);
        if (_hasPending) {
            assertEq(pendingCap.value,   _pendingCap);
            assertGt(pendingCap.validAt, 0);
        } else {
            assertEq(pendingCap.value,   0);
            assertEq(pendingCap.validAt, 0);
        }
    }

    function _assertMorphoCap(
        address             _vault,
        MarketParams memory _config,
        uint256             _currentCap,
        uint256             _pendingCap
    ) internal view {
        _assertMorphoCap(_vault, _config, _currentCap, true, _pendingCap);
    }

    function _assertMorphoCap(
        address             _vault,
        MarketParams memory _config,
        uint256             _currentCap
    ) internal view {
        _assertMorphoCap(_vault, _config, _currentCap, false, 0);
    }

    /******************************************************************************************************************/
    /*** Internal testing helper funcitons                                                                         ****/
    /******************************************************************************************************************/

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

    function _testAssetOnboardings(SparkLendAssetOnboardingParams[] memory collaterals) internal {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);

        uint256 startingReserveLength = allConfigsBefore.length;

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        assertEq(allConfigsAfter.length, startingReserveLength + collaterals.length);

        for (uint256 i = 0; i < collaterals.length; i++) {
            _testAssetOnboarding(allConfigsAfter, collaterals[i]);
        }
    }

    function _testAssetOnboarding(
        ReserveConfig[] memory allReserveConfigs,
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
            '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
        );
    }

    function _testMorphoCapUpdate(
        address vault,
        MarketParams memory config,
        uint256 currentCap,
        uint256 newCap
    )
        internal
    {
        _assertMorphoCap(vault, config, currentCap);

        executeAllPayloadsAndBridges();

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

    }

    function _testMorphoPendlePTOracleConfig(
        address pt,
        address oracle,
        uint256 discount,
        uint256 currentPrice
    )
        internal
    {
        IMorphoChainlinkOracleV2 _oracle = IMorphoChainlinkOracleV2(oracle);

        assertEq(address(_oracle.BASE_FEED_2()),          address(0));
        assertEq(address(_oracle.BASE_VAULT()),           address(0));
        assertEq(_oracle.BASE_VAULT_CONVERSION_SAMPLE(),  1);
        assertEq(address(_oracle.QUOTE_FEED_1()),         address(0));
        assertEq(address(_oracle.QUOTE_FEED_2()),         address(0));
        assertEq(address(_oracle.QUOTE_VAULT()),          address(0));
        assertEq(_oracle.QUOTE_VAULT_CONVERSION_SAMPLE(), 1);
        assertEq(_oracle.SCALE_FACTOR(),                  1e18);
        assertEq(_oracle.price(),                         currentPrice);
        assertLe(_oracle.price(),                         1e36);

        IPendleLinearDiscountOracle baseFeed = IPendleLinearDiscountOracle(address(_oracle.BASE_FEED_1()));

        assertEq(baseFeed.PT(),                  pt);
        assertEq(baseFeed.baseDiscountPerYear(), discount);

        uint256 snapshot = vm.snapshot();
        skip(365 days);
        assertEq(_oracle.price(), 1e36);
        vm.revertTo(snapshot);

        // TODO confirm morpho oracle was deployed from official factory
        // TODO add a bytecode check to the pendle oracle
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
        assertEq(ICustomIRM(newParams.irm).RATE_SOURCE(), ICustomIRM(oldParams.irm).RATE_SOURCE());

        uint256 ssrRate = uint256(IRateSource(ICustomIRM(newParams.irm).RATE_SOURCE()).getAPR());

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

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

        assertEq(ITargetBaseIRM(configBefore.interestRateStrategy).getBaseVariableBorrowRateSpread(), oldParams.baseRateSpread);

        executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

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

        assertEq(ITargetBaseIRM(configAfter.interestRateStrategy).getBaseVariableBorrowRateSpread(), newParams.baseRateSpread);
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
        assertEq(ICustomIRM(newParams.irm).RATE_SOURCE(), ICustomIRM(oldParams.irm).RATE_SOURCE());

        int256 ssrRate = IRateSource(ICustomIRM(newParams.irm).RATE_SOURCE()).getAPR();

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

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

        assertEq(uint256(ITargetKinkIRM(configBefore.interestRateStrategy).getVariableRateSlope1Spread()), uint256(oldParams.variableRateSlope1Spread));

        executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(createConfigurationSnapshot('', ctx.pool), symbol);

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

        assertEq(uint256(ITargetKinkIRM(configAfter.interestRateStrategy).getVariableRateSlope1Spread()), uint256(newParams.variableRateSlope1Spread));
    }
}
