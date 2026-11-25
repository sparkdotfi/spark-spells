// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Base } from "../../../lib/spark-address-registry/src/Base.sol";

import { CCTPForwarder } from "../../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

interface IControllerLike {

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

}

/**
 * @title  December 3, 2026 Spark Base Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Raise the CCTP V2 rate limit for USDC sent from Base to Ethereum.
 * Forum:  https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-spark-for-upcoming-spell/28472
 * Vote:   TBD
 */
contract SparkBase_20261203 is SparkPayloadBase {

    function execute() external {
        // 6. Raise the CCTP V2 rate limit for USDC sent from Base to Ethereum.
        IRateLimitsLike(Base.PAU_RATELIMITS).setRateLimitData(
            IControllerLike(Base.PAU_CONTROLLER).cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            25_000_000e6,
            uint256(100_000_000e6) / 1 days
        );
    }

}
