// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  June 12, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard Morpho Spark DAI Vault
 *         - Add SLL to Vault Allocator Role
 *         - Update syrupUSDC Rate Limit
 *         SparkLend:
 *         - Update ezETH Parameters
 *         - Update Stablecoin Market Reserve Factors
 *         Spark DAI Morpho Vault:
 *         - Reduce Supply Cap for Inactive Pools
 *         - Onboard PT-EUSDE-14Aug2025/DAI
 *         - Onboard PT-SUSDE-25Sep2025/DAI
 *         - Update Vault Fee and Fee Recipient
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/june-12-2025-proposed-changes-to-spark-for-upcoming-spell/26559
 * Vote:   https://vote.sky.money/polling/QmQRCn2K
 *         https://vote.sky.money/polling/QmbY2bxz
 *         https://vote.sky.money/polling/Qme3Des6
 *         https://vote.sky.money/polling/QmUa7Au1
 *         https://vote.sky.money/polling/QmTX3KM9
 *         https://vote.sky.money/polling/QmRsqaaC
 *         https://vote.sky.money/polling/QmdyVQok
 *         https://vote.sky.money/polling/QmS3i2S3
 *         https://vote.sky.money/polling/QmSZJpsT
 */
contract SparkEthereum_20250612 is SparkPayloadEthereum {

    uint256 internal constant MORPHO_SPARK_DAI_VAULT_FEE = 0.1e18;

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_EUSDE_14AUG2025            = 0x14Bdc3A3AE09f5518b923b69489CBcAfB238e617;
    address internal constant PT_EUSDE_14AUG2025_PRICE_FEED = 0x4f98667af07f3faB3F7a77E65Fcf48c7335eAA7a;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant PT_SUSDE_25SEP2025            = 0x9F56094C450763769BA0EA9Fe2876070c0fD5F77;
    address internal constant PT_SUSDE_25SEP2025_PRICE_FEED = 0x26394307806F4DD1ea053EC61CFFCa15613a4573;
    address internal constant SYRUP_USDC                    = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    constructor() {
        PAYLOAD_BASE = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
    }

    function _postExecute() internal override {
        _onboardERC4626Vault(
            Ethereum.MORPHO_VAULT_DAI_1,
            200_000_000e18,
            100_000_000e18 / uint256(1 days)
        );

        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).setIsAllocator(
            Ethereum.ALM_RELAYER,
            true
        );

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.EZETH, max: 40_000, gap: 5_000, increaseCooldown: 12 hours });

        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).setFeeRecipient(Ethereum.ALM_PROXY);
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).setFee(MORPHO_SPARK_DAI_VAULT_FEE);

        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.DAI,  10_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDS, 10_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDC, 10_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDT, 10_00);

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
                SYRUP_USDC
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e6,
                slope     : 20_000_000e6 / uint256(1 days)
            }),
            "syrupUSDCDepositLimit",
            6
        );

        // Offboard PT-eUSDE-29MAY2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_29MAY2025,
                oracle:          PT_EUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            0
        );

        // Offboard PT-SUSDE-29MAY2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_29MAY2025,
                oracle:          PT_SUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            0
        );

        // Onboard PT-EUSDE-14Aug2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_14AUG2025,
                oracle:          PT_EUSDE_14AUG2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );

        // Onboard PT-SUSDE-25SEP2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_25SEP2025,
                oracle:          PT_SUSDE_25SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );
    }

}
