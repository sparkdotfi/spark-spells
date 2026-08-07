// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { IHooks } from "spark-alm-controller/lib/uniswap-v4-core/src/interfaces/IHooks.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests}                from "src/test-harness/SpellTests.sol";
import { UniV4Helpers }             from "src/test-harness/UniV4Helpers.sol";

import { ICurvePoolLike } from "src/interfaces/Interfaces.sol";

contract SparkEthereum_20260813_SLLTests is SparkLiquidityLayerTests, UniV4Helpers {

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    address internal constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;

    constructor() {
        _spellId   = 20260813;
        _blockDate = 1785761559;
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4USDGUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  USDS_USDG_POOL_ID));
        bytes32 withdrawKey = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), USDS_USDG_POOL_ID));
        bytes32 swapKey     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     USDS_USDG_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(USDS_USDG_POOL_ID)))), 0);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);

        ( int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing ) = controller.uniswapV4TickLimits(USDS_USDG_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(USDS_USDG_POOL_ID)))), 0.999e18);

        _assertRateLimit(depositKey,  10_000_000e18,     100_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);
        _assertRateLimit(swapKey,     5_000_000e18,      200_000_000e18 / uint256(1 days));

        ( _tickLowerMin, _tickUpperMax, _maxTickSpacing ) = controller.uniswapV4TickLimits(USDS_USDG_POOL_ID);

        assertEq(_tickLowerMin,   -276_334);
        assertEq(_tickUpperMax,   -276_314);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4LimitOrder(USDS_USDG_POOL_ID);
    }

    function test_ETHEREUM_sparkLiquidityLayer_onboardUniswapV4RLUSDUSDS() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey  = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_DEPOSIT(),  RLUSD_USDS_POOL_ID));
        bytes32 withdrawKey = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_WITHDRAW(), RLUSD_USDS_POOL_ID));
        bytes32 swapKey     = keccak256(abi.encode(controller.LIMIT_UNISWAP_V4_SWAP(),     RLUSD_USDS_POOL_ID));

        assertEq(controller.maxSlippages(address(uint160(uint256(RLUSD_USDS_POOL_ID)))), 0);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);

        ( int24 _tickLowerMin, int24 _tickUpperMax, uint24 _maxTickSpacing ) = controller.uniswapV4TickLimits(RLUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   0);
        assertEq(_tickUpperMax,   0);
        assertEq(_maxTickSpacing, 0);

        _executeAllPayloadsAndBridges();

        assertEq(controller.maxSlippages(address(uint160(uint256(RLUSD_USDS_POOL_ID)))), 0.999e18);

        _assertRateLimit(depositKey,  10_000_000e18,     50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);
        _assertRateLimit(swapKey,     5_000_000e18,      100_000_000e18 / uint256(1 days));

        ( _tickLowerMin, _tickUpperMax, _maxTickSpacing ) = controller.uniswapV4TickLimits(RLUSD_USDS_POOL_ID);

        assertEq(_tickLowerMin,   -10);
        assertEq(_tickUpperMax,   10);
        assertEq(_maxTickSpacing, 10);

        _testUniswapV4LimitOrder(RLUSD_USDS_POOL_ID);
    }

    function test_ETHEREUM_curvePoolOnboarding_USDCRLUSD() external onChain(ChainIdUtils.Ethereum()) {
        assertEq(ICurvePoolLike(CURVE_USDC_RLUSD).coins(0), Ethereum.USDC);
        assertEq(ICurvePoolLike(CURVE_USDC_RLUSD).coins(1), RLUSD);

        _testCurveOnboarding({
            controller                  : Ethereum.ALM_CONTROLLER,
            pool                        : CURVE_USDC_RLUSD,
            expectedDepositAmountToken0 : 0,
            expectedSwapAmountToken0    : 500_000e6,  // coins(0) is USDC (6 decimals)
            maxSlippage                 : 0.999e18,
            swapLimit                   : RateLimitData(5_000_000e18, 25_000_000e18 / uint256(1 days)),
            depositLimit                : RateLimitData(0, 0),
            withdrawLimit               : RateLimitData(0, 0)
        });
    }

    function test_ETHEREUM_uniswapV4PoolIdIntegrity() external onChain(ChainIdUtils.Ethereum()) {
        _assertUniswapV4PoolId(USDS_USDG_POOL_ID,  Ethereum.USDS, Ethereum.USDG);
        _assertUniswapV4PoolId(RLUSD_USDS_POOL_ID, RLUSD,         Ethereum.USDS);
    }

    function _assertUniswapV4PoolId(bytes32 poolId, address currency0, address currency1) internal view {
        PoolKey memory expectedPoolKey = PoolKey({
            currency0   : Currency.wrap(currency0),
            currency1   : Currency.wrap(currency1),
            fee         : 5,  // 0.0005%
            tickSpacing : 1,
            hooks       : IHooks(address(0))
        });

        assertEq(keccak256(abi.encode(expectedPoolKey)), poolId);
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }
        super.deal(token, to, amount);
    }

}

contract SparkEthereum_20260813_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260813;
        _blockDate = 1785761559;
    }

}

contract SparkEthereum_20260813_SpellTests is SpellTests {

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 1_756_359e18;

    constructor() {
        _spellId   = 20260813;
        _blockDate = 1785761559;
    }

    function test_ETHEREUM_sparkTreasury_transferExcessUSDSForBuybacks() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore  = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 opsMultisigBalanceBefore = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,  45_236_509.249708907368137212e18);
        assertEq(opsMultisigBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),      sparkProxyBalanceBefore - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG), opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
    }

}
