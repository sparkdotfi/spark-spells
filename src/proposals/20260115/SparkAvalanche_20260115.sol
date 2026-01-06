// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Avalanche Proposal
 * @notice Spark Savings - Increase spUSDC Deposit Cap
 * Forum:  
 * Vote:   
 */
contract SparkAvalanche_20260115 is SparkPayloadAvalanche {

    function execute() external {
        // Spark Savings - Increase spUSDC Deposit Cap
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).setDepositCap(500_000_000e6);
    }

}
