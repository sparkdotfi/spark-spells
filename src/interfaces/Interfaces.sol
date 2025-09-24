// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.7.5 <0.9.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { Id } from "metamorpho/interfaces/IMetaMorpho.sol";

interface IProxyLike {

    function implementation() external view returns (address);

}

interface IOracleLike {

    function DECIMALS() external view returns (uint8);

    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function name() external view returns (string memory);

    function version() external view returns (uint256);

    function latestAnswer() external view returns (int256);

}

interface ITreasuryControllerLike {

    function transfer(
        address collector,
        address token,
        address recipient,
        uint256 amount
    ) external;

}

interface IAuthorityLike {

    function canCall(address src, address dst, bytes4 sig) external view returns (bool);

    function hat() external view returns (address);

    function lock(uint256 amount) external;

    function vote(address[] calldata slate) external;

    function lift(address target) external;

}

interface ICustomIRMLike {

    function RATE_SOURCE() external view returns (address);

    function getBaseVariableBorrowRateSpread() external view returns (uint256);

}

interface IExecutableLike {

    function execute() external;

}

interface IMorphoLike {

    struct Position {
        uint256 supplyShares;
        uint128 borrowShares;
        uint128 collateral;
    }

    function position(Id id, address user) external view returns (Position memory p);

    function market(Id id)
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        );

}

interface IMorphoOracleFactoryLike {

    // NOTE: This applies to all oracles deployed by the factory
    function isMorphoChainlinkOracleV2(address) external view returns (bool);

}

interface IPendleLinearDiscountOracleLike {

    function baseDiscountPerYear() external view returns (uint256);

    function decimals() external view returns (uint256);

    function getDiscount(uint256 timeLeft) external view returns (uint256);

    function maturity() external view returns (uint256);

    function PT() external view returns (address);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

}

interface IRateSourceLike {

    function getAPR() external view returns (int256);

    function decimals() external view returns (uint256);

}

interface ISparkProxyLike {

    function wards(address) external view returns (uint256);

}

interface ITargetBaseIRMLike {

    function getBaseVariableBorrowRateSpread() external view returns (uint256);

}

interface ITargetKinkIRMLike {

    function getVariableRateSlope1Spread() external view returns (uint256);

}

interface ICurvePoolLike is IERC20 {

    function A() external view returns (uint256);

    function add_liquidity(
        uint256[] memory amounts,
        uint256 minMintAmount,
        address receiver
    ) external;

    function balances(uint256 index) external view returns (uint256);

    function coins(uint256 index) external returns (address);

    function exchange(
        int128  inputIndex,
        int128  outputIndex,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256 tokensOut);

    function fee() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function N_COINS() external view returns (uint256);

    function offpeg_fee_multiplier() external view returns (uint256);

    function remove_liquidity(
        uint256 burnAmount,
        uint256[] memory minAmounts,
        address receiver
    ) external;

    function stored_rates() external view returns (uint256[] memory);

}

interface IPoolManagerLike {

    function poolDelegate() external view returns (address);

    function strategyList(uint256 index) external view returns (address);

    function withdrawalManager() external view returns (address);

}

interface IPsmLike {

    function pocket() external view returns (address);

}

interface IMapleStrategyLike {

    function withdrawFromStrategy(uint256 amount) external;

}

interface IWithdrawalManagerLike {

    function processRedemptions(uint256 maxSharesToProcess) external;

}

interface ISyrupLike is IERC4626 {

    function manager() external view returns (address);

}

interface ISUSDELike is IERC4626 {

    function silo() external view returns (address);

}

interface ICurveStableswapFactoryLike {

    function get_implementation_address(address pool) external view returns (address);

}

interface IFarmLike {

    function earned(address account) external view returns (uint256);

    function rewardsToken() external view returns (address);

    function stakingToken() external view returns (address);

}
