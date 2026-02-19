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
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x29be63afc3b7495581259401c68e6dd892e0a8870a45ad66b2d7b224f4b33dde
 *         https://snapshot.box/#/s:sparkfi.eth/proposal/0xdc1931c6f37149183ae2f15b61f56621d5091d1ce4469ad95cc6cdd33963db8c
 */
contract SparkEthereum_20260226 is SparkPayloadEthereum {

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT     = 571_957e18;

    address internal constant MORPHO_VAULT_V2_USDT = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;
    address internal constant PAXOS_PYUSD_USDC     = 0x2f7BE67e11A4D621E36f1A8371b0a5Fe16dE6B20;
    address internal constant PAXOS_PYUSD_USDG     = 0x227B1912C2fFE1353EA3A603F1C05F030Cc262Ff;
    address internal constant PAXOS_USDC_PYUSD     = 0xFb1F749024b4544c425f5CAf6641959da31EdF37;
    address internal constant PAXOS_USDG_PYUSD     = 0x035b322D0e79de7c8733CdDA5a7EF8b51a6cfcfa;

    function _postExecute() internal override {
        // 1. Spark Foundation Grant for March (Exec)
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG, FOUNDATION_GRANT_AMOUNT);

        // 2. SPK Buybacks Transfer for February 2026 (Exec)
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);

        // 4. Increase Rate Limit for SparkLend USDT
        _configureAaveToken({
            token        : SparkLend.USDT_SPTOKEN,
            depositMax   : 250_000_000e6,
            depositSlope : 2_000_000_000e6 / uint256(1 days)
        });

        // 5. Increase Rate Limit for Aave Core USDT
        _configureAaveToken({
            token        : Ethereum.ATOKEN_CORE_USDT,
            depositMax   : 10_000_000e6,
            depositSlope : 1_000_000_000e6 / uint256(1 days)
        });

        // 6. Increase Rate Limit for Maple syrupUSDT
        bytes32 depositKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT();
        bytes32 redeemKey  = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM();

        bytes32 SYRUP_USDT_DEPOSIT_KEY = RateLimitHelpers.makeAddressKey(depositKey, Ethereum.SYRUP_USDT);
        bytes32 SYRUP_USDT_REDEEM_KEY  = RateLimitHelpers.makeAddressKey(redeemKey,  Ethereum.SYRUP_USDT);

        SLLHelpers.setRateLimitData({
            key        : SYRUP_USDT_DEPOSIT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 25_000_000e6,
            slope      : 100_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : SYRUP_USDT_REDEEM_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 50_000_000e6,
            slope      : 500_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // 7. Onboard with Paxos
        bytes32 transferKey = MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER();

        bytes32 PAXOS_USDC_PYUSD_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC,  PAXOS_USDC_PYUSD);
        bytes32 PAXOS_PYUSD_USDC_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.PYUSD, PAXOS_PYUSD_USDC);
        bytes32 PAXOS_PYUSD_USDG_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.PYUSD, PAXOS_PYUSD_USDG);
        bytes32 PAXOS_USDG_PYUSD_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDG,  PAXOS_USDG_PYUSD);

        SLLHelpers.setRateLimitData({
            key        : PAXOS_USDC_PYUSD_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 50_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : PAXOS_PYUSD_USDC_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 200_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : PAXOS_PYUSD_USDG_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 50_000_000e6 / uint256(1 days),
            decimals   : 6
        });
        SLLHelpers.setRateLimitData({
            key        : PAXOS_USDG_PYUSD_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 5_000_000e6,
            slope      : 100_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // 8. Onboard Morpho v2 USDT Vault
        _setUpNewMorphoVaultV2({
            vault_          : MORPHO_VAULT_V2_USDT,
            name            : "Spark Blue-Chip USDT",
            symbol          : "spUSDTbc",
            sllDepositMax   : 50_000_000e6,
            sllDepositSlope : 1_000_000_000e6 / uint256(1 days)
        });
    }

}
