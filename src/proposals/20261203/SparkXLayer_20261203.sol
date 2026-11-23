// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { XLayer } from "spark-address-registry/XLayer.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

/**
 * @title  December 3, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice Spark Savings:
 *         - Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU.
 * Forum:  TBD (forum post planned for 2026-11-20)
 * Vote:   TBD
 */
contract SparkXLayer_20261203 {

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    // Ethereum spUSDT PAU ALMProxy (Pre-deployed contracts 1), created by EthereumSparkSpUSDTPayload.
    address internal constant ETHEREUM_SPUSDT_PAU_ALM_PROXY = 0x2ceF3e65858EE6706FAd66550876412d08342BC8;

    function execute() external {
        // 3. Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU.
        ForeignController(XLayer.ALM_CONTROLLER).setLayerZeroRecipient(
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(ETHEREUM_SPUSDT_PAU_ALM_PROXY)))
        );
    }

}
