// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadUnichain, Unichain } from "../../SparkPayloadUnichain.sol";

/**
 * @title  October 30, 2025 Spark Unichain Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkUnichain_20251030 is SparkPayloadUnichain {

    address internal constant NEW_CONTROLLER = 0xF16DE710899C7bdd6D46873265392CCA68e5D5bA;

    function execute() external {
        _upgradeController(Unichain.ALM_CONTROLLER, NEW_CONTROLLER);
    }

}
