// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

interface IAccessControlsLike {

    function grantRole(bytes32 role, address account) external;

}

interface IAdministeredAgentLike {

    function addActor(address actor) external;

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function removeGrantor(address grantor) external;

}

interface IALMProxyLike {

    function CONTROLLER() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

interface IBeaconLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

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

    function grantRole(bytes32 role, address account) external;

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function setUnlimitedRateLimitData(bytes32 key) external;

}

/**
 * @title  November 5, 2026 Spark Base Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Onboard Parallel Diamond PAU with CCTP V2.
 *         - Grant the PAS Configurator admin over the Base Diamond PAU access controls and rate limits.
 *         - Transfer admin of the Base Diamond PAU Beacon from the Spark Executor to the Sky governance relay.
 * Forum:  https://forum.skyeco.com/t/november-5-2026-proposed-changes-to-spark-for-upcoming-spell/28351
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xa0cf2d0ad428858797853eb9b015bf921e2f53a07b96aaa4de4bf28e84653298
 */
contract SparkBase_20261105 is SparkPayloadBase {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant PAS_CONFIGURATOR       = 0x458Acd38fD749F6325039e63e8Bc496dBc286D11;
    address internal constant SOTER_FREEZER_MULTISIG = 0x747BF29B189e2a070a921Af7Cf65681E3d5F5967;
    address internal constant SOTER_GRANTOR_MULTISIG = 0x97EC6398e5dD047BA3223cFC017bFC6436Ac3Fe7;

    function execute() external {
        // 1. Onboard Parallel Diamond PAU with CCTP V2.

        // Grant controller role to PAU Controller
        IALMProxyLike(Base.ALM_PROXY).grantRole(
            IALMProxyLike(Base.ALM_PROXY).CONTROLLER(),
            Base.PAU_CONTROLLER
        );

        // Setup administered agent for PAU
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).addRevoker(
            SOTER_FREEZER_MULTISIG
        );
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).addGrantor(
            SOTER_GRANTOR_MULTISIG
        );
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).removeGrantor(
            Base.PAU_GRANTOR_MULTISIG
        );
        IAdministeredAgentLike(Base.PAU_ADMINISTERED_AGENT).addActor(
            Base.PLANNER_WALLET
        );

        // Set rate limits
        IRateLimitsLike(Base.PAU_RATELIMITS).setUnlimitedRateLimitData(
            IControllerLike(Base.PAU_CONTROLLER).cctp_toCCTPRateLimitKey()
        );

        IRateLimitsLike(Base.PAU_RATELIMITS).setRateLimitData(
            IControllerLike(Base.PAU_CONTROLLER).cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );

        // Set domain parameters
        IControllerLike(Base.PAU_CONTROLLER).cctp_setDomainParameters(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(Ethereum.ALM_PROXY))),
            0,
            0 // no fee cap rate
        );

        // 2. Grant the PAS Configurator admin over the Base Diamond PAU access controls and rate limits.
        IAccessControlsLike(Base.PAU_ACCESS_CONTROLS).grantRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        IRateLimitsLike(Base.PAU_RATELIMITS).grantRole(DEFAULT_ADMIN_ROLE,          PAS_CONFIGURATOR);

        // 3. Transfer admin of the Base Diamond PAU Beacon from the Spark Executor to the Sky governance relay.
        IBeaconLike(Base.SPARK_BEACON).grantRole(DEFAULT_ADMIN_ROLE,  Base.SKY_GOV_RELAY);
        IBeaconLike(Base.SPARK_BEACON).revokeRole(DEFAULT_ADMIN_ROLE, Base.SPARK_EXECUTOR);
    }

}
