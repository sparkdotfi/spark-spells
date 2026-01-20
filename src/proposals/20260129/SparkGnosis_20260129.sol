// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'lib/erc20-helpers/src/interfaces/IERC20.sol';

import { SparkPayloadGnosis } from 'src/SparkPayloadGnosis.sol';

/**
 * @title  January 29, 2026 Spark Gnosis Proposal
 * @notice SparkLend - Deprecate Market Phase 1
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-29-2026-proposed-changes/27620
 * Vote:   
 */
contract SparkGnosis_20260129 is SparkPayloadGnosis {

    function _postExecute() internal override {
        // Deprecate Market Phase 1

        address[] memory reserves = LISTING_ENGINE.POOL().getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFreeze(reserves[i], true);
            LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(reserves[i], 50_00);
        }
    }

}
