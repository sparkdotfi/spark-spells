// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Optimism } from "spark-address-registry/Optimism.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

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
 * @title  July 2, 2026 Spark Optimism Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Remove Excess Liquidity.
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   
 */
contract SparkOptimism_20260702 is SparkPayloadOptimism {

    function execute() external {
        IALMProxy almProxy = IALMProxy(Optimism.ALM_PROXY);

        uint256 usdsWithdrawAmount  = IERC20(Optimism.USDS).balanceOf(Optimism.ALM_PROXY);
        uint256 susdsWithdrawAmount = IERC20(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        // Withdraw USDS from Optimism to Ethereum
        almProxy.doCall(
            Optimism.USDS,
            abi.encodeCall(IERC20(Optimism.USDS).approve, (Optimism.TOKEN_BRIDGE, usdsWithdrawAmount))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Optimism.TOKEN_BRIDGE).bridgeERC20To,
                (Optimism.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, usdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        // Withdraw sUSDS from Optimism to Ethereum
        almProxy.doCall(
            Optimism.SUSDS,
            abi.encodeCall(IERC20(Optimism.SUSDS).approve, (Optimism.TOKEN_BRIDGE, susdsWithdrawAmount))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Optimism.TOKEN_BRIDGE).bridgeERC20To,
                (Optimism.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, susdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
