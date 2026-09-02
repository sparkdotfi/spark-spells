// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { EngineFlags } from "../../AaveV3PayloadBase.sol";

import { SparkPayloadEthereum, IEngine } from "../../SparkPayloadEthereum.sol";

/**
 * @title  September 10, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Deprecate LBTC as Collateral.
 *         - Update USDT Interest Rate Model.
 *         Spark Liquidity Layer:
 *         - Offboard Unused Integrations.
 *         - Onboard the Sentora RLUSD Morpho Vaults V2 Instance.
 * Forum:  https://forum.skyeco.com/t/september-10-2026-proposed-changes-to-spark-for-upcoming-spell/28208
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xce102fe51d0f9dffa64c47df88974e52899ce5347375854adfe3547225489421
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x95329a02677772384f4d2bad196de1f2b0fe6b83a06ab61fe634fb07643dcb86
 */
contract SparkEthereum_20260910 is SparkPayloadEthereum {

    address internal constant NEW_USDT_IRM        = 0x4FA65B096681bD6FeecF78e5D83096bf4A5762A0;
    address internal constant SENTORA_RLUSD_VAULT = 0xFC8C624B6080a0a780583799f2A862DE936F6E22;

    constructor() {
        // PAYLOAD_GNOSIS = 0x2222222222222222222222222222222222222222;
    }

    function collateralsUpdates()
        public view override returns (IEngine.CollateralUpdate[] memory)
    {
        // 2. Deprecate LBTC as Collateral.

        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset          : Ethereum.LBTC,
            ltv            : 0,
            liqThreshold   : EngineFlags.KEEP_CURRENT,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        MainnetController almController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        // 1. Offboard unused Spark Liquidity Layer integrations (34 rate limits set to zero).

        bytes32 erc4626DepositKey  = almController.LIMIT_4626_DEPOSIT();
        bytes32 erc4626WithdrawKey = almController.LIMIT_4626_WITHDRAW();
        bytes32 aaveDepositKey     = almController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey    = almController.LIMIT_AAVE_WITHDRAW();
        bytes32 mapleRedeemKey     = almController.LIMIT_MAPLE_REDEEM();
        bytes32 curveDepositKey    = almController.LIMIT_CURVE_DEPOSIT();
        bytes32 curveWithdrawKey   = almController.LIMIT_CURVE_WITHDRAW();
        bytes32 curveSwapKey       = almController.LIMIT_CURVE_SWAP();
        bytes32 transferKey        = almController.LIMIT_ASSET_TRANSFER();

        // Deactivate Morpho v1 DAI vault.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.MORPHO_VAULT_DAI_1), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.MORPHO_VAULT_DAI_1), 0, 0);

        // Deactivate Morpho v1 USDS vault.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.MORPHO_VAULT_USDS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.MORPHO_VAULT_USDS), 0, 0);

        // Deactivate Aave Core USDe.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(aaveDepositKey,  Ethereum.ATOKEN_CORE_USDE), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Ethereum.ATOKEN_CORE_USDE), 0, 0);

        // Deactivate Ethena.
        rateLimits.setRateLimitData(almController.LIMIT_USDE_MINT(),      0, 0);
        rateLimits.setRateLimitData(almController.LIMIT_USDE_BURN(),      0, 0);
        rateLimits.setRateLimitData(almController.LIMIT_SUSDE_COOLDOWN(), 0, 0);

        // Deactivate Maple syrupUSDT.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.SYRUP_USDT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.SYRUP_USDT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(mapleRedeemKey,     Ethereum.SYRUP_USDT), 0, 0);

        // Deactivate Maple syrupUSDC.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626DepositKey,  Ethereum.SYRUP_USDC), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(erc4626WithdrawKey, Ethereum.SYRUP_USDC), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(mapleRedeemKey,     Ethereum.SYRUP_USDC), 0, 0);

        // Deactivate Curve PYUSD/USDS.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveDepositKey,  Ethereum.CURVE_PYUSDUSDS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveWithdrawKey, Ethereum.CURVE_PYUSDUSDS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveSwapKey,     Ethereum.CURVE_PYUSDUSDS), 0, 0);

        // Deactivate Curve PYUSD/USDC.
        // Note: the deposit and withdraw limits were never configured, so only the swap leg
        //       needs action.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveSwapKey, Ethereum.CURVE_PYUSDUSDC), 0, 0);

        // Deactivate Curve sUSDS/USDT.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveDepositKey,  Ethereum.CURVE_SUSDSUSDT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveWithdrawKey, Ethereum.CURVE_SUSDSUSDT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveSwapKey,     Ethereum.CURVE_SUSDSUSDT), 0, 0);

        // Deactivate Curve USDC/USDT.
        // Note: the deposit and withdraw limits were zeroed on 2025-04-21, so only the swap
        //       leg needs action.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveSwapKey, Ethereum.CURVE_USDCUSDT), 0, 0);

        // Deactivate Curve weETH/WETH-ng.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(curveSwapKey, Ethereum.CURVE_WEETHWETHNG), 0, 0);

        // Deactivate Superstate USTB and USCC.
        // Note: the redemption legs are self-transfers — LIMIT_ASSET_TRANSFER(asset, asset) —
        //       used to trigger burn-on-transfer redemption.
        rateLimits.setRateLimitData(almController.LIMIT_SUPERSTATE_SUBSCRIBE(), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USTB, Ethereum.USTB), 0, 0);
        // Note: LIMIT_SUPERSTATE_REDEEM is not declared by the deployed v1.10.0 controller.
        //       The dormant storage entry is zeroed defensively so a future controller
        //       reintroducing that constant cannot inherit a live unlimited limit.
        rateLimits.setRateLimitData(keccak256("LIMIT_SUPERSTATE_REDEEM"), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, Ethereum.USCC_DEPOSIT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USCC, Ethereum.USCC),         0, 0);

        // Deactivate B2C2 OTC.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC,  Ethereum.B2C2_DEPOSIT_ADDRESS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT,  Ethereum.B2C2_DEPOSIT_ADDRESS), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.PYUSD, Ethereum.B2C2_DEPOSIT_ADDRESS), 0, 0);

        // Deactivate the Anchorage USDT and USAT legs.
        // Note: the Anchorage USDC leg is actively used and stays untouched.
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT), 0, 0);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USAT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT), 0, 0);

        // 4. Update the USDT Interest Rate Model.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, NEW_USDT_IRM);

        // 5. Onboard the Sentora RLUSD Morpho Vaults V2 instance.
        _configureERC4626Vault({
            controller      : Ethereum.ALM_CONTROLLER,
            vault           : SENTORA_RLUSD_VAULT,
            depositMax      : 10_000_000e18,
            depositSlope    : 100_000_000e18 / uint256(1 days),
            maxExchangeRate : 3
        });
    }

}
