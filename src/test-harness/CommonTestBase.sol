// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import 'forge-std/StdJson.sol';
import 'forge-std/Test.sol';
import {IERC20} from 'erc20-helpers/interfaces/IERC20.sol';

library ChainIds {
    uint256 internal constant MAINNET = 1;
    uint256 internal constant OPTIMISM = 10;
    uint256 internal constant GNOSIS = 100;
    uint256 internal constant POLYGON = 137;
    uint256 internal constant FANTOM = 250;
    uint256 internal constant METIS = 1088;
    uint256 internal constant BASE = 8453;
    uint256 internal constant ARBITRUM = 42161;
    uint256 internal constant AVALANCHE = 43114;
    uint256 internal constant HARMONY = 1666600000;
  }

contract CommonTestBase is Test {
  using stdJson for string;

  address public constant ETH_MOCK_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  address public constant EOA = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

  address public constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  address public constant EURE_GNOSIS  = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
  address public constant USDCE_GNOSIS = 0x2a22f9c3b484c3629090FeED35F17Ff8F88f76F0;

  address public constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

  /**
   * @notice deal doesn't support amounts stored in a script right now.
   * This function patches deal to mock and transfer funds instead.
   * @param asset the asset to deal
   * @param user the user to deal to
   * @param amount the amount to deal
   * @return bool true if the caller has changed due to prank usage
   */
  function _patchedDeal(address asset, address user, uint256 amount) internal returns (bool) {
    if (block.chainid == ChainIds.MAINNET) {
      // USDC
      if (asset == USDC_MAINNET) {
        vm.prank(0x28C6c06298d514Db089934071355E5743bf21d60);
        IERC20(asset).transfer(user, amount);
        return true;
      }
    } else if (block.chainid == ChainIds.GNOSIS) {
      // EURe
      if (asset == EURE_GNOSIS) {
        vm.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        IERC20(asset).transfer(user, amount);
        return true;
      }
      // USDC.e
      if (asset == USDCE_GNOSIS) {
        vm.prank(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        IERC20(asset).transfer(user, amount);
        return true;
      }
    } else if (block.chainid == ChainIds.BASE) {
      // USDC
      if (asset == USDC_BASE) {
        vm.prank(0x7C310a03f4CFa19F7f3d7F36DD3E05828629fa78);
        IERC20(asset).transfer(user, amount);
        return true;
      }
    }
    return false;
  }

  /**
   * Patched version of deal
   * @param asset to deal
   * @param user to deal to
   * @param amount to deal
   */
  function deal2(address asset, address user, uint256 amount) internal {
    bool patched = _patchedDeal(asset, user, amount);
    if (!patched) {
      deal(asset, user, amount);
    }
  }

  /**
   * @dev generates the diff between two reports
   */
  function diffReports(string memory reportBefore, string memory reportAfter) internal {
    string memory outPath = string(
      abi.encodePacked('./diffs/', reportBefore, '_', reportAfter, '.md')
    );
    string memory beforePath = string(abi.encodePacked('./reports/', reportBefore, '.json'));
    string memory afterPath = string(abi.encodePacked('./reports/', reportAfter, '.json'));

    string[] memory inputs = new string[](7);
    inputs[0] = 'npx';
    inputs[1] = '@marsfoundation/aave-cli';
    inputs[2] = 'diff-snapshots';
    inputs[3] = beforePath;
    inputs[4] = afterPath;
    inputs[5] = '-o';
    inputs[6] = outPath;
    vm.ffi(inputs);
  }

  /**
   * @dev forwards time by x blocks
   */
  function _skipBlocks(uint128 blocks) internal {
    vm.roll(block.number + blocks);
    vm.warp(block.timestamp + blocks * 12); // assuming a block is around 12seconds
  }

  function _isInUint256Array(
    uint256[] memory haystack,
    uint256 needle
  ) internal pure returns (bool) {
    for (uint256 i = 0; i < haystack.length; i++) {
      if (haystack[i] == needle) return true;
    }
    return false;
  }

  function _isInAddressArray(
    address[] memory haystack,
    address needle
  ) internal pure returns (bool) {
    for (uint256 i = 0; i < haystack.length; i++) {
      if (haystack[i] == needle) return true;
    }
    return false;
  }
}
