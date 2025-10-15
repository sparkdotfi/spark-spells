// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.7.5 <0.9.0;

import { Vm } from "forge-std/Vm.sol";

library ProxyHelpers {

    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getInitializableAdminUpgradeabilityProxyAdmin(
        address proxy
    ) internal view returns (address) {
        return address(
            uint160(
                uint256(VM.load(proxy, 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103))
            )
        );
    }

    function getInitializableAdminUpgradeabilityProxyImplementation(
        address proxy
    ) internal view returns (address) {
        return address(
            uint160(
                uint256(VM.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc))
            )
        );
    }

}
