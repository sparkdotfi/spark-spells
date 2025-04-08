// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadArbitrumOne, Arbitrum } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  April 17, 2025 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer: Onboard Fluid sUSDS
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-17-2025-proposed-changes-to-spark-for-upcoming-spell/26234
 * Vote:   https://vote.makerdao.com/polling/QmZbk3gD
 */
contract SparkArbitrumOne_20250417 is SparkPayloadArbitrumOne {

    address internal constant FLUID_SUSDS = 0x3459fcc94390C3372c0F7B4cD3F8795F0E5aFE96;

    function execute() external {
        _onboardERC4626Vault(FLUID_SUSDS, 10_000_000e18, uint256(5_000_000e18) / 1 days);
    }

}
