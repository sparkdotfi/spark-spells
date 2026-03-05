// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IACLManager } from 'aave-v3-core/contracts/interfaces/IACLManager.sol';

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { SLLHelpers, SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

/**
 * @title  March 12, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Upgrade Mainnet Controller to v1.10
 *         SparkLend:
 *         - Upgrade Cap Automators to v1.1
 *         - Add Assets to Killswitch Oracle Mechanism
 *         Spark Treasury:
 *         - Transfer SparkLend DAI and SparkLend USDS from SubDAO Proxy to ALM Proxy
 * Forum:  https://forum.sky.money/t/march-12-2026-proposed-changes-to-spark-for-upcoming-spell/27741
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0xeb2f5f08ec6ab8a2ff5302453ac7383f7519a09cf7e1e56cbb7fc8244f15cfa2
           https://snapshot.org/#/s:sparkfi.eth/proposal/0xdc686a9bc77b44cb323c23dce2cc091ebd34d7876d6e1f4413786f17e0739726
           https://snapshot.org/#/s:sparkfi.eth/proposal/0x9aebbe69e8555d03dc97b55475dac08225e157b3fd475d7a29848b8631627367
           https://snapshot.org/#/s:sparkfi.eth/proposal/0xf8c2f98cb39912a22457522c445c453b5f796f24c1886d1687dc96648ffa4c16
 */
contract SparkEthereum_20260312 is SparkPayloadEthereum {

    using SLLHelpers for address;

    address internal constant MORPHO_VAULT_V2_USDT = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;
    address internal constant NEW_ALM_CONTROLLER   = 0x5c46Fc65855c0C7465a1EA85EEA0B24B601502D3;
    address internal constant NEW_CAP_AUTOMATOR    = 0x4C1341636721b8B687647920B2E9481f3AB1F2eE;

    bytes32 internal constant PYUSD_USDS_POOL_ID = 0xe63e32b2ae40601662f760d6bf5d771057324fbd97784fe1d3717069f7b75d45;
    bytes32 internal constant USDT_USDS_POOL_ID  = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;

    address internal constant CBBTC_BTC_RATIO_ORACLE    = 0x64B157212C21097002920D57322B671b88DFcCBC;
    address internal constant WBTC_BTC_CHAINLINK_ORACLE = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    address internal constant WEETH_ETH_RATIO_ORACLE    = 0x4C805FD3c64B79840d36813Fc90c165bf77bb7E4;
    address internal constant RETH_ETH_RATIO_ORACLE     = 0xd0B378dA552D06B6D3497e4b5ba2A83418f78d06;

    function _postExecute() internal override {
        // 1. Upgrade Controller to v1.10
        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC, 10);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1,   10);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS,    10);
        _migrateMaxExchangeRate(Ethereum.SUSDS,                10);
        _migrateMaxExchangeRate(Ethereum.FLUID_SUSDS,          10);
        _migrateMaxExchangeRate(Ethereum.SUSDE,                10);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDC,           10);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDT,           10);
        _migrateMaxExchangeRate(Ethereum.ARKIS_VAULT,          10);
        _migrateMaxExchangeRate(MORPHO_VAULT_V2_USDT,          1_000_000);

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

        _migrateMaxSlippage(address(uint160(uint256(PYUSD_USDS_POOL_ID))));
        _migrateMaxSlippage(address(uint160(uint256(USDT_USDS_POOL_ID))));

        _migrateUniswapV4TickLimits(PYUSD_USDS_POOL_ID);
        _migrateUniswapV4TickLimits(USDT_USDS_POOL_ID);

        // 2. Upgrade Cap Automators to v1.1
        IACLManager(SparkLend.ACL_MANAGER).removeRiskAdmin(SparkLend.CAP_AUTOMATOR);

        IACLManager(SparkLend.ACL_MANAGER).addRiskAdmin(NEW_CAP_AUTOMATOR);

        address[] memory reserves = IPool(SparkLend.POOL).getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            _migrateCapConfig(reserves[i]);
        }

        // 3. Add Assets to Killswitch Oracle Mechanism
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(CBBTC_BTC_RATIO_ORACLE,    0.95e18);
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(RETH_ETH_RATIO_ORACLE,     0.95e18);
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(WBTC_BTC_CHAINLINK_ORACLE, 0.95e8);
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(WEETH_ETH_RATIO_ORACLE,    0.95e18);

        // 4. Transfer SparkLend DAI and SparkLend USDS from SubDAO Proxy to ALM Proxy
        IERC20(SparkLend.DAI_SPTOKEN).transfer(Ethereum.ALM_PROXY,  IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY));
        IERC20(SparkLend.USDS_SPTOKEN).transfer(Ethereum.ALM_PROXY, IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.SPARK_PROXY));
    }

    function _migrateUniswapV4TickLimits(bytes32 poolId) internal {
        ( int24 tickLower, int24 tickUpper, uint24 maxTickSpacing ) = MainnetController(Ethereum.ALM_CONTROLLER).uniswapV4TickLimits(poolId);

        MainnetController(NEW_ALM_CONTROLLER).setUniswapV4TickLimits(poolId, tickLower, tickUpper, maxTickSpacing);
    }

    function _migrateCapConfig(address asset) internal {
        ( uint48 supplyMax, uint48 supplyGap, uint48 supplyIncreaseCooldown,, ) = ICapAutomator(SparkLend.CAP_AUTOMATOR).supplyCapConfigs(asset);
        ( uint48 borrowMax, uint48 borrowGap, uint48 borrowIncreaseCooldown,, ) = ICapAutomator(SparkLend.CAP_AUTOMATOR).borrowCapConfigs(asset);

        if (supplyMax > 0) ICapAutomator(NEW_CAP_AUTOMATOR).setSupplyCapConfig(asset, supplyMax, supplyGap, supplyIncreaseCooldown);
        if (borrowMax > 0) ICapAutomator(NEW_CAP_AUTOMATOR).setBorrowCapConfig(asset, borrowMax, borrowGap, borrowIncreaseCooldown);
    }

    function _migrateMaxExchangeRate(address vault, uint256 rate) internal {
        uint256 oldMaxExchangeRate = MainnetController(Ethereum.ALM_CONTROLLER).maxExchangeRates(vault);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(vault, 1, rate);

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
