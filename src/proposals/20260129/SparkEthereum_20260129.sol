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
 *         - Onboard with Paxos
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

    address internal constant ARKIS              = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant NEW_ALM_CONTROLLER = 0xE43c41356CbBa9449fE6CF27c6182F62C4FB3fE9;
    address internal constant USDG               = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;

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

        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC, 1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1,   1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS,    1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDS,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.FLUID_SUSDS,          1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDE,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SYRUP_USDC,           1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SYRUP_USDT,           1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(ARKIS,                         1, 10);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDC,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDE,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDS,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDT,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_PRIME_USDS, 0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.CURVE_WEETHWETHNG, 0.9975e18);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.DAI_SPTOKEN,   0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDC_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDS_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDT_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.WETH_SPTOKEN,  0.99999e18);

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

}
