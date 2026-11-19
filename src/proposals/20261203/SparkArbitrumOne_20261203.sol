// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

// Diamond PAU controller (diamond-pau v1.16.0): the admin function and the facet calls this payload makes.
interface IControllerLike {

    function layerZero_getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    ) external pure returns (bytes32 key);

    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function sparkVault_getTakeRateLimitKey(address sparkVault) external pure returns (bytes32 key);

    function transferAsset_getTransferRateLimitKey(address asset, address destination) external pure returns (bytes32 key);

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IOFTLike {

    function peers(uint32 eid) external view returns (bytes32 peer);

}

interface IRateLimitsLike {

    function setUnlimitedRateLimitData(bytes32 key) external;

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
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkArbitrumOne_20261203 is SparkPayloadArbitrumOne {

    bytes32 internal constant LAYER_ZERO_FACET_ID     = "LAYER_ZERO_FACET";
    bytes32 internal constant SPARK_VAULT_FACET_ID    = "SPARK_VAULT_FACET";
    bytes32 internal constant TRANSFER_ASSET_FACET_ID = "TRANSFER_ASSET_FACET";

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    // PLACEHOLDER: Arbitrum spUSDT PAU (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2026120300000000000000000000000000000012;
    address internal constant SPUSDT_PAU_CONTROLLER = 0x2026120300000000000000000000000000000011;
    address internal constant SPUSDT_PAU_RATELIMITS = 0x2026120300000000000000000000000000000013;

    // PLACEHOLDER: Spark Vaults Administered Agent on Arbitrum (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant SPARK_VAULTS_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000014;

    // PLACEHOLDER: Ethereum spUSDT PAU ALMProxy (Pre-deployed contracts 1), from spark-address-registry at handover.
    address internal constant ETHEREUM_SPUSDT_PAU_ALM_PROXY = 0x2026120300000000000000000000000000000002;

    function execute() external {
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits       rateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);

        IControllerLike spUsdtPauController = IControllerLike(SPUSDT_PAU_CONTROLLER);
        IRateLimitsLike spUsdtPauRateLimits = IRateLimitsLike(SPUSDT_PAU_RATELIMITS);
        ISparkVaultLike spUsdt              = ISparkVaultLike(Arbitrum.SPARK_VAULT_V2_SPUSDT);

        // 2. Move spUSDT onto its own Diamond PAU.

        // 2.1 Enable the SparkVault, TransferAsset and LayerZero integrations from the Spark Beacon.
        bytes32[] memory integrationIds = new bytes32[](3);
        integrationIds[0] = SPARK_VAULT_FACET_ID;
        integrationIds[1] = TRANSFER_ASSET_FACET_ID;
        integrationIds[2] = LAYER_ZERO_FACET_ID;

        spUsdtPauController.updateIntegrations(integrationIds);

        // 2.2 Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),   SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(),  Arbitrum.ALM_PROXY);
        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_VAULTS_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Arbitrum.ALM_PROXY_FREEZABLE);

        // 2.3 spUSDT PAU rate limits (unlimited, as on the Spark Liquidity Layer today) and LayerZero recipient.
        spUsdtPauRateLimits.setUnlimitedRateLimitData(
            spUsdtPauController.sparkVault_getTakeRateLimitKey(Arbitrum.SPARK_VAULT_V2_SPUSDT)
        );
        spUsdtPauRateLimits.setUnlimitedRateLimitData(
            spUsdtPauController.transferAsset_getTransferRateLimitKey(Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT)
        );
        spUsdtPauRateLimits.setUnlimitedRateLimitData(
            spUsdtPauController.layerZero_getTransferRateLimitKey(
                Arbitrum.USDT_OFT,
                IOFTLike(Arbitrum.USDT_OFT).peers(LZ_EID_ETHEREUM),
                LZ_EID_ETHEREUM,
                Arbitrum.USDT0
            )
        );

        spUsdtPauController.layerZero_setRecipient(LZ_EID_ETHEREUM, bytes32(uint256(uint160(ETHEREUM_SPUSDT_PAU_ALM_PROXY))));

        // 2.4 Zero the moved legacy keys.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Arbitrum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), Arbitrum.USDT0, Arbitrum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        rateLimits.setRateLimitData(
            keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Arbitrum.USDT_OFT, LZ_EID_ETHEREUM)),
            0,
            0
        );
    }

}
