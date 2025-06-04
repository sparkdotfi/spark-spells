// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

interface IMorpho {
    function setFee(uint256 newFee) external;
    function setFeeRecipient(address newFeeRecipient) external;
}

/**
 * @title  June 12, 2025 Spark Base Proposal
 * @notice 
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell/26372
 * Vote:   https://vote.makerdao.com/polling/QmfPc8Ub
 */
contract SparkBase_20250612 is SparkPayloadBase {

    uint256 internal constant MORPHO_SPARK_USDC_VAULT_FEE = 0.1e18;

    function execute() external {
        IMorpho(Base.MORPHO_VAULT_SUSDC).setFeeRecipient(Base.SPARK_EXECUTOR);
        IMorpho(Base.MORPHO_VAULT_SUSDC).setFee(MORPHO_SPARK_USDC_VAULT_FEE);
    }

}
