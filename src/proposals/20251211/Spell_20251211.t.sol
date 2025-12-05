// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { VmSafe }   from "forge-std/Vm.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ISyrupLike,
    ISparkVaultV2Like,
    IALMProxyFreezableLike,
    IMorphoVaultLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IArkisVaultLike is IERC4626 {

    struct Metadata {
        address   asset;
        uint256   totalAssetsThreshold;
        address[] markets;
        address[] investors;
        address   curator;
        uint80    performanceFee;
        bool      isPrivate;
    }

    function allocateAssets(address market, uint256 amount) external;
    function exitAssets(address market, uint256 amount) external;

    function info() external view returns (Metadata memory);

}

interface IArkisMarketLike is IERC4626 {

    struct Metadata {
        address   leverage;
        uint32    apy;
        uint256   totalDepositThreshold;
        address[] collaterals;
        address[] lenders;
        address[] borrowers;
    }

    struct Whitelist {
        address[] tokens;
        address[] operators;
    }

    function borrow(address borrower, uint192 amount) external;

    function repay(address borrower, uint256 balance, bool isLiquidation) external;

    function BORROWER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function LENDER_ROLE() external view returns (bytes32);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function info() external view returns (Metadata memory, Whitelist memory);

    function setApy(uint32 apy) external;

}

contract SparkEthereum_20251211_SLLTests is SparkLiquidityLayerTests {

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant ARKIS_FACTORY  = 0x7ad1dd2516F1499852aAEb95a33D7Ec1BA31b5C3;
    address internal constant ARKIS_MARKET   = 0xcDE9CA90aCd83b57b47ae5ccEf610FDA3049225B;
    address internal constant BORROWER1      = 0x907856BD487C405e48f96f45b451A7b6dDf801e3;
    address internal constant BORROWER2      = 0x50B82f42D51D875b1bfdd946ad27AeE2a6b1AB41;
    address internal constant BORROWER3      = 0xCB04cD15967DD4c725dE5DE487e3715b39f75f42;
    address internal constant DISPATCHER     = 0x2f01D7CFfe62673B3D2b680295A2D047F3848e4c;
    address internal constant MARKET_FACTORY = 0xe70d11D23F36826C58f30C61B4DeAf0A89a6D837;

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-03T18:58:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;

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

    function test_ETHEREUM_arkisVaultConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        IArkisVaultLike  vault  = IArkisVaultLike(ARKIS);

        IArkisVaultLike.Metadata memory vaultInfo = vault.info();

        // Vault Info

        assertEq(vaultInfo.asset,                Ethereum.USDC);
        assertEq(vaultInfo.totalAssetsThreshold, 0);
        assertEq(vaultInfo.markets.length,       1);
        assertEq(vaultInfo.investors.length,     1);
        assertEq(vaultInfo.curator,              Ethereum.ALM_OPS_MULTISIG);
        assertEq(vaultInfo.performanceFee,       0);
        assertEq(vaultInfo.isPrivate,            true);

        assertEq(vaultInfo.markets[0],   ARKIS_MARKET);
        assertEq(vaultInfo.investors[0], Ethereum.ALM_PROXY);

        // Vault

        assertEq(vault.name(),        "Spark Prime USDC 1");
        assertEq(vault.symbol(),      "sparkPrimeUSDC1");
        assertEq(vault.asset(),       Ethereum.USDC);
        assertEq(vault.decimals(),    6);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_ETHEREUM_arkisMarketConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        address arkisHYPE          = 0xB299784Ba2F23e4FD92f7fcb6F1Edb64363C242E;
        address arkis_stNEAR_Bybit = 0xE93A0B00c0E3d623cC7Ec45486247E5a05B698E8;
        address arkis_stHYPE       = 0xb8C259072CAcE7aC812e0d98fEF34799724174e2;

        address curveRouter  = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e;
        address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

        IArkisMarketLike market = IArkisMarketLike(ARKIS_MARKET);

        (
            IArkisMarketLike.Metadata  memory marketInfo,
            IArkisMarketLike.Whitelist memory whitelist
        ) = market.info();

        // Market Info

        assertEq(marketInfo.leverage,              Ethereum.USDC);
        assertEq(marketInfo.apy,                   665);
        assertEq(marketInfo.totalDepositThreshold, 30_000_000e6);
        assertEq(marketInfo.collaterals.length,    8);
        assertEq(marketInfo.lenders.length,        1);
        assertEq(marketInfo.borrowers.length,      3);

        assertEq(marketInfo.collaterals[0], Ethereum.WBTC);
        assertEq(marketInfo.collaterals[1], Ethereum.WSTETH);
        assertEq(marketInfo.collaterals[2], Ethereum.USDC);
        assertEq(marketInfo.collaterals[3], arkisHYPE);
        assertEq(marketInfo.collaterals[4], Ethereum.WETH);
        assertEq(marketInfo.collaterals[5], arkis_stNEAR_Bybit);
        assertEq(marketInfo.collaterals[6], arkis_stHYPE);
        assertEq(marketInfo.collaterals[7], Ethereum.USDT);

        assertEq(marketInfo.lenders[0], ARKIS);

        assertEq(marketInfo.borrowers[0], BORROWER1);
        assertEq(marketInfo.borrowers[1], BORROWER2);
        assertEq(marketInfo.borrowers[2], BORROWER3);

        // Whitelist

        assertEq(whitelist.tokens.length,    8);
        assertEq(whitelist.operators.length, 2);

        assertEq(whitelist.tokens[0], Ethereum.WBTC);
        assertEq(whitelist.tokens[1], Ethereum.WSTETH);
        assertEq(whitelist.tokens[2], Ethereum.USDC);
        assertEq(whitelist.tokens[3], arkisHYPE);
        assertEq(whitelist.tokens[4], Ethereum.WETH);
        assertEq(whitelist.tokens[5], arkis_stNEAR_Bybit);
        assertEq(whitelist.tokens[6], arkis_stHYPE);
        assertEq(whitelist.tokens[7], Ethereum.USDT);

        assertEq(whitelist.operators[0], curveRouter);
        assertEq(whitelist.operators[1], pendleRouter);

        // Market

        assertEq(market.getRoleMemberCount(market.BORROWER_ROLE()),      3);
        assertEq(market.getRoleMemberCount(market.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(market.getRoleMemberCount(market.LENDER_ROLE()),        1);

        assertEq(market.getRoleMember(market.BORROWER_ROLE(),      0), BORROWER1);
        assertEq(market.getRoleMember(market.BORROWER_ROLE(),      1), BORROWER2);
        assertEq(market.getRoleMember(market.BORROWER_ROLE(),      2), BORROWER3);
        assertEq(market.getRoleMember(market.DEFAULT_ADMIN_ROLE(), 0), MARKET_FACTORY);
        assertEq(market.getRoleMember(market.LENDER_ROLE(),        0), ARKIS);

        assertEq(market.name(),        "Spark Leveraged Carry ERC4626");
        assertEq(market.symbol(),      "Spark-Leveraged-Carry-ERC4626");
        assertEq(market.asset(),       Ethereum.USDC);
        assertEq(market.decimals(),    6);
        assertEq(market.totalSupply(), 0);
        assertEq(market.totalAssets(), 0);
    }

    function test_ETHEREUM_arkisE2ETest() external onChain(ChainIdUtils.Ethereum()) {
        IArkisVaultLike  vault  = IArkisVaultLike(ARKIS);
        IArkisMarketLike market = IArkisMarketLike(ARKIS_MARKET);
        IERC20           usdc   = IERC20(Ethereum.USDC);

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        deal(address(usdc), address(ctx.proxy), 1_000_000e6);

        _executeAllPayloadsAndBridges();

        // Step 1: Deposit 1m USDC into the vault from SLL

        vm.prank(ctx.relayer);
        uint256 shares = MainnetController(ctx.controller).depositERC4626(address(vault), 1_000_000e6);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);
        assertEq(vault.totalAssets(),           1_000_000e6);

        skip(1 days);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);  // No value accrual
        assertEq(vault.totalAssets(),           1_000_000e6);

        assertEq(market.totalAssets(), 0);

        // Step 2: Allocate 1m USDC to market as the curator

        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        vault.allocateAssets(ARKIS_MARKET, 1_000_000e6);

        assertEq(market.totalAssets(), 1_000_000e6);

        skip(1 days);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);  // No value accrual
        assertEq(vault.totalAssets(),           1_000_000e6);
        assertEq(market.totalAssets(),          1_000_000e6);

        // Step 3: Borrow 1m USDC from the market

        vm.prank(DISPATCHER);
        market.borrow(BORROWER1, 1_000_000e6);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);
        assertEq(vault.totalAssets(),           1_000_000e6);
        assertEq(market.totalAssets(),          1_000_000e6);

        skip(1 days);

        uint256 expectedAssets = 1_000_000e6 + 1_000_000e6 * uint256(665) / 10000 / 365;

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Rounding
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          expectedAssets);

        // Step 4: Repay and borrow again atomically to trigger compound interest

        uint256 repayAmount = expectedAssets + 1;  // Rounding

        deal(address(usdc), DISPATCHER, repayAmount);

        vm.startPrank(DISPATCHER);
        usdc.approve(address(market), repayAmount);
        market.repay(BORROWER1, repayAmount, false);
        market.borrow(BORROWER1, uint192(expectedAssets));
        vm.stopPrank();

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Rounding
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          expectedAssets);

        skip(1 days);

        expectedAssets = expectedAssets + expectedAssets * 1 * uint256(665) / 10000 / 365;

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Rounding
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          expectedAssets);

        // Step 5: Repay as borrower

        repayAmount = expectedAssets + 1;  // Rounding

        deal(address(usdc), DISPATCHER, repayAmount);

        vm.startPrank(DISPATCHER);
        usdc.approve(address(market), repayAmount);
        market.repay(BORROWER1, repayAmount, false);
        vm.stopPrank();

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Rounding
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          expectedAssets);

        // Step 6: Warp to check value accrual stops

        skip(1 days);

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Value accrual stops
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          expectedAssets);

        // Step 7: Withdraw as curator

        vm.startPrank(Ethereum.ALM_OPS_MULTISIG);
        vault.exitAssets(ARKIS_MARKET, expectedAssets);
        vm.stopPrank();

        assertEq(vault.convertToAssets(shares), expectedAssets - 1);  // Rounding
        assertEq(vault.totalAssets(),           expectedAssets);
        assertEq(market.totalAssets(),          0);

        // Step 8: Withdraw from SLL

        vm.prank(ctx.relayer);
        MainnetController(ctx.controller).withdrawERC4626(address(vault), expectedAssets - 1);  // Rounding

        assertEq(vault.balanceOf(address(ctx.proxy)), 0);  // Don't need to assert underlying

        assertEq(vault.totalAssets(),  1);
        assertEq(market.totalAssets(), 0);

        assertEq(usdc.balanceOf(address(ctx.proxy)), expectedAssets - 1);
        assertEq(usdc.balanceOf(address(ctx.proxy)), 1_000_364.416753e6);
    }

    function test_ETHEREUM_arkisE2ETest_fullYear() external onChain(ChainIdUtils.Ethereum()) {
        IArkisVaultLike  vault  = IArkisVaultLike(ARKIS);
        IArkisMarketLike market = IArkisMarketLike(ARKIS_MARKET);
        IERC20           usdc   = IERC20(Ethereum.USDC);

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        deal(address(usdc), address(ctx.proxy), 1_000_000e6);

        _executeAllPayloadsAndBridges();

        // Step 1: Deposit 1m USDC into the vault from SLL

        vm.prank(ctx.relayer);
        uint256 shares = MainnetController(ctx.controller).depositERC4626(address(vault), 1_000_000e6);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);
        assertEq(vault.totalAssets(),           1_000_000e6);

        // Step 2: Allocate 1m USDC to market as the curator

        vm.prank(Ethereum.ALM_OPS_MULTISIG);
        vault.allocateAssets(ARKIS_MARKET, 1_000_000e6);

        // Step 3: Borrow 1m USDC from the market and assert value accrues at 6.65% annually

        vm.prank(DISPATCHER);
        market.borrow(BORROWER1, 1_000_000e6);

        assertEq(vault.convertToAssets(shares), 1_000_000e6);
        assertEq(vault.totalAssets(),           1_000_000e6);
        assertEq(market.totalAssets(),          1_000_000e6);

        skip(365 days);

        assertEq(vault.convertToAssets(shares), 1_066_500e6 - 1);  // Rounding
        assertEq(vault.totalAssets(),           1_066_500e6);
        assertEq(market.totalAssets(),          1_066_500e6);
    }

    function test_ETHEREUM_onboardingAnchorage() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            ANCHORAGE
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 50_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDC,
            destination    : ANCHORAGE,
            transferKey    : transferKey,
            transferAmount : 1_000_000e6
        }));
    }

    function test_ETHEREUM_onboardingArkis() external onChain(ChainIdUtils.Ethereum()) {
        _testERC4626Onboarding({
            vault                 : ARKIS,
            expectedDepositAmount : 1_000_000e6,
            depositMax            : 5_000_000e6,
            depositSlope          : 5_000_000e6 / uint256(1 days),
            tolerance             : 10,
            skipInitialCheck      : false
        });
    }

    function test_ETHEREUM_sparkVaultsV2_configureSPPYUSD() external onChain(ChainIdUtils.Ethereum()) {
        _testVaultConfiguration({
            asset:      Ethereum.PYUSD,
            name:       "Spark Savings PYUSD",
            symbol:     "spPYUSD",
            rho:        1764599075,
            vault_:     Ethereum.SPARK_VAULT_V2_SPPYUSD,
            minVsr:     1e27,
            maxVsr:     TEN_PCT_APY,
            depositCap: 250_000_000e6,
            amount:     1_000_000e6
        });
    }

    function test_ETHEREUM_sparkVaultSetterRoleChanges() external onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like spUsdc = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like spUsdt = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);
        ISparkVaultV2Like spEth  = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH);

        bytes32 SETTER_ROLE = spUsdc.SETTER_ROLE();

        assertEq(spUsdc.hasRole(SETTER_ROLE, Ethereum.ALM_OPS_MULTISIG), true);
        assertEq(spUsdt.hasRole(SETTER_ROLE, Ethereum.ALM_OPS_MULTISIG), true);
        assertEq(spEth.hasRole(SETTER_ROLE,  Ethereum.ALM_OPS_MULTISIG), true);

        assertEq(spUsdc.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(spUsdt.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(spEth.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(spUsdc.getRoleMemberCount(SETTER_ROLE), 1);
        assertEq(spUsdt.getRoleMemberCount(SETTER_ROLE), 1);
        assertEq(spEth.getRoleMemberCount(SETTER_ROLE),  1);

        assertEq(spUsdc.hasRole(SETTER_ROLE, Ethereum.ALM_OPS_MULTISIG), false);
        assertEq(spUsdt.hasRole(SETTER_ROLE, Ethereum.ALM_OPS_MULTISIG), false);
        assertEq(spEth.hasRole(SETTER_ROLE,  Ethereum.ALM_OPS_MULTISIG), false);

        assertEq(spUsdc.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(spUsdt.hasRole(SETTER_ROLE, Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(spEth.hasRole(SETTER_ROLE,  Ethereum.ALM_PROXY_FREEZABLE), true);
    }

    function test_ETHEREUM_morphoVaultAllocatorRoleChanges() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultLike morphoUsdc = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC);
        IMorphoVaultLike morphoUsds = IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS);

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_RELAYER_MULTISIG), true);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_RELAYER_MULTISIG), true);

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), false);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_RELAYER_MULTISIG), false);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_RELAYER_MULTISIG), false);

        assertEq(morphoUsdc.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);
        assertEq(morphoUsds.isAllocator(Ethereum.ALM_PROXY_FREEZABLE), true);
    }

    function test_ETHEREUM_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Ethereum()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Ethereum.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Ethereum.ALM_RELAYER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), false);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Ethereum.ALM_FREEZER_MULTISIG),          false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),                   true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Ethereum.SPARK_PROXY);

        vm.recordLogs();

        _executeMainnetPayload();  // Have to use this to properly load logs on mainnet

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Ethereum.ALM_RELAYER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG), true);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Ethereum.ALM_FREEZER_MULTISIG),          true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Ethereum.SPARK_PROXY),                   true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](3);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Ethereum.ALM_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Ethereum.ALM_FREEZER_MULTISIG);
    }

    function test_AVALANCHE_sparkVaultSetterRoleChanges() external onChain(ChainIdUtils.Avalanche()) {
        ISparkVaultV2Like vault = ISparkVaultV2Like(Avalanche.SPARK_VAULT_V2_SPUSDC);

        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_OPS_MULTISIG),    true);
        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_OPS_MULTISIG),    false);
        assertEq(vault.hasRole(vault.SETTER_ROLE(), Avalanche.ALM_PROXY_FREEZABLE), true);

        assertEq(vault.getRoleMemberCount(vault.SETTER_ROLE()), 1);
    }

    function test_AVALANCHE_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Avalanche()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Avalanche.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Avalanche.ALM_RELAYER),    false);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Avalanche.ALM_RELAYER2),   false);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Avalanche.ALM_FREEZER),    false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR), true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Avalanche.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Avalanche.ALM_RELAYER),    true);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Avalanche.ALM_RELAYER2),   true);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Avalanche.ALM_FREEZER),    true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Avalanche.SPARK_EXECUTOR), true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Avalanche.ALM_RELAYER);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Avalanche.ALM_RELAYER2);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Avalanche.ALM_FREEZER);
    }

    function test_BASE_morphoVaultAllocatorRoleChanges() external onChain(ChainIdUtils.Base()) {
        IMorphoVaultLike morphoUsdc = IMorphoVaultLike(Base.MORPHO_VAULT_SUSDC);

        assertEq(morphoUsdc.isAllocator(Base.ALM_RELAYER),         true);
        assertEq(morphoUsdc.isAllocator(Base.ALM_PROXY_FREEZABLE), false);

        _executeAllPayloadsAndBridges();

        assertEq(morphoUsdc.isAllocator(Base.ALM_RELAYER),         false);
        assertEq(morphoUsdc.isAllocator(Base.ALM_PROXY_FREEZABLE), true);
    }

    function test_BASE_ALMProxyFreezableConfiguration() external onChain(ChainIdUtils.Base()) {
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(Base.ALM_PROXY_FREEZABLE);

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Base.ALM_RELAYER),    false);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Base.ALM_RELAYER2),   false);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Base.ALM_FREEZER),    false);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Base.SPARK_EXECUTOR), true);

        VmSafe.EthGetLogs[] memory roleLogs = _getEvents(block.chainid, address(proxy), RoleGranted.selector);

        assertEq(roleLogs.length, 1);

        assertEq32(roleLogs[0].topics[1], proxy.DEFAULT_ADMIN_ROLE());

        assertEq(address(uint160(uint256(roleLogs[0].topics[2]))), Base.SPARK_EXECUTOR);

        RecordedLogs.init();

        _executeAllPayloadsAndBridges();

        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Base.ALM_RELAYER),    true);
        assertEq(proxy.hasRole(proxy.CONTROLLER(),         Base.ALM_RELAYER2),   true);
        assertEq(proxy.hasRole(proxy.FREEZER(),            Base.ALM_FREEZER),    true);
        assertEq(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), Base.SPARK_EXECUTOR), true);

        VmSafe.Log[] memory recordedLogs = vm.getRecordedLogs();  // This gets the logs of all payloads
        VmSafe.Log[] memory newLogs      = new VmSafe.Log[](7);

        uint256 j = 0;
        for (uint256 i = 0; i < recordedLogs.length; ++i) {
            if (recordedLogs[i].emitter   != address(proxy))       continue;
            if (recordedLogs[i].topics[0] != RoleGranted.selector) continue;
            newLogs[j] = recordedLogs[i];
            j++;
        }

        assertEq32(newLogs[0].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[1].topics[1], proxy.CONTROLLER());
        assertEq32(newLogs[2].topics[1], proxy.FREEZER());

        assertEq(address(uint160(uint256(newLogs[0].topics[2]))), Base.ALM_RELAYER);
        assertEq(address(uint160(uint256(newLogs[1].topics[2]))), Base.ALM_RELAYER2);
        assertEq(address(uint160(uint256(newLogs[2].topics[2]))), Base.ALM_FREEZER);
    }

}

contract SparkEthereum_20251211_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-02T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;
    }

}

contract SparkEthereum_20251211_SpellTests is SpellTests {

    uint256 internal constant AMOUNT_TO_ASSET_FOUNDATION = 150_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION       = 1_100_000e18;

    address internal constant SPARK_ASSET_FOUNDATION = 0xEabCb8C0346Ac072437362f1692706BA5768A911;

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-02T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  345_775_075.648347910394560559e18);
        assertEq(spUsdsBalanceBefore, 182_567_680.712149092854209493e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 3_568.313310802219726430e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 1_612.873159374336061895e18);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore                = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationUsdsBalanceBefore           = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 sparkAssetFoundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION);

        assertEq(sparkUsdsBalanceBefore,                31_639_488.445801365846236778e18);
        assertEq(foundationUsdsBalanceBefore,           5_100_000e18);
        assertEq(sparkAssetFoundationUsdsBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkUsdsBalanceBefore - AMOUNT_TO_FOUNDATION - AMOUNT_TO_ASSET_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationUsdsBalanceBefore + AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(SPARK_ASSET_FOUNDATION),             sparkAssetFoundationUsdsBalanceBefore + AMOUNT_TO_ASSET_FOUNDATION);
    }

}
