// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IMetaMorpho, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";

library MorphoHelpers {

    /**
     * @notice Submit a Morpho vault cap with a standard amount (without decimals)
     * @param vault The MetaMorpho vault address
     * @param params The market parameters
     * @param standardAmount The cap amount in standard units (e.g., 1_000_000_000 for 1B tokens)
     * @dev Automatically converts the standard amount to the loan token's decimal representation
     */
    function submitMorphoCap(
        address             vault,
        MarketParams memory params,
        uint256             standardAmount
    ) internal {
        uint256 decimals = IERC20(params.loanToken).decimals();
        uint256 cap      = standardAmount * (10 ** decimals);
        
        IMetaMorpho(vault).submitCap(params, cap);
    }

}
