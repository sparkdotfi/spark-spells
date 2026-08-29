# Sourcing recipe — where every derived value comes from

> Adapted from `spark-gov-proposal/references/sourcing.md` @ 2026-07-07 (audit-citation and
> governance-timing sections dropped; procedures adapted to run inside a spark-spells checkout).
> When the source skill's copy improves, re-sync the shared parts.

The generated spell is only as trustworthy as its sources. Golden rule: **every address, key, and
amount is either copied from the forum post, resolved from a canonical source below, or supplied by
the user and verified on-chain. Nothing is invented. When a value can't be resolved, record
`[TBD]` + what's needed + who confirms — it becomes a Phase 5 question, never a guess.**

## 1. Standard ecosystem addresses → spark-address-registry

The registry is the single source of truth for every already-deployed Spark/Sky address: SubDAO
proxy, ALM controller/proxy/rate-limits, tokens (USDS/USDC/USDT/sUSDS), L2 executors + ALM proxies
+ token bridges, multisigs (foundation, asset foundation, ops, freezer), SparkLend spTokens,
treasuries.

- Read the **local submodule** `lib/spark-address-registry/src/<Chain>.sol` and reference constants
  by symbol (`Ethereum.USDS`, `Unichain.TOKEN_BRIDGE`) — never re-hardcode a registry address.
- Record the submodule's pinned SHA once (`git -C lib/spark-address-registry rev-parse HEAD`) and
  cite it in the patterns file. If the post references an address the submodule doesn't have,
  check whether the registry's remote master has it (the submodule can lag) — if so, that's a
  "registry bump needed" flag for the user, not a hardcode.
- **Do NOT trust cached address tables** in skill reference files or memory — they go stale.
  Always read the live registry file.

## 2. Mechanism semantics & function signatures → lib/spark-alm-controller (and product repos)

For any SLL action, read the controller source in the local submodule for the exact calls and
their gating:

- `src/MainnetController.sol` (mainnet ops + admin setters), `src/ForeignController.sol` (L2 ops),
  `src/RateLimits.sol` + `src/RateLimitHelpers.sol` (limit keys), `src/OTCBuffer.sol` (OTC buffer).
- Capture: function names + signatures the spell will call, which role gates them
  (`DEFAULT_ADMIN_ROLE` config setters are executed by the spell as Spark Proxy / the L2 executor;
  `RELAYER`-gated functions are operational, not spell calls), and **how each rate-limit key is
  computed at call time** — the key you set must match the derivation the controller performs when
  consuming it (see footguns §3).

Other product repos by item type (read the local `lib/` copy when vendored, the GitHub repo
otherwise): `sparklend-advanced` (IRMs), `sparklend-v1-core` (Pool/Configurator), `spark-vaults-v2`
(SparkVaultV2), `spark-psm` (PSM3), `spark-gov-relay` (Executor), `xchain-helpers` (forwarders,
EID/domain constants).

## 3. Action patterns → references/precedent-index.md + archive/

Match each post item to a pattern card in `precedent-index.md` first; the card names the call
sequence, keys, units, and intake items. Then inspect the matching current or archived proposal and
extract its semantic pattern (Stage A). If no repository precedent matches, the item is NOVEL:
build minimally from the audited product source and flag it.

## 4. On-chain verification of supplied/new addresses

For any raw address in the post that is not a registry constant (counterparties, freshly-deployed
contracts, recipient multisigs):

- Verify on-chain before use (Blockscout MCP tools or `cast` against the chain's RPC):
  code exists on the right chain (or is a known EOA counterparty), source verified, contract name
  matches expectations, admin/roles are the chain's executor with **zero deployer residue**, and
  sanity getters agree (e.g. a buffer's `almProxy()` == registry `ALM_PROXY`; EIP-1967
  implementation slot for proxies).
- A supplied address that verifies to the *wrong* contract (e.g. last cycle's payload) is a
  finding to surface, not a value to use.
- Record what was verified (and how) in the patterns file; anything unverifiable is `[TBD]` and
  goes in the report's **Not verified** section.

### Pool identity and units

Before generating an AMM test amount, verify at `_blockDate` and record the canonical factory/pool
identity, ordered assets, and each asset's `decimals()`. For Curve, query `coins(0)`/`coins(1)` and
factory membership; for Uniswap, reconstruct the PoolKey and pool id. Record the human amount and
raw token amount separately from controller rate limits, which may be 1e18-normalized regardless
of token decimals. An unresolved pool keeps the item in Scaffold state; never infer units from its
rate-limit values.

## Parameter conversion cheatsheet

| Post says | On-chain value | Notes |
|---|---|---|
| `maxSlippage: 20bps` | `0.998e18` | `(1 - bps/10000) * 1e18` (wad) |
| `slope: 100M/day` | `uint256(100_000_000e18) / 1 days` | per-second; the rate-limit `slope` field. No separate refill-rate field. |
| `rechargeRate: 50K/day` | `uint256(50_000e18) / 1 days` | per-second, 1e18 precision |
| `maxAmount: 5M` (1e18-normalized limits) | `5_000_000e18` | check the limit's normalization in the controller |
| `10,000 USDS` | `10_000e18` | token decimals: USDS/DAI/sUSDS e18, USDC/USDT e6, WBTC e8 |
| `unlimited` | `setUnlimitedRateLimitData(key)` | asserts as `type(uint256).max`, slope 0 |
| rate-limit key | `keccak256(abi.encode(LIMIT_<NAME>, <operand(s)>))` | via the matching `RateLimitHelpers.make*Key` — verify operand arity against the controller |

Always record **both** the human unit (from the post) and the on-chain value in the patterns file,
with the source of each.

## Balance-dependent amounts

When the post gives a precise snapshot that represents "the whole balance" (e.g. "transfer
85,943,747.63 × conversion rate at execution", "withdraw the full ALM Proxy balance"), do **not**
hardcode the snapshot — it will be stale at execution. Verify the live balance on-chain for
sizing/sanity, and express the action as **full-balance-at-execution** (`type(uint256).max` where
the contract caps to available balance, or a live `balanceOf`/conversion read at execution).
Note in the PR that the post's figure was an at-drafting estimate. Same for recurring "claim all"
items.

For a fixed deterministic transfer, query exact sender and recipient balances at `_blockDate` and
pin exact pre-state, post-state, and transfer arithmetic. Relational assertions alone are not
sufficient.
