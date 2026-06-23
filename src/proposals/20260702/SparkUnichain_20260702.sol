// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Unichain } from "spark-address-registry/Unichain.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

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
 * @title  July 2, 2026 Spark Unichain Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Remove Excess Liquidity.
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   
 */
contract SparkUnichain_20260702 is SparkPayloadUnichain {

    function execute() external {
        IALMProxy almProxy = IALMProxy(Unichain.ALM_PROXY);

        uint256 usdsWithdrawAmount  = IERC20(Unichain.USDS).balanceOf(Unichain.ALM_PROXY);
        uint256 susdsWithdrawAmount = IERC20(Unichain.SUSDS).balanceOf(Unichain.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        // Withdraw USDS from Unichain to Ethereum
        almProxy.doCall(
            Unichain.USDS,
            abi.encodeCall(IERC20(Unichain.USDS).approve, (Unichain.TOKEN_BRIDGE, usdsWithdrawAmount))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Unichain.TOKEN_BRIDGE).bridgeERC20To,
                (Unichain.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, usdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        // Withdraw sUSDS from Unichain to Ethereum
        almProxy.doCall(
            Unichain.SUSDS,
            abi.encodeCall(IERC20(Unichain.SUSDS).approve, (Unichain.TOKEN_BRIDGE, susdsWithdrawAmount))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Unichain.TOKEN_BRIDGE).bridgeERC20To,
                (Unichain.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, susdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
