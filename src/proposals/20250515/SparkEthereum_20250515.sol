// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  May 15, 2025 Spark Ethereum Proposal
 * @notice SparkLend Freezer Mom:
 *         - Update Authority
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/atlas-edit-weekly-cycle-proposal-week-of-may-5-2025/26319
 * Vote:   https://vote.makerdao.com/polling/QmcZNZg3
 */
contract SparkEthereum_20250515 is SparkPayloadEthereum {

    function _postExecute() internal override {
        ISparkLendFreezerMom(Ethereum.FREEZER_MOM).setAuthority(0x929d9A1435662357F54AdcF64DcEE4d6b867a6f9);
    }

}
