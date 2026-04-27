// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

/**
 * @title  May 7, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Update LBTC Parameters.
 *         - Update WBTC Parameters.
 *         Spark Liquidity Layer:
 *         - Offboard Aave Core USDT.
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

    address internal constant OLD_MORPHO_VAULT_V2_USDT = Ethereum.MORPHO_VAULT_V2_USDT;
    address internal constant NEW_MORPHO_VAULT_V2_USDT = 0xb0c424116172B55CbB6dD3136F5989F7959e5B91;

    constructor() {
        // PAYLOAD_AVALANCHE = ;
    }

    function _postExecute() internal override {
        MainnetController almController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        // 5a. Deactivate old Morpho Vault V2 USDT integration.
        bytes32 erc4626DepositKey  = almController.LIMIT_4626_DEPOSIT();

        bytes32 OLD_MORPHO_VAULT_V2_USDT_DEPOSIT_KEY = RateLimitHelpers.makeAddressKey(erc4626DepositKey, OLD_MORPHO_VAULT_V2_USDT);

        rateLimits.setRateLimitData(OLD_MORPHO_VAULT_V2_USDT_DEPOSIT_KEY,  0, 0);

        // 5b. Onboard new Morpho Vault V2 USDT integration with same configuration as old one.
        // NOTE: New Morpho Vault V2 USDT is already configured with the same parameters as old one outside spell.
        //       So onboarding only configures the rate limit.

        _configureERC4626Vault({
            controller      : Ethereum.ALM_CONTROLLER,
            vault           : NEW_MORPHO_VAULT_V2_USDT,
            depositMax      : 100_000_000e6,
            depositSlope    : 1_000_000_000e6 / uint256(1 days),
            maxExchangeRate : 1_000_000
        });

        // 6. Offboard Aave Core USDT.
        bytes32 aaveDepositKey  = almController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey = almController.LIMIT_AAVE_WITHDRAW();

        bytes32 ATOKEN_CORE_USDT_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Ethereum.ATOKEN_CORE_USDT);
        bytes32 ATOKEN_CORE_USDT_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Ethereum.ATOKEN_CORE_USDT);

        rateLimits.setRateLimitData(ATOKEN_CORE_USDT_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(ATOKEN_CORE_USDT_WITHDRAW_KEY, 0, 0);

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
