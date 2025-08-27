// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  September 4, 2025 Spark Base Proposal
 * @notice Spark USDC Morpho Vault:
 *         - Reduce Vault Fee
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/september-4-2025-proposed-changes-to-spark-for-upcoming-spell/27102
 * Vote:   
 */
contract SparkBase_20250904 is SparkPayloadBase {

    uint256 internal constant MORPHO_SPARK_USDC_VAULT_FEE = 0.01e18;

    function execute() external {
        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).setFee(MORPHO_SPARK_USDC_VAULT_FEE);
    }

}
