// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import '../../../src/test-harness/SparkTestBase.sol';

import { ChainIdUtils } from '../../../src/libraries/ChainId.sol';

interface SparkLendFreezerMom {
    function authority() external view returns (address);
}

contract SparkEthereum_20250501Test is SparkTestBase {

    constructor() {
        id = "20250515";
    }

    function setUp() public {
        setupDomains("2025-05-06T17:20:00Z");

        deployPayloads();
    }

    function test_ETHEREUM_sparkLend_freezerMomAuthorityUpdate() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(SparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), Ethereum.CHIEF);

        executeAllPayloadsAndBridges();

        assertEq(SparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), 0x929d9A1435662357F54AdcF64DcEE4d6b867a6f9);
    }

}
