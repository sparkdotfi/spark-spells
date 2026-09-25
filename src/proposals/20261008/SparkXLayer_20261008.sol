// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { XLayer } from "spark-address-registry/XLayer.sol";

interface ISavingsIntentsLike {

    function RELAYER() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function updateVaultConfig(
        address vault,
        bool    whitelisted_,
        uint256 minIntentAssets_,
        uint256 maxIntentAssets_
    ) external;

}

/**
 * @title  October 8, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice
 * Forum:
 * Vote:
 */
contract SparkXLayer_20261008 {

    function execute() external {
        // Grant RELAYER role in savings intents to SPUSDC_PAU_ADMINISTERED_AGENT
        ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).grantRole(
            ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).RELAYER(),
            XLayer.SPUSDC_PAU_ADMINISTERED_AGENT
        );

        // Update vault config in savings intents to add spUSDC.abi
        ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).updateVaultConfig({
            vault            : XLayer.SPARK_VAULT_V2_SPUSDC,
            whitelisted_     : true,
            minIntentAssets_ : 1_000_000e6,
            maxIntentAssets_ : 500_000_000e6
        });
    }

}
