// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import {
    ControllerInstance,
    ForeignControllerInit
} from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadOptimism, Optimism, SLLHelpers } from "../../SparkPayloadOptimism.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

/**
 * @title  May 29, 2025 Spark Optimism Proposal
 * @notice Spark Liquidity Layer: Activate Spark Liquidity Layer
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell/26372/2
 * Vote:   TODO
 */
contract SparkOptimism_20250529 is SparkPayloadOptimism {

    function execute() external {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);
        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(Ethereum.ALM_PROXY)))
        });
    
        ForeignControllerInit.initAlmSystem({
            controllerInst: ControllerInstance({
                almProxy   : Optimism.ALM_PROXY,
                controller : Optimism.ALM_CONTROLLER,
                rateLimits : Optimism.ALM_RATE_LIMITS
            }),
            configAddresses: ForeignControllerInit.ConfigAddressParams({
                freezer       : Optimism.ALM_FREEZER,
                relayer       : Optimism.ALM_RELAYER,
                oldController : address(0)
            }),
            checkAddresses: ForeignControllerInit.CheckAddressParams({
                admin : Optimism.SPARK_EXECUTOR,
                psm   : Optimism.PSM3,
                cctp  : Optimism.CCTP_TOKEN_MESSENGER,
                usdc  : Optimism.USDC,
                usds  : Optimism.USDS,
                susds : Optimism.SUSDS
            }),
            mintRecipients: mintRecipients
        });

        SLLHelpers.activateSparkLiquidityLayer({
            rateLimits  : Optimism.ALM_RATE_LIMITS,
            usdc        : Optimism.USDC,
            usds        : Optimism.USDS,
            susds       : Optimism.SUSDS,
            usdcDeposit : RateLimitData({ // TODO: what values to get here.
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
