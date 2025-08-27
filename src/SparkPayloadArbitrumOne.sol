// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { SLLHelpers } from './libraries/SLLHelpers.sol';

/**
 * @dev Base smart contract for Arbitrum One.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadArbitrumOne {
    
    function _upgradeController(address oldController, address newController) internal {
        SLLHelpers.upgradeForeignController(
            ControllerInstance({
                almProxy:    Arbitrum.ALM_PROXY,
                controller:  newController,
                rateLimits:  Arbitrum.ALM_RATE_LIMITS
            }),
            ForeignControllerInit.ConfigAddressParams({
                freezer:       Arbitrum.ALM_FREEZER,
                relayer:       Arbitrum.ALM_RELAYER,
                oldController: oldController
            }),
            ForeignControllerInit.CheckAddressParams({
                admin : Arbitrum.SPARK_EXECUTOR,
                psm   : Arbitrum.PSM3,
                cctp  : Arbitrum.CCTP_TOKEN_MESSENGER,
                usdc  : Arbitrum.USDC,
                susds : Arbitrum.SUSDS,
                usds  : Arbitrum.USDS
            })
        );
    }

    function _configureAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureAaveToken(
            Arbitrum.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _configureERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureERC4626Vault(
            Arbitrum.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SLLHelpers.activateMorphoVault(
            vault,
            Arbitrum.ALM_RELAYER
        );
    }

}
