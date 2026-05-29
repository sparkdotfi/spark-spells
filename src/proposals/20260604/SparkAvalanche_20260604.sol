// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadAvalanche, Avalanche } from "../../SparkPayloadAvalanche.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

interface IALMProxyFreezableLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

/**
 * @title  June 4, 2026 Spark Avalanche Proposal
 * @notice Spark Liquidity Layer - Update ALM Proxy Freezable
 * @author Phoenix Labs
 * Forum:  https://forum.skyeco.com/t/june-4-2026-proposed-changes-to-spark-for-upcoming-spell/27931
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x75c80c3b462ab1efe3aa2cb919e97e487ae66d0c62265d204fe9499499cc7e6d
 */
contract SparkAvalanche_20260604 is SparkPayloadAvalanche {

    address internal constant NEW_ALM_PROXY_FREEZABLE = 0x93c81ADc7F98FdBC8C7a15eCBeD312c8F6adbcB3;

    function execute() external {
        // Grant ALLOCATOR Role for Relayer 1 and 2 on NEW_ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(NEW_ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like      vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Avalanche.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Avalanche.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   Avalanche.ALM_FREEZER_MULTISIG);

        // Spark Savings - Update Setter Role to New ALM Proxy Freezable for spUSDC
        vault.revokeRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE);
        vault.grantRole(vault.SETTER_ROLE(),  NEW_ALM_PROXY_FREEZABLE);
    }

}
