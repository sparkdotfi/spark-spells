// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SLLHelpers, SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  April 09, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Deactivate Fluid sUSDS, Aave Prime USDS, Aave Core USDS, Aave Core USDC
 *         - Configure Aave Core USDT, SparkLend USDT, SparkLend ETH
 *         - Configure Maple syrupUSDT
 *         - Configure Morpho Blue Chip USDT Vault
 *         - Configure Curve weETH/WETH-ng and sUSDS/USDT
 *         - Update Anchorage USDT and USAT transfer asset limits
 *         Spark Savings:
 *         - Increase spUSDT, spUSDC, spETH deposit caps
 * Forum:  https://forum.skyeco.com/t/april-9-2026-proposed-changes-to-spark-for-upcoming-spell/27804
 * Vote:
 *
 */
contract SparkEthereum_20260409 is SparkPayloadEthereum {

    address internal constant ANCHORAGE_USAT_USDT = 0x49506C3Aa028693458d6eE816b2EC28522946872;

    ISparkVaultV2Like internal constant spEth  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);
    ISparkVaultV2Like internal constant spUsdc = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
    ISparkVaultV2Like internal constant spUsdt = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

    MainnetController almController = MainnetController(Ethereum.ALM_CONTROLLER);

    IRateLimits rateLimits = IRateLimits(Ethereum.ALM_RATE_LIMITS);

    constructor() {
        // PAYLOAD_ARBITRUM = ; // @TODO
        // PAYLOAD_BASE     = ; // @TODO
    }

    function _postExecute() internal override {
        // Spark Liquidity Layer - Update Rate Limits

        bytes32 aaveDepositKey     = almController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey    = almController.LIMIT_AAVE_WITHDRAW();
        bytes32 erc4626DepositKey  = almController.LIMIT_4626_DEPOSIT();
        bytes32 erc4626WithdrawKey = almController.LIMIT_4626_WITHDRAW();
        bytes32 mapleRedeemKey     = almController.LIMIT_MAPLE_REDEEM();
        bytes32 transferKey        = almController.LIMIT_ASSET_TRANSFER();

        // 1. Deactivate Fluid sUSDS
        bytes32 FLUID_SUSDS_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.FLUID_SUSDS);
        bytes32 FLUID_SUSDS_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.FLUID_SUSDS);

        IRateLimits(rateLimits).setRateLimitData(FLUID_SUSDS_DEPOSIT_KEY,  0, 0);
        IRateLimits(rateLimits).setRateLimitData(FLUID_SUSDS_WITHDRAW_KEY, 0, 0);

        // 2. Deactivate Aave Prime USDS
        bytes32 ATOKEN_PRIME_USDS_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Ethereum.ATOKEN_PRIME_USDS);
        bytes32 ATOKEN_PRIME_USDS_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Ethereum.ATOKEN_PRIME_USDS);

        IRateLimits(rateLimits).setRateLimitData(ATOKEN_PRIME_USDS_DEPOSIT_KEY,  0, 0);
        IRateLimits(rateLimits).setRateLimitData(ATOKEN_PRIME_USDS_WITHDRAW_KEY, 0, 0);

        // 3. Deactivate Aave Core USDS
        bytes32 ATOKEN_CORE_USDS_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Ethereum.ATOKEN_CORE_USDS);
        bytes32 ATOKEN_CORE_USDS_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Ethereum.ATOKEN_CORE_USDS);

        IRateLimits(rateLimits).setRateLimitData(ATOKEN_CORE_USDS_DEPOSIT_KEY,  0, 0);
        IRateLimits(rateLimits).setRateLimitData(ATOKEN_CORE_USDS_WITHDRAW_KEY, 0, 0);

        // 4. Deactivate Aave Core USDC

        bytes32 ATOKEN_CORE_USDC_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Ethereum.ATOKEN_CORE_USDC);
        bytes32 ATOKEN_CORE_USDC_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Ethereum.ATOKEN_CORE_USDC);

        IRateLimits(rateLimits).setRateLimitData(ATOKEN_CORE_USDC_DEPOSIT_KEY,  0, 0);
        IRateLimits(rateLimits).setRateLimitData(ATOKEN_CORE_USDC_WITHDRAW_KEY, 0, 0);

        // 5. Increase Rate Limit for Aave Core USDT
        _configureAaveToken({
            token        : Ethereum.ATOKEN_CORE_USDT,
            depositMax   : 100_000_000e6,
            depositSlope : 1_000_000_000e6 / uint256(1 days)
        });

        // 6. Increase Rate Limit for SparkLend USDT
        _configureAaveToken({
            token        : SparkLend.USDT_SPTOKEN,
            depositMax   : 500_000_000e6,
            depositSlope : 2_000_000_000e6 / uint256(1 days)
        });

        // 7. Increase Rate Limit for Maple syrupUSDT
        bytes32 SYRUP_USDT_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.SYRUP_USDT);
        bytes32 SYRUP_USDT_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.SYRUP_USDT);
        bytes32 SYRUP_USDT_REDEEM_KEY   = RateLimitHelpers.makeAddressKey(mapleRedeemKey,     Ethereum.SYRUP_USDT);

        SLLHelpers.setRateLimitData({
            key        : SYRUP_USDT_DEPOSIT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 50_000_000e6,
            slope      : 100_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        SLLHelpers.setRateLimitData({
            key        : SYRUP_USDT_WITHDRAW_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : type(uint256).max,
            slope      : 0,
            decimals   : 6
        });

        SLLHelpers.setRateLimitData({
            key        : SYRUP_USDT_REDEEM_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : type(uint256).max,
            slope      : 0,
            decimals   : 6
        });

        // 8. Increase Rate Limit for Spark Blue Chip USDT Morpho Vault
        SLLHelpers.configureERC4626Vault({
            rateLimits    : Ethereum.ALM_RATE_LIMITS,
            vault         : Ethereum.MORPHO_VAULT_V2_USDT,
            depositMax    : 100_000_000e6,
            depositSlope  : 1_000_000_000e6 / uint256(1 days),
            withdrawMax   : type(uint256).max,
            withdrawSlope : 0
        });

        // 9. Increase Rate Limit for SparkLend ETH
        _configureAaveToken({
            token        : SparkLend.WETH_SPTOKEN,
            depositMax   : 50_000e18,
            depositSlope : 250_000e18 / uint256(1 days)
        });

        // 10. Increase Rate Limits for Curve weETH/WETH-ng
        _configureCurvePool({
            controller    : Ethereum.ALM_CONTROLLER,
            pool          : Ethereum.CURVE_WEETHWETHNG,
            maxSlippage   : 0.9975e18,
            swapMax       : 1_000e18,
            swapSlope     : 50_000e18 / uint256(1 days),
            depositMax    : 0,
            depositSlope  : 0,
            withdrawMax   : 0,
            withdrawSlope : 0
        });

        // 11. Increase Rate Limits for Curve sUSDS/USDT
        _configureCurvePool({
            controller    : Ethereum.ALM_CONTROLLER,
            pool          : Ethereum.CURVE_SUSDSUSDT,
            maxSlippage   : 0.9975e18,
            swapMax       : 10_000_000e18,
            swapSlope     : 200_000_000e18 / uint256(1 days),
            depositMax    : 0,
            depositSlope  : 0,
            withdrawMax   : 0,
            withdrawSlope : 0
        });

        // 12. Update Anchorage USDT transfer asset limit
        bytes32 USDT_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT, ANCHORAGE_USAT_USDT);
        bytes32 USAT_KEY = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USAT, ANCHORAGE_USAT_USDT);

        SLLHelpers.setRateLimitData({
            key        : USDT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 50_000_000e6,
            slope      : 250_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // 13. Update Anchorage USAT transfer asset limit

        SLLHelpers.setRateLimitData({
            key        : USAT_KEY,
            rateLimits : Ethereum.ALM_RATE_LIMITS,
            maxAmount  : 50_000_000e6,
            slope      : 250_000_000e6 / uint256(1 days),
            decimals   : 6
        });

        // Spark Savings - Raise Deposit Caps for spUSDC, spUSDT and spETH

        // 1. Increase spUSDC vault deposit cap
        spUsdc.setDepositCap(10_000_000_000e6);

        // 2. Increase spUSDT vault deposit cap
        spUsdt.setDepositCap(10_000_000_000e6);

        // 3. Increase spETH vault deposit cap
        spEth.setDepositCap(1_000_000e18);
    }

}
