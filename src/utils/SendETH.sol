// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

// Allows you to bypass the payable fallback function and send ETH to a contract
contract SendETH {

    constructor(address to) payable {
        selfdestruct(payable(to));
    }

}
