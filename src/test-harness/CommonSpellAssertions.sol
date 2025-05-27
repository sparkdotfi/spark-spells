// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Address } from '../libraries/Address.sol';

import { Base } from 'spark-address-registry/Base.sol';

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";

import { SpellRunner } from "./SpellRunner.sol";

/// @dev assertions that make sense to run on every chain where a spark spell
/// can be executed
abstract contract CommonSpellAssertions is SpellRunner {
    function test_ETHEREUM_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.Ethereum());
    }

    function test_BASE_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.Base());
    }

    function test_GNOSIS_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.Gnosis());
    }

    function test_ARBITRUM_ONE_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.ArbitrumOne());
    }

    function test_OPTIMISM_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_PayloadBytecodeMatches() public {
        _assertPayloadBytecodeMatches(ChainIdUtils.Unichain());
    }

    function _assertPayloadBytecodeMatches(ChainId chainId) private onChain(chainId) {
        address actualPayload = chainData[chainId].payload;
        vm.skip(actualPayload == address(0));
        require(Address.isContract(actualPayload), "PAYLOAD IS NOT A CONTRACT");
        address expectedPayload = deployPayload(chainId);

        uint256 expectedBytecodeSize = expectedPayload.code.length;
        uint256 actualBytecodeSize   = actualPayload.code.length;

        uint256 metadataLength = _getBytecodeMetadataLength(expectedPayload);
        assertTrue(metadataLength <= expectedBytecodeSize);
        expectedBytecodeSize -= metadataLength;

        metadataLength = _getBytecodeMetadataLength(actualPayload);
        assertTrue(metadataLength <= actualBytecodeSize);
        actualBytecodeSize -= metadataLength;

        assertEq(actualBytecodeSize, expectedBytecodeSize);

        uint256 size = actualBytecodeSize;
        uint256 expectedHash;
        uint256 actualHash;

        assembly {
            let ptr := mload(0x40)

            extcodecopy(expectedPayload, ptr, 0, size)
            expectedHash := keccak256(ptr, size)

            extcodecopy(actualPayload, ptr, 0, size)
            actualHash := keccak256(ptr, size)
        }

        assertEq(actualHash, expectedHash);
    }

    function _getBytecodeMetadataLength(address a) internal view returns (uint256 length) {
        // The Solidity compiler encodes the metadata length in the last two bytes of the contract bytecode.
        assembly {
            let ptr  := mload(0x40)
            let size := extcodesize(a)
            if iszero(lt(size, 2)) {
                extcodecopy(a, ptr, sub(size, 2), 2)
                length := mload(ptr)
                length := shr(240, length)
                length := add(length, 2)  // The two bytes used to specify the length are not counted in the length
            }
            // Return zero if the bytecode is shorter than two bytes.
        }
    }
}
