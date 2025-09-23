// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import { Vm } from 'forge-std/Vm.sol';

import { IERC20 } from 'erc20-helpers/interfaces/IERC20.sol';

library DealUtils {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant MAINNET   = 1;
    uint256 internal constant OPTIMISM  = 10;
    uint256 internal constant GNOSIS    = 100;
    uint256 internal constant POLYGON   = 137;
    uint256 internal constant FANTOM    = 250;
    uint256 internal constant METIS     = 1088;
    uint256 internal constant BASE      = 8453;
    uint256 internal constant ARBITRUM  = 42161;
    uint256 internal constant AVALANCHE = 43114;
    uint256 internal constant HARMONY   = 1666600000;

    address public constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant EURE_GNOSIS  = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    address public constant USDCE_GNOSIS = 0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0;

    address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /**
     * @notice deal doesn't support amounts stored in a script right now.
     * This function patches deal to mock and transfer funds instead.
     * @param  asset  The asset to deal
     * @param  user   The user to deal to
     * @param  amount The amount to deal
     * @return bool   True if the caller has changed due to prank usage
     */
    function _patchedDeal(address asset, address user, uint256 amount) internal returns (bool) {
        if (block.chainid == MAINNET) {
            // USDC
            if (asset == USDC_MAINNET) {
                VM.prank(0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341);  // USDC whale
                IERC20(asset).transfer(user, amount);
                return true;
            }
        } else if (block.chainid == GNOSIS) {
            // EURe
            if (asset == EURE_GNOSIS) {
                VM.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);  // EURe whale
                IERC20(asset).transfer(user, amount);
                return true;
            }

            // USDC.e
            if (asset == USDCE_GNOSIS) {
                VM.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);  // USDC.e whale
                IERC20(asset).transfer(user, amount);
                return true;
            }
        } else if (block.chainid == BASE) {
            // USDC
            if (asset == USDC_BASE) {
                VM.prank(0x7C310a03f4CFa19F7f3d7F36DD3E05828629fa78);  // Base USDC whale
                IERC20(asset).transfer(user, amount);
                return true;
            }
        }

        return false;
    }

    /**
     * Patched version of deal
     * @param asset  The asset to deal
     * @param user   The user to deal to
     * @param amount The amount to deal
     */
    function deal(address asset, address user, uint256 amount) internal {
        if (_patchedDeal(asset, user, amount)) return;

        deal(asset, user, amount);
    }

}
