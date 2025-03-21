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
        // March 21, 2025
        setupDomains({
            mainnetForkBlock:     22095253,
            baseForkBlock:        27711491,  // Not used
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 316623039  // Not used
        });
        
        deployPayloads();
    }

}
