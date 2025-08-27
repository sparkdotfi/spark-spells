// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }                       from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

import { SparkPayloadEthereum, IEngine, EngineFlags, SLLHelpers } from "../../SparkPayloadEthereum.sol";

interface ITreasuryController {
    function transfer(
        address collector,
        address token,
        address recipient,
        uint256 amount
    ) external;
}

interface IController {
    function transferAsset(
        address asset,
        address destination,
        uint256 amount
    ) external;

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;
}

/**
 * @title  September 4, 2025 Spark Ethereum Proposal
 * @notice Spark USDS Morpho Vault:
 *         - Onboard November Ethena PTs
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/september-4-2025-proposed-changes-to-spark-for-upcoming-spell/27102
 * Vote:   
 */
contract SparkEthereum_20250904 is SparkPayloadEthereum {

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x20Cea639A895c3c85dce326dc6A736508C310B4b;
    address internal constant PT_SUSDE_27NOV2025            = 0xe6A934089BBEe34F832060CE98848359883749B3;
    address internal constant PT_SUSDE_27NOV2025_PRICE_FEED = 0x098fA1fcB5Ed89Bffb2d6876857764fc14837DB5;
    address internal constant WETH_PRICE_FEED               = 0xdC6fd5831277c693b1054e19E94047cB37c77615;
    address internal constant WSTETH_PRICE_FEED             = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

    address internal constant CURVE_PYUSDUSDC = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address internal constant PYUSD_ATOKEN    = 0x779224df1c756b4EDD899854F32a53E8c2B2ce5d;
    address internal constant USDE_ATOKEN     = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
    address internal constant USDS_ATOKEN     = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;

    address internal constant GROVE_ALM_PROXY  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant SPARK_FOUNDATION = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;
    address internal constant SPARK_USDC_VAULT = 0xfeaC08ffA38d95ec5Ed7C46c933C8891a44C5F26;

    uint256 internal constant USDS_AMOUNT_TO_SPARK_FOUNDATION = 800_000e18;

    function _postExecute() internal override {
        IMetaMorpho(SPARK_USDC_VAULT).setIsAllocator(
            Ethereum.ALM_RELAYER,
            true
        );
        MarketParams memory idleMarket = SLLHelpers.morphoIdleMarket(Ethereum.USDC);
        IMetaMorpho(SPARK_USDC_VAULT).submitCap(
            idleMarket,
            type(uint184).max
        );
        IMetaMorpho(SPARK_USDC_VAULT).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDC,
                collateralToken: Ethereum.CBBTC,
                oracle:          CBBTC_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            500_000_000e6
        );
        IMetaMorpho(SPARK_USDC_VAULT).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDC,
                collateralToken: Ethereum.WSTETH,
                oracle:          WSTETH_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            500_000_000e6
        );
        IMetaMorpho(SPARK_USDC_VAULT).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDC,
                collateralToken: Ethereum.WETH,
                oracle:          WETH_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            500_000_000e6
        );

        _onboardERC4626Vault(
            SPARK_USDC_VAULT,
            50_000_000e6,
            25_000_000e6 / uint256(1 days)
        );

        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDE_27NOV2025,
                oracle:          PT_USDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SUSDE_27NOV2025,
                oracle:          PT_SUSDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );

        _onboardAaveToken(USDE_ATOKEN, 250_000_000e18, 100_000_000e18 / uint256(1 days));

        MainnetController(Ethereum.ALM_CONTROLLER).setMaxSlippage(Ethereum.CURVE_SUSDSUSDT, 0.9975e18);
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_CURVE_SWAP(),
                Ethereum.CURVE_SUSDSUSDT
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 5_000_000e18,
                slope     : 100_000_000e18 / uint256(1 days)
            }),
            "curveSwapLimit",
            18
        );

        MainnetController(Ethereum.ALM_CONTROLLER).setMaxSlippage(CURVE_PYUSDUSDC, 0.9990e18);
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_CURVE_SWAP(),
                CURVE_PYUSDUSDC
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 5_000_000e18,
                slope     : 100_000_000e18 / uint256(1 days)
            }),
            "curveSwapLimit",
            18
        );

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
                Ethereum.USDT_ATOKEN
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "usdtDepositLimit",
            6
        );

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
                PYUSD_ATOKEN
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "pyusdDepositLimit",
            6
        );

        // Grant controller role to Spark Proxy
        IController(Ethereum.ALM_PROXY).grantRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );

        IALMProxy(Ethereum.ALM_PROXY).doCall(
            Ethereum.BUIDLI,
            abi.encodeCall(
                IERC20(Ethereum.BUIDLI).transfer,
                (GROVE_ALM_PROXY, IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY))
            )
        );

        // Revoke controller role from Spark Proxy
        IController(Ethereum.ALM_PROXY).revokeRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );

        address[] memory assets = new address[](2);
        assets[0] = Ethereum.DAI;
        assets[1] = Ethereum.USDS;

        IPool(Ethereum.POOL).mintToTreasury(assets);

        ITreasuryController(Ethereum.TREASURY_CONTROLLER).transfer({
            collector: Ethereum.TREASURY,
            token:     Ethereum.DAI_ATOKEN,
            recipient: Ethereum.SPARK_PROXY,
            amount:    IERC20(Ethereum.DAI_ATOKEN).balanceOf(Ethereum.TREASURY)
        });

        ITreasuryController(Ethereum.TREASURY_CONTROLLER).transfer({
            collector: Ethereum.TREASURY,
            token:     USDS_ATOKEN,
            recipient: Ethereum.SPARK_PROXY,
            amount:    IERC20(USDS_ATOKEN).balanceOf(Ethereum.TREASURY)
        });

        IERC20(Ethereum.USDS).transfer(SPARK_FOUNDATION, USDS_AMOUNT_TO_SPARK_FOUNDATION);
    }

}
