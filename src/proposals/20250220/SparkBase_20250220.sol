// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";
import { ForeignController }               from "spark-alm-controller/src/ForeignController.sol";

/**
 * @title  Feb 20, 2025 Spark Base Proposal
 * @notice Spark Liquidity Layer: Increase PSM Rate Limits
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/feb-20-2025-proposed-changes-to-spark-for-upcoming-spell/25951
 * Vote:   https://vote.makerdao.com/polling/QmUEJbje#poll-detail
 */
contract SparkBase_20250220 is SparkPayloadBase {

    function execute() external { 
        // PSM USDC
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
                Base.USDC
            ),
            Base.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            "psmUsdcDepositLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_WITHDRAW(),
                Base.USDC
            ),
            Base.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            "psmUsdcWithdrawLimit",
            6
        );

        // PSM USDS
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
                Base.USDS
            ),
            Base.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmUsdsDepositLimit",
            18
        );

        // PSM sUSDS
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                ForeignController(Base.ALM_CONTROLLER).LIMIT_PSM_DEPOSIT(),
                Base.SUSDS
            ),
            Base.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmSusdsDepositLimit",
            18
        );
    }

}
