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
 * @notice Spark Savings Intents:
 *         - Add spUSDC to the X Layer Savings Vault Intents contract.
 *         - Make the spUSDC PAU Administered Agent a relayer on Savings Intents contract.
 * Forum:  https://forum.skyeco.com/t/october-8-2026-proposed-changes-to-spark-for-upcoming-spell/28265
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xeaab1672f63e49d6075eefbede7cab3fac3db3bba3c2f486eee7bb492d82ff3e
 */
contract SparkXLayer_20261008 {

    function execute() external {
        // Add spUSDC to the X Layer Savings Vault Intents contract.
        ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).updateVaultConfig({
            vault            : XLayer.SPARK_VAULT_V2_SPUSDC,
            whitelisted_     : true,
            minIntentAssets_ : 1_000_000e6,
            maxIntentAssets_ : 500_000_000e6
        });

        // Make the spUSDC PAU Administered Agent a relayer on Savings Intents contract.
        ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).grantRole(
            ISavingsIntentsLike(XLayer.SPARK_SAVINGS_INTENTS).RELAYER(),
            XLayer.SPUSDC_PAU_ADMINISTERED_AGENT
        );
    }

}
