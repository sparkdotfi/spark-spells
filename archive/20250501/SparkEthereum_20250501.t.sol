// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import '../../../src/test-harness/SparkTestBase.sol';

import { ChainIdUtils } from '../../../src/libraries/ChainId.sol';

contract SparkEthereum_20250417Test is SparkTestBase {

    address constant DAI_IRM_OLD  = 0x5a7E7a32331189a794ac33Fec76C0A1dD3dDCF9c;
    address constant USDC_IRM_OLD = 0xb7b734CF1F13652E930f8a604E8f837f85160174;
    address constant USDS_IRM_OLD = 0xD94BA511284d2c56F59a687C3338441d33304E07;
    address constant USDT_IRM_OLD = 0xb7b734CF1F13652E930f8a604E8f837f85160174;

    address constant DAI_USDS_IRM  = 0x7729E1CE24d7c4A82e76b4A2c118E328C35E6566;  // DAI  and USDS use the same params, same IRM
    address constant USDC_USDT_IRM = 0x7F2fc6A7E3b3c658A84999b26ad2013C4Dc87061;  // USDC and USDT use the same params, same IRM

    address constant AAVE_CORE_AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;

    constructor() {
        id = "20250501";
    }

    function setUp() public {
        setupDomains("2025-04-23T17:20:00Z");

        deployPayloads();
    }

    function test_ETHEREUM_sparkLend_daiIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : DAI_IRM_OLD,
            baseRateSpread     : 0.005e27,
            variableRateSlope1 : 0,
            variableRateSlope2 : 0,
            optimalUsageRatio  : 1e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : DAI_USDS_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.0075e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.8e27
        });
        _testRateTargetBaseIRMUpdate("DAI", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdsIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : USDS_IRM_OLD,
            baseRateSpread     : 0.005e27,
            variableRateSlope1 : 0,
            variableRateSlope2 : 0.2e27,
            optimalUsageRatio  : 1e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : DAI_USDS_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.0075e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.8e27
        });
        _testRateTargetBaseIRMUpdate("USDS", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdcIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDC_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDC", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() public onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : USDT_IRM_OLD,
            baseRate                 : 0,
            variableRateSlope1Spread : 0,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : USDC_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.01e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdtOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding({
            aToken:                Ethereum.USDT_ATOKEN,
            expectedDepositAmount: 25_000_000e6,
            depositMax:            100_000_000e6,
            depositSlope:          50_000_000e6 / uint256(1 days)
        });
    }

    function test_ETHEREUM_aaveCore_usdtOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding({
            aToken:                AAVE_CORE_AUSDT,
            expectedDepositAmount: 25_000_000e6,
            depositMax:            50_000_000e6,
            depositSlope:          25_000_000e6 / uint256(1 days)
        });
    }

    function test_ETHEREUM_sparkLend_usdtCapAutomatorUpdates() public onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDT, 0,          0,         0);  // Not set up
        _assertBorrowCapConfig(Ethereum.USDT, 28_500_000, 3_000_000, 12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDT, 500_000_000, 100_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 450_000_000, 50_000_000,  12 hours);
    }

}
