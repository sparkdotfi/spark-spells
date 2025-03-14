// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SparkPayloadArbitrumOne, Arbitrum } from "../../SparkPayloadArbitrumOne.sol";

/**
 * @title  March 20, 2025 Spark Base Proposal
 * @notice Onboard Aave USDC, Onboard Fluid sUSDS
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/march-20-2025-proposed-changes-to-spark-for-upcoming-spell/26113
 * Vote:   https://vote.makerdao.com/polling/Qmf4PDcJ
 *         https://vote.makerdao.com/polling/QmZbk3gD
 */
contract SparkArbitrumOne_20250320 is SparkPayloadArbitrumOne {

    function execute() external {
        _onboardAaveToken(Arbitrum.ATOKEN_USDC, 30_000_000e6, 15_000_000e6 / uint256(1 days));
    }

}
