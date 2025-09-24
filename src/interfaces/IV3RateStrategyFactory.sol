// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IDefaultInterestRateStrategy } from "sparklend-v1-core/interfaces/IDefaultInterestRateStrategy.sol";
import { IPoolAddressesProvider }       from "sparklend-v1-core/interfaces/IPoolAddressesProvider.sol";

interface IV3RateStrategyFactory {

    event RateStrategyCreated(
        address indexed strategy,
        bytes32 indexed hashedParam,
        RateStrategyParams params
    );

    /// @dev same parameters and the ones received on the constructor of DefaultReserveInterestRateStrategy
    /// in practice defining the strategy itself
    struct RateStrategyParams {
        uint256 optimalUsageRatio;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
        uint256 stableRateSlope1;
        uint256 stableRateSlope2;
        uint256 baseStableRateOffset;
        uint256 stableRateExcessOffset;
        uint256 optimalStableToTotalDebtRatio;
    }

    /**
     * @notice Create new rate strategies from a list of parameters
     * @dev If a strategy with exactly the same `RateStrategyParams` already exists, no creation happens but
     *  its address is returned
     * @param params `RateStrategyParams[]` list of parameters for multiple strategies
     * @return address[] list of strategies
     */
    function createStrategies(RateStrategyParams[] memory params) external returns (address[] memory);

    /**
     * @notice Returns the identifier of a rate strategy from its parameters
     * @param params `RateStrategyParams` the parameters of the rate strategy
     * @return bytes32 the keccak256 hash generated from the `RateStrategyParams` parameters
     *   to be used as identifier of the rate strategy on the factory
     */
    function strategyHashFromParams(RateStrategyParams memory params) external pure returns (bytes32);

    /**
     * @notice Returns all the strategies registered in the factory
     * @return address[] list of strategies
     */
    function getAllStrategies() external view returns (address[] memory);

    /**
     * @notice Returns the a strategy added, given its parameters.
     * @dev Only if the strategy is registered in the factory.
     * @param params `RateStrategyParams` the parameters of the rate strategy
     * @return address the address of the strategy
     */
    function getStrategyByParams(RateStrategyParams memory params) external view returns (address);

    /**
     * @notice From an asset in the Aave v3 pool, returns exclusively its parameters
     * @param asset The address of the asset
     * @return RateStrategyParams The parameters or the strategy, or empty RateStrategyParams struct
     */
    function getStrategyDataOfAsset(address asset) external view returns (RateStrategyParams memory);

    /**
     * @notice From a rate strategy address, returns its parameters
     * @param strategy The address of the rate strategy
     * @return RateStrategyParams Struct with the parameters of the strategy
     */
    function getStrategyData(
        IDefaultInterestRateStrategy strategy
    ) external view returns (RateStrategyParams memory);

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

}
