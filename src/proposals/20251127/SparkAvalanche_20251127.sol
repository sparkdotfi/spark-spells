// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

/**
 * @title  November 27, 2025 Spark Avalanche Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * Forum:  https://forum.sky.money/t/november-27-2025-proposed-changes-to-spark-for-upcoming-spell/27418
 * Vote:   
 */
contract SparkAvalanche_20251127 is SparkPayloadAvalanche {

    address internal constant NEW_ALM_CONTROLLER = 0x4eE67c8Db1BAa6ddE99d936C7D313B5d31e8fa38;

    function execute() external {
        _upgradeController(Avalanche.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        ForeignController(NEW_ALM_CONTROLLER).setMaxSlippage(Avalanche.ATOKEN_CORE_USDC, 0.99999e18);
    }

}
