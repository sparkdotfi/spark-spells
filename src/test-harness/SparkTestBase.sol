// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { SparkEthereumTests } from "./SparkEthereumTests.sol";

import { console2 } from "forge-std/console2.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IRateLimits } from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {VmSafe } from "forge-std/Vm.sol";

/// @dev convenience contract meant to be the single point of entry for all
/// spell-specifictest contracts
abstract contract SparkTestBase is SparkEthereumTests {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    // enum Category {
    //     // TODO
    // };

    struct SLLIntegration {
        string   label;
        string category;  // TODO enum
        bytes32  entryId;
        bytes32  exitId;
    }

    SLLIntegration[] public arbitrumSllIntegrations;
    SLLIntegration[] public baseSllIntegrations;
    SLLIntegration[] public ethereumSllIntegrations;
    SLLIntegration[] public optimismSllIntegrations;
    SLLIntegration[] public unichainSllIntegrations;

    uint256 START_BLOCK = 21029247;

    EnumerableSet.Bytes32Set private _arbitrumRateLimitKeys;
    EnumerableSet.Bytes32Set private _baseRateLimitKeys;
    EnumerableSet.Bytes32Set private _ethereumRateLimitKeys;
    EnumerableSet.Bytes32Set private _optimismRateLimitKeys;
    EnumerableSet.Bytes32Set private _unichainRateLimitKeys;

    function getAllRateLimitKeys() public returns (bytes32[] memory uniqueKeys) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IRateLimits.RateLimitDataSet.selector;

        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            Ethereum.ALM_RATE_LIMITS,
            topics
        );

        // Collect unique keys from topics[1] (`key`)
        for (uint256 i = 0; i < allLogs.length; i++) {
            console2.logBytes32(allLogs[i].topics[0]);
            if (allLogs[i].topics.length > 1) {
                ( uint256 maxAmount,,, )
                    = abi.decode(allLogs[i].data, (uint256,uint256,uint256,uint256));
                if (maxAmount == 0) continue;
                _ethereumRateLimitKeys.add(allLogs[i].topics[1]);
            }
        }

        console2.log("_ethereumRateLimitKeys.length", _ethereumRateLimitKeys.length());
        console2.log("allLogs.length", allLogs.length);
        // console2.log("_ethereumRateLimitKeys.values", _ethereumRateLimitKeys.values());

        // Copy to memory (OZ returns a memory array view of the storage vector)
        uniqueKeys = _ethereumRateLimitKeys.values();

        // // IMPORTANT: clear the storage set so nothing persists between calls
        // _ethereumRateLimitKeys.clear();
    }

    function _beforeExecution() internal {
        // set all storage, assert
    }

    function _afterExecution() internal {
        // set all storage using beforeExecution
        // override to add more values, assert
    }

    function test_test() public {
        bytes32[] memory uniqueKeys = getAllRateLimitKeys();
        console2.log("uniqueKeys.length", uniqueKeys.length);
        for (uint256 i = 0; i < uniqueKeys.length; i++) {
            console2.logBytes32(uniqueKeys[i]);
        }
    }

}
