// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { DataTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { ForeignController } from 'spark-alm-controller/src/ForeignController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';
import { IRateLimits }       from 'spark-alm-controller/src/interfaces/IRateLimits.sol';

import { ReserveConfig } from "src/test-harness/ProtocolV3TestBase.sol";
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

contract SparkEthereum_20250403Test is SparkTestBase {

    constructor() {
        id = '20250403';
    }

    function setUp() public {
        // March 25, 2025
        setupDomains({
            mainnetForkBlock:     22124252,
            baseForkBlock:        28060210,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 319402704
        });
        
        deployPayloads();
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c
        });
    }

}
