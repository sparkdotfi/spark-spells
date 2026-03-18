// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract SparkEthereum_20260326_SLLTests is SparkLiquidityLayerTests {

    address internal constant ANCHORAGE_USAT_USDT = 0x49506C3Aa028693458d6eE816b2EC28522946872;

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773856373;  // 2026-03-18T17:52:53Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_sll_anchorageUSAT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USAT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USAT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

    function test_ETHEREUM_sll_anchorageUSDT_transferAssetRateLimit() external onChain(ChainIdUtils.Ethereum()) {
        bytes32 transferKey = RateLimitHelpers.makeAddressAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
            Ethereum.USDT,
            ANCHORAGE_USAT_USDT
        );

        _assertRateLimit(transferKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(transferKey, 5_000_000e6, 250_000_000e6 / uint256(1 days));

        _testTransferAssetIntegration(TransferAssetE2ETestParams({
            ctx            : _getSparkLiquidityLayerContext(),
            asset          : Ethereum.USDT,
            destination    : ANCHORAGE_USAT_USDT,
            transferKey    : transferKey,
            transferAmount : 5_000_000e6
        }));
    }

}

contract SparkEthereum_20260326_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773856373;  // 2026-03-18T17:52:53Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function test_ETHEREUM_activateWBTC() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory wbtcConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(wbtcConfigBefore.ltv,                  0);
        assertEq(wbtcConfigBefore.liquidationThreshold, 35_00);
        assertEq(wbtcConfigBefore.liquidationBonus,     107_00);

        _assertSupplyCapConfig(Ethereum.WBTC, 5_000, 200, 12 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 1,     1,   12 hours);

        _executeAllPayloadsAndBridges();

        _assertSupplyCapConfig(Ethereum.WBTC, 3_000, 500, 12 hours);
        _assertBorrowCapConfig(Ethereum.WBTC, 1,     1,   12 hours);

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory wbtcConfigAfter = wbtcConfigBefore;

        wbtcConfigAfter.ltv                  = 77_00;
        wbtcConfigAfter.liquidationThreshold = 78_00;
        wbtcConfigAfter.liquidationBonus     = 107_00;

        _validateReserveConfig(wbtcConfigAfter, allConfigsAfter);
    }

    function test_ETHEREUM_activateWBTC_e2e() external onChain(ChainIdUtils.Ethereum()) {
        _executeAllPayloadsAndBridges();

        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigs = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory wbtcConfig = _findReserveConfigBySymbol(allConfigs, 'WBTC');
        ReserveConfig memory usdcConfig = _findReserveConfigBySymbol(allConfigs, 'USDC');

        // Check that borrowing is disabled for WBTC.
        assertEq(wbtcConfig.borrowingEnabled, false);

        _e2eTestAsset(ctx.pool, wbtcConfig, usdcConfig);
    }

}

contract SparkEthereum_20260326_SpellTests is SpellTests {

    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 100_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT       = 414_215e18;

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773856373;  // 2026-03-18T17:52:53Z
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = 0x9fFadcf3aFb43c1Af4Ec1D9B6B0405f1FBCf94D6;
    }

    function officeHours(uint256 timestamp) public pure returns (bool) {
        uint256 day  = (timestamp / 1 days + 3) % 7;
        uint256 hour = timestamp / 1 hours % 24;
        return day < 5 && hour >= 14 && hour < 21;
    }

    function test_officeHours() external {
        assertEq(officeHours(1773669599), false);  // Monday 16th March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1773669600), true);   // Monday 16th March 2026, 14:00:00 UTC is during office hours
        assertEq(officeHours(1773694799), true);   // Monday 16th March 2026, 20:59:59 UTC is during office hours
        assertEq(officeHours(1773694800), false);  // Monday 16th March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1773755999), false);  // Tuesday 17th March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1773756000), true);   // Tuesday 17th March 2026, 14:00:00 UTC is during office hours
        assertEq(officeHours(1773781199), true);   // Tuesday 17th March 2026, 20:59:59 UTC is during office hours
        assertEq(officeHours(1773781200), false);  // Tuesday 17th March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1773842399), false);  // Wednesday 18th March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1773842400), true);   // Wednesday 18th March 2026, 14:00:00 UTC is during office hours
        assertEq(officeHours(1773867599), true);   // Wednesday 18th March 2026, 20:59:59 UTC is during office hours
        assertEq(officeHours(1773867600), false);  // Wednesday 18th March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1773928799), false);  // Thursday 19th March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1773928800), true);   // Thursday 19th March 2026, 14:00:00 UTC is during office hours
        assertEq(officeHours(1773953999), true);   // Thursday 19th March 2026, 20:59:59 UTC is during office hours
        assertEq(officeHours(1773954000), false);  // Thursday 19th March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1774015199), false);  // Friday 20th March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1774015200), true);   // Friday 20th March 2026, 14:00:00 UTC is during office hours
        assertEq(officeHours(1774040399), true);   // Friday 20th March 2026, 20:59:59 UTC is during office hours
        assertEq(officeHours(1774040400), false);  // Friday 20th March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1774101599), false);  // Saturday 21st March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1774101600), false);  // Saturday 21st March 2026, 14:00:00 UTC is not during office hours
        assertEq(officeHours(1774126799), false);  // Saturday 21st March 2026, 20:59:59 UTC is not during office hours
        assertEq(officeHours(1774126800), false);  // Saturday 21st March 2026, 21:00:00 UTC is not during office hours

        assertEq(officeHours(1774187999), false);  // Sunday 22nd March 2026, 13:59:59 UTC is not during office hours
        assertEq(officeHours(1774188000), false);  // Sunday 22nd March 2026, 14:00:00 UTC is not during office hours
        assertEq(officeHours(1774213199), false);  // Sunday 22nd March 2026, 20:59:59 UTC is not during office hours
        assertEq(officeHours(1774213200), false);  // Sunday 22nd March 2026, 21:00:00 UTC is not during office hours
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 opsMultisigBalanceBefore     = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      36_722_470.91397762025440102e18);
        assertEq(foundationBalanceBefore,      0);
        assertEq(opsMultisigBalanceBefore,     0);
        assertEq(assetFoundationBalanceBefore, 55_000e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY), sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - USDS_SPK_BUYBACK_AMOUNT);

        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                opsMultisigBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
    }

}
