// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { XLayer } from "spark-address-registry/XLayer.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

interface ISparkVaultLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function SETTER_ROLE() external view returns (bytes32);

}

/**
 * @title  December 3, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice Spark Savings:
 *         - Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU and move SETTER to the Spark Vaults Administered Agent.
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkXLayer_20261203 {

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    // PLACEHOLDER: Ethereum spUSDT PAU ALMProxy (Pre-deployed contracts 1), from spark-address-registry at handover.
    address internal constant ETHEREUM_SPUSDT_PAU_ALM_PROXY = 0x2026120300000000000000000000000000000002;

    // PLACEHOLDER: Spark Vaults Administered Agent on X Layer (Pre-deployed contracts 6), from spark-address-registry at handover.
    address internal constant SPARK_ADMINISTERED_AGENT = 0x2026120300000000000000000000000000000021;

    function execute() external {
        ISparkVaultLike spUsdt = ISparkVaultLike(XLayer.SPARK_VAULT_V2_SPUSDT);

        // 3. Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU and move SETTER.

        // 3.1 LayerZero recipient for Ethereum, from the Ethereum Spark Liquidity Layer ALM Proxy.
        ForeignController(XLayer.ALM_CONTROLLER).setLayerZeroRecipient(
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(ETHEREUM_SPUSDT_PAU_ALM_PROXY)))
        );

        // 3.2 Move SETTER on spUSDT.
        spUsdt.grantRole(spUsdt.SETTER_ROLE(),  SPARK_ADMINISTERED_AGENT);
        spUsdt.revokeRole(spUsdt.SETTER_ROLE(), XLayer.ALM_PROXY_FREEZABLE);
    }

}
