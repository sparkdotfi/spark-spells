// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { RateLimitData }     from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

import { ReserveConfig }    from '../../test-harness/ProtocolV3TestBase.sol';
import { SparkLendContext } from '../../test-harness/SparklendTests.sol';

contract SparkEthereum_20250417Test is SparkTestBase {

    address constant DAI_IRM_OLD  = 0x5a7E7a32331189a794ac33Fec76C0A1dD3dDCF9c;
    address constant USDC_IRM_OLD = 0x0F1a9a787b4103eF5929121CD9399224c6455dD6;
    address constant USDS_IRM_OLD = 0xD94BA511284d2c56F59a687C3338441d33304E07;
    address constant USDT_IRM_OLD = 0x0F1a9a787b4103eF5929121CD9399224c6455dD6;

    address constant DAI_USDS_IRM  = 0x7729E1CE24d7c4A82e76b4A2c118E328C35E6566;  // DAI  and USDS use the same params, same IRM
    address constant USDC_USDT_IRM = 0x7F2fc6A7E3b3c658A84999b26ad2013C4Dc87061;  // USDC and USDT use the same params, same IRM

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

}
