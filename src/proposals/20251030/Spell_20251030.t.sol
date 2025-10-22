// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainId.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { 
    ISyrupLike,
    ISparkVaultV2Like,
    IERC20Like
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20251030_SLLTests is SparkLiquidityLayerTests {

    address internal constant ARBITRUM_NEW_ALM_CONTROLLER = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;
    address internal constant OPTIMISM_NEW_ALM_CONTROLLER = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
    address internal constant UNICHAIN_NEW_ALM_CONTROLLER = 0x7CD6EC14785418aF694efe154E7ff7d9ba99D99b;

    address internal constant SYRUP_USDT = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-20T15:17:00Z";
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.ArbitrumOne()].prevController = Arbitrum.ALM_CONTROLLER;
        chainData[ChainIdUtils.ArbitrumOne()].newController  = ARBITRUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Optimism()].prevController = Optimism.ALM_CONTROLLER;
        chainData[ChainIdUtils.Optimism()].newController  = OPTIMISM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Unichain()].prevController = Unichain.ALM_CONTROLLER;
        chainData[ChainIdUtils.Unichain()].newController  = UNICHAIN_NEW_ALM_CONTROLLER;

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0x0546eFeBb465c33A49D3E592b218e0B00fA51BF1;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Optimism()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
        // chainData[ChainIdUtils.Unichain()].payload  = 0x4924e46935F6706d08413d44dF5C31a9d40F6a64;
    }

    function test_ARBITRUM_controllerUpgrade() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testControllerUpgrade({
            oldController: Arbitrum.ALM_CONTROLLER,
            newController: ARBITRUM_NEW_ALM_CONTROLLER
        });
    }

    function test_OPTIMISM_controllerUpgrade() public onChain(ChainIdUtils.Optimism()) {
        _testControllerUpgrade({
            oldController: Optimism.ALM_CONTROLLER,
            newController: OPTIMISM_NEW_ALM_CONTROLLER
        });
    }

    function test_UNICHAIN_controllerUpgrade() public onChain(ChainIdUtils.Unichain()) {
        _testControllerUpgrade({
            oldController: Unichain.ALM_CONTROLLER,
            newController: UNICHAIN_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_onboardSyrupUSDT() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
            SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
            SYRUP_USDT
        );

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(redeemKey,   0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 50_000_000e6, 10_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(redeemKey);
        _assertUnlimitedRateLimit(withdrawKey);

        // Maple onboarding process
        ISyrupLike syrup = ISyrupLike(SYRUP_USDT);

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

        _testMapleIntegration(MapleE2ETestParams({
            ctx:           ctx,
            vault:         SYRUP_USDT,
            depositAmount: 1_000_000e6,
            depositKey:    depositKey,
            redeemKey:     redeemKey,
            withdrawKey:   withdrawKey,
            tolerance:     10
        }));
    }

}

contract SparkEthereum_20251030_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address internal constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-22T07:32:00Z";
    }

    function test_ETHEREUM_sparkLend_usdcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDC, 1_000_000_000, 150_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDC, 950_000_000,   50_000_000,  12 hours);

        DataTypes.ReserveConfigurationMap memory config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDC);

        assertEq(config.getSupplyCap(), 183_143_502);
        assertEq(config.getBorrowCap(), 83_933_418);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDC, 0, 0, 0);
        _assertBorrowCapConfig(Ethereum.USDC, 0, 0, 0);

        config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDC);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);

        // Caps can’t be changed with automator
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execSupply(Ethereum.USDC);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execBorrow(Ethereum.USDC);

        config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDC);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_usdtCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.USDT, 5_000_000_000, 1_000_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDT, 5_000_000_000, 200_000_000,   12 hours);

        DataTypes.ReserveConfigurationMap memory config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDT);

        assertEq(config.getSupplyCap(), 1_904_511_069);
        assertEq(config.getBorrowCap(), 821_423_249);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDT, 0, 0, 0);
        _assertBorrowCapConfig(Ethereum.USDT, 0, 0, 0);

        config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDT);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);

        // Caps can’t be changed with automator
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execSupply(Ethereum.USDT);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execBorrow(Ethereum.USDT);

        config = IPool(Ethereum.POOL).getConfiguration(Ethereum.USDT);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_pyusdCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(PYUSD, 500_000_000, 50_000_000, 12 hours);
        _assertBorrowCapConfig(PYUSD, 475_000_000, 25_000_000, 12 hours);

        DataTypes.ReserveConfigurationMap memory config = IPool(Ethereum.POOL).getConfiguration(PYUSD);

        assertEq(config.getSupplyCap(), 500_000_000);
        assertEq(config.getBorrowCap(), 363_906_088);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(PYUSD, 0, 0, 0);
        _assertBorrowCapConfig(PYUSD, 0, 0, 0);

        config = IPool(Ethereum.POOL).getConfiguration(PYUSD);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);

        // Caps can’t be changed with automator
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execSupply(PYUSD);
        ICapAutomator(Ethereum.CAP_AUTOMATOR).execBorrow(PYUSD);

        config = IPool(Ethereum.POOL).getConfiguration(PYUSD);

        assertEq(config.getSupplyCap(), ReserveConfiguration.MAX_VALID_SUPPLY_CAP);
        assertEq(config.getBorrowCap(), ReserveConfiguration.MAX_VALID_BORROW_CAP);
    }

    function test_ETHEREUM_sparkLend_cbbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.CBBTC, 10_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 500,    50,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.CBBTC, 20_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.CBBTC, 10_000, 50,  12 hours);
    }

    function test_ETHEREUM_sparkLend_tbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.TBTC, 500, 125, 12 hours);
        _assertBorrowCapConfig(Ethereum.TBTC, 250, 25,  12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.TBTC, 1_000, 125, 12 hours);
        _assertBorrowCapConfig(Ethereum.TBTC, 900,   25,  12 hours);
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  407_568_011.143768143248809289e18);
        assertEq(spUsdsBalanceBefore, 172_648_019.339848759936460960e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.DAI_TREASURY), 0);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.TREASURY),    0);
        assertEq(IERC20(Ethereum.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spDaiBalanceBefore + 65_557.659034227304964786e18);
        assertEq(IERC20(Ethereum.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),   spUsdsBalanceBefore + 33_086.258380656692096081e18);
    }

}

contract SparkEthereum_20251030_SpellTests is SpellTests {

    using SafeERC20 for IERC20;

    constructor() {
        _spellId   = 20251030;
        _blockDate = "2025-10-22T07:32:00Z";
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 50_000_000e6);
        assertEq(usdtVault.depositCap(), 50_000_000e6);
        assertEq(ethVault.depositCap(),  10_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 250_000_000e6);
        assertEq(usdtVault.depositCap(), 250_000_000e6);
        assertEq(ethVault.depositCap(),  50_000e18);

        // Boundary deposit test for Spark Savings V2 USDC //

        uint256 maxDepositUsdc = usdcVault.maxDeposit(address(this));

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        usdcVault.deposit(maxDepositUsdc + 1, address(this));

        // Can deposit less than or equal to maxDeposit
        
        assertEq(usdcVault.balanceOf(address(this)), 0);

        deal(Ethereum.USDC, address(this), maxDepositUsdc);
        IERC20(Ethereum.USDC).approve(address(usdcVault), maxDepositUsdc);

        uint256 shares = usdcVault.deposit(maxDepositUsdc, address(this));

        assertEq(usdcVault.balanceOf(address(this)), shares);

        // Boundary deposit test for Spark Savings V2 USDT //

        uint256 maxDepositUsdt = usdtVault.maxDeposit(address(this));

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        usdtVault.deposit(maxDepositUsdt + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(usdtVault.balanceOf(address(this)), 0);

        deal(Ethereum.USDT, address(this), maxDepositUsdt);
        IERC20(Ethereum.USDT).safeIncreaseAllowance(address(usdtVault), maxDepositUsdt);

        shares = usdtVault.deposit(maxDepositUsdt, address(this));

        assertEq(usdtVault.balanceOf(address(this)), shares);

        // Boundary deposit test for Spark Savings V2 ETH //

        uint256 maxDepositEth = ethVault.maxDeposit(address(this));

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        ethVault.deposit(maxDepositEth + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(ethVault.balanceOf(address(this)), 0);

        deal(Ethereum.WETH, address(this), maxDepositEth);
        IERC20(Ethereum.WETH).approve(address(ethVault), maxDepositEth);

        shares = ethVault.deposit(maxDepositEth, address(this));

        assertEq(ethVault.balanceOf(address(this)), shares);
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(usdcVault.depositCap(), 50_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 150_000_000e6);

        // Boundary deposit test for Spark Savings V2 USDC //

        uint256 maxDepositUsdc = usdcVault.maxDeposit(address(this));

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        usdcVault.deposit(maxDepositUsdc + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(usdcVault.balanceOf(address(this)), 0);

        deal(Avalanche.USDC, address(this), maxDepositUsdc);
        IERC20(Avalanche.USDC).approve(address(usdcVault), maxDepositUsdc);

        uint256 shares = usdcVault.deposit(maxDepositUsdc, address(this));

        assertEq(usdcVault.balanceOf(address(this)), shares);
    }

}
