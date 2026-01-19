// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';
import { VmSafe }   from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, Id, PendingUint192, MarketConfig } from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParamsLib }                                             from "lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { AaveOracle }        from "sparklend-v1-core/misc/AaveOracle.sol";
import { IPool }             from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator } from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { DataTypes }         from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPoolDataProvider } from "sparklend-v1-core/interfaces/IPoolDataProvider.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { ChainIdUtils }         from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ICurvePoolLike,
    ISparkVaultV2Like,
    ISyrupLike,
    IPSM3Like
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20260129_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xE43c41356CbBa9449fE6CF27c6182F62C4FB3fE9;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1768574062;  // 2026-01-16T14:34:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;

        // Maple onboarding process
        ISyrupLike syrup = ISyrupLike(Ethereum.SYRUP_USDT);

        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = address(Ethereum.ALM_PROXY);
        booleans[0] = true;

        vm.startPrank(permissionManager.admin());
        permissionManager.setLenderAllowlist(
            syrup.manager(),
            lenders,
            booleans
        );
        vm.stopPrank();
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

        assertEq(usdtVault.depositCap(), 500_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdtVault.depositCap(), 2_000_000_000e6);

        _testSparkVaultDepositCapBoundary({
            vault:              usdtVault,
            depositCap:         2_000_000_000e6,
            expectedMaxDeposit: 1_845_509_060.394753e6
        });
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

contract SparkEthereum_20260129_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1768574062;  // 2026-01-16T14:34:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
    }

    function test_ETHEREUM_sparkLend_deprecateTBTC() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.TBTC).configuration;

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 20_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.TBTC).configuration;

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 99_00);

        _testUserActionsAfterPayloadExecutionSparkLend(Ethereum.TBTC, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateEZETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.EZETH).configuration;

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.EZETH).configuration;

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 15_00);

        _testUserActionsAfterPayloadExecutionSparkLend(Ethereum.EZETH, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateRSETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.RSETH).configuration;

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getReserveData(Ethereum.RSETH).configuration;

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 15_00);

        _testUserActionsAfterPayloadExecutionSparkLend(Ethereum.RSETH, Ethereum.USDC);
    }

    function _testUserActionsAfterPayloadExecutionSparkLend(address collateralAsset, address debtAsset) internal {
        address testUser         = makeAddr("testUser");
        uint256 collateralAmount = 100 * 10 ** IERC20Metadata(collateralAsset).decimals();
        uint256 debtAmount       = 10 * 10 ** IERC20Metadata(debtAsset).decimals();

        IPool pool = IPool(SparkLend.POOL);

        deal(collateralAsset, testUser, collateralAmount);

        vm.startPrank(testUser);

        IERC20(collateralAsset).approve(address(SparkLend.POOL), type(uint256).max);

        // User can't supply.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.supply(collateralAsset, collateralAmount, testUser, 0);

        // User can't borrow.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.borrow(collateralAsset, debtAmount, 2, 0, testUser);

        vm.stopPrank();

        _setupUserSparkLendPosition(collateralAsset, debtAsset, testUser, collateralAmount, debtAmount);

        // User can repay the debt.
        deal(debtAsset, testUser, debtAmount);

        vm.startPrank(testUser);

        IERC20(debtAsset).approve(address(SparkLend.POOL), type(uint256).max);
        
        pool.repay(debtAsset, debtAmount, 2, testUser);

        // User can withdraw the collateral.
        pool.withdraw(collateralAsset, collateralAmount, testUser);

        vm.stopPrank();

        _setupUserSparkLendPosition(collateralAsset, debtAsset, testUser, collateralAmount, debtAmount);

        // Manipulate the price oracle used by sparklend.
        address mockOracle = address(new MockAggregator(1));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);
        assets[0]  = collateralAsset;
        sources[0] = mockOracle;
        
        vm.prank(Ethereum.SPARK_PROXY);
        AaveOracle(SparkLend.AAVE_ORACLE).setAssetSources(assets, sources);

        // User can be liquidated.
        vm.prank(testUser);
        pool.liquidationCall(collateralAsset, debtAsset, testUser, debtAmount, false);
    }

    function _setupUserSparkLendPosition(
        address collateralAsset,
        address debtAsset,
        address testUser,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal {
        IPool pool = IPool(SparkLend.POOL);

        deal(collateralAsset, testUser, collateralAmount);

        vm.prank(testUser);
        IERC20(collateralAsset).approve(address(SparkLend.POOL), type(uint256).max);

        // Set Reserve frozen to false.
        vm.prank(Ethereum.SPARK_PROXY);
        IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, false);
        
        vm.startPrank(testUser);

        pool.supply(collateralAsset, collateralAmount, testUser, 0);
        pool.borrow(debtAsset,       debtAmount,       2,          0, testUser);

        vm.stopPrank();

        // Set Reserve frozen to true.
        vm.prank(Ethereum.SPARK_PROXY);
        IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, true);
    }

}

contract SparkEthereum_20260129_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260129;
         _blockDate = 1768574062;  // 2026-01-16T14:34:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  319_047_956.431520054882571853e18);
        assertEq(spUsdsBalanceBefore, 342_048_578.468237917665483512e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 86_220.888775852652987990e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 36_508.019549894218943671e18);
    }

}
