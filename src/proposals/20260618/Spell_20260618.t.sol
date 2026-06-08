// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPool }               from "sparklend-v1-core/interfaces/IPool.sol";
import { IScaledBalanceToken } from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { RecordedLogs } from "xchain-helpers/testing/utils/RecordedLogs.sol";

import {
    IALMProxyFreezableLike,
    IMorphoVaultLike,
    IPositionManagerLike,
    ISparkVaultV2Like 
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260618_SLLTests is SparkLiquidityLayerTests {

    address internal constant BINANCE_OTC_BUFFER = 0x1851c64BBfad132CBE75481f1690C381288ea492;

    constructor() {
        _spellId   = 20260618;
        _blockDate = 1780912753;  // 2026-06-8T09:59:13Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x1566BFA55D95686a823751298533D42651183988;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Optimism()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Unichain()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
    }

    function test_ETHEREUM_sll_onboardBinanceOTCBuffer() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 key = RateLimitHelpers.makeAddressKey(
            mainnetController.LIMIT_OTC_SWAP(),
            BINANCE_EXCHANGE
        );

        _assertRateLimit(key, 0, 0);

        assertEq(mainnetController.maxSlippages(BINANCE_EXCHANGE),                        0);
        assertEq(IERC20(Ethereum.USDT).allowance(BINANCE_OTC_BUFFER, Ethereum.ALM_PROXY), 0);
        assertEq(IERC20(Ethereum.USDC).allowance(BINANCE_OTC_BUFFER, Ethereum.ALM_PROXY), 0);

        assertEq(mainnetController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDT), false);
        assertEq(mainnetController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDC), false);

        {
            (address buffer, uint256 rechargeRate18,,,) = mainnetController.otcs(BINANCE_EXCHANGE);
            assertEq(buffer,         address(0));
            assertEq(rechargeRate18, 0);
        }

        _executeAllPayloadsAndBridges();

        _assertRateLimit(key, 5_000_000e18, uint256(100_000_000e18) / 1 days);

        assertEq(mainnetController.maxSlippages(BINANCE_EXCHANGE),                        0.998e18);
        assertEq(IERC20(Ethereum.USDT).allowance(BINANCE_OTC_BUFFER, Ethereum.ALM_PROXY), type(uint256).max);
        assertEq(IERC20(Ethereum.USDC).allowance(BINANCE_OTC_BUFFER, Ethereum.ALM_PROXY), type(uint256).max);

        assertTrue(mainnetController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDT));
        assertTrue(mainnetController.otcWhitelistedAssets(BINANCE_EXCHANGE, Ethereum.USDC));

        {
            (address buffer, uint256 rechargeRate18,,,) = mainnetController.otcs(BINANCE_EXCHANGE);
            assertEq(buffer,         BINANCE_OTC_BUFFER);
            assertEq(rechargeRate18, uint256(50_000e18) / 1 days);
        }

        _testOTCIntegration(OTCE2ETestParams({
            ctx:           _getSparkLiquidityLayerContext(),
            exchange:      BINANCE_EXCHANGE,
            transferKey:   key,
            asset0:        Ethereum.USDT,
            asset1:        Ethereum.USDC,
            amount:        5_000_000e6
        }));
    }

}

contract SparkEthereum_20260618_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260618;
        _blockDate = 1780912753;  // 2026-06-8T09:59:13Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x1566BFA55D95686a823751298533D42651183988;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Optimism()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Unichain()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
    }

}

contract SparkEthereum_20260618_SpellTests is SpellTests {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;

    constructor() {
        _spellId   = 20260618;
        _blockDate = 1780912753;  // 2026-06-8T09:59:13Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Base()].payload     = 0x1566BFA55D95686a823751298533D42651183988;
        // chainData[ChainIdUtils.Ethereum()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Optimism()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
        // chainData[ChainIdUtils.Unichain()].payload = 0xAb385eC0Df225D5A37F5245D2aE43D53Fe4Fed20;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      37_022_794.249708907368137212e18);
        assertEq(foundationBalanceBefore,      326_990.0222e18);
        assertEq(assetFoundationBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
