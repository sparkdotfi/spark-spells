// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadBase } from "src/SparkPayloadBase.sol";

/**
 * @title  April 09, 2026 Spark Base Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Deactivate Aave USDC and Fluid sUSDS
 * Forum:  https://forum.skyeco.com/t/april-9-2026-proposed-changes-to-spark-for-upcoming-spell/27804
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x6c889e7be8fba52d9cac4bd2e89c9bcb4ee1952afb40b555e87bf09062cb837f
 */
contract SparkBase_20260409 is SparkPayloadBase {

    function execute() external {
        ForeignController almController = ForeignController(Base.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Base.ALM_RATE_LIMITS);

        // 1. Deactivate Aave USDC

        bytes32 ATOKEN_USDC_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_AAVE_DEPOSIT(),  Base.ATOKEN_USDC);
        bytes32 ATOKEN_USDC_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_AAVE_WITHDRAW(), Base.ATOKEN_USDC);

        rateLimits.setRateLimitData(ATOKEN_USDC_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(ATOKEN_USDC_WITHDRAW_KEY, 0, 0);

        // 2. Deactivate Fluid sUSDS

        bytes32 FLUID_SUSDS_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_DEPOSIT(),  Base.FLUID_SUSDS);
        bytes32 FLUID_SUSDS_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_WITHDRAW(), Base.FLUID_SUSDS);

        rateLimits.setRateLimitData(FLUID_SUSDS_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(FLUID_SUSDS_WITHDRAW_KEY, 0, 0);
    }

}
