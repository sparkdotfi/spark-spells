// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ReserveConfiguration } from "lib/sparklend-v1-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { OTCBuffer }         from "spark-alm-controller/src/OTCBuffer.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

/**
 * @title  June 18, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Onboard Binance with OTC-Buffer.
 *         Spark Treasury:
 *         - Grants for Spark Foundation and Spark Assets Foundation for Q3 2026.
 * Forum:  https://forum.skyeco.com/t/june-18-2026-proposed-changes-to-spark-for-upcoming-spell/27952
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x81e46a9c323dafde20fa6104fb93855889217b590335157c3c58be6760735747
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0xe556733096975218413695c0bd3905a865a38e4ded7603551b40f49cebfbb9ba
 */
contract SparkEthereum_20260618 is SparkPayloadEthereum {

    address internal constant BINANCE_EXCHANGE   = 0xd010b876696F345d9E0a1B70F573244FcC2e0A0e;
    address internal constant BINANCE_OTC_BUFFER = 0x1851c64BBfad132CBE75481f1690C381288ea492;

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;

    constructor() {
        // PAYLOAD_BASE     = 0x1566BFA55D95686a823751298533D42651183988;
        // PAYLOAD_OPTIMISM = 0x0000000000000000000000000000000000000000;
        // PAYLOAD_UNICHAIN = 0x0000000000000000000000000000000000000000;
    }

    function _postExecute() internal override {
        // 1. Onboard Binance with OTC-Buffer.
        IRateLimits       rateLimits        = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        OTCBuffer         otcBuffer         = OTCBuffer(BINANCE_OTC_BUFFER);

        otcBuffer.approve(Ethereum.USDT, type(uint256).max);
        otcBuffer.approve(Ethereum.USDC, type(uint256).max);

        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_OTC_SWAP(),
            BINANCE_EXCHANGE
        );

        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        mainnetController.setMaxSlippage(BINANCE_EXCHANGE,     0.998e18);
        mainnetController.setOTCBuffer(BINANCE_EXCHANGE,       address(otcBuffer));
        mainnetController.setOTCRechargeRate(BINANCE_EXCHANGE, uint256(50_000e18) / 1 days);

        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDT, true);
        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDC, true);

        // 7. Grants for Spark Foundation and Spark Assets Foundation for Q3 2026
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
