// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import {
    ControllerInstance,
    ForeignControllerInit
} from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadUnichain, Unichain, SLLHelpers } from "../../SparkPayloadUnichain.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

/**
 * @title  May 29, 2025 Spark Unichain Proposal
 * @notice Spark Liquidity Layer: Activate Spark Liquidity Layer
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell/26372/2
 * Vote:   TODO
 */
contract SparkUnichain_20250529 is SparkPayloadUnichain {

    function execute() external {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);
        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY)
        });
    
        ForeignControllerInit.initAlmSystem({
            controllerInst: ControllerInstance({
                almProxy   : Unichain.ALM_PROXY,
                controller : Unichain.ALM_CONTROLLER,
                rateLimits : Unichain.ALM_RATE_LIMITS
            }),
            configAddresses: ForeignControllerInit.ConfigAddressParams({
                freezer       : Unichain.ALM_FREEZER,
                relayer       : Unichain.ALM_RELAYER,
                oldController : address(0)
            }),
            checkAddresses: ForeignControllerInit.CheckAddressParams({
                admin : Unichain.SPARK_EXECUTOR,
                psm   : Unichain.PSM3,
                cctp  : Unichain.CCTP_TOKEN_MESSENGER,
                usdc  : Unichain.USDC,
                usds  : Unichain.USDS,
                susds : Unichain.SUSDS
            }),
            mintRecipients: mintRecipients
        });

        SLLHelpers.activateSparkLiquidityLayer({
            rateLimits  : Unichain.ALM_RATE_LIMITS,
            usdc        : Unichain.USDC,
            usds        : Unichain.USDS,
            susds       : Unichain.SUSDS,
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
