// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

import { IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

interface IALMProxyFreezableLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

/**
 * @title  June 4, 2026 Spark Base Proposal
 * @notice Spark Liquidity Layer - Update ALM Proxy Freezable
 * @author Phoenix Labs
 * Forum:  https://forum.skyeco.com/t/june-4-2026-proposed-changes-to-spark-for-upcoming-spell/27931
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x75c80c3b462ab1efe3aa2cb919e97e487ae66d0c62265d204fe9499499cc7e6d
 */
contract SparkBase_20260604 is SparkPayloadBase {

    address internal constant NEW_ALM_PROXY_FREEZABLE = 0x92d7B06e5844e67174AE9E86bdCb06428482DDF9;

    function execute() external {
        // Grant ALLOCATOR Role for Relayer 1 and 2 on NEW_ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(NEW_ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Base.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Base.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   Base.ALM_FREEZER_MULTISIG);

        // Spark USDC Morpho Vault - Update Allocator Role to New ALM Proxy Freezable
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).setIsAllocator(Base.ALM_PROXY_FREEZABLE, false);
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).setIsAllocator(NEW_ALM_PROXY_FREEZABLE,  true);
    }

}
