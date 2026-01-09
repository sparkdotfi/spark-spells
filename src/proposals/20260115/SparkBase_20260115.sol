// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

import { IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Base Proposal
 * @notice Spark USDC Morpho Vault - Update Vault Roles
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-15-2026-proposed-changes-to-spark-for-upcoming-spell/27585
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x85f242a3d35252380a21ae3e5c80b023122e74af95698a301b541c7b610ffee8
 */
contract SparkBase_20260115 is SparkPayloadBase {

    address internal constant CURATOR_MULTISIG  = 0x0f963A8A8c01042B69054e787E5763ABbB0646A3;
    address internal constant GUARDIAN_MULTISIG = 0xf5748bBeFa17505b2F7222B23ae11584932C908B;

    function execute() external {
        // Spark USDC Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).setCurator(CURATOR_MULTISIG);
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).submitGuardian(GUARDIAN_MULTISIG);
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).submitTimelock(10 days);
    }

}
