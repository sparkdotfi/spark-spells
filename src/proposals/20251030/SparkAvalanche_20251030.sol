// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  Oct 30, 2025 Spark Avalanche Proposal
 * @notice Spark Savings - Increase spUSDC Vault Deposit Cap
 * Forum:  https://forum.sky.money/t/october-30-2025-proposed-changes-to-spark-for-upcoming-spell/27309
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x58549e11044e7c8dfecd9a60c8ecb8e77d42dbef46a1db64c09e7d9540102b1c
 */
contract SparkAvalanche_20251030 is SparkPayloadAvalanche {

    function execute() external {
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).setDepositCap(150_000_000e6);
    }

}
