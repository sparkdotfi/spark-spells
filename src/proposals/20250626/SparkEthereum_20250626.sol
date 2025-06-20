// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  June 26, 2025 Spark Ethereum Proposal
 * @notice Spark DAI Morpho Vault:
 *         - Onboard PT-syrupUSDC-28Aug2025/DAI
 *         - Onboard PT-USDe-25Sept2025/DAI
 *         Spark Proxy:
 *         - Transfer USDS to destination
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/june-26-2025-proposed-changes-to-spark-for-upcoming-spell/26663
 * Vote:   https://vote.sky.money/polling/QmcGPTMX
 *         https://vote.sky.money/polling/QmWtGgPH
 */
contract SparkEthereum_20250626 is SparkPayloadEthereum {

    address internal constant DESTINATION                        = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;
    address internal constant PT_SYRUP_USDC_28AUG2025            = 0xCcE7D12f683c6dAe700154f0BAdf779C0bA1F89A;
    address internal constant PT_SYRUP_USDC_28AUG2025_PRICE_FEED = 0xdcC91883A87D336a2EEC0213E9167b4A6CD5b175;
    address internal constant PT_USDE_25SEP2025                  = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a;
    address internal constant PT_USDE_25SEP2025_PRICE_FEED       = 0x076a476329CAf84Ef7FED997063a0055900eE00f;

    uint256 internal constant TRANSFER_AMOUNT = 800_000e18;

    function _postExecute() internal override {
        // Onboard PT-syrupUSDC-28Aug2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SYRUP_USDC_28AUG2025,
                oracle:          PT_SYRUP_USDC_28AUG2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            300_000_000e18
        );

        // Onboard PT-USDe-25Sept2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_25SEP2025,
                oracle:          PT_USDE_25SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            500_000_000e18
        );

        // Transfer USDS to destination
        IERC20(Ethereum.USDS).transfer(DESTINATION, TRANSFER_AMOUNT);
    }

}
