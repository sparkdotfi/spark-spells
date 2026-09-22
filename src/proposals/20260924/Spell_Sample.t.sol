// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract SparkEthereum_11111_SLLTests is SparkLiquidityLayerTests {

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 1111;
        _blockDate = 1790070959;
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }

        super.deal(token, to, amount);
    }

}

contract SparkEthereum_1111_SpellTests is SpellTests {

    constructor() {
        _spellId   = 1111;
        _blockDate = 1790070959;
    }

}
