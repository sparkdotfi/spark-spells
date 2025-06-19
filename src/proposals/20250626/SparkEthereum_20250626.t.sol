// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { SparkTestBase } from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250626Test is SparkTestBase {

    address internal constant PT_USDE_25SEP2025                  = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a;
    address internal constant PT_USDE_25SEP2025_PRICE_FEED       = 0x076a476329CAf84Ef7FED997063a0055900eE00f;
    address internal constant PT_SYRUP_USDC_28AUG2025            = 0xCcE7D12f683c6dAe700154f0BAdf779C0bA1F89A;
    address internal constant PT_SYRUP_USDC_28AUG2025_PRICE_FEED = 0xdcC91883A87D336a2EEC0213E9167b4A6CD5b175;

    constructor() {
        id = "20250626";
    }

    function setUp() public {
        setupDomains("2025-06-19T16:40:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Ethereum()].payload = 0xF485e3351a4C3D7d1F89B1842Af625Fd0dFB90C8;
    }

    function test_ETHEREUM_morpho_PTSYRUPUSDC28AUG2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SYRUP_USDC_28AUG2025,
                oracle:          PT_SYRUP_USDC_28AUG2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     300_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_SYRUP_USDC_28AUG2025,
            loanToken: Ethereum.DAI,
            oracle:    PT_SYRUP_USDC_28AUG2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1756339200
        });
    }

    function test_ETHEREUM_morpho_PTUSDE25SEP2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_25SEP2025,
                oracle:          PT_USDE_25SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     500_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:        PT_USDE_25SEP2025,
            loanToken: Ethereum.DAI,
            oracle:    PT_USDE_25SEP2025_PRICE_FEED,
            discount:  0.15e18,
            maturity:  1758758400
        });
    }

}
