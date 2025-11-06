// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }          from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorphoChainlinkOracleV2 } from "morpho-blue-oracles/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol";

import { PendleSparkLinearDiscountOracle } from "pendle-core-v2-public/oracles/internal/PendleSparkLinearDiscountOracle.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MorphoUpgradableOracle } from "sparklend-advanced/src/MorphoUpgradableOracle.sol";

import {
    IMorphoLike,
    IMorphoOracleFactoryLike,
    IPendleLinearDiscountOracleLike
} from "../interfaces/Interfaces.sol";

import { MorphoHelpers } from "../libraries/MorphoHelpers.sol";

import { SpellRunner } from "./SpellRunner.sol";

/// @dev assertions specific to mainnet
/// TODO: separate mainnet-specific sparklend tests from those we should run on Gnosis as well
abstract contract MorphoTests is SpellRunner {

    address internal constant MORPHO_ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    function _testMorphoCapUpdate(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             newCap
    )
        internal
    {
        MorphoHelpers.assertMorphoCap(vault, config, currentCap);
        _executeAllPayloadsAndBridges();

        if (newCap > currentCap) {
            // Increases are timelocked
            MorphoHelpers.assertMorphoCap(vault, config, currentCap, newCap);

            assertEq(IMetaMorpho(vault).timelock(), 1 days);

            skip(1 days);

            IMetaMorpho(vault).acceptCap(config);

            MorphoHelpers.assertMorphoCap(vault, config, newCap);
        } else {
            // Decreases are immediate
            MorphoHelpers.assertMorphoCap(vault, config, newCap);
        }

        // Check total assets in the morpho market are greater than 1 unit of the loan token
        ( uint256 totalSupplyAssets_, , , , , ) = IMorphoLike(Ethereum.MORPHO).market(MarketParamsLib.id(config));
        assertGe(totalSupplyAssets_, 10 ** IERC20(config.loanToken).decimals());

        // Check shares of address(1) are greater or equal to 10 ** loanTokenDecimals (1 unit)
        IMorphoLike.Position memory position = IMorphoLike(Ethereum.MORPHO).position(MarketParamsLib.id(config), address(1));
        assertGe(position.supplyShares, 10 ** IERC20(config.loanToken).decimals());
    }

    function _testMorphoPendlePTOracleConfig(
        address pt,
        address loanToken,
        address oracle,
        uint256 discount,
        uint256 maturity
    )
        internal
    {
        IMorphoChainlinkOracleV2        oracle_      = IMorphoChainlinkOracleV2(oracle);
        MorphoUpgradableOracle          baseFeed     = MorphoUpgradableOracle(address(oracle_.BASE_FEED_1()));
        IPendleLinearDiscountOracleLike pendleOracle = IPendleLinearDiscountOracleLike(address(baseFeed.source()));

        // TODO: This assumes loanTokenDecimals >= ptDecimals, fix for the other case.
        uint256 assetConversion = 10 ** (IERC20(loanToken).decimals() - IERC20(pt).decimals());

        assertEq(address(oracle_.BASE_FEED_2()),          address(0));
        assertEq(address(oracle_.BASE_VAULT()),           address(0));
        assertEq(oracle_.BASE_VAULT_CONVERSION_SAMPLE(),  1);
        assertEq(address(oracle_.QUOTE_FEED_1()),         address(0));
        assertEq(address(oracle_.QUOTE_FEED_2()),         address(0));
        assertEq(address(oracle_.QUOTE_VAULT()),          address(0));
        assertEq(oracle_.QUOTE_VAULT_CONVERSION_SAMPLE(), 1);
        assertEq(oracle_.SCALE_FACTOR(),                  1e36 * assetConversion / 10 ** (IERC20(address(baseFeed)).decimals()));
        assertGe(oracle_.price(),                         0.01e36);
        assertLe(oracle_.price(),                         1e36 * assetConversion);

        assertEq(pendleOracle.PT(),                  pt);
        assertEq(pendleOracle.baseDiscountPerYear(), discount);
        assertEq(pendleOracle.maturity(),            maturity);
        assertEq(pendleOracle.getDiscount(365 days), discount);

        assertEq(baseFeed.owner(),           Ethereum.SPARK_PROXY);
        assertEq(address(baseFeed.source()), address(pendleOracle));
        assertEq(baseFeed.decimals(),        pendleOracle.decimals());

        ( , int256 pendlePrice, , , )   = pendleOracle.latestRoundData();
        ( , int256 baseFeedPrice, , , ) = baseFeed.latestRoundData();

        assertEq(baseFeedPrice, pendlePrice);

        uint256 blockTime = block.timestamp;
        uint256 price     = oracle_.price();

        vm.warp(blockTime + 1 days);

        assertApproxEqAbs(uint256(oracle_.price() - price) / 1e18, uint256(0.15e18) / 365, 1);

        vm.warp(maturity - 1 seconds);

        assertLe(oracle_.price(), 1e36 * assetConversion);

        vm.warp(maturity);

        assertEq(oracle_.price(), 1e36 * assetConversion);

        assertTrue(IMorphoOracleFactoryLike(MORPHO_ORACLE_FACTORY).isMorphoChainlinkOracleV2(address(oracle_)));

        address expectedPendleOracle = address(new PendleSparkLinearDiscountOracle(pt, discount));

        _assertBytecodeMatches(expectedPendleOracle, address(pendleOracle));

        address expectedBaseFeed = address(new MorphoUpgradableOracle{salt: bytes32(0)}(Ethereum.SPARK_PROXY, address(pendleOracle)));

        _assertBytecodeMatches(expectedBaseFeed, address(baseFeed));
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

}
