// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 }   from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { XLayer }   from "spark-address-registry/XLayer.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

// Diamond PAU Beacon (diamond-pau v1.16.0).
interface IBeaconLike {

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    struct Config {
        address facet;
        Wire[]  wires;
    }

    function setIntegration(bytes32 id, Config calldata config) external;

}

// Diamond PAU controller (diamond-pau v1.16.0): the admin function and the facet calls this payload makes.
interface IControllerLike {

    function layerZero_getTransferRateLimitKey(
        address oft,
        bytes32 peer,
        uint32  destinationEndpointId,
        address token
    ) external pure returns (bytes32 key);

    function layerZero_setRecipient(uint32 destinationEndpointId, bytes32 recipient) external;

    function swapAsset_getCompleteSwapRateLimitKey(
        address assetOut,
        address counterpartyProxy,
        address assetIn
    ) external pure returns (bytes32 key);

    function swapAsset_getInitiateSwapRateLimitKey(
        address assetOut,
        address counterpartyProxy,
        address counterpartyController,
        address assetIn
    ) external pure returns (bytes32 key);

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IOFTLike {

    function peers(uint32 eid) external view returns (bytes32 peer);

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

}

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

    bytes32 internal constant LAYER_ZERO_FACET_ID = "LAYER_ZERO_FACET";
    bytes32 internal constant SWAP_ASSET_FACET_ID = "SWAP_ASSET_FACET";

    uint32 internal constant LZ_EID_ARBITRUM = 30110;
    uint32 internal constant LZ_EID_XLAYER   = 30274;

    // PLACEHOLDER: Ethereum spUSDT PAU (Pre-deployed contracts 1), from spark-address-registry at handover.
    address internal constant SPUSDT_PAU_ALM_PROXY  = 0x2026120300000000000000000000000000000002;
    address internal constant SPUSDT_PAU_CONTROLLER = 0x2026120300000000000000000000000000000001;
    address internal constant SPUSDT_PAU_RATELIMITS = 0x2026120300000000000000000000000000000003;

    // PLACEHOLDER: Spark Liquidity Layer swap controller (Pre-deployed contracts 2), from spark-address-registry at handover.
    address internal constant SLL_SWAP_CONTROLLER = 0x2026120300000000000000000000000000000004;
    address internal constant SLL_SWAP_RATELIMITS = 0x2026120300000000000000000000000000000005;

    // PLACEHOLDER: Spark Vaults Administered Agent on Ethereum (Pre-deployed contracts 4), from spark-address-registry at handover.
    address internal constant SPARK_VAULTS_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000006;

    // PLACEHOLDER: Arbitrum spUSDT PAU ALMProxy (Pre-deployed contracts 5), from spark-address-registry at handover.
    address internal constant ARBITRUM_SPUSDT_PAU_ALM_PROXY = 0x2026120300000000000000000000000000000012;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 2_681_519e18;

    function _postExecute() internal override {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        IControllerLike spUsdtPauController = IControllerLike(SPUSDT_PAU_CONTROLLER);
        IRateLimitsLike spUsdtPauRateLimits = IRateLimitsLike(SPUSDT_PAU_RATELIMITS);
        IControllerLike sllSwapController   = IControllerLike(SLL_SWAP_CONTROLLER);
        IRateLimitsLike sllSwapRateLimits   = IRateLimitsLike(SLL_SWAP_RATELIMITS);
        ISparkVaultLike spUsdt              = ISparkVaultLike(Ethereum.SPARK_VAULT_V2_SPUSDT);

        // 1. Move spUSDT onto its own Diamond PAU and back it with sUSDS.

        // 1.1 Register the SwapAsset and LayerZero facets on the Spark Beacon.
        IBeaconLike(Ethereum.SPARK_BEACON).setIntegration(SWAP_ASSET_FACET_ID, _buildSwapAssetIntegration(Ethereum.SWAP_ASSET_FACET));
        IBeaconLike(Ethereum.SPARK_BEACON).setIntegration(LAYER_ZERO_FACET_ID, _buildLayerZeroIntegration(Ethereum.LAYERZERO_FACET));

        // 1.2 Enable the integrations: LayerZero and SwapAsset on the spUSDT PAU (from the Spark Beacon),
        //     SwapAsset on the swap controller (from the Sky Beacon).
        bytes32[] memory spUsdtPauIntegrationIds = new bytes32[](2);
        spUsdtPauIntegrationIds[0] = LAYER_ZERO_FACET_ID;
        spUsdtPauIntegrationIds[1] = SWAP_ASSET_FACET_ID;

        spUsdtPauController.updateIntegrations(spUsdtPauIntegrationIds);

        bytes32[] memory sllSwapIntegrationIds = new bytes32[](1);
        sllSwapIntegrationIds[0] = SWAP_ASSET_FACET_ID;

        sllSwapController.updateIntegrations(sllSwapIntegrationIds);

        // 1.3 Move TAKER and SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.TAKER_ROLE(),   SPUSDT_PAU_ALM_PROXY);
        spUsdt.revokeRole(spUsdt.TAKER_ROLE(),  Ethereum.ALM_PROXY);
        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_VAULTS_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);

        // 1.4 spUSDT PAU LayerZero limits and recipients.
        spUsdtPauRateLimits.setRateLimitData(
            spUsdtPauController.layerZero_getTransferRateLimitKey(
                Ethereum.USDT_OFT,
                IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_ARBITRUM),
                LZ_EID_ARBITRUM,
                Ethereum.USDT
            ),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );
        spUsdtPauRateLimits.setRateLimitData(
            spUsdtPauController.layerZero_getTransferRateLimitKey(
                Ethereum.USDT_OFT,
                IOFTLike(Ethereum.USDT_OFT).peers(LZ_EID_XLAYER),
                LZ_EID_XLAYER,
                Ethereum.USDT
            ),
            5_000_000e6,
            uint256(100_000_000e6) / 1 days
        );

        spUsdtPauController.layerZero_setRecipient(LZ_EID_ARBITRUM, bytes32(uint256(uint160(ARBITRUM_SPUSDT_PAU_ALM_PROXY))));
        spUsdtPauController.layerZero_setRecipient(LZ_EID_XLAYER,   bytes32(uint256(uint160(XLayer.ALM_PROXY))));

        // 1.5 Zero the moved Spark Liquidity Layer keys.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Ethereum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(controller.LIMIT_ASSET_TRANSFER(), Ethereum.USDT, Ethereum.SPARK_VAULT_V2_SPUSDT),
            0,
            0
        );
        rateLimits.setRateLimitData(
            keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_ARBITRUM)),
            0,
            0
        );
        rateLimits.setRateLimitData(
            keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), Ethereum.USDT_OFT, LZ_EID_XLAYER)),
            0,
            0
        );

        // 1.6 Swap controller on the Spark Liquidity Layer.
        IALMProxy(Ethereum.ALM_PROXY).grantRole(IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(), SLL_SWAP_CONTROLLER);

        sllSwapRateLimits.setRateLimitData(
            sllSwapController.swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDS, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDT),
            100_000_000e18,
            uint256(500_000_000e18) / 1 days
        );
        sllSwapRateLimits.setRateLimitData(
            sllSwapController.swapAsset_getInitiateSwapRateLimitKey(Ethereum.USDT, SPUSDT_PAU_ALM_PROXY, SPUSDT_PAU_CONTROLLER, Ethereum.USDS),
            100_000_000e6,
            uint256(500_000_000e6) / 1 days
        );

        // 1.7 Swap limits on the spUSDT PAU.
        spUsdtPauRateLimits.setRateLimitData(
            spUsdtPauController.swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDT, Ethereum.ALM_PROXY, Ethereum.USDS),
            100_000_000e6,
            uint256(1_000_000_000e6) / 1 days
        );
        spUsdtPauRateLimits.setRateLimitData(
            spUsdtPauController.swapAsset_getCompleteSwapRateLimitKey(Ethereum.USDS, Ethereum.ALM_PROXY, Ethereum.USDT),
            100_000_000e18,
            uint256(1_000_000_000e18) / 1 days
        );

        // 1.8 Transfer sUSDS backing to the spUSDT PAU: the sUSDS worth the USDT taken from spUSDT and not returned,
        //     read at execution. USDT has 6 decimals and USDS 18.
        _transferAssetFromAlmProxy(
            Ethereum.SUSDS,
            SPUSDT_PAU_ALM_PROXY,
            IERC4626(Ethereum.SUSDS).convertToShares(spUsdt.assetsOutstanding() * 1e12)
        );

        // 5. Transfer USDS to the buyback executor to fund SPK buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

    // Mirrors BeaconConfig.buildSwapAssetIntegration in diamond-pau v1.16.0 (b0b7efd0).
    function _buildSwapAssetIntegration(address facet) internal pure returns (IBeaconLike.Config memory) {
        IBeaconLike.Wire[] memory wires = new IBeaconLike.Wire[](5);

        wires[0] = _wire("swapAsset_", "initiateSwap(address,address,address,uint256)");
        wires[1] = _wire("swapAsset_", "completeSwap(address,address,uint256)");
        wires[2] = _wire("swapAsset_", "getInitiateSwapRateLimitKey(address,address,address,address)");
        wires[3] = _wire("swapAsset_", "getCompleteSwapRateLimitKey(address,address,address)");
        wires[4] = _wire("swapAsset_", "VERSION()");

        return IBeaconLike.Config({ facet: facet, wires: wires });
    }

    // Mirrors BeaconConfig.buildLayerZeroIntegration in diamond-pau v1.16.0 (b0b7efd0).
    function _buildLayerZeroIntegration(address facet) internal pure returns (IBeaconLike.Config memory) {
        IBeaconLike.Wire[] memory wires = new IBeaconLike.Wire[](6);

        wires[0] = _wire("layerZero_", "setRecipient(uint32,bytes32)");
        wires[1] = _wire("layerZero_", "transfer(address,uint256,uint32)");
        wires[2] = _wire("layerZero_", "getRecipient(uint32)");
        wires[3] = _wire("layerZero_", "getTransferRateLimitKey(address,bytes32,uint32,address)");
        wires[4] = _wire("layerZero_", "quoteTransfer(address,uint256,uint32)");
        wires[5] = _wire("layerZero_", "VERSION()");

        return IBeaconLike.Config({ facet: facet, wires: wires });
    }

    // A wire maps the controller's prefixed call selector to the facet's own selector.
    function _wire(string memory prefix, string memory facetSignature) internal pure returns (IBeaconLike.Wire memory) {
        return IBeaconLike.Wire({
            callSelector:     bytes4(keccak256(bytes(string.concat(prefix, facetSignature)))),
            delegateSelector: bytes4(keccak256(bytes(facetSignature)))
        });
    }

}
