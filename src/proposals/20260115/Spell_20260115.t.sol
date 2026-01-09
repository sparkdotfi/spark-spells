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

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";

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
    ISyrupLike,
    IPSM3Like
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

interface ITokenBridgeLike {
    function escrow() external returns (address);
}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

contract SparkEthereum_20260115_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767971084;  // 2026-01-09T15:34:00Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Avalanche()].payload = 0x2F66666fB60c038f10948e9645Ca969bb397E2d5;
        chainData[ChainIdUtils.Base()].payload      = 0xeCCA0D296Cb133081d41E9772B60D57F5fd2798E;
        chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;

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
            expectedMaxDeposit: 782_841_456.461691e6
        });

        _testSparkVaultDepositCapBoundary({
            vault:              ethVault,
            depositCap:         250_000e18,
            expectedMaxDeposit: 234_003.969648177695058093e18
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
            expectedMaxDeposit: 298_099_909.3341e6
        });
    }

}

contract SparkEthereum_20260115_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767971084;  // 2026-01-09T15:34:00Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Avalanche()].payload = 0x2F66666fB60c038f10948e9645Ca969bb397E2d5;
        chainData[ChainIdUtils.Base()].payload      = 0xeCCA0D296Cb133081d41E9772B60D57F5fd2798E;
        chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
    }

}

import { console } from "forge-std/console.sol";

contract SparkEthereum_20260115_SpellTests is SpellTests {

    using MarketParamsLib for MarketParams;

    error NotCuratorRole();
    error NotCuratorNorGuardianRole();
    error TimelockNotElapsed();

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

    address internal constant ETH_CURATOR_MULTISIG   = 0x0f963A8A8c01042B69054e787E5763ABbB0646A3;
    address internal constant ETH_GUARDIAN_MULTISIG  = 0xf5748bBeFa17505b2F7222B23ae11584932C908B;
    address internal constant BASE_CURATOR_MULTISIG  = 0x0f963A8A8c01042B69054e787E5763ABbB0646A3;
    address internal constant BASE_GUARDIAN_MULTISIG = 0xf5748bBeFa17505b2F7222B23ae11584932C908B;

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;
    address internal constant WETH                          = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE                    = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    constructor() {
        _spellId   = 20260115;
        _blockDate = 1767971084;  // 2026-01-09T15:34:00Z
    }

    function setUp() public override {
        super.setUp();

        chainData[ChainIdUtils.Avalanche()].payload = 0x2F66666fB60c038f10948e9645Ca969bb397E2d5;
        chainData[ChainIdUtils.Base()].payload      = 0xeCCA0D296Cb133081d41E9772B60D57F5fd2798E;
        chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
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

    function test_ETHEREUM_killSwitchActivationForLBTC() external onChain(ChainIdUtils.Ethereum()) {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),                      1);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),                      2);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0.95e8);

        // Sanity check the latest answers
        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 1.00312712e8);

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

        assertEq(_getBorrowEnabled(reserves[0]),  false);
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

        assertEq(healthFactor, 1.754265816108159361e18);

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

        assertEq(healthFactor, 0.195082661982381210e18);

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
            1_500_000_000e6
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
            1_500_000_000e6
        );

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e6);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(ETH_GUARDIAN_MULTISIG);
        morphoVaultBcUSDC.revokePendingCap(id);

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Boundary test for submitCap()

        vm.prank(ETH_CURATOR_MULTISIG);
        morphoVaultBcUSDC.submitCap(
            params,
            1_500_000_000e6
        );

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e6);

        skip(10 days - 1);

        // acceptCap() should fail 1 second before the timelock.

        vm.expectRevert(TimelockNotElapsed.selector);
        morphoVaultBcUSDC.acceptCap(params);

        skip(1 seconds);

        // acceptCap() should pass

        morphoVaultBcUSDC.acceptCap(params);

        MarketConfig memory config = morphoVaultBcUSDC.config(id);
        assertEq(config.cap, 1_500_000_000e6);
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
            1_500_000_000e6
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
            1_500_000_000e6
        );

        PendingUint192 memory pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e6);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(BASE_GUARDIAN_MULTISIG);
        morphoVaultUSDC.revokePendingCap(id);

        pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);

        // Boundary test for submitCap()

        vm.prank(BASE_CURATOR_MULTISIG);
        morphoVaultUSDC.submitCap(
            params,
            1_500_000_000e6
        );

        pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e6);

        skip(10 days - 1);

        // acceptCap() should fail 1 second before the timelock.

        vm.expectRevert(TimelockNotElapsed.selector);
        morphoVaultUSDC.acceptCap(params);

        skip(1 seconds);

        // acceptCap() should pass

        morphoVaultUSDC.acceptCap(params);

        MarketConfig memory config = morphoVaultUSDC.config(id);
        assertEq(config.cap, 1_500_000_000e6);
    }

    function test_ETHEREUM_ARBITRUM_sUsdsDistributions() public {
        IERC20   usds     = IERC20(Ethereum.USDS);
        IERC4626 susds    = IERC4626(Ethereum.SUSDS);
        IERC4626 arbSusds = IERC4626(Arbitrum.SUSDS);

        address escrow = ITokenBridgeLike(Ethereum.ARBITRUM_TOKEN_BRIDGE).escrow();

        uint256 ethFork = chainData[ChainIdUtils.Ethereum()].domain.forkId;
        uint256 arbFork = chainData[ChainIdUtils.ArbitrumOne()].domain.forkId;

        vm.selectFork(ethFork);

        uint256 sUsdsEscrowBalance    = susds.balanceOf(escrow);
        uint256 usdsSparkProxyBalance = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 usdsTotalSupply       = usds.totalSupply();
        uint256 susdsTotalSupply      = susds.totalSupply();

        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);
        assertEq(susds.balanceOf(escrow),               sUsdsEscrowBalance);
        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  usdsSparkProxyBalance);

        vm.selectFork(arbFork);

        uint256 arbSUsdsProxyBalance = arbSusds.balanceOf(Arbitrum.ALM_PROXY);
        uint256 arbSUsdsTotalSupply  = arbSusds.totalSupply();

        _executeAllPayloadsAndBridges();

        uint256 newShares = arbSusds.balanceOf(Arbitrum.ALM_PROXY) - arbSUsdsProxyBalance;

        assertEq(arbSusds.totalSupply(), arbSUsdsTotalSupply + newShares);

        vm.selectFork(ethFork);

        assertEq(susds.convertToAssets(newShares), 250_000_000e18 - 1);                                        // $250m of value bridged to Arbitrum
        assertEq(susds.totalSupply(),              susdsTotalSupply + susds.convertToShares(350_000_000e18));  // $350m of sUSDS minted to Arbitrum and Optimism

        assertApproxEqAbs(usds.totalSupply(), usdsTotalSupply + 350_000_000e18, 1500e18);  // $350m of USDS minted for Arbitrum and Optimism

        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);                               // No funds remaining in Spark Proxy on Ethereum
        assertEq(susds.balanceOf(escrow),               sUsdsEscrowBalance + newShares);  // $250m of sUSDS held in escrow
        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  usdsSparkProxyBalance);           // No remaining USDS left over
    }

    function test_ETHEREUM_OPTIMISM_sUsdsDistributions() public {
        IERC20   usds    = IERC20(Ethereum.USDS);
        IERC4626 susds   = IERC4626(Ethereum.SUSDS);
        IERC4626 opSusds = IERC4626(Optimism.SUSDS);

        address escrow = ITokenBridgeLike(Ethereum.OPTIMISM_TOKEN_BRIDGE).escrow();

        uint256 ethFork = chainData[ChainIdUtils.Ethereum()].domain.forkId;
        uint256 opFork  = chainData[ChainIdUtils.Optimism()].domain.forkId;

        vm.selectFork(ethFork);

        uint256 sUsdsEscrowBalance    = susds.balanceOf(escrow);
        uint256 usdsSparkProxyBalance = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 usdsTotalSupply       = usds.totalSupply();
        uint256 susdsTotalSupply      = susds.totalSupply();

        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);
        assertEq(susds.balanceOf(escrow),               sUsdsEscrowBalance);
        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  usdsSparkProxyBalance);

        vm.selectFork(opFork);

        uint256 opSUsdsProxyBalance = opSusds.balanceOf(Optimism.ALM_PROXY);
        uint256 opbSUsdsTotalSupply = opSusds.totalSupply();

        _executeAllPayloadsAndBridges();

        uint256 newShares = opSusds.balanceOf(Optimism.ALM_PROXY) - opSUsdsProxyBalance;

        assertEq(opSusds.totalSupply(), opbSUsdsTotalSupply + newShares);

        vm.selectFork(ethFork);

        assertEq(susds.convertToAssets(newShares), 100_000_000e18);                                            // $100m of value bridged to Optimism
        assertEq(susds.totalSupply(),              susdsTotalSupply + susds.convertToShares(350_000_000e18));  // $350m of sUSDS minted to Arbitrum and Optimism

        assertApproxEqAbs(usds.totalSupply(), usdsTotalSupply + 350_000_000e18, 1500e18);  // $350m of USDS minted for Arbitrum and Optimism

        assertEq(susds.balanceOf(Ethereum.SPARK_PROXY), 0);                               // No funds remaining in Spark Proxy on Ethereum
        assertEq(susds.balanceOf(escrow),               sUsdsEscrowBalance + newShares);  // $100m of sUSDS held in escrow
        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),  usdsSparkProxyBalance);           // No remaining USDS left over
    }

    function test_ETHEREUM_ARBITRUM_psm3Deposit() public onChain(ChainIdUtils.ArbitrumOne()) {
        IERC20 arbSusds = IERC20(Arbitrum.SUSDS);

        uint256 startingSUsdsProxyBalance = arbSusds.balanceOf(Arbitrum.ALM_PROXY);

        _executeAllPayloadsAndBridges();

        uint256 newSUsdsProxyBalance = arbSusds.balanceOf(Arbitrum.ALM_PROXY);

        uint256 mintedSUsds = newSUsdsProxyBalance - startingSUsdsProxyBalance;

        assertGe(mintedSUsds, 200_000_000e18);  // Sanity check

        IPSM3Like psm3 = IPSM3Like(Arbitrum.PSM3);

        uint256 sllPsm3Value = psm3.convertToAssetValue(psm3.shares(Arbitrum.ALM_PROXY));

        vm.prank(Arbitrum.ALM_RELAYER);
        uint256 shares = ForeignController(Arbitrum.ALM_CONTROLLER).depositPSM(Arbitrum.SUSDS, mintedSUsds);

        // $250m deposited into PSM3, with some imprecision due to crosschain rateProvider
        assertApproxEqAbs(
            psm3.convertToAssetValue(psm3.shares(Arbitrum.ALM_PROXY)),
            sllPsm3Value + 250_000_000e18,
            10e18
        );

        assertEq(arbSusds.balanceOf(Arbitrum.ALM_PROXY), startingSUsdsProxyBalance); // Back to starting balance
    }

    function test_ETHEREUM_OPTIMISM_psm3Deposit() public onChain(ChainIdUtils.Optimism()) {
        IERC20 opSusds = IERC20(Optimism.SUSDS);

        uint256 startingSUsdsProxyBalance = opSusds.balanceOf(Optimism.ALM_PROXY);

        _executeAllPayloadsAndBridges();

        uint256 newSUsdsProxyBalance = opSusds.balanceOf(Optimism.ALM_PROXY);

        uint256 mintedSUsds = newSUsdsProxyBalance - startingSUsdsProxyBalance;

        assertGe(mintedSUsds, 50_000_000e18);  // Sanity check

        IPSM3Like psm3 = IPSM3Like(Optimism.PSM3);

        uint256 sllPsm3Value = psm3.convertToAssetValue(psm3.shares(Optimism.ALM_PROXY));

        vm.prank(Optimism.ALM_RELAYER);
        uint256 shares = ForeignController(Optimism.ALM_CONTROLLER).depositPSM(Optimism.SUSDS, mintedSUsds);

        // $100m deposited into PSM3, with some imprecision due to crosschain rateProvider
        assertApproxEqAbs(
            psm3.convertToAssetValue(psm3.shares(Optimism.ALM_PROXY)),
            sllPsm3Value + 100_000_000e18,
            11e18
        );

        assertEq(opSusds.balanceOf(Optimism.ALM_PROXY), startingSUsdsProxyBalance);  // Back to starting balance
    }

}
