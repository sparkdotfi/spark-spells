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
import { Gnosis }    from "spark-address-registry/Gnosis.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency }     from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }      from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "spark-alm-controller/lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";

import { UserConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/UserConfiguration.sol";

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

interface IPositionManagerLike {

    function transferFrom(address from, address to, uint256 id) external;

    function getPoolAndPositionInfo(uint256 tokenId)
        external view returns (PoolKey memory poolKey, PositionInfo info);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function nextTokenId() external view returns (uint256 nextTokenId);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory poolKeys);

}

interface IV4QuoterLike {

    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool    zeroForOne;
        uint128 exactAmount;
        bytes   hookData;
    }

    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external returns (uint256 amountOut, uint256 gasEstimate);

}

contract MockAggregator {

    int256 public latestAnswer;

    constructor(int256 _latestAnswer) {
        latestAnswer = _latestAnswer;
    }

}

import { console2 } from "forge-std/console2.sol";

contract SparkEthereum_20260129_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xE43c41356CbBa9449fE6CF27c6182F62C4FB3fE9;

    address internal constant _V4_QUOTER = 0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1768896843;  // 2026-01-20T08:14:00Z
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

    struct UniswapV4DepositWithdrawParams {
        bytes32 poolId;
        uint256 depositAmount0;
        uint256 depositAmount1;
        uint128 liquidity;
        int24   tickLower;
        int24   tickUpper;
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4PYUSDUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        bytes32 depositPoolId  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  PYUSD_USDS_POOL_ID));
        bytes32 withdrawPoolId = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), PYUSD_USDS_POOL_ID));
        bytes32 swapPoolId     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     PYUSD_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(PYUSD_USDS_POOL_ID)))), 0);
        
        _assertRateLimit(depositPoolId,  0, 0);
        _assertRateLimit(withdrawPoolId, 0, 0);
        _assertRateLimit(swapPoolId,     0, 0);

        (int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing) = controller.uniswapV4TickLimits(PYUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(PYUSD_USDS_POOL_ID)))), 0.999e18);

        _assertRateLimit(depositPoolId,  10_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawPoolId, 50_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapPoolId,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        (_tickLowerMin, _tickUpperMax, _maxTickSpacing) = controller.uniswapV4TickLimits(PYUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   276_314);
        assertEq(_tickUpperMax,   276_334);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4DepositWithdraw(
            UniswapV4DepositWithdrawParams({
                poolId         : PYUSD_USDS_POOL_ID,
                depositAmount0 : 1_000_000e6,
                depositAmount1 : 1_000_000e18,
                liquidity      : 1_000_000e12,
                tickLower      : 276_314,
                tickUpper      : 276_324
            })
        );
        _testUniswapV4Swap({
            poolId : PYUSD_USDS_POOL_ID
        });
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4USDTUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        bytes32 depositPoolId  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  USDT_USDS_POOL_ID));
        bytes32 withdrawPoolId = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), USDT_USDS_POOL_ID));
        bytes32 swapPoolId     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     USDT_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(USDT_USDS_POOL_ID)))), 0);
        
        _assertRateLimit(depositPoolId,  0, 0);
        _assertRateLimit(withdrawPoolId, 0, 0);
        _assertRateLimit(swapPoolId,     0, 0);

        (int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing) = controller.uniswapV4TickLimits(USDT_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(USDT_USDS_POOL_ID)))), 0.998e18);

        _assertRateLimit(depositPoolId,  5_000_000e18, 50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawPoolId, 50_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapPoolId,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        (_tickLowerMin, _tickUpperMax, _maxTickSpacing) = controller.uniswapV4TickLimits(USDT_USDS_POOL_ID);

        assertEq(_tickLowerMin,   276_304);
        assertEq(_tickUpperMax,   276_344);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4DepositWithdraw(
            UniswapV4DepositWithdrawParams({
                poolId         : USDT_USDS_POOL_ID,
                depositAmount0 : 1_000_000e6,
                depositAmount1 : 1_000_000e18,
                liquidity      : 1_000_000e12,
                tickLower      : 276_304,
                tickUpper      : 276_314
            })
        );
        _testUniswapV4Swap({
            poolId : USDT_USDS_POOL_ID
        });
    }

    function _testUniswapV4DepositWithdraw(UniswapV4DepositWithdrawParams memory params) internal {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(params.poolId));

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        uint256 rateLimitBeforeCall = controller.rateLimits().getCurrentRateLimit(
            keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  params.poolId))
        );

        // Increase position.

        deal(
            Currency.unwrap(poolKey.currency0),
            address(ctx.proxy),
            params.depositAmount0
        );
        deal(
            Currency.unwrap(poolKey.currency1),
            address(ctx.proxy),
            params.depositAmount1
        );

        uint256 token0BeforeCall = _getBalanceOf(poolKey.currency0, address(ctx.proxy));
        uint256 token1BeforeCall = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        vm.prank(ctx.relayer);
        controller.mintPositionUniswapV4({
            poolId     : params.poolId,
            tickLower  : params.tickLower,
            tickUpper  : params.tickUpper,
            liquidity  : params.liquidity,
            amount0Max : params.depositAmount0,
            amount1Max : params.depositAmount1
        });

        uint256 amount0Received = token0BeforeCall - _getBalanceOf(poolKey.currency0, address(ctx.proxy));
        uint256 amount1Received = token1BeforeCall - _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        assertEq(
            rateLimitBeforeCall - controller.rateLimits().getCurrentRateLimit(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  params.poolId))
            ),
            _toNormalizedAmount(poolKey.currency0, amount0Received) +
            _toNormalizedAmount(poolKey.currency1, amount1Received)
        );

        uint256 tokenId = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).nextTokenId() - 1;

        assertEq(IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).ownerOf(tokenId), address(ctx.proxy));

        assertEq(IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).getPositionLiquidity(tokenId), params.liquidity);

        // Decrease position.

        token0BeforeCall = _getBalanceOf(poolKey.currency0, address(ctx.proxy));
        token1BeforeCall = _getBalanceOf(poolKey.currency1, address(ctx.proxy));

        rateLimitBeforeCall = controller.rateLimits().getCurrentRateLimit(
            keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), params.poolId))
        );

        uint256 positionLiquidityBeforeCall = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).getPositionLiquidity(tokenId);

        vm.prank(ctx.relayer);
        controller.decreaseLiquidityUniswapV4({
            poolId            : params.poolId,
            tokenId           : tokenId,
            liquidityDecrease : params.liquidity,
            amount0Min        : 0,
            amount1Min        : 0
        });

        amount0Received = _getBalanceOf(poolKey.currency0, address(ctx.proxy)) - token0BeforeCall;
        amount1Received = _getBalanceOf(poolKey.currency1, address(ctx.proxy)) - token1BeforeCall;

        assertEq(
            rateLimitBeforeCall - controller.rateLimits().getCurrentRateLimit(
                keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), params.poolId))
            ),
            _toNormalizedAmount(poolKey.currency0, amount0Received) +
            _toNormalizedAmount(poolKey.currency1, amount1Received)
        );

        assertEq(
            IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).getPositionLiquidity(tokenId),
            positionLiquidityBeforeCall - params.liquidity
        );
    }

    function _testUniswapV4Swap(bytes32 poolId) internal {
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        Currency currencyIn  = poolKey.currency0;
        Currency currencyOut = poolKey.currency1;

        uint128 swapAmount = uint128(10_000 * 10 ** IERC20Metadata(Currency.unwrap(currencyIn)).decimals());

        bytes32 swapPoolId = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(), poolId));

        deal(
            Currency.unwrap(currencyIn),
            address(ctx.proxy), _getBalanceOf(currencyIn, address(ctx.proxy)) + swapAmount
        );

        uint256 token0BeforeCall    = _getBalanceOf(currencyIn, address(ctx.proxy));
        uint256 token1BeforeCall    = _getBalanceOf(currencyOut, address(ctx.proxy));
        uint128 amountOutMin        = _getSwapAmountOutMin(poolId, Currency.unwrap(currencyIn), swapAmount, 1.5e18);
        uint256 rateLimitBeforeCall = controller.rateLimits().getCurrentRateLimit(swapPoolId);

        vm.prank(ctx.relayer);
        controller.swapUniswapV4({
            poolId       : poolId,
            tokenIn      : Currency.unwrap(currencyIn),
            amountIn     : swapAmount,
            amountOutMin : amountOutMin
        });

        assertEq(token0BeforeCall - _getBalanceOf(currencyIn, address(ctx.proxy)),  swapAmount);
        assertGe(_getBalanceOf(currencyOut, address(ctx.proxy)) - token1BeforeCall, amountOutMin);

        assertEq(
            rateLimitBeforeCall - controller.rateLimits().getCurrentRateLimit(swapPoolId),
            _toNormalizedAmount(currencyIn, swapAmount)
        );
    }

    function _getSwapAmountOutMin(
        bytes32 poolId,
        address tokenIn,
        uint128 amountIn,
        uint256 maxSlippage
    )
        internal returns (uint128 amountOutMin)
    {
        PoolKey memory poolKey = IPositionManagerLike(UniswapV4Lib._POSITION_MANAGER).poolKeys(bytes25(poolId));

        address token0 = Currency.unwrap(poolKey.currency0);

        IV4QuoterLike.QuoteExactSingleParams memory params = IV4QuoterLike.QuoteExactSingleParams({
            poolKey     : poolKey,
            zeroForOne  : tokenIn == token0,
            exactAmount : amountIn,
            hookData    : bytes("")
        });

        ( uint256 amountOut, ) = IV4QuoterLike(_V4_QUOTER).quoteExactInputSingle(params);

        console2.log("Amount In: %s", amountIn);
        console2.log("Amount out: %s", amountOut);
        console2.log("Max Slippage: %s", maxSlippage);

        return uint128((amountOut * maxSlippage) / 1e18);
    }

    function _toNormalizedAmount(Currency currency, uint256 amount)
        internal view returns (uint256 normalizedAmount)
    {
        return amount * 1e18 / (10 ** IERC20Metadata(Currency.unwrap(currency)).decimals());
    }

    function _getBalanceOf(Currency currency, address  account)
        internal view returns (uint256 balance)
    {
        return IERC20(Currency.unwrap(currency)).balanceOf(account);
    }

}

contract SparkEthereum_20260129_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;
    using SafeERC20 for IERC20;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1768896843;  // 2026-01-20T08:14:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
    }

    function test_GNOSIS_sparkLend_deprecateMarket() external onChain(ChainIdUtils.Gnosis()) {
        address[] memory reserves = IPool(Gnosis.POOL).getReservesList();

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveConfigurationMap memory config = IPool(Gnosis.POOL).getConfiguration(reserves[i]);

            assertEq(config.getActive(), true);
            assertEq(config.getPaused(), false);
            assertEq(config.getFrozen(), false);
        }

        _executeAllPayloadsAndBridges();

        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveConfigurationMap memory config = IPool(Gnosis.POOL).getConfiguration(reserves[i]);

            assertEq(config.getActive(), true);
            assertEq(config.getPaused(), false);
            assertEq(config.getFrozen(), true);

            assertEq(config.getReserveFactor(), 50_00);

            if(reserves[i] == Gnosis.EURE) continue;
            _testUserActionsAfterPayloadExecutionSparkLend(reserves[i], reserves[i] != Gnosis.USDC ? Gnosis.USDC : Gnosis.USDT);
        }
    }

    function test_ETHEREUM_sparkLend_deprecateTBTC() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.TBTC);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 20_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.TBTC);

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 99_00);

        _testUserActionsAfterPayloadExecutionSparkLend(Ethereum.TBTC, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateEZETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.EZETH);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.EZETH);

        assertEq(newConfig.getActive(),        true);
        assertEq(newConfig.getPaused(),        false);
        assertEq(newConfig.getFrozen(),        true);
        assertEq(newConfig.getReserveFactor(), 15_00);

        _testUserActionsAfterPayloadExecutionSparkLend(Ethereum.EZETH, Ethereum.USDC);
    }

    function test_ETHEREUM_sparkLend_deprecateRSETH() external onChain(ChainIdUtils.Ethereum()) {
        DataTypes.ReserveConfigurationMap memory oldConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.RSETH);

        assertEq(oldConfig.getActive(),        true);
        assertEq(oldConfig.getPaused(),        false);
        assertEq(oldConfig.getFrozen(),        false);
        assertEq(oldConfig.getReserveFactor(), 15_00);

        _executeAllPayloadsAndBridges();

        DataTypes.ReserveConfigurationMap memory newConfig = IPool(SparkLend.POOL).getConfiguration(Ethereum.RSETH);

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

        IPool pool = IPool(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.POOL : SparkLend.POOL);

        deal(collateralAsset, testUser, collateralAmount);

        vm.startPrank(testUser);

        IERC20(collateralAsset).approve(
            block.chainid == ChainIdUtils.Gnosis() ? address(Gnosis.POOL) : address(SparkLend.POOL),
            type(uint256).max
        );

        // User can't supply.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.supply(collateralAsset, collateralAmount, testUser, 0);

        // User can't borrow.
        vm.expectRevert(bytes("28"));  // RESERVE_FROZEN
        pool.borrow(collateralAsset, debtAmount, 2, 0, testUser);

        vm.stopPrank();

        // If the reserve is not active or has a debt ceiling, skip the test as user collateral enabled will be false.
        if(pool.getReserveData(collateralAsset).configuration.getLtv() == 0) return;
        if(pool.getReserveData(collateralAsset).configuration.getDebtCeiling() > 0) return;

        _setupUserSparkLendPosition(collateralAsset, debtAsset, testUser, collateralAmount, debtAmount);

        // User can repay the debt.
        deal(debtAsset, testUser, debtAmount);

        vm.startPrank(testUser);

        IERC20(debtAsset).safeIncreaseAllowance(
            block.chainid == ChainIdUtils.Gnosis() ? address(Gnosis.POOL) : address(SparkLend.POOL),
            type(uint256).max
        );

        pool.repay(debtAsset, debtAmount, 2, testUser);

        // User can withdraw the collateral.
        pool.withdraw(collateralAsset, 1 * 10 ** IERC20Metadata(collateralAsset).decimals(), testUser);

        vm.stopPrank();

        _setupUserSparkLendPosition(collateralAsset, debtAsset, testUser, collateralAmount, debtAmount);

        // Manipulate the price oracle used by sparklend.
        address mockOracle = address(new MockAggregator(1));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);
        assets[0]  = collateralAsset;
        sources[0] = mockOracle;

        if(block.chainid == ChainIdUtils.Gnosis()) {
            vm.prank(Gnosis.AMB_EXECUTOR);
            AaveOracle(Gnosis.AAVE_ORACLE).setAssetSources(assets, sources);
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            AaveOracle(SparkLend.AAVE_ORACLE).setAssetSources(assets, sources);
        }

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
        IPool pool = IPool(block.chainid == ChainIdUtils.Gnosis() ? Gnosis.POOL : SparkLend.POOL);

        deal(collateralAsset, testUser, collateralAmount);

        vm.prank(testUser);
        IERC20(collateralAsset).approve(
            block.chainid == ChainIdUtils.Gnosis() ? address(Gnosis.POOL) : address(SparkLend.POOL),
            type(uint256).max
        );

        // Set Reserve frozen to false.
        if(block.chainid == ChainIdUtils.Gnosis()) {
            vm.startPrank(Gnosis.AMB_EXECUTOR);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, false);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(debtAsset,       false);
            vm.stopPrank();
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, false);
        }

        vm.startPrank(testUser);

        pool.supply(collateralAsset, collateralAmount, testUser, 0);
        pool.borrow(debtAsset,       debtAmount,       2,          0, testUser);

        vm.stopPrank();

        // Set Reserve frozen to true.
        if(block.chainid == ChainIdUtils.Gnosis()) {
            vm.startPrank(Gnosis.AMB_EXECUTOR);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, true);
            IPoolConfigurator(Gnosis.POOL_CONFIGURATOR).setReserveFreeze(debtAsset,       true);
            vm.stopPrank();
        } else {
            vm.prank(Ethereum.SPARK_PROXY);
            IPoolConfigurator(SparkLend.POOL_CONFIGURATOR).setReserveFreeze(collateralAsset, true);
        }
    }

}

contract SparkEthereum_20260129_SpellTests is SpellTests {

    uint256 internal constant FOUNDATION_GRANT_AMOUNT = 1_100_000e18;

    constructor() {
        _spellId   = 20260129;
        _blockDate = 1768896843;  // 2026-01-20T08:14:00Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0xCE352d9429A5e10b29D3d610C7217f9333e04aB4;
    }

    function test_ETHEREUM_sparkLend_withdrawAllReserves() external onChain(ChainIdUtils.Ethereum()) {
        address[] memory reserves             = IPool(SparkLend.POOL).getReservesList();
        uint256[] memory aTokenBalancesBefore = new uint256[](reserves.length);

        for(uint256 i = 0; i < reserves.length; i++) {
            address aToken = IPool(SparkLend.POOL).getReserveData(reserves[i]).aTokenAddress;

            if(
                aToken != SparkLend.DAI_SPTOKEN   &&
                aToken != SparkLend.USDS_SPTOKEN  &&
                aToken != SparkLend.USDC_SPTOKEN  &&
                aToken != SparkLend.PYUSD_SPTOKEN &&
                aToken != SparkLend.USDT_SPTOKEN
            ) {
                aTokenBalancesBefore[i] = IERC20(aToken).balanceOf(Ethereum.ALM_OPS_MULTISIG);
            } else {
                aTokenBalancesBefore[i] = IERC20(aToken).balanceOf(Ethereum.ALM_PROXY);
            }
        }

        _executeAllPayloadsAndBridges();

        for(uint256 i = 0; i < reserves.length; i++) {
            address aToken = IPool(SparkLend.POOL).getReserveData(reserves[i]).aTokenAddress;

            if(
                aToken != SparkLend.DAI_SPTOKEN   &&
                aToken != SparkLend.USDS_SPTOKEN  &&
                aToken != SparkLend.USDC_SPTOKEN  &&
                aToken != SparkLend.PYUSD_SPTOKEN &&
                aToken != SparkLend.USDT_SPTOKEN
            ) {
                assertGe(IERC20(aToken).balanceOf(Ethereum.ALM_OPS_MULTISIG), aTokenBalancesBefore[i]);
            } else {
                assertGe(IERC20(aToken).balanceOf(Ethereum.ALM_PROXY), aTokenBalancesBefore[i]);
            }
        }
    }

    function test_ETHEREUM_sparkTreasury_foundationGrant() external onChain(ChainIdUtils.Ethereum()) {
        uint256 proxyBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);

        assertEq(proxyBalanceBefore,      30_389_488.445801365846236778e18);
        assertEq(foundationBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               proxyBalanceBefore - FOUNDATION_GRANT_AMOUNT);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
    }

}
