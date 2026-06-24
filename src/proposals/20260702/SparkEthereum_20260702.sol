// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

/**
 * @title  July 2, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Set USDC Interest Rate Model to Target Very Low Liquidity.
 *         Spark Liquidity Layer:
 *         - Enable USDT Bridging to Arbitrum.
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xcd4642f0ada4ccb7d8ad744594dc1ea8051c5819724810b11aca042df6dd0a66
 */
contract SparkEthereum_20260702 is SparkPayloadEthereum {

    address internal constant NEW_USDC_IRM         = 0xDE99e49E9e42B1d8490C38926e6C9A79010e6eF2;
    address internal constant USDT_OFT             = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;
    uint32  internal constant LZ_ENDPOINT_ARBITRUM = 30110;

    constructor() {
        // PAYLOAD_ARBITRUM  = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // PAYLOAD_AVALANCHE = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // PAYLOAD_BASE      = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // PAYLOAD_OPTIMISM  = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
        // PAYLOAD_UNICHAIN  = 0x9A56C59453a2fBAe01Ba46045441490e5C7a664d;
    }

    function _postExecute() internal override {
        // 1. Set USDC Interest Rate Model to Target Very Low Liquidity.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDC, NEW_USDC_IRM);

        // 6. Enable USDT Bridging to Arbitrum.
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits        = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        mainnetController.setLayerZeroRecipient(
            LZ_ENDPOINT_ARBITRUM,
            bytes32(uint256(uint160(Arbitrum.ALM_PROXY)))
        );

        rateLimits.setRateLimitData(
            keccak256(abi.encode(mainnetController.LIMIT_LAYERZERO_TRANSFER(), USDT_OFT, LZ_ENDPOINT_ARBITRUM)),
            5_000_000e6,
            uint256(50_000_000e6) / 1 days
        );
    }

}
