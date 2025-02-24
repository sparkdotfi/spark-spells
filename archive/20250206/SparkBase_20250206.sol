// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho }      from 'lib/metamorpho/src/interfaces/IMetaMorpho.sol';
import { Base }             from 'spark-address-registry/Base.sol';
import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

/**
 * @title  Feb 06, 2025 Spark Base Proposal
 * @notice Spark Liquidity Layer: onboard Fluid sUSDS, increase Morpho Vault Timelock
 * @author Wonderland
 * Forum:  https://forum.sky.money/t/feb-6-2025-proposed-changes-to-spark-for-upcoming-spell-actual/25888
 * Vote:   https://vote.makerdao.com/polling/QmUMkWLQ - increase Morpho Vault Timelock
 *         https://vote.makerdao.com/polling/QmTfntSm - onboard Fluid sUSDS
 */
contract SparkBase_20250206 is SparkPayloadBase {

    address public immutable FLUID_SUSDS_VAULT       = 0xf62e339f21d8018940f188F6987Bcdf02A849619;
    uint256 public immutable FLUID_SUSDS_MAX_DEPOSIT = 10_000_000e18;
    uint256 public immutable FLUID_SUSDS_MAX_SLOPE   = 5_000_000e18 / uint256(1 days);

    uint256 public immutable NEW_TIMELOCK = 1 days;

    function execute() external { 
        _onboardERC4626Vault(
            FLUID_SUSDS_VAULT,
            FLUID_SUSDS_MAX_DEPOSIT,
            FLUID_SUSDS_MAX_SLOPE
        );
        IMetaMorpho(Base.MORPHO_VAULT_SUSDC).submitTimelock(NEW_TIMELOCK);
    }

}
