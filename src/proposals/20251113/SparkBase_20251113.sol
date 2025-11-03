// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base } from "spark-address-registry/Base.sol";

import { SparkPayloadBase, SLLHelpers } from "../../SparkPayloadBase.sol";

/**
 * @title  November 13, 2025 Spark Base Proposal
 * @notice Spark Blue Chip USDC Morpho Vault:
           - Onboard cbETH and ETH
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-13-2025-proposed-changes-to-spark-for-upcoming-spell/27354
 * Vote:   
 */
contract SparkBase_20251113 is SparkPayloadBase {

    address internal constant ETH        = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    address internal constant CBETH        = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address internal constant CBETH_ORACLE = 0xb40d93F44411D8C09aD17d7F88195eF9b05cCD96;

    function execute() external {
        // Onboard ETH and cbETH
        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).submitCap(
            MarketParams({
                loanToken:       Base.USDC,
                collateralToken: ETH,
                oracle:          ETH_ORACLE,
                irm:             Base.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            1_000_000_000e18
        );

        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).submitCap(
            MarketParams({
                loanToken:       Base.USDC,
                collateralToken: CBETH,
                oracle:          CBETH_ORACLE,
                irm:             Base.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            50_000_000e18
        );
    }

}
