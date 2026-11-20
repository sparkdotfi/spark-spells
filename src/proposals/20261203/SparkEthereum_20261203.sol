// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { BeaconConfig } from "diamond-pau/src/libraries/BeaconConfig.sol";

import { IRateLimits as IPAURateLimits } from "diamond-pau/src/interfaces/IRateLimits.sol";
import { IController }                   from "diamond-pau/src/interfaces/IController.sol";

import { ILayerZeroController } from "diamond-pau/src/facets/layer-zero/ILayerZeroController.sol";

import { IERC20 }   from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { IALMProxy as ILegacyALMProxy }     from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits as ILegacyRateLimits } from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController }                from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }                 from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

interface IPAUControllerLike is IController, ILayerZeroController {}

interface ISparkVaultLike {

    function assetsOutstanding() external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function SETTER_ROLE() external view returns (bytes32);

    function TAKER_ROLE() external view returns (bytes32);

}

/**
 * @title  December 3, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Savings:
 *         - Move spUSDT onto its own Diamond PAU and back it with sUSDS from the Spark Liquidity Layer.
 *         Spark Treasury:
 *         - Transfer USDS to the buyback executor to fund SPK buybacks.
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkEthereum_20261203 is SparkPayloadEthereum {

    uint32 internal constant LZ_EID_ARBITRUM = 30110;
    uint32 internal constant LZ_EID_XLAYER   = 30274;

    bytes32 internal constant PEER_ARBITRUM = bytes32(uint256(uint160(0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92)));
    bytes32 internal constant PEER_XLAYER   = bytes32(uint256(uint160(0x94BCCa6bdfd6A61817Ab0E960bFedE4984505554)));

    // PLACEHOLDER: Ethereum spUSDT PAU (Pre-deployed contracts 1), from spark-address-registry at handover.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2026120300000000000000000000000000000002;
    address internal constant SPUSDT_PAU_CONTROLLER = 0x2026120300000000000000000000000000000001;

    // PLACEHOLDER: Spark Liquidity Layer PAU controller (Pre-deployed contracts 2), from spark-address-registry at handover.
    address internal constant SLL_PAU_CONTROLLER = 0x2026120300000000000000000000000000000004;

    // PLACEHOLDER: Spark Vaults Administered Agent on Ethereum (Pre-deployed contracts 4), from spark-address-registry at handover.
    address internal constant SPARK_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000006;

    // PLACEHOLDER: Arbitrum spUSDT PAU ALMProxy (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant ARBITRUM_SPUSDT_PAU_ALM_PROXY = 0x2026120300000000000000000000000000000012;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    function _postExecute() internal override {
        MainnetController legacyController = MainnetController(Ethereum.ALM_CONTROLLER);
        ILegacyRateLimits legacyRateLimits = ILegacyRateLimits(Ethereum.ALM_RATE_LIMITS);

        IPAUControllerLike spUsdtPauController = IPAUControllerLike(SPUSDT_PAU_CONTROLLER);

        IPAUControllerLike sllPAUController = IPAUControllerLike(SLL_PAU_CONTROLLER);

        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        // 1. Move spUSDT onto its own Diamond PAU and back it with sUSDS.

        // Grant the SLL PAU controller CONTROLLER role on Legacy ALMProxy.
        ILegacyALMProxy(Ethereum.ALM_PROXY).grantRole(ILegacyALMProxy(Ethereum.ALM_PROXY).CONTROLLER(), SLL_PAU_CONTROLLER);

        // Register the SwapAsset and LayerZero facets on the Spark Beacon.
        BeaconConfig.setSwapAssetIntegration(Ethereum.SPARK_BEACON, Ethereum.SWAP_ASSET_FACET);
        BeaconConfig.setLayerZeroIntegration(Ethereum.SPARK_BEACON, Ethereum.LAYERZERO_FACET);

        // Enable the integrations: LayerZero and SwapAsset on the spUSDT PAU amd SwapAsset on the SLL PAU.
        bytes32[] memory spUsdtPauIntegrationIds = new bytes32[](2);
        spUsdtPauIntegrationIds[0] = BeaconConfig.LAYER_ZERO_INTEGRATION;
        spUsdtPauIntegrationIds[1] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        spUsdtPauController.updateIntegrations(spUsdtPauIntegrationIds);

        bytes32[] memory sllPauIntegrationIds = new bytes32[](1);
        sllPauIntegrationIds[0] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        sllPAUController.updateIntegrations(sllPauIntegrationIds);

        // Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),  SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(), Ethereum.ALM_PROXY);

        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);

        // spUSDT PAU LayerZero recipients.
        spUsdtPauController.layerZero_setRecipient(LZ_EID_ARBITRUM, bytes32(uint256(uint160(ARBITRUM_SPUSDT_PAU_ALM_PROXY))));
        spUsdtPauController.layerZero_setRecipient(LZ_EID_XLAYER,   bytes32(uint256(uint160(XLayer.ALM_PROXY))));

        // Zero the moved Spark Liquidity Layer keys.
        legacyRateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(legacyController.LIMIT_SPARK_VAULT_TAKE(), Ethereum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        legacyRateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(legacyController.LIMIT_ASSET_TRANSFER(), Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        legacyRateLimits.setRateLimitData(
            keccak256(abi.encode(legacyController.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_ARBITRUM)),
            0,
            0
        );
        legacyRateLimits.setRateLimitData(
            keccak256(abi.encode(legacyController.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_XLAYER)),
            0,
            0
        );

        // Transfer sUSDS backing to the spUSDT PAU.
        _transferAssetFromAlmProxy(
            Ethereum.SUSDS,
            SPUSDT_PAU_ALM_PROXY,
            IERC4626(Ethereum.SUSDS).convertToShares(spUsdt.assetsOutstanding() * 1e12)
        );

        // 5. Transfer USDS to the buyback executor to fund SPK buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
