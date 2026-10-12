// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  September 24, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Treasury:
 *         - Transfer the October 2026 monthly grants to the Spark Foundation and the Spark Assets Foundation.
 *         - Transfer USDS to the buyback executor to fund SPK buybacks.
 * Forum:  https://forum.skyeco.com/t/september-24-2026-proposed-changes-to-spark-for-upcoming-spell/28237
 */
contract SparkEthereum_20260924 is SparkPayloadEthereum {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 972_485e18;

    function _postExecute() internal override {
        // 1. Transfer the October 2026 monthly grants to the Spark Foundation and the Spark Assets Foundation.
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       SPARK_FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);

        // 2. Transfer USDS to the buyback executor to fund SPK buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
