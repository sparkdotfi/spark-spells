// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, PendingUint192, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }          from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorphoChainlinkOracleV2 } from "morpho-blue-oracles/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol";

import { PendleSparkLinearDiscountOracle } from "pendle-core-v2-public/oracles/internal/PendleSparkLinearDiscountOracle.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MorphoUpgradableOracle }                                     from "sparklend-advanced/src/MorphoUpgradableOracle.sol";
import { IPoolAddressesProvider, RateTargetKinkInterestRateStrategy } from "sparklend-advanced/src/RateTargetKinkInterestRateStrategy.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { ISparkLendFreezerMom } from "sparklend-freezer/interfaces/ISparkLendFreezerMom.sol";

import { ReserveConfiguration, DataTypes } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }                      from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    ICustomIRMLike,
    IMorphoLike,
    IMorphoOracleFactoryLike,
    IPendleLinearDiscountOracleLike,
    IRateSourceLike,
    ITargetKinkIRMLike
} from "../interfaces/Interfaces.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SLLHelpers }            from "../libraries/SLLHelpers.sol";

import { SparklendTests }           from "./SparklendTests.sol";
import { SparkLiquidityLayerTests } from "./SparkLiquidityLayerTests.sol";
import { SpellRunner }              from "./SpellRunner.sol";

// TODO: MDL, only used by `SparkTestBase`.
/// @dev assertions specific to mainnet
/// TODO: separate tests related to sparklend from the rest (eg: morpho)
///       also separate mainnet-specific sparklend tests from those we should
///       run on Gnosis as well
abstract contract SparkEthereumTests is SparklendTests, SparkLiquidityLayerTests {

    using RecordedLogs for *;

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    struct RateTargetKinkIRMParams {
        address irm;
        uint256 baseRate;
        int256  variableRateSlope1Spread;
        uint256 variableRateSlope2;
        uint256 optimalUsageRatio;
    }

    address internal constant MORPHO_ORACLE_FACTORY = 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766;

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    // TODO: MDL, seems to be SLL, but may be neither.
    function _testMorphoCapUpdate(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             newCap
    )
        internal
    {
        _assertMorphoCap(vault, config, currentCap);
        _executeAllPayloadsAndBridges();

        if (newCap > currentCap) {
            // Increases are timelocked
            _assertMorphoCap(vault, config, currentCap, newCap);

            assertEq(IMetaMorpho(vault).timelock(), 1 days);

            skip(1 days);

            IMetaMorpho(vault).acceptCap(config);

            _assertMorphoCap(vault, config, newCap);
        } else {
            // Decreases are immediate
            _assertMorphoCap(vault, config, newCap);
        }

        // Check total assets in the morpho market are greater than 1 unit of the loan token
        ( uint256 totalSupplyAssets_, , , , , ) = IMorphoLike(Ethereum.MORPHO).market(MarketParamsLib.id(config));
        assertGe(totalSupplyAssets_, 10 ** IERC20(config.loanToken).decimals());

        // Check shares of address(1) are greater or equal to 1e6 * 10 ** loanTokenDecimals (1 unit)
        IMorphoLike.Position memory position = IMorphoLike(Ethereum.MORPHO).position(MarketParamsLib.id(config), address(1));
        assertGe(position.supplyShares, 10 ** IERC20(config.loanToken).decimals() * 1e6);
    }

    // TODO: MDL, seems to be SLL, but may be neither.
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

    // TODO: MDL, seems to be Sparklend.
    function _testRateTargetKinkIRMUpdate(
        string                  memory symbol,
        RateTargetKinkIRMParams memory oldParams,
        RateTargetKinkIRMParams memory newParams
    )
        internal
    {
        SparkLendContext memory ctx = _getSparkLendContext();

        // Rate source should be the same
        assertEq(ICustomIRMLike(newParams.irm).RATE_SOURCE(), ICustomIRMLike(oldParams.irm).RATE_SOURCE());

        uint256 ssrRateDecimals = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).decimals();

        int256 ssrRate = IRateSourceLike(ICustomIRMLike(newParams.irm).RATE_SOURCE()).getAPR() * int256(10 ** (27 - ssrRateDecimals));

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configBefore = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configBefore.interestRateStrategy,
            oldParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             oldParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + oldParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        oldParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + oldParams.variableRateSlope1Spread),
                variableRateSlope2:            oldParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configBefore.interestRateStrategy).getVariableRateSlope1Spread()), uint256(oldParams.variableRateSlope1Spread));

        _executeAllPayloadsAndBridges();

        // TODO: MDL, not writing to config, so we don't need a clone.
        ReserveConfig memory configAfter = _findReserveConfigBySymbol(_createConfigurationSnapshot("", ctx.pool), symbol);

        _validateInterestRateStrategy(
            configAfter.interestRateStrategy,
            newParams.irm,
            InterestStrategyValues({
                addressesProvider:             address(ctx.poolAddressesProvider),
                optimalUsageRatio:             newParams.optimalUsageRatio,
                optimalStableToTotalDebtRatio: 0,
                baseStableBorrowRate:          uint256(ssrRate + newParams.variableRateSlope1Spread),
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseVariableBorrowRate:        newParams.baseRate,
                variableRateSlope1:            uint256(ssrRate + newParams.variableRateSlope1Spread),
                variableRateSlope2:            newParams.variableRateSlope2
            })
        );

        assertEq(uint256(ITargetKinkIRMLike(configAfter.interestRateStrategy).getVariableRateSlope1Spread()), uint256(newParams.variableRateSlope1Spread));

        address expectedIRM = address(new RateTargetKinkInterestRateStrategy(
            IPoolAddressesProvider(address(ctx.poolAddressesProvider)),
            ICustomIRMLike(newParams.irm).RATE_SOURCE(),
            newParams.optimalUsageRatio,
            newParams.baseRate,
            newParams.variableRateSlope1Spread,
            newParams.variableRateSlope2
        ));

        _assertBytecodeMatches(expectedIRM, newParams.irm);
    }

    // TODO: MDL, seems to be SLL, but may be neither.
    function _testMorphoVaultCreation(
        address               asset,
        string         memory name,
        string         memory symbol,
        MarketParams[] memory markets,
        uint256[]      memory caps,
        uint256               vaultFee,
        uint256               initialDeposit,
        uint256               sllDepositMax,
        uint256               sllDepositSlope
    )
        internal
    {
        require(markets.length == caps.length, "Markets and caps length mismatch");

        // TODO: make constant.
        bytes32 createMetaMorphoSig = keccak256("CreateMetaMorpho(address,address,address,uint256,address,string,string,bytes32)");

        // Start the recorder
        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        VmSafe.Log[] memory allLogs = RecordedLogs.getLogs();

        // TODO: make below loop a getter with a return to make this all cleaner. Possibly incorporating the zero check.
        address vault;

        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics[0] == createMetaMorphoSig) {
                vault = address(uint160(uint256(allLogs[i].topics[1])));
                break;
            }
        }

        require(vault != address(0), "Vault not found");

        assertEq(IMetaMorpho(vault).asset(),                           asset);
        assertEq(IMetaMorpho(vault).name(),                            name);
        assertEq(IMetaMorpho(vault).symbol(),                          symbol);
        assertEq(IMetaMorpho(vault).timelock(),                        1 days);
        assertEq(IMetaMorpho(vault).isAllocator(Ethereum.ALM_RELAYER), true);
        assertEq(IMetaMorpho(vault).supplyQueueLength(),               1);
        assertEq(IMetaMorpho(vault).owner(),                           Ethereum.SPARK_PROXY);
        assertEq(IMetaMorpho(vault).feeRecipient(),                    Ethereum.ALM_PROXY);
        assertEq(IMetaMorpho(vault).fee(),                             vaultFee);

        for (uint256 i = 0; i < markets.length; ++i) {
            _assertMorphoCap(vault, markets[i], caps[i]);
        }

        assertEq(
            Id.unwrap(IMetaMorpho(vault).supplyQueue(0)),
            Id.unwrap(MarketParamsLib.id(SLLHelpers.morphoIdleMarket(asset)))
        );

        _assertMorphoCap(vault, SLLHelpers.morphoIdleMarket(asset), type(uint184).max);

        assertEq(IMetaMorpho(vault).totalAssets(),    initialDeposit);
        assertEq(IERC20(vault).balanceOf(address(1)), initialDeposit * 1e18 / 10 ** IERC20(asset).decimals());

        if (sllDepositMax == 0 || sllDepositSlope == 0) return;

        _testERC4626Onboarding(vault, sllDepositMax / 10, sllDepositMax, sllDepositSlope, 10, true);
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _assertBorrowCapConfigNotSet(address asset) internal view {
        _assertBorrowCapConfig(asset, 0, 0, 0);
    }

    function _assertSupplyCapConfigNotSet(address asset) internal view {
        _assertSupplyCapConfig(asset, 0, 0, 0);
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        bool                hasPending,
        uint256             pendingCap
    ) internal view {
        Id id = MarketParamsLib.id(config);

        assertEq(IMetaMorpho(vault).config(id).cap, currentCap);

        PendingUint192 memory pendingCap_ = IMetaMorpho(vault).pendingCap(id);

        if (hasPending) {
            assertEq(pendingCap_.value,   pendingCap);
            assertGt(pendingCap_.validAt, 0);
        } else {
            assertEq(pendingCap_.value,   0);
            assertEq(pendingCap_.validAt, 0);
        }
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             pendingCap
    ) internal view {
        _assertMorphoCap(vault, config, currentCap, true, pendingCap);
    }

    function _assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap
    ) internal view {
        _assertMorphoCap(vault, config, currentCap, false, 0);
    }

}
