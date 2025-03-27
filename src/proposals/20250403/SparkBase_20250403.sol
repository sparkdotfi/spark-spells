// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  April 3, 2025 Spark Base Proposal
 * @notice Upgrade ALM Controller
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell/26155
 * Vote:   N/A
 */
contract SparkBase_20250403 is SparkPayloadBase {

    address internal constant OLD_ALM_CONTROLLER = Base.ALM_CONTROLLER;
    address internal constant NEW_ALM_CONTROLLER = 0xB94378b5347a3E199AF3575719F67A708a5D8b9B;

    function execute() external {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );
    }

}
