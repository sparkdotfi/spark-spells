// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { Avalanche } from "spark-address-registry/Avalanche.sol";

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { SLLHelpers } from "./libraries/SLLHelpers.sol";

/**
 * @dev    Base smart contract for Avalanche.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadAvalanche {

    function _upgradeController(address oldController, address newController) internal {
        address[] memory relayers = new address[](2);
        relayers[0] = Avalanche.ALM_RELAYER;
        relayers[1] = Avalanche.ALM_RELAYER2;

        SLLHelpers.upgradeForeignController(
            ControllerInstance({
                almProxy:    Avalanche.ALM_PROXY,
                controller:  newController,
                rateLimits:  Avalanche.ALM_RATE_LIMITS
            }),
            ForeignControllerInit.ConfigAddressParams({
                freezer:       Avalanche.ALM_FREEZER,
                relayers:      relayers,
                oldController: oldController
            }),
            ForeignControllerInit.CheckAddressParams({
                admin : Avalanche.SPARK_EXECUTOR,
                psm   : address(0),
                cctp  : Avalanche.CCTP_TOKEN_MESSENGER,
                usdc  : Avalanche.USDC,
                susds : address(0),
                usds  : address(0)
            }),
            false
        );
    }

    function _configureAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureAaveToken(
            Avalanche.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _configureERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureERC4626Vault(
            Avalanche.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SLLHelpers.activateMorphoVault(
            vault,
            Avalanche.ALM_RELAYER
        );
    }

}
