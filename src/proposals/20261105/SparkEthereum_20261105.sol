// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from "../../../lib/spark-address-registry/src/Ethereum.sol";

import { MainnetController } from "../../../lib/spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "../../../lib/spark-alm-controller/src/RateLimitHelpers.sol";

import { SLLHelpers, SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  November 5, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Onboard OUSD mint and redeem.
 *         - Onboard the Uniswap v4 OUSD/USDS pool.
 * Forum:  https://forum.skyeco.com/t/november-5-2026-proposed-changes-to-spark-for-upcoming-spell/28351
 */
contract SparkEthereum_20261105 is SparkPayloadEthereum {

    address internal constant OUSD                = 0x9f6F3991D525015a6F8CaF062C83b62fD3AC4436;
    address internal constant BRIDGE_USDC_DEPOSIT = 0xCeB913e6CB36651af7FA4585F6C8F0e81C015A5F;
    address internal constant BRIDGE_OUSD_DEPOSIT = 0x3539f3f7F3A368EAf87315cE56ea2834a6e6a195;

    bytes32 internal constant OUSD_USDS_POOL_ID = 0x710254704dfff19aee863a784a36823eb9c926cae8d3d425080d7c88c144a9c7;

    constructor() {
        // PAYLOAD_BASE = 0xb037C43b433964A2017cd689f535BEb6B0531473;
    }

    function _postExecute() internal override {
        // 4. Onboard OUSD mint and redeem.
        bytes32 transferKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER();

        bytes32 BRIDGE_USDC_OUSD_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, BRIDGE_USDC_DEPOSIT);
        bytes32 BRIDGE_OUSD_USDC_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, OUSD,          BRIDGE_OUSD_DEPOSIT);

        SLLHelpers.setRateLimitData({
            key        : BRIDGE_USDC_OUSD_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 50_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : BRIDGE_OUSD_USDC_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 200_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // 5. Onboard the Uniswap v4 OUSD/USDS pool.
        SLLHelpers.configureUniswapV4Pool({
            controller     : Ethereum.ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : OUSD_USDS_POOL_ID,
            maxSlippage    : 0.999e18,
            tickLower      : 276_314,
            tickUpper      : 276_334,
            maxTickSpacing : 10,
            depositMax     : 10_000_000e18,
            depositSlope   : 50_000_000e18 / uint256(1 days),
            withdrawMax    : type(uint256).max,
            withdrawSlope  : 0,
            swapMax        : 5_000_000e18,
            swapSlope      : 100_000_000e18 / uint256(1 days)
        });
    }

}
