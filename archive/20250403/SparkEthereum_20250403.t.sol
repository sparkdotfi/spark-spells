// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from 'spark-alm-controller/src/MainnetController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';

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

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

contract SparkEthereum_20250403Test is SparkTestBase {

    address internal constant ETHEREUM_OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c;

    address internal constant BASE_OLD_ALM_CONTROLLER     = Base.ALM_CONTROLLER;
    address internal constant BASE_NEW_ALM_CONTROLLER     = 0xB94378b5347a3E199AF3575719F67A708a5D8b9B;

    address internal constant ARBITRUM_OLD_ALM_CONTROLLER = Arbitrum.ALM_CONTROLLER;
    address internal constant ARBITRUM_NEW_ALM_CONTROLLER = 0x98f567464e91e9B4831d3509024b7868f9F79ee1;

    address internal constant BUIDL         = 0x6a9DA2D710BB9B700acde7Cb81F10F1fF8C89041;
    address internal constant BUIDL_DEPOSIT = 0xD1917664bE3FdAea377f6E8D5BF043ab5C3b1312;
    address internal constant BUIDL_REDEEM  = 0x8780Dd016171B91E4Df47075dA0a947959C34200;
    address internal constant BUIDL_ADMIN   = 0xe01605f6b6dC593b7d2917F4a0940db2A625b09e;

    address constant CENTRIFUGE_JTRSY_VAULT        = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;
    address constant CENTRIFUGE_JTRSY_TOKEN        = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    uint64  constant CENTRIFUGE_JTRSY_POOL_ID      = 4139607887;
    bytes16 constant CENTRIFUGE_JTRSY_TRANCHE_ID   = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant CENTRIFUGE_USDC_ASSET_ID      = 242333941209166991950178742833476896417;
    address constant CENTRIFUGE_ROOT               = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
    address constant CENTRIFUGE_INVESTMENT_MANAGER = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;

    address internal constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    address internal constant PT_USDE_27MAR2025_PRICE_FEED  = 0xA8ccE51046d760291f77eC1EB98147A75730Dcd5;
    address internal constant PT_USDE_27MAR2025             = 0x8A47b431A7D947c6a3ED6E42d501803615a97EAa;
    address internal constant PT_SUSDE_27MAR2025_PRICE_FEED = 0x38d130cEe60CDa080A3b3aC94C79c34B6Fc919A7;
    address internal constant PT_SUSDE_27MAR2025            = 0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;

    constructor() {
        id = '20250403';
    }

    function setUp() public {
        setupDomains("2025-03-31T19:55:30Z");

        deployPayloads();

        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].payload = 0x545eeEc8Ca599085cE86ada51eb8c0c35Af1e9d6;
        chainSpellMetadata[ChainIdUtils.Base()].payload        = 0x43d32D791C35D34d28fa8c33cfB8ca3c6AE0d02d;
        chainSpellMetadata[ChainIdUtils.Ethereum()].payload    = 0x6B34C0E12C84338f494efFbf49534745DDE2F24b;
    }

    // Overriding because of upgrade
    function _getLatestControllers() internal pure override returns (address, address, address) {
        return (
            ETHEREUM_NEW_ALM_CONTROLLER,
            ARBITRUM_NEW_ALM_CONTROLLER,
            BASE_NEW_ALM_CONTROLLER
        );
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

        bytes32 depositKey = RateLimitHelpers.makeAssetDestinationKey(
            controller.LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            BUIDL_DEPOSIT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetDestinationKey(
            controller.LIMIT_ASSET_TRANSFER(),
            BUIDL,
            BUIDL_REDEEM
        );

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  500_000_000e6,     100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        IERC20 usdc  = IERC20(Ethereum.USDC);
        IERC20 buidl = IERC20(BUIDL);

        // USDS -> USDC limits are 200m, go a bit below in case some is in use
        uint256 mintAmount = 190_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        uint256 buidlDepositBalance = usdc.balanceOf(BUIDL_DEPOSIT);
        uint256 buidlRedeemBalance  = buidl.balanceOf(BUIDL_REDEEM);

        assertEq(usdc.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(usdc.balanceOf(BUIDL_DEPOSIT),      buidlDepositBalance);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 500_000_000e6);

        controller.transferAsset(address(usdc), BUIDL_DEPOSIT, mintAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(ctx.proxy)), 0);
        assertEq(usdc.balanceOf(BUIDL_DEPOSIT),      buidlDepositBalance + mintAmount);

        assertEq(buidl.balanceOf(address(ctx.proxy)), 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 500_000_000e6 - mintAmount);

        // Emulate BUIDL deposit
        vm.startPrank(BUIDL_ADMIN);
        IBuidlLike(BUIDL).issueTokens(address(ctx.proxy), mintAmount);
        vm.stopPrank();

        assertEq(buidl.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(buidl.balanceOf(BUIDL_REDEEM),       buidlRedeemBalance);

        vm.prank(ctx.relayer);
        controller.transferAsset(address(buidl), BUIDL_REDEEM, mintAmount);

        assertEq(buidl.balanceOf(address(ctx.proxy)), 0);
        assertEq(buidl.balanceOf(BUIDL_REDEEM),       buidlRedeemBalance + mintAmount);
    }

    function test_ETHEREUM_superstateUSTBOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        IERC20 usdc           = IERC20(Ethereum.USDC);
        ISuperstateToken ustb = ISuperstateToken(Ethereum.USTB);

        bytes32 depositKey        = controller.LIMIT_SUPERSTATE_SUBSCRIBE();
        bytes32 withdrawKey       = controller.LIMIT_SUPERSTATE_REDEEM();
        bytes32 offchainRedeemKey = RateLimitHelpers.makeAssetDestinationKey(
            controller.LIMIT_ASSET_TRANSFER(),
            address(ustb),
            address(ustb)
        );

        _assertRateLimit(depositKey,        0, 0);
        _assertRateLimit(withdrawKey,       0, 0);
        _assertRateLimit(offchainRedeemKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 300_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);
        _assertRateLimit(offchainRedeemKey, type(uint256).max, 0);

        // USDS -> USDC limits are 200m, go a bit below in case some is in use
        uint256 mintAmount = 190_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(ustb.balanceOf(address(ctx.proxy)), 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 300_000_000e6);

        (uint256 ustbShares,,) = ustb.calculateSuperstateTokenOut(mintAmount, address(usdc));

        controller.subscribeSuperstate(mintAmount);
        vm.stopPrank();

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 300_000_000e6 - mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)), 0);
        assertEq(ustb.balanceOf(address(ctx.proxy)), ustbShares);

        // Doing a smaller redeem because there is not necessarily enough liquidity
        vm.prank(ctx.relayer);
        controller.redeemSuperstate(ustbShares / 100);

        assertApproxEqAbs(usdc.balanceOf(address(ctx.proxy)), mintAmount * 1/100, 100);
        assertApproxEqAbs(ustb.balanceOf(address(ctx.proxy)), ustbShares * 99/100, 1);

        uint256 totalSupply = ustb.totalSupply();

        // You can always burn the whole amount by doing it offchain
        uint256 ustbBalance = ustb.balanceOf(address(ctx.proxy));
        vm.prank(ctx.relayer);
        controller.transferAsset(address(ustb), address(ustb), ustbBalance);

        // Transfering to token contract burns the amount
        assertEq(ustb.totalSupply(), totalSupply - ustbBalance);

        // USDC will come back async
        assertApproxEqAbs(usdc.balanceOf(address(ctx.proxy)), mintAmount * 1/100, 100);
        assertEq(ustb.balanceOf(address(ctx.proxy)), 0);
    }

    function test_ETHEREUM_centrifugeJTRSYOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_7540_DEPOSIT(),
            CENTRIFUGE_JTRSY_VAULT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_7540_REDEEM(),
            CENTRIFUGE_JTRSY_VAULT
        );

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 200_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        IERC20 usdc  = IERC20(Ethereum.USDC);
        IERC20 jtrsy = IERC20(CENTRIFUGE_JTRSY_TOKEN);

        // USDS -> USDC limits are 200m, go a bit below in case some is in use
        uint256 mintAmount = 190_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 200_000_000e6);

        controller.requestDepositERC7540(CENTRIFUGE_JTRSY_VAULT, mintAmount);
        vm.stopPrank();

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey), 200_000_000e6 - mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        _centrifugeFulfillDepositRequest(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.claimDepositERC7540(CENTRIFUGE_JTRSY_VAULT);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), mintAmount / 2);

        vm.prank(ctx.relayer);
        controller.requestRedeemERC7540(CENTRIFUGE_JTRSY_VAULT, mintAmount / 2);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        _centrifugeFulfillRedeemRequest(mintAmount / 2);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  0);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);

        vm.prank(ctx.relayer);
        controller.claimRedeemERC7540(CENTRIFUGE_JTRSY_VAULT);

        assertEq(usdc.balanceOf(address(ctx.proxy)),  mintAmount);
        assertEq(jtrsy.balanceOf(address(ctx.proxy)), 0);
    }

    function _centrifugeFulfillDepositRequest(uint256 amountUsdc) internal {
        uint128 _amountUsdc = uint128(amountUsdc);
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        // Fulfill request at price 2.0
        vm.prank(CENTRIFUGE_ROOT);
        IInvestmentManager(CENTRIFUGE_INVESTMENT_MANAGER).fulfillDepositRequest(
            CENTRIFUGE_JTRSY_POOL_ID,
            CENTRIFUGE_JTRSY_TRANCHE_ID,
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
            CENTRIFUGE_JTRSY_POOL_ID,
            CENTRIFUGE_JTRSY_TRANCHE_ID,
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
        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_DEPOSIT(),
            vault
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ctx.controller).LIMIT_4626_WITHDRAW(),
            vault
        );

        _assertRateLimit(depositKey,  0, 0);
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

        vm.prank(ctx.relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        MainnetController(ctx.controller).depositERC4626(vault, depositMax + 1);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  depositMax);
        assertEq(ctx.rateLimits.getCurrentRateLimit(withdrawKey), type(uint256).max);
        assertEq(usdc.balanceOf(address(ctx.proxy)),              expectedDepositAmount);
        assertEq(syrup.balanceOf(address(ctx.proxy)),             0);

        vm.prank(ctx.relayer);
        uint256 shares = MainnetController(ctx.controller).depositERC4626(vault, expectedDepositAmount);
        assertGt(shares, 0);

        assertEq(ctx.rateLimits.getCurrentRateLimit(depositKey),  0);
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
    }

    function test_ETHEREUM_sparkLend_usdcUpdates() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        bytes32 usdcDepositKey = RateLimitHelpers.makeAssetKey(
            MainnetController(ETHEREUM_NEW_ALM_CONTROLLER).LIMIT_AAVE_DEPOSIT(),
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

    function test_ETHEREUM_sllCoreRateLimitIncrease() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdsMintKey       = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER).LIMIT_USDS_MINT();
        bytes32 swapUSDSToUSDCKey = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER).LIMIT_USDS_TO_USDC();

        _assertRateLimit(usdsMintKey,       50_000_000e18, 50_000_000e18 / uint256(1 days));
        _assertRateLimit(swapUSDSToUSDCKey, 50_000_000e6,  50_000_000e6 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertRateLimit(usdsMintKey,       200_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertRateLimit(swapUSDSToUSDCKey, 200_000_000e6,  200_000_000e6 / uint256(1 days));
    }

    function test_ETHEREUM_sparkLend_rsethUpdates() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        _assertSupplyCapConfig(Ethereum.RSETH, 20_000, 2_000, 12 hours);

        executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.RSETH, 40_000, 5_000, 12 hours);
    }

    function test_ETHEREUM_morpho_PTUSDE27MAR2025Offboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_27MAR2025,
                oracle:          PT_USDE_27MAR2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 100_000_000e18,
            newCap:     0
        });
    }

    function test_ETHEREUM_morpho_PTSUSDE27MAR2025Offboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_27MAR2025,
                oracle:          PT_SUSDE_27MAR2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 500_000_000e18,
            newCap:     0
        });
    }

    function test_ETHEREUM_morpho_PTSUSDE29MAY2025CapIncrease() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_29MAY2025,
                oracle:          PT_SUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 200_000_000e18,
            newCap:     400_000_000e18
        });
    }

}
