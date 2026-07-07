// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

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
 * @title  July 2, 2026 Spark Base Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Remove Excess Liquidity.
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x4f6d0c56862e4b66e006c8c363a8daa79df521af0964360016edd2bfb8a49178
 */
contract SparkBase_20260702 is SparkPayloadBase {

    function execute() external {
        IALMProxy almProxy = IALMProxy(Base.ALM_PROXY);

        uint256 usdsWithdrawAmount  = IERC20(Base.USDS).balanceOf(Base.ALM_PROXY);
        uint256 susdsWithdrawAmount = IERC20(Base.SUSDS).balanceOf(Base.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        // Withdraw USDS from Base to Ethereum
        almProxy.doCall(
            Base.USDS,
            abi.encodeCall(IERC20(Base.USDS).approve, (Base.TOKEN_BRIDGE, usdsWithdrawAmount))
        );
        almProxy.doCall(
            Base.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Base.TOKEN_BRIDGE).bridgeERC20To,
                (Base.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, usdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        // Withdraw sUSDS from Base to Ethereum
        almProxy.doCall(
            Base.SUSDS,
            abi.encodeCall(IERC20(Base.SUSDS).approve, (Base.TOKEN_BRIDGE, susdsWithdrawAmount))
        );
        almProxy.doCall(
            Base.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Base.TOKEN_BRIDGE).bridgeERC20To,
                (Base.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, susdsWithdrawAmount, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
