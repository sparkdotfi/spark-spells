// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.23;

import { VmSafe } from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, PendingUint192, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

library MorphoHelpers {

    VmSafe internal constant VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        bool                hasPending,
        uint256             pendingCap
    ) internal view {
        Id id = MarketParamsLib.id(config);

        VM.assertEq(IMetaMorpho(vault).config(id).cap, currentCap);

        PendingUint192 memory pendingCap_ = IMetaMorpho(vault).pendingCap(id);

        if (hasPending) {
            VM.assertEq(pendingCap_.value,   pendingCap);
            VM.assertGt(pendingCap_.validAt, 0);
        } else {
            VM.assertEq(pendingCap_.value,   0);
            VM.assertEq(pendingCap_.validAt, 0);
        }
    }

    function assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap,
        uint256             pendingCap
    ) internal view {
        assertMorphoCap(vault, config, currentCap, true, pendingCap);
    }

    function assertMorphoCap(
        address             vault,
        MarketParams memory config,
        uint256             currentCap
    ) internal view {
        assertMorphoCap(vault, config, currentCap, false, 0);
    }

}
