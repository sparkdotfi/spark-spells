// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { ReserveConfiguration } from "lib/sparklend-v1-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { OTCBuffer }         from "spark-alm-controller/src/OTCBuffer.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

/**
 * @title  June 4, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Update Cap Automator Parameters.
 *         - Update Parameters for Deprecated Assets.
 *         Spark Liquidity Layer:
 *         - Onboard with Binance.
 *         Spark Treasury:
 *         - Transfer Excess USDS from SubDAO Proxy for SPK Buybacks.
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20260604 is SparkPayloadEthereum {

    uint256 internal constant SPK_BUYBACKS_AMOUNT = 326_945e18;

    address internal constant BINANCE_EXCHANGE   = 0x6666666666666666666666666666666666666666;
    address internal constant BINANCE_OTC_BUFFER = 0x1851c64BBfad132CBE75481f1690C381288ea492;

    // function _preExecute() internal override {
    //     LISTING_ENGINE.POOL_CONFIGURATOR().setEModeCategory({
    //         categoryId:           3,
    //         ltv:                  1,
    //         liquidationThreshold: 1,
    //         liquidationBonus:     101_00,
    //         oracle:               address(0),  // No oracle override
    //         label:                'BTC'
    //     });
    // }

    function collateralsUpdates()
        public view override returns (IEngine.CollateralUpdate[] memory)
    {
        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](4);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset          : Ethereum.RSETH,
            ltv            : 0,
            liqThreshold   : 70_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });
        collateralUpdates[1] = IEngine.CollateralUpdate({
            asset          : Ethereum.EZETH,
            ltv            : 0,
            liqThreshold   : 70_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });
        collateralUpdates[2] = IEngine.CollateralUpdate({
            asset          : Ethereum.TBTC,
            ltv            : 0,
            liqThreshold   : 70_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });
        collateralUpdates[3] = IEngine.CollateralUpdate({
            asset          : Ethereum.RETH,
            ltv            : EngineFlags.KEEP_CURRENT,
            liqThreshold   : 70_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        // 3. Update Cap Automator Parameters
        ICapAutomator capAutomator = ICapAutomator(SparkLend.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.WETH,
            max              : ReserveConfiguration.MAX_VALID_SUPPLY_CAP,
            gap              : 100_000,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.WETH,
            max              : ReserveConfiguration.MAX_VALID_SUPPLY_CAP,
            gap              : 10_000,
            increaseCooldown : 4 hours
        });

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.WSTETH,
            max              : ReserveConfiguration.MAX_VALID_SUPPLY_CAP,
            gap              : 50_000,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.WSTETH,
            max              : 1,
            gap              : 1,
            increaseCooldown : 0
        });

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.WEETH,
            max              : 500_000,
            gap              : 10_000,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.WEETH,
            max              : 1,
            gap              : 1,
            increaseCooldown : 0
        });

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.WBTC,
            max              : 50_000,
            gap              : 500,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.WBTC,
            max              : 50_000,
            gap              : 100,
            increaseCooldown : 4 hours
        });

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.CBBTC,
            max              : 50_000,
            gap              : 500,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.CBBTC,
            max              : 50_000,
            gap              : 100,
            increaseCooldown : 4 hours
        });

        capAutomator.setSupplyCapConfig({
            asset            : Ethereum.LBTC,
            max              : 10_000,
            gap              : 200,
            increaseCooldown : 4 hours
        });
        capAutomator.setBorrowCapConfig({
            asset            : Ethereum.LBTC,
            max              : 1,
            gap              : 1,
            increaseCooldown : 0
        });

        // 7. Onboard with Binance
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);
        IRateLimits       rateLimits        = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        OTCBuffer otcBuffer = OTCBuffer(BINANCE_OTC_BUFFER);

        otcBuffer.approve(Ethereum.USDT, type(uint256).max);
        otcBuffer.approve(Ethereum.USDC, type(uint256).max);

        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_OTC_SWAP(),
            BINANCE_EXCHANGE
        );

        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        mainnetController.setMaxSlippage(BINANCE_EXCHANGE,     0.9995e18);
        mainnetController.setOTCBuffer(BINANCE_EXCHANGE,       address(otcBuffer));
        mainnetController.setOTCRechargeRate(BINANCE_EXCHANGE, uint256(1_000_000e18) / 1 days);

        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDT, true);
        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDC, true);

        // 9. Transfer Excess USDS from SubDAO Proxy for SPK Buybacks
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);
    }

}
