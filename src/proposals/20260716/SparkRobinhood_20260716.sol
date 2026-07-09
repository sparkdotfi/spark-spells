// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { Robinhood } from "spark-address-registry/Robinhood.sol";

import { SLLHelpers } from "../../libraries/SLLHelpers.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

interface IALMProxyFreezableLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

/**
 * @title  July 16, 2026 Spark Robinhood Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer - Activate SLL and Spark Savings Infrastructure.
 * Forum:  https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-spark-for-upcoming-spell/28029
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xd177bc28b65afb23dc39a5e7cfdded7084b3b722b230e08d7067b68fa0f4486a
 */
contract SparkRobinhood_20260716 {

    address internal constant OLD_FREEZER_RELAYER_SETTER = 0x59C85fe4385403e93877e48e5521f2F02B150359;

    function execute() external {
        ForeignController controller = ForeignController(Robinhood.ALM_CONTROLLER);

        // Grant ALLOCATOR_ROLE Role for Relayer 1 and 2 on ALM_PROXY_FREEZABLE and FREEZER_ROLE role to the ALM_FREEZER_MULTISIG
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Robinhood.ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Robinhood.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   Robinhood.ALM_FREEZER_MULTISIG);

        ISparkVaultV2Like spUSDGvault = ISparkVaultV2Like(Robinhood.SPARK_VAULT_V2_SPUSDG);

        spUSDGvault.revokeRole(spUSDGvault.SETTER_ROLE(), OLD_FREEZER_RELAYER_SETTER);
        spUSDGvault.grantRole(spUSDGvault.SETTER_ROLE(),  Robinhood.ALM_PROXY_FREEZABLE);

        controller.grantRole(controller.FREEZER(),  Robinhood.ALM_FREEZER_MULTISIG);
        controller.revokeRole(controller.FREEZER(), OLD_FREEZER_RELAYER_SETTER);

        controller.grantRole(controller.RELAYER(),  Robinhood.ALM_BACKSTOP_RELAYER_MULTISIG);
        controller.revokeRole(controller.RELAYER(), OLD_FREEZER_RELAYER_SETTER);

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                controller.LIMIT_ASSET_TRANSFER(),
                Robinhood.USDG,
                Robinhood.PAXOS_USDG_DEPOSIT
            ),
            Robinhood.ALM_RATE_LIMITS,
            50_000_000e6,
            250_000_000e6 / uint256(1 days),
            6
        );
    }

}
