// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

import { IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Base Proposal
 * @notice Spark USDC Morpho Vault - Update Vault Roles
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkBase_20251211 is SparkPayloadBase {

    address internal constant SPARK_USDC_MORPHO_VAULT_CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    function execute() external {
        // Spark USDC Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Base.MORPHO_VAULT_USDC_BC).setCurator(SPARK_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        IMorphoVaultLike(Base.MORPHO_VAULT_USDC_BC).submitGuardian(SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        IMorphoVaultLike(Base.MORPHO_VAULT_USDC_BC).submitTimelock(10 days);
    }

}
