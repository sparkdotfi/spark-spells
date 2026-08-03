// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

/**
 * @title  August 13, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Onboard Uniswap v4 USDG/USDS Pool.
 *         - Onboard Uniswap v4 rlUSD/USDS Pool.
 *         - Onboard Curve rlUSD/USDC for Swaps.
 *         Spark Treasury:
 *         - Transfer Excess USDS for Buybacks.
 * Forum:  TBD
 * Vote:   TBD
 */
contract SparkEthereum_20260813 is SparkPayloadEthereum {

    bytes32 internal constant USDG_USDS_POOL_ID  = 0x28adc7179a8a83c3379955d59563c0fec33eadfa83946b447af289190ff5fcff;
    bytes32 internal constant RLUSD_USDS_POOL_ID = 0x9035721b23481db3888fd201b9c2b26dbc3af60258bca65e669f2ed98dc8eb4f;

    address internal constant CURVE_RLUSD_USDC = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 1_756_359e18;

    function _postExecute() internal override {
        // 1. Onboard Uniswap v4 USDG/USDS Pool.
        // Doc gave the 0.999-1.001 band as +276_314/+276_334 (the PYUSD/USDS-style ordering, currency0 = 6-decimal
        // token). In this pool USDS (18 decimals) is currency0 and USDG (6 decimals) is currency1 — the opposite
        // ordering — so the same 0.999-1.001 band lands at the negated ticks. Verified against the live pool's
        // actual current tick (-276_325) via StateView.getSlot0 at the fork block.
        SLLHelpers.configureUniswapV4Pool({
            controller     : Ethereum.ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : USDG_USDS_POOL_ID,
            maxSlippage    : 0.999e18,
            tickLower      : -276_334,
            tickUpper      : -276_314,
            maxTickSpacing : 10,
            depositMax     : 10_000_000e18,
            depositSlope   : 100_000_000e18 / uint256(1 days),
            withdrawMax    : type(uint256).max,
            withdrawSlope  : 0,
            swapMax        : 5_000_000e18,
            swapSlope      : 200_000_000e18 / uint256(1 days)
        });

        // 2. Onboard Uniswap v4 rlUSD/USDS Pool.
        SLLHelpers.configureUniswapV4Pool({
            controller     : Ethereum.ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : RLUSD_USDS_POOL_ID,
            maxSlippage    : 0.999e18,
            tickLower      : -10,
            tickUpper      : 10,
            maxTickSpacing : 10,
            depositMax     : 10_000_000e18,
            depositSlope   : 50_000_000e18 / uint256(1 days),
            withdrawMax    : type(uint256).max,
            withdrawSlope  : 0,
            swapMax        : 5_000_000e18,
            swapSlope      : 100_000_000e18 / uint256(1 days)
        });

        // 3. Onboard Curve rlUSD/USDC for Swaps.
        _configureCurvePool({
            controller    : Ethereum.ALM_CONTROLLER,
            pool          : CURVE_RLUSD_USDC,
            maxSlippage   : 0.999e18,
            swapMax       : 5_000_000e18,
            swapSlope     : 25_000_000e18 / uint256(1 days),
            depositMax    : 0,
            depositSlope  : 0,
            withdrawMax   : 0,
            withdrawSlope : 0
        });

        // 4. Transfer Excess USDS for Buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
