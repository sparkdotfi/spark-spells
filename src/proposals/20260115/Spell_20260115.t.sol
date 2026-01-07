// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';
import { VmSafe }   from "forge-std/Vm.sol";

import { IMetaMorpho, MarketParams, Id, PendingUint192 } from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParamsLib }                               from "lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { IPool } from "sparklend-v1-core/interfaces/IPool.sol";

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

    address internal constant CURVE_WETHWETHNG = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20260115;
        _blockDate = "2026-01-06T11:27:00Z";
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
            pool:                        CURVE_WETHWETHNG,
            expectedDepositAmountToken0: 0,
            expectedSwapAmountToken0:    10e18,
            maxSlippage:                 0.9975e18,
            swapLimit:                   RateLimitData(100e18, 1_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(0, 0),
            withdrawLimit:               RateLimitData(0, 0)
        });

        ICurvePoolLike pool = ICurvePoolLike(CURVE_WETHWETHNG);

        assertEq(pool.A(),   5_000);
        assertEq(pool.fee(), 0.00005e10);  // 0.005%

        assertEq(pool.offpeg_fee_multiplier(), 10e10);
    }

}

contract SparkEthereum_20260115_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260115;
        _blockDate = "2026-01-06T11:27:00Z";
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

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

    address internal constant SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG     = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG    = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDC_MORPHO_VAULT_CURATOR_MULTISIG     = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG    = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant CBBTC_PRICE_FEED              = 0xA6D6950c9F177F1De7f7757FB33539e3Ec60182a;
    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;
    address internal constant ETH                           = 0x4200000000000000000000000000000000000006;
    address internal constant ETH_ORACLE                    = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;

    constructor() {
        _spellId   = 20260115;
        _blockDate = "2026-01-06T14:35:00Z";
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

        assertEq(spDaiBalanceBefore,  333_849_082.286915784892880274e18);
        assertEq(spUsdsBalanceBefore, 223_853_707.572674573310461547e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 76_005.838616609321226274e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 29_341.248141612364654571e18);
    }

    function test_ETHEREUM_killSwitchActivationForLBTC() external onChain(ChainIdUtils.Ethereum()) {
        IKillSwitchOracle kso = IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE);

        assertEq(kso.numOracles(),                           1);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE),      0);

        _executeAllPayloadsAndBridges();

        assertEq(kso.numOracles(),                      2);
        assertEq(kso.oracleThresholds(LBTC_BTC_ORACLE), 0.95e8);
        
        // Sanity check the latest answers
        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 1.00175168e8);

        // Should not be able to trigger either
        vm.expectRevert("KillSwitchOracle/price-above-threshold");
        kso.trigger(LBTC_BTC_ORACLE);

        // Replace both Chainlink aggregator with MockAggregator reporting below
        // threshold prices
        vm.store(
            LBTC_BTC_ORACLE,
            bytes32(uint256(2)),
            bytes32((uint256(uint160(address(new MockAggregator(0.95e8)))) << 16) | 1)
        );

        assertEq(IChainlinkAggregator(LBTC_BTC_ORACLE).latestAnswer(), 0.95e8);

        assertEq(kso.triggered(), false);

        assertEq(_getBorrowEnabled(Ethereum.DAI),    true);
        assertEq(_getBorrowEnabled(Ethereum.SDAI),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDC),   true);
        assertEq(_getBorrowEnabled(Ethereum.WETH),   true);
        assertEq(_getBorrowEnabled(Ethereum.WSTETH), true);
        assertEq(_getBorrowEnabled(Ethereum.WBTC),   false);
        assertEq(_getBorrowEnabled(Ethereum.GNO),    false);
        assertEq(_getBorrowEnabled(Ethereum.RETH),   true);
        assertEq(_getBorrowEnabled(Ethereum.USDT),   true);
        assertEq(_getBorrowEnabled(Ethereum.LBTC),   false);

        kso.trigger(LBTC_BTC_ORACLE);

        assertEq(kso.triggered(), true);

        assertEq(_getBorrowEnabled(Ethereum.DAI),    false);
        assertEq(_getBorrowEnabled(Ethereum.SDAI),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDC),   false);
        assertEq(_getBorrowEnabled(Ethereum.WETH),   false);
        assertEq(_getBorrowEnabled(Ethereum.WSTETH), false);
        assertEq(_getBorrowEnabled(Ethereum.WBTC),   false);
        assertEq(_getBorrowEnabled(Ethereum.GNO),    false);
        assertEq(_getBorrowEnabled(Ethereum.RETH),   false);
        assertEq(_getBorrowEnabled(Ethereum.USDT),   false);
        assertEq(_getBorrowEnabled(Ethereum.LBTC),   false);
    }

    function _getBorrowEnabled(address asset) internal view returns (bool) {
        return ReserveConfiguration.getBorrowingEnabled(
            IPool(SparkLend.POOL).getConfiguration(asset)
        );
    }

    function test_ETHEREUM_morphoVaultUSDS_updateRoles() external onChain(ChainIdUtils.Ethereum()) {
        IMetaMorpho morphoUsdsVault = IMetaMorpho(Ethereum.MORPHO_VAULT_USDS);

        assertEq(morphoUsdsVault.curator(),  address(0));
        assertEq(morphoUsdsVault.guardian(), address(0));
        assertEq(morphoUsdsVault.timelock(), 1 days);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdsVault.curator(),  SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG);
        assertEq(morphoUsdsVault.guardian(), SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        assertEq(morphoUsdsVault.timelock(), 10 days);

        MarketParams memory params = MarketParams({
            loanToken:       Ethereum.USDS,
            collateralToken: PT_USDE_27NOV2025,
            oracle:          PT_USDE_27NOV2025_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.915e18
        });
        Id id = params.id();

        // Clear any pending cap for the market.
        vm.prank(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoUsdsVault.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG);
        morphoUsdsVault.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoUsdsVault.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoUsdsVault.revokePendingCap(id);

        pendingCap = morphoUsdsVault.pendingCap(id);
        assertEq(pendingCap.value, 0);
    }

    function test_ETHEREUM_morphoVaultBcUSDC_updateRoles() external onChain(ChainIdUtils.Ethereum()) {
        IMetaMorpho morphoVaultBcUSDC = IMetaMorpho(Ethereum.MORPHO_VAULT_USDC_BC);

        assertEq(morphoVaultBcUSDC.curator(),  address(0));
        assertEq(morphoVaultBcUSDC.guardian(), address(0));
        assertEq(morphoVaultBcUSDC.timelock(), 1 days);

        _executeAllPayloadsAndBridges();

        assertEq(morphoVaultBcUSDC.curator(),  SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        assertEq(morphoVaultBcUSDC.guardian(), SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        assertEq(morphoVaultBcUSDC.timelock(), 10 days);

        MarketParams memory params = MarketParams({
            loanToken:       Ethereum.USDC,
            collateralToken: Ethereum.CBBTC,
            oracle:          CBBTC_PRICE_FEED,
            irm:             Ethereum.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        Id id = params.id();

        // Clear any pending cap for the market.
        vm.prank(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoVaultBcUSDC.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG);
        morphoVaultBcUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoVaultBcUSDC.revokePendingCap(id);

        pendingCap = morphoVaultBcUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);
    }

    function test_BASE_morphoVaultUSDC_updateRoles() external onChain(ChainIdUtils.Base()) {
        IMetaMorpho morphoVaultUSDC = IMetaMorpho(Base.MORPHO_VAULT_SUSDC);

        assertEq(morphoVaultUSDC.curator(),  address(0));
        assertEq(morphoVaultUSDC.guardian(), address(0));
        assertEq(morphoVaultUSDC.timelock(), 1 days);

        _executeAllPayloadsAndBridges();

        assertEq(morphoVaultUSDC.curator(),  SPARK_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        assertEq(morphoVaultUSDC.guardian(), SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        assertEq(morphoVaultUSDC.timelock(), 10 days);

        MarketParams memory params = MarketParams({
            loanToken:       Base.USDC,
            collateralToken: ETH,
            oracle:          ETH_ORACLE,
            irm:             Base.MORPHO_DEFAULT_IRM,
            lltv:            0.86e18
        });
        Id id = params.id();

        // Clear any pending cap for the market.
        vm.prank(SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoVaultUSDC.revokePendingCap(id);

        // Curator setting supply cap should work.
        vm.prank(SPARK_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        morphoVaultUSDC.submitCap(
            params,
            1_500_000_000e18
        );

        PendingUint192 memory pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 1_500_000_000e18);

        // Guardian should be able to revoke the Pending Cap set by curator.
        vm.prank(SPARK_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        morphoVaultUSDC.revokePendingCap(id);

        pendingCap = morphoVaultUSDC.pendingCap(id);
        assertEq(pendingCap.value, 0);
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like ethVault  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(ethVault.depositCap(),  100_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 1_000_000_000e6);
        assertEq(ethVault.depositCap(),  250_000e18);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         1_000_000_000e6,
            expectedMaxDeposit: 780_023_691.407679e6
        });

        _test_vault_depositBoundaryLimit({
            vault:              ethVault,
            depositCap:         250_000e18,
            expectedMaxDeposit: 235_812.755774673383848284e18
        });
    }

    function test_AVALANCHE_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(usdcVault.depositCap(), 250_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 500_000_000e6);

        _test_vault_depositBoundaryLimit({
            vault:              usdcVault,
            depositCap:         500_000_000e6,
            expectedMaxDeposit: 299_916_771.645952e6
        });
    }

    function _test_vault_depositBoundaryLimit(
        ISparkVaultV2Like vault,
        uint256           depositCap,
        uint256           expectedMaxDeposit
    ) internal {
        address asset = vault.asset();

        uint256 maxDeposit = depositCap - vault.totalAssets();

        assertEq(maxDeposit, expectedMaxDeposit);

        // Fails on depositing more than max
        vm.expectRevert("SparkVault/deposit-cap-exceeded");
        vault.deposit(maxDeposit + 1, address(this));

        // Can deposit less than or equal to maxDeposit

        assertEq(vault.balanceOf(address(this)), 0);

        deal(asset, address(this), maxDeposit);
        IERC20(asset).approve(address(vault), maxDeposit);

        uint256 shares = vault.deposit(maxDeposit, address(this));

        assertEq(vault.balanceOf(address(this)), shares);
    }

    function test_ETHEREUM_ARBITRUM_OPTIMISM_sUsdsDistributions() public {
        vm.selectFork(chainData[ChainIdUtils.Optimism()].domain.forkId);

        uint256 startingOptimismSUsdsShares = IERC4626(Optimism.SUSDS).balanceOf(Base.ALM_PROXY);

        vm.selectFork(chainData[ChainIdUtils.ArbitrumOne()].domain.forkId);

        uint256 arbSUsdsShares = IERC4626(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY);

        _executeAllPayloadsAndBridges();
        
        assertEq(IERC20(Arbitrum.USDS).balanceOf(Arbitrum.ALM_PROXY) - arbSUsdsShares, 250_000_000e18);

        vm.selectFork(chainData[ChainIdUtils.Optimism()].domain.forkId);

        assertEq(IERC4626(Optimism.SUSDS).balanceOf(Optimism.ALM_PROXY) - startingOptimismSUsdsShares, 100_000_000e18);

        vm.selectFork(chainData[ChainIdUtils.Ethereum()].domain.forkId);

        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.SPARK_PROXY), 0);
    }

}
