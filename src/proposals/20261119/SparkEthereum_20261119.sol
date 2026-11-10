// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SLLHelpers, SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  November 19, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Upgrade the ALM controller to MainnetController v1.11.0 (CCTP V2).
 *         - Deprecate the Spark Liquidity Layer on OP Mainnet.
 *         - Deprecate the Spark Liquidity Layer on Unichain.
 *         - Deprecate Avalanche.
 *         Spark Treasury:
 *         - Transfer the December 2026 monthly grants to the Spark Foundation and the Spark Asset Foundation.
 * Forum:  https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-spark-for-upcoming-spell/28390
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x5547b7f06c852c98c517e53fb8f2516062d7d890c9abd1bd7b2c9a5db67f9289
 */
contract SparkEthereum_20261119 is SparkPayloadEthereum {

    address internal constant NEW_ALM_CONTROLLER = 0xc953972Cd006d1f12686fd7185c6D443b15900Cd;

    address internal constant CURVE_USDC_RLUSD         = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;
    address internal constant OLD_MORPHO_VAULT_V2_USDT = 0xc7CDcFDEfC64631ED6799C95e3b110cd42F2bD22;

    bytes32 internal constant OUSD_USDS_POOL_ID  = 0x710254704dfff19aee863a784a36823eb9c926cae8d3d425080d7c88c144a9c7;
    bytes32 internal constant PYUSD_USDS_POOL_ID = 0xe63e32b2ae40601662f760d6bf5d771057324fbd97784fe1d3717069f7b75d45;
    bytes32 internal constant RLUSD_USDS_POOL_ID = 0x9035721b23481db3888fd201b9c2b26dbc3af60258bca65e669f2ed98dc8eb4f;
    bytes32 internal constant USDS_USDG_POOL_ID  = 0x28adc7179a8a83c3379955d59563c0fec33eadfa83946b447af289190ff5fcff;
    bytes32 internal constant USDT_USDS_POOL_ID  = 0x3b1b1f2e775a6db1664f8e7d59ad568605ea2406312c11aef03146c0cf89d5b9;

    uint32 internal constant LZ_ENDPOINT_ARBITRUM = 30110;
    uint32 internal constant LZ_ENDPOINT_XLAYER   = 30274;

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    constructor() {
        // PAYLOAD_AVALANCHE = address(0);
        // PAYLOAD_OPTIMISM  = address(0);
        // PAYLOAD_UNICHAIN  = address(0);
        // PAYLOAD_XLAYER    = address(0);
    }

    function _postExecute() internal override {
        MainnetController newController = MainnetController(NEW_ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Ethereum.ALM_RATE_LIMITS);

        // 1. Upgrade the ALM controller to MainnetController v1.11.0 (CCTP V2).

        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC,          10);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1,            10);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS,             10);
        _migrateMaxExchangeRate(Ethereum.SUSDS,                         10);
        _migrateMaxExchangeRate(Ethereum.FLUID_SUSDS,                   10);
        _migrateMaxExchangeRate(Ethereum.SUSDE,                         10);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDC,                    10);
        _migrateMaxExchangeRate(Ethereum.SYRUP_USDT,                    10);
        _migrateMaxExchangeRate(Ethereum.ARKIS_VAULT,                   10);
        _migrateMaxExchangeRate(Ethereum.MORPHO_VAULT_V2_USDT,          1_000_000);
        _migrateMaxExchangeRate(OLD_MORPHO_VAULT_V2_USDT,               1_000_000);
        _migrateMaxExchangeRate(Ethereum.SENTORA_RLUSD_MORPHO_VAULT_V2, 3);

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
        _migrateMaxSlippage(SparkLend.USDG_SPTOKEN);
        _migrateMaxSlippage(SparkLend.RLUSD_SPTOKEN);

        _migrateMaxSlippage(Ethereum.CURVE_PYUSDUSDC);
        _migrateMaxSlippage(Ethereum.CURVE_USDCUSDT);
        _migrateMaxSlippage(Ethereum.CURVE_PYUSDUSDS);
        _migrateMaxSlippage(Ethereum.CURVE_SUSDSUSDT);
        _migrateMaxSlippage(Ethereum.CURVE_WEETHWETHNG);
        _migrateMaxSlippage(CURVE_USDC_RLUSD);

        _migrateMaxSlippage(address(uint160(uint256(PYUSD_USDS_POOL_ID))));
        _migrateMaxSlippage(address(uint160(uint256(USDT_USDS_POOL_ID))));
        _migrateMaxSlippage(address(uint160(uint256(USDS_USDG_POOL_ID))));
        _migrateMaxSlippage(address(uint160(uint256(RLUSD_USDS_POOL_ID))));
        _migrateMaxSlippage(address(uint160(uint256(OUSD_USDS_POOL_ID))));

        _migrateMaxSlippage(Ethereum.BINANCE_EXCHANGE);

        _migrateUniswapV4TickLimits(PYUSD_USDS_POOL_ID);
        _migrateUniswapV4TickLimits(USDT_USDS_POOL_ID);
        _migrateUniswapV4TickLimits(USDS_USDG_POOL_ID);
        _migrateUniswapV4TickLimits(RLUSD_USDS_POOL_ID);
        _migrateUniswapV4TickLimits(OUSD_USDS_POOL_ID);

        _migrateLayerZeroRecipient(LZ_ENDPOINT_ARBITRUM);
        _migrateLayerZeroRecipient(LZ_ENDPOINT_XLAYER);

        _migrateOTC(Ethereum.BINANCE_EXCHANGE, Ethereum.USDT, Ethereum.USDC);

        // 2. Deprecate the Spark Liquidity Layer on OP Mainnet: close the Ethereum USDC route to OP Mainnet.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(newController.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM),
            0,
            0
        );

        // 3. Deprecate the Spark Liquidity Layer on Unichain: close the Ethereum USDC route to Unichain.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(newController.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN),
            0,
            0
        );

        // 4. Deprecate Avalanche: close the Ethereum USDC route to Avalanche.
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeUint32Key(newController.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_AVALANCHE),
            0,
            0
        );

        // 7. Transfer the December 2026 monthly grants to the Spark Foundation and the Spark Asset Foundation.
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       SPARK_FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
    }

    function _migrateMaxExchangeRate(address vault, uint256 rate) internal {
        uint256 oldMaxExchangeRate = MainnetController(Ethereum.ALM_CONTROLLER).maxExchangeRates(vault);

        SLLHelpers.setMaxExchangeRate(NEW_ALM_CONTROLLER, vault, 1, rate);

        require(
            MainnetController(NEW_ALM_CONTROLLER).maxExchangeRates(vault) == oldMaxExchangeRate,
            "Max exchange rate mismatch"
        );
    }

    function _migrateMaxSlippage(address pool) internal {
        uint256 oldMaxSlippage = MainnetController(Ethereum.ALM_CONTROLLER).maxSlippages(pool);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(pool, oldMaxSlippage);
    }

    function _migrateUniswapV4TickLimits(bytes32 poolId) internal {
        ( int24 tickLower, int24 tickUpper, uint24 maxTickSpacing )
            = MainnetController(Ethereum.ALM_CONTROLLER).uniswapV4TickLimits(poolId);

        MainnetController(NEW_ALM_CONTROLLER).setUniswapV4TickLimits(poolId, tickLower, tickUpper, maxTickSpacing);
    }

    function _migrateLayerZeroRecipient(uint32 destinationEndpointId) internal {
        bytes32 oldRecipient = MainnetController(Ethereum.ALM_CONTROLLER).layerZeroRecipients(destinationEndpointId);

        MainnetController(NEW_ALM_CONTROLLER).setLayerZeroRecipient(destinationEndpointId, oldRecipient);
    }

    function _migrateOTC(address exchange, address asset0, address asset1) internal {
        MainnetController oldController = MainnetController(Ethereum.ALM_CONTROLLER);
        MainnetController newController = MainnetController(NEW_ALM_CONTROLLER);

        ( address otcBuffer, uint256 rechargeRate18, , , ) = oldController.otcs(exchange);

        newController.setOTCBuffer(exchange, otcBuffer);

        newController.setOTCRechargeRate(exchange, rechargeRate18);

        newController.setOTCWhitelistedAsset(exchange, asset0, oldController.otcWhitelistedAssets(exchange, asset0));
        newController.setOTCWhitelistedAsset(exchange, asset1, oldController.otcWhitelistedAssets(exchange, asset1));
    }

}
