// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';

import { SparkLiquidityLayerHelpers } from './libraries/SparkLiquidityLayerHelpers.sol';

/**
 * @dev Base smart contract for Arbitrum One.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadArbitrumOne {

    function _onboardAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardAaveToken(
            Arbitrum.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _onboardERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardERC4626Vault(
            Arbitrum.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SparkLiquidityLayerHelpers.activateMorphoVault(
            vault,
            Arbitrum.ALM_RELAYER
        );
    }

}
