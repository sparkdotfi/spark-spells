// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMorpho, MarketParams, Id } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Position } from 'morpho-blue/src/interfaces/IMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { SparkTestBase } from '../../test-harness/SparkTestBase.sol';

contract SparkEthereum_20250626Test is SparkTestBase {

    address internal constant DESTINATION                        = 0x92e4629a4510AF5819d7D1601464C233599fF5ec;
    address internal constant PT_SYRUP_USDC_28AUG2025            = 0xCcE7D12f683c6dAe700154f0BAdf779C0bA1F89A;
    address internal constant PT_SYRUP_USDC_28AUG2025_PRICE_FEED = 0xdcC91883A87D336a2EEC0213E9167b4A6CD5b175;
    address internal constant PT_USDE_25SEP2025                  = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a;
    address internal constant PT_USDE_25SEP2025_PRICE_FEED       = 0x076a476329CAf84Ef7FED997063a0055900eE00f;

    uint256 internal constant TRANSFER_AMOUNT = 800_000e18;

    constructor() {
        id = "20250626";
    }

    function setUp() public {
        setupDomains("2025-06-20T16:35:00Z");

        deployPayloads();

        chainData[ChainIdUtils.Ethereum()].payload = 0x74e1ba852C864d689562b5977EedCB127fDE0C9F;

        deal(Ethereum.USDS, Ethereum.SPARK_PROXY, TRANSFER_AMOUNT);
    }

    function test_ETHEREUM_transferUSDS() public onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 destinationBalanceBefore = usds.balanceOf(DESTINATION);
        uint256 sparkProxyBalanceBefore  = usds.balanceOf(Ethereum.SPARK_PROXY);

        executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(DESTINATION),          destinationBalanceBefore + TRANSFER_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY), sparkProxyBalanceBefore  - TRANSFER_AMOUNT);
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

        Position memory position = IMorpho(Ethereum.MORPHO).position(
            Id.wrap(0xbd290578029fb5adc4a67b0a96ec409002478d1092e56429a00ed30a106de7f3),  // id of PT-syrupUSDC-28Aug2025/DAI
            address(1)
        );

        assertEq(position.supplyShares, 1e24);
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

        Position memory position = IMorpho(Ethereum.MORPHO).position(
            Id.wrap(0x45d97c66db5e803b9446802702f087d4293a2f74b370105dc3a88a278bf6bb21),  // id of PT-USDe-25Sept2025/DAI
            address(1)
        );

        assertEq(position.supplyShares, 1e24);
    }

}
