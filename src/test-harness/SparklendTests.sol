// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { StdChains } from "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Gnosis }   from "spark-address-registry/Gnosis.sol";

import { IPoolAddressesProvider, RateTargetKinkInterestRateStrategy } from "sparklend-advanced/src/RateTargetKinkInterestRateStrategy.sol";

import { ISparkLendFreezerMom } from "sparklend-freezer/interfaces/ISparkLendFreezerMom.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { InitializableAdminUpgradeabilityProxy } from "sparklend-v1-core/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";

import { IAaveOracle }                  from "sparklend-v1-core/interfaces/IAaveOracle.sol";
import { IACLManager }                  from "sparklend-v1-core/interfaces/IACLManager.sol";
import { IDefaultInterestRateStrategy } from "sparklend-v1-core/interfaces/IDefaultInterestRateStrategy.sol";
import { IPool }                        from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolAddressesProvider }       from "sparklend-v1-core/interfaces/IPoolAddressesProvider.sol";
import { IPoolConfigurator }            from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { IScaledBalanceToken }          from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";
import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";

import { IncentivizedERC20 } from "sparklend-v1-core/protocol/tokenization/base/IncentivizedERC20.sol";

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import {
    IAuthorityLike,
    ICustomIRMLike,
    IExecutableLike,
    IRateSourceLike,
    ISparkProxyLike,
    ITargetBaseIRMLike,
    ITargetKinkIRMLike
} from "../interfaces/Interfaces.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { ProtocolV3TestBase }    from "./ProtocolV3TestBase.sol";
import { SpellRunner }           from "./SpellRunner.sol";

// TODO: MDL, only used by `SparkEthereumTests`.
/// @dev assertions specific to sparklend, which are not run on chains where it is not deployed
abstract contract SparklendTests is ProtocolV3TestBase, SpellRunner {

    using WadRayMath for uint256;

    struct InterestStrategyValues {
        address addressesProvider;
        uint256 optimalUsageRatio;
        uint256 optimalStableToTotalDebtRatio;
        uint256 baseStableBorrowRate;
        uint256 stableRateSlope1;
        uint256 stableRateSlope2;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
    }

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

    struct SparkLendContext {
        IPoolAddressesProvider poolAddressesProvider;
        IPool                  pool;
        IPoolConfigurator      poolConfigurator;
        IACLManager            aclManager;
        IAaveOracle            priceOracle;
    }

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using DomainHelpers for StdChains.Chain;
    using DomainHelpers for Domain;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_SpellExecutionDiff() external {
        _runSpellExecutionDiff(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_SpellExecutionDiff() external {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runSpellExecutionDiff(ChainIdUtils.Gnosis());
    }

    function test_ETHEREUM_E2E_sparkLend() external {
        _runE2ETests(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_E2E_sparkLend() external {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runE2ETests(ChainIdUtils.Gnosis());
    }

    // TODO: MDL, should combine tests to call `_executeAllPayloadsAndBridges` once and then run make all assertions.
    function test_ETHEREUM_TokenImplementationsMatch() external {
        _testMatchingTokenImplementations(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_TokenImplementationsMatch() external {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _testMatchingTokenImplementations(ChainIdUtils.Gnosis());
    }

    function test_ETHEREUM_Oracles() external {
        _runOraclesTests(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_Oracles() external {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runOraclesTests(ChainIdUtils.Gnosis());
    }

    function test_ETHEREUM_AllReservesSeeded() external {
        _testAllReservesAreSeeded(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_AllReservesSeeded() external {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _testAllReservesAreSeeded(ChainIdUtils.Gnosis());
    }

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

    function test_ETHEREUM_RewardsConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        _assertRewardsConfigurations();
        _executeAllPayloadsAndBridges();
        _assertRewardsConfigurations();
    }

    function test_ETHEREUM_CapAutomator() external onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runCapAutomatorTests();

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runCapAutomatorTests();
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _runSpellExecutionDiff(ChainId chainId) internal onChain(chainId) {
        IPool pool = _getSparkLendContext().pool;

        string memory prefix   = string(abi.encodePacked(vm.toString(_spellId), "-", chainId.toDomainString()));
        string memory prePath  = string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-pre"));
        string memory postPath = string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-post"));

        _createConfigurationSnapshot(prePath, pool);
        _executeAllPayloadsAndBridges();
        _createConfigurationSnapshot(postPath, pool);
        _generateDiffReports(prePath, postPath);
    }

    function _runE2ETests(ChainId chainId) internal onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        _e2eTest(ctx.pool);

        // Prevent MemoryLimitOOG
        _clearLogs();

        _executeAllPayloadsAndBridges();

        _e2eTest(ctx.pool);
    }

    function _testMatchingTokenImplementations(ChainId chainId) internal onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // This test is to avoid a footgun where the token implementations are upgraded (possibly in an emergency) and
        // the config engine is not redeployed to use the new implementation. As a general rule all reserves should
        // use the same implementation for AToken, StableDebtToken and VariableDebtToken.
        _executeAllPayloadsAndBridges();

        address[] memory reserves = ctx.pool.getReservesList();

        assertGt(reserves.length, 0);

        DataTypes.ReserveData memory data = ctx.pool.getReserveData(reserves[0]);

        address aTokenImplementation            = _getImplementation(address(ctx.poolConfigurator), data.aTokenAddress);
        address stableDebtTokenImplementation   = _getImplementation(address(ctx.poolConfigurator), data.stableDebtTokenAddress);
        address variableDebtTokenImplementation = _getImplementation(address(ctx.poolConfigurator), data.variableDebtTokenAddress);

        for (uint256 i = 1; i < reserves.length; ++i) {
            DataTypes.ReserveData memory expectedData = ctx.pool.getReserveData(reserves[i]);

            assertEq(_getImplementation(address(ctx.poolConfigurator), expectedData.aTokenAddress),            aTokenImplementation);
            assertEq(_getImplementation(address(ctx.poolConfigurator), expectedData.stableDebtTokenAddress),   stableDebtTokenImplementation);
            assertEq(_getImplementation(address(ctx.poolConfigurator), expectedData.variableDebtTokenAddress), variableDebtTokenImplementation);
        }
    }

    function _runOraclesTests(ChainId chainId) internal onChain(chainId) {
        _validateOracles();
        _executeAllPayloadsAndBridges();
        _validateOracles();
    }

    function _testAllReservesAreSeeded(ChainId chainId) internal onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        _executeAllPayloadsAndBridges();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            address aToken = ctx.pool.getReserveData(reserves[i]).aTokenAddress;

            if (aToken == Ethereum.GNO_SPTOKEN) continue;

            require(IERC20(aToken).totalSupply() >= 1e4, "RESERVE_NOT_SEEDED");
        }
    }

    function _testIRMChanges(
        address asset,
        uint256 oldOptimal,
        uint256 oldBase,
        uint256 oldSlope1,
        uint256 oldSlope2,
        uint256 newOptimal,
        uint256 newBase,
        uint256 newSlope1,
        uint256 newSlope2
    ) internal {
        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot("", _getSparkLendContext().pool);
        ReserveConfig   memory config           = _findReserveConfig(allConfigsBefore, asset);

        IDefaultInterestRateStrategy prevIRM = IDefaultInterestRateStrategy(config.interestRateStrategy);
        _validateInterestRateStrategy(
            address(prevIRM),
            address(prevIRM),
            InterestStrategyValues({
                addressesProvider:             address(prevIRM.ADDRESSES_PROVIDER()),
                optimalUsageRatio:             oldOptimal,
                optimalStableToTotalDebtRatio: prevIRM.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(),
                baseStableBorrowRate:          oldSlope1,
                stableRateSlope1:              prevIRM.getStableRateSlope1(),
                stableRateSlope2:              prevIRM.getStableRateSlope2(),
                baseVariableBorrowRate:        oldBase,
                variableRateSlope1:            oldSlope1,
                variableRateSlope2:            oldSlope2
            })
        );

        _executeAllPayloadsAndBridges();

        // TODO: MDL, not writing to config, so we don't need a clone.
        address newIRM = _findReserveConfig(_createConfigurationSnapshot("", _getSparkLendContext().pool), asset).interestRateStrategy;
        assertNotEq(newIRM, address(prevIRM));

        _validateInterestRateStrategy(
            newIRM,
            newIRM,
            InterestStrategyValues({
                addressesProvider:             address(prevIRM.ADDRESSES_PROVIDER()),
                optimalUsageRatio:             newOptimal,
                optimalStableToTotalDebtRatio: prevIRM.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(),
                baseStableBorrowRate:          newSlope1,
                stableRateSlope1:              prevIRM.getStableRateSlope1(),
                stableRateSlope2:              prevIRM.getStableRateSlope2(),
                baseVariableBorrowRate:        newBase,
                variableRateSlope1:            newSlope1,
                variableRateSlope2:            newSlope2
            })
        );
    }

    /**
     * @dev generates the diff between two reports
     */
    function _generateDiffReports(string memory reportBefore, string memory reportAfter) internal {
        string memory outPath = string(
            abi.encodePacked("./diffs/", reportBefore, "_", reportAfter, ".md")
        );

        string memory beforePath = string(abi.encodePacked("./reports/", reportBefore, ".json"));
        string memory afterPath = string(abi.encodePacked("./reports/", reportAfter, ".json"));

        string[] memory inputs = new string[](7);
        inputs[0] = "npx";
        inputs[1] = "@marsfoundation/aave-cli";
        inputs[2] = "diff-snapshots";
        inputs[3] = beforePath;
        inputs[4] = afterPath;
        inputs[5] = "-o";
        inputs[6] = outPath;

        vm.ffi(inputs);
    }

    function _runCapAutomatorTests() internal {
        address[] memory reserves = _getSparkLendContext().pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            _testAutomatedCapsUpdate(reserves[i]);
        }
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

    function _testAutomatedCapsUpdate(address asset) internal {
        SparkLendContext      memory ctx               = _getSparkLendContext();
        DataTypes.ReserveData memory reserveDataBefore = ctx.pool.getReserveData(asset);

        uint256 supplyCapBefore = reserveDataBefore.configuration.getSupplyCap();
        uint256 borrowCapBefore = reserveDataBefore.configuration.getBorrowCap();

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        ( , , , , uint48 supplyCapLastIncreaseTime ) = capAutomator.supplyCapConfigs(asset);
        ( , , , , uint48 borrowCapLastIncreaseTime ) = capAutomator.borrowCapConfigs(asset);

        capAutomator.exec(asset);

        DataTypes.ReserveData memory reserveDataAfter = ctx.pool.getReserveData(asset);

        uint256 supplyCapAfter = reserveDataAfter.configuration.getSupplyCap();
        uint256 borrowCapAfter = reserveDataAfter.configuration.getBorrowCap();

        uint48 max;
        uint48 gap;
        uint48 cooldown;

        ( max, gap, cooldown, , ) = capAutomator.supplyCapConfigs(asset);

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

        ( max, gap, cooldown, , ) = capAutomator.borrowCapConfigs(asset);

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

    function _voteAndCast(address spell) internal {
        IAuthorityLike authority = IAuthorityLike(Ethereum.CHIEF);

        address skyWhale = makeAddr("skyWhale");
        uint256 amount   = 10_000_000_000 ether;

        deal(Ethereum.SKY, skyWhale, amount);

        vm.startPrank(skyWhale);

        IERC20(Ethereum.SKY).approve(address(authority), amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = spell;

        authority.vote(slate);

        // Min amount of blocks to pass to vote again.
        vm.roll(block.number + 11);

        authority.lift(spell);

        vm.stopPrank();

        assertEq(authority.hat(), spell);

        vm.prank(makeAddr("randomUser"));
        IExecutableLike(spell).execute();
    }

    // TODO: MDL, not used anywhere.
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

    // TODO: MDL, only used by `_testAssetOnboardings` above.
    function _testAssetOnboarding(
        ReserveConfig[]                memory allReserveConfigs,
        SparkLendAssetOnboardingParams memory params
    )
        internal view
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // TODO: MDL, not writing to config, so we don't need a clone.
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

    // TODO: MDL, not used anywhere.
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

        // TODO: MDL, not writing to config, so we don't need a clone.
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

        // TODO: MDL, not writing to config, so we don't need a clone.
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

    // TODO: MDL, seems to be Sparklend.
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

        // TODO: MDL, not writing to config, so we don't need a clone.
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

        // TODO: MDL, not writing to config, so we don't need a clone.
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

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

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

    function _assertFrozen(address asset, bool frozen) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getFrozen(), frozen);
    }

    function _assertPaused(address asset, bool paused) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getPaused(), paused);
    }

    function _assertRewardsConfigurations() internal view {
        SparkLendContext memory ctx      = _getSparkLendContext();
        address[]        memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            DataTypes.ReserveData memory reserveData = ctx.pool.getReserveData(reserves[i]);

            assertEq(address(IncentivizedERC20(reserveData.aTokenAddress).getIncentivesController()),            Ethereum.INCENTIVES);
            assertEq(address(IncentivizedERC20(reserveData.variableDebtTokenAddress).getIncentivesController()), Ethereum.INCENTIVES);
        }
    }

    function _assertSupplyCapConfig(address asset, uint48 max, uint48 gap, uint48 increaseCooldown) internal view {
        (
            uint48 max_,
            uint48 gap_,
            uint48 increaseCooldown_,
            , // lastUpdateBlock
              // lastIncreaseTime
        ) = ICapAutomator(Ethereum.CAP_AUTOMATOR).supplyCapConfigs(asset);

        assertEq(max_,              max);
        assertEq(gap_,              gap);
        assertEq(increaseCooldown_, increaseCooldown);
    }

    // TODO: This should probably be simplified with assembly, too much boilerplate.
    // TODO: MDL, might not even need this as callers of `_findReserveConfig` and `_findReserveConfigBySymbol` do not
    //       modify the config, and even if they did, it should be their responsibility to clone the config.
    function _clone(ReserveConfig memory config) internal pure returns (ReserveConfig memory) {
        return
            ReserveConfig({
                symbol: config.symbol,
                underlying: config.underlying,
                aToken: config.aToken,
                stableDebtToken: config.stableDebtToken,
                variableDebtToken: config.variableDebtToken,
                decimals: config.decimals,
                ltv: config.ltv,
                liquidationThreshold: config.liquidationThreshold,
                liquidationBonus: config.liquidationBonus,
                liquidationProtocolFee: config.liquidationProtocolFee,
                reserveFactor: config.reserveFactor,
                usageAsCollateralEnabled: config.usageAsCollateralEnabled,
                borrowingEnabled: config.borrowingEnabled,
                interestRateStrategy: config.interestRateStrategy,
                stableBorrowRateEnabled: config.stableBorrowRateEnabled,
                isPaused: config.isPaused,
                isActive: config.isActive,
                isFrozen: config.isFrozen,
                isSiloed: config.isSiloed,
                isBorrowableInIsolation: config.isBorrowableInIsolation,
                isFlashloanable: config.isFlashloanable,
                supplyCap: config.supplyCap,
                borrowCap: config.borrowCap,
                debtCeiling: config.debtCeiling,
                eModeCategory: config.eModeCategory
            });
    }

    function _getImplementation(address admin, address proxy) internal returns (address) {
        // TODO: MDL, very odd that this query requires a prank.
        vm.prank(admin);
        return InitializableAdminUpgradeabilityProxy(payable(proxy)).implementation();
    }

    function _getSparkLendContext(ChainId chain) internal view returns (SparkLendContext memory ctx) {
        IPoolAddressesProvider poolAddressesProvider;

        if (chain == ChainIdUtils.Ethereum()) {
            poolAddressesProvider = IPoolAddressesProvider(Ethereum.POOL_ADDRESSES_PROVIDER);
        } else if (chain == ChainIdUtils.Gnosis()) {
            poolAddressesProvider = IPoolAddressesProvider(Gnosis.POOL_ADDRESSES_PROVIDER);
        } else {
            revert("SparkLend/executing on unknown chain");
        }

        ctx = SparkLendContext(
            poolAddressesProvider,
            IPool(poolAddressesProvider.getPool()),
            IPoolConfigurator(poolAddressesProvider.getPoolConfigurator()),
            IACLManager(poolAddressesProvider.getACLManager()),
            IAaveOracle(poolAddressesProvider.getPriceOracle())
        );
    }

    function _getSparkLendContext() internal view returns (SparkLendContext memory) {
        return _getSparkLendContext(ChainIdUtils.fromUint(block.chainid));
    }

    // TODO: MDL, drop the `1` suffix.
    function _isEqual1(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _findReserveConfig(
        ReserveConfig[] memory configs,
        address                underlying
    ) internal pure returns (ReserveConfig memory) {
        for (uint256 i = 0; i < configs.length; ++i) {
            // Important to clone the struct, to avoid unexpected side effect if modifying the returned config
            if (configs[i].underlying == underlying) return _clone(configs[i]);
        }

        revert("RESERVE_CONFIG_NOT_FOUND");
    }

    function _findReserveConfigBySymbol(
        ReserveConfig[] memory configs,
        string          memory symbolOfUnderlying
    ) internal pure returns (ReserveConfig memory) {
        for (uint256 i = 0; i < configs.length; ++i) {
            // Important to clone the struct, to avoid unexpected side effect if modifying the returned config
            if (_isEqual1(configs[i].symbol, symbolOfUnderlying)) return _clone(configs[i]);
        }

        revert("RESERVE_CONFIG_NOT_FOUND");
    }

    function _validateInterestRateStrategy(
        address                       interestRateStrategyAddress,
        address                       expectedStrategy,
        InterestStrategyValues memory expectedStrategyValues
    ) internal view {
        IDefaultInterestRateStrategy strategy = IDefaultInterestRateStrategy(
            interestRateStrategyAddress
        );

        require(
            address(strategy) == expectedStrategy,
            "_validateInterestRateStrategy() : INVALID_STRATEGY_ADDRESS"
        );

        require(
            strategy.OPTIMAL_USAGE_RATIO() == expectedStrategyValues.optimalUsageRatio,
            "_validateInterestRateStrategy() : INVALID_OPTIMAL_RATIO"
        );

        require(
            strategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO() ==
                expectedStrategyValues.optimalStableToTotalDebtRatio,
            "_validateInterestRateStrategy() : INVALID_OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO"
        );

        require(
            address(strategy.ADDRESSES_PROVIDER()) == expectedStrategyValues.addressesProvider,
            "_validateInterestRateStrategy() : INVALID_ADDRESSES_PROVIDER"
        );

        require(
            strategy.getBaseVariableBorrowRate() == expectedStrategyValues.baseVariableBorrowRate,
            "_validateInterestRateStrategy() : INVALID_BASE_VARIABLE_BORROW"
        );

        require(
            strategy.getBaseStableBorrowRate() == expectedStrategyValues.baseStableBorrowRate,
            "_validateInterestRateStrategy() : INVALID_BASE_STABLE_BORROW"
        );

        require(
            strategy.getStableRateSlope1() == expectedStrategyValues.stableRateSlope1,
            "_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_1"
        );

        require(
            strategy.getStableRateSlope2() == expectedStrategyValues.stableRateSlope2,
            "_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_2"
        );

        require(
            strategy.getVariableRateSlope1() == expectedStrategyValues.variableRateSlope1,
            "_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_1"
        );

        require(
            strategy.getVariableRateSlope2() == expectedStrategyValues.variableRateSlope2,
            "_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_2"
        );
    }

    function _validateOracles() internal view {
        SparkLendContext memory ctx = _getSparkLendContext();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            require(ctx.priceOracle.getAssetPrice(reserves[i]) >= 0.5e8,      "_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_LOW");
            require(ctx.priceOracle.getAssetPrice(reserves[i]) <= 1_000_000e8,"_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_HIGH");
        }
    }

    function _validateReserveConfig(
        ReserveConfig   memory expectedConfig,
        ReserveConfig[] memory allConfigs
    ) internal pure {
        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory config = _findReserveConfig(allConfigs, expectedConfig.underlying);

        require(
            _isEqual1(config.symbol, expectedConfig.symbol),
            "_validateConfigsInAave() : INVALID_SYMBOL"
        );

        require(
            config.underlying == expectedConfig.underlying,
            "_validateConfigsInAave() : INVALID_UNDERLYING"
        );

        require(config.decimals == expectedConfig.decimals, "_validateConfigsInAave: INVALID_DECIMALS");

        require(config.ltv == expectedConfig.ltv, "_validateConfigsInAave: INVALID_LTV");

        require(
            config.liquidationThreshold == expectedConfig.liquidationThreshold,
            "_validateConfigsInAave: INVALID_LIQ_THRESHOLD"
        );

        require(
            config.liquidationBonus == expectedConfig.liquidationBonus,
            "_validateConfigsInAave: INVALID_LIQ_BONUS"
        );

        require(
            config.liquidationProtocolFee == expectedConfig.liquidationProtocolFee,
            "_validateConfigsInAave: INVALID_LIQUIDATION_PROTOCOL_FEE"
        );

        require(
            config.reserveFactor == expectedConfig.reserveFactor,
            "_validateConfigsInAave: INVALID_RESERVE_FACTOR"
        );

        require(
            config.usageAsCollateralEnabled == expectedConfig.usageAsCollateralEnabled,
            "_validateConfigsInAave: INVALID_USAGE_AS_COLLATERAL"
        );

        require(
            config.borrowingEnabled == expectedConfig.borrowingEnabled,
            "_validateConfigsInAave: INVALID_BORROWING_ENABLED"
        );

        require(
            config.stableBorrowRateEnabled == expectedConfig.stableBorrowRateEnabled,
            "_validateConfigsInAave: INVALID_STABLE_BORROW_ENABLED"
        );

        require(
            config.isActive == expectedConfig.isActive,
            "_validateConfigsInAave: INVALID_IS_ACTIVE"
        );

        require(
            config.isFrozen == expectedConfig.isFrozen,
            "_validateConfigsInAave: INVALID_IS_FROZEN"
        );

        require(
            config.isSiloed == expectedConfig.isSiloed,
            "_validateConfigsInAave: INVALID_IS_SILOED"
        );

        require(
            config.isBorrowableInIsolation == expectedConfig.isBorrowableInIsolation,
            "_validateConfigsInAave: INVALID_IS_BORROWABLE_IN_ISOLATION"
        );

        require(
            config.isFlashloanable == expectedConfig.isFlashloanable,
            "_validateConfigsInAave: INVALID_IS_FLASHLOANABLE"
        );

        require(
            config.supplyCap == expectedConfig.supplyCap,
            "_validateConfigsInAave: INVALID_SUPPLY_CAP"
        );

        require(
            config.borrowCap == expectedConfig.borrowCap,
            "_validateConfigsInAave: INVALID_BORROW_CAP"
        );

        require(
            config.debtCeiling == expectedConfig.debtCeiling,
            "_validateConfigsInAave: INVALID_DEBT_CEILING"
        );

        require(
            config.eModeCategory == expectedConfig.eModeCategory,
            "_validateConfigsInAave: INVALID_EMODE_CATEGORY"
        );

        require(
            config.interestRateStrategy == expectedConfig.interestRateStrategy,
            "_validateConfigsInAave: INVALID_INTEREST_RATE_STRATEGY"
        );
    }

}
