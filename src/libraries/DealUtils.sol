// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.7.5 <0.9.0;

import { Vm } from "forge-std/Vm.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

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

    address internal constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant EURE_GNOSIS  = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    address internal constant USDCE_GNOSIS = 0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0;

    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address internal constant USDC_MAINNET_WHALE = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address internal constant EURE_GNOSIS_WHALE  = 0xbDA14C8F73773469a819C52C110FdC1A63884aDc;
    address internal constant USDCE_GNOSIS_WHALE = 0xB1EeAD6959cb5bB9B20417d6689922523B2B86C3;
    address internal constant USDC_BASE_WHALE    = 0x7C310a03f4CFa19F7f3d7F36DD3E05828629fa78;

    /**
     * @notice deal doesn't support amounts stored in a script right now.
     * This function patches deal to mock and transfer funds instead.
     * @param  asset  The asset to deal
     * @param  user   The user to deal to
     * @param  amount The amount to deal
     * @return bool   True if the caller has changed due to prank usage
     */
    function patchedDeal(address asset, address user, uint256 amount) internal returns (bool) {
        uint256 startingBalance = IERC20(asset).balanceOf(user);

        if (startingBalance == amount) return true;

        if (block.chainid == MAINNET) {
            // USDC
            if (asset == USDC_MAINNET) {
                VM.prank(amount > startingBalance ? USDC_MAINNET_WHALE : user);
                IERC20(asset).transfer(amount > startingBalance ? user : USDC_MAINNET_WHALE, amount);
                return true;
            }
        } else if (block.chainid == GNOSIS) {
            // EURe
            if (asset == EURE_GNOSIS) {
                VM.prank(amount > startingBalance ? EURE_GNOSIS_WHALE : user);
                IERC20(asset).transfer(amount > startingBalance ? user : EURE_GNOSIS_WHALE, amount);
                return true;
            }

            // USDC.e
            if (asset == USDCE_GNOSIS) {
                VM.prank(amount > startingBalance ? USDCE_GNOSIS_WHALE : user);
                IERC20(asset).transfer(amount > startingBalance ? user : USDCE_GNOSIS_WHALE, amount);
                return true;
            }
        } else if (block.chainid == BASE) {
            // USDC
            if (asset == USDC_BASE) {
                VM.prank(amount > startingBalance ? USDC_BASE_WHALE : user);
                IERC20(asset).transfer(amount > startingBalance ? user : USDC_BASE_WHALE, amount);
                return true;
            }
        }

        return false;
    }

}
