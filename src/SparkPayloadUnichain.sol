// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Unichain } from 'spark-address-registry/Unichain.sol';

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { SLLHelpers } from './libraries/SLLHelpers.sol';

/**
 * @dev Base smart contract for Unichain.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadUnichain {
    
    function _upgradeController(address oldController, address newController) internal {
        SLLHelpers.upgradeForeignController(
            ControllerInstance({
                almProxy:    Unichain.ALM_PROXY,
                controller:  newController,
                rateLimits:  Unichain.ALM_RATE_LIMITS
            }),
            ForeignControllerInit.ConfigAddressParams({
                freezer:       Unichain.ALM_FREEZER,
                relayer:       Unichain.ALM_RELAYER,
                oldController: oldController
            }),
            ForeignControllerInit.CheckAddressParams({
                admin : Unichain.SPARK_EXECUTOR,
                psm   : Unichain.PSM3,
                cctp  : Unichain.CCTP_TOKEN_MESSENGER,
                usdc  : Unichain.USDC,
                susds : Unichain.SUSDS,
                usds  : Unichain.USDS
            })
        );
    }

    function _onboardAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.onboardAaveToken(
            Unichain.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _onboardERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.onboardERC4626Vault(
            Unichain.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SLLHelpers.activateMorphoVault(
            vault,
            Unichain.ALM_RELAYER
        );
    }

}
