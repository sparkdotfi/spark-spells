# spark-spells Repository Conventions

> Synced from `spark-spell-review/reference/conventions.md` @ 2026-07-07 — edit the source skill's
> copy, not this one, and re-sync. The codegen addendum at the end of this file is owned here.

Reference for writing (and self-reviewing) spell code. Everything here is verifiable in the repo —
if a convention below conflicts with the current proposal or 3–4 most recent archives, the live
repository pattern wins; flag the discrepancy so this file gets updated.

## Directory layout

- `src/proposals/<YYYYMMDD>/` — the active spell under review. The date is the target execution date.
- `archive/<YYYYMMDD>/` — completed spells. Use the current proposal plus the 3–4 most recent
  archives as ground truth (the repo evolves; old archive entries may use superseded patterns).
- One payload file per chain: `Spark<Chain>_<YYYYMMDD>.sol` (e.g. `SparkEthereum_20260702.sol`,
  `SparkBase_20260702.sol`).
- One test file per spell: `Spell_<YYYYMMDD>.t.sol`, in the same directory.

## Payload structure

| Chain | Base contract |
|---|---|
| Ethereum | `SparkPayloadEthereum` (extends `AaveV3PayloadBase(SparkLend.CONFIG_ENGINE)`) |
| Base / Arbitrum / Optimism / Unichain / Avalanche | `SparkPayload<Chain>` |
| Gnosis | `SparkPayloadGnosis` (extends `AaveV3PayloadBase(Gnosis.CONFIG_ENGINE)`) |

Key mechanics:

- The **only external non-view entry point is `execute()`** (from `AaveV3PayloadBase`). Spell logic
  goes in `_postExecute()` (occasionally `_preExecute()`). SparkLend config changes go in the
  structured override functions (`capsUpdates()`, `collateralsUpdates()`, `borrowsUpdates()`,
  `rateStrategiesUpdates()`, `priceFeedsUpdates()`, `newListings()` / `newListingsCustom()`),
  which the base `execute()` routes through the `LISTING_ENGINE` via **delegatecall**.
- The mainnet payload is executed via **delegatecall from `SPARK_PROXY`** (StarGuard plot/exec →
  proxy → payload). Consequence: **payloads must not declare or write storage variables** — only
  `constant` and `immutable` (set in constructor). A storage write in a payload writes into
  SPARK_PROXY's storage layout. The test harness has `test_ETHEREUM_SparkProxyStorage` to catch
  this, but review it statically too.
- Cross-chain propagation: the mainnet `execute()` queues each configured L2 payload through the
  chain's forwarder — `OptimismForwarder.sendMessageL1toL2` (Base, Optimism, Unichain, with
  distinct `L1_CROSS_DOMAIN_*` messengers), `ArbitrumForwarder.sendMessageL1toL2`,
  `AMBForwarder.sendMessageEthereumToGnosisChain`, `LZForwarder.sendMessage` (Avalanche,
  `ENDPOINT_ID_AVALANCHE`). L2 payload addresses are set in the mainnet payload's **constructor**
  as `PAYLOAD_ARBITRUM`, `PAYLOAD_BASE`, `PAYLOAD_GNOSIS`, `PAYLOAD_OPTIMISM`, `PAYLOAD_UNICHAIN`,
  `PAYLOAD_AVALANCHE` (immutables; `address(0)` means "no payload for that chain this spell").
- StarGuard: mainnet spells expose `isExecutable() external view returns (bool)`. It must either
  return `true` unconditionally or implement logic that the forum post explicitly describes
  (office hours, earliest execution date). `test_officeHours` in the harness covers the standard
  14:00–21:00 UTC Mon–Fri window.

## Natspec header (every payload)

```solidity
/**
 * @title  July 2, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend:
 *         - Set USDC Interest Rate Model to Target Very Low Liquidity.
 *         Spark Liquidity Layer:
 *         - Enable USDT Bridging to Arbitrum.
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x...
 */
```

- `@title` is `<Month> <Day>, <Year> Spark <Chain> Proposal` and must match the directory date.
- `Forum:` is the specification source of truth. All chain payloads of one spell must reference the
  same forum post(s). Multiple `Forum:`/`Vote:` lines are allowed when a spell implements several
  posts/votes.
- `Vote:` (Snapshot, `s:sparkfi.eth`) may be absent early in the spell lifecycle and added once the
  vote is live. Its absence pre-vote is expected; its absence at deployment/handover stage is a
  finding.
- Numbered comments inside `_postExecute()` (`// 1.`, `// 2.` …) refer to the instruction numbering
  of the forum post — gaps are normal when other items are handled by struct overrides or other
  chains' payloads. Verify the numbers against the post; do not assume they must be sequential.
- Deviations from an instruction are annotated `// Note:` explaining why; actions with no matching
  instruction also require a `// Note:` justification.

## Address usage

- Addresses that exist in `lib/spark-address-registry` (`Ethereum.sol`, `Base.sol`, `Arbitrum.sol`,
  `Optimism.sol`, `Unichain.sol`, `Avalanche.sol`, `Gnosis.sol`, `SparkLend.sol`) **must** be used
  from the registry, never re-hardcoded.
- New contracts not yet in the registry are declared `internal constant` with a name that describes
  them, and their addresses must appear in the forum post (directly or via linked deployment
  artifacts).
- A registry submodule bump in a spell PR is itself in scope: diff the submodule commits and verify
  each added/changed address independently.

## SLL / ALM patterns

- Mainnet controller: `MainnetController(Ethereum.ALM_CONTROLLER)`; L2s use
  `ForeignController(<Chain>.ALM_CONTROLLER)`. Rate limits: `IRateLimits(<Chain>.ALM_RATE_LIMITS)`.
- Rate limit keys are built with `RateLimitHelpers.makeAddressKey / makeAddressAddressKey /
  makeUint32Key / makeBytes32Key`, or raw `keccak256(abi.encode(controller.LIMIT_X(), ...))` for
  key shapes the helpers don't cover (e.g. `LIMIT_LAYERZERO_TRANSFER` keyed on `(oft, dstEid)`).
  **The key construction must exactly match how the controller derives the key at call time** —
  read the controller source in `lib/spark-alm-controller` for the limit id being set; a key that
  hashes the wrong components silently creates a rate limit nothing ever consumes while the real
  action reverts with zero limit.
- Slope convention: `uint256(<amount-per-day>) / 1 days` — the cast to `uint256` before division
  is deliberate (avoids intermediate truncation surprises with typed literals). Amounts use the
  **token's decimals**: `e6` for USDC/USDT, `e18` for USDS/DAI/sUSDS, `e8` for WBTC.
- Unlimited rate limits use `setUnlimitedRateLimitData(key)` / assert `type(uint256).max`.
  Sanity band used by the harness `_assertRateLimit`: slope recharges max in 7.5 minutes–30 days.
- Helper wrappers exist and should be preferred when applicable: `_configureAaveToken`,
  `_configureERC4626Vault`, `_configureCurvePool`, `_setUpNewMorphoVault(V2)`,
  `_activateMorphoVault`, `_upgradeController`, `_transferAssetFromAlmProxy`, `_sendOpTokens`,
  `_sendArbTokens`, and `SLLHelpers.*` (`onboardERC4626Vault`, `configureAaveToken`, …).
- LayerZero: `setLayerZeroRecipient(dstEid, bytes32(uint256(uint160(<remote ALM proxy>))))`. EIDs
  are LayerZero **endpoint IDs** (e.g. 30101 Ethereum, 30110 Arbitrum) — not chain ids, not CCTP
  domains. CCTP uses `makeUint32Key(LIMIT_USDC_TO_DOMAIN, <cctp domain>)` with CCTP domain ids
  (0 Ethereum, 3 Arbitrum, 6 Base…). Confusing the two id spaces is a recurring hazard.

## SparkLend patterns

- Parameter units: LTV / liquidation threshold / liquidation bonus / reserve factor are **bps**
  (`70_00` = 70%). IRM parameters on rate strategies are **ray** (`0.01e27`). Slippage bounds on
  the controller are **wad** (`0.998e18`). Caps via `capsUpdates()` are whole-token units (no
  decimals). `EngineFlags.KEEP_CURRENT` for anything not being changed.
- Direct `POOL_CONFIGURATOR` calls in `_postExecute()` are used for what the config engine doesn't
  cover: `setReserveInterestRateStrategyAddress`, `setAssetEModeCategory`, `setReserveFactor`,
  freeze/pause.
- Cap automator: `ICapAutomator(SparkLend.CAP_AUTOMATOR).setSupplyCapConfig/setBorrowCapConfig`
  `({asset, max, gap, increaseCooldown})` — `increaseCooldown` conventionally `4 hours` — note
  `max` is in whole tokens like engine caps.
- New IRMs are deployed contracts referenced by constant; their **constructor parameters are not
  visible in the spell diff** and must be verified on-chain against the forum post
  (RateTargetKink/RateTargetBase parameters in ray).

## Morpho patterns

- `IMetaMorpho(vault).submitCap(marketParams, newCap)`: **cap increases enter a 1-day timelock**
  and need a later `acceptCap` (by anyone, after timelock); decreases apply immediately. A spell
  that submits an increase and asserts the new cap immediately is wrong; the harness helper
  `_testMorphoCapUpdate` encodes the correct semantics.
- Pendle PT markets: oracle config has its own helper `_testMorphoPendlePTOracleConfig`; PT
  maturity dates in market params must match the forum post.

## Test harness (`src/test-harness/`)

- `SpellRunner` — multi-chain fork orchestration. `_spellId` (YYYYMMDD) locates payload contracts
  by naming convention via `vm.getCode`; `_blockDate` (unix timestamp, commented with full UTC
  date) drives fork block selection for all chains via Etherscan API (FFI). `chainData[chainId]`
  holds payload address, executor, domain, bridges. `_executeAllPayloadsAndBridges()` executes the
  mainnet payload through StarGuard plot/exec, relays bridge messages (OP/Arbitrum/AMB/CCTP/LZ),
  and executes foreign payloads.
- `SpellTests` — universal tests every spell inherits: `test_ETHEREUM_PayloadsConfigured`
  (constructor `PAYLOAD_*` ↔ test `chainData` consistency), `test_*_PayloadBytecodeMatches`
  (deployed bytecode ↔ locally compiled source), `test_ETHEREUM_SparkProxyStorage` (no proxy
  storage corruption), `test_officeHours`, `test_ETHEREUM_sparkLend_withdrawAllReserves`.
- `SparklendTests` — `_testIRMChanges`, `_testRateTargetKinkIRMUpdate`, `_testRateTargetBaseIRMUpdate`,
  `_testAssetOnboarding`, `_testAutomatedCapsUpdate`, `_assertSupplyCapConfig`,
  `_assertBorrowCapConfig`, `_assertFrozen`, `_assertPaused`, `_assertReserveChange`.
- `SparkLiquidityLayerTests` — `_assertRateLimit` / `_assertUnlimitedRateLimit`, and e2e
  integrations: `_testERC4626Onboarding/Integration`, `_testAaveIntegration`,
  `_testMorphoVaultCreation`, `_testCurveLP/SwapIntegration`, `_testUniswapV4LP/SwapIntegration`,
  `_testPSMIntegration`, `_testOTCIntegration`, `_testMapleIntegration`,
  `_testLayerZeroTransferIntegration`, `_testControllerUpgrade`, `_testE2ESLLCrossChainForDomain`.
- `MorphoTests` — `_testMorphoCapUpdate`, `_testMorphoPendlePTOracleConfig`.

## Test file conventions

- Test contracts are split by concern:
  `Spark<Chain>_<YYYYMMDD>_SLLTests is SparkLiquidityLayerTests`,
  `..._SparklendTests is SparklendTests`, `..._SpellTests is SpellTests`, etc. Each sets
  `_spellId` + `_blockDate` in the constructor and the deployed payload addresses in `setUp()`
  via `chainData[ChainIdUtils.<Chain>()].payload = 0x...`.
- Test naming: `test_<CHAIN>_<area>_<action>()` with the `onChain(ChainIdUtils.<Chain>())`
  modifier, e.g. `test_ETHEREUM_sll_lzRateLimits`.
- The canonical assertion shape is **before/after**: assert the exact pre-execution value (old
  param, zeroed rate limit, exact token balance at the fork block), call
  `_executeAllPayloadsAndBridges()`, assert the exact post-execution value. A test that only
  asserts the post-state proves much less — flag it.
- Onboardings/integrations require the matching e2e helper, not just config asserts.

## Spell lifecycle (what the PR stage implies for review)

1. **Pre-deployment**: payload code + tests; constructor `PAYLOAD_*` slots and test `chainData`
   deployment addresses may be unset; forum post exists; Snapshot vote may not. This does not
   permit unresolved integration addresses in a review-ready payload.
2. **Post-deployment ("finalize")**: constructor gets the deployed L2 payload addresses, test
   `chainData` gets the deployed addresses for all chains, `Vote:` links added. Bytecode-match
   tests become meaningful: deployed code must equal compiled source at this commit. Deployment
   must be plain `CREATE`, verified on the chain's primary explorer, optimizer/EVM/license
   settings matching `foundry.toml` (solc 0.8.25, optimizer on, cancun).
3. **Archive**: after execution the directory moves to `archive/` unchanged.

Identify the stage from the diff (are `PAYLOAD_*`/`chainData` addresses being filled in?) and apply
the right checks; do not flag pre-deployment PRs for missing deployed addresses.

## CI

`.github/workflows/test.yml` runs `forge test -vvv` with RPC URLs + Etherscan/Alchemy keys, and the
spell-caster job posts a Tenderly fork simulation link as a PR comment. If a spell-caster comment
exists on the PR, read it — a revert or unexpected action in the simulation is a finding.

---

## Codegen addendum (owned by spark-spell-codegen; from human corrections to generated spells)

Style details confirmed by the human-corrected 2026-06-18 spell — reproduce them when generating:

- **Numbered comments** in `_postExecute()` follow the **forum post's item numbering, gaps normal**
  (e.g. `// 1.` … `// 7.` with 2–6 living on other chains / in struct overrides / deferred). Do not
  renumber around deferred items.
- **Slope literal style**: `uint256(100_000_000e18) / 1 days` — the cast wraps the *amount*, not
  the divisor.
- **Prefer importing the real contract type** over a hand-rolled `*Like` interface when the
  contract is in `lib/` (e.g. `import { OTCBuffer } from "spark-alm-controller/src/OTCBuffer.sol"`)
  . A small local interface (e.g. `ITokenBridgeLike`) is right when no clean import exists —
  declared above the natspec header, fields aligned.
- **Foreign (L2) payloads**: grant/revoke the ALM Proxy `CONTROLLER` role to **`address(this)`**
  (the payload runs as the executor via delegatecall); import the base via the relative path
  `"../../SparkPayload<Chain>.sol"`; declare per-token amount constants
  (`USDS_WITHDRAW_AMOUNT`, `SUSDS_WITHDRAW_AMOUNT`), not one shared constant; inline the
  `doCall` sequences per asset rather than a local helper function; explicit casts inside
  `abi.encodeCall` tuples (`uint32(500_000)`, `bytes("")`).
- **Constant naming** follows the counterparty's public label (`BINANCE_EXCHANGE`), not its role
  in the mechanism (`BINANCE_DEPOSIT`).
- **`// Note:`** annotation is required on any code action not traceable to a post instruction,
  and on any deliberate deviation from an instruction.
- **Tests**: item tests may pin exact fork-state balances (`assertEq(balBefore, 36_359_440.24...e18)`)
  — obtain them via the discover-then-pin loop (SKILL.md Phase 6), never by guessing. Directional
  e2e coverage: an integration that swaps both ways gets one test per direction. Don't duplicate a
  check the inherited generic suite already performs (e.g. claim-reserves is covered by
  `test_ETHEREUM_sparkLend_withdrawAllReserves`).
