// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  April 3, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer: Onboard BUIDL-I, USTB, JTRSY, syrupUSDC
 *                                Increase USDC rate limit for SparkLend
 *         SparkLend: Increase USDC Supply/Borrow Caps
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell/26155
 * Vote:   https://vote.makerdao.com/polling/QmSwQ6Wc
 *         https://vote.makerdao.com/polling/QmTE29em
 *         https://vote.makerdao.com/polling/QmehvjH9
 *         https://vote.makerdao.com/polling/QmSytTo4
 *         https://vote.makerdao.com/polling/QmZGQhkG
 *         https://vote.makerdao.com/polling/QmWQCbns
 */
contract SparkEthereum_20250403 is SparkPayloadEthereum {

    address internal constant OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant NEW_ALM_CONTROLLER = 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c;

    constructor() {
        PAYLOAD_ARBITRUM = address(0);  // TODO
        PAYLOAD_BASE     = address(0);  // TODO
    }

    function _postExecute() internal override {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );
    }

}
