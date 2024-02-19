// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { SparkPayloadEthereum } from '../../SparkPayloadEthereum.sol';
import { IACLManager } from 'aave-v3-core/contracts/interfaces/IACLManager.sol';

/**
 * @title  March 06, 2024 Spark Ethereum Proposal - Activate Cap Automator
 * @author Phoenix Labs
 * @dev    This proposal activates the Cap Automator
 * Forum:  TODO
 * Vote:   TODO
 */
contract SparkEthereum_20240306 is SparkPayloadEthereum {

    address public constant ACL_MANAGER   = 0xdA135Cd78A086025BcdC87B038a1C462032b510C;
    address public constant CAP_AUTOMATOR = 0xdA135Cd78A086025BcdC87B038a1C462032b510C; // TODO: Replace with the actual address

    function _postExecute() internal override {
        IACLManager(ACL_MANAGER).addRiskAdmin(CAP_AUTOMATOR);
    }

}
