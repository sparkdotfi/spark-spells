// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { SparkLiquidityLayerTests } from "./SparkLiquidityLayerTests.sol";
import { SparkEthereumTests }       from "./SparkEthereumTests.sol";
import { CommonSpellAssertions }    from "./CommonSpellAssertions.sol";

/// @dev convenience contract meant to be the single point of entry for all
/// spell-specifictest contracts
abstract contract SparkTestBase is SparkLiquidityLayerTests, SparkEthereumTests, CommonSpellAssertions {
}
