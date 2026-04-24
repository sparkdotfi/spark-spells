// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { UserConfiguration }    from "sparklend-v1-core/protocol/libraries/configuration/UserConfiguration.sol";

import { AaveOracle }        from "sparklend-v1-core/misc/AaveOracle.sol";
import { DataTypes }         from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IPool }             from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator } from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

interface IEndpointV2 {
    function getConfig(address receiver, address uln, uint32 eid, uint32 configType) external view returns (bytes memory);
}

contract SparkEthereum_20260507_SLLTests is SparkLiquidityLayerTests {

    // the formal properties are documented in the setter functions
    struct UlnConfig {
        uint64    confirmations;
        // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
        uint8     requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNThreshold; // (0, optionalDVNCount]
        address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
        address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
    }

    address internal constant LAYERZERO_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload  = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
        // chainData[ChainIdUtils.Avalanche()].payload = ;
    }

    /**********************************************************************************************/
    /*** Ethereum - Offboard Aave Core USDT                                                     ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateAaveCoreUsdt() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDT);

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    /**********************************************************************************************/
    /*** Avalanche - Offboard Aave USDC                                                         ***/
    /**********************************************************************************************/

    function test_AVALANCHE_sll_deactivateAaveCoreUsdc() external onChain(ChainIdUtils.Avalanche()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        ForeignController controller = ForeignController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Avalanche.ATOKEN_CORE_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Avalanche.ATOKEN_CORE_USDC);

        _assertRateLimit(depositKey,  20_000_000e6,     10_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }
    
    /**********************************************************************************************/
    /*** Avalanche - Update Bridge DVN Configuration                                            ***/
    /**********************************************************************************************/

    function test_AVALANCHE_sll_updateBridgeDvnConfiguration() external onChain(ChainIdUtils.Avalanche()) {
        IEndpointV2 endpoint = IEndpointV2(LAYERZERO_ENDPOINT_V2);

        address receiveUln302 = 0xbf3521d309642FA9B1c91A08609505BA09752c61;

        bytes memory configBytes = endpoint.getConfig(
            Avalanche.SPARK_RECEIVER,
            receiveUln302,
            30101,  // eid 30101 is for Ethereum Mainnet
            2       // configType 2 is for UlnConfig
        );
        UlnConfig memory config = abi.decode(configBytes, (UlnConfig));

        // Verify the old config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     2,                                          "requiredDVNCount should be 2");
        assertEq(config.optionalDVNCount,     0,                                          "optionalDVNCount should be 0");
        assertEq(config.optionalDVNThreshold, 0,                                          "optionalDVNThreshold should be 0");
        assertEq(config.requiredDVNs.length,  2,                                          "requiredDVNs length should be 2");
        assertEq(config.requiredDVNs[0],      0x962F502A63F5FBeB44DC9ab932122648E8352959, "first DVN should be LayerZero Labs");
        assertEq(config.requiredDVNs[1],      0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc, "second DVN should be Google");
        assertEq(config.optionalDVNs.length,  0,                                          "optionalDVNs length should be 0");

        _executeAllPayloadsAndBridges();

        configBytes = endpoint.getConfig(
            Avalanche.SPARK_RECEIVER,
            receiveUln302,
            30101,  // eid 30101 is for Ethereum Mainnet
            2       // configType 2 is for UlnConfig
        );
        config = abi.decode(configBytes, (UlnConfig));

        // Verify the new config
        assertEq(config.confirmations,        15,                                         "confirmations should be 15");
        assertEq(config.requiredDVNCount,     0,                                          "requiredDVNCount should be 255");
        assertEq(config.optionalDVNCount,     7,                                          "optionalDVNCount should be 7");
        assertEq(config.optionalDVNThreshold, 4,                                          "optionalDVNThreshold should be 4");
        assertEq(config.requiredDVNs.length,  0,                                          "requiredDVNs length should be 0");
        assertEq(config.optionalDVNs.length,  7,                                          "optionalDVNs length should be 7");
        assertEq(config.optionalDVNs[0],      0x07C05EaB7716AcB6f83ebF6268F8EECDA8892Ba1, "first DVN should be Horizen");
        assertEq(config.optionalDVNs[1],      0x962F502A63F5FBeB44DC9ab932122648E8352959, "second DVN should be LayerZero Labs");
        assertEq(config.optionalDVNs[2],      0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5, "third DVN should be Nethermind");
        assertEq(config.optionalDVNs[3],      0xbe57e9E7d9eB16B92C6383792aBe28D64a18c0F1, "fourth DVN should be Deutsche Telekom");
        assertEq(config.optionalDVNs[4],      0xcC49E6fca014c77E1Eb604351cc1E08C84511760, "fifth DVN should be Canary");
        assertEq(config.optionalDVNs[5],      0xE4193136B92bA91402313e95347c8e9FAD8d27d0, "sixth DVN should be Luganodes");
        assertEq(config.optionalDVNs[6],      0xE94aE34DfCC87A61836938641444080B98402c75, "seventh DVN should be P2P");
    }

}

contract SparkEthereum_20260507_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
    }

    /**********************************************************************************************/
    /*** Ethereum - Update LBTC and WBTC CapAutomator Supply Caps                               ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkLend_lbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.LBTC, 10_000, 500, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.LBTC, 5_000, 200, 12 hours);
    }

    function test_ETHEREUM_sparkLend_wbtcCapAutomatorUpdates() external onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.WBTC, 3_000, 500, 12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WBTC, 30_000, 500, 12 hours);
    }

}

contract SparkEthereum_20260507_SpellTests is SpellTests {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 326_945e18;

    constructor() {
        _spellId   = 20260507;
        _blockDate = 1776434632;  // 2026-04-17T14:03:52Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x160158d029697FEa486dF8968f3Be17a706dF0F0;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore          = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      36_373_387.913977620254401020e18);
        assertEq(foundationBalanceBefore,      0.0095e18);
        assertEq(assetFoundationBalanceBefore, 142_000e18);
        assertEq(almOpsBalanceBefore,          0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
    }

}
