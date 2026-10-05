// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  October 8, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * Forum:  https://forum.skyeco.com/t/october-8-2026-proposed-changes-to-spark-for-upcoming-spell/28265
 */
contract SparkEthereum_20261008 is SparkPayloadEthereum {

    constructor() {
        PAYLOAD_ARBITRUM = 0xb037C43b433964A2017cd689f535BEb6B0531473;
        PAYLOAD_XLAYER   = 0x3c2B7d559Fd4bd17827B49278FCe1c7d55f39311;
    }

}
