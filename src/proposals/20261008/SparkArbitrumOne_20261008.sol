// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

interface IAccessControlsLike {

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IAdministeredAgentLike {

    function addActor(address actor) external;

    function addAdmin(address admin) external;

    function removeAdmin(address admin) external;

}

interface IALMProxyLike {

    function grantRole(bytes32 role, address account) external;

    function CONTROLLER() external returns (bytes32);

}

interface IBeaconLike {

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

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

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function setUnlimitedRateLimitData(bytes32 key) external;

}

contract SparkArbitrumOne_20261008 is SparkPayloadArbitrumOne {

    address internal constant PAS_CONFIGURATOR       = 0x0000000000000000000000000000000000000000;  // TODO: Add actual address
    address internal constant SKY_L2_GOVERANCE_RELAY = 0x0000000000000000000000000000000000000000;  // TODO: Add actual address

    function execute() external {
        // Grant controller role to PAU Controller
        IALMProxyLike(Arbitrum.ALM_PROXY).grantRole(
            IALMProxyLike(Arbitrum.ALM_PROXY).CONTROLLER(),
            Arbitrum.PAU_CONTROLLER
        );

        // Add ALM_BACKSTOP_RELAYER_MULTISIG as an actor to administered agent
        IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT).addActor(
            Arbitrum.ALM_BACKSTOP_RELAYER_MULTISIG
        );

        // Set domain parameters
        IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_setDomainParameters(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(Ethereum.ALM_PROXY))),
            0,
            0 // no fee cap rate
        );

        // Set rate limits
        IRateLimitsLike(Arbitrum.PAU_RATELIMITS).setUnlimitedRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_toCCTPRateLimitKey()
        );

        IRateLimitsLike(Arbitrum.PAU_RATELIMITS).setRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            5_000_000e6,
            uint256(150_000_000e6) / 1 days
        );

        // TODO: placehodler
        IAccessControlsLike(Arbitrum.PAU_ACCESS_CONTROLS).grantRole(IAccessControlsLike(Arbitrum.PAU_ACCESS_CONTROLS).DEFAULT_ADMIN_ROLE(), PAS_CONFIGURATOR);

        // Transfer all DEFAULT_ADMIN_ROLEs related to PAU to Sky L2GovernanceRelay
        _transferAllDefaultAdminRolesToSkyL2GovernanceRelay();
    }

    function _transferAllDefaultAdminRolesToSkyL2GovernanceRelay() internal {
        IBeaconLike(Arbitrum.SPARK_BEACON).grantRole(IBeaconLike(Arbitrum.SPARK_BEACON).DEFAULT_ADMIN_ROLE(),  SKY_L2_GOVERANCE_RELAY);
        IBeaconLike(Arbitrum.SPARK_BEACON).revokeRole(IBeaconLike(Arbitrum.SPARK_BEACON).DEFAULT_ADMIN_ROLE(), Arbitrum.SPARK_EXECUTOR);
    }

}
