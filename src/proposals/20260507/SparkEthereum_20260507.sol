// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

/**
 * @title  May 7, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Update LBTC Parameters.
 *         - Update WBTC Parameters.
 *         Spark Treasury:
 *         - Monthly Grants for Spark Foundation and Spark Assets Foundation.
 *         - Transfer Excess USDS from SubDAO Proxy for SPK Buybacks.
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20260507 is SparkPayloadEthereum {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 326_945e18;

    function _postExecute() internal override {
        // 7. Update LBTC Parameters.
        ICapAutomator(SparkLend.CAP_AUTOMATOR).setSupplyCapConfig({
            asset            : Ethereum.LBTC,
            max              : 5_000,
            gap              : 200,
            increaseCooldown : 12 hours
        });

        // 8. Update WBTC Parameters.
        ICapAutomator(SparkLend.CAP_AUTOMATOR).setSupplyCapConfig({
            asset            : Ethereum.WBTC,
            max              : 30_000,
            gap              : 500,
            increaseCooldown : 12 hours
        });

        // 10. Monthly Grants for Spark Foundation and Spark Assets Foundation
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, ASSET_FOUNDATION_GRANT_AMOUNT);

        // 11. Transfer Excess USDS from SubDAO Proxy for SPK Buybacks
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);
    }

}
