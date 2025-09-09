// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {
    Ethereum,
    Base,
    SparkPayloadEthereum,
    IEngine,
    EngineFlags,
    Rates
} from "../../SparkPayloadEthereum.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Base } from "spark-address-registry/Base.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

import { AllocatorBuffer } from "dss-allocator/src/AllocatorBuffer.sol";
import { AllocatorVault }  from "dss-allocator/src/AllocatorVault.sol";

import { ControllerInstance }              from "spark-alm-controller/deploy/ControllerInstance.sol";
import { MainnetControllerInit }           from "spark-alm-controller/deploy/MainnetControllerInit.sol";
import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

interface ITokenBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

/**
 * @title  Jan 09, 2025 Spark Ethereum Proposal
 * @notice Sparklend: update WBTC, cbBTC, wstETH, weETH, DAI, USDC and USDT parameters
 *         Morpho: onboard PT-USDe-29May2025 and adjust existing caps
           Spark Liquidity Layer: Controller Upgrade, Onboard Ethena Direct,
                                  Aave V3 and increase liquidity available to Base
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/27-dec-2024-proposed-changes-to-spark-for-upcoming-spell/25760
 * Vote:   https://vote.makerdao.com/polling/QmYScEHT
 *         https://vote.makerdao.com/polling/Qma1xA18
 *         https://vote.makerdao.com/polling/QmeEvuG2
 *         https://vote.makerdao.com/polling/QmVpv1G8
 *         https://vote.makerdao.com/polling/QmZ2Qmy5
 *         https://vote.makerdao.com/polling/QmSTYyW5
 *         https://vote.makerdao.com/polling/QmTFsGw8
 *         https://vote.makerdao.com/polling/QmYDGkjM
 *         https://vote.makerdao.com/polling/QmZfSDMH
 *         https://vote.makerdao.com/polling/QmQ6bYou
 */
contract SparkEthereum_20250109 is SparkPayloadEthereum {

    address internal constant NEW_ALM_CONTROLLER = 0x5cf73FDb7057E436A6eEaDFAd27E45E7ab6E431e;

    address internal constant NEW_DAI_IRM         = 0xd957978711F705358dbE34B37D381a76E1555E28;
    address internal constant NEW_STABLECOINS_IRM = 0xb7b734CF1F13652E930f8a604E8f837f85160174;

    address internal constant PT_SUSDE_24OCT2024_PRICE_FEED = 0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35;
    address internal constant PT_SUSDE_24OCT2024            = 0xAE5099C39f023C91d3dd55244CAFB36225B0850E;
    address internal constant PT_SUSDE_26DEC2024_PRICE_FEED = 0x81E5E28F33D314e9211885d6f0F4080E755e4595;
    address internal constant PT_SUSDE_26DEC2024            = 0xEe9085fC268F6727d5D4293dBABccF901ffDCC29;
    address internal constant PT_SUSDE_27MAR2025_PRICE_FEED = 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7;
    address internal constant PT_SUSDE_27MAR2025            = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;

    address internal constant ATOKEN_USDS = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address internal constant ATOKEN_USDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    uint256 internal constant USDS_MINT_AMOUNT = 99_000_000e18;

    constructor() {
        PAYLOAD_BASE = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    }

    function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
        IEngine.CollateralUpdate[] memory updates = new IEngine.CollateralUpdate[](2);

        // WBTC: Reduce LT from 60% to 55%
        updates[0] = IEngine.CollateralUpdate({
            asset:          Ethereum.WBTC,
            ltv:            EngineFlags.KEEP_CURRENT,
            liqThreshold:   55_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        // weETH: Disable isolation mode
        updates[1] = IEngine.CollateralUpdate({
            asset:          Ethereum.WEETH,
            ltv:            EngineFlags.KEEP_CURRENT,
            liqThreshold:   EngineFlags.KEEP_CURRENT,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    0,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        return updates;
    }

    function borrowsUpdates() public pure override returns (IEngine.BorrowUpdate[] memory) {
        IEngine.BorrowUpdate[] memory updates = new IEngine.BorrowUpdate[](1);

        // wstETH: Increase reserve factor from 15% to 30%
        updates[0] = IEngine.BorrowUpdate({
            asset:                 Ethereum.WSTETH,
            enabledToBorrow:       EngineFlags.KEEP_CURRENT,
            flashloanable:         EngineFlags.KEEP_CURRENT,
            stableRateModeEnabled: EngineFlags.KEEP_CURRENT,
            borrowableInIsolation: EngineFlags.KEEP_CURRENT,
            withSiloedBorrowing:   EngineFlags.KEEP_CURRENT,
            reserveFactor:         30_00
        });

        return updates;
    }

    function rateStrategiesUpdates()
        public
        view
        override
        returns (IEngine.RateStrategyUpdate[] memory)
    {
        IEngine.RateStrategyUpdate[] memory updates = new IEngine.RateStrategyUpdate[](1);

        Rates.RateStrategyParams memory wstethParams = LISTING_ENGINE
            .RATE_STRATEGIES_FACTORY()
            .getStrategyDataOfAsset(Ethereum.WSTETH);
        wstethParams.baseVariableBorrowRate = 0;
        wstethParams.optimalUsageRatio      = _bpsToRay(70_00);
        wstethParams.variableRateSlope1     = _bpsToRay(2_00);
        wstethParams.variableRateSlope2     = _bpsToRay(200_00);
        updates[0] = IEngine.RateStrategyUpdate({
            asset:  Ethereum.WSTETH,
            params: wstethParams
        });

        return updates;
    }

    function _postExecute() internal override {
        // --- Cap Automator Updates ---

        // cbBTC: Increase max from 3k to 10k
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.CBBTC,
            max:              10_000,
            gap:              500,
            increaseCooldown: 12 hours
        });

        // wstETH: Increase supply max from 1.2m to 2m
        //         Increase borrow max from 100k to 1m, gap from 5k to 10k
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.WSTETH,
            max:              2_000_000,
            gap:              50_000,
            increaseCooldown: 12 hours
        });
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setBorrowCapConfig({
            asset:            Ethereum.WSTETH,
            max:              1_000_000,
            gap:              10_000,
            increaseCooldown: 12 hours
        });

        // --- Custom IRM Updates ---

        // DAI, USDC, USDT: update IRM to anchor to SSR, increase DAI spread by 0.25%
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(
            Ethereum.DAI,
            NEW_DAI_IRM
        );
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(
            Ethereum.USDC,
            NEW_STABLECOINS_IRM
        );
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(
            Ethereum.USDT,
            NEW_STABLECOINS_IRM
        );

        // --- Morpho Supply Cap Updates ---

        _morphoSupplyCapUpdates();

        // --- Spark Liquidity Layer Controller Upgrade ---

        _upgradeController();

        // --- Spark Liquidity Layer Onboarding ---

        // Ethena Direct
        _onboardEthena();

        // Aave V3
        _onboardAaveToken(ATOKEN_USDS, 50_000_000e18, 25_000_000e18 / uint256(1 days));
        _onboardAaveToken(ATOKEN_USDC, 50_000_000e6,  25_000_000e6 / uint256(1 days));

        // --- Send USDS and sUSDS to Base ---

        // Mint USDS
        AllocatorVault(Ethereum.ALLOCATOR_VAULT).draw(USDS_MINT_AMOUNT);
        AllocatorBuffer(Ethereum.ALLOCATOR_BUFFER).approve(Ethereum.USDS, address(this), USDS_MINT_AMOUNT);
        IERC20(Ethereum.USDS).transferFrom(Ethereum.ALLOCATOR_BUFFER, address(this), USDS_MINT_AMOUNT);

        // Bridge to Base
        IERC20(Ethereum.USDS).approve(Ethereum.BASE_TOKEN_BRIDGE, USDS_MINT_AMOUNT);
        ITokenBridge(Ethereum.BASE_TOKEN_BRIDGE).bridgeERC20To(Ethereum.USDS, Base.USDS, Base.ALM_PROXY, USDS_MINT_AMOUNT, 1_000_000, "");
    }

    function _morphoSupplyCapUpdates() private {
        // Reduce existing cap for USDe 94.5% LTV 10m -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: Ethereum.USDE,
                oracle:          Ethereum.MORPHO_USDE_ORACLE,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.945e18
            }),
            0
        );

        // Reduce existing cap for USDe 77% LTV 1b -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: Ethereum.USDE,
                oracle:          Ethereum.MORPHO_USDE_ORACLE,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.77e18
            }),
            0
        );

        // Reduce existing cap for sUSDe 94.5% LTV 10m -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: Ethereum.SUSDE,
                oracle:          Ethereum.MORPHO_SUSDE_ORACLE,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.945e18
            }),
            0
        );

        // Reduce existing cap for sUSDe 77% LTV 1b -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: Ethereum.SUSDE,
                oracle:          Ethereum.MORPHO_SUSDE_ORACLE,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.77e18
            }),
            0
        );

        // Reduce existing cap for PT-sUSDe-24Oct2024 100m -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_24OCT2024,
                oracle:          PT_SUSDE_24OCT2024_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            0
        );

        // Reduce existing cap for PT-sUSDe-26Dec2024 250m -> 0
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_26DEC2024,
                oracle:          PT_SUSDE_26DEC2024_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            0
        );

        // Increase existing cap for PT-sUSDe-27Mar2025 400m -> 500m
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_27MAR2025,
                oracle:          PT_SUSDE_27MAR2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );

        // Onboard PT-sUSDe-29May2025 0 -> 200m
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_29MAY2025,
                oracle:          PT_SUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            200_000_000e18
        );
    }

    function _upgradeController() private {
        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](1);
        mintRecipients[0] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(Base.ALM_PROXY)))
        });

        MainnetControllerInit.upgradeController({
            controllerInst: ControllerInstance({
                almProxy   : Ethereum.ALM_PROXY,
                controller : NEW_ALM_CONTROLLER,
                rateLimits : Ethereum.ALM_RATE_LIMITS
            }),
            configAddresses: MainnetControllerInit.ConfigAddressParams({
                freezer       : Ethereum.ALM_FREEZER,
                relayer       : Ethereum.ALM_RELAYER,
                oldController : Ethereum.ALM_CONTROLLER
            }),
            checkAddresses: MainnetControllerInit.CheckAddressParams({
                admin      : Ethereum.SPARK_PROXY,
                proxy      : Ethereum.ALM_PROXY,
                rateLimits : Ethereum.ALM_RATE_LIMITS,
                vault      : Ethereum.ALLOCATOR_VAULT,
                psm        : Ethereum.PSM,
                daiUsds    : Ethereum.DAI_USDS,
                cctp       : Ethereum.CCTP_TOKEN_MESSENGER
            }),
            mintRecipients: mintRecipients
        });
    }

    function _onboardEthena() private {
        // USDe mint/burn
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_USDE_MINT(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 50_000_000e6 / uint256(1 days)
            }),
            "ethenaMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_USDE_BURN(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e18,
                slope     : 100_000_000e18 / uint256(1 days)
            }),
            "ethenaBurnLimit",
            18
        );

        // sUSDe deposit (no need for withdrawal because of cooldown)
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
                Ethereum.SUSDE
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000_000e18,
                slope     : 100_000_000e18 / uint256(1 days)
            }),
            "susdeDepositLimit",
            18
        );

        // Cooldown
        RateLimitHelpers.setRateLimitData(
            MainnetController(NEW_ALM_CONTROLLER).LIMIT_SUSDE_COOLDOWN(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 500_000_000e18,
                slope     : 250_000_000e18 / uint256(1 days)
            }),
            "susdeCooldownLimit",
            18
        );
    }

}
