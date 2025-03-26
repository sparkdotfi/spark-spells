// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

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

contract SparkEthereum_20250403Test is SparkTestBase {

    address internal constant ETHEREUM_OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xF51164FE5B0DC7aFB9192E1b806ae18A8813Ae8c;

    address constant CENTRIFUGE_JTSRY_VAULT        = 0x36036fFd9B1C6966ab23209E073c68Eb9A992f50;
    address constant CENTRIFUGE_JTSRY_TOKEN        = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    uint64  constant CENTRIFUGE_JTREASURY_POOL_ID  = 4139607887;
    bytes16 constant CENTRIFUGE_JTSRY_TRANCHE_ID   = 0x97aa65f23e7be09fcd62d0554d2e9273;
    uint128 constant CENTRIFUGE_USDC_ASSET_ID      = 242333941209166991950178742833476896417;
    address constant CENTRIFUGE_ROOT               = 0x0C1fDfd6a1331a875EA013F3897fc8a76ada5DfC;
    address constant CENTRIFUGE_INVESTMENT_MANAGER = 0x427A1ce127b1775e4Cbd4F58ad468B9F832eA7e9;

    constructor() {
        id = '20250403';
    }

    function setUp() public {
        // March 25, 2025
        setupDomains({
            mainnetForkBlock:     22130932,
            baseForkBlock:        28060210,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 319402704
        });
        
        deployPayloads();
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: ETHEREUM_OLD_ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_superstateUSTBOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();
        MainnetController controller = MainnetController(ETHEREUM_NEW_ALM_CONTROLLER);

        executeAllPayloadsAndBridges();

        IERC20 usdc = IERC20(Ethereum.USDC);
        IERC20 ustb = IERC20(Ethereum.USTB);

        // USDS -> USDC limits are 50m, go a bit below in case some is in use
        uint256 mintAmount = 40_000_000e6;
        vm.startPrank(ctx.relayer);
        controller.mintUSDS(mintAmount * 1e12);
        controller.swapUSDSToUSDC(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(ustb.balanceOf(address(ctx.proxy)), 0);

        controller.subscribeSuperstate(mintAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(ctx.proxy)), 0);
        assertEq(ustb.balanceOf(address(ctx.proxy)), mintAmount);

        vm.prank(ctx.relayer);
        controller.redeemSuperstate(mintAmount);

        assertEq(usdc.balanceOf(address(ctx.proxy)), mintAmount);
        assertEq(ustb.balanceOf(address(ctx.proxy)), 0);
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

}
