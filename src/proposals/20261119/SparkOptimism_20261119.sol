// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Optimism } from "spark-address-registry/Optimism.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadOptimism } from "../../SparkPayloadOptimism.sol";

interface ITokenBridgeLike {

    function bridgeERC20To(
        address        localToken,
        address        remoteToken,
        address        to,
        uint256        amount,
        uint32         minGasLimit,
        bytes   memory extraData
    ) external;

}

/**
 * @title  November 19, 2026 Spark Optimism Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Deprecate the Spark Liquidity Layer on OP Mainnet.
 * Forum:  https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-spark-for-upcoming-spell/28390
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x61efe7dcaadc2baf6b0dde519ceb3e360f7ac864c888004108d97012843246ed
 */
contract SparkOptimism_20261119 is SparkPayloadOptimism {

    function execute() external {
        IALMProxy         almProxy   = IALMProxy(Optimism.ALM_PROXY);
        ForeignController controller = ForeignController(Optimism.ALM_CONTROLLER);
        IRateLimits       rateLimits = IRateLimits(Optimism.ALM_RATE_LIMITS);

        // 2. Deprecate the Spark Liquidity Layer on OP Mainnet.

        // Return the remaining USDS and sUSDS to the Ethereum ALM Proxy.
        uint256 usdsWithdrawAmount  = IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY);
        uint256 susdsWithdrawAmount = IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        almProxy.doCall(
            Optimism.USDS,
            abi.encodeCall(IERC20.approve, (Optimism.TOKEN_BRIDGE, usdsWithdrawAmount))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike.bridgeERC20To,
                (Optimism.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, usdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.doCall(
            Optimism.SUSDS,
            abi.encodeCall(IERC20.approve, (Optimism.TOKEN_BRIDGE, susdsWithdrawAmount))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike.bridgeERC20To,
                (Optimism.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, susdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));

        // Set every rate limit on OP Mainnet to zero.
        bytes32 psmDepositKey  = controller.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey = controller.LIMIT_PSM_WITHDRAW();

        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Optimism.USDC),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Optimism.USDS),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Optimism.SUSDS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Optimism.USDC),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Optimism.USDS),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Optimism.SUSDS), 0, 0);

        rateLimits.setRateLimitData(controller.LIMIT_USDC_TO_CCTP(), 0, 0);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );
    }

}
