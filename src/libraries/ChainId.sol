// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;
import { Domain } from "xchain-helpers/testing/Domain.sol";

// TODO: MDL, check if this custom type is even worth it.

type ChainId is uint256;
using ChainIdUtils for ChainId global;
using { equals as == } for ChainId global;
using { notEquals as != } for ChainId global;

function equals(ChainId left, ChainId right) pure returns(bool) {
    return ChainId.unwrap(left) == ChainId.unwrap(right);
}

function notEquals(ChainId left, ChainId right) pure returns(bool) {
    return ChainId.unwrap(left) != ChainId.unwrap(right);
}

library ChainIdUtils {
    function fromDomain(Domain memory domain) internal pure returns (ChainId) {
        return fromUint(domain.chain.chainId);
    }

    function fromUint(uint256 id) internal pure returns (ChainId chainId) {
        if (id == 1) return ChainId.wrap(id);
        if (id == 100) return ChainId.wrap(id);
        if (id == 8453) return ChainId.wrap(id);
        if (id == 42161) return ChainId.wrap(id);
        if (id == 10) return ChainId.wrap(id);
        if (id == 130) return ChainId.wrap(id);

        require(false, "ChainIdUtils/invalid-chain-id");
    }

    function toDomainString(ChainId id) internal pure returns (string memory domainString) {
        if (ChainId.unwrap(id) == 1) return "Ethereum";
        if (ChainId.unwrap(id) == 100) return "Gnosis";
        if (ChainId.unwrap(id) == 8453) return "Base";
        if (ChainId.unwrap(id) == 42161) return "ArbitrumOne";
        if (ChainId.unwrap(id) == 10) return "Optimism";
        if (ChainId.unwrap(id) == 130) return "Unichain";

        require(false, "ChainIdUtils/invalid-chain-id");
    }

    function Ethereum() internal pure returns (ChainId) {
        return ChainId.wrap(1);
    }

    function Gnosis() internal pure returns (ChainId) {
        return ChainId.wrap(100);
    }

    function Base() internal pure returns (ChainId) {
        return ChainId.wrap(8453);
    }

    function ArbitrumOne() internal pure returns (ChainId) {
        return ChainId.wrap(42161);
    }

    function Optimism() internal pure returns (ChainId) {
        return ChainId.wrap(10);
    }

    function Unichain() internal pure returns (ChainId) {
        return ChainId.wrap(130);
    }
}
