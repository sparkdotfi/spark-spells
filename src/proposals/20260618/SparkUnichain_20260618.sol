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
 * @title  June 18, 2026 Spark Unichain Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Remove Excess Liquidity.
 * Forum:  https://forum.skyeco.com/t/june-18-2026-proposed-changes-to-spark-for-upcoming-spell/27952
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x81e46a9c323dafde20fa6104fb93855889217b590335157c3c58be6760735747
 */
contract SparkUnichain_20260618 is SparkPayloadUnichain {

    uint256 internal constant USDS_WITHDRAW_AMOUNT  = 10_000e18;
    uint256 internal constant SUSDS_WITHDRAW_AMOUNT = 10_000e18;

    function execute() external {
        IALMProxy almProxy = IALMProxy(Unichain.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        // Withdraw USDS from Unichain to Ethereum
        almProxy.doCall(
            Unichain.USDS,
            abi.encodeCall(IERC20(Unichain.USDS).approve, (Unichain.TOKEN_BRIDGE, USDS_WITHDRAW_AMOUNT))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Unichain.TOKEN_BRIDGE).bridgeERC20To,
                (Unichain.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, USDS_WITHDRAW_AMOUNT, uint32(500_000), bytes(""))
            )
        );

        // Withdraw sUSDS from Unichain to Ethereum
        almProxy.doCall(
            Unichain.SUSDS,
            abi.encodeCall(IERC20(Unichain.SUSDS).approve, (Unichain.TOKEN_BRIDGE, SUSDS_WITHDRAW_AMOUNT))
        );
        almProxy.doCall(
            Unichain.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Unichain.TOKEN_BRIDGE).bridgeERC20To,
                (Unichain.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, SUSDS_WITHDRAW_AMOUNT, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
