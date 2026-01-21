// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { AllocatorBuffer } from 'dss-allocator/src/AllocatorBuffer.sol';
import { AllocatorVault }  from 'dss-allocator/src/AllocatorVault.sol';

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 29, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Savings - Increase spUSDT Supply Cap
 *         SparkLend:
 *         - Deprecate tBTC Phase 1
 *         - Deprecate ezETH Phase 1
 *         - Deprecate rsETH (Phase 1)
 *         Spark Liquidity Layer:
 *         - Upgrade ALM Controller to v1.9.0
 *         - Onboard Uniswap v4 PYUSD/USDS Pool
 *         - Onboard Uniswap v4 USDT/USDS Pool
 *         Spark Treasury:
 *         - Spark Foundation Grant for February 2026
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-29-2026-proposed-changes/27620
 * Vote:   
 */
contract SparkEthereum_20260129 is SparkPayloadEthereum {

    using SLLHelpers for address;

    ISparkVaultV2Like internal constant spUsdt = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

    address internal constant NEW_ALM_CONTROLLER = 0xc9ff605003A1b389980f650e1aEFA1ef25C8eE32;

    bytes32 internal constant PYUSD_USDS_POOL_ID = 0xe63e32b2ae40601662f760d6bf5d771057324fbd97784fe1d3717069f7b75d45;
    bytes32 internal constant USDT_USDS_POOL_ID  = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;

    constructor() {
        // PAYLOAD_GNOSIS = 
    }

    function _postExecute() internal override {
        // Increase spUSDT Supply Cap
        spUsdt.setDepositCap(2_000_000_000e6);

        // Upgrade Controller to v1.9
        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS);
        _migrateMaxExchangeRate(Ethereum.SUSDS);
        _migrateMaxExchangeRate(Ethereum.FLUID_SUSDS);
        _migrateMaxExchangeRate(Ethereum.SUSDE);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDC);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDT);
        _migrateMaxExchangeRate(Ethereum.ARKIS_VAULT);

        _migrateMaxSlippage(Ethereum.CURVE_SUSDSUSDT);
        _migrateMaxSlippage(Ethereum.CURVE_PYUSDUSDC);
        _migrateMaxSlippage(Ethereum.CURVE_USDCUSDT);
        _migrateMaxSlippage(Ethereum.CURVE_PYUSDUSDS);

        _migrateMaxSlippage(Ethereum.ATOKEN_CORE_USDC);
        _migrateMaxSlippage(Ethereum.ATOKEN_CORE_USDE);
        _migrateMaxSlippage(Ethereum.ATOKEN_CORE_USDS);
        _migrateMaxSlippage(Ethereum.ATOKEN_CORE_USDT);
        _migrateMaxSlippage(Ethereum.ATOKEN_PRIME_USDS);

        _migrateMaxSlippage(SparkLend.DAI_SPTOKEN);
        _migrateMaxSlippage(SparkLend.USDC_SPTOKEN);
        _migrateMaxSlippage(SparkLend.USDS_SPTOKEN);
        _migrateMaxSlippage(SparkLend.USDT_SPTOKEN);
        _migrateMaxSlippage(SparkLend.PYUSD_SPTOKEN);
        _migrateMaxSlippage(SparkLend.WETH_SPTOKEN);

        _migrateMaxSlippage(Ethereum.CURVE_WEETHWETHNG);

        // Deprecate tBTC Phase 1
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.TBTC, 99_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(Ethereum.TBTC, true);

        // Deprecate ezETH Phase 1
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(Ethereum.EZETH, true);

        // Deprecate rsETH (Phase 1)
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(Ethereum.RSETH, true);

        // Onboard Uniswap v4 PYUSD/USDS Pool
        SLLHelpers.configureUniswapV4Pool({
            controller     : NEW_ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : PYUSD_USDS_POOL_ID,
            maxSlippage    : 0.999e18,
            tickLower      : 276_314,
            tickUpper      : 276_334,
            maxTickSpacing : 10,
            depositMax     : 10_000_000e18,
            depositSlope   : 100_000_000e18 / uint256(1 days),
            withdrawMax    : 50_000_000e18,
            withdrawSlope  : 200_000_000e18 / uint256(1 days),
            swapMax        : 5_000_000e18,
            swapSlope      : 50_000_000e18 / uint256(1 days)
        });

        // Onboard Uniswap v4 USDT/USDS Pool
        SLLHelpers.configureUniswapV4Pool({
            controller     : NEW_ALM_CONTROLLER,
            rateLimits     : Ethereum.ALM_RATE_LIMITS,
            poolId         : USDT_USDS_POOL_ID,
            maxSlippage    : 0.998e18,
            tickLower      : 276_304,
            tickUpper      : 276_344,
            maxTickSpacing : 10,
            depositMax     : 5_000_000e18,
            depositSlope   : 50_000_000e18 / uint256(1 days),
            withdrawMax    : 50_000_000e18,
            withdrawSlope  : 200_000_000e18 / uint256(1 days),
            swapMax        : 5_000_000e18,
            swapSlope      : 50_000_000e18 / uint256(1 days)
        });

        // Spark Foundation Grant for February 2026
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG, FOUNDATION_GRANT_AMOUNT);
    }

    function _migrateMaxExchangeRate(address vault) internal {
        uint256 oldMaxExchangeRate = MainnetController(Ethereum.ALM_CONTROLLER).maxExchangeRates(vault);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(vault, 1, 10);

        require(
            MainnetController(NEW_ALM_CONTROLLER).maxExchangeRates(vault) == oldMaxExchangeRate,
            "Max exchange rate mismatch"
        );
    }

    function _migrateMaxSlippage(address pool) internal {
        uint256 oldMaxSlippage = MainnetController(Ethereum.ALM_CONTROLLER).maxSlippages(pool);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(pool, oldMaxSlippage);
    }

}
