// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Optimism } from "spark-address-registry/Optimism.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { SparkPayloadOptimism } from "../../SparkPayloadOptimism.sol";

interface ITokenBridgeLike {

    function bridgeERC20To(
        address      _localToken,
        address      _remoteToken,
        address      _to,
        uint256      _amount,
        uint32       _minGasLimit,
        bytes memory _extraData
    ) external;

}

/**
 * @title  June 18, 2026 Spark Optimism Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Remove Excess Liquidity.
 * Forum:
 * Vote:
 */
contract SparkOptimism_20260618 is SparkPayloadOptimism {

    uint256 internal constant USDS_WITHDRAW_AMOUNT  = 10_000e18;
    uint256 internal constant SUSDS_WITHDRAW_AMOUNT = 10_000e18;

    function execute() external {
        IALMProxy almProxy = IALMProxy(Optimism.ALM_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(), address(this));

        // Withdraw USDS from Optimism to Ethereum
        almProxy.doCall(
            Optimism.USDS,
            abi.encodeCall(IERC20(Optimism.USDS).approve, (Optimism.TOKEN_BRIDGE, USDS_WITHDRAW_AMOUNT))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Optimism.TOKEN_BRIDGE).bridgeERC20To,
                (Optimism.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, USDS_WITHDRAW_AMOUNT, uint32(500_000), bytes(""))
            )
        );

        // Withdraw sUSDS from Optimism to Ethereum
        almProxy.doCall(
            Optimism.SUSDS,
            abi.encodeCall(IERC20(Optimism.SUSDS).approve, (Optimism.TOKEN_BRIDGE, SUSDS_WITHDRAW_AMOUNT))
        );
        almProxy.doCall(
            Optimism.TOKEN_BRIDGE,
            abi.encodeCall(
                ITokenBridgeLike(Optimism.TOKEN_BRIDGE).bridgeERC20To,
                (Optimism.SUSDS, Ethereum.SUSDS, Ethereum.ALM_PROXY, SUSDS_WITHDRAW_AMOUNT, uint32(500_000), bytes(""))
            )
        );

        almProxy.revokeRole(almProxy.CONTROLLER(), address(this));
    }

}
