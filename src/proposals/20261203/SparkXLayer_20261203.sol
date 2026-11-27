// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Ethereum } from "../../../lib/spark-address-registry/src/Ethereum.sol";
import { XLayer }   from "../../../lib/spark-address-registry/src/XLayer.sol";

import { ForeignController } from "../../../lib/spark-alm-controller/src/ForeignController.sol";

/**
 * @title  December 3, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice Spark Savings:
 *         - Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU.
 * Forum:  https://forum.skyeco.com/t/december-3-2026-proposed-changes-to-spark-for-upcoming-spell/28472
 * Vote:   TBD
 */
contract SparkXLayer_20261203 {

    uint32 internal constant LZ_EID_ETHEREUM = 30101;

    function execute() external {
        // 3. Point spUSDT's LayerZero route to Ethereum at the Ethereum spUSDT PAU.
        ForeignController(XLayer.ALM_CONTROLLER).setLayerZeroRecipient(
            LZ_EID_ETHEREUM,
            bytes32(uint256(uint160(Ethereum.SPUSDT_PAU_ALM_PROXY)))
        );
    }

}
