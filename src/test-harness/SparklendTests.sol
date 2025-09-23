// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { StdChains } from 'forge-std/Test.sol';

import { ProtocolV3TestBase } from './ProtocolV3TestBase.sol';

import { Address } from '../libraries/Address.sol';

import { InitializableAdminUpgradeabilityProxy } from "sparklend-v1-core/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";
import { IACLManager }                           from 'sparklend-v1-core/interfaces/IACLManager.sol';
import { IPoolConfigurator }                     from 'sparklend-v1-core/interfaces/IPoolConfigurator.sol';
import { ReserveConfiguration }                  from 'sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol';
import { IPoolAddressesProvider }                from 'sparklend-v1-core/interfaces/IPoolAddressesProvider.sol';

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";

import { CommonSpellAssertions } from "./CommonSpellAssertions.sol";

import { SpellRunner } from "./SpellRunner.sol";

struct SparkLendContext {
    IPoolAddressesProvider poolAddressesProvider;
    IPool                  pool;
    IPoolConfigurator      poolConfigurator;
    IACLManager            aclManager;
    IAaveOracle            priceOracle;
}

/// @dev assertions specific to sparklend, which are not run on chains where
/// it is not deployed
abstract contract SparklendTests is ProtocolV3TestBase, SpellRunner, CommonSpellAssertions {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using DomainHelpers for StdChains.Chain;
    using DomainHelpers for Domain;

    function _getSparkLendContext(ChainId chain) internal view returns(SparkLendContext memory ctx) {
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

    function _getSparkLendContext() internal view returns(SparkLendContext memory) {
        return _getSparkLendContext(ChainIdUtils.fromUint(block.chainid));
    }

    function test_ETHEREUM_SpellExecutionDiff() public {
        _runSpellExecutionDiff(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_SpellExecutionDiff() public {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runSpellExecutionDiff(ChainIdUtils.Gnosis());
    }

    function _runSpellExecutionDiff(ChainId chainId) onChain(chainId) private {
        string memory prefix = string(abi.encodePacked(id, '-', chainId.toDomainString()));

        IPool pool = _getSparkLendContext().pool;

        createConfigurationSnapshot(
            string(abi.encodePacked(prefix, '-', vm.toString(address(pool)), '-pre')),
            pool
        );

        executeAllPayloadsAndBridges();

        createConfigurationSnapshot(
            string(abi.encodePacked(prefix, '-', vm.toString(address(pool)), '-post')),
            pool
        );

        diffReports(
            string(abi.encodePacked(prefix, '-', vm.toString(address(pool)), '-pre')),
            string(abi.encodePacked(prefix, '-', vm.toString(address(pool)), '-post'))
        );
    }

    function test_ETHEREUM_E2E_sparkLend() public {
        _runE2ETests(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_E2E_sparkLend() public {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runE2ETests(ChainIdUtils.Gnosis());
    }

    function _runE2ETests(ChainId chainId) private onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        e2eTest(ctx.pool);

        // Prevent MemoryLimitOOG
        _clearLogs();

        executeAllPayloadsAndBridges();

        e2eTest(ctx.pool);
    }

    function test_ETHEREUM_TokenImplementationsMatch() public {
        _assertTokenImplementationsMatch(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_TokenImplementationsMatch() public {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _assertTokenImplementationsMatch(ChainIdUtils.Gnosis());
    }

    function _assertTokenImplementationsMatch(ChainId chainId) private onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        // This test is to avoid a footgun where the token implementations are upgraded (possibly in an emergency) and
        // the config engine is not redeployed to use the new implementation. As a general rule all reserves should
        // use the same implementation for AToken, StableDebtToken and VariableDebtToken.
        executeAllPayloadsAndBridges();

        address[] memory reserves = ctx.pool.getReservesList();
        assertGt(reserves.length, 0);

        DataTypes.ReserveData memory data = ctx.pool.getReserveData(reserves[0]);
        address aTokenImpl            = getImplementation(address(ctx.poolConfigurator), data.aTokenAddress);
        address stableDebtTokenImpl   = getImplementation(address(ctx.poolConfigurator), data.stableDebtTokenAddress);
        address variableDebtTokenImpl = getImplementation(address(ctx.poolConfigurator), data.variableDebtTokenAddress);

        for (uint256 i = 1; i < reserves.length; i++) {
            DataTypes.ReserveData memory expectedData = ctx.pool.getReserveData(reserves[i]);

            assertEq(getImplementation(address(ctx.poolConfigurator), expectedData.aTokenAddress),            aTokenImpl);
            assertEq(getImplementation(address(ctx.poolConfigurator), expectedData.stableDebtTokenAddress),   stableDebtTokenImpl);
            assertEq(getImplementation(address(ctx.poolConfigurator), expectedData.variableDebtTokenAddress), variableDebtTokenImpl);
        }
    }

    function test_ETHEREUM_Oracles() public {
        _runOraclesTests(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_Oracles() public {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _runOraclesTests(ChainIdUtils.Gnosis());
    }

    function _runOraclesTests(ChainId chainId) private onChain(chainId) {
        _validateOracles();

        executeAllPayloadsAndBridges();

        _validateOracles();
    }

    function test_ETHEREUM_AllReservesSeeded() public {
        _assertAllReservesSeeded(ChainIdUtils.Ethereum());
    }

    function test_GNOSIS_AllReservesSeeded() public {
        vm.skip(chainData[ChainIdUtils.Gnosis()].payload == address(0));
        _assertAllReservesSeeded(ChainIdUtils.Gnosis());
    }

    function _assertAllReservesSeeded(ChainId chainId) private onChain(chainId) {
        SparkLendContext memory ctx = _getSparkLendContext();

        executeAllPayloadsAndBridges();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            address aToken = ctx.pool.getReserveData(reserves[i]).aTokenAddress;

            if (aToken == Ethereum.GNO_SPTOKEN) {
                continue;
            }

            require(IERC20(aToken).totalSupply() >= 1e4, 'RESERVE_NOT_SEEDED');
        }
    }

    function _validateOracles() internal view {
        SparkLendContext memory ctx = _getSparkLendContext();

        address[] memory reserves = ctx.pool.getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            require(ctx.priceOracle.getAssetPrice(reserves[i]) >= 0.5e8,      '_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_LOW');
            require(ctx.priceOracle.getAssetPrice(reserves[i]) <= 1_000_000e8,'_validateAssetSourceOnOracle() : INVALID_PRICE_TOO_HIGH');
        }
    }

    function getImplementation(address admin, address proxy) internal returns (address) {
        vm.prank(admin);
        return InitializableAdminUpgradeabilityProxy(payable(proxy)).implementation();
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
        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', _getSparkLendContext().pool);
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

        executeAllPayloadsAndBridges();

        address newIRM = _findReserveConfig(createConfigurationSnapshot('', _getSparkLendContext().pool), asset).interestRateStrategy;
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

    /** Utils **/

    /**
     * @dev generates the diff between two reports
     */
    function diffReports(string memory reportBefore, string memory reportAfter) internal {
        string memory outPath = string(
            abi.encodePacked('./diffs/', reportBefore, '_', reportAfter, '.md')
        );

        string memory beforePath = string(abi.encodePacked('./reports/', reportBefore, '.json'));
        string memory afterPath = string(abi.encodePacked('./reports/', reportAfter, '.json'));

        string[] memory inputs = new string[](7);
        inputs[0] = 'npx';
        inputs[1] = '@marsfoundation/aave-cli';
        inputs[2] = 'diff-snapshots';
        inputs[3] = beforePath;
        inputs[4] = afterPath;
        inputs[5] = '-o';
        inputs[6] = outPath;

        vm.ffi(inputs);
    }

}
