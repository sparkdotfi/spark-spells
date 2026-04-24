// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Avalanche }  from "spark-address-registry/Avalanche.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadAvalanche } from "src/SparkPayloadAvalanche.sol";

/**
 * @title  May 7, 2026 Spark Avalanche Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Offboard Aave USDC.
 * Forum:  
 * Vote:   
 */
contract SparkAvalanche_20260507 is SparkPayloadAvalanche {

    function execute() external {
        // 2. Offboard Aave USDC.

        ForeignController almController = ForeignController(Avalanche.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Avalanche.ALM_RATE_LIMITS);

        bytes32 aaveDepositKey  = almController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey = almController.LIMIT_AAVE_WITHDRAW();

        bytes32 ATOKEN_CORE_USDC_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Avalanche.ATOKEN_CORE_USDC);
        bytes32 ATOKEN_CORE_USDC_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Avalanche.ATOKEN_CORE_USDC);

        rateLimits.setRateLimitData(ATOKEN_CORE_USDC_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(ATOKEN_CORE_USDC_WITHDRAW_KEY, 0, 0);
    }

}
