// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import '../../SparkTestBase.sol';

import { Ownable } from 'aave-v3-core/contracts/dependencies/openzeppelin/contracts/Ownable.sol';

import { SparkGoerli_20230830 } from './SparkGoerli_20230830.sol';

contract SparkGoerli_20230830Test is SparkGoerliTestBase {

    address internal constant PAUSE_PROXY                  = 0x5DCdbD3cCF9B09EAAD03bc5f50fA2B3d3ACA0121;
    address public   constant POOL_ADDRESSES_PROVIDER      = 0x026a5B6114431d8F3eF2fA0E1B2EDdDccA9c540E;
    IPool   public   constant POOL                         = IPool(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d);

    address public   constant WETH                         = 0x7D5afF7ab67b431cDFA6A94d50d3124cC4AB2611;
    uint256 public   constant OLD_WETH_OPTIMAL_USAGE_RATIO = 0.80e27;
    uint256 public   constant NEW_WETH_OPTIMAL_USAGE_RATIO = 0.90e27;
    uint256 public   constant OLD_WETH_INTEREST_RATE       = 0.030e27;
    uint256 public   constant NEW_WETH_INTEREST_RATE       = 0.038e27;

    address public   constant wstETH                       = 0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352;
    uint256 public   constant OLD_WSTETH_SUPPLY_CAP        = 200_000;
    uint256 public   constant NEW_WSTETH_SUPPLY_CAP        = 400_000;
    
    constructor() {
        id = '20230830';
    }

    function setUp() public {
        vm.createSelectFork(getChain('goerli').rpcUrl, 9_500_235);
        // For now deploying the payload in the test
        payload = deployPayload();

        // Temporarily keeping the setup from the previous spell - will update after its execution
        loadPoolContext(poolAddressesProviderRegistry.getAddressesProvidersList()[0]);
        vm.prank(PAUSE_PROXY);
        Ownable(address(poolAddressesProvider)).transferOwnership(address(executor));
    }

    function testSpellSpecifics() public {

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('pre-Spark-Goerli-20230830', POOL);
        
        /*******************************************/
        /*** wstETH Supply Cap Before Assertions ***/
        /*******************************************/
        
        ReserveConfig memory wstETHConfigBefore = _findReserveConfig(allConfigsBefore, wstETH);
        assertEq(wstETHConfigBefore.supplyCap, OLD_WSTETH_SUPPLY_CAP);

        /*****************************************************/
        /*** WETH Interest Rate Strategy Before Assertions ***/
        /*****************************************************/
        
        ReserveConfig memory WETHConfigBefore = _findReserveConfig(allConfigsBefore, WETH);
        IDefaultInterestRateStrategy interestRateStrategyBefore = IDefaultInterestRateStrategy(
            WETHConfigBefore.interestRateStrategy
        );

        _validateInterestRateStrategy(
            WETHConfigBefore.interestRateStrategy,
            WETHConfigBefore.interestRateStrategy,
            InterestStrategyValues({
                addressesProvider:             POOL_ADDRESSES_PROVIDER,
                optimalUsageRatio:             OLD_WETH_OPTIMAL_USAGE_RATIO,
                optimalStableToTotalDebtRatio: interestRateStrategyBefore.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(),
                baseStableBorrowRate:          OLD_WETH_INTEREST_RATE,
                stableRateSlope1:              interestRateStrategyBefore.getStableRateSlope1(),
                stableRateSlope2:              interestRateStrategyBefore.getStableRateSlope2(),
                baseVariableBorrowRate:        interestRateStrategyBefore.getBaseVariableBorrowRate(),
                variableRateSlope1:            OLD_WETH_INTEREST_RATE,
                variableRateSlope2:            interestRateStrategyBefore.getVariableRateSlope2()
            })
        );
        
        /***********************/
        /*** Execute Payload ***/
        /***********************/
        
        GovHelpers.executePayload(vm, payload, executor);

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('post-Spark-Goerli-20230830', POOL);
        
        /******************************************/
        /*** wstETH Supply Cap After Assertions ***/
        /******************************************/
        
        wstETHConfigBefore.supplyCap = NEW_WSTETH_SUPPLY_CAP;
        _validateReserveConfig(wstETHConfigBefore, allConfigsAfter);
        
        /****************************************************/
        /*** WETH Interest Rate Strategy After Assertions ***/
        /****************************************************/

        ReserveConfig memory WETHConfigAfter = _findReserveConfig(allConfigsAfter, WETH);

        _validateInterestRateStrategy(
            WETHConfigAfter.interestRateStrategy,
            WETHConfigAfter.interestRateStrategy,
            InterestStrategyValues({
                addressesProvider:             POOL_ADDRESSES_PROVIDER,
                optimalUsageRatio:             NEW_WETH_OPTIMAL_USAGE_RATIO,
                optimalStableToTotalDebtRatio: interestRateStrategyBefore.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO(),
                baseStableBorrowRate:          NEW_WETH_INTEREST_RATE,
                stableRateSlope1:              interestRateStrategyBefore.getStableRateSlope1(),
                stableRateSlope2:              interestRateStrategyBefore.getStableRateSlope2(),
                baseVariableBorrowRate:        interestRateStrategyBefore.getBaseVariableBorrowRate(),
                variableRateSlope1:            NEW_WETH_INTEREST_RATE,
                variableRateSlope2:            interestRateStrategyBefore.getVariableRateSlope2()
            })
        );
    }
}