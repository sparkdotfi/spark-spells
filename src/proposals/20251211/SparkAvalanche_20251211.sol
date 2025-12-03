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
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x007a555d46f2c215b7d69163e763f03c3b91f31cd43dd08de88a1531631a4766
 */
contract SparkAvalanche_20251211 is SparkPayloadAvalanche {

    function execute() external {
        // Grant CONTROLLER Role for Relayer 1 and 2 on Avalanche.ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxy         proxy = IALMProxy(Avalanche.ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        proxy.grantRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER);
        proxy.grantRole(proxy.CONTROLLER(),                               Avalanche.ALM_RELAYER2);
        proxy.grantRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Avalanche.ALM_FREEZER);

        // Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC
        vault.revokeRole(vault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG);
        vault.grantRole(vault.SETTER_ROLE(),  Avalanche.ALM_PROXY_FREEZABLE);
    }

}
