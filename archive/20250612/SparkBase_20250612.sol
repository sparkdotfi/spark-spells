// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  June 12, 2025 Spark Base Proposal
 * @notice Morpho USDC Vault:
 *         - Set fee and fee recipient
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/june-12-2025-proposed-changes-to-spark-for-upcoming-spell/26559
 * Vote:   https://vote.sky.money/polling/QmdyVQok
 */
contract SparkBase_20250612 is SparkPayloadBase {

    uint256 internal constant MORPHO_SPARK_USDC_VAULT_FEE = 0.1e18;

    function execute() external {
        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).setFeeRecipient(Base.ALM_PROXY);
        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).setFee(MORPHO_SPARK_USDC_VAULT_FEE);
    }

}
