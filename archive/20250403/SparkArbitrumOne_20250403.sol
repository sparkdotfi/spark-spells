// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadArbitrumOne, Arbitrum } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  April 3, 2025 Spark Arbitrum Proposal
 * @notice Upgrade ALM Controller
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell/26155
 * Vote:   N/A
 */
contract SparkArbitrumOne_20250403 is SparkPayloadArbitrumOne {

    address internal constant OLD_ALM_CONTROLLER = Arbitrum.ALM_CONTROLLER;
    address internal constant NEW_ALM_CONTROLLER = 0x98f567464e91e9B4831d3509024b7868f9F79ee1;

    function execute() external {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );
    }

}
