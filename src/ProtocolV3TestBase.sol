// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5 <0.9.0;

import 'forge-std/Test.sol';

import { IAaveOracle }                  from 'sparklend-v1-core/contracts/interfaces/IAaveOracle.sol';
import { IAToken }                      from 'sparklend-v1-core/contracts/interfaces/IAToken.sol';
import { IDefaultInterestRateStrategy } from 'sparklend-v1-core/contracts/interfaces/IDefaultInterestRateStrategy.sol';
import { IPool }                        from 'sparklend-v1-core/contracts/interfaces/IPool.sol';
import { IPoolAddressesProvider }       from 'sparklend-v1-core/contracts/interfaces/IPoolAddressesProvider.sol';
import { IPoolConfigurator }            from 'sparklend-v1-core/contracts/interfaces/IPoolConfigurator.sol';
import { IPoolDataProvider }            from 'sparklend-v1-core/contracts/interfaces/IPoolDataProvider.sol';
import { IStableDebtToken }             from 'sparklend-v1-core/contracts/interfaces/IStableDebtToken.sol';
import { IVariableDebtToken }           from 'sparklend-v1-core/contracts/interfaces/IVariableDebtToken.sol';

import { ReserveConfiguration } from 'sparklend-v1-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import { WadRayMath }           from 'sparklend-v1-core/contracts/protocol/libraries/math/WadRayMath.sol';
import { DataTypes }            from 'sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Gnosis }   from 'spark-address-registry/Gnosis.sol';

import { IERC20 }    from 'erc20-helpers/interfaces/IERC20.sol';
import { SafeERC20 } from 'erc20-helpers/SafeERC20.sol';

import { ICapAutomator }  from 'sparklend-cap-automator/interfaces/ICapAutomator.sol';

import { ProxyHelpers }   from './libraries/ProxyHelpers.sol';
import { CommonTestBase } from './CommonTestBase.sol';

interface IProxyLike {
  function implementation() external view returns (address);
}

interface IOracleLike {
  function DECIMALS() external view returns (uint8);
  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function name() external view returns (string memory);
  function version() external view returns (uint256);
  function latestAnswer() external view returns (int256);
}

struct ReserveConfig {
  string symbol;
  address underlying;
  address aToken;
  address stableDebtToken;
  address variableDebtToken;
  uint256 decimals;
  uint256 ltv;
  uint256 liquidationThreshold;
  uint256 liquidationBonus;
  uint256 liquidationProtocolFee;
  uint256 reserveFactor;
  bool usageAsCollateralEnabled;
  bool borrowingEnabled;
  address interestRateStrategy;
  bool stableBorrowRateEnabled;
  bool isPaused;
  bool isActive;
  bool isFrozen;
  bool isSiloed;
  bool isBorrowableInIsolation;
  bool isFlashloanable;
  uint256 supplyCap;
  uint256 borrowCap;
  uint256 debtCeiling;
  uint256 eModeCategory;
}

struct LocalVars {
  IPoolDataProvider.TokenData[] reserves;
  ReserveConfig[] configs;
}

struct InterestStrategyValues {
  address addressesProvider;
  uint256 optimalUsageRatio;
  uint256 optimalStableToTotalDebtRatio;
  uint256 baseStableBorrowRate;
  uint256 stableRateSlope1;
  uint256 stableRateSlope2;
  uint256 baseVariableBorrowRate;
  uint256 variableRateSlope1;
  uint256 variableRateSlope2;
}

struct LiquidationBalanceAssertions {
  uint256 aTokenBorrowerBefore;
  uint256 collateralATokenBefore;
  uint256 aTokenTreasuryBefore;
  uint256 collateralLiquidatorBefore;
  uint256 debtBefore;
  uint256 borrowATokenBefore;
  uint256 borrowLiquidatorBefore;
  uint256 aTokenBorrowerAfter;
  uint256 collateralATokenAfter;
  uint256 aTokenTreasuryAfter;
  uint256 collateralLiquidatorAfter;
  uint256 debtAfter;
  uint256 borrowATokenAfter;
  uint256 borrowLiquidatorAfter;
}

struct ReserveTokens {
  address aToken;
  address stableDebtToken;
  address variableDebtToken;
}

contract ProtocolV3TestBase is CommonTestBase {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
  using SafeERC20 for IERC20;
  using WadRayMath for uint256;

  /**
   * @dev Generates a markdown compatible snapshot of the whole pool configuration into `/reports`.
   * @param reportName filename suffix for the generated reports.
   * @param pool the pool to be snapshotted
   * @return ReserveConfig[] list of configs
   */
  function createConfigurationSnapshot(
    string memory reportName,
    IPool pool
  ) public returns (ReserveConfig[] memory) {
    return createConfigurationSnapshot(reportName, pool, true, true, true, true);
  }

  function createConfigurationSnapshot(
    string memory reportName,
    IPool pool,
    bool reserveConfigs,
    bool strategyConfigs,
    bool eModeConigs,
    bool poolConfigs
  ) public returns (ReserveConfig[] memory) {
    string memory path = string(abi.encodePacked('./reports/', reportName, '.json'));
    // overwrite with empty json to later be extended
    vm.writeFile(
      path,
      '{ "eModes": {}, "reserves": {}, "strategies": {}, "poolConfiguration": {} }'
    );
    vm.serializeUint('root', 'chainId', block.chainid);
    ReserveConfig[] memory configs = _getReservesConfigs(pool);
    if (reserveConfigs) _writeReserveConfigs(path, configs, pool);
    if (strategyConfigs) _writeStrategyConfigs(path, configs);
    if (eModeConigs) _writeEModeConfigs(path, configs, pool);
    if (poolConfigs) _writePoolConfiguration(path, pool);

    return configs;
  }

  /**
   * @dev Makes an e2e test performing a deposit, borrow, repay and withdraw for all permutations
   *      of collateral and borrow assets.
   * @param pool T he pool that should be tested
   */
  function e2eTest(IPool pool) public {
    uint256 snapshot = vm.snapshot();

    ReserveConfig[] memory configs = _getReservesConfigs(pool);

    for (uint256 i = 0; i < configs.length; i++) {
      if (!_includeCollateralAssetInE2e(configs[i])) {
        console.log('Skip collateral: %s, not configured', configs[i].symbol);
        continue;
      }

      for(uint256 j; j < configs.length; j++) {
        if (!_includeBorrowAssetInE2e(configs[j])) {
          console.log('Skip borrow: %s, not configured', configs[i].symbol);
          continue;
        }

        e2eTestAsset(pool, configs[i], configs[j]);
        vm.revertTo(snapshot);
      }
    }
  }

  function e2eTestAsset(
    IPool pool,
    ReserveConfig memory collateralConfig,
    ReserveConfig memory borrowConfig
  ) public {
    console.log(
      '\n\nE2E: Collateral %s, borrow %s',
      collateralConfig.symbol,
      borrowConfig.symbol
    );

    address collateralSupplier = vm.addr(3);
    address borrowSupplier     = vm.addr(4);
    address liquidator         = vm.addr(5);

    uint256 collateralAmount = _getTokenAmountByDollarValue(pool, collateralConfig, 110_000);
    uint256 borrowSeedAmount = _getTokenAmountByDollarValue(pool, borrowConfig,     100_000);

    uint256 maxBorrowAmount = _getMaxBorrowAmount(
      pool, collateralConfig, borrowConfig, collateralAmount
    );

    uint256 totalBorrowAssetSupplied = borrowConfig.underlying == collateralConfig.underlying
      ? collateralAmount * 2 + borrowSeedAmount + maxBorrowAmount
      : borrowSeedAmount + maxBorrowAmount;

      uint256 totalCollateralAssetSupplied = borrowConfig.underlying == collateralConfig.underlying
      ? collateralAmount * 2 + borrowSeedAmount + maxBorrowAmount
      : collateralAmount * 2;

    if (_isAboveSupplyCap(collateralConfig, totalCollateralAssetSupplied)) {
      console.log('Skip collateral: %s, supply cap fully utilized', collateralConfig.symbol);
      return;
    }
    if (
      _isAboveSupplyCap(borrowConfig, totalBorrowAssetSupplied)
    ) {
      console.log('Skip borrow: %s, supply cap fully utilized', borrowConfig.symbol);
      return;
    }

    if (
      _isAboveBorrowCap(pool, borrowConfig, maxBorrowAmount)
    ) {
      console.log('Skip borrow: %s, borrow cap fully utilized', borrowConfig.symbol);
      return;
    }

    if (collateralConfig.debtCeiling > 0 && !borrowConfig.isBorrowableInIsolation) {
      console.log('Skip: %s-%s combo, asset not supported for isolated borrow', collateralConfig.symbol, borrowConfig.symbol);
      return;
    }

    // Seed pool with assets to maximize precision in calculations (dusty markets reduce precision in general assertions)
    _supply(collateralConfig, pool, address(this), collateralAmount);
    _supply(borrowConfig,     pool, address(this), borrowSeedAmount);

    // Set up collateral and borrow amounts
    _supply(collateralConfig, pool, collateralSupplier, collateralAmount);
    _supply(borrowConfig,     pool, borrowSupplier,     maxBorrowAmount);

    if (collateralConfig.debtCeiling > 0) {
      // Need to enable as collateral before borrowing for assets in isolation mode
      vm.prank(collateralSupplier);
      pool.setUserUseReserveAsCollateral(collateralConfig.underlying, true);
    }

    uint256 snapshot = vm.snapshot();

    // Test 1: Ensure user can't borrow more than LTV

    _e2eTestBorrowAboveLTV(pool, collateralSupplier, borrowConfig, maxBorrowAmount);
    vm.revertTo(snapshot);

    // Test 2: Ensure user can borrow and repay with variable rates

    _e2eTestBorrowRepayWithdraw(pool, collateralSupplier, collateralConfig, borrowConfig, maxBorrowAmount);
    vm.revertTo(snapshot);

    // Test 3: Ensure user cannot borrow with stable rates (Use 95% of max
    // borrow because of warping in test)

    _e2eTestStableBorrowDisabled(pool, collateralSupplier, borrowConfig, maxBorrowAmount * uint256(95) / 100);
    vm.revertTo(snapshot);

    // Test 4: Test liquidation

    _e2eTestLiquidationReceiveCollateral(pool, collateralSupplier, liquidator, collateralConfig, borrowConfig, maxBorrowAmount);
    vm.revertTo(snapshot);

    // Test 5: Test flashloan

    _e2eTestFlashLoan(pool, borrowConfig, maxBorrowAmount);
    vm.revertTo(snapshot);

    // Test 6: Test mintToTreasury

    _e2eTestMintToTreasury(pool, borrowConfig);
    vm.revertTo(snapshot);
  }

  /**
   * Reserves that are frozen or not active should not be included in e2e test suite
   */
  function _includeBorrowAssetInE2e(ReserveConfig memory config) internal pure returns (bool) {
    return !config.isFrozen && config.isActive && !config.isPaused && config.borrowingEnabled;
  }

  function _includeCollateralAssetInE2e(ReserveConfig memory config) internal pure returns (bool) {
    return !config.isFrozen && config.isActive && !config.isPaused && config.usageAsCollateralEnabled && config.ltv > 0;
  }

  function _getTokenPrice(IPool pool, ReserveConfig memory config) internal view returns (uint256) {
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    return oracle.getAssetPrice(config.underlying);
  }

  function _getTokenAmountByDollarValue(
    IPool pool,
    ReserveConfig memory config,
    uint256 dollarValue
  ) internal view returns (uint256) {
    uint256 price = _getTokenPrice(pool, config);

    return (dollarValue * 10 ** (8 + config.decimals)) / price;
  }

  function _getMaxBorrowAmount(
    IPool pool,
    ReserveConfig memory collateralConfig,
    ReserveConfig memory borrowConfig,
    uint256 collateralAmount
  ) internal view returns (uint256) {
    // Intentionally introducing a slight rounding error to not trigger the LTV edge case failure condition
    return collateralAmount
      * _getTokenPrice(pool, collateralConfig)
      / _getTokenPrice(pool, borrowConfig)
      * (10 ** borrowConfig.decimals)
      / (10 ** collateralConfig.decimals)
      * collateralConfig.ltv
      / 100_00;
  }

  function _isAboveBorrowCap(
    IPool pool,
    ReserveConfig memory borrowConfig,
    uint256 borrowAmount
  ) internal view returns (bool) {
    DataTypes.ReserveData memory reserveData = pool.getReserveData(borrowConfig.underlying);

    uint256 scaledBorrowCap = borrowConfig.borrowCap * 10 ** borrowConfig.decimals;

    if (scaledBorrowCap == 0) return false;

    uint256 currScaledVariableDebt = IVariableDebtToken(borrowConfig.variableDebtToken).scaledTotalSupply();
    (,uint256 currTotalStableDebt,,) = IStableDebtToken(borrowConfig.stableDebtToken).getSupplyData();

    uint256 totalDebt = currTotalStableDebt + currScaledVariableDebt.rayMul(reserveData.variableBorrowIndex);

    return (borrowAmount + totalDebt) > scaledBorrowCap;
  }

  function _e2eTestBorrowAboveLTV(
    IPool pool,
    address borrower,
    ReserveConfig memory config,
    uint256 maxBorrowAmount
  ) internal {
    // Borrow at exactly theoretical max, and then the smallest unit over
    vm.startPrank(borrower);
    pool.borrow(config.underlying, maxBorrowAmount, 2, 0, borrower);

    // Since Chainlink precision is 8 decimals, the additional borrow needs to be at least 1e8
    // precision to trigger the LTV failure condition.
    uint256 minThresholdAmount = 10 ** config.decimals > 1e8 ? 10 ** config.decimals - 1e8 : 2;

    vm.expectRevert(bytes("36")); // COLLATERAL_CANNOT_COVER_NEW_BORROW
    pool.borrow(config.underlying, minThresholdAmount, 2, 0, borrower);

    vm.stopPrank();
  }

  function _e2eTestBorrowRepayWithdraw(
    IPool pool,
    address borrower,
    ReserveConfig memory collateralConfig,
    ReserveConfig memory borrowConfig,
    uint256 amount
  ) internal {
    // Step 1: Borrow against collateral

    this._borrow(borrowConfig, pool, borrower, amount, false);

    // Step 2: Warp to increase interest in system

    skip(2 hours);

    // Step 3: Repay original borrow amount, without accrued interest,
    //         assert updated state of borrow reserve

    DataTypes.ReserveData memory beforeReserve = pool.getReserveData(borrowConfig.underlying);
    _repay(borrowConfig, pool, borrower, amount, false);
    DataTypes.ReserveData memory afterReserve = pool.getReserveData(borrowConfig.underlying);

    _assertReserveChange(beforeReserve, afterReserve, int256(amount), 2 hours);

    skip(2 hours);

    // Step 4: Try to withdraw all collateral, demonstrate it's not possible without paying back
    //         accrued debt

    uint256 totalCollateral = IERC20(collateralConfig.aToken).balanceOf(borrower);
    uint256 remainingDebt   = IERC20(borrowConfig.variableDebtToken).balanceOf(borrower);

    // Handle edge case for for low LTV collaterals at under 1% causing rounding errors here, preventing failure.
    if (collateralConfig.ltv > 100) {
      vm.prank(borrower);
      vm.expectRevert(bytes("35"));  // HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
      pool.withdraw(collateralConfig.underlying, totalCollateral, borrower);
    }

    // Step 5: Pay back remaining debt

    _repay(borrowConfig, pool, borrower, remainingDebt, false);

    // Step 6: Warp to increase interest in system

    skip(1 hours);

    // Step 7: Withdraw all collateral, assert updated state of collateral reserves

    beforeReserve = pool.getReserveData(collateralConfig.underlying);
    _withdraw(collateralConfig, pool, borrower, totalCollateral);
    afterReserve = pool.getReserveData(collateralConfig.underlying);

    // If collateral == borrow asset, reserve was updated during repay step
    uint256 timePassed = collateralConfig.underlying == borrowConfig.underlying ? 1 hours : 5 hours;

    _assertReserveChange(beforeReserve, afterReserve, -int256(amount), timePassed);
  }

  function _assertReserveChange(
    DataTypes.ReserveData memory beforeReserve,
    DataTypes.ReserveData memory afterReserve,
    int256 amountRepaid,
    uint256 timeSinceLastUpdate
  ) internal pure {
    assertEq(afterReserve.configuration.data, beforeReserve.configuration.data);

    assertApproxEqAbs(
      uint256(afterReserve.liquidityIndex),
      uint256(beforeReserve.liquidityIndex)
      * (1e27 + (beforeReserve.currentLiquidityRate * timeSinceLastUpdate / 365 days)) / 1e27,
      1
    );

    if (amountRepaid > 0) {
      assertLt(afterReserve.currentLiquidityRate,      beforeReserve.currentLiquidityRate);
      assertLe(afterReserve.currentVariableBorrowRate, beforeReserve.currentVariableBorrowRate);
      assertLe(afterReserve.currentStableBorrowRate,   beforeReserve.currentStableBorrowRate);
      assertLe(afterReserve.isolationModeTotalDebt,    beforeReserve.isolationModeTotalDebt);
    } else {
      assertGe(afterReserve.currentLiquidityRate,      beforeReserve.currentLiquidityRate);
      assertGe(afterReserve.currentVariableBorrowRate, beforeReserve.currentVariableBorrowRate);
      assertGe(afterReserve.currentStableBorrowRate,   beforeReserve.currentStableBorrowRate);
      assertGe(afterReserve.isolationModeTotalDebt,    beforeReserve.isolationModeTotalDebt);
    }

    assertEq(afterReserve.lastUpdateTimestamp, beforeReserve.lastUpdateTimestamp + timeSinceLastUpdate);

    assertEq(afterReserve.id,                          beforeReserve.id);
    assertEq(afterReserve.aTokenAddress,               beforeReserve.aTokenAddress);
    assertEq(afterReserve.stableDebtTokenAddress,      beforeReserve.stableDebtTokenAddress);
    assertEq(afterReserve.variableDebtTokenAddress,    beforeReserve.variableDebtTokenAddress);
    assertEq(afterReserve.interestRateStrategyAddress, beforeReserve.interestRateStrategyAddress);
    assertEq(afterReserve.unbacked,                    beforeReserve.unbacked);

    assertGe(afterReserve.accruedToTreasury, beforeReserve.accruedToTreasury);

    uint256 expectedInterest;
    for (uint256 i; i < timeSinceLastUpdate; i++) {
      expectedInterest +=
        uint256(beforeReserve.variableBorrowIndex)
        * uint256(beforeReserve.currentVariableBorrowRate)
        * 1 seconds
        / 365 days
        / 1e27;
    }

    // Accurate to 0.01%
    assertApproxEqRel(
      afterReserve.variableBorrowIndex,
      beforeReserve.variableBorrowIndex + expectedInterest,
      1e14
    );
  }

  function _isAboveSupplyCap(ReserveConfig memory config, uint256 supplyAmount) internal view returns (bool) {
    return IERC20(config.aToken).totalSupply() + supplyAmount > (config.supplyCap * 10 ** config.decimals);
  }

  function _e2eTestStableBorrowDisabled(
    IPool pool,
    address borrower,
    ReserveConfig memory borrowConfig,
    uint256 amount
  ) internal {
    vm.expectRevert(bytes("31")); // STABLE_BORROWING_NOT_ENABLED
    this._borrow(borrowConfig, pool, borrower, amount, true);

    vm.warp(block.timestamp + 1 hours);

    this._borrow(borrowConfig, pool, borrower, amount, false);

    vm.warp(block.timestamp + 1 hours);

    vm.startPrank(borrower);
    IERC20(borrowConfig.underlying).safeApprove(address(pool), amount);

    vm.expectRevert(bytes("39")); // NO_DEBT_OF_SELECTED_TYPE
    pool.repay(borrowConfig.underlying, amount, 1, borrower);

    vm.warp(block.timestamp + 1 hours);

    pool.repay(borrowConfig.underlying, amount, 2, borrower);

    vm.stopPrank();
  }

  function _e2eTestLiquidationReceiveCollateral(
    IPool pool,
    address borrower,
    address liquidator,
    ReserveConfig memory collateralConfig,
    ReserveConfig memory borrowConfig,
    uint256 amount
  ) internal {
    this._borrow(borrowConfig, pool, borrower, amount, false);
    IPoolConfigurator configurator = IPoolConfigurator(
      IPoolAddressesProvider(pool.ADDRESSES_PROVIDER()).getPoolConfigurator()
    );
    // Set ltv/lt to 1bps which enables liquidation on the position
    vm.prank(IPoolAddressesProvider(pool.ADDRESSES_PROVIDER()).getACLAdmin());
    configurator.configureReserveAsCollateral(
      collateralConfig.underlying,
      1,
      1,
      collateralConfig.liquidationBonus
    );

    vm.warp(block.timestamp + 1 hours);

    _liquidateAndReceiveCollateral(collateralConfig, borrowConfig, pool, liquidator, borrower);
  }

  function _e2eTestFlashLoan(
    IPool pool,
    ReserveConfig memory testAssetConfig,
    uint256 amount
  ) internal {
    assertEq(IERC20(testAssetConfig.underlying).balanceOf(address(this)), 0, 'UNDERLYING_NOT_ZERO');
    pool.flashLoanSimple(
      address(this),
      testAssetConfig.underlying,
      amount,
      abi.encode(address(pool)),
      0
    );
    assertEq(IERC20(testAssetConfig.underlying).balanceOf(address(this)), 0, 'UNDERLYING_NOT_ZERO');
  }

  // Called back from the flashloan
  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address,
    bytes calldata params
  ) external returns (bool) {
    address pool = abi.decode(params, (address));
    assertEq(IERC20(asset).balanceOf(address(this)), amount, 'UNDERLYING_NOT_AMOUNT');

    // Temporary measure while USDC/EURe/USDC.e deal gets fixed, set the balance to amount + premium either way
    uint256 dealAmount = asset == USDC_MAINNET || asset == EURE_GNOSIS || asset == USDCE_GNOSIS ? premium : amount + premium;
    deal2(asset, address(this), dealAmount);

    vm.startPrank(address(this));
    SafeERC20.safeApprove(IERC20(asset), pool, amount + premium);
    vm.stopPrank();

    return true;
  }

  function _e2eTestMintToTreasury(
    IPool pool,
    ReserveConfig memory testAssetConfig
  ) internal {
    address[] memory assets = new address[](1);
    assets[0] = testAssetConfig.underlying;
    pool.mintToTreasury(assets);
  }

  function _supply(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount
  ) internal {
    require(!config.isFrozen, 'SUPPLY(): FROZEN_RESERVE');
    require( config.isActive, 'SUPPLY(): INACTIVE_RESERVE');
    require(!config.isPaused, 'SUPPLY(): PAUSED_RESERVE');

    deal2(config.underlying, user, amount);

    uint256 aTokenBefore           = IERC20(config.aToken).balanceOf(user);
    uint256 underlyingATokenBefore = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserBefore   = IERC20(config.underlying).balanceOf(user);

    console.log('SUPPLY: %s, Amount: %s', config.symbol, _formattedAmount(amount, config.decimals));
    vm.startPrank(user);
    IERC20(config.underlying).safeApprove(address(pool), amount);
    pool.supply(config.underlying, amount, user, 0);
    vm.stopPrank();

    uint256 aTokenAfter           = IERC20(config.aToken).balanceOf(user);
    uint256 underlyingATokenAfter = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserAfter   = IERC20(config.underlying).balanceOf(user);

    assertApproxEqAbs(aTokenAfter,           aTokenBefore           + amount, 1);
    assertApproxEqAbs(underlyingATokenAfter, underlyingATokenBefore + amount, 1);
    assertApproxEqAbs(underlyingUserAfter,   underlyingUserBefore   - amount, 1);
  }

  function _withdraw(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount
  ) internal returns (uint256) {
    uint256 aTokenBefore           = IERC20(config.aToken).balanceOf(user);
    uint256 underlyingATokenBefore = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserBefore   = IERC20(config.underlying).balanceOf(user);

    vm.prank(user);
    uint256 amountOut = pool.withdraw(config.underlying, amount, user);
    console.log('WITHDRAW: %s, Amount: %s', config.symbol, _formattedAmount(amountOut, config.decimals));

    uint256 aTokenAfter           = IERC20(config.aToken).balanceOf(user);
    uint256 underlyingATokenAfter = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserAfter   = IERC20(config.underlying).balanceOf(user);

    assertApproxEqAbs(aTokenAfter, aTokenBefore < amount ? 0 : aTokenBefore - amount, 1);

    assertApproxEqAbs(underlyingATokenAfter, underlyingATokenBefore - amountOut, 1);
    assertApproxEqAbs(underlyingUserAfter,   underlyingUserBefore   + amountOut, 1);

    return amountOut;
  }

  function _borrow(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount,
    bool stable
  ) external {
    address debtToken = stable ? config.stableDebtToken : config.variableDebtToken;

    uint256 debtBefore             = IERC20(debtToken).balanceOf(user);
    uint256 underlyingATokenBefore = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserBefore   = IERC20(config.underlying).balanceOf(user);

    console.log('BORROW: %s, Amount %s, Stable: %s', config.symbol, _formattedAmount(amount, config.decimals), stable);
    vm.prank(user);
    pool.borrow(config.underlying, amount, stable ? 1 : 2, 0, user);

    uint256 debtAfter             = IERC20(debtToken).balanceOf(user);
    uint256 underlyingATokenAfter = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserAfter   = IERC20(config.underlying).balanceOf(user);

    assertApproxEqAbs(debtAfter,             debtBefore             + amount, 1);
    assertApproxEqAbs(underlyingATokenAfter, underlyingATokenBefore - amount, 1);
    assertApproxEqAbs(underlyingUserAfter,   underlyingUserBefore   + amount, 1);
  }

  function _repay(
    ReserveConfig memory config,
    IPool pool,
    address user,
    uint256 amount,
    bool stable
  ) internal {
    address debtToken = stable ? config.stableDebtToken : config.variableDebtToken;

    deal2(config.underlying, user, amount);

    uint256 debtBefore             = IERC20(debtToken).balanceOf(user);
    uint256 underlyingATokenBefore = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserBefore   = IERC20(config.underlying).balanceOf(user);

    console.log('REPAY: %s, Amount: %s', config.symbol, _formattedAmount(amount, config.decimals));
    vm.startPrank(user);
    IERC20(config.underlying).safeApprove(address(pool), amount);
    pool.repay(config.underlying, amount, stable ? 1 : 2, user);
    vm.stopPrank();

    uint256 debtAfter             = IERC20(debtToken).balanceOf(user);
    uint256 underlyingATokenAfter = IERC20(config.underlying).balanceOf(config.aToken);
    uint256 underlyingUserAfter   = IERC20(config.underlying).balanceOf(user);

    assertApproxEqAbs(debtAfter,             debtBefore             - amount, 1);
    assertApproxEqAbs(underlyingATokenAfter, underlyingATokenBefore + amount, 1);
    assertApproxEqAbs(underlyingUserAfter,   underlyingUserBefore   - amount, 1);
  }

  function _liquidateAndReceiveCollateral(
    ReserveConfig memory collateral,
    ReserveConfig memory borrow,
    IPool pool,
    address liquidator,
    address user
  ) internal {
    address debtToken = borrow.variableDebtToken;

    LiquidationBalanceAssertions memory balances;

    balances.debtBefore = IERC20(debtToken).balanceOf(user);

    deal2(borrow.underlying, liquidator, balances.debtBefore);

    balances.aTokenBorrowerBefore = IERC20(collateral.aToken).balanceOf(user);
    balances.aTokenTreasuryBefore = IERC20(collateral.aToken).balanceOf(IAToken(collateral.aToken).RESERVE_TREASURY_ADDRESS());

    balances.collateralATokenBefore     = IERC20(collateral.underlying).balanceOf(collateral.aToken);
    balances.collateralLiquidatorBefore = IERC20(collateral.underlying).balanceOf(liquidator);

    balances.borrowATokenBefore     = IERC20(borrow.underlying).balanceOf(borrow.aToken);
    balances.borrowLiquidatorBefore = IERC20(borrow.underlying).balanceOf(liquidator);

    // TODO: Add totalSupply assertions

    vm.startPrank(liquidator);
    SafeERC20.safeApprove(IERC20(borrow.underlying), address(pool), balances.debtBefore);

    console.log('LIQUIDATE: Collateral: %s, Debt: %s, Debt Amount: %s', collateral.symbol, borrow.symbol, _formattedAmount(balances.debtBefore, borrow.decimals));
    pool.liquidationCall(collateral.underlying, borrow.underlying, user, balances.debtBefore, false);
    vm.stopPrank();

    balances.aTokenBorrowerAfter = IERC20(collateral.aToken).balanceOf(user);
    balances.aTokenTreasuryAfter = IERC20(collateral.aToken).balanceOf(IAToken(collateral.aToken).RESERVE_TREASURY_ADDRESS());

    balances.collateralATokenAfter     = IERC20(collateral.underlying).balanceOf(collateral.aToken);
    balances.collateralLiquidatorAfter = IERC20(collateral.underlying).balanceOf(liquidator);

    balances.debtAfter = IERC20(debtToken).balanceOf(user);

    balances.borrowATokenAfter     = IERC20(borrow.underlying).balanceOf(borrow.aToken);
    balances.borrowLiquidatorAfter = IERC20(borrow.underlying).balanceOf(liquidator);

    assertEq(balances.debtAfter, 0);  // All debt removed, full liquidation

    // Checks to ensure diffs aren't zero
    assertLt(balances.collateralATokenAfter,     balances.collateralATokenBefore);      // Collateral balance of aToken decreases
    assertGt(balances.collateralLiquidatorAfter, balances.collateralLiquidatorBefore);  // Liquidator receives collateral
    assertLt(balances.aTokenBorrowerAfter,       balances.aTokenBorrowerBefore);        // Collateral removed from aToken liquidity

    if (collateral.liquidationProtocolFee > 0) {
      assertGt(balances.aTokenTreasuryAfter, balances.aTokenTreasuryBefore);  // Treasury receives collateral aToken if protocol fee > 0
    }

    ( uint256 totalCollateralToLiquidate, uint256 amountToProtocol )
      = _getLiquidationAmounts(collateral, borrow, pool, balances.debtBefore);

    assertApproxEqAbs(balances.aTokenBorrowerBefore - balances.aTokenBorrowerAfter,  totalCollateralToLiquidate, 2);  // Borrower loses all collateral accounting in system
    assertApproxEqAbs(balances.aTokenTreasuryAfter  - balances.aTokenTreasuryBefore, amountToProtocol,           2);  // Treasury receives expected amount in aToken

    if (collateral.underlying == borrow.underlying) {
      assertGt(balances.borrowLiquidatorAfter,     balances.borrowLiquidatorBefore);  // Liquidator gets liquidation bonus
      assertLt(balances.borrowATokenAfter,         balances.borrowATokenBefore);      // borrowAsset balance of aToken decreases because of liquidation bonus

      // Liquidator uses debtBefore to receive (totalCollateralToLiquidate - amountToProtocol)
      uint256 netCollateralChange = (totalCollateralToLiquidate - amountToProtocol) - balances.debtBefore;

      assertApproxEqAbs(balances.borrowLiquidatorAfter - balances.borrowLiquidatorBefore, netCollateralChange, 2);  // Liquidator nets the expected amount of borrowAsset
      assertApproxEqAbs(balances.borrowATokenBefore    - balances.borrowATokenAfter,      netCollateralChange, 2);  // aToken liquidity increases by same amount

      // Same values but adding to be comprehensive
      assertApproxEqAbs(balances.collateralLiquidatorAfter - balances.collateralLiquidatorBefore, netCollateralChange, 2);  // Liquidator receives expected collateral
      assertApproxEqAbs(balances.collateralATokenBefore    - balances.collateralATokenAfter,      netCollateralChange, 2);  // Collateral aToken liquidity decreases by expected amount
      // TODO: Add liquidation bonus assertions
      return;
    }

    assertLt(balances.borrowLiquidatorAfter, balances.borrowLiquidatorBefore);  // Liquidator uses borrowAsset to buy collateral
    assertGt(balances.borrowATokenAfter,     balances.borrowATokenBefore);      // borrowAsset balance of aToken increases

    assertEq(balances.borrowLiquidatorBefore - balances.borrowLiquidatorAfter, balances.debtBefore);  // Liquidator borrowAsset funds equal amount removed from debt accounting
    assertEq(balances.borrowATokenAfter      - balances.borrowATokenBefore,    balances.debtBefore);  // aToken liquidity increases by same amount

    // 1 unit diff to account for liquidity index calculation on _transfer in aToken
    assertApproxEqAbs(balances.collateralLiquidatorAfter - balances.collateralLiquidatorBefore, totalCollateralToLiquidate - amountToProtocol, 2);  // Liquidator receives expected collateral
    assertApproxEqAbs(balances.collateralATokenBefore    - balances.collateralATokenAfter,      totalCollateralToLiquidate - amountToProtocol, 2);  // Collateral aToken liquidity decreases by expected amount

    // The amount of collateral that the liquidator receives is equal to the amount of aTokens that the Borrower lost, minus the portion
    // of the borrower's aTokens that were transferred to the treasury during the liquidation.
    assertApproxEqAbs(
      balances.collateralLiquidatorAfter - balances.collateralLiquidatorBefore,
      (balances.aTokenBorrowerBefore - balances.aTokenBorrowerAfter) - (balances.aTokenTreasuryAfter - balances.aTokenTreasuryBefore),
      2
    );
  }

  function _getLiquidationAmounts(
    ReserveConfig memory collateral,
    ReserveConfig memory borrow,
    IPool pool,
    uint256 debtToCover
  )
    internal view returns (uint256 totalCollateralToLiquidate, uint256 amountToProtocol)
  {
    uint256 baseCollateralToLiquidate =
      debtToCover
        * _getTokenPrice(pool, borrow)
        * 10 ** collateral.decimals
        / _getTokenPrice(pool, collateral)
        / 10 ** borrow.decimals;

    totalCollateralToLiquidate = baseCollateralToLiquidate * collateral.liquidationBonus / 100_00;

    // Recalculating this here to follow same math to capture rounding errors.
    uint256 bonusCollateral = totalCollateralToLiquidate - totalCollateralToLiquidate * 100_00 / collateral.liquidationBonus;

    amountToProtocol = bonusCollateral * collateral.liquidationProtocolFee / 100_00;
  }

  function _rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
    assembly {
      switch x case 0 {switch n case 0 {z := b} default {z := 0}}
      default {
        switch mod(n, 2) case 0 { z := b } default { z := x }
        let half := div(b, 2)  // for rounding.
        for { n := div(n, 2) } n { n := div(n,2) } {
          let xx := mul(x, x)
          if iszero(eq(div(xx, x), x)) { revert(0,0) }
          let xxRound := add(xx, half)
          if lt(xxRound, xx) { revert(0,0) }
          x := div(xxRound, b)
          if mod(n,2) {
            let zx := mul(z, x)
            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
            let zxRound := add(zx, half)
            if lt(zxRound, zx) { revert(0,0) }
            z := div(zxRound, b)
          }
        }
      }
    }
  }

  function _getAPY(uint256 apr) internal pure returns (uint256) {
    uint256 rate = apr / 365 days + 1e27;

    return _rpow(rate, 365 days, 1e27) - 1e27;
  }

  function _formattedAmount(uint256 amount, uint256 decimals) internal pure returns (string memory) {
    return string(abi.encodePacked(vm.toString(amount / 10 ** decimals), ".", vm.toString(amount % 10 ** decimals)));
  }

  function _writeEModeConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) internal {
    // keys for json stringification
    string memory eModesKey = 'emodes';
    string memory content = '{}';

    uint256[] memory usedCategories = new uint256[](configs.length);
    for (uint256 i = 0; i < configs.length; i++) {
      if (!_isInUint256Array(usedCategories, configs[i].eModeCategory)) {
        usedCategories[i] = configs[i].eModeCategory;
        DataTypes.EModeCategory memory category = pool.getEModeCategoryData(
          uint8(configs[i].eModeCategory)
        );
        string memory key = vm.toString(configs[i].eModeCategory);
        vm.serializeUint(key, 'eModeCategory', configs[i].eModeCategory);
        vm.serializeString(key, 'label', category.label);
        vm.serializeUint(key, 'ltv', category.ltv);
        vm.serializeUint(key, 'liquidationThreshold', category.liquidationThreshold);
        vm.serializeUint(key, 'liquidationBonus', category.liquidationBonus);
        string memory object = vm.serializeAddress(key, 'priceSource', category.priceSource);
        content = vm.serializeString(eModesKey, key, object);
      }
    }
    string memory output = vm.serializeString('root', 'eModes', content);
    vm.writeJson(output, path);
  }

  function _writeStrategyConfigs(string memory path, ReserveConfig[] memory configs) internal {
    // keys for json stringification
    string memory strategiesKey = 'stategies';
    string memory content = '{}';

    address[] memory usedStrategies = new address[](configs.length);
    for (uint256 i = 0; i < configs.length; i++) {
      if (!_isInAddressArray(usedStrategies, configs[i].interestRateStrategy)) {
        usedStrategies[i] = configs[i].interestRateStrategy;
        content = _writeStrategyConfig(strategiesKey, configs[i].interestRateStrategy);
      }
    }
    string memory output = vm.serializeString('root', 'strategies', content);
    vm.writeJson(output, path);
  }

  function _writeStrategyConfig(string memory strategiesKey, address _strategy) internal returns (string memory content) {
    string memory key = vm.toString(_strategy);
    IDefaultInterestRateStrategy strategy = IDefaultInterestRateStrategy(
      _strategy
    );
    vm.serializeString(
      key,
      'baseStableBorrowRate',
      vm.toString(strategy.getBaseStableBorrowRate())
    );
    vm.serializeString(key, 'stableRateSlope1', vm.toString(strategy.getStableRateSlope1()));
    vm.serializeString(key, 'stableRateSlope2', vm.toString(strategy.getStableRateSlope2()));
    vm.serializeString(
      key,
      'baseVariableBorrowRate',
      vm.toString(strategy.getBaseVariableBorrowRate())
    );
    vm.serializeString(
      key,
      'variableRateSlope1',
      vm.toString(strategy.getVariableRateSlope1())
    );
    vm.serializeString(
      key,
      'variableRateSlope2',
      vm.toString(strategy.getVariableRateSlope2())
    );
    vm.serializeString(
      key,
      'optimalStableToTotalDebtRatio',
      vm.toString(strategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO())
    );
    vm.serializeString(
      key,
      'maxExcessStableToTotalDebtRatio',
      vm.toString(strategy.MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO())
    );
    vm.serializeString(key, 'optimalUsageRatio', vm.toString(strategy.OPTIMAL_USAGE_RATIO()));
    string memory object = vm.serializeString(
      key,
      'maxExcessUsageRatio',
      vm.toString(strategy.MAX_EXCESS_USAGE_RATIO())
    );
    content = vm.serializeString(strategiesKey, key, object);
  }

  function _writeReserveConfigs(
    string memory path,
    ReserveConfig[] memory configs,
    IPool pool
  ) internal {
    // keys for json stringification
    string memory reservesKey = 'reserves';
    string memory content = '{}';

    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
    for (uint256 i = 0; i < configs.length; i++) {
      ReserveConfig memory config = configs[i];
      IOracleLike assetOracle = IOracleLike(oracle.getSourceOfAsset(config.underlying));

      string memory key = vm.toString(config.underlying);
      vm.serializeString(key, 'symbol', config.symbol);
      vm.serializeUint(key, 'ltv', config.ltv);
      vm.serializeUint(key, 'liquidationThreshold', config.liquidationThreshold);
      vm.serializeUint(key, 'liquidationBonus', config.liquidationBonus);
      vm.serializeUint(key, 'liquidationProtocolFee', config.liquidationProtocolFee);
      vm.serializeUint(key, 'reserveFactor', config.reserveFactor);
      vm.serializeUint(key, 'decimals', config.decimals);
      vm.serializeUint(key, 'borrowCap', config.borrowCap);
      vm.serializeUint(key, 'supplyCap', config.supplyCap);
      vm.serializeUint(key, 'debtCeiling', config.debtCeiling);
      vm.serializeUint(key, 'eModeCategory', config.eModeCategory);
      vm.serializeBool(key, 'usageAsCollateralEnabled', config.usageAsCollateralEnabled);
      vm.serializeBool(key, 'borrowingEnabled', config.borrowingEnabled);
      vm.serializeBool(key, 'stableBorrowRateEnabled', config.stableBorrowRateEnabled);
      vm.serializeBool(key, 'isPaused', config.isPaused);
      vm.serializeBool(key, 'isActive', config.isActive);
      vm.serializeBool(key, 'isFrozen', config.isFrozen);
      vm.serializeBool(key, 'isSiloed', config.isSiloed);
      vm.serializeBool(key, 'isBorrowableInIsolation', config.isBorrowableInIsolation);
      vm.serializeBool(key, 'isFlashloanable', config.isFlashloanable);
      vm.serializeAddress(key, 'interestRateStrategy', config.interestRateStrategy);
      vm.serializeAddress(key, 'underlying', config.underlying);
      vm.serializeAddress(key, 'aToken', config.aToken);
      vm.serializeAddress(key, 'stableDebtToken', config.stableDebtToken);
      vm.serializeAddress(key, 'variableDebtToken', config.variableDebtToken);
      vm.serializeAddress(
        key,
        'aTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, config.aToken)
      );
      vm.serializeString(key, 'aTokenSymbol', IERC20(config.aToken).symbol());
      vm.serializeString(key, 'aTokenName', IERC20(config.aToken).name());
      vm.serializeAddress(
        key,
        'stableDebtTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
          vm,
          config.stableDebtToken
        )
      );
      vm.serializeString(
        key,
        'stableDebtTokenSymbol',
        IERC20(config.stableDebtToken).symbol()
      );
      vm.serializeString(key, 'stableDebtTokenName', IERC20(config.stableDebtToken).name());
      vm.serializeAddress(
        key,
        'variableDebtTokenImpl',
        ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(
          vm,
          config.variableDebtToken
        )
      );
      vm.serializeString(
        key,
        'variableDebtTokenSymbol',
        IERC20(config.variableDebtToken).symbol()
      );
      vm.serializeString(
        key,
        'variableDebtTokenName',
        IERC20(config.variableDebtToken).name()
      );
      if (block.chainid == 1) {
        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);
        (uint48 maxBorrowCap, uint48 borrowCapGap, uint48 borrowCapIncreaseCooldown,, ) = capAutomator.borrowCapConfigs(config.underlying);
        vm.serializeUint(key, 'maxBorrowCap', maxBorrowCap);
        vm.serializeUint(key, 'borrowCapGap', borrowCapGap);
        vm.serializeUint(key, 'borrowCapIncreaseCooldown', borrowCapIncreaseCooldown);

        (uint48 maxSupplyCap, uint48 supplyCapGap, uint48 supplyCapIncreaseCooldown,, ) = capAutomator.supplyCapConfigs(config.underlying);
        vm.serializeUint(key, 'maxSupplyCap', maxSupplyCap);
        vm.serializeUint(key, 'supplyCapGap', supplyCapGap);
        vm.serializeUint(key, 'supplyCapIncreaseCooldown', supplyCapIncreaseCooldown);
      }
      vm.serializeAddress(key, 'oracle', address(assetOracle));
      if (address(assetOracle) != address(0)) {
        try assetOracle.description() returns (string memory name) {
          vm.serializeString(key, 'oracleDescription', name);
        } catch {
          try assetOracle.name() returns (string memory name) {
            vm.serializeString(key, 'oracleName', name);
          } catch {}
        }
        try assetOracle.decimals() returns (uint8 decimals) {
          vm.serializeUint(key, 'oracleDecimals', decimals);
        } catch {
          try assetOracle.DECIMALS() returns (uint8 decimals) {
            vm.serializeUint(key, 'oracleDecimals', decimals);
          } catch {}
        }
      }
      string memory out = vm.serializeUint(
        key,
        'oracleLatestAnswer',
        uint256(oracle.getAssetPrice(config.underlying))
      );
      content = vm.serializeString(reservesKey, key, out);
    }
    string memory output = vm.serializeString('root', 'reserves', content);
    vm.writeJson(output, path);
  }

  function _writePoolConfiguration(string memory path, IPool pool) internal {
    // keys for json stringification
    string memory poolConfigKey = 'poolConfig';

    // addresses provider
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    vm.serializeAddress(poolConfigKey, 'poolAddressesProvider', address(addressesProvider));

    // oracles
    vm.serializeAddress(poolConfigKey, 'oracle', addressesProvider.getPriceOracle());
    vm.serializeAddress(
      poolConfigKey,
      'priceOracleSentinel',
      addressesProvider.getPriceOracleSentinel()
    );

    // pool configurator
    IPoolConfigurator configurator = IPoolConfigurator(addressesProvider.getPoolConfigurator());
    vm.serializeAddress(poolConfigKey, 'poolConfigurator', address(configurator));
    vm.serializeAddress(
      poolConfigKey,
      'poolConfiguratorImpl',
      ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, address(configurator))
    );

    // PoolDataProvider
    IPoolDataProvider pdp = IPoolDataProvider(addressesProvider.getPoolDataProvider());
    vm.serializeAddress(poolConfigKey, 'protocolDataProvider', address(pdp));

    // pool
    vm.serializeAddress(
      poolConfigKey,
      'poolImpl',
      ProxyHelpers.getInitializableAdminUpgradeabilityProxyImplementation(vm, address(pool))
    );
    string memory content = vm.serializeAddress(poolConfigKey, 'pool', address(pool));

    string memory output = vm.serializeString('root', 'poolConfig', content);
    vm.writeJson(output, path);
  }

  function _getReservesConfigs(IPool pool) internal view returns (ReserveConfig[] memory) {
    IPoolAddressesProvider addressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    IPoolDataProvider poolDataProvider = IPoolDataProvider(addressesProvider.getPoolDataProvider());
    LocalVars memory vars;

    vars.reserves = poolDataProvider.getAllReservesTokens();

    vars.configs = new ReserveConfig[](vars.reserves.length);

    for (uint256 i = 0; i < vars.reserves.length; i++) {
      vars.configs[i] = _getStructReserveConfig(pool, vars.reserves[i]);
      ReserveTokens memory reserveTokens = _getStructReserveTokens(
        poolDataProvider,
        vars.configs[i].underlying
      );
      vars.configs[i].aToken = reserveTokens.aToken;
      vars.configs[i].variableDebtToken = reserveTokens.variableDebtToken;
      vars.configs[i].stableDebtToken = reserveTokens.stableDebtToken;
    }

    return vars.configs;
  }

  function _getStructReserveTokens(
    IPoolDataProvider pdp,
    address underlyingAddress
  ) internal view returns (ReserveTokens memory) {
    ReserveTokens memory reserveTokens;
    (reserveTokens.aToken, reserveTokens.stableDebtToken, reserveTokens.variableDebtToken) = pdp
      .getReserveTokensAddresses(underlyingAddress);

    return reserveTokens;
  }

  function _getStructReserveConfig(
    IPool pool,
    IPoolDataProvider.TokenData memory reserve
  ) internal view virtual returns (ReserveConfig memory) {
    ReserveConfig memory localConfig;
    DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(
      reserve.tokenAddress
    );
    localConfig.interestRateStrategy = pool
      .getReserveData(reserve.tokenAddress)
      .interestRateStrategyAddress;
    (
      localConfig.ltv,
      localConfig.liquidationThreshold,
      localConfig.liquidationBonus,
      localConfig.decimals,
      localConfig.reserveFactor,
      localConfig.eModeCategory
    ) = configuration.getParams();
    (
      localConfig.isActive,
      localConfig.isFrozen,
      localConfig.borrowingEnabled,
      localConfig.stableBorrowRateEnabled,
      localConfig.isPaused
    ) = configuration.getFlags();
    localConfig.symbol = reserve.symbol;
    localConfig.underlying = reserve.tokenAddress;
    localConfig.usageAsCollateralEnabled = localConfig.liquidationThreshold != 0;
    localConfig.isSiloed = configuration.getSiloedBorrowing();
    (localConfig.borrowCap, localConfig.supplyCap) = configuration.getCaps();
    localConfig.debtCeiling = configuration.getDebtCeiling();
    localConfig.liquidationProtocolFee = configuration.getLiquidationProtocolFee();
    localConfig.isBorrowableInIsolation = configuration.getBorrowableInIsolation();

    localConfig.isFlashloanable = configuration.getFlashLoanEnabled();

    return localConfig;
  }

  // TODO This should probably be simplified with assembly, too much boilerplate
  function _clone(ReserveConfig memory config) internal pure returns (ReserveConfig memory) {
    return
      ReserveConfig({
        symbol: config.symbol,
        underlying: config.underlying,
        aToken: config.aToken,
        stableDebtToken: config.stableDebtToken,
        variableDebtToken: config.variableDebtToken,
        decimals: config.decimals,
        ltv: config.ltv,
        liquidationThreshold: config.liquidationThreshold,
        liquidationBonus: config.liquidationBonus,
        liquidationProtocolFee: config.liquidationProtocolFee,
        reserveFactor: config.reserveFactor,
        usageAsCollateralEnabled: config.usageAsCollateralEnabled,
        borrowingEnabled: config.borrowingEnabled,
        interestRateStrategy: config.interestRateStrategy,
        stableBorrowRateEnabled: config.stableBorrowRateEnabled,
        isPaused: config.isPaused,
        isActive: config.isActive,
        isFrozen: config.isFrozen,
        isSiloed: config.isSiloed,
        isBorrowableInIsolation: config.isBorrowableInIsolation,
        isFlashloanable: config.isFlashloanable,
        supplyCap: config.supplyCap,
        borrowCap: config.borrowCap,
        debtCeiling: config.debtCeiling,
        eModeCategory: config.eModeCategory
      });
  }

  function _findReserveConfig(
    ReserveConfig[] memory configs,
    address underlying
  ) internal pure returns (ReserveConfig memory) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (configs[i].underlying == underlying) {
        // Important to clone the struct, to avoid unexpected side effect if modifying the returned config
        return _clone(configs[i]);
      }
    }
    revert('RESERVE_CONFIG_NOT_FOUND');
  }

  function _findReserveConfigBySymbol(
    ReserveConfig[] memory configs,
    string memory symbolOfUnderlying
  ) internal pure returns (ReserveConfig memory) {
    for (uint256 i = 0; i < configs.length; i++) {
      if (
        keccak256(abi.encodePacked(configs[i].symbol)) ==
        keccak256(abi.encodePacked(symbolOfUnderlying))
      ) {
        return _clone(configs[i]);
      }
    }
    revert('RESERVE_CONFIG_NOT_FOUND');
  }

  function _logReserveConfig(ReserveConfig memory config) internal pure {
    console.log('Symbol ', config.symbol);
    console.log('Underlying address ', config.underlying);
    console.log('AToken address ', config.aToken);
    console.log('Stable debt token address ', config.stableDebtToken);
    console.log('Variable debt token address ', config.variableDebtToken);
    console.log('Decimals ', config.decimals);
    console.log('LTV ', config.ltv);
    console.log('Liquidation Threshold ', config.liquidationThreshold);
    console.log('Liquidation Bonus ', config.liquidationBonus);
    console.log('Liquidation protocol fee ', config.liquidationProtocolFee);
    console.log('Reserve Factor ', config.reserveFactor);
    console.log('Usage as collateral enabled ', (config.usageAsCollateralEnabled) ? 'Yes' : 'No');
    console.log('Borrowing enabled ', (config.borrowingEnabled) ? 'Yes' : 'No');
    console.log('Stable borrow rate enabled ', (config.stableBorrowRateEnabled) ? 'Yes' : 'No');
    console.log('Supply cap ', config.supplyCap);
    console.log('Borrow cap ', config.borrowCap);
    console.log('Debt ceiling ', config.debtCeiling);
    console.log('eMode category ', config.eModeCategory);
    console.log('Interest rate strategy ', config.interestRateStrategy);
    console.log('Is active ', (config.isActive) ? 'Yes' : 'No');
    console.log('Is frozen ', (config.isFrozen) ? 'Yes' : 'No');
    console.log('Is siloed ', (config.isSiloed) ? 'Yes' : 'No');
    console.log('Is borrowable in isolation ', (config.isBorrowableInIsolation) ? 'Yes' : 'No');
    console.log('Is flashloanable ', (config.isFlashloanable) ? 'Yes' : 'No');
    console.log('-----');
    console.log('-----');
  }

  function _validateReserveConfig(
    ReserveConfig memory expectedConfig,
    ReserveConfig[] memory allConfigs
  ) internal pure {
    ReserveConfig memory config = _findReserveConfig(allConfigs, expectedConfig.underlying);
    require(
      keccak256(bytes(config.symbol)) == keccak256(bytes(expectedConfig.symbol)),
      '_validateConfigsInAave() : INVALID_SYMBOL'
    );
    require(
      config.underlying == expectedConfig.underlying,
      '_validateConfigsInAave() : INVALID_UNDERLYING'
    );
    require(config.decimals == expectedConfig.decimals, '_validateConfigsInAave: INVALID_DECIMALS');
    require(config.ltv == expectedConfig.ltv, '_validateConfigsInAave: INVALID_LTV');
    require(
      config.liquidationThreshold == expectedConfig.liquidationThreshold,
      '_validateConfigsInAave: INVALID_LIQ_THRESHOLD'
    );
    require(
      config.liquidationBonus == expectedConfig.liquidationBonus,
      '_validateConfigsInAave: INVALID_LIQ_BONUS'
    );
    require(
      config.liquidationProtocolFee == expectedConfig.liquidationProtocolFee,
      '_validateConfigsInAave: INVALID_LIQUIDATION_PROTOCOL_FEE'
    );
    require(
      config.reserveFactor == expectedConfig.reserveFactor,
      '_validateConfigsInAave: INVALID_RESERVE_FACTOR'
    );

    require(
      config.usageAsCollateralEnabled == expectedConfig.usageAsCollateralEnabled,
      '_validateConfigsInAave: INVALID_USAGE_AS_COLLATERAL'
    );
    require(
      config.borrowingEnabled == expectedConfig.borrowingEnabled,
      '_validateConfigsInAave: INVALID_BORROWING_ENABLED'
    );
    require(
      config.stableBorrowRateEnabled == expectedConfig.stableBorrowRateEnabled,
      '_validateConfigsInAave: INVALID_STABLE_BORROW_ENABLED'
    );
    require(
      config.isActive == expectedConfig.isActive,
      '_validateConfigsInAave: INVALID_IS_ACTIVE'
    );
    require(
      config.isFrozen == expectedConfig.isFrozen,
      '_validateConfigsInAave: INVALID_IS_FROZEN'
    );
    require(
      config.isSiloed == expectedConfig.isSiloed,
      '_validateConfigsInAave: INVALID_IS_SILOED'
    );
    require(
      config.isBorrowableInIsolation == expectedConfig.isBorrowableInIsolation,
      '_validateConfigsInAave: INVALID_IS_BORROWABLE_IN_ISOLATION'
    );
    require(
      config.isFlashloanable == expectedConfig.isFlashloanable,
      '_validateConfigsInAave: INVALID_IS_FLASHLOANABLE'
    );
    require(
      config.supplyCap == expectedConfig.supplyCap,
      '_validateConfigsInAave: INVALID_SUPPLY_CAP'
    );
    require(
      config.borrowCap == expectedConfig.borrowCap,
      '_validateConfigsInAave: INVALID_BORROW_CAP'
    );
    require(
      config.debtCeiling == expectedConfig.debtCeiling,
      '_validateConfigsInAave: INVALID_DEBT_CEILING'
    );
    require(
      config.eModeCategory == expectedConfig.eModeCategory,
      '_validateConfigsInAave: INVALID_EMODE_CATEGORY'
    );
    require(
      config.interestRateStrategy == expectedConfig.interestRateStrategy,
      '_validateConfigsInAave: INVALID_INTEREST_RATE_STRATEGY'
    );
  }

  function _validateInterestRateStrategy(
    address interestRateStrategyAddress,
    address expectedStrategy,
    InterestStrategyValues memory expectedStrategyValues
  ) internal view {
    IDefaultInterestRateStrategy strategy = IDefaultInterestRateStrategy(
      interestRateStrategyAddress
    );

    require(
      address(strategy) == expectedStrategy,
      '_validateInterestRateStrategy() : INVALID_STRATEGY_ADDRESS'
    );

    require(
      strategy.OPTIMAL_USAGE_RATIO() == expectedStrategyValues.optimalUsageRatio,
      '_validateInterestRateStrategy() : INVALID_OPTIMAL_RATIO'
    );
    require(
      strategy.OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO() ==
        expectedStrategyValues.optimalStableToTotalDebtRatio,
      '_validateInterestRateStrategy() : INVALID_OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO'
    );
    require(
      address(strategy.ADDRESSES_PROVIDER()) == expectedStrategyValues.addressesProvider,
      '_validateInterestRateStrategy() : INVALID_ADDRESSES_PROVIDER'
    );
    require(
      strategy.getBaseVariableBorrowRate() == expectedStrategyValues.baseVariableBorrowRate,
      '_validateInterestRateStrategy() : INVALID_BASE_VARIABLE_BORROW'
    );
    require(
      strategy.getBaseStableBorrowRate() == expectedStrategyValues.baseStableBorrowRate,
      '_validateInterestRateStrategy() : INVALID_BASE_STABLE_BORROW'
    );
    require(
      strategy.getStableRateSlope1() == expectedStrategyValues.stableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_1'
    );
    require(
      strategy.getStableRateSlope2() == expectedStrategyValues.stableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_STABLE_SLOPE_2'
    );
    require(
      strategy.getVariableRateSlope1() == expectedStrategyValues.variableRateSlope1,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_1'
    );
    require(
      strategy.getVariableRateSlope2() == expectedStrategyValues.variableRateSlope2,
      '_validateInterestRateStrategy() : INVALID_VARIABLE_SLOPE_2'
    );
  }

  function _noReservesConfigsChangesApartNewListings(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter
  ) internal pure {
    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
    }
  }

  function _noReservesConfigsChangesApartFrom(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter,
    address assetChangedUnderlying
  ) internal pure {
    require(allConfigsBefore.length == allConfigsAfter.length, 'A_UNEXPECTED_NEW_LISTING_HAPPENED');

    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      if (assetChangedUnderlying != allConfigsBefore[i].underlying) {
        _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
      }
    }
  }

  /// @dev Version in batch, useful when multiple asset changes are expected
  function _noReservesConfigsChangesApartFrom(
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter,
    address[] memory assetChangedUnderlying
  ) internal pure {
    require(allConfigsBefore.length == allConfigsAfter.length, 'A_UNEXPECTED_NEW_LISTING_HAPPENED');

    for (uint256 i = 0; i < allConfigsBefore.length; i++) {
      bool isAssetExpectedToChange;
      for (uint256 j = 0; j < assetChangedUnderlying.length; j++) {
        if (assetChangedUnderlying[j] == allConfigsBefore[i].underlying) {
          isAssetExpectedToChange = true;
          break;
        }
      }
      if (!isAssetExpectedToChange) {
        _requireNoChangeInConfigs(allConfigsBefore[i], allConfigsAfter[i]);
      }
    }
  }

  function _requireNoChangeInConfigs(
    ReserveConfig memory config1,
    ReserveConfig memory config2
  ) internal pure {
    require(
      keccak256(abi.encodePacked(config1.symbol)) == keccak256(abi.encodePacked(config2.symbol)),
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_SYMBOL_CHANGED'
    );
    require(
      config1.underlying == config2.underlying,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_UNDERLYING_CHANGED'
    );
    require(
      config1.aToken == config2.aToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_A_TOKEN_CHANGED'
    );
    require(
      config1.stableDebtToken == config2.stableDebtToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_STABLE_DEBT_TOKEN_CHANGED'
    );
    require(
      config1.variableDebtToken == config2.variableDebtToken,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_VARIABLE_DEBT_TOKEN_CHANGED'
    );
    require(
      config1.decimals == config2.decimals,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_DECIMALS_CHANGED'
    );
    require(
      config1.ltv == config2.ltv,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LTV_CHANGED'
    );
    require(
      config1.liquidationThreshold == config2.liquidationThreshold,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LIQ_THRESHOLD_CHANGED'
    );
    require(
      config1.liquidationBonus == config2.liquidationBonus,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LIQ_BONUS_CHANGED'
    );
    require(
      config1.liquidationProtocolFee == config2.liquidationProtocolFee,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_LIQ_PROTOCOL_FEE_CHANGED'
    );
    require(
      config1.reserveFactor == config2.reserveFactor,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_RESERVE_FACTOR_CHANGED'
    );
    require(
      config1.usageAsCollateralEnabled == config2.usageAsCollateralEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_USAGE_AS_COLLATERAL_ENABLED_CHANGED'
    );
    require(
      config1.borrowingEnabled == config2.borrowingEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_BORROWING_ENABLED_CHANGED'
    );
    require(
      config1.interestRateStrategy == config2.interestRateStrategy,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_INTEREST_RATE_STRATEGY_CHANGED'
    );
    require(
      config1.stableBorrowRateEnabled == config2.stableBorrowRateEnabled,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_STABLE_BORROWING_CHANGED'
    );
    require(
      config1.isActive == config2.isActive,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_ACTIVE_CHANGED'
    );
    require(
      config1.isFrozen == config2.isFrozen,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_FROZEN_CHANGED'
    );
    require(
      config1.isSiloed == config2.isSiloed,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_SILOED_CHANGED'
    );
    require(
      config1.isBorrowableInIsolation == config2.isBorrowableInIsolation,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_BORROWABLE_IN_ISOLATION_CHANGED'
    );
    require(
      config1.isFlashloanable == config2.isFlashloanable,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_IS_FLASHLOANABLE_CHANGED'
    );
    require(
      config1.supplyCap == config2.supplyCap,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_SUPPLY_CAP_CHANGED'
    );
    require(
      config1.borrowCap == config2.borrowCap,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_BORROW_CAP_CHANGED'
    );
    require(
      config1.debtCeiling == config2.debtCeiling,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_DEBT_CEILING_CHANGED'
    );
    require(
      config1.eModeCategory == config2.eModeCategory,
      '_noReservesConfigsChangesApartNewListings() : UNEXPECTED_E_MODE_CATEGORY_CHANGED'
    );
  }

  function _validateCountOfListings(
    uint256 count,
    ReserveConfig[] memory allConfigsBefore,
    ReserveConfig[] memory allConfigsAfter
  ) internal pure {
    require(
      allConfigsBefore.length == allConfigsAfter.length - count,
      '_validateCountOfListings() : INVALID_COUNT_OF_LISTINGS'
    );
  }

  function _validateReserveTokensImpls(
    IPoolAddressesProvider addressProvider,
    ReserveConfig memory config,
    ReserveTokens memory expectedImpls
  ) internal {
    address poolConfigurator = addressProvider.getPoolConfigurator();
    vm.startPrank(poolConfigurator);
    require(
      IProxyLike(config.aToken).implementation() ==
        expectedImpls.aToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    require(
      IProxyLike(config.variableDebtToken).implementation() ==
        expectedImpls.variableDebtToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    require(
      IProxyLike(config.stableDebtToken).implementation() ==
        expectedImpls.stableDebtToken,
      '_validateReserveTokensImpls() : INVALID_ATOKEN_IMPL'
    );
    vm.stopPrank();
  }

  function _validateAssetSourceOnOracle(
    IPoolAddressesProvider addressesProvider,
    address asset,
    address expectedSource
  ) internal view {
    IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());

    require(
      oracle.getSourceOfAsset(asset) == expectedSource,
      '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE'
    );
    require(
      IOracleLike(oracle.getSourceOfAsset(asset)).decimals() == 8,
      '_validateAssetSourceOnOracle() : INVALID_PRICE_SOURCE_DECIMALS'
    );

  }

  function _validateAssetsOnEmodeCategory(
    uint256 category,
    ReserveConfig[] memory assetsConfigs,
    string[] memory expectedAssets
  ) internal pure {
    string[] memory assetsInCategory = new string[](assetsConfigs.length);

    uint256 countCategory;
    for (uint256 i = 0; i < assetsConfigs.length; i++) {
      if (assetsConfigs[i].eModeCategory == category) {
        assetsInCategory[countCategory] = assetsConfigs[i].symbol;
        require(
          keccak256(bytes(assetsInCategory[countCategory])) ==
            keccak256(bytes(expectedAssets[countCategory])),
          '_getAssetOnEmodeCategory(): INCONSISTENT_ASSETS'
        );
        countCategory++;
        if (countCategory > expectedAssets.length) {
          revert('_getAssetOnEmodeCategory(): MORE_ASSETS_IN_CATEGORY_THAN_EXPECTED');
        }
      }
    }
    if (countCategory < expectedAssets.length) {
      revert('_getAssetOnEmodeCategory(): LESS_ASSETS_IN_CATEGORY_THAN_EXPECTED');
    }
  }
}

/**
 * only applicable to v3 harmony at this point
 */
contract ProtocolV3LegacyTestBase is ProtocolV3TestBase {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  function _getStructReserveConfig(
    IPool pool,
    IPoolDataProvider.TokenData memory reserve
  ) internal view override returns (ReserveConfig memory) {
    ReserveConfig memory localConfig;
    DataTypes.ReserveConfigurationMap memory configuration = pool.getConfiguration(
      reserve.tokenAddress
    );
    localConfig.interestRateStrategy = pool
      .getReserveData(reserve.tokenAddress)
      .interestRateStrategyAddress;
    (
      localConfig.ltv,
      localConfig.liquidationThreshold,
      localConfig.liquidationBonus,
      localConfig.decimals,
      localConfig.reserveFactor,
      localConfig.eModeCategory
    ) = configuration.getParams();
    (
      localConfig.isActive,
      localConfig.isFrozen,
      localConfig.borrowingEnabled,
      localConfig.stableBorrowRateEnabled,
      localConfig.isPaused
    ) = configuration.getFlags();
    localConfig.symbol = reserve.symbol;
    localConfig.underlying = reserve.tokenAddress;
    localConfig.usageAsCollateralEnabled = localConfig.liquidationThreshold != 0;
    localConfig.isSiloed = configuration.getSiloedBorrowing();
    (localConfig.borrowCap, localConfig.supplyCap) = configuration.getCaps();
    localConfig.debtCeiling = configuration.getDebtCeiling();
    localConfig.liquidationProtocolFee = configuration.getLiquidationProtocolFee();
    localConfig.isBorrowableInIsolation = configuration.getBorrowableInIsolation();

    localConfig.isFlashloanable = false;

    return localConfig;
  }

}
