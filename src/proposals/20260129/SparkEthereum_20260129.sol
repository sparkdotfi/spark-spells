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
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-29-2026-proposed-changes/27620
 * Vote:   
 */
contract SparkEthereum_20260129 is SparkPayloadEthereum {

    using SLLHelpers for address;

    ISparkVaultV2Like internal constant spUsdt = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

    address internal constant NEW_ALM_CONTROLLER = 0xE43c41356CbBa9449fE6CF27c6182F62C4FB3fE9;
    address internal constant USDG               = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;

    bytes32 internal constant PYUSD_USDS_POOL_ID = 0xe63e32b2ae40601662f760d6bf5d771057324fbd97784fe1d3717069f7b75d45;
    bytes32 internal constant USDT_USDS_POOL_ID  = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;

    constructor() {
        // PAYLOAD_GNOSIS = 
    }

    function _postExecute() internal override {
        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

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

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDC,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDE,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDS,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDT,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_PRIME_USDS, 0.99999e18);

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

        // Onboard with Paxos
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                address(0xdeadbeef)
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                address(0xdeadbeef)
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            200_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                address(0xdeadbeef1)
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                USDG,
                address(0xdeadbeef)
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e6,
            100_000_000e6 / uint256(1 days),
            6
        );

        // Onboard Uniswap v4 PYUSD/USDS Pool
        MainnetController(NEW_ALM_CONTROLLER).setUniswapV4TickLimits(PYUSD_USDS_POOL_ID, 276_314, 276_334, 10);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(address(uint160(uint256(PYUSD_USDS_POOL_ID))), 0.999e18);
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_DEPOSIT(),
                    PYUSD_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            10_000_000e18,
            100_000_000e18 / uint256(1 days),
            18
        );
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_WITHDRAW(),
                    PYUSD_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            50_000_000e18,
            200_000_000e18 / uint256(1 days),
            18
        );
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_SWAP(),
                    PYUSD_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e18,
            50_000_000e18 / uint256(1 days),
            18
        );

        // Onboard Uniswap v4 USDT/USDS Pool
        MainnetController(NEW_ALM_CONTROLLER).setUniswapV4TickLimits(USDT_USDS_POOL_ID, 276_304, 276_344, 10);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(address(uint160(uint256(USDT_USDS_POOL_ID))), 0.998e18);
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_DEPOSIT(),
                    USDT_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e18,
            50_000_000e18 / uint256(1 days),
            18
        );
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_WITHDRAW(),
                    USDT_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            50_000_000e18,
            200_000_000e18 / uint256(1 days),
            18
        );
        SLLHelpers.setRateLimitData(
            keccak256(
                abi.encode(
                    MainnetController(NEW_ALM_CONTROLLER).LIMIT_UNISWAP_V4_SWAP(),
                    USDT_USDS_POOL_ID
                )
            ),
            Ethereum.ALM_RATE_LIMITS,
            5_000_000e18,
            50_000_000e18 / uint256(1 days),
            18
        );
    }

}
