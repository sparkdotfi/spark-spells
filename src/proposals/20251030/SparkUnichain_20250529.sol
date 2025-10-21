// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadUnichain, Unichain } from "../../SparkPayloadUnichain.sol";

/**
 * @title  October 10, 2025 Spark Unichain Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.7
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-30-2025-proposed-changes-to-spark-for-upcoming-spell/27309
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x86f6b4e728e943fedf8ff814808e2d9bc0220f57edae40e3cf3711fb72d2e097
 */
contract SparkUnichain_20251030 is SparkPayloadUnichain {

    address internal constant NEW_CONTROLLER = 0x7CD6EC14785418aF694efe154E7ff7d9ba99D99b;

    function execute() external {
        _upgradeController(Unichain.ALM_CONTROLLER, NEW_CONTROLLER);
    }

}
