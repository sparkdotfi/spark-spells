// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Avalanche } from "spark-address-registry/Avalanche.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { LZForwarder }   from "xchain-helpers/forwarders/LZForwarder.sol";
import { LZReceiver }    from "xchain-helpers/receivers/LZReceiver.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

import { SparkPayloadAvalanche } from "../../SparkPayloadAvalanche.sol";

/**
 * @title  November 19, 2026 Spark Avalanche Proposal
 * @author Phoenix Labs
 * @notice Spark Savings and Spark Liquidity Layer - Deprecate Avalanche.
 * Forum:  https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-spark-for-upcoming-spell/28390
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xf1426e0ea2fcab571a5d59e650b24a88f56c041efe8ddc31d22a9d354dd57f97
 */
contract SparkAvalanche_20261119 is SparkPayloadAvalanche {

    function execute() external {
        ISparkVaultV2Like spUsdc     = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);
        ForeignController controller = ForeignController(Avalanche.ALM_CONTROLLER);
        IRateLimits       rateLimits = IRateLimits(Avalanche.ALM_RATE_LIMITS);
        IExecutor         executor   = IExecutor(Avalanche.SPARK_EXECUTOR);

        // 4. Deprecate Avalanche.

        // Close spUSDC to deposits and fix its rate at 0%.
        spUsdc.setDepositCap(0);
        spUsdc.setVsrBounds(1e27, 1e27);

        // Close the USDC route to Ethereum and stop the ALM Proxy taking USDC from spUSDC.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAddressKey(controller.LIMIT_SPARK_VAULT_TAKE(), Avalanche.SPARK_VAULT_V2_SPUSDC),
            0,
            0
        );

        // Retire the Avalanche governance bridge. This payload was delivered through it, so after these two calls
        // no further message from the Spark SubProxy can reach the Avalanche Spark Executor.
        LZReceiver(Avalanche.SPARK_RECEIVER).setPeer(LZForwarder.ENDPOINT_ID_ETHEREUM, bytes32(0));

        executor.revokeRole(executor.SUBMISSION_ROLE(), Avalanche.SPARK_RECEIVER);
    }

}
