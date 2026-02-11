// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { Optimism } from "spark-address-registry/Optimism.sol";

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { SLLHelpers } from "./libraries/SLLHelpers.sol";

/**
 * @dev    Base smart contract for Optimism.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadOptimism {

    function _upgradeController(address oldController, address newController) internal {
        address[] memory relayers = new address[](2);
        relayers[0] = Optimism.ALM_RELAYER_MULTISIG;
        relayers[1] = Optimism.ALM_BACKSTOP_RELAYER_MULTISIG;

        SLLHelpers.upgradeForeignController(
            ControllerInstance({
                almProxy   : Optimism.ALM_PROXY,
                controller : newController,
                rateLimits : Optimism.ALM_RATE_LIMITS
            }),
            ForeignControllerInit.ConfigAddressParams({
                freezer       : Optimism.ALM_FREEZER_MULTISIG,
                relayers      : relayers,
                oldController : oldController
            }),
            ForeignControllerInit.CheckAddressParams({
                admin : Optimism.SPARK_EXECUTOR,
                psm   : Optimism.PSM3,
                cctp  : Optimism.CCTP_TOKEN_MESSENGER,
                usdc  : Optimism.USDC,
                susds : Optimism.SUSDS,
                usds  : Optimism.USDS
            }),
            true
        );
    }

    function _configureAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureAaveToken(
            Optimism.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _configureERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureERC4626Vault(
            Optimism.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SLLHelpers.activateMorphoVault(
            vault,
            Optimism.ALM_RELAYER_MULTISIG
        );
    }

}
