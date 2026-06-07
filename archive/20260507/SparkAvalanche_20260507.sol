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
 * Forum:  https://forum.skyeco.com/t/may-7-2026-proposed-changes-to-spark-for-upcoming-spell/27870
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x2912831b683f5461d7bb4a5702c63ff8d2a4ff93d4422ce0cca0ef29f4a3509c
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x710eb6996204b3df1eedd19d2f8bea9d0d69cdfa85a31c514527d9c212686348
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
