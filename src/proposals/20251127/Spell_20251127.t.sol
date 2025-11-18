// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import {
    ISyrupLike
} from "src/interfaces/Interfaces.sol";

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

contract SparkEthereum_20251127_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    address internal constant ARBITRUM_NEW_ALM_CONTROLLER  = 0xC40611AC4Fff8572Dc5F02A238176edCF15Ea7ba;
    address internal constant AVALANCHE_NEW_ALM_CONTROLLER = 0x4eE67c8Db1BAa6ddE99d936C7D313B5d31e8fa38;
    address internal constant BASE_NEW_ALM_CONTROLLER      = 0x86036CE5d2f792367C0AA43164e688d13c5A60A8;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER  = 0xE52d643B27601D4d2BAB2052f30cf936ed413cec;
    address internal constant OPTIMISM_NEW_ALM_CONTROLLER  = 0x689502bc817E6374286af8f171Ed4715721406f7;
    address internal constant UNICHAIN_NEW_ALM_CONTROLLER  = 0xF16DE710899C7bdd6D46873265392CCA68e5D5bA;

    constructor() {
        _spellId   = 20251127;
        _blockDate = "2025-11-12T15:03:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Avalanche()].payload   = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Base()].payload        = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Optimism()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Unichain()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;

        chainData[ChainIdUtils.ArbitrumOne()].prevController = Arbitrum.ALM_CONTROLLER;
        chainData[ChainIdUtils.ArbitrumOne()].newController  = ARBITRUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Avalanche()].prevController = Avalanche.ALM_CONTROLLER;
        chainData[ChainIdUtils.Avalanche()].newController  = AVALANCHE_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Base()].prevController = Base.ALM_CONTROLLER;
        chainData[ChainIdUtils.Base()].newController  = BASE_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = ETHEREUM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Optimism()].prevController = Optimism.ALM_CONTROLLER;
        chainData[ChainIdUtils.Optimism()].newController  = OPTIMISM_NEW_ALM_CONTROLLER;

        chainData[ChainIdUtils.Unichain()].prevController = Unichain.ALM_CONTROLLER;
        chainData[ChainIdUtils.Unichain()].newController  = UNICHAIN_NEW_ALM_CONTROLLER;

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

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_BASE_controllerUpgrade() public onChain(ChainIdUtils.Base()) {
        _testControllerUpgrade({
            oldController: Base.ALM_CONTROLLER,
            newController: BASE_NEW_ALM_CONTROLLER
        });
    }

    function test_ARBITRUM_controllerUpgrade() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testControllerUpgrade({
            oldController: Arbitrum.ALM_CONTROLLER,
            newController: ARBITRUM_NEW_ALM_CONTROLLER
        });
    }

    function test_AVALANCHE_controllerUpgrade() public onChain(ChainIdUtils.Avalanche()) {
        _testControllerUpgrade({
            oldController: Avalanche.ALM_CONTROLLER,
            newController: AVALANCHE_NEW_ALM_CONTROLLER
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

    function test_ETHEREUM_sll_onboardB2C2() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 usdcKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDC,
            B2C2
        );

        bytes32 usdtKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            B2C2
        );

        bytes32 pyusdKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.PYUSD,
            B2C2
        );

        _assertRateLimit(usdcKey,  0, 0);
        _assertRateLimit(usdtKey,  0, 0);
        _assertRateLimit(pyusdKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdcKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(usdtKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.USDC,
            destination:    B2C2,
            transferKey:    usdcKey,
            transferAmount: 1_000_000e6
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.USDT,
            destination:    B2C2,
            transferKey:    usdtKey,
            transferAmount: 1_000_000e6
        }));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx:            _getSparkLiquidityLayerContext(),
            asset:          Ethereum.PYUSD,
            destination:    B2C2,
            transferKey:    pyusdKey,
            transferAmount: 1_000_000e6
        }));
    }

}

contract SparkEthereum_20251127_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20251127;
        _blockDate = "2025-11-12T15:03:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Avalanche()].payload   = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Base()].payload        = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Optimism()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Unichain()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
    }

}

contract SparkEthereum_20251127_SpellTests is SpellTests {

    uint256 internal constant AMOUNT_TO_ARKIS      = 4_000_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION = 1_100_000e18;

    constructor() {
        _spellId   = 20251127;
        _blockDate = "2025-11-12T15:03:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.ArbitrumOne()].payload = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Avalanche()].payload   = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // chainData[ChainIdUtils.Base()].payload        = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Optimism()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
        // chainData[ChainIdUtils.Unichain()].payload    = 0x63Fa202a7020e8eE0837196783f0fB768CBFE2f1;
    }

    function test_ETHEREUM_sparkLend_withdrawUsdsDaiReserves() external onChain(ChainIdUtils.Ethereum()) {
        uint256 spDaiBalanceBefore  = IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);
        uint256 spUsdsBalanceBefore = IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY);

        assertEq(spDaiBalanceBefore,  400_266_875.239255468540263867e18);
        assertEq(spUsdsBalanceBefore, 490_245_308.384770712325288736e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 38_917.102263032215056332e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 34_318.634327998530525485e18);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);

        assertEq(sparkUsdsBalanceBefore,      32_722_317.445801365846236778e18);
        assertEq(foundationUsdsBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkUsdsBalanceBefore - AMOUNT_TO_ARKIS - AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationUsdsBalanceBefore + AMOUNT_TO_ARKIS + AMOUNT_TO_FOUNDATION);
    }

}
