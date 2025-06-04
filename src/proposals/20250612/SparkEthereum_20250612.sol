// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { AllocatorBuffer } from 'dss-allocator/src/AllocatorBuffer.sol';
import { AllocatorVault }  from 'dss-allocator/src/AllocatorVault.sol';

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, IEngine, EngineFlags, SLLHelpers } from "../../SparkPayloadEthereum.sol";

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

interface IMorpho {
    function setFee(uint256 newFee) external;
    function setFeeRecipient(address newFeeRecipient) external;
}

/**
 * @title  June 12, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard Morpho Spark DAI Vault
 *         - Add SLL to Vault Allocator Role
 *         - Update syrupUSDC Rate Limit
 *         SparkLend:
 *         - Update ezETH Parameters
 *         Spark DAI Morpho Vault:
 *         - Offboard PT-eUSDE-29MAY2025/DAI
 *         - Offboard PT-SUSDE-29MAY2025/DAI
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/june-12-2025-proposed-changes-to-spark-for-upcoming-spell/26559
 * Vote:   TODO
 */
contract SparkEthereum_20250612 is SparkPayloadEthereum {

    uint256 internal constant MORPHO_SPARK_DAI_VAULT_FEE = 0.1e18;

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant SYRUP_USDC                    = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    constructor() {
        // PAYLOAD_BASE = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;
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
    
        IMorpho(Ethereum.MORPHO_VAULT_DAI_1).setFeeRecipient(Ethereum.SPARK_PROXY);
        IMorpho(Ethereum.MORPHO_VAULT_DAI_1).setFee(MORPHO_SPARK_DAI_VAULT_FEE);
    
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
    }

}
