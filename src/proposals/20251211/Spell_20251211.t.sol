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

contract SparkEthereum_20251211_SLLTests is SparkLiquidityLayerTests {

    IPermissionManagerLike internal constant permissionManager
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-11T12:12:00Z";
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

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: Ethereum.ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });

        assertEq(address(MainnetController(ETHEREUM_NEW_ALM_CONTROLLER).ethenaMinter()), Ethereum.ETHENA_MINTER);
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

contract SparkEthereum_20251211_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-11T12:12:00Z";
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Avalanche()].payload   = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // chainData[ChainIdUtils.Base()].payload        = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        // chainData[ChainIdUtils.Ethereum()].payload    = 0x2C9E477313EC440fe4Ab6C98529da2793e6890F2;
    }

}

contract SparkEthereum_20251211_SpellTests is SpellTests {

    uint256 internal constant AMOUNT_TO_ARKIS      = 4_000_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION = 1_100_000e18;

    constructor() {
        _spellId   = 20251211;
        _blockDate = "2025-12-11T12:12:00Z";
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

        assertEq(spDaiBalanceBefore,  355_997_143.466638232280558708e18);
        assertEq(spUsdsBalanceBefore, 549_084_070.848804689610030281e18);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(SparkLend.DAI_TREASURY), 0);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(SparkLend.TREASURY),    0);
        assertEq(IERC20(SparkLend.DAI_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),     spDaiBalanceBefore + 17_949.997576019611612844e18);
        assertEq(IERC20(SparkLend.USDS_SPTOKEN).balanceOf(Ethereum.ALM_PROXY),    spUsdsBalanceBefore + 22_771.1195233143918119e18);
    }

    function test_ETHEREUM_usdsTransfers() external onChain(ChainIdUtils.Ethereum()) {
        uint256 sparkUsdsBalanceBefore      = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationUsdsBalanceBefore = IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);

        assertEq(sparkUsdsBalanceBefore,      32_097_248.445801365846236778e18);
        assertEq(foundationUsdsBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_PROXY),               sparkUsdsBalanceBefore - AMOUNT_TO_ARKIS - AMOUNT_TO_FOUNDATION);
        assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG), foundationUsdsBalanceBefore + AMOUNT_TO_ARKIS + AMOUNT_TO_FOUNDATION);
    }

}
