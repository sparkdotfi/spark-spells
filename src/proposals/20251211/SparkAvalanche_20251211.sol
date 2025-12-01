// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

/**
 * @title  December 11, 2025 Spark Avalanche Proposal
 * @notice Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC
 * Forum:  https://forum.sky.money/t/december-11-2025-proposed-changes-to-spark-for-upcoming-spell/27481
 * Vote:   
 */
contract SparkAvalanche_20251211 is SparkPayloadAvalanche {

    address internal constant ALM_PROXY_FREEZABLE = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;

    function execute() external {
        // Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC
        ISparkVaultLike(Avalanche.SPARK_VAULT_V2_SPUSDC).grantRole(ISparkVaultLike(Avalanche.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(), ALM_PROXY_FREEZABLE);
    }

}
