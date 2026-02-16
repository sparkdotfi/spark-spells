// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SLLHelpers, SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

/**
 * @title  February 26, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Treasury:
 *         - Spark Foundation Grant for March (Exec).
 *         - SPK Buybacks Transfer for February 2026 (Exec).
 *         Spark Liquidity Layer:
 *         - Increase Rate Limit for SparkLend USDT.
 *         - Increase Rate Limit for Aave Core USDT.
 *         - Increase Rate Limit for Maple syrupUSDT.
 *         - Onboard with Paxos (Exec).
 *         - Onboard Morpho v2 USDT Vault.
 * Forum:  https://forum.sky.money/t/february-26-2026-proposed-changes-to-spark-for-upcoming-spell/27719
 * Vote:   
 */
contract SparkEthereum_20260226 is SparkPayloadEthereum {

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT     = 571_957e18;

    address internal constant PAXOS_USDC_PYUSD = 0xFb1F749024b4544c425f5CAf6641959da31EdF37;
    address internal constant PAXOS_PYUSD_USDC = 0x2f7BE67e11A4D621E36f1A8371b0a5Fe16dE6B20;
    address internal constant PAXOS_PYUSD_USDG = 0x227B1912C2fFE1353EA3A603F1C05F030Cc262Ff;
    address internal constant PAXOS_USDG_PYUSD = 0x035b322D0e79de7c8733CdDA5a7EF8b51a6cfcfa;

    function _postExecute() internal override {
        // Spark Foundation Grant for March (Exec)
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG, FOUNDATION_GRANT_AMOUNT);

        // SPK Buybacks Transfer for February 2026 (Exec)
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);

        // Increase Rate Limit for SparkLend USDT
        _configureAaveToken(
            SparkLend.USDT_SPTOKEN,
            250_000_000e6,
            2_000_000_000e6 / uint256(1 days)
        );

        // Increase Rate Limit for Aave Core USDT
        _configureAaveToken(
            Ethereum.ATOKEN_CORE_USDT,
            10_000_000e6,
            1_000_000_000e6 / uint256(1 days)
        );

        // Increase Rate Limit for Maple syrupUSDT
        SLLHelpers.configureERC4626Vault({
            rateLimits:    Ethereum.ALM_RATE_LIMITS,
            vault:         Ethereum.SYRUP_USDT,
            depositMax:    25_000_000e6,
            depositSlope:  100_000_000e6 / uint256(1 days),
            withdrawMax:   50_000_000e6,
            withdrawSlope: 500_000_000e6 / uint256(1 days)
        });

        // Onboard with Paxos
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                PAXOS_USDC_PYUSD
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                PAXOS_PYUSD_USDC
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            200_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                PAXOS_PYUSD_USDG
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDG,
                PAXOS_USDG_PYUSD
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            100_000_000e6 / uint256(1 days),
            6
        );

        // Onboard Morpho v2 USDT Vault
        _setUpNewMorphoVaultV2({
            asset           : Ethereum.USDT,
            salt            : bytes32("SPARK_MORPHO_VAULT_V2_USDT"),
            initialDeposit  : 1e6,
            sllDepositMax   : 50_000_000e6,
            sllDepositSlope : 1_000_000_000e6 / uint256(1 days)
        });
    }

}
