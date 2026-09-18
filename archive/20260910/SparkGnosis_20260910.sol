// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Gnosis } from "spark-address-registry/Gnosis.sol";

import { SparkPayloadGnosis } from "../../SparkPayloadGnosis.sol";

/**
 * @title  September 10, 2026 Spark Gnosis Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Complete the Deprecation of the Gnosis Market.
 * Forum:  https://forum.skyeco.com/t/september-10-2026-proposed-changes-to-spark-for-upcoming-spell/28208
 */
contract SparkGnosis_20260910 is SparkPayloadGnosis {

    function _postExecute() internal override {
        // 3. Complete the deprecation of SparkLend on Gnosis Chain.

        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Gnosis.WXDAI,  0, 1, 105_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Gnosis.WETH,   0, 1, 105_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Gnosis.WSTETH, 0, 1, 108_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Gnosis.GNO,    0, 1, 112_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().configureReserveAsCollateral(Gnosis.SXDAI,  0, 1, 106_00);

        LISTING_ENGINE.POOL_CONFIGURATOR().setAssetEModeCategory(Gnosis.WETH,   0);
        LISTING_ENGINE.POOL_CONFIGURATOR().setAssetEModeCategory(Gnosis.WSTETH, 0);

        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Gnosis.WXDAI,  0);
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Gnosis.WETH,   0);
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Gnosis.WSTETH, 0);
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Gnosis.GNO,    0);
        LISTING_ENGINE.POOL_CONFIGURATOR().setLiquidationProtocolFee(Gnosis.SXDAI,  0);
    }

}
