// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }                       from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { SparkPayloadEthereum, IEngine, EngineFlags, SLLHelpers } from "../../SparkPayloadEthereum.sol";

/**
 * @title  September 4, 2025 Spark Ethereum Proposal
 * @notice Spark USDS Morpho Vault:
 *         - Onboard November Ethena PTs
 *         Spark USDC Morpho Vault:
 *         - Create Vault and Onboard Assets
 *         Spark Liquidity Layer:
 *         - Onboard Spark USDC Morpho Vault
 *         - Onboard Aave aUSDe
 *         - Increase Curve Swap Rate Limits
 *         - Increase SparkLend spUSDt and spPYUSD Rate Limits
 *         Spark Treasury:
 *         - Transfer BUIDL to Grove
 *         - Withdraw USDS and DAI Reserves from SparkLend
 *         - Transfer USDS to Spark Foundation
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/september-4-2025-proposed-changes-to-spark-for-upcoming-spell/27102
 * Vote:   
 */
contract SparkEthereum_20250904 is SparkPayloadEthereum {

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;
    address internal constant PT_SUSDE_27NOV2025            = 0xe6A934089BBEe34F832060CE98848359883749B3;
    address internal constant PT_SUSDE_27NOV2025_PRICE_FEED = 0xd46F66D7Fc5aD6f54b9B62D36B9A4d99f3Cca451;
    address internal constant WSTETH_PRICE_FEED             = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

    address internal constant CURVE_PYUSDUSDC = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address internal constant USDE_ATOKEN     = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;

    address internal constant GROVE_ALM_PROXY  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant SPARK_FOUNDATION = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;

    uint256 internal constant USDS_AMOUNT_TO_SPARK_FOUNDATION = 800_000e18;

    function _postExecute() internal override {

        MarketParams[] memory markets = new MarketParams[](2);
        uint256[] memory caps = new uint256[](2);

        markets[0] = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.CBBTC,
            oracle:          CBBTC_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        caps[0] = 500_000_000e6;

        markets[1] = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.WSTETH,
            oracle:          WSTETH_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        caps[1] = 500_000_000e6;

        _setupNewMorphoVault({
            asset:           Ethereum.USDC,
            name:            "Spark Blue Chip USDC Vault",
            symbol:          "sparkUSDCbc",
            markets:         markets,
            caps:            caps,
            initialDeposit:  1e6,
            sllDepositMax:   50_000_000e6,
            sllDepositSlope: 100_000_000e6 / uint256(1 days)
        });

        // Onboard November Ethena PTs

        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDE_27NOV2025,
                oracle:          PT_USDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SUSDE_27NOV2025,
                oracle:          PT_SUSDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );

        // Onboard Aave aUSDe

        _configureAaveToken(USDE_ATOKEN, 250_000_000e18, 100_000_000e18 / uint256(1 days));

        // Increase Curve Swap Rate Limits

        _configureCurvePool({
            controller:    Ethereum.ALM_CONTROLLER,
            pool:          Ethereum.CURVE_SUSDSUSDT,
            maxSlippage:   0.9975e18,
            swapMax:       5_000_000e18,
            swapSlope:     100_000_000e18 / uint256(1 days),
            depositMax:    0,
            depositSlope:  0,
            withdrawMax:   0,
            withdrawSlope: 0
        });
        _configureCurvePool({
            controller:    Ethereum.ALM_CONTROLLER,
            pool:          CURVE_PYUSDUSDC,
            maxSlippage:   0.9990e18,
            swapMax:       5_000_000e18,
            swapSlope:     100_000_000e18 / uint256(1 days),
            depositMax:    0,
            depositSlope:  0,
            withdrawMax:   0,
            withdrawSlope: 0
        });

        // Increase SparkLend spUSDt and spPYUSD Rate Limits

        _configureAaveToken(Ethereum.USDT_SPTOKEN,  100_000_000e6, 100_000_000e6 / uint256(1 days));
        _configureAaveToken(Ethereum.PYUSD_SPTOKEN, 100_000_000e6, 100_000_000e6 / uint256(1 days));

        // Transfer BUIDLI to Grove

        _transferAssetFromAlmProxy(
            Ethereum.BUIDLI,
            GROVE_ALM_PROXY,
            IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY)
        );

        // Withdraw USDS and DAI Reserves from SparkLend

        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // Transfer USDS to Spark Foundation

        IERC20(Ethereum.USDS).transfer(SPARK_FOUNDATION, USDS_AMOUNT_TO_SPARK_FOUNDATION);
    }

}
