// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
           - Onboard with Binance for Trading Functionality
           - Onboard with Paxos
           - Onboard with Native Markets
           Spark USDS Morpho Vault - Update Vault Roles
           Spark Blue Chip USDC Morpho Vault - Update Vault Roles
           Spark Savings:
           - Increase spUSDC Deposit Cap
           - Increase spETH Deposit Cap
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20251211 is SparkPayloadEthereum {

    address internal constant PAXOS_PYUSD_DEPOSIT         = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant PAXOS_USDC_DEPOSIT          = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant NATIVE_MARKETS_USDC_DEPOSIT = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG     = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG    = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant BINANCE_EXCHANGE   = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant BINANCE_OTC_BUFFER = 0xaC348dbb93776e64462dF68AD9edE022e52C233b;

    constructor() {
    }

    function _postExecute() internal override {
        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // Onboard with Binance
        IOtcBuffer(BINANCE_OTC_BUFFER).approve(Ethereum.USDC, type(uint256).max);
        IOtcBuffer(BINANCE_OTC_BUFFER).approve(Ethereum.USDT, type(uint256).max);

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_OTC_SWAP(),
                BINANCE_EXCHANGE
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            5_000_000e6 / uint256(1 days),
            6
        );

        MainnetController(Ethereum.MainnetController).setOTCBuffer(BINANCE_EXCHANGE,  BINANCE_OTC_BUFFER);
        MainnetController(Ethereum.MainnetController).setMaxSlippage(BINANCE,         0.9998e18);
        MainnetController(Ethereum.MainnetController).setOTCRechargeRate(BINANCE,     5_000_000e6 / uint256(1 days));
        MainnetController(Ethereum.MainnetController).setOTCWhitelistedAsset(BINANCE, Ethereum.USDC, true);
        MainnetController(Ethereum.MainnetController).setOTCWhitelistedAsset(BINANCE, Ethereum.USDT, true);

        // Onboard with Paxos
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                PAXOS_PYUSD_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                PAXOS_USDC_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );

        // Onboard with Native Markets
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                NATIVE_MARKETS_USDC_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            10_000_000e6 / uint256(1 days),
            6
        );

        // Spark USDS Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).setCurator(SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).submitGuardian(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).submitTimelock(10 days);

        // Spark Blue Chip USDC Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).setCurator(SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).submitGuardian(SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).submitTimelock(10 days);

        // Increase Vault Deposit Caps
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).setDepositCap(1_000_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).setDepositCap(250_000e18);
    }

}
