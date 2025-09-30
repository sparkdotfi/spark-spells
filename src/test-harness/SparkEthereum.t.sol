// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { SparkEthereumTests } from "./SparkEthereumTests.sol";

contract SparkEthereumTesting is SparkEthereumTests {

    constructor() {
        _spellId   = 20251002;
        _blockDate = "2025-09-29T14:06:00Z";
    }

}
