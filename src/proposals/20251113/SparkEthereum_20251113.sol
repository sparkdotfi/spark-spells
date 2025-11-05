// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

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
           Spark Savings:
           - Increase Deposit Caps for spUSDC, spUSDT, and spETH
           Spark Liquidity Layer:
           - Increase Rate Limits for SparkLend USDC and USDT
* @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-13-2025-proposed-changes-to-spark-for-upcoming-spell/27354
 * Vote:   
 */
contract SparkEthereum_20251113 is SparkPayloadEthereum {

    address internal constant GROVE_SUBDAO_PROXY = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;
    address internal constant PYUSD              = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant PYUSD_IRM          = 0xDF7dedCfd522B1ee8da2c8526f642745800c8035;

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 625_069e18;

    constructor() {
        // PAYLOAD_AVALANCHE = 0xCF9326e24EBfFBEF22ce1050007A43A3c0B6DB55;
        // PAYLOAD_BASE      = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;
    }

    function _postExecute() internal override {
        // Transfer Share of Ethena Net Profit to Grove
        IERC20(Ethereum.USDS).transfer(GROVE_SUBDAO_PROXY, GROVE_PAYMENT_AMOUNT);

        // Deprecate sDAI and sUSDS Collateral
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.SDAI,  1);
        LISTING_ENGINE.POOL_CONFIGURATOR().setSupplyCap(Ethereum.SUSDS, 1);

        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.SDAI);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).removeSupplyCapConfig(Ethereum.SUSDS);

        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Ethereum.SDAI,  0, 80_00, 105_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Ethereum.SUSDS, 0, 80_00, 105_00);

        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // Update PYUSD Interest Rate Model
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(PYUSD, PYUSD_IRM);

        // Increase Rate Limits for SparkLend USDC and USDT
        _configureAaveToken(
            Ethereum.USDC_SPTOKEN,
            100_000_000e6,
            200_000_000e6 / uint256(1 days)
        );
        _configureAaveToken(
            Ethereum.USDT_SPTOKEN,
            100_000_000e6,
            200_000_000e6 / uint256(1 days)
        );

        // Increase Vault Deposit Caps
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).setDepositCap(500_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).setDepositCap(500_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).setDepositCap(100_000e18);
    }

}
