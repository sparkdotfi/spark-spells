// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

/**
 * @title  November 13, 2025 Spark Avalanche Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * Forum:  
 * Vote:   
 */
contract SparkAvalanche_20251113 is SparkPayloadAvalanche {

    address internal constant NEW_ALM_CONTROLLER = 0x4eE67c8Db1BAa6ddE99d936C7D313B5d31e8fa38;
    address internal constant AAVE_ATOKEN_USDC   = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;

    function execute() external {
        _upgradeController(Avalanche.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        ForeignController(NEW_ALM_CONTROLLER).setMaxSlippage(AAVE_ATOKEN_USDC, 0.99e18);
    }

}
