// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SLLHelpers }                       from "src/libraries/SLLHelpers.sol";
import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

/**
 * @title  October 16, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *          - Disable Unused Products
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-16-2025-proposed-changes-to-spark-for-upcoming-spell/27215
 * Vote:   
 */
contract SparkEthereum_20251016 is SparkPayloadEthereum {

    function _postExecute() internal override {
        // Disable Unused Products
        IRateLimits(Ethereum.ALM_RATE_LIMITS).setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
                Ethereum.JTRSY_VAULT
            ),
            0,
            0
        );

        IRateLimits(Ethereum.ALM_RATE_LIMITS).setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                Ethereum.BUIDLI_DEPOSIT
            ),
            0,
            0
        );

        // Set CCTP for Avalanche
        MainnetController(Ethereum.ALM_CONTROLLER).setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE,
            SLLHelpers.addrToBytes32(Avalanche.ALM_PROXY)
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE
            ),
            Ethereum.ALM_RATE_LIMITS,
            100_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
    }

}
