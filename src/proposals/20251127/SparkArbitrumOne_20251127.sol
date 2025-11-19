// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { Arbitrum, SparkPayloadArbitrumOne, SLLHelpers } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  November 27, 2025 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-27-2025-proposed-changes-to-spark-for-upcoming-spell/27418
 * Vote:   
 */
contract SparkArbitrumOne_20251127 is SparkPayloadArbitrumOne {

    using SLLHelpers for address;

    address internal constant NEW_ALM_CONTROLLER = 0xC40611AC4Fff8572Dc5F02A238176edCF15Ea7ba;

    function execute() external {
        _upgradeController(Arbitrum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(Arbitrum.FLUID_SUSDS, 1, 10);

        ForeignController(NEW_ALM_CONTROLLER).setMaxSlippage(Arbitrum.ATOKEN_USDC, 0.99999e18);
    }

}
