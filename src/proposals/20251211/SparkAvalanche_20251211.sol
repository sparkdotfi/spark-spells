// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like, IALMProxyFreezableLike } from "../../interfaces/Interfaces.sol";

/**
 * @title  December 11, 2025 Spark Avalanche Proposal
 * @notice Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC
 * Forum:  https://forum.sky.money/t/december-11-2025-proposed-changes-to-spark-for-upcoming-spell/27481
 * Vote:   
 */
contract SparkAvalanche_20251211 is SparkPayloadAvalanche {

    address internal constant ALM_PROXY_FREEZABLE = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;

    function execute() external {
        // Grant CONTROLLER Role for Relayer 1 and 2 on ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxy(ALM_PROXY_FREEZABLE).CONTROLLER(),
            Avalanche.ALM_RELAYER
        );
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxy(ALM_PROXY_FREEZABLE).CONTROLLER(),
            Avalanche.ALM_RELAYER2
        );
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxyFreezableLike(ALM_PROXY_FREEZABLE).FREEZER(),
            Avalanche.ALM_FREEZER
        );

        // Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).revokeRole(ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG);
        ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).grantRole(ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(),  ALM_PROXY_FREEZABLE);
    }

}
