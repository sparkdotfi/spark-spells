// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum, IEngine, EngineFlags } from "../../SparkPayloadEthereum.sol";

/**
 * @title  August 21, 2025 Spark Ethereum Proposal
 * @notice SparkLend:
 *         - Refresh Market Params
 *         Spark USDS Morpho Vault:
 *         - Activate Vault Fee
 *         Spark Treasury:
 *         - Transfer Aave Revenue Share Payment
 *         - Authorize Rate Limited Transfer of MORPHO Tokens to Multisig
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/august-21-2025-proposed-changes-to-spark-for-upcoming-spell/26997
 * Vote:   https://vote.sky.money/polling/QmefEkAi
 *         https://vote.sky.money/polling/QmP8NVR5
 *         https://vote.sky.money/polling/QmNmGBSt
 */
contract SparkEthereum_20250821 is SparkPayloadEthereum {

    uint256 internal constant MORPHO_SPARK_USDS_VAULT_FEE = 0.1e18;
    uint256 internal constant USDS_AMOUNT                 = 19_411.17e18;

    address internal constant AAVE_V3_COLLECTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    address internal constant MORPHO_TOKEN      = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address internal constant SPARK_MULTISIG    = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;

    address internal constant NEW_USDS_DAI_IRM  = 0x8a95998639A34462A1FdAaaA5506F66F90Ef2fDd;
    address internal constant NEW_USDC_USDT_IRM = 0x2961d766D71F33F6C5e6Ca8bA7d0Ca08E6452C92;
    address internal constant NEW_WETH_IRM      = 0x4FD869adB651917D5c2591DD7128Ae6e1C24bDD5;

    function collateralsUpdates()
        public pure override returns (IEngine.CollateralUpdate[] memory)
    {
        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](8);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset:          Ethereum.WETH,
            ltv:            85_00,
            liqThreshold:   86_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[1] = IEngine.CollateralUpdate({
            asset:          Ethereum.WSTETH,
            ltv:            83_00,
            liqThreshold:   84_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[2] = IEngine.CollateralUpdate({
            asset:          Ethereum.CBBTC,
            ltv:            81_00,
            liqThreshold:   82_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[3] = IEngine.CollateralUpdate({
            asset:          Ethereum.WEETH,
            ltv:            79_00,
            liqThreshold:   80_00,
            liqBonus:       8_00,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[4] = IEngine.CollateralUpdate({
            asset:          Ethereum.RSETH,
            ltv:            75_00,
            liqThreshold:   76_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[5] = IEngine.CollateralUpdate({
            asset:          Ethereum.EZETH,
            ltv:            75_00,
            liqThreshold:   76_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[6] = IEngine.CollateralUpdate({
            asset:          Ethereum.LBTC,
            ltv:            74_00,
            liqThreshold:   75_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        collateralUpdates[7] = IEngine.CollateralUpdate({
            asset:          Ethereum.TBTC,
            ltv:            74_00,
            liqThreshold:   75_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).setFeeRecipient(Ethereum.ALM_PROXY);
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).setFee(MORPHO_SPARK_USDS_VAULT_FEE);

        IERC20(Ethereum.USDS).transfer(AAVE_V3_COLLECTOR, USDS_AMOUNT);

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                MORPHO_TOKEN,
                SPARK_MULTISIG
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 100_000e18,
                slope     : 100_000e18 / uint256(1 days)
            }),
            "morphoTransferLimit",
            18
        );

        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.DAI,  NEW_USDS_DAI_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDS, NEW_USDS_DAI_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDC, NEW_USDC_USDT_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, NEW_USDC_USDT_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.WETH, NEW_WETH_IRM);

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setBorrowCapConfig({ asset: Ethereum.WSTETH, max: 1, gap: 1, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: Ethereum.RETH,   max: 1, gap: 1, increaseCooldown: 12 hours });
    }

}
