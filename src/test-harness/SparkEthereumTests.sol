// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Address } from '../libraries/Address.sol';

import { IPoolAddressesProvider } from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

import { IAaveOracle }                     from 'sparklend-v1-core/contracts/interfaces/IAaveOracle.sol';
import { IScaledBalanceToken }             from "sparklend-v1-core/contracts/interfaces/IScaledBalanceToken.sol";
import { IncentivizedERC20 }               from 'sparklend-v1-core/contracts/protocol/tokenization/base/IncentivizedERC20.sol';
import { ReserveConfiguration, DataTypes } from 'sparklend-v1-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import { WadRayMath }                      from "sparklend-v1-core/contracts/protocol/libraries/math/WadRayMath.sol";

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

import { IMetaMorpho, MarketParams, PendingUint192, Id } from 'metamorpho/interfaces/IMetaMorpho.sol';
import { MarketParamsLib }                               from 'morpho-blue/src/libraries/MarketParamsLib.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IDefaultInterestRateStrategy } from 'sparklend-v1-core/contracts/interfaces/IDefaultInterestRateStrategy.sol';

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";

import { InterestStrategyValues, ReserveConfig } from 'src/test-harness/ProtocolV3TestBase.sol';

import { SparklendTests } from "./SparklendTests.sol";

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

interface IRateTargetBaseIRM {
    function RATE_SOURCE() external view returns (address);
    function getBaseVariableBorrowRateSpread() external view returns (uint256);
}

/// @dev assertions specific to mainnet
/// TODO: separate tests related to sparklend from the rest (eg: morpho)
///       also separate mainnet-specific sparklend tests from those we should
///       run on Gnosis as well
abstract contract SparkEthereumTests is SparklendTests {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    IAuthority           internal authority;
    ISparkLendFreezerMom internal freezerMom;
    ICapAutomator        internal capAutomator;

    constructor() {
        authority    = IAuthority(Ethereum.CHIEF);
        freezerMom   = ISparkLendFreezerMom(Ethereum.FREEZER_MOM);
        capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);
    }

    function test_ETHEREUM_FreezerMom() public onChain(ChainIdUtils.Ethereum()){
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTests();

        vm.revertTo(snapshot);
        executeAllPayloadsAndBridges();

        _runFreezerMomTests();
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
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            if (chainId == ChainIdUtils.Ethereum()) continue;  // Checking only foreign payloads
            address payload = chainSpellMetadata[chainId].payload;
            if (payload != address(0)) {
                // A payload is defined for this domain
                // We verify the mainnet spell defines this payload correctly
                address mainnetPayload = _getForeignPayloadFromMainnetSpell(chainId);
                assertEq(mainnetPayload, payload, "Mainnet payload not matching deployed payload");
            }
        }
    }

    function _runRewardsConfigurationTests() internal {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        address[] memory reserves = pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveData memory reserveData = pool.getReserveData(reserves[i]);

            assertEq(address(IncentivizedERC20(reserveData.aTokenAddress).getIncentivesController()),            Ethereum.INCENTIVES);
            assertEq(address(IncentivizedERC20(reserveData.variableDebtTokenAddress).getIncentivesController()), Ethereum.INCENTIVES);
        }
    }

    function _assertFrozen(address asset, bool frozen) internal view {
        assertEq(pool.getConfiguration(asset).getFrozen(), frozen);
    }

    function _assertPaused(address asset, bool paused) internal view {
        assertEq(pool.getConfiguration(asset).getPaused(), paused);
    }

    function _voteAndCast(address _spell) internal {
        address mkrWhale = makeAddr("mkrWhale");
        uint256 amount = 1_000_000 ether;

        deal(Ethereum.MKR, mkrWhale, amount);

        vm.startPrank(mkrWhale);
        IERC20(Ethereum.MKR).approve(address(authority), amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = _spell;
        authority.vote(slate);

        vm.roll(block.number + 1);

        authority.lift(_spell);

        vm.stopPrank();

        assertEq(authority.hat(), _spell);

        vm.prank(makeAddr("randomUser"));
        IExecutable(_spell).execute();
    }

    function _runFreezerMomTests() internal {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        // Sanity checks - cannot call Freezer Mom unless you have the hat
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
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        address[] memory reserves = pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            _assertAutomatedCapsUpdate(reserves[i]);
        }
    }

    function _assertAutomatedCapsUpdate(address asset) internal {
        DataTypes.ReserveData memory reserveDataBefore = pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

        (,,,,uint48 supplyCapLastIncreaseTime) = capAutomator.supplyCapConfigs(asset);
        (,,,,uint48 borrowCapLastIncreaseTime) = capAutomator.borrowCapConfigs(asset);

        capAutomator.exec(asset);

        DataTypes.ReserveData memory reserveDataAfter = pool.getReserveData(asset);

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
        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.borrowCapConfigs(asset);
        assertEq(_max,              max);
        assertEq(_gap,              gap);
        assertEq(_increaseCooldown, increaseCooldown);
    }

    function _assertBorrowCapConfigNotSet(address asset) internal view {
        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.borrowCapConfigs(asset);
        assertEq(_max,              0);
        assertEq(_gap,              0);
        assertEq(_increaseCooldown, 0);
    }

    function _assertSupplyCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        (uint48 _max, uint48 _gap, uint48 _increaseCooldown,,) = capAutomator.supplyCapConfigs(asset);
        assertEq(_max,              max);
        assertEq(_gap,              gap);
        assertEq(_increaseCooldown, increaseCooldown);
    }

    function _assertSupplyCapConfigNotSet(address asset) internal view {
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

    function _testAssetOnboardings(SparkLendAssetOnboardingParams[] memory collaterals) internal{
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);

        uint256 startingReserveLength = allConfigsBefore.length;

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);

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
        // TODO: Refactor this
        IPoolAddressesProvider poolAddressesProvider
            = IPoolAddressesProvider(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

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
            addressesProvider:             address(poolAddressesProvider),
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

        IAaveOracle oracle = IAaveOracle(poolAddressesProvider.getPriceOracle());

        require(
            oracle.getSourceOfAsset(params.tokenAddress) == params.oracleAddress,
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

        _assertMorphoCap(vault, config, currentCap, newCap);

        assertEq(IMetaMorpho(vault).timelock(), 1 days);
        skip(1 days);

        IMetaMorpho(vault).acceptCap(config);

        _assertMorphoCap(vault, config, newCap);
    }

    function _testMorphoPendlePTOracleConfig(
        address oracle,
        uint256 currentPrice
    )
        internal
    {
        uint256 ptSUSDE29MAY2025Price = IMorphoChainlinkOracle(PT_SUSDE_29MAY2025_PRICE_FEED).price();

        assertEq(ptSUSDE29MAY2025Price, 0.903243903792491122e36);

        uint256 timeSkip = 60 days;
        skip(timeSkip);

        uint256 newPTSUSDE29MAY2025Price = IMorphoChainlinkOracle(PT_SUSDE_29MAY2025_PRICE_FEED).price();

        // Price for both feeds increases over time
        assertGt(newPTSUSDE29MAY2025Price, ptSUSDE29MAY2025Price);

        uint256 ptSUSDE29MAY2025YearlyPriceIncrease = (newPTSUSDE29MAY2025Price - ptSUSDE29MAY2025Price) * 365 days / (timeSkip);

        // Calculated yield should equal the expected one
        assertApproxEqAbs(ptSUSDE29MAY2025YearlyPriceIncrease / 1e18, PT_SUSDE_29MAY2025_YIELD, 4);

        assertLt(IMorphoChainlinkOracle(PT_SUSDE_29MAY2025_PRICE_FEED).price(), 1e36);

        // Prices on maturity should be 1e36
        vm.warp(IPendlePT(PT_SUSDE_29MAY2025).expiry());
        assertEq(IMorphoChainlinkOracle(PT_SUSDE_29MAY2025_PRICE_FEED).price(), 1e36);

        skip(365 days);

        // Prices should remain to be 1e36
        assertEq(IMorphoChainlinkOracle(PT_SUSDE_29MAY2025_PRICE_FEED).price(), 1e36);
    }

    function _testRateTargetBaseIRMUpdate(
        string memory symbol,
        address       oldIRM,
        address       newIRM,
        uint256       oldSpread,
        uint256       newSpread,
        uint256       oldBaseRate,
        uint256       newBaseRate
    )
        internal
    {
        // Rate source should be the same
        assertEq(IRateTargetBaseIRM(newIRM).RATE_SOURCE(), IRateTargetBaseIRM(oldIRM).RATE_SOURCE());

        // Check spreads
        assertEq(IRateTargetBaseIRM(oldIRM).getBaseVariableBorrowRateSpread(), oldSpread);
        assertEq(IRateTargetBaseIRM(newIRM).getBaseVariableBorrowRateSpread(), newSpread);

        // Check change in base variable borrow rate
        assertEq(IDefaultInterestRateStrategy(oldIRM).getBaseVariableBorrowRate(), oldBaseRate);
        assertEq(IDefaultInterestRateStrategy(newIRM).getBaseVariableBorrowRate(), newBaseRate);

        ReserveConfig memory configBefore = _findReserveConfigBySymbol(createConfigurationSnapshot('', pool), symbol);

        assertEq(configBefore.interestRateStrategy, oldIRM);

        executeAllPayloadsAndBridges();

        ReserveConfig memory configAfter = _findReserveConfigBySymbol(createConfigurationSnapshot('', pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newIRM,
            InterestStrategyValues({
                addressesProvider:             address(poolAddressesProvider),
                optimalUsageRatio:             1e27,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          IDefaultInterestRateStrategy(oldIRM).getVariableRateSlope1(),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        newBaseRate,
                variableRateSlope1:            IDefaultInterestRateStrategy(oldIRM).getVariableRateSlope1(),
                variableRateSlope2:            IDefaultInterestRateStrategy(oldIRM).getVariableRateSlope2()
            })
        );
    }

}
