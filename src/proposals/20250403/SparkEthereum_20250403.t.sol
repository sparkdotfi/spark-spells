// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { DataTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from 'spark-alm-controller/src/MainnetController.sol';
import { ForeignController } from 'spark-alm-controller/src/ForeignController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';
import { IRateLimits }       from 'spark-alm-controller/src/interfaces/IRateLimits.sol';

import { ReserveConfig } from "src/test-harness/ProtocolV3TestBase.sol";
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

import { SparkLiquidityLayerContext } from "../../test-harness/SparkLiquidityLayerTests.sol";

interface IInvestmentManager {
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;
    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares
    ) external;
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;
}

interface ISuperstateToken is IERC20 {
    function calculateSuperstateTokenOut(uint256, address)
        external view returns (uint256, uint256, uint256);
}

interface IMapleTokenExtended is IERC4626 {
    function manager() external view returns (address);
}

interface IWithdrawalManagerLike {
    function processRedemptions(uint256 maxSharesToProcess) external;
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (IWithdrawalManagerLike);
    function poolDelegate() external view returns (address);
}

contract SparkEthereum_20250403Test is SparkTestBase {

    address internal constant ETHEREUM_OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c;
    
    address internal constant BASE_OLD_ALM_CONTROLLER     = Base.ALM_CONTROLLER;
    address internal constant BASE_NEW_ALM_CONTROLLER     = 0xB94378b5347a3E199AF3575719F67A708a5D8b9B;

    address internal constant ARBITRUM_OLD_ALM_CONTROLLER = Arbitrum.ALM_CONTROLLER;
    address internal constant ARBITRUM_NEW_ALM_CONTROLLER = 0x98f567464e91e9B4831d3509024b7868f9F79ee1;

    address internal constant BUIDL         = 0x6a9DA2D710BB9B700acde7Cb81F10F1fF8C89041;
    address internal constant BUIDL_DEPOSIT = address(1);  // TODO
    address internal constant BUIDL_REDEEM  = address(1);  // TODO

    address constant CENTRIFUGE_JTSRY_VAULT        = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;
    address constant CENTRIFUGE_JTSRY_TOKEN        = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    uint64  constant CENTRIFUGE_JTREASURY_POOL_ID  = 4139607887;
    bytes16 constant CENTRIFUGE_JTSRY_TRANCHE_ID   = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant CENTRIFUGE_USDC_ASSET_ID      = 242333941209166991950178742833476896417;
    address constant CENTRIFUGE_ROOT               = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
    address constant CENTRIFUGE_INVESTMENT_MANAGER = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;

    address internal constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    constructor() {
        id = '20250403';
    }

    function setUp() public {
        // March 25, 2025
        setupDomains({
            mainnetForkBlock:     22138004,
            baseForkBlock:        28143096,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 320065046
        });
        
        deployPayloads();
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: ETHEREUM_OLD_ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_BASE_controllerUpgrade() public onChain(ChainIdUtils.Base()) {
        _testControllerUpgrade({
            oldController: BASE_OLD_ALM_CONTROLLER,
            newController: BASE_NEW_ALM_CONTROLLER
        });
    }

    function test_ARBITRUM_controllerUpgrade() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testControllerUpgrade({
            oldController: ARBITRUM_OLD_ALM_CONTROLLER,
            newController: ARBITRUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_blackrockBUIDLOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        executeAllPayloadsAndBridges();

        IERC20 usdc  = IERC20(Ethereum.USDC);
        IERC20 buidl = IERC20(BUIDL);

        // USDS -> USDC limits are 50m, go a bit below in case some is in use
        uint256 mintAmount = 40_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(buidl.balanceOf(address(ctx.proxy)), 0);

        controller.transferAsset(address(usdc), BUIDL_DEPOSIT, mintAmount);
        vm.stopPrank();

        // Emulate BUIDL deposit
        deal(BUIDL, address(ctx.proxy), mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(buidl.balanceOf(address(ctx.proxy)), mintAmount);

        vm.prank(ctx.relayer);
        controller.transferAsset(address(buidl), BUIDL_REDEEM, mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(buidl.balanceOf(address(ctx.proxy)), 0);
    }

    function test_ETHEREUM_superstateUSTBOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        executeAllPayloadsAndBridges();

        IERC20 usdc           = IERC20(Ethereum.USDC);
        ISuperstateToken ustb = ISuperstateToken(Ethereum.USTB);

        // USDS -> USDC limits are 50m, go a bit below in case some is in use
        uint256 mintAmount = 40_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(ustb.balanceOf(address(ctx.proxy)), 0);

        (uint256 ustbShares,,) = ustb.calculateSuperstateTokenOut(mintAmount, address(usdc));

        controller.subscribeSuperstate(mintAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(ctx.proxy)), 0);
        assertEq(ustb.balanceOf(address(ctx.proxy)), ustbShares);

        vm.prank(ctx.relayer);
        controller.redeemSuperstate(ustbShares / 10);

        assertApproxEqAbs(usdc.balanceOf(address(ctx.proxy)), mintAmount / 10, 10);
        assertApproxEqAbs(ustb.balanceOf(address(ctx.proxy)), ustbShares * 9 / 10, 1);
    }

    function test_ETHEREUM_centrifugeJTRSYOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        executeAllPayloadsAndBridges();

        IERC20 usdc  = IERC20(Ethereum.USDC);
        IERC20 jtrsy = IERC20(CENTRIFUGE_JTSRY_TOKEN);

        // USDS -> USDC limits are 50m, go a bit below in case some is in use
        uint256 mintAmount = 40_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        controller.requestDepositERC7540(CENTRIFUGE_JTSRY_VAULT, mintAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        _centrifugeFulfillDepositRequest(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.claimDepositERC7540(CENTRIFUGE_JTSRY_VAULT);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), mintAmount / 2);

        vm.prank(ctx.relayer);
        controller.requestRedeemERC7540(CENTRIFUGE_JTSRY_VAULT, mintAmount / 2);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        _centrifugeFulfillRedeemRequest(mintAmount / 2);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.claimRedeemERC7540(CENTRIFUGE_JTSRY_VAULT);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);
    }

    function _centrifugeFulfillDepositRequest(uint256 amountUsdc) internal {
        uint128 _amountUsdc = uint128(amountUsdc);
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // Fulfill request at price 2.0
        vm.prank(CENTRIFUGE_ROOT);
        IInvestmentManager(CENTRIFUGE_INVESTMENT_MANAGER).fulfillDepositRequest(
            CENTRIFUGE_JTREASURY_POOL_ID,
            CENTRIFUGE_JTSRY_TRANCHE_ID,
            address(ctx.proxy),
            CENTRIFUGE_USDC_ASSET_ID,
            _amountUsdc,
            _amountUsdc / 2
        );
    }

    function _centrifugeFulfillRedeemRequest(uint256 amountJtrsy) internal {
        uint128 _amountJtrsy = uint128(amountJtrsy);
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // Fulfill request at price 2.0
        vm.prank(CENTRIFUGE_ROOT);
        IInvestmentManager(CENTRIFUGE_INVESTMENT_MANAGER).fulfillRedeemRequest(
            CENTRIFUGE_JTREASURY_POOL_ID,
            CENTRIFUGE_JTSRY_TRANCHE_ID,
            address(ctx.proxy),
            CENTRIFUGE_USDC_ASSET_ID,
            _amountJtrsy * 2,
            _amountJtrsy
        );
    }

    function test_ETHEREUM_mapleSyrupUSDCOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        address vault                 = SYRUP_USDC;
        uint256 expectedDepositAmount = 25_000_000e6;
        uint256 depositMax            = 25_000_000e6;
        uint256 depositSlope          = 5_000_000e6 / uint256(1 days);
        IERC20 usdc                   = IERC20(Ethereum.USDC);
        IMapleTokenExtended syrup     = IMapleTokenExtended(vault);
        
        // Slightly modify code from _testERC4626Onboarding due to async redemption
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        bool unlimitedDeposit = depositMax == type(uint256).max;
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_DEPOSIT(),
            vault
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_WITHDRAW(),
            vault
        );

        _assertRateLimit(depositKey, 0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);

        executeAllPayloadsAndBridges();

        ctx.controller = ETHEREUM_NEW_ALM_CONTROLLER;

        vm.startPrank(ctx.relayer);
        MainnetController(ctx.controller).mintUSDS(expectedDepositAmount * 1e12);
        MainnetController(ctx.controller).swapUSDSToUSDC(expectedDepositAmount);
        vm.stopPrank();

        _assertRateLimit(depositKey, depositMax, depositSlope);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        if (!unlimitedDeposit) {
            vm.prank(ctx.relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            MainnetController(ctx.controller).depositERC4626(vault, depositMax + 1);
        }

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
        assertEq(usdc.balanceOf(address(ctx.proxy)),              expectedDepositAmount);
        assertEq(syrup.balanceOf(address(ctx.proxy)),             0);

        vm.prank(ctx.relayer);
        uint256 shares = MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);
        assertGt(shares, 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  unlimitedDeposit ? type(uint256).max : depositMax - expectedDepositAmount);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
        assertEq(usdc.balanceOf(address(ctx.proxy)),              0);
        assertEq(syrup.balanceOf(address(ctx.proxy)),             shares);

        vm.prank(ctx.relayer);
        MainnetController(ctx.controller).requestMapleRedemption(vault, shares / 2);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertApproxEqAbs(syrup.balanceOf(address(ctx.proxy)), shares / 2, 1);
        
        IWithdrawalManagerLike withdrawManager = IPoolManagerLike(syrup.manager()).withdrawalManager();
        vm.prank(IPoolManagerLike(syrup.manager()).poolDelegate());
        withdrawManager.processRedemptions(shares / 2);

        assertApproxEqAbs(usdc.balanceOf(address(ctx.proxy)),  expectedDepositAmount / 2, 1);
        assertApproxEqAbs(syrup.balanceOf(address(ctx.proxy)), shares / 2, 1);

        if (!unlimitedDeposit) {
            // Do some sanity checks on the slope
            // This is to catch things like forgetting to divide to a per-second time, etc

            // We assume it takes at least 1 day to recharge to max
            uint256 dailySlope = depositSlope * 1 days;
            assertLe(dailySlope, depositMax);

            // It shouldn't take more than 30 days to recharge to max
            uint256 monthlySlope = depositSlope * 30 days;
            assertGe(monthlySlope, depositMax);
        }
    }

    function test_ETHEREUM_sparkLend_usdcUpdates() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        bytes32 usdcDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
            Ethereum.USDC_ATOKEN
        );

        _assertSupplyCapConfig(Ethereum.USDC, 0, 0, 0);
        _assertBorrowCapConfig(Ethereum.USDC, 57_000_000, 6_000_000, 12 hours);
        _assertRateLimit(usdcDepositKey, 20_000_000e6, 10_000_000e6 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.USDC, 1_000_000_000, 150_000_000, 12 hours);
        _assertBorrowCapConfig(Ethereum.USDC, 950_000_000, 50_000_000, 12 hours);
        _assertRateLimit(usdcDepositKey, 100_000_000e6, 50_000_000e6 / uint256(1 days));
    }

}
