// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { SparkPayloadBase, SLLHelpers } from "../../SparkPayloadBase.sol";

/**
 * @title  November 27, 2025 Spark Base Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkBase_20251127 is SparkPayloadBase {

    using SLLHelpers for address;

    address internal constant NEW_ALM_CONTROLLER = 0x86036CE5d2f792367C0AA43164e688d13c5A60A8;

    function execute() external {
        _upgradeController(Base.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        ForeignController(NEW_ALM_CONTROLLER).setMaxSlippage(Base.ATOKEN_USDC, 0.99e18);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(Base.MORPHO_VAULT_SUSDC, 1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Base.FLUID_SUSDS,        1, 10);
    }

}
