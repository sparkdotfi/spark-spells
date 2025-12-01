// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.7.5 <0.9.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC7540 } from "forge-std/interfaces/IERC7540.sol";

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

interface IStarGuardLike {
    function plot(address addr_, bytes32 tag_) external;
    function exec() external returns (address addr);
}

interface ISparkVaultV2Like {

    function asset() external view returns (address);

    function assetsOf(address user) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function chi() external view returns (uint192);

    function decimals() external view returns (uint8);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function depositCap() external view returns (uint256);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function grantRole(bytes32 role, address account) external; 

    function hasRole(bytes32 role, address account) external view returns (bool);

    function minVsr() external view returns (uint256);

    function maxDeposit(address) external view returns (uint256);

    function maxVsr() external view returns (uint256);

    function name() external view returns (string memory);

    function nowChi() external view returns (uint256);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    function rho() external view returns (uint64);

    function setDepositCap(uint256 newCap) external;

    function SETTER_ROLE() external view returns (bytes32);

    function setVsr(uint256 newVsr) external;

    function symbol() external view returns (string memory);

    function TAKER_ROLE() external view returns (bytes32);

    function totalAssets() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function vsr() external view returns (uint256);

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

interface IMorphoVaultLike {
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;
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

    function strategyListLength() external view returns (uint256);

    function withdrawalManager() external view returns (address);

}

interface IPSMLike {

    function pocket() external view returns (address);

}

interface IMapleStrategyLike {

    function assetsUnderManagement() external view returns (uint256);

    function withdrawFromStrategy(uint256 amount) external;

}

interface IWithdrawalManagerLike {

    function processRedemptions(uint256 maxSharesToProcess) external;

    function totalShares() external returns (uint256);

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

interface ISuperstateTokenLike is IERC20 {

    function calculateSuperstateTokenOut(uint256, address) external view returns (uint256, uint256, uint256);

    function supportedStablecoins(address stablecoin) external view returns (address sweepDestination, uint256 fee);

}

interface ISSRedemptionLike {

    function calculateUsdcOut(uint256 ustbAmount) external view returns (uint256 usdcOutAmount, uint256 usdPerUstbChainlinkRaw);

    function calculateUstbIn(uint256 usdcOutAmount) external view returns (uint256 ustbInAmount, uint256 usdPerUstbChainlinkRaw);

}

interface IInvestmentManagerLike {

    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;

    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares
    ) external;

    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;

    function escrow() external view returns (address);

}

interface ICentrifugeTokenLike is IERC7540 {

    function claimableCancelDepositRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableAssets);

    function claimableCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (uint256 claimableShares);

    function pendingCancelDepositRequest(uint256 requestId, address controller)
        external view returns (bool isPending);

    function pendingCancelRedeemRequest(uint256 requestId, address controller)
        external view returns (bool isPending);

    function manager() external view returns (address);

    function share() external view returns (address);

    function root() external view returns (address);

    function trancheId() external view returns (bytes16);

    function poolId() external view returns (uint64);

}

interface IPSM3Like {

    function convertToAssets(address asset, uint256 shares) external view returns (uint256);

    function convertToAssetValue(uint256 shares) external view returns (uint256);

    function shares(address account) external view returns (uint256);

}

interface IATokenLike {

    function POOL() external view returns(address);

}

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);

}
