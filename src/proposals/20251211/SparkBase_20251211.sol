// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

import { SparkPayloadBase, SLLHelpers } from "../../SparkPayloadBase.sol";

/**
 * @title  December 11, 2025 Spark Base Proposal
 * @notice Spark USDC Morpho Vault - Update Allocator Role to ALM Proxy Freezable
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/december-11-2025-proposed-changes-to-spark-for-upcoming-spell/27481
 * Vote:   
 */
contract SparkBase_20251211 is SparkPayloadBase {

    address internal constant ALM_PROXY_FREEZABLE = 0xCBA0C0a2a0B6Bb11233ec4EA85C5bFfea33e724d;

    function execute() external {
        // Spark USDC Morpho Vault - Update Allocator Role to ALM Proxy Freezable
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).setIsAllocator(ALM_PROXY_FREEZABLE, true);
    }

}
