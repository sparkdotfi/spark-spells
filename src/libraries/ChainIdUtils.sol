// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.23;

import { Domain } from "xchain-helpers/testing/Domain.sol";

library ChainIdUtils {

    function toDomainString(uint256 id) internal pure returns (string memory domainString) {
        if (id == 1)     return "Ethereum";
        if (id == 100)   return "Gnosis";
        if (id == 8453)  return "Base";
        if (id == 42161) return "ArbitrumOne";
        if (id == 10)    return "Optimism";
        if (id == 130)   return "Unichain";
        if (id == 43114) return "Avalanche";
        if (id == 4663)  return "Robinhood";
        if (id == 196)   return "XLayer";

        require(false, "ChainIdUtils/invalid-chain-id");
    }

    function Ethereum() internal pure returns (uint256 chainId) {
        return 1;
    }

    function Gnosis() internal pure returns (uint256 chainId) {
        return 100;
    }

    function Base() internal pure returns (uint256 chainId) {
        return 8453;
    }

    function ArbitrumOne() internal pure returns (uint256 chainId) {
        return 42161;
    }

    function Optimism() internal pure returns (uint256 chainId) {
        return 10;
    }

    function Unichain() internal pure returns (uint256 chainId) {
        return 130;
    }

    function Avalanche() internal pure returns (uint256 chainId) {
        return 43114;
    }

    function Robinhood() internal pure returns (uint256 chainId) {
        return 4663;
    }

    function XLayer() internal pure returns (uint256 chainId) {
        return 196;
    }

}
