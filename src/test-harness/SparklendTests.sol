// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { StdChains } from "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Gnosis }   from "spark-address-registry/Gnosis.sol";

import { ISparkLendFreezerMom } from "sparklend-freezer/interfaces/ISparkLendFreezerMom.sol";

import { InitializableAdminUpgradeabilityProxy } from "sparklend-v1-core/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";

import { IACLManager }                  from "sparklend-v1-core/interfaces/IACLManager.sol";
import { IPoolConfigurator }            from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { IPoolAddressesProvider }       from "sparklend-v1-core/interfaces/IPoolAddressesProvider.sol";
import { IPool }                        from "sparklend-v1-core/interfaces/IPool.sol";
import { IAaveOracle }                  from "sparklend-v1-core/interfaces/IAaveOracle.sol";
import { IDefaultInterestRateStrategy } from "sparklend-v1-core/interfaces/IDefaultInterestRateStrategy.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import {
    IAuthorityLike,
    IExecutableLike
} from "../interfaces/Interfaces.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { ProtocolV3TestBase }    from "./ProtocolV3TestBase.sol";
import { SpellRunner }           from "./SpellRunner.sol";

// TODO: MDL, only used by `SparkEthereumTests`.
/// @dev assertions specific to sparklend, which are not run on chains where it is not deployed
abstract contract SparklendTests is ProtocolV3TestBase, SpellRunner {

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

    function test_ETHEREUM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Ethereum());
    }

    function test_BASE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Base());
    }

    function test_GNOSIS_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Gnosis());
    }

    function test_ARBITRUM_ONE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.ArbitrumOne());
    }

    function test_OPTIMISM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Unichain());
    }

    function test_ETHEREUM_FreezerMom() external onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();

        _runFreezerMomTests();

        vm.revertTo(snapshot);

        _executeAllPayloadsAndBridges();
        _runFreezerMomTests();
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _runSpellExecutionDiff(ChainId chainId) internal onChain(chainId) {
        string memory prefix = string(abi.encodePacked(vm.toString(_spellId), "-", chainId.toDomainString()));

        IPool pool = _getSparkLendContext().pool;

        _createConfigurationSnapshot(
            string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-pre")),
            pool
        );

        _executeAllPayloadsAndBridges();

        _createConfigurationSnapshot(
            string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-post")),
            pool
        );

        _generateDiffReports(
            string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-pre")),
            string(abi.encodePacked(prefix, "-", vm.toString(address(pool)), "-post"))
        );
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

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _assertFrozen(address asset, bool frozen) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getFrozen(), frozen);
    }

    function _assertPaused(address asset, bool paused) internal view {
        assertEq(_getSparkLendContext().pool.getConfiguration(asset).getPaused(), paused);
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

    function _validateOracles() internal view {
        SparkLendContext memory ctx = _getSparkLendContext();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; ++i) {
            require(ctx.priceOracle.getAssetPrice(reserves[i]) >= 0.5e8,      "_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_LOW");
            require(ctx.priceOracle.getAssetPrice(reserves[i]) <= 1_000_000e8,"_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_HIGH");
        }
    }

}
