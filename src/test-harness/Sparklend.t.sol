// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { SparklendTests } from "./SparklendTests.sol";

contract SparklendTesting is SparklendTests {

    constructor() {
        _spellId   = 20251002;
        _blockDate = "2025-09-29T14:06:00Z";
    }

}
