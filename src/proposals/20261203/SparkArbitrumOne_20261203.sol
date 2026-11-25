// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Arbitrum } from "../../../lib/spark-address-registry/src/Arbitrum.sol";

import { IRateLimits }       from "../../../lib/spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "../../../lib/spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "../../../lib/spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

interface IAdministeredAgent {

    function addActor(address account) external;

    function removeActor(address account) external;

}

interface ISparkVaultLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function SETTER_ROLE() external view returns (bytes32);

    function TAKER_ROLE() external view returns (bytes32);

}

/**
 * @title  December 3, 2026 Spark Arbitrum One Proposal
 * @author Phoenix Labs
 * @notice Spark Savings - Move spUSDT onto its own Diamond PAU and send its USDT0 back to the Ethereum spUSDT PAU.
 * Forum:  https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-spark-for-upcoming-spell/28472
 * Vote:   TBD
 */
contract SparkArbitrumOne_20261203 is SparkPayloadArbitrumOne {

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    // TODO: Move to spark-address-registry once deployed.
    // Arbitrum spUSDT PAU ALMProxy (Pre-deployed contracts 5), created by ArbitrumSparkSpUSDTPayload.
    address internal constant SPUSDT_PAU_ALM_PROXY = 0x6172A812bd36a7C21733bFc99991250E81768aaf;

    // Planner and Spark Administered Agent on Arbitrum (Pre-deployed contracts 5), created by ArbitrumSparkSpUSDTPayload.
    address internal constant SPARK_ADMINISTERED_AGENT   = 0x01F45C14E8A56560b84a8CcB422ca75379224951;
    address internal constant PLANNER_ADMINISTERED_AGENT = 0xB56d9D463661DF1325A16a56cF273881eCD6AA22;

    function execute() external {
        ForeignController legacyController = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits       legacyRateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);

        ISparkVaultLike spUsdt = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        // 2. Move spUSDT onto its own Diamond PAU.

        // 2.1 Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),  SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(), Arbitrum.ALM_PROXY);

        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Arbitrum.ALM_PROXY_FREEZABLE);

        // 2.2 Zero the moved legacy keys.
        legacyRateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(legacyController.LIMIT_SPARK_VAULT_TAKE(), Arbitrum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        legacyRateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(legacyController.LIMIT_ASSET_TRANSFER(), Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        legacyRateLimits.setRateLimitData(
            keccak256(abi.encode(legacyController.LIMIT_LAYERZERO_TRANSFER(), Arbitrum.USDT_OFT, LZ_EID_ETHEREUM)),
            0,
            0
        );

        // 2.3 Make the Arbitrum Spark Planner Administered Agent the only actor on the existing Arbitrum PAU Administered Agent.

        IAdministeredAgent pauAdministeredAgent = IAdministeredAgent(Arbitrum.PAU_ADMINISTERED_AGENT);

        pauAdministeredAgent.addActor(PLANNER_ADMINISTERED_AGENT);

        pauAdministeredAgent.removeActor(Arbitrum.ALM_RELAYER_MULTISIG);
        pauAdministeredAgent.removeActor(Arbitrum.PLANNER_WALLET);
    }

}
