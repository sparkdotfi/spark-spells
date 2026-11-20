// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

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
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkArbitrumOne_20261203 is SparkPayloadArbitrumOne {

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    // PLACEHOLDER: Arbitrum spUSDT PAU (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2026120300000000000000000000000000000012;

    // PLACEHOLDER: Spark Vaults Administered Agent on Arbitrum (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant SPARK_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000014;

    function execute() external {
        ForeignController legacyController = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits       legacyRateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);

        ISparkVaultLike spUsdt = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        // 2. Move spUSDT onto its own Diamond PAU.

        // Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),  SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(), Arbitrum.ALM_PROXY);

        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Arbitrum.ALM_PROXY_FREEZABLE);

        // Zero the moved legacy keys.
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
    }

}
