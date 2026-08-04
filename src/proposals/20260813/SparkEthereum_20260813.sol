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
 * Forum:  https://forum.skyeco.com/t/august-13-2026-proposed-changes-to-spark-for-upcoming-spell/28135/8
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x101ed4ff7ef77f8e4a6db6af4bbf053b703001c0245a1e166babb8ba6ad633fb
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0xf99d50e34900ea8f54c90053584f758d2a6d1ddbbe77a8c8d751e2c5a8fd0493
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x3240fc78276a2f4898188809464b3357124b2c42065f55a46a7a7254eabd0f82
 */
contract SparkEthereum_20260813 is SparkPayloadEthereum {

    bytes32 internal constant USDG_USDS_POOL_ID  = 0x28adc7179a8a83c3379955d59563c0fec33eadfa83946b447af289190ff5fcff;
    bytes32 internal constant RLUSD_USDS_POOL_ID = 0x9035721b23481db3888fd201b9c2b26dbc3af60258bca65e669f2ed98dc8eb4f;

    address internal constant CURVE_RLUSD_USDC = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 1_756_359e18;

    function _postExecute() internal override {
        // 1. Onboard Uniswap v4 USDG/USDS Pool.
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
