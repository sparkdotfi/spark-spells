// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ChainIdUtils }  from "../../libraries/ChainIdUtils.sol";

import { SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

interface IALMProxyLike {

    function grantRole(bytes32 role, address account) external;

    function CONTROLLER() external returns (bytes32);

}

interface IControllerLike {

    function cctp_setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    function cctp_toCCTPRateLimitKey() external pure returns (bytes32 key);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

}

contract SparkArbitrumOne_1111 is SparkPayloadArbitrumOne {

    function execute() external {
        // Grant controller role to PAU Controller
        IALMProxyLike(Arbitrum.ALM_PROXY).grantRole(
            IALMProxyLike(Arbitrum.ALM_PROXY).CONTROLLER(),
            Arbitrum.PAU_CONTROLLER
        );

        // Set domain parameters
        IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_setDomainParameters(
            uint32(ChainIdUtils.Ethereum()),
            bytes32(uint256(uint160(Ethereum.ALM_PROXY))),
            0,
            0 // no fee cap rate
        );

        // Set rate limits
        IRateLimitsLike(Ethereum.ALM_RATE_LIMITS).setRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_toCCTPRateLimitKey(),
            100_000_000e6,
            uint256(500_000_000e6) / 1 days
        );

        IRateLimitsLike(Ethereum.ALM_RATE_LIMITS).setRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_getToDomainRateLimitKey(uint32(ChainIdUtils.Ethereum())),
            10_000_000e6,
            uint256(250_000_000e6) / 1 days
        );
    }

}
