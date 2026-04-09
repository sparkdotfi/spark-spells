// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { SLLHelpers, SparkPayloadEthereum, IEngine } from "src/SparkPayloadEthereum.sol";

import { EngineFlags } from "src/AaveV3PayloadBase.sol";

/**
 * @title  April 23, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Update ETH Interest Rate Model
 *         - Update USDT Interest Rate Model
 *         - Deprecate rETH
 *         Spark Treasury:
 *         - Monthly Grants for Spark Foundation and Spark Assets Foundation.
 * Forum:  https://forum.skyeco.com/t/april-23-2026-proposed-changes-to-spark-for-upcoming-spell/27831
 * Vote:   
 */
contract SparkEthereum_20260423 is SparkPayloadEthereum {

    address internal constant NEW_USDT_IRM = 0x4E494988E68e6Fc52309BE4937869e27F0C304AC;
    address internal constant NEW_WETH_IRM = 0xDFB6206FfC5BA5B48D2852370ee6A1bf6887476a;

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;

    function collateralsUpdates()
        public view override returns (IEngine.CollateralUpdate[] memory)
    {
        IEngine.CollateralUpdate[] memory collateralUpdates = new IEngine.CollateralUpdate[](1);

        collateralUpdates[0] = IEngine.CollateralUpdate({
            asset          : Ethereum.RETH,
            ltv            : 0,
            liqThreshold   : EngineFlags.KEEP_CURRENT,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });

        return collateralUpdates;
    }

    function _postExecute() internal override {
        // 1. Update ETH Interest Rate Model.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.WETH, NEW_WETH_IRM);

        // 2. Update USDT Interest Rate Model.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, NEW_USDT_IRM);

        // 3. Deprecate rETH.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(Ethereum.RETH, true);

        // 5. Monthly Grants for Spark Foundation and Spark Assets Foundation
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
