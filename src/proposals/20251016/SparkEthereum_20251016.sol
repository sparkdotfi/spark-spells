// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

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
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
                Ethereum.JTRSY
            ),
            Ethereum.ALM_RATE_LIMITS,
            0,
            0,
            18
        );
    }

}
