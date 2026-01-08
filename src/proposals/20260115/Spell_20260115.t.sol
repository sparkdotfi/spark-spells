// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';
import { VmSafe }   from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, Id, PendingUint192, MarketConfig } from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParamsLib }                                             from "lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { AaveOracle } from "sparklend-v1-core/misc/AaveOracle.sol";
import { IPool }      from "sparklend-v1-core/interfaces/IPool.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { ChainIdUtils }         from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ICurvePoolLike,
    ISparkVaultV2Like,
    ISyrupLike
} from "src/interfaces/Interfaces.sol";

interface IChainlinkAggregator {
    function latestAnswer() external view returns (int256);
}

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

contract SparkEthereum_20260115_SLLTests is SparkLiquidityLayerTests {

    address internal constant CURVE_WEETHWETHNG = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767859429;  // 2026-01-08T08:04:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        // chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;

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

    function test_ETHEREUM_curvePoolOnboarding() external onChain(ChainIdUtils.Ethereum()) {
        _testCurveOnboarding({
            controller:                  Ethereum.ALM_CONTROLLER,
            pool:                        CURVE_WEETHWETHNG,
            expectedDepositAmountToken0: 0,
            expectedSwapAmountToken0:    10e18,
            maxSlippage:                 0.9975e18,
            swapLimit:                   RateLimitData(100e18, 1_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(0, 0),
            withdrawLimit:               RateLimitData(0, 0)
        });

        ICurvePoolLike pool = ICurvePoolLike(CURVE_WEETHWETHNG);

        assertEq(pool.A(),   5_000);
        assertEq(pool.fee(), 0.00005e10);  // 0.005%

        assertEq(pool.offpeg_fee_multiplier(), 10e10);
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(ethVault.depositCap(),  100_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 1_000_000_000e6);
        assertEq(ethVault.depositCap(),  250_000e18);

        _testSparkVaultDepositCapBoundary({
            vault:              usdcVault,
            depositCap:         1_000_000_000e6,
            expectedMaxDeposit: 779_644_583.499468e6
        });

        _testSparkVaultDepositCapBoundary({
            vault:              ethVault,
            depositCap:         250_000e18,
            expectedMaxDeposit: 236_070.661082022093344741e18
        });
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(usdcVault.depositCap(), 250_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 500_000_000e6);

        _testSparkVaultDepositCapBoundary({
            vault:              usdcVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 301_781_699.829455e6
        });
    }

}

contract SparkEthereum_20260115_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767859429;  // 2026-01-08T08:04:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        // chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;
    }

}

contract SparkEthereum_20260115_SpellTests is SpellTests {

    using MarketParamsLib for MarketParams;

    error NotCuratorRole();
    error NotCuratorNorGuardianRole();
    error TimelockNotElapsed();

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

    address internal constant ETH_CURATOR_MULTISIG   = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant ETH_GUARDIAN_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant BASE_CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant BASE_GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;
    address internal constant WETH                          = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE                    = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767859429;  // 2026-01-08T08:04:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload = 0x3A60e678eA258A30c7cab2B70439a37fd6495Fe1;
        // chainData[ChainIdUtils.Base()].payload      = 0x2C07e5E977B6db3A2a776028158359fcE212F04A;
        // chainData[ChainIdUtils.Ethereum()].payload  = 0x2cB9Fa737603cB650d4919937a36EA732ACfe963;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  326_138_770.335962665625026796e18);
        assertEq(spUsdsBalanceBefore, 224_340_049.016097029894731273e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 81_600.440168468291624562e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 32_773.538347293426995369e18);
    }

    function test_ETHEREUM_killSwitchActivationForLBTC() external onChain(ChainIdUtils.Ethereum()) {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),                      1);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),                      2);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0.95e8);

        // Sanity check the latest answers
        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 1.00262946e8);

        // Should not be able to trigger
        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(LBTC_BTC_ORACLE);

        // Assert Boundary Condition
        vm.store(
            LBTC_BTC_ORACLE,
            bytes32(uint256(2)),
            bytes32((uint256(uint160(address(new MockAggregator(0.95e8 + 1)))) << 16) | 1)
        );

        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 0.95e8 + 1);

        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(LBTC_BTC_ORACLE);

        assertEq(kso.triggered(), false);

        // Replace Chainlink aggregator with MockAggregator reporting
        // below threshold and set the current phase ID
        vm.store(
            LBTC_BTC_ORACLE,
            bytes32(uint256(2)),
            bytes32((uint256(uint160(address(new MockAggregator(0.95e8)))) << 16) | 1)
        );

        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 0.95e8);

        // Fetch all assets from the pool
        address[] memory reserves = IPool(SparkLend.POOL).getReservesList();

        assertEq(reserves.length, 18);

        assertEq(kso.triggered(), false);

        assertEq(_getBorrowEnabled(reserves[0]),  true);
        assertEq(_getBorrowEnabled(reserves[1]),  false);
        assertEq(_getBorrowEnabled(reserves[2]),  true);
        assertEq(_getBorrowEnabled(reserves[3]),  true);
        assertEq(_getBorrowEnabled(reserves[4]),  true);
        assertEq(_getBorrowEnabled(reserves[5]),  false);
        assertEq(_getBorrowEnabled(reserves[6]),  false);
        assertEq(_getBorrowEnabled(reserves[7]),  true);
        assertEq(_getBorrowEnabled(reserves[8]),  true);
        assertEq(_getBorrowEnabled(reserves[9]),  false);
        assertEq(_getBorrowEnabled(reserves[10]), true);
        assertEq(_getBorrowEnabled(reserves[11]), false);
        assertEq(_getBorrowEnabled(reserves[12]), true);
        assertEq(_getBorrowEnabled(reserves[13]), false);
        assertEq(_getBorrowEnabled(reserves[14]), true);
        assertEq(_getBorrowEnabled(reserves[15]), false);
        assertEq(_getBorrowEnabled(reserves[16]), false);
        assertEq(_getBorrowEnabled(reserves[17]), true);

        kso.trigger(LBTC_BTC_ORACLE);

        assertEq(kso.triggered(), true);

         assertEq(_getBorrowEnabled(reserves[0]), false);
        assertEq(_getBorrowEnabled(reserves[1]),  false);
        assertEq(_getBorrowEnabled(reserves[2]),  false);
        assertEq(_getBorrowEnabled(reserves[3]),  false);
        assertEq(_getBorrowEnabled(reserves[4]),  false);
        assertEq(_getBorrowEnabled(reserves[5]),  false);
        assertEq(_getBorrowEnabled(reserves[6]),  false);
        assertEq(_getBorrowEnabled(reserves[7]),  false);
        assertEq(_getBorrowEnabled(reserves[8]),  false);
        assertEq(_getBorrowEnabled(reserves[9]),  false);
        assertEq(_getBorrowEnabled(reserves[10]), false);
        assertEq(_getBorrowEnabled(reserves[11]), false);
        assertEq(_getBorrowEnabled(reserves[12]), false);
        assertEq(_getBorrowEnabled(reserves[13]), false);
        assertEq(_getBorrowEnabled(reserves[14]), false);
        assertEq(_getBorrowEnabled(reserves[15]), false);
        assertEq(_getBorrowEnabled(reserves[16]), false);
        assertEq(_getBorrowEnabled(reserves[17]), false);
    }

    function test_ETHEREUM_positionLiquidableAfterkillSwitchActivationForLBTC() external onChain(ChainIdUtils.Ethereum()) {
        address user = 0x219dE81f5d9b30f4759459C81c3CF47AbaA0dED1;

        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        IPool pool = IPool(SparkLend.POOL);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(user);

        deal(Ethereum.USDT, address(this), 100_000_000e6);
        SafeERC20.safeIncreaseAllowance(IERC20(Ethereum.USDT), address(pool), 100_000_000e6);

        assertEq(healthFactor, 1.763842849507460125e18);

        // Should not be able to liquidate
        vm.expectRevert(bytes("45"));   // HEALTH_FACTOR_NOT_BELOW_THRESHOLD
        pool.liquidationCall(Ethereum.LBTC, Ethereum.USDT, user, 10_000_000e6, false);

        _executeAllPayloadsAndBridges();

        // Replace Chainlink aggregator with MockAggregator reporting 
        // below threshold and set the current phase ID
        vm.store(
            LBTC_BTC_ORACLE,
            bytes32(uint256(2)),
            bytes32((uint256(uint160(address(new MockAggregator(0.2e8)))) << 16) | 1)
        );

        kso.trigger(LBTC_BTC_ORACLE);

        assertEq(kso.triggered(), true);

        // Manipulate the price oracle used by sparklend
        address mockOracle = address(new MockAggregator(10_000e8));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);
        assets[0]  = Ethereum.LBTC;
        sources[0] = mockOracle;

        vm.prank(Ethereum.SPARK_PROXY);
        AaveOracle(SparkLend.AAVE_ORACLE).setAssetSources(assets, sources);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(user);

        assertEq(healthFactor, 0.195109189416086504e18);

        // Should be able to liquidate the asset
        pool.liquidationCall(Ethereum.LBTC, Ethereum.USDT, user, 10_000_000e6, false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return ReserveConfiguration.getBorrowingEnabled(
            IPool(SparkLend.POOL).getConfiguration(asset)
        );
    }

    function test_ETHEREUM_morphoVaultUSDS_updateRoles() external onChain(ChainIdUtils.Ethereum()) {
        IMetaMorpho morphoUsdsVault = IMetaMorpho(Ethereum.MORPHO_VAULT_USDS);

        MarketParams memory params = MarketParams({
            loanToken:       Ethereum.USDS,
            collateralToken: PT_USDE_27NOV2025,
            oracle:          PT_USDE_27NOV2025_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.915e18
        });
        Id id = params.id();

        assertEq(morphoUsdsVault.curator(),  address(0));
        assertEq(morphoUsdsVault.guardian(), address(0));
        assertEq(morphoUsdsVault.timelock(), 1 days);

        // Curator cannot set SupplyCap
        vm.prank(ETH_CURATOR_MULTISIG);
        vm.expectRevert(NotCuratorRole.selector);
        morphoUsdsVault.submitCap(
            params,
            1_500_000_000e18
        );

        // Guardian can't revoke pending cap.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        vm.expectRevert(NotCuratorNorGuardianRole.selector);
        morphoUsdsVault.revokePendingCap(id);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdsVault.curator(),  ETH_CURATOR_MULTISIG);
        assertEq(morphoUsdsVault.guardian(), ETH_GUARDIAN_MULTISIG);
        assertEq(morphoUsdsVault.timelock(), 10 days);

        // Clear any pending cap for the market.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        morphoUsdsVault.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(ETH_CURATOR_MULTISIG);
        morphoUsdsVault.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoUsdsVault.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        morphoUsdsVault.revokePendingCap(id);

        pendingCap = morphoUsdsVault.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Boundary test for submitCap()

        vm.prank(ETH_CURATOR_MULTISIG);
        morphoUsdsVault.submitCap(
            params,
            800_000_000e18
        );

        pendingCap = morphoUsdsVault.pendingCap(id);
        assertEq(pendingCap.value, 800_000_000e18);

        skip(10 days - 1);

        // acceptCap() should fail 1 second before the timelock.

        vm.expectRevert(TimelockNotElapsed.selector);
        morphoUsdsVault.acceptCap(params);

        skip(1 seconds);

        // acceptCap() should pass

        morphoUsdsVault.acceptCap(params);

        MarketConfig memory config = morphoUsdsVault.config(id);
        assertEq(config.cap, 800_000_000e18);
    }

    function test_ETHEREUM_morphoVaultBcUSDC_updateRoles() external onChain(ChainIdUtils.Ethereum()) {
        IMetaMorpho morphoVaultBcUSDC = IMetaMorpho(Ethereum.MORPHO_VAULT_USDC_BC);

        MarketParams memory params = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.CBBTC,
            oracle:          CBBTC_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        Id id = params.id();

        assertEq(morphoVaultBcUSDC.curator(),  address(0));
        assertEq(morphoVaultBcUSDC.guardian(), address(0));
        assertEq(morphoVaultBcUSDC.timelock(), 1 days);

        // Curator cannot set SupplyCap
        vm.prank(ETH_CURATOR_MULTISIG);
        vm.expectRevert(NotCuratorRole.selector);
        morphoVaultBcUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Guardian cannot revoke
        vm.prank(ETH_GUARDIAN_MULTISIG);
        vm.expectRevert(NotCuratorNorGuardianRole.selector);
        morphoVaultBcUSDC.revokePendingCap(id);

        _executeAllPayloadsAndBridges();

        assertEq(morphoVaultBcUSDC.curator(),  ETH_CURATOR_MULTISIG);
        assertEq(morphoVaultBcUSDC.guardian(), ETH_GUARDIAN_MULTISIG);
        assertEq(morphoVaultBcUSDC.timelock(), 10 days);

        // Clear any pending cap for the market.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        morphoVaultBcUSDC.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(ETH_CURATOR_MULTISIG);
        morphoVaultBcUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        morphoVaultBcUSDC.revokePendingCap(id);

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Boundary test for submitCap()

        vm.prank(ETH_CURATOR_MULTISIG);
        morphoVaultBcUSDC.submitCap(
            params,
            800_000_000e18
        );

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 800_000_000e18);

        skip(10 days - 1);

        // acceptCap() should fail 1 second before the timelock.

        vm.expectRevert(TimelockNotElapsed.selector);
        morphoVaultBcUSDC.acceptCap(params);

        skip(1 seconds);

        // acceptCap() should pass

        morphoVaultBcUSDC.acceptCap(params);

        MarketConfig memory config = morphoVaultBcUSDC.config(id);
        assertEq(config.cap, 800_000_000e18);
    }

    function test_BASE_morphoVaultUSDC_updateRoles() external onChain(ChainIdUtils.Base()) {
        IMetaMorpho morphoVaultUSDC = IMetaMorpho(Base.MORPHO_VAULT_SUSDC);

        MarketParams memory params = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: WETH,
            oracle:          ETH_ORACLE,
            irm:             Base.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        Id id = params.id();

        assertEq(morphoVaultUSDC.curator(),  address(0));
        assertEq(morphoVaultUSDC.guardian(), address(0));
        assertEq(morphoVaultUSDC.timelock(), 1 days);

        // Curator cannot set SupplyCap.
        vm.prank(BASE_CURATOR_MULTISIG);
        vm.expectRevert(NotCuratorRole.selector);
        morphoVaultUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        // Guardian should not be able to revoke the Pending Cap.
        vm.prank(BASE_GUARDIAN_MULTISIG);
        vm.expectRevert(NotCuratorNorGuardianRole.selector);
        morphoVaultUSDC.revokePendingCap(id);

        _executeAllPayloadsAndBridges();

        assertEq(morphoVaultUSDC.curator(),  BASE_CURATOR_MULTISIG);
        assertEq(morphoVaultUSDC.guardian(), BASE_GUARDIAN_MULTISIG);
        assertEq(morphoVaultUSDC.timelock(), 10 days);

        // Clear any pending cap for the market.
        vm.prank(BASE_GUARDIAN_MULTISIG);
        morphoVaultUSDC.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(BASE_CURATOR_MULTISIG);
        morphoVaultUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(BASE_GUARDIAN_MULTISIG);
        morphoVaultUSDC.revokePendingCap(id);

        pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Boundary test for submitCap()

        vm.prank(BASE_CURATOR_MULTISIG);
        morphoVaultUSDC.submitCap(
            params,
            800_000_000e18
        );

        pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 800_000_000e18);

        skip(10 days - 1);

        // acceptCap() should fail 1 second before the timelock.

        vm.expectRevert(TimelockNotElapsed.selector);
        morphoVaultUSDC.acceptCap(params);

        skip(1 seconds);

        // acceptCap() should pass

        morphoVaultUSDC.acceptCap(params);

        MarketConfig memory config = morphoVaultUSDC.config(id);
        assertEq(config.cap, 800_000_000e18);
    }

    function test_ETHEREUM_ARBITRUM_sUsdsDistributions() public {
        IERC4626 susds = IERC4626(Ethereum.SUSDS);
        IERC20   usds  = IERC20(Ethereum.USDS);

        vm.selectFork(chainData[ChainIdUtils.Ethereum()].domain.forkId);

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  30_389_488.445801365846236778e18);
        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);

        vm.selectFork(chainData[ChainIdUtils.ArbitrumOne()].domain.forkId);

        uint256 startingArbSUsdsShares = IERC4626(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY);

        _executeAllPayloadsAndBridges();

        uint256 newShares = IERC4626(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY) - startingArbSUsdsShares;

        vm.selectFork(chainData[ChainIdUtils.Ethereum()].domain.forkId);

        assertEq(susds.convertToAssets(newShares), 250_000_000e18 - 1);

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  30_389_488.445801365846236778e18);
        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);
    }

    function test_ETHEREUM_OPTIMISM_sUsdsDistributions() public {
        IERC4626 susds = IERC4626(Ethereum.SUSDS);
        IERC20   usds  = IERC20(Ethereum.USDS);

        vm.selectFork(chainData[ChainIdUtils.Ethereum()].domain.forkId);

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  30_389_488.445801365846236778e18);
        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);

        vm.selectFork(chainData[ChainIdUtils.Optimism()].domain.forkId);

        uint256 startingOptimismSUsdsShares = IERC4626(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY);

        _executeAllPayloadsAndBridges();

        uint256 newShares = IERC4626(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY) - startingOptimismSUsdsShares;

        vm.selectFork(chainData[ChainIdUtils.Ethereum()].domain.forkId);

        assertEq(susds.convertToAssets(newShares), 100_000_000e18 - 1);

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  30_389_488.445801365846236778e18);
        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);
    }

}
