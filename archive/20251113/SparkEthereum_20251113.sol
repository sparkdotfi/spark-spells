// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  November 13, 2025 Spark Ethereum Proposal
 * @notice Spark Treasury:
           - Transfer Share of Ethena Net Profit to Grove
           SparkLend:
           - Deprecate sUSDS and sDAI Collateral
           - Update PYUSD Interest Rate Model
           - Claim USDS and DAI Reserves
           Spark Savings:
           - Increase Deposit Caps for spUSDC, spUSDT, and spETH
           Spark Liquidity Layer:
           - Increase Rate Limits for SparkLend USDC and USDT
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-13-2025-proposed-changes-to-spark-for-upcoming-spell/27354
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x785d3b23e63e3e6b6fb7927ca0bc529b2dc7b58d429102465e4ba8a36bc23fda
           https://snapshot.box/#/s:sparkfi.eth/proposal/0xe697ded18a50e09618c6f34fb89cbb8358d84a4c40602928ae4b44a644b83dcf
           https://snapshot.box/#/s:sparkfi.eth/proposal/0x4c705ab40a35c3c903adb87466bf563b00abc78b1d161034278d2acd74fb7621
 */
contract SparkEthereum_20251113 is SparkPayloadEthereum {

    address internal constant PYUSD_IRM = 0xDF7dedCfd522B1ee8da2c8526f642745800c8035;

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 625_069e18;

    constructor() {
        PAYLOAD_AVALANCHE = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        PAYLOAD_BASE      = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
    }

    function _postExecute() internal override {
        // Transfer Share of Ethena Net Profit to Grove
        IERC20(Ethereum.USDS).transfer(Ethereum.GROVE_SUBDAO_PROXY, GROVE_PAYMENT_AMOUNT);

        // Deprecate sDAI and sUSDS Collateral
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.SDAI,  1);
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.SUSDS, 1);

        ICapAutomator(SparkLend.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.SDAI);
        ICapAutomator(SparkLend.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.SUSDS);

        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Ethereum.SDAI,  0, 80_00, 105_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Ethereum.SUSDS, 0, 80_00, 105_00);

        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // Update PYUSD Interest Rate Model
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.PYUSD, PYUSD_IRM);

        // Increase Rate Limits for SparkLend USDC and USDT
        _configureAaveToken(
            SparkLend.USDC_SPTOKEN,
            100_000_000e6,
            200_000_000e6 / uint256(1 days)
        );
        _configureAaveToken(
            SparkLend.USDT_SPTOKEN,
            100_000_000e6,
            200_000_000e6 / uint256(1 days)
        );

        // Increase Vault Deposit Caps
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).setDepositCap(500_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).setDepositCap(500_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).setDepositCap(100_000e18);
    }

}
