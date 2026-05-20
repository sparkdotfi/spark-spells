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

import { IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

interface IALMProxyLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

interface ISparkVaultV2Like {

    function SETTER_ROLE() external view returns (bytes32);

    function revokeRole(bytes32 role, address account) external;

    function grantRole(bytes32 role, address account) external;

}

/**
 * @title  June 4, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Update Cap Automator Parameters.
 *         - Update Parameters for Deprecated Assets.
 *         - Increase USDC and USDT Reserve Factors.
 *         Spark Liquidity Layer:
 *         - Onboard with Binance.
 *         - Update ALM Proxy Freezable.
 *         Spark Treasury:
 *         - Transfer Excess USDS from SubDAO Proxy for SPK Buybacks.
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20260604 is SparkPayloadEthereum {

    uint256 internal constant SPK_BUYBACKS_AMOUNT = 663_354e18;

    address internal constant BINANCE_EXCHANGE   = 0x6666666666666666666666666666666666666666;
    address internal constant BINANCE_OTC_BUFFER = 0x1851c64BBfad132CBE75481f1690C381288ea492;

    address internal constant NEW_ALM_PROXY_FREEZABLE = 0xe5c6318456a7Cb6f74f93B4eee4616dB5fcef699;

    bytes32 internal constant USDT_USDS_POOL_ID = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;

    constructor() {
        // PAYLOAD_AVALANCHE = 0x4A71f81C6109230932978bAB7CA746f0be0C4580;
        // PAYLOAD_BASE      = 0x4A71f81C6109230932978bAB7CA746f0be0C4580;
    }

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
            max              : ReserveConfiguration.MAX_VALID_BORROW_CAP,
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

        // 5. Increase USDC and USDT Reserve Factors
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDC, 10_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDT, 10_00);

        // 6. Update Rate Limits
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            250_000_000e6 / uint256(1 days),
            6
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeBytes32Key(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_UNISWAP_V4_SWAP(),
                USDT_USDS_POOL_ID
            ),
            Ethereum.ALM_RATE_LIMITS,
            25_000_000e18,
            250_000_000e18 / uint256(1 days),
            18
        );

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

        rateLimits.setRateLimitData(key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        mainnetController.setMaxSlippage(BINANCE_EXCHANGE,     0.998e18);
        mainnetController.setOTCBuffer(BINANCE_EXCHANGE,       address(otcBuffer));
        mainnetController.setOTCRechargeRate(BINANCE_EXCHANGE, uint256(50_000e18) / 1 days);

        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDT, true);
        mainnetController.setOTCWhitelistedAsset(BINANCE_EXCHANGE, Ethereum.USDC, true);

        // 8. Update ALM Proxy Freezable

        // Grant ALLOCATOR_ROLE Role for Relayer 1 and 2 on NEW_ALM_PROXY_FREEZABLE and FREEZER_ROLE role to the ALM_FREEZER_MULTISIG
        IALMProxyLike proxy = IALMProxyLike(NEW_ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Ethereum.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   Ethereum.ALM_FREEZER_MULTISIG);

        // Spark Savings - Update Setter Role to New ALM Proxy Freezable for spUSDC, spUSDT, spETH
        ISparkVaultV2Like spUSDCvault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like spUSDTvault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like spETHvault   = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);
        ISparkVaultV2Like spPYUSDvault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPPYUSD);

        spUSDCvault.revokeRole(spUSDCvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);
        spUSDCvault.grantRole(spUSDCvault.SETTER_ROLE(),  NEW_ALM_PROXY_FREEZABLE);

        spUSDTvault.revokeRole(spUSDTvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);
        spUSDTvault.grantRole(spUSDTvault.SETTER_ROLE(),  NEW_ALM_PROXY_FREEZABLE);

        spETHvault.revokeRole(spETHvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);
        spETHvault.grantRole(spETHvault.SETTER_ROLE(),  NEW_ALM_PROXY_FREEZABLE);

        spPYUSDvault.revokeRole(spPYUSDvault.SETTER_ROLE(), Ethereum.ALM_PROXY_FREEZABLE);
        spPYUSDvault.grantRole(spPYUSDvault.SETTER_ROLE(),  NEW_ALM_PROXY_FREEZABLE);

        // Spark USDC Morpho Vault - Update Allocator Role to New ALM Proxy Freezable
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).setIsAllocator(Ethereum.ALM_PROXY_FREEZABLE, false);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).setIsAllocator(NEW_ALM_PROXY_FREEZABLE,      true);

        // Spark USDS Morpho Vault - Update Allocator Role to New ALM Proxy Freezable
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).setIsAllocator(Ethereum.ALM_PROXY_FREEZABLE, false);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).setIsAllocator(NEW_ALM_PROXY_FREEZABLE,      true);

        // 9. Transfer Excess USDS from SubDAO Proxy for SPK Buybacks
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, SPK_BUYBACKS_AMOUNT);
    }

}
