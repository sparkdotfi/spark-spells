// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadUnichain, Unichain } from "../../SparkPayloadUnichain.sol";

/**
 * @title  November 27, 2025 Spark Unichain Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-27-2025-proposed-changes-to-spark-for-upcoming-spell/27418
 * Vote:   
 */
contract SparkUnichain_20251127 is SparkPayloadUnichain {

    address internal constant NEW_CONTROLLER = 0xF16DE710899C7bdd6D46873265392CCA68e5D5bA;

    function execute() external {
        _upgradeController(Unichain.ALM_CONTROLLER, NEW_CONTROLLER);
    }

}
