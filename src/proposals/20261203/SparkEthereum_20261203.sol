// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { BeaconConfig } from "diamond-pau/src/libraries/BeaconConfig.sol";

import { IController } from "diamond-pau/src/interfaces/IController.sol";

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
 *         SparkLend:
 *         - Claim accrued SparkLend reserves and route them to the Spark Liquidity Layer and the Spark Operations Multisig.
 *         Spark Treasury:
 *         - Transfer USDS to the buyback executor to fund SPK buybacks.
 *         Spark Liquidity Layer:
 *         - Add a Diamond PAU controller to the Spark Liquidity Layer ALM Proxy, carrying SwapAssetFacet.
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkEthereum_20261203 is SparkPayloadEthereum {

    uint32 internal constant LZ_EID_ARBITRUM = 30110;
    uint32 internal constant LZ_EID_XLAYER   = 30274;

    // Ethereum spUSDT PAU (Pre-deployed contracts 1), created by EthereumSparkSpUSDTPayload.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2ceF3e65858EE6706FAd66550876412d08342BC8;
    address internal constant SPUSDT_PAU_CONTROLLER = 0xBaA8B6E49a8d0B6D2E8D0F57c0CA9647ce28C236;

    // Spark Liquidity Layer PAU controller (Pre-deployed contracts 2), created by EthereumSparkSpUSDTPayload.
    address internal constant SLL_PAU_CONTROLLER = 0x650044537F5d4aab322796426939214096c9445f;

    // Spark Vaults Administered Agent on Ethereum (Pre-deployed contracts 4), created by EthereumSparkSpUSDTPayload.
    address internal constant SPARK_ADMINISTERED_AGENT = 0xfE4b2fD27e8232a79485ba8bA8DBFcD9A88f0738;

    // Arbitrum spUSDT PAU ALMProxy (Pre-deployed contracts 5), created by ArbitrumSparkSpUSDTPayload.
    address internal constant ARBITRUM_SPUSDT_PAU_ALM_PROXY = 0xf30dAD25A887a99D01606F117610072F2050ccAD;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    constructor() {
        // PAYLOAD_ARBITRUM = ;
        // PAYLOAD_BASE     = ;
        // PAYLOAD_XLAYER   = ;
    }

    function _postExecute() internal override {
        MainnetController legacyController = MainnetController(Ethereum.ALM_CONTROLLER);
        ILegacyRateLimits legacyRateLimits = ILegacyRateLimits(Ethereum.ALM_RATE_LIMITS);

        IPAUControllerLike spUsdtPauController = IPAUControllerLike(SPUSDT_PAU_CONTROLLER);

        IPAUControllerLike sllPAUController = IPAUControllerLike(SLL_PAU_CONTROLLER);

        ISparkVaultLike spUsdt = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        // 1. Move spUSDT onto its own Diamond PAU and back it with sUSDS.

        // 1.1 Register the SwapAsset and LayerZero facets on the Spark Beacon.
        BeaconConfig.setSwapAssetIntegration(Ethereum.SPARK_BEACON, Ethereum.SWAP_ASSET_FACET);
        BeaconConfig.setLayerZeroIntegration(Ethereum.SPARK_BEACON, Ethereum.LAYERZERO_FACET);

        // 1.2 Enable the LayerZero and SwapAsset integrations on the spUSDT PAU.
        bytes32[] memory spUsdtPauIntegrationIds = new bytes32[](2);
        spUsdtPauIntegrationIds[0] = BeaconConfig.LAYER_ZERO_INTEGRATION;
        spUsdtPauIntegrationIds[1] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        spUsdtPauController.updateIntegrations(spUsdtPauIntegrationIds);

        // 1.3 Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),  SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(), Ethereum.ALM_PROXY);

        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);

        // 1.4 spUSDT PAU LayerZero recipients.
        spUsdtPauController.layerZero_setRecipient(LZ_EID_ARBITRUM, bytes32(uint256(uint160(ARBITRUM_SPUSDT_PAU_ALM_PROXY))));
        spUsdtPauController.layerZero_setRecipient(LZ_EID_XLAYER,   bytes32(uint256(uint160(XLayer.ALM_PROXY))));

        // 1.5 Zero the moved Spark Liquidity Layer keys.
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

        // 1.6 Transfer sUSDS backing to the spUSDT PAU.
        _transferAssetFromAlmProxy(
            Ethereum.SUSDS,
            SPUSDT_PAU_ALM_PROXY,
            IERC4626(Ethereum.SUSDS).convertToShares(spUsdt.assetsOutstanding() * 1e12)
        );

        // 4. Claim SparkLend reserves: executed by `SparkPayloadEthereum.execute()` after `_postExecute`.

        // 5. Transfer USDS to the buyback executor to fund SPK buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);

        // 7. Add a Diamond PAU controller to the Spark Liquidity Layer ALM Proxy.

        // 7.1 Enable the SwapAsset integration on the SLL PAU controller, from the Sky Beacon.
        bytes32[] memory sllPauIntegrationIds = new bytes32[](1);
        sllPauIntegrationIds[0] = BeaconConfig.SWAP_ASSET_INTEGRATION;

        sllPAUController.updateIntegrations(sllPauIntegrationIds);

        // 7.2 Grant the SLL PAU controller CONTROLLER on the Spark Liquidity Layer ALM Proxy.
        ILegacyALMProxy(Ethereum.ALM_PROXY).grantRole(ILegacyALMProxy(Ethereum.ALM_PROXY).CONTROLLER(), SLL_PAU_CONTROLLER);
    }

}
