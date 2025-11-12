// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { Arbitrum, SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  November 27, 2025 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkArbitrumOne_20251127 is SparkPayloadArbitrumOne {

    address internal constant NEW_ALM_CONTROLLER = 0xC40611AC4Fff8572Dc5F02A238176edCF15Ea7ba;

    function execute() external {
        _upgradeController(Arbitrum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        ForeignController(NEW_ALM_CONTROLLER).setMaxSlippage(Arbitrum.ATOKEN_USDC, 0.99e18);

        ForeignController(NEW_ALM_CONTROLLER).setMaxExchangeRate(Arbitrum.FLUID_SUSDS, 1e36, 1e36);
    }

}
