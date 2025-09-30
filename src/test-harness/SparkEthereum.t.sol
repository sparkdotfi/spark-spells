// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils } from "../libraries/ChainId.sol";

import { SparkEthereumTests } from "./SparkEthereumTests.sol";

contract SparkEthereumTesting is SparkEthereumTests {

    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;
    address internal constant NEW_ALM_CONTROLLER_BASE = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;

    address internal constant BASE_PAYLOAD = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
    address internal constant ETHEREUM_PAYLOAD = 0x7B28F4Bdd7208fe80916EBC58611Eb72Fb6A09Ed;

    constructor() {
        _spellId = 20250918;
        _blockDate = "2025-09-15T16:42:00Z";

        _previousEthereumController = Ethereum.ALM_CONTROLLER;
        _newEthereumController      = NEW_ALM_CONTROLLER_ETHEREUM;
        _previousBaseController     = Base.ALM_CONTROLLER;
        _newBaseController          = NEW_ALM_CONTROLLER_BASE;
        _basePayload                = BASE_PAYLOAD;
        _ethereumPayload            = ETHEREUM_PAYLOAD;
    }

}
