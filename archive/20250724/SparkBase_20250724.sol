// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController }               from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  June 24, 2025 Spark Base Proposal
 * @notice Spark Liquidity Layer:
 *         - Increase Spark USDC Morpho vault rate limits
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/july-24-2025-proposed-changes-to-spark-for-upcoming-spell/26796
 * Vote:   https://vote.sky.money/polling/QmSnpq5K
 */
contract SparkBase_20250724 is SparkPayloadBase {

    function execute() external {
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                ForeignController(Base.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
                Base.MORPHO_VAULT_SUSDC
            ),
            Base.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            "vaultDepositLimit",
            6
        );
    }

}
