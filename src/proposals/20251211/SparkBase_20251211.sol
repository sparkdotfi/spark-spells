// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.25;

import { Base } from "spark-address-registry/Base.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { SparkPayloadBase } from "../../SparkPayloadBase.sol";

import { IMorphoVaultLike, IALMProxyFreezableLike } from "../../interfaces/Interfaces.sol";

/**
 * @title  December 11, 2025 Spark Base Proposal
 * @notice Spark USDC Morpho Vault - Update Allocator Role to ALM Proxy Freezable
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/december-11-2025-proposed-changes-to-spark-for-upcoming-spell/27481
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x9b21777dfa9f7628060443a046b76a5419740f692557ef45c92f6fac1ff31801
 */
contract SparkBase_20251211 is SparkPayloadBase {

    function execute() external {
        // Grant CONTROLLER Role for Relayer 1 and 2 on Base.ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxy         proxy = IALMProxy(Base.ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER);
        proxy.grantRole(proxy.CONTROLLER(),                               Base.ALM_RELAYER2);
        proxy.grantRole(IALMProxyFreezableLike(address(proxy)).FREEZER(), Base.ALM_FREEZER);

        // Spark USDC Morpho Vault - Update Allocator Role to ALM Proxy Freezable
        IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC).setIsAllocator(Base.ALM_PROXY_FREEZABLE, true);
    }

}
