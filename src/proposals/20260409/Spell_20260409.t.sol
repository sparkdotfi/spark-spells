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

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

contract SparkEthereum_20260409_SLLTests is SparkLiquidityLayerTests {


    constructor() {
        _spellId   = 20260409;
        _blockDate = 1773932817;  // 2026-03-19T15:06:57Z // @TODO
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = ;
    }

    function test_ETHEREUM_sll_syrupUSDTRateLimitIncrease() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        bytes32 depositKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
            Ethereum.SYRUP_USDT
        );
        bytes32 redeemKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_MAPLE_REDEEM(),
            Ethereum.SYRUP_USDT
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
            Ethereum.SYRUP_USDT
        );

        _assertRateLimit(depositKey, 50_000_000e6, 10_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(redeemKey);
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey, 25_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertRateLimit(redeemKey,  50_000_000e6, 500_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(withdrawKey);

        _testMapleIntegration(MapleE2ETestParams({
            ctx           : ctx,
            vault         : Ethereum.SYRUP_USDT,
            depositAmount : 1_000_000e6,
            depositKey    : depositKey,
            redeemKey     : redeemKey,
            withdrawKey   : withdrawKey,
            tolerance     : 10
        }));
    }


}

contract SparkEthereum_20260409_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773932817;  // 2026-03-19T15:06:57Z // @TODO
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = ;
    }

    function test_ETHEREUM_sparkSavingsV2_increaseVaultDepositCaps() public onChain(ChainIdUtils.Ethereum()) {
        ISparkVaultV2Like usdcVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        ISparkVaultV2Like usdtVault = ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT);

        assertEq(usdcVault.depositCap(), 500_000_000e6);
        assertEq(usdtVault.depositCap(), 500_000_000e6);

        _executeAllPayloadsAndBridges();

        assertEq(usdcVault.depositCap(), 1_000_000_000e6);
        assertEq(usdtVault.depositCap(), 1_000_000_000e6);

        _testSparkVaultDepositCapBoundary({
            vault:              usdcVault,
            depositCap:         1_000_000_000e6,
            expectedMaxDeposit: 782_841_456.461691e6
        });

        _testSparkVaultDepositCapBoundary({
            vault:              usdtVault,
            depositCap:         1_000_000_000e6,
            expectedMaxDeposit: 782_841_456.461691e6
        });
    }

}

contract SparkEthereum_20260409_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260326;
        _blockDate = 1773932817;  // 2026-03-19T15:06:57Z // @TODO
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload = ;
    }

    function test_officeHours() external onChain(ChainIdUtils.Ethereum()) {
        SparkPayloadEthereum payload = SparkPayloadEthereum(chainData[ChainIdUtils.Ethereum()].payload);

        assertEq(payload.officeHours(1773669599), false);  // Monday 16th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773669600), true);   // Monday 16th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773694799), true);   // Monday 16th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773694800), false);  // Monday 16th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773755999), false);  // Tuesday 17th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773756000), true);   // Tuesday 17th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773781199), true);   // Tuesday 17th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773781200), false);  // Tuesday 17th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773842399), false);  // Wednesday 18th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773842400), true);   // Wednesday 18th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773867599), true);   // Wednesday 18th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773867600), false);  // Wednesday 18th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773928799), false);  // Thursday 19th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773928800), true);   // Thursday 19th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773953999), true);   // Thursday 19th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773954000), false);  // Thursday 19th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774015199), false);  // Friday 20th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774015200), true);   // Friday 20th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1774040399), true);   // Friday 20th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1774040400), false);  // Friday 20th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774101599), false);  // Saturday 21st March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774101600), false);  // Saturday 21st March 2026, 14:00:00 UTC is not during office hours
        assertEq(payload.officeHours(1774126799), false);  // Saturday 21st March 2026, 20:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774126800), false);  // Saturday 21st March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774187999), false);  // Sunday 22nd March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774188000), false);  // Sunday 22nd March 2026, 14:00:00 UTC is not during office hours
        assertEq(payload.officeHours(1774213199), false);  // Sunday 22nd March 2026, 20:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774213200), false);  // Sunday 22nd March 2026, 21:00:00 UTC is not during office hours
    }

}
