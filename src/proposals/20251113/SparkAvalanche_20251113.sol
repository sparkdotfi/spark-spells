// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  November 13, 2025 Spark Avalanche Proposal
 * @notice Spark Savings - Increase spUSDC Vault Deposit Cap
 * Forum:  https://forum.sky.money/t/november-13-2025-proposed-changes-to-spark-for-upcoming-spell/27354
 * Vote:   
 */
contract SparkAvalanche_20251113 is SparkPayloadAvalanche {

    function execute() external {
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).setDepositCap(250_000_000e6);
    }

}
