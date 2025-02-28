// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  March 06, 2025 Spark Base Proposal
 * @notice Update cbBTC Morpho supply cap
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/march-6-2025-proposed-changes-to-spark-for-upcoming-spell/26036
 * Vote:   TODO
 */
contract SparkBase_20250306 is SparkPayloadBase {

    address internal constant CBBTC_USDC_ORACLE = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;

    function execute() external {
        MarketParams memory usdcCBBTC = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: Base.CBBTC,
            oracle:          CBBTC_USDC_ORACLE,
            irm:             Base.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });

        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).submitCap(
            usdcCBBTC,
            500_000_000e6
        );
    }

}
