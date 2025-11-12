// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadOptimism, Optimism } from "../../SparkPayloadOptimism.sol";


/**
 * @title  October 30, 2025 Spark Optimism Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.7
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-30-2025-proposed-changes-to-spark-for-upcoming-spell/27309
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x86f6b4e728e943fedf8ff814808e2d9bc0220f57edae40e3cf3711fb72d2e097
 */
contract SparkOptimism_20251030 is SparkPayloadOptimism {

    address internal constant NEW_CONTROLLER = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;

    function execute() external {
        _upgradeController(Optimism.ALM_CONTROLLER, NEW_CONTROLLER);
    }

}
