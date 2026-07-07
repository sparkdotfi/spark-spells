// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { Robinhood } from "spark-address-registry/Robinhood.sol";

import { SLLHelpers } from "../../libraries/SLLHelpers.sol";

/**
 * @title  July 16, 2026 Spark Robinhood Proposal
 * @author Phoenix Labs
 * @notice
 * Forum:
 * Vote:
 */
contract SparkRobinhood_20260716 {

    address internal constant PAXOS_USDG_DEPOSIT = 0x17C0F5345d1144fdF670D14719077be3842E5087;

    function execute() external {
        ForeignController controller = ForeignController(Robinhood.ALM_CONTROLLER);

        controller.grantRole(controller.FREEZER(),  Robinhood.ALM_FREEZER_MULTISIG_2);
        controller.revokeRole(controller.FREEZER(), Robinhood.ALM_FREEZER_MULTISIG_1);

        controller.grantRole(controller.RELAYER(),  Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG);
        controller.revokeRole(controller.RELAYER(), Robinhood.ALM_RELAYER_MULTISIG_1);

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                controller.LIMIT_ASSET_TRANSFER(),
                Robinhood.USDG,
                PAXOS_USDG_DEPOSIT
            ),
            Robinhood.ALM_RATE_LIMITS,
            50_000_000e6,
            250_000_000e6 / uint256(1 days),
            6
        );
    }

}
