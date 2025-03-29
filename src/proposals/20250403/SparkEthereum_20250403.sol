// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  April 3, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer: Upgrade ALM Controller
 *                                Onboard BUIDL-I, USTB, JTRSY, syrupUSDC
 *                                Increase USDC rate limit for SparkLend
 *                                Increase Core Rate Limits
 *         SparkLend: Increase USDC Supply/Borrow Caps
 *                    Increase rsETH Supply Caps
 *         Morpho: Ethena PT Supply Cap Adjustments
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell/26155
 *         https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell-2/26203
 * Vote:   https://vote.makerdao.com/polling/QmSwQ6Wc
 *         https://vote.makerdao.com/polling/QmTE29em
 *         https://vote.makerdao.com/polling/QmehvjH9
 *         https://vote.makerdao.com/polling/QmSytTo4
 *         https://vote.makerdao.com/polling/QmZGQhkG
 *         https://vote.makerdao.com/polling/QmWQCbns
 *         TODO
 *         TODO
 *         TODO
 *         TODO
 */
contract SparkEthereum_20250403 is SparkPayloadEthereum {

    address internal constant OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant NEW_ALM_CONTROLLER = 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c;

    address internal constant BUIDL         = 0x6a9DA2D710BB9B700acde7Cb81F10F1fF8C89041;
    address internal constant BUIDL_DEPOSIT = 0xD1917664bE3FdAea377f6E8D5BF043ab5C3b1312;
    address internal constant BUIDL_REDEEM  = 0x8780Dd016171B91E4Df47075dA0a947959C34200;

    address internal constant JTRSY_VAULT = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;

    address internal constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    address internal constant PT_USDE_27MAR2025_PRICE_FEED  = 0xA8ccE51046d760291f77eC1EB98147A75730Dcd5;
    address internal constant PT_USDE_27MAR2025             = 0x8A47b431A7D947c6a3ED6E42d501803615a97EAa;
    address internal constant PT_SUSDE_27MAR2025_PRICE_FEED = 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7;
    address internal constant PT_SUSDE_27MAR2025            = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;

    constructor() {
        PAYLOAD_ARBITRUM = address(0);  // TODO
        PAYLOAD_BASE     = address(0);  // TODO
    }

    function _postExecute() internal override {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );

        _onboardBlackrockBUIDL();
        _onboardSuperstateUSTB();
        _onboardCentrifugeJTRSY();
        _onboardMapleSyrupUSDC();

        _updateSparkLendUSDC();
        _increaseCoreRateLimits();
        _rsETHCapsUpdate();
        _adjustMorphoPTs();
    }

    function _onboardBlackrockBUIDL() private {
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                BUIDL_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 500_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "buidlMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                BUIDL,
                BUIDL_REDEEM
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "buidlBurnLimit",
            6
        );
    }

    function _onboardSuperstateUSTB() private {
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_SUPERSTATE_SUBSCRIBE(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 300_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "ustbMintLimit",
            6
        );
        // Instant liquidity redemption
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_SUPERSTATE_REDEEM(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "ustbBurnLimit",
            6
        );
        // Offchain redemption
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USTB,
                Ethereum.USTB
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "ustbOffchainBurnLimit",
            6
        );
    }

    function _onboardCentrifugeJTRSY() private {
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_7540_DEPOSIT(),
                JTRSY_VAULT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 200_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "jtrsyMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_7540_REDEEM(),
                JTRSY_VAULT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "jtrsyBurnLimit",
            6
        );
    }

    function _onboardMapleSyrupUSDC() private {
        _onboardERC4626Vault({
            vault:        SYRUP_USDC,
            depositMax:   25_000_000e6,
            depositSlope: 5_000_000e6 / uint256(1 days)
        });
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
                SYRUP_USDC
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "syrupUSDCRedeemLimit",
            6
        );
    }

    function _updateSparkLendUSDC() private {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.USDC, max: 1_000_000_000, gap: 150_000_000, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: Ethereum.USDC, max: 950_000_000,   gap: 50_000_000,  increaseCooldown: 12 hours });

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
                Ethereum.USDC_ATOKEN
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            "usdcDepositLimit",
            6
        );
    }

    function _increaseCoreRateLimits() private {
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_USDS_MINT(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 200_000_000e18,
                slope     : 200_000_000e18 / uint256(1 days)
            }),
            "usdsMintLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_USDS_TO_USDC(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 200_000_000e6,
                slope     : 200_000_000e6 / uint256(1 days)
            }),
            "swapUSDSToUSDCLimit",
            6
        );
    }

    function _rsETHCapsUpdate() private {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.RSETH, max: 40_000, gap: 5_000, increaseCooldown: 12 hours });
    }

    function _adjustMorphoPTs() private {
        // Offboard PT-USDE-27MAR2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_27MAR2025,
                oracle:          PT_USDE_27MAR2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            0
        );

        // Offboard PT-SUSDE-27MAR2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_27MAR2025,
                oracle:          PT_SUSDE_27MAR2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            0
        );

        // Raise cap PT-SUSDE-29MAY2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_29MAY2025,
                oracle:          PT_SUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            400_000_000e18
        );
    }

}
