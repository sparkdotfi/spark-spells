// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

import { SparkPayloadBase, Base } from "../../SparkPayloadBase.sol";

/**
 * @title  May 29, 2025 Spark Base Proposal
 * @notice SparkLend: Update cbBTC Morpho supply cap
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell/26372
 * Vote:   https://vote.makerdao.com/polling/QmfPc8Ub
 */
contract SparkBase_20250529 is SparkPayloadBase {

    address internal constant CBBTC_USDC_ORACLE = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;

    function execute() external {
        MarketParams memory usdcCBBTC = MarketParams({
            loanToken       : Base.USDC,
            collateralToken : Base.CBBTC,
            oracle          : CBBTC_USDC_ORACLE,
            irm             : Base.MORPHO_DEFAULT_IRM,
            lltv            : 0.86e18
        });

        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).submitCap(
            usdcCBBTC,
            1_000_000_000e6
        );
    }

}
