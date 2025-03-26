// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

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

    address internal constant JTRSY_VAULT = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;

    address internal constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    constructor() {
        PAYLOAD_ARBITRUM = address(0);  // TODO
        PAYLOAD_BASE     = address(0);  // TODO
    }

    function _postExecute() internal override {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );

        _onboardSuperstateUSTB();
        _onboardCentrifugeJTRSY();
        _onboardMapleSyrupUSDC();
    }

    function _onboardSuperstateUSTB() private {
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_SUPERSTATE_SUBSCRIBE(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 300_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "ustbMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_SUPERSTATE_REDEEM(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "ustbBurnLimit",
            6
        );
    }

    function _onboardCentrifugeJTRSY() private {
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
                JTRSY_VAULT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 200_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "jtrsyMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_7540_REDEEM(),
                JTRSY_VAULT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "jtrsyBurnLimit",
            6
        );
    }

    function _onboardMapleSyrupUSDC() private {
        _onboardERC4626Vault({
            vault:        SYRUP_USDC,
            depositMax:   25_000_000e6,
            depositSlope: 5_000_000e6 / uint256(1 days)
        });
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
                SYRUP_USDC
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "syrupUSDCRedeemLimit",
            6
        );
    }

}
