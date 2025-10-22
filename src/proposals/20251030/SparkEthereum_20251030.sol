// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  October 30, 2025 Spark Ethereum Proposal
 * @notice SparkLend:
           - Remove Supply and Borrow Caps for Non Collateral Stablecoins (USDC, USDT, PYUSD)
           - Increase cbBTC Supply and Borrow Caps
           - Increase tBTC Supply and Borrow Caps
           - Claim Reserves for USDS and DAI Markets
           Spark Savings:
           - Increase Vault Deposit Caps
           Spark Liquidity Layer:
           - Onboard syrupUSDT
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-16-2025-proposed-changes-to-spark-for-upcoming-spell/27215
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xeea0e2648f55df4e57f8717831a5949f2a35852e32aa0f98a7e16e7ed56268a8
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x95138f104ff84defb64985368f348af4d7500b2641b88b396e37426126f5ce0d
           https://snapshot.box/#/s:sparkfi.eth/proposal/0xab448e3d135620340da30616c0dabaa293f816a9edd4dc009f29b0ffb5bcbad2
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x14300684fb44685ad27270745fa6780e8083f3741de2119b98cf6bb1e44b4617
           https://snapshot.box/#/s:sparkfi.eth/proposal/0xf289dbc26dc0380bfab16a5d6c12b6167d8a47a348891797ea8bc3b752a4ce7a
 */
contract SparkEthereum_20251030 is SparkPayloadEthereum {

    address internal constant PYUSD      = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant SYRUP_USDT = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    constructor() {
        // PAYLOAD_ARBITRUM  = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // PAYLOAD_AVALANCHE = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // PAYLOAD_OPTIMISM  = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // PAYLOAD_UNICHAIN  = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
    }

    function _postExecute() internal override {
        // Remove Supply and Borrow Caps for Non Collateral Stablecoins (USDC, USDT, PYUSD)
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.USDC,  ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.USDT,  ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(PYUSD,          ReserveConfiguration.MAX_VALID_SUPPLY_CAP);

        LISTING_ENGINE.POOL_CONFIGURATOR().setBorrowCap(Ethereum.USDC, ReserveConfiguration.MAX_VALID_BORROW_CAP);
        LISTING_ENGINE.POOL_CONFIGURATOR().setBorrowCap(Ethereum.USDT, ReserveConfiguration.MAX_VALID_BORROW_CAP);
        LISTING_ENGINE.POOL_CONFIGURATOR().setBorrowCap(PYUSD,         ReserveConfiguration.MAX_VALID_BORROW_CAP);

        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.USDC);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.USDT);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeSupplyCapConfig(PYUSD);

        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeBorrowCapConfig(Ethereum.USDC);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeBorrowCapConfig(Ethereum.USDT);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeBorrowCapConfig(PYUSD);

        // Increase cbBTC Supply and Borrow Caps
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.CBBTC,
            max:              20_000,
            gap:              500,
            increaseCooldown: 12 hours
        });

        ICapAutomator(Ethereum.CAP_AUTOMATOR).setBorrowCapConfig({
            asset:            Ethereum.CBBTC,
            max:              10_000,
            gap:              50,
            increaseCooldown: 12 hours
        });

        // Increase tBTC Supply and Borrow Caps
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.TBTC,
            max:              1_000,
            gap:              125,
            increaseCooldown: 12 hours
        });

        ICapAutomator(Ethereum.CAP_AUTOMATOR).setBorrowCapConfig({
            asset:            Ethereum.TBTC,
            max:              900,
            gap:              25,
            increaseCooldown: 12 hours
        });

        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // Increase Vault Deposit Caps
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).setDepositCap(250_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).setDepositCap(250_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).setDepositCap(50_000e18);
    
        // Onboard syrupUSDT
        _configureERC4626Vault({
            vault:        SYRUP_USDT,
            depositMax:   50_000_000e6,
            depositSlope: 10_000_000e6 / uint256(1 days)
        });
        IRateLimits(Ethereum.ALM_RATE_LIMITS).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
                SYRUP_USDT
            )
        );
    }

}
