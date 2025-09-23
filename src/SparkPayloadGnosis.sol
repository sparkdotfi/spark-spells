// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { AaveV3PayloadBase, IEngine } from './AaveV3PayloadBase.sol';

import { Gnosis } from 'spark-address-registry/Gnosis.sol';

/**
 * @dev Base smart contract for Gnosis Chain.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadGnosis is
    AaveV3PayloadBase(IEngine(Gnosis.CONFIG_ENGINE))
{
    function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
        return IEngine.PoolContext({networkName: 'Gnosis Chain', networkAbbreviation: 'Gno'});
    }
}
