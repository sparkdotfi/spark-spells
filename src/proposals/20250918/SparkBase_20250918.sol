// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { ForeignController }     from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }      from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }           from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadBase } from "src/SparkPayloadBase.sol";

/**
 * @title  Sep 18, 2025 Spark Base Proposal
 * @notice Spark Liquidity Layer:
 *         - Upgrade ALM Controller to v1.7
 *         - Increase USDC CCTP Rate Limits
 *         - Activate MORPHO Transfer Rate Limit
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/september-18-2025-proposed-changes-to-spark-for-upcoming-spell/27153
 * Vote:   
 */
contract SparkBase_20250918 is SparkPayloadBase {

    address internal constant NEW_ALM_CONTROLLER = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
    address internal constant MORPHO_TOKEN       = 0xBAa5CC21fd487B8Fcc2F632f3F4E8D37262a0842;
    address internal constant SPARK_MULTISIG     = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;

    function execute() external {
        // --- Upgrade ALM Controller to v1.7 ---

        _upgradeController(Base.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        // --- Increase USDC CCTP Rate Limits ---

        IRateLimits(Base.ALM_RATE_LIMITS).setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                ForeignController(NEW_ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
            ),
            200_000_000e6,
            500_000_000e6 / uint256(1 days)
        );

        // --- Activate MORPHO Transfer Rate Limit ---

        IRateLimits(Base.ALM_RATE_LIMITS).setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                ForeignController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                MORPHO_TOKEN,
                SPARK_MULTISIG
            ),
            100_000e18,
            100_000e18 / uint256(1 days)
        );
    }

}
