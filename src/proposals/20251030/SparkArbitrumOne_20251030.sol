// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum, SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  October 30, 2025 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.7
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-30-2025-proposed-changes-to-spark-for-upcoming-spell/27309
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x86f6b4e728e943fedf8ff814808e2d9bc0220f57edae40e3cf3711fb72d2e097
 */
contract SparkArbitrumOne_20251030 is SparkPayloadArbitrumOne {

    address internal constant NEW_CONTROLLER = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;

    function execute() external {
        _upgradeController(Arbitrum.ALM_CONTROLLER, NEW_CONTROLLER);
    }

}
