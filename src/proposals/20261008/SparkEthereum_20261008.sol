// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  October 8, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Bridge sUSDS to Arbitrum.
 * Forum:  https://forum.skyeco.com/t/october-8-2026-proposed-changes-to-spark-for-upcoming-spell/28265
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xf0bb6c2fd1786746d00ae0a58d6ae63b3c35157079989cbbcabc820ef3a8d35e
 */
contract SparkEthereum_20261008 is SparkPayloadEthereum {

    uint256 internal constant SUSDS_TRANSFER_AMOUNT = 100_000_000e18;

    constructor() {
        // PAYLOAD_ARBITRUM = 0x930e7EFC310F1E62ff3DfC7b60A8FF06d4046887;
        // PAYLOAD_XLAYER   = 0x930e7EFC310F1E62ff3DfC7b60A8FF06d4046887;
    }

    function _postExecute() internal override {
        // 2. Bridge sUSDS to Arbitrum

        _transferAssetFromAlmProxy(Ethereum.SUSDS, Ethereum.SPARK_PROXY, SUSDS_TRANSFER_AMOUNT);

        _sendArbTokens(Ethereum.SUSDS, SUSDS_TRANSFER_AMOUNT);
    }

}
