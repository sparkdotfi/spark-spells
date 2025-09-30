// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils } from "../libraries/ChainId.sol";

import { SparkEthereumTests } from "./SparkEthereumTests.sol";

contract SparkEthereumTesting is SparkEthereumTests {

    constructor() {
        _spellId   = 20251002;
        _blockDate = "2025-09-29T14:06:00Z";
    }

}
