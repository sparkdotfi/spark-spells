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

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function removeAdmin(address admin) external;

    function removeGrantor(address grantor) external;

    function removeRevoker(address revoker) external;

}

interface IALMProxyLike {

    function CONTROLLER() external returns (bytes32);

    function doCall(
        address        target,
        bytes   memory data
    ) external returns (bytes memory);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

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

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

}

interface IRateLimitsLike {

    function DEFAULT_ADMIN_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function setUnlimitedRateLimitData(bytes32 key) external;

}

interface IArbitrumTokenBridge {

    function outboundTransfer(
        address        l1Token,
        address        to,
        uint256        amount,
        bytes calldata data
    ) external payable returns (bytes memory res);

}

/**
 * @title  October 8, 2026 Spark Arbitrum One Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Onboard Parallel Diamond PAU with CCTP V2.
 *         - Return idle USDS from Arbitrum to the Ethereum ALM Proxy.
 *         - Grant the PAS Configurator admin over the Arbitrum Diamond PAU access controls and rate limits.
 *         - Transfer admin of the Arbitrum Diamond PAU Beacon from the Spark Executor to the Sky governance relay.
 * Forum:  https://forum.skyeco.com/t/october-8-2026-proposed-changes-to-spark-for-upcoming-spell/28265
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xff837d7434b33bc2d74a133e5c2acbcdf2ff17e6b76005621cfd43794f0d85cb
 *         https://snapshot.box/#/s:sparkfi.eth/proposal/0x93fd7352008805e27da235e51c02e7c987ff5d0ee3feccd3cd157e09a2e9adfe
 *         https://snapshot.box/#/s:sparkfi.eth/proposal/0x4680fb4b5717156b6e53f858ab6a267190deab0d51380b5fb9d27910e09d4e74
 *         https://snapshot.box/#/s:sparkfi.eth/proposal/0x84f74256a6f0e41078483b5c7ce8dad4b885f5bc656a5bcaccb84f36d74e536c
 */
contract SparkArbitrumOne_20261008 is SparkPayloadArbitrumOne {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant PAS_CONFIGURATOR       = 0x0000000000000000000000000000000000000000;  // TODO: Add actual address
    address internal constant SOTER_FREEZER_MULTISIG = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address
    address internal constant SOTER_GRANTOR_MULTISIG = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address
    address internal constant SPARK_HOT_WALLET       = 0xC758519Ace14E884fdbA9ccE25F2DbE81b7e136f;  // TODO: Add actual address

    function execute() external {
        // 1. Onboard Parallel Diamond PAU with CCTP V2.

        // Grant controller role to PAU Controller
        IALMProxyLike(Arbitrum.ALM_PROXY).grantRole(
            IALMProxyLike(Arbitrum.ALM_PROXY).CONTROLLER(),
            Arbitrum.PAU_CONTROLLER
        );

        // Setup administered agent for PAU
        IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT).addRevoker(
            SOTER_FREEZER_MULTISIG
        );
        IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT).addGrantor(
            SOTER_GRANTOR_MULTISIG
        );
        IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT).removeGrantor(
            Arbitrum.PAU_GRANTOR_MULTISIG
        );
        IAdministeredAgentLike(Arbitrum.PAU_ADMINISTERED_AGENT).addActor(
            SPARK_HOT_WALLET
        );

        // Set rate limits
        IRateLimitsLike(Arbitrum.PAU_RATELIMITS).setUnlimitedRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_toCCTPRateLimitKey()
        );

        IRateLimitsLike(Arbitrum.PAU_RATELIMITS).setRateLimitData(
            IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_getToDomainRateLimitKey(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );

        // Set domain parameters
        IControllerLike(Arbitrum.PAU_CONTROLLER).cctp_setDomainParameters(
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            bytes32(uint256(uint160(Ethereum.ALM_PROXY))),
            0,
            0 // no fee cap rate
        );

        // 3. Return idle USDS from Arbitrum to the Ethereum ALM Proxy.
        _sendUSDSBackFromArbitrum(IERC20Like(Arbitrum.USDS).balanceOf(Arbitrum.ALM_PROXY));

        // 5. Grant the PAS Configurator admin over the Arbitrum Diamond PAU access controls and rate limits.
        IAccessControlsLike(Arbitrum.PAU_ACCESS_CONTROLS).grantRole(DEFAULT_ADMIN_ROLE, PAS_CONFIGURATOR);
        IRateLimitsLike(Arbitrum.PAU_RATELIMITS).grantRole(DEFAULT_ADMIN_ROLE,          PAS_CONFIGURATOR);

        // 6. Transfer admin of the Arbitrum Diamond PAU Beacon from the Spark Executor to the Sky governance relay.
        IBeaconLike(Arbitrum.SPARK_BEACON).grantRole(DEFAULT_ADMIN_ROLE,  Arbitrum.SKY_GOV_RELAY);
        IBeaconLike(Arbitrum.SPARK_BEACON).revokeRole(DEFAULT_ADMIN_ROLE, Arbitrum.SPARK_EXECUTOR);
    }

    function _sendUSDSBackFromArbitrum(uint256 amount) internal {
        IALMProxyLike almProxy = IALMProxyLike(Arbitrum.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        almProxy.doCall(
            Arbitrum.USDS,
            abi.encodeCall(IERC20Like(Arbitrum.USDS).approve, (Arbitrum.TOKEN_BRIDGE, amount))
        );

        almProxy.doCall(
            Arbitrum.TOKEN_BRIDGE,
            abi.encodeCall(
                IArbitrumTokenBridge(Arbitrum.TOKEN_BRIDGE).outboundTransfer,
                (Ethereum.USDS, Ethereum.ALM_PROXY, amount, "")
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
