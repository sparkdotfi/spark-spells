// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { XLayer } from "spark-address-registry/XLayer.sol";

interface IALMProxyFreezableLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

/**
 * @title  July 16, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice Spark Savings - Deploy spUSDT.
 * Forum:  https://forum.skyeco.com/t/july-16-2026-proposed-changes-to-spark-for-upcoming-spell/28029
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xd177bc28b65afb23dc39a5e7cfdded7084b3b722b230e08d7067b68fa0f4486a
 */
contract SparkXLayer_20260716 {

    function execute() external {
        // Grant ALLOCATOR_ROLE Role for Relayer 1 and 2 on ALM_PROXY_FREEZABLE and FREEZER_ROLE role to the ALM_FREEZER_MULTISIG
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(XLayer.ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), XLayer.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), XLayer.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   XLayer.ALM_FREEZER_MULTISIG);
    }

}
