// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Avalanche } from "spark-address-registry/Avalanche.sol";

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

import { SparkPayloadAvalanche } from "../../SparkPayloadAvalanche.sol";

/**
 * @title  July 2, 2026 Spark Avalanche Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Add Timelock and Guardian to Avalanche Governance Bridge
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x5f3a7d62d6d26c06890dd0300071d0f22cd4fdd7115c0d9c94577b90f644089c
 */
contract SparkAvalanche_20260702 is SparkPayloadAvalanche {

    uint256 internal constant TIMELOCK_DELAY = 3 days;

    function execute() external {
        IExecutor(Avalanche.SPARK_EXECUTOR).updateDelay(TIMELOCK_DELAY);

        IExecutor(Avalanche.SPARK_EXECUTOR).grantRole(
            IExecutor(Avalanche.SPARK_EXECUTOR).GUARDIAN_ROLE(),
            Avalanche.ALM_OPS_MULTISIG
        );
    }

}
