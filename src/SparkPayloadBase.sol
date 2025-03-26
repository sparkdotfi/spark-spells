// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Base } from 'spark-address-registry/Base.sol';

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { SparkLiquidityLayerHelpers } from './libraries/SparkLiquidityLayerHelpers.sol';

/**
 * @dev Base smart contract for Base Chain.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadBase {
    
    function _upgradeController(
        address oldController,
        address newController
    ) internal {
        SparkLiquidityLayerHelpers.upgradeForeignController(
            ControllerInstance({
                almProxy:    Base.ALM_PROXY,
                controller:  newController,
                rateLimits:  Base.ALM_RATE_LIMITS
            }),
            ForeignControllerInit.ConfigAddressParams({
                freezer:       Base.ALM_FREEZER,
                relayer:       Base.ALM_RELAYER,
                oldController: oldController
            }),
            ForeignControllerInit.CheckAddressParams({
                admin : Base.SPARK_EXECUTOR,
                psm   : Base.PSM3,
                cctp  : Base.CCTP_TOKEN_MESSENGER,
                usdc  : Base.USDC,
                susds : Base.SUSDS,
                usds  : Base.USDS
            })
        );
    }

    function _onboardAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardAaveToken(
            Base.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _onboardERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardERC4626Vault(
            Base.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _activateMorphoVault(address vault) internal {
        SparkLiquidityLayerHelpers.activateMorphoVault(
            vault,
            Base.ALM_RELAYER
        );
    }

}
