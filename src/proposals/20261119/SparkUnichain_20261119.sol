// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Unichain } from "spark-address-registry/Unichain.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadUnichain } from "../../SparkPayloadUnichain.sol";

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
 * @title  November 19, 2026 Spark Unichain Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Deprecate the Spark Liquidity Layer on Unichain.
 * Forum:  https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-spark-for-upcoming-spell/28390
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x4ca8fbf47c4679aa74d3cd6681c89ced9383e9f923b7dc6f33c94f7f8f0cee5b
 */
contract SparkUnichain_20261119 is SparkPayloadUnichain {

    function execute() external {
        IALMProxy         almProxy   = IALMProxy(Unichain.ALM_PROXY);
        ForeignController controller = ForeignController(Unichain.ALM_CONTROLLER);
        IRateLimits       rateLimits = IRateLimits(Unichain.ALM_RATE_LIMITS);

        // 3. Deprecate the Spark Liquidity Layer on Unichain.

        // Return the remaining USDS and sUSDS to the Ethereum ALM Proxy.
        uint256 usdsWithdrawAmount  = IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY);
        uint256 susdsWithdrawAmount = IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        almProxy.doCall(
            Unichain.USDS,
            abi.encodeCall(IERC20.approve, (Unichain.TOKEN_BRIDGE, usdsWithdrawAmount))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike.bridgeERC20To,
                (Unichain.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, usdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.doCall(
            Unichain.SUSDS,
            abi.encodeCall(IERC20.approve, (Unichain.TOKEN_BRIDGE, susdsWithdrawAmount))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike.bridgeERC20To,
                (Unichain.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, susdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));

        // Set every rate limit on Unichain to zero.
        bytes32 psmDepositKey  = controller.LIMIT_PSM_DEPOSIT();
        bytes32 psmWithdrawKey = controller.LIMIT_PSM_WITHDRAW();

        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Unichain.USDC),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Unichain.USDS),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmDepositKey,  Unichain.SUSDS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Unichain.USDC),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Unichain.USDS),  0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(psmWithdrawKey, Unichain.SUSDS), 0, 0);

        rateLimits.setRateLimitData(controller.LIMIT_USDC_TO_CCTP(), 0, 0);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(controller.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            0,
            0
        );
    }

}
