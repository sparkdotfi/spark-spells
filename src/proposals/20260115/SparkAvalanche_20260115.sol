// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Avalanche Proposal
 * @notice Spark Savings - Increase spUSDC Deposit Cap
 * Forum:  https://forum.sky.money/t/january-15-2026-proposed-changes-to-spark-for-upcoming-spell/27585
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x994d54ecdadc8f4a69de921207afe3731f3066f086e63ff6a1fd0d4bbfb51b53
 */
contract SparkAvalanche_20260115 is SparkPayloadAvalanche {

    function execute() external {
        // Spark Savings - Increase spUSDC Deposit Cap
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).setDepositCap(500_000_000e6);
    }

}
