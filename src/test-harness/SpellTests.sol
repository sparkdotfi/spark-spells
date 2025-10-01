// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";

import { ISparkProxyLike } from "../interfaces/Interfaces.sol";

import { SpellRunner } from "./SpellRunner.sol";

abstract contract SpellTests is SpellRunner {

    address internal constant ESM = 0x09e05fF6142F2f9de8B6B65855A1d56B6cfE4c58;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_PayloadsConfigured() external onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; ++i) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);

            if (chainId == ChainIdUtils.Ethereum()) continue;  // Checking only foreign payloads

            address payload = chainData[chainId].payload;

            if (payload == address(0)) continue;

            // A payload is defined for this domain
            // We verify the mainnet spell defines this payload correctly
            address mainnetPayload = _getForeignPayloadFromMainnetSpell(chainId);
            assertEq(mainnetPayload, payload, "Mainnet payload not matching deployed payload");
        }
    }

    function test_ETHEREUM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Ethereum());
    }

    function test_BASE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Base());
    }

    function test_GNOSIS_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Gnosis());
    }

    function test_ARBITRUM_ONE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.ArbitrumOne());
    }

    function test_OPTIMISM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Unichain());
    }

    function test_ETHEREUM_SparkProxyStorage() external onChain(ChainIdUtils.Ethereum()) {
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(ESM),                  1);
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(Ethereum.SPARK_PROXY, 100);
        _executeAllPayloadsAndBridges();

        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(ESM),                  1);
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(Ethereum.SPARK_PROXY, 100);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _checkStorageSlot(address target, uint256 limit) internal view {
        for (uint256 slot; slot < limit; ++slot) {
            bytes32 result = vm.load(address(target), bytes32(uint256(slot)));
            require(result == bytes32(0), "Slot is not zero");
        }
    }

}
