// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

/**
 * @title  July 16, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Deactivate Old USDT Morpho V2 Vault.
 *         - Enable USDT Bridging to X Layer.
 *         - Enable USDG Bridging to Robinhood Chain.
 * Forum:  https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-spark-for-upcoming-spell/28029
 * Vote:
 */
contract SparkEthereum_20260716 is SparkPayloadEthereum {

    address internal constant ANCHORAGE_FEES_RECIPIENT = 0x2002020202020202020202020202020202020202;  // TODO: change
    address internal constant INCENTIVES_RECIPIENT     = 0x2002020202020202020202020202020202020202;  // TODO: change
    address internal constant PAXOS_USDG_DEPOSIT       = 0xf752cF318dfF2C01575c98741AA52e7a34d873Fd;
    address internal constant USDT_OFT                 = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;
    address internal constant XLAYER_ALM_PROXY         = 0x0000000000000000000000000000000000000064;  // TODO: change

    uint256 internal constant ANCHORAGE_FEES_AMOUNT         = 500_000e18;
    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant INCENTIVES_AMOUNT             = 2_000_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 64_231e18;

    uint32 internal constant LZ_ENDPOINT_XLAYER = 30110;  // TODO: change

    constructor() {
    }

    function _postExecute() internal override {
        MainnetController almController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        // Enable USDG Bridging to Robinhood Chain.

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                almController.LIMIT_ASSET_TRANSFER(),
                Ethereum.USDG,
                PAXOS_USDG_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            50_000_000e6,
            250_000_000e6 / uint256(1 days),
            6
        );

        // Enable USDT Bridging to X Layer.

        almController.setLayerZeroRecipient(
            LZ_ENDPOINT_XLAYER,
            bytes32(uint256(uint160(XLAYER_ALM_PROXY)))
        );

        rateLimits.setRateLimitData(
            keccak256(abi.encode(almController.LIMIT_LAYERZERO_TRANSFER(), USDT_OFT, LZ_ENDPOINT_XLAYER)),
            5_000_000e6,
            uint256(100_000_000e6) / 1 days
        );

        // Deactivate Old USDT Morpho V2 Vault.

        bytes32 MORPHO_VAULT_V2_USDT_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_V2_USDT);
        bytes32 MORPHO_VAULT_V2_USDT_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(almController.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_V2_USDT);

        rateLimits.setRateLimitData(MORPHO_VAULT_V2_USDT_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(MORPHO_VAULT_V2_USDT_WITHDRAW_KEY, 0, 0);

        // USDS Transfer to Spark Foundation for Incentives.

        IERC20(Ethereum.USDS).transfer(INCENTIVES_RECIPIENT, INCENTIVES_AMOUNT);

        // USDS Transfer to Spark Assets Foundation for Anchorage Fees.

        IERC20(Ethereum.USDS).transfer(ANCHORAGE_FEES_RECIPIENT, ANCHORAGE_FEES_AMOUNT);

        // Grants for Spark Foundation and Spark Assets Foundation (Exec).

        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, ASSET_FOUNDATION_GRANT_AMOUNT);

        // Transfer USDS for Buybacks (Exec).

        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);
    }

}
