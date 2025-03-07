// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import {
    ControllerInstance,
    ForeignControllerInit
} from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { SparkPayloadArbitrumOne, Arbitrum, SparkLiquidityLayerHelpers } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  Feb 20, 2025 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer: Activate Spark Liquidity Layer
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/feb-20-2025-proposed-changes-to-spark-for-upcoming-spell/25951
 * Vote:   https://vote.makerdao.com/polling/QmcicBXG#poll-detail
 */
contract SparkArbitrumOne_20250220 is SparkPayloadArbitrumOne {

    function execute() external {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);
        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(Ethereum.ALM_PROXY)))
        });

        ForeignControllerInit.initAlmSystem({
            controllerInst: ControllerInstance({
                almProxy   : Arbitrum.ALM_PROXY,
                controller : Arbitrum.ALM_CONTROLLER,
                rateLimits : Arbitrum.ALM_RATE_LIMITS
            }),
            configAddresses: ForeignControllerInit.ConfigAddressParams({
                freezer       : Arbitrum.ALM_FREEZER,
                relayer       : Arbitrum.ALM_RELAYER,
                oldController : address(0)
            }),
            checkAddresses: ForeignControllerInit.CheckAddressParams({
                admin : Arbitrum.SPARK_EXECUTOR,
                psm   : Arbitrum.PSM3,
                cctp  : Arbitrum.CCTP_TOKEN_MESSENGER,
                usdc  : Arbitrum.USDC,
                usds  : Arbitrum.USDS,
                susds : Arbitrum.SUSDS
            }),
            mintRecipients: mintRecipients
        });

        SparkLiquidityLayerHelpers.activateSparkLiquidityLayer({
            rateLimits  : Arbitrum.ALM_RATE_LIMITS,
            usdc        : Arbitrum.USDC,
            usds        : Arbitrum.USDS,
            susds       : Arbitrum.SUSDS,
            usdcDeposit : RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            usdcWithdraw : RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            cctpEthereumDeposit : RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 25_000_000e6 / uint256(1 days)
            })
        });
    }

}
