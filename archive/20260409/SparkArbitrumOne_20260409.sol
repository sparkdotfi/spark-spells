// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadArbitrumOne } from "src/SparkPayloadArbitrumOne.sol";

/**
 * @title  April 09, 2026 Spark Arbitrum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Deactivate Aave USDC and Fluid sUSDS
 * Forum:  https://forum.skyeco.com/t/april-9-2026-proposed-changes-to-spark-for-upcoming-spell/27804
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x6c889e7be8fba52d9cac4bd2e89c9bcb4ee1952afb40b555e87bf09062cb837f
 */
contract SparkArbitrumOne_20260409 is SparkPayloadArbitrumOne {

    function execute() external {
        ForeignController almController = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Arbitrum.ALM_RATE_LIMITS);

        // 1. Deactivate Aave USDC

        bytes32 ATOKEN_USDC_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_AAVE_DEPOSIT(),  Arbitrum.ATOKEN_USDC);
        bytes32 ATOKEN_USDC_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_AAVE_WITHDRAW(), Arbitrum.ATOKEN_USDC);

        rateLimits.setRateLimitData(ATOKEN_USDC_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(ATOKEN_USDC_WITHDRAW_KEY, 0, 0);

        // 2. Deactivate Fluid sUSDS

        bytes32 FLUID_SUSDS_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_DEPOSIT(),  Arbitrum.FLUID_SUSDS);
        bytes32 FLUID_SUSDS_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_WITHDRAW(), Arbitrum.FLUID_SUSDS);

        rateLimits.setRateLimitData(FLUID_SUSDS_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(FLUID_SUSDS_WITHDRAW_KEY, 0, 0);
    }

}
