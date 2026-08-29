# Known Spell Review Findings & Footguns

> Synced from `spark-spell-review/reference/footguns.md` @ 2026-07-07 — edit the source skill's
> copy, not this one, and re-sync.

Distilled from ~1,300 human review comments across 18 merged spark-spells PRs, the internal Prime
Agent reviewer checklist, and post-mortems. These are the things human reviewers actually catch.
Every item here has burned a real PR at least once — check each one deliberately, do not skim.

**How codegen uses this file.** It is written for reviewers; you apply it as *generation rules* —
write code that would survive each check, don't wait to be caught. Each codegen agent applies the
sections its orchestrator prompt names while writing (§1–3 and §12 for payloads; §10–11 for tests),
and Phase 8 re-checks the full file against the finished diff. Inverted examples: §10 "assertGe is
a finding" → write exact-value before/after assertions (discover-then-pin, see SKILL.md Phase 6);
§12 "copy-paste drift" → after adapting a precedent, hunt your own unedited remnants.

## 1. Spec ↔ code divergence (highest severity class)

- **Wrong constant vs forum post** — a rate limit of 5M where the post says 50M, `0.99e18` vs
  `0.999999e18` slippage, one digit off in an address. Compare every literal character-by-character
  against the post.
- **Action in the post but missing from the spell** — e.g. a transfer to a foundation described in
  the proposal with no corresponding code, or a reserve claim mentioned but not implemented.
- **Action in the spell but not in the post** — every state-changing call must trace to an
  instruction. An unexplained extra action is a critical finding unless annotated `// Note:` with a
  justification that itself makes sense.
- **Deliberate deferrals** — sometimes an item in the post is intentionally out of scope for this
  spell (split across dates). Don't assume; flag it and let the author confirm, but check the post
  and PR description for stated scope first.
- **Execution order ≠ forum post order** — reviewers ask for payload actions (and their comments)
  to follow the post's ordering, and for the order to be consistent across chains' payloads.

## 2. Decimals & units

- Amounts must use the **token's decimals**: USDC/USDT `e6`, USDS/DAI/sUSDS `e18`, WBTC `e8`.
  A USDC cap written `e18` is a 10^12 error that still compiles and can even pass weak tests.
- LTV/LT/liq bonus/reserve factor: **bps** (`70_00`). IRM params: **ray** (`e27`).
  Slippage/exchange rates on the controller: **wad** (`e18`). Engine + cap automator caps:
  **whole tokens, no decimals**.
- Derived values should be expressed as their derivation, not a pre-computed magic number
  (e.g. `SPK_VESTING_AMOUNT / 4 years`, `uint256(50_000_000e6) / 1 days`), with a comment stating
  the provenance of any composite precision (e.g. "1e25 = 1e6 * 1e18 * 10").
- Timestamps commented with the full UTC date; verify the conversion and verify the date against
  the post.
- APY/rate constants derived via continuous-compounding include the `bc -l` derivation in a
  comment — recompute it.

## 3. Rate-limit semantics (protocol-specific, silently wrong)

- **Zeroing a deposit rate limit can block withdrawals** — some code paths (e.g.
  `ERC4626Lib.withdraw`) consult a key you might think is deposit-only. When offboarding, verify
  what each zeroed key actually gates by reading the controller/lib source.
- **Exit paths need limits too** — onboarding that sets deposit limits but forgets withdraw /
  redeem / `LIMIT_ASSET_TRANSFER` exit keys traps funds. Conversely some venues (Maple) use
  request-redeem semantics: deposit + requestRedeem are limited, withdraw is intentionally
  unlimited. Match the venue's model, not the generic ERC4626 one.
- **Key construction must match the controller's runtime derivation** — wrong helper
  (`makeAddressKey` vs `makeAddressAddressKey` vs `makeUint32Key`) or wrong component order in a
  raw `keccak256(abi.encode(...))` creates a limit nothing consumes while the real action reverts
  at zero. Diff against the controller source for that `LIMIT_*` id.
- **Unlimited vs bounded is a spec decision** — `type(uint256).max` must be what the post says.
  Tests should demonstrate slope recharge with a warp, and show unrelated limits (e.g. CCTP
  staying unlimited) are untouched.

## 4. Roles & permissions

- **Grants without revokes** — migrating a role to a new holder must revoke the old holder on
  every affected chain. A leftover ALLOCATOR/CONTROLLER/SETTER is a live escalation path.
- **Exhaustiveness** — assert `getRoleMemberCount(ROLE) == N`, not just `hasRole` for expected
  members; filter `RoleGranted`/`RoleRevoked` logs and assert the exact count so no *unexpected*
  grant slips through.
- **New contracts**: admin must be the chain's executor (`SPARK_PROXY` on mainnet,
  `SPARK_EXECUTOR` on L2s), deployer must have zero residual access, no third party has any role.

## 5. Cross-chain wiring

- **Three id spaces that must never be conflated**: EVM chain ids, LayerZero endpoint ids
  (30101 = Ethereum, 30110 = Arbitrum, …), CCTP domain ids (0 = Ethereum, 3 = Arbitrum,
  6 = Base, …). Verify each id against official docs for the intended chain.
- LZ recipient/peer encoding: `bytes32(uint256(uint160(addr)))` of the **remote** chain's proxy —
  easy to encode the local one.
- LZ DVN send/receive confirmation configs must be symmetric with the remote side or the channel
  bricks (`commitVerification` reverts forever). If the spell touches DVN/send/receive configs,
  check both directions.
- Mainnet payload constructor `PAYLOAD_*` addresses, test `chainData[...].payload` addresses, and
  the actually-deployed L2 payloads must be the same addresses, chain by chain.
- OP-stack chains share the same L2 messenger address (`0x420...0007`) — tests relaying one OP
  chain's bridge must zero the other OP chain payloads to avoid cross-contamination (existing
  convention in tests; its absence causes flaky or falsely-passing tests).

## 6. Upgrade & migration completeness

- Controller upgrades must migrate **every** configured value from the old controller: max
  slippage, max exchange rates, tick limits, OTC buffer/recharge/whitelists, per-asset configs.
  The robust pattern reviewers converged on: replay the old controller's full setter-event history
  and diff against the new controller's state, plus `require(old == new)` in migration helpers.
- **Stale references during upgrades**: helpers like `SLLHelpers.configureERC4626Vault` that
  internally read `Ethereum.ALM_CONTROLLER` will configure the *old* controller if the same spell
  upgrades it — pass the new controller explicitly; in tests use `ctx.controller`, not the
  registry constant.
- Dependency lockstep: if the spell interacts with newly deployed ALM contracts, the
  `lib/spark-alm-controller` submodule must be at the matching released/audited tag — and must
  NOT be bumped when contracts weren't redeployed.

## 7. Timelocks & multi-step operations

- Morpho `submitCap` **increases** sit in a 1-day (sometimes longer) timelock needing `acceptCap`
  later; decreases are immediate. Asserting an increased cap immediately after execution is wrong.
  Boundary-test the timelock: revert one second before expiry, succeed after.
- Vesting/streams: warp tests must not overshoot the vesting end; check start/cliff/end arithmetic
  against the post's dates.
- Anything the spell starts but a later spell/keeper must finish (acceptCap, claim, finalize)
  should be called out in the review so the follow-up isn't forgotten.

## 8. SparkLend semantics

- Freezing vs pausing: frozen reserves block new supply/borrow but must still allow repay,
  withdraw, and liquidation. Tests must prove existing users aren't trapped and healthy positions
  aren't liquidatable purely due to the change.
- Offboarding an asset from the cap automator: remove the automator config AND set caps manually —
  reviewers rejected doing it through the automator; also assert `execSupply`/`execBorrow`
  afterwards can't move caps.
- Params rewritten incidentally by a struct update (e.g. liq bonus passed through unchanged) must
  still be asserted at their expected values.
- Use `ReserveConfiguration.MAX_VALID_SUPPLY_CAP` / `MAX_VALID_BORROW_CAP` for "infinite" caps,
  not ad-hoc literals.
- LTV ≤ liquidation threshold always; lowering LT can make existing positions liquidatable — if
  the post doesn't acknowledge that, flag it.
- New IRMs: read the deployed IRM's params on-chain (they are not in the diff) and check against
  the post; know the IRM family's semantics (e.g. in RateTargetKink IRMs the spread excludes the
  base rate — don't "correct" domain-accurate math without checking the contract).

## 9. Vault launches (inflation-attack & metadata hygiene)

- Dead deposit: initial mint to `address(1)`/`0xdead` present, exact shares and `totalSupply`
  asserted, mint/Deposit event contents checked.
- `name`/`symbol` match the established family convention (verify against an existing sibling
  vault via `cast call`); `decimals()` equals the underlying's.
- Deposits must revert before spell execution (vault not live early).
- New Morpho vaults: UI-listing requirements (adapter/factory checks), liquidity adapter config
  matching the sibling vault, `maxRate` in family tolerance.

## 10. Tests that prove nothing (the #1 review theme)

- Assertions must be **exact values**, not `assertGe`/non-zero/"didn't revert".
- **Before AND after**: assert the precise pre-state (old param value, zero rate limit, exact
  balance at the pinned block), execute, assert the precise post-state.
- **Assert the unchanged**: state adjacent to the change (other rate limits, other reserves'
  params, other role holders) must be asserted NOT to have changed.
- Assert collection lengths and event counts (`assertEq(reservesList.length, 18)`,
  "exactly 3 RoleGranted events") — otherwise extra actions hide in the gaps.
- Tautological assertions (loop counters that can't be wrong, messages asserting a different value
  than the code) — read each assertion asking "what input would make this fail?"
- Every onboarding/integration needs the matching e2e helper exercising the real flow (deposit,
  bridge round trip, liquidation path), not config asserts alone.
- Boundary tests: cap max vs max+1, timelock expiry ±1s, threshold ±1 wei via `vm.store`.

## 11. Fork staleness & determinism

- Hardcoded balance assertions drift as the chain moves — verify asserted balances are correct at
  the pinned `_blockDate`/block, and that the `_blockDate` comment matches the timestamp.
- Prefer relative warps (`vm.warp(block.timestamp + 3 days)`) over querying execution time —
  deterministic across block rolls.
- If the PR bumps fork blocks, re-check every exact-value assertion in the file, not just failing
  ones.

## 12. Copy-paste & drift (individually small, collectively the most common bug source)

Spells are written by editing the previous spell. Look specifically for:
- Wrong chain in comments/test names (Arbitrum block number pasted into an Optimism test).
- Token label mixups (sUSDS vs sDAI, WETH labeled ETH).
- Wrong forum/vote URL, or a stale one from the previous spell; missing description bullet for an
  action that exists in code.
- Assertion messages contradicting the asserted value.
- Redundant operations carried over (approving a bridge that a helper already approves), unused
  imports (some break compilation), leftover workarounds no longer needed, locally-declared
  interfaces duplicating `Interfaces.sol` or standard libs.
- Filename/title/date inconsistencies (directory date vs `@title` date vs `_spellId`).

## 13. Code placement & reuse (repo discipline reviewers enforce)

- Reusable payload logic belongs in `SparkPayloadEthereum`/`SLLHelpers`/`MorphoHelpers`, not
  inlined in one spell; reusable test logic belongs in the test harness
  (`SparkLiquidityLayerTests` etc.), not in one spell's test file.
- Iterate `pool.getReservesList()` instead of enumerating assets by hand when the action is
  "for all reserves".
- Style is enforced uniformly: aligned params/colons, named parameters for multi-arg struct calls,
  ALL_CAPS constants, alphabetical asset ordering, no gratuitous casts. Report style issues in a
  single grouped 🔵 finding, not one per line.

## 14. Deployment-stage verification (when reviewing a finalize PR)

- Independently verify **every** pre-deployed contract: `forge verify-bytecode` (or manual
  creation-code comparison) against the reviewed source at the release tag; constructor args
  decoded and checked against the post (a deployed controller with wrong constructor token
  addresses passed review once at code level and was caught only by constructor-param tests).
- Deployed via plain `CREATE` (not CREATE2), source verified on the chain's primary explorer,
  optimizer/EVM-version/license matching `foundry.toml`.
- Tests updated to run against the deployed payload addresses; no test skipped post-deployment.
- Codehash of the deployed mainnet spell matches a local build of the reviewed commit.
