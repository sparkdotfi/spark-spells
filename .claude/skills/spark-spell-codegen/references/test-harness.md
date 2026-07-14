# Test-harness guide — writing `Spell_<YYYYMMDD>.t.sol`

The test file is the most error-prone part. Reproduce the structure of a recent `archive/<date>/Spell_<date>.t.sol` exactly; this doc explains the moving parts so the adaptation is correct.

## File structure

`Spell_<id>.t.sol` defines **three** test contracts, one per base harness in `src/test-harness/`:

```solidity
contract Spark<Chain>_<id>_SLLTests       is SparkLiquidityLayerTests { ... }
contract Spark<Chain>_<id>_SparklendTests is SparklendTests          { ... }
contract Spark<Chain>_<id>_SpellTests     is SpellTests              { ... }
```

Each shares the same constructor and `setUp()`:

```solidity
constructor() {
    _spellId   = <YYYYMMDD>;      // integer form of the date
    _blockDate = <timestamp>;     // the operator-supplied fork timestamp — do NOT guess
}

function setUp() public override {
    super.setUp();
    chainData[ChainIdUtils.Ethereum()].payload = <addr>;
    chainData[ChainIdUtils.Base()].payload     = <addr>;
    // ...one line per affected chain...
}
```

- **Payload auto-deploy:** the harness deploys each payload from source **by name** — `deployCode("Spark<Chain>_<id>.sol:Spark<Chain>_<id>")`, derived from `_spellId`. So each payload's **file name and contract name must be exactly `Spark<Chain>_<YYYYMMDD>`**, or it won't be found.
- `_blockDate` drives the fork block on every chain (the harness resolves the block for that timestamp). Assertions read real state at that block, so the value must be the one the operator gave you.

## Inherited generic tests — you do NOT write these

Extending the three bases automatically pulls in a large suite of generic regression tests (e.g. `test_*_PayloadBytecodeMatches`, `test_*_E2E_sparkLiquidityLayer`, `test_ETHEREUM_AllReservesSeeded`, `test_*_Oracles`, `test_officeHours`). You only add **item-specific** `test_<CHAIN>_<name>()` functions. Chains with no payload are auto-skipped.

## Writing an item test

Gate each test to its chain and use the pre → execute → post pattern:

```solidity
function test_<CHAIN>_<description>() public onChain(ChainIdUtils.<Chain>()) {
    // 1. read/assert PRE-execution state
    _assertRateLimit(key, 0, 0);
    // ...

    _executeAllPayloadsAndBridges();   // runs the mainnet payload + relays foreign payloads

    // 2. assert POST-execution state
    _assertRateLimit(key, 5_000_000e18, uint256(100_000_000e18) / 1 days);
    // ...
}
```

Useful helpers (grep the base contracts for exact signatures):
- `_assertRateLimit(bytes32 key, uint256 maxAmount, uint256 slope)`
- rate-limit keys: `RateLimitHelpers.makeAddressKey(MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_X(), addr)`
- `_getSparkLiquidityLayerContext()` — SLL context (proxy, controller, relayer…)
- `_executeAllPayloadsAndBridges()` — the standard "run the spell" call

## Two patterns you'll likely need

**SLL OTC integration (send/claim round trip):** the SLL harness provides an end-to-end helper — grep `src/test-harness/SparkLiquidityLayerTests.sol` for `_testOTCIntegration` and its params struct (`OTCE2ETestParams`), and any `BINANCE_EXCHANGE`-style constants already defined there. Assert the configured values (rate limit, `maxSlippages`, `otcs(...)` buffer + rechargeRate, `otcWhitelistedAssets`, buffer allowances) before and after execution, then call the e2e helper to validate an actual swap round trip.

**L2 → L1 withdrawal over the standard bridge:** assert the L2 ALM proxy balance drops, then simulate finalization and assert arrival on Ethereum:

```solidity
uint256 l2Before  = IERC20(<L2>.USDS).balanceOf(<L2>.ALM_PROXY);
chainData[ChainIdUtils.Ethereum()].domain.selectFork();
uint256 l1Before  = IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY);
chainData[ChainIdUtils.<L2>()].domain.selectFork();

RecordedLogs.init();
_executeAllPayloadsAndBridges();
assertEq(IERC20(<L2>.USDS).balanceOf(<L2>.ALM_PROXY), l2Before - <amount>);

OptimismBridgeTesting.relayMessagesToSource(chainData[ChainIdUtils.<L2>()].bridges[0], false);
chainData[ChainIdUtils.Ethereum()].domain.selectFork();
assertEq(IERC20(Ethereum.USDS).balanceOf(Ethereum.ALM_PROXY), l1Before + <amount>);
```

Note: when testing one OP-stack chain's bridge, set the *other* OP chains' `chainData[...].payload = address(0)` inside the test so their `SentMessage` logs don't interfere with the relay (all OP chains share the same L2 messenger). Copy this exactly from a precedent that does an L2 withdrawal, if one exists.

## Imports

Mirror a recent `Spell_<date>.t.sol` import block: `forge-std`, `openzeppelin` ERC20, the per-chain registry libs, `spark-alm-controller` (controller, `RateLimitHelpers`, any lib), `sparklend-*`, `src/libraries/ChainIdUtils.sol`, the three `src/test-harness/*` bases, `xchain-helpers/testing/*` (Domain, RecordedLogs, OptimismBridgeTesting) for bridge tests, and `../../interfaces/Interfaces.sol` for local interfaces.
