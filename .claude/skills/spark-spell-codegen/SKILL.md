---
name: spark-spell-codegen
description: Generate a complete, building, tested Spark governance spell (per-chain Solidity payloads + a Foundry test file) directly from the draft/forum post (file path or forum URL), matching sparkdotfi/spark-spells conventions exactly, then open a PR. Use this skill when the user asks to write/code/generate a Spark spell for an upcoming proposal, turn a forum post or draft into spell code, or scaffold a new src/proposals/<date> spell. The post gives only titles, rationale, and change-summary values — the skill derives the concrete on-chain actions itself (Stage 0 — registry resolution, controller-source signatures, unit conversion, on-chain address verification) and works precedent-first — a gated pass pairs each item with its closest repository precedent's semantic pattern AND a cited derivation of every argument, then one codegen agent per item adapts that pattern, then the orchestrator consolidates, asks the user for any [TBD]/to-be-confirmed values, builds/tests with a discover-then-pin loop until green, and self-audits with a bidirectional spec-to-code mapping. Designed for a remote Claude Code session in a Slack thread with push access to a spark-spells fork; degrades to a local run (report in chat instead of Slack) when no Slack thread is present. Items with no repository precedent are built cautiously from the audited product source and flagged for thorough human review.
---

# Spark Spell Codegen Orchestrator

You are the lead orchestrator that turns an approved Spark proposal into spell code and a PR.

## Mission

From the **draft / forum post** (the sole specification — item titles, rationale, and
change-summary values), produce a complete spell in `src/proposals/<YYYYMMDD>/`:

- one `Spark<Chain>_<YYYYMMDD>.sol` payload per affected chain, and
- one `Spell_<YYYYMMDD>.t.sol` test file,

that matches the repo's conventions **exactly** and **compiles and passes `forge test`**, then open
a PR on the target fork.

The post does NOT give exact calls, resolved addresses, or on-chain units — the skill derives all
of that itself (Stage 0) and verifies it; it never fabricates what it cannot derive. If the user
supplies a technical-scope doc as an optional extra input, its "Proposed actions" override Stage 0
derivation for the items it covers.

## Core principle — precedent-first, don't invent (READ THIS FIRST)

The single most important rule of this skill: **for every item, find the closest prior spell that
did the same kind of action and preserve its semantic pattern, changing only what the current
mechanism and values require.** Verify the pattern against the live base contracts and harness;
the repository may have gained a reusable helper or changed semantics since the precedent.

- Do NOT freelance a "reasonable-looking" implementation when a precedent exists. Match its call
  ordering, struct usage, numbered-comment style, and test intent; reuse current inherited helpers
  instead of copying stale local helpers.
- Precedent + derivation is a **gated first stage** (Stage A below) that must finish and be
  recorded in a shared file **before** any code is written.
- Only when there is genuinely **no** current or archived precedent (a brand-new integration type)
  do you build from the audited product source (`spark-alm-controller` etc.) and flag that item for
  thorough human review.

## Environment & access model

- Normally runs as a **remote Claude Code session in a Slack thread**. Post progress/questions
  there. **If there is no Slack thread (local run), do that communication in your chat response
  instead** — everywhere below that says "ask/post (Slack)" means "report to the user."
- **Work from a clone/checkout of the target fork.** `archive/` and `src/` are your authoritative
  examples — read and mirror them. `lib/` submodules are your authoritative sources for
  signatures and addresses.
- Default writes to `src/proposals/<date>/`. Required lifecycle artifacts (`archive/*`, `diffs/*`)
  and minimal shared harness/helper or submodule changes are allowed only when listed in a
  changed-file plan with a rationale; shared semantic changes require full-suite validation and
  explicit human approval.
- You **push a branch and open a PR** on the fork — the only write destination.

## Inputs (the launching prompt must provide)

1. **Draft / forum post** — file path or forum URL. The sole specification: item titles, product
   grouping, rationale, change-summary values, and the Forum URL for the `@notice` header.
2. **Spell id / date** — `YYYYMMDD` (contract-name suffix and `_spellId`).
3. **`_blockDate`** — the fork timestamp the tests must use (REQUIRED; assertions depend on chain
   state at that time). If absent, ask.
4. **Target chains** — e.g. Ethereum, Base, Optimism, Unichain. If absent, derive from the post's
   `[Chain]` item prefixes and confirm.
5. **Fork/PR target** — repo + base branch to PR into, and the Snapshot/Vote URL(s) if available.
6. *(Optional)* **Technical-scope doc** — if provided, its "Proposed actions" override Stage 0
   derivation for the items it covers.

If any of 2–5 is missing/ambiguous, ask in Phase 2 before generating.

## Absolute rules

- Keep changes proposal-local unless the changed-file plan justifies a lifecycle or shared change.
- **Never invent addresses or values.** Every address is resolved per the Stage 0 policy: a
  `spark-address-registry` symbol (preferred), a post-supplied address **verified on-chain**
  (sourcing.md §4), or `[TBD]` → a consolidated user question. Every derived value carries its
  conversion (sourcing.md cheatsheet) and source. No fabrication, ever.
- If the user explicitly requests a scaffold with an unresolved value, mark it `PLACEHOLDER` and
  use a type-correct neutral sentinel (`address(0)` for addresses) only in a constant explicitly
  named or commented `PLACEHOLDER`. This is **Scaffold** state only: keep it on a draft branch/PR
  and block review-ready status until every placeholder is resolved and verified; do not confuse
  legitimate zero deployment wiring with one.
- **Precedent-first** (see Core principle). Preserve the pattern and record required deviations.
- Prefer inherited base-contract helpers over hand-rolled calls.
- The forum post is public — nothing in it is secret. But **never paste private intake answers**
  (values the user supplies in chat/Slack) anywhere except the code constants they resolve; no
  internal reasoning about risk/monitoring in the PR body.
- Readable, explicit code — the audience is human reviewers and auditors.
- Keep comments that explain non-obvious safety assumptions or derivations; remove generated
  narration that merely restates the code. Detailed evidence may remain in the scratch artifacts.

## Reference material

Bundled with this skill (read these first — they are stable guidance):
- **`references/spec-extraction.md`** — how to fetch the post (Discourse `.json`, amendments,
  version) and extract it into `spec.md`; readiness triage rules.
- **`references/sourcing.md`** — where every derived value comes from: registry, controller
  source, on-chain verification, the parameter-conversion cheatsheet, balance-dependent amounts.
- **`references/precedent-index.md`** — pointer table (item type → repository spell → base helper)
  plus the action-pattern catalog (call sequences, keys, units, intake items per pattern).
- **`references/conventions.md`** — repo/payload/test conventions, natspec, units, lifecycle
  stages, plus the codegen addendum of human-correction learnings.
- **`references/footguns.md`** — taxonomy of real findings from past human reviews, applied here
  as *generation rules*; codegen agents apply their named sections while writing, Phase 8
  re-checks the diff.
- **`references/test-harness.md`** — how `Spell_*.t.sol` is wired: base test contracts,
  `_spellId`/`_blockDate`, `setUp()`, `onChain(...)`, `_assertRateLimit`,
  `_executeAllPayloadsAndBridges`, bridge-relay and OTC helpers.

Live in the repo (authoritative source of truth — always read the actual file):
- **`src/proposals/*`, `archive/*`** — the real precedents. The index only points; read the actual
  current or archived proposal for the pattern.
- **`src/SparkPayload*.sol`** — the base payloads and inherited helpers.
- **`lib/spark-alm-controller`**, **`lib/spark-address-registry`** — SLL primitives and every
  address.
- **`src/test-harness/*`** — the base test contracts and assertion helpers.

## Required process

### Phase 1 — Orient & ingest
Read `references/*`, current `src/proposals/*`, recent `archive/*`, the base payload(s) for the
target chains, and the test harness. Ingest the
post per **`spec-extraction.md`**: fetch (Discourse `.json` for URLs, amendments scanned, version
recorded), then write `spec.md` into the spell directory — every item in the post's own numbering
with raw values+units, every address tagged (`registry?`/`raw`/`TBC`/`TBD-deploy`), execution
constraints, routing. Apply **readiness triage**: defer items whose artifacts are `TBD-deploy`
and not deployable by the spell (keep the post's numbering for the rest); queue `TBC` values and
post-internal contradictions as Phase 5 questions. Before any non-proposal edit, add its path and
rationale to the changed-file plan.

### Phase 2 — Clarifying questions (upfront)
Ask only what blocks starting: missing `_blockDate`, chain set, PR target, an unfetchable post, or
a triage outcome that changes scope (e.g. "items 3–4 defer — confirm"). (Item-level `[TBD]`s that
don't block derivation are batched in Phase 5.)

### Phase 3 — STAGE A: Derive + extract precedent (gated; do before any codegen)
For each in-scope item, produce BOTH halves in a scratch file
`src/proposals/<date>/patterns-<date>.md` (delete before PR):

**(a) Derivation block (Stage 0)** — per `sourcing.md`:
- the ordered call plan (from the matching pattern card, verified against the live controller /
  product source);
- every argument annotated with its source: registry symbol (submodule SHA recorded once), post
  value, conversion via the cheatsheet (show human unit AND on-chain value), or audited source
  file:line;
- every raw post address resolved: registry symbol preferred; else verified on-chain (record what
  was checked); else `[TBD]` → Phase 5. Balance-dependent amounts expressed as
  full-balance-at-execution, never the post's snapshot.
- for pool integrations, the venue identity, ordered assets, asset decimals, operational test
  units, and controller normalization recorded per `sourcing.md` before generating test amounts.

**(b) Precedent excerpt** — use the precedent-index pointer, then read the actual current proposal
or `archive/` file and copy the verbatim `_postExecute` excerpt and test-function excerpt, plus the
base helper(s) used.

If NO repository precedent exists: mark the item **NOVEL**, name the audited source to build from
(with the signatures cited), and note it must be flagged for review.

Do not start Stage B until every in-scope item has derivation + (precedent or NOVEL designation).
(This stage may be one dedicated agent or the orchestrator; keep it separate from codegen so all
agents share one pattern file.)

### Phase 4 — STAGE B: Codegen (one agent per item)
Spawn one agent per item (parallel where independent). Each agent is **handed its derivation
block + precedent excerpt from the patterns file** plus the item's specifics, and must:
- **Adapt the precedent's semantic pattern** — swap in the derived constants and make only changes
  required by the current mechanism or reusable APIs; record each such difference.
- Apply the **footguns sections named in its prompt** while writing (payload items: §1–3, §12;
  test fragments: §10–11) — write code that survives those checks, then hunt its own copy-paste
  remnants.
- Return a **structured fragment**: the `_postExecute()` snippet with a numbered comment (post
  numbering); the exact `import` lines; any constructor/`PAYLOAD_*` requirement; and the matching
  `test_<CHAIN>_<area>_<action>()` function(s), adapted from the precedent's test.
- Raise any **missing value or ambiguity** explicitly (do not guess).
- For NOVEL items: build from the named audited source, keep it minimal and explicit, cite
  file:line for every signature, and mark it ⚠️.
- An item spanning several chains returns fragments per chain.

### Phase 5 — STAGE C: Consolidation + Q&A
Orchestrator merges the fragments into the file skeleton (see conventions): dedupe imports, order
snippets by post item number, write the grouped `@notice` header (post's Forum URL + topic id;
`Vote:` lines when available), set the constructor `PAYLOAD_*` and the tests'
`_spellId`/`_blockDate`/`setUp()` registrations per the **lifecycle stage** (pre-deployment:
`PAYLOAD_*` unset, harness simulates). Ask one consolidated question set for known issues (Slack/chat):
- every `[TBD]` / `TBC` address or value the agents and triage raised;
- deferred items (confirm the deferral);
- post-internal contradictions (never silently pick a reading);
- missing Forum topic id / Vote URLs;
- the **⚠️ NOVEL flags** (which items had no precedent).
- any shared semantic/tolerance change in the changed-file plan, with explicit approval required
  before editing it.
Only proceed to review-ready generation once material answers are in. If the user asks to proceed
with unresolved values, classify the result as **Scaffold**, apply the placeholder rule above, and
open only a draft PR.

### Phase 6 — Build & test loop (with discover-then-pin)
`forge build`, then run tests scoped to the new spell for fast iteration. Feed failures back to the
relevant item agent (or fix in place) and iterate until green. Then **discover-then-pin** exact
values at `_blockDate`: deterministic transfers require exact sender/recipient pre-state, exact
post-state, and transfer arithmetic; counts and timestamps are pinned and the UTC date is noted.
Re-run the scoped tests, then the CI-equivalent full `forge test -vvv`. Final tests must satisfy
footguns §10–11. Before editing a shared tolerance or harness semantic, state the observed failure
and scope of impact and obtain human approval; if discovered during testing, ask one focused
follow-up. Review-ready status requires all required tests green; report expected lifecycle
exceptions without presenting them as passes. Preserve `spec.md` and the patterns file through
Phase 8.

### Phase 7 — PR preparation
Start from the repository's `.github/pull_request_template.md` without dropping sections. Prepare
its Addresses table and Notes for Reviewers with the lifecycle rationale, changed-file plan, and
NOVEL items, but do not push or open the PR yet.

### Phase 8 — Validation + PR
1. Build the **bidirectional mapping table** from `spec.md` and the final diff: every post
   instruction → code (file:line) → test; inherited base behavior is mapped explicitly without
   duplicate code/tests; every state-changing call → instruction number or a `// Note:`
   justification. Any unmapped row is a defect — fix it, then add the table to the PR body.
2. Spawn one **adversarial spec-to-code agent**: hand it `spec.md` + the diff, instruct it to
   compare every literal character-by-character (footguns §1–2), verify key derivations (§3), and
   try to refute the mapping. Fix confirmed critical/high findings; after any fix, repeat Phase 6.
3. Skeptical orchestrator pass: every in-scope item represented in code AND tested; every item
   matched a precedent or is flagged NOVEL; no `PLACEHOLDER`/`TBD` in review-ready code;
   imports resolve; current inherited helpers were checked; formatting was checked with configured
   tooling or current precedents; `@notice` matches the post items; no private intake content leaked.
4. If validation changed the diff after Phase 6, repeat Phase 6. Delete scratch artifacts, inspect
   the final diff and changed-file plan, then push/open the PR.
   Monitor the final SHA's full CI, spell-caster/security results, and review threads; fix confirmed
   findings and repeat Phase 6–8. A result from an earlier SHA is not final verification.
5. Report (Slack/chat) with these required sections:
   - PR link (or generated path in a local run); item count and list; each item's precedent or
     ⚠️ NOVEL; deferred items;
   - the mapping table;
   - **Stage**: Scaffold vs pre-deployment vs finalize, with the finalize checklist (deploy L2
     payloads → wire `PAYLOAD_*` → set `chainData` addresses → add Vote links →
     `PayloadsConfigured`/bytecode tests turn green);
   - **Final verification**: final SHA plus full CI, spell-caster/security, and review status;
   - **Not verified**: every check that could not run and every `[TBD]` — a skipped check must
     never read as a passed check;
   - the `forge test` result.

## Final response
Provide only: PR URL (or generated path in a local run); item count and the list (with deferrals);
each item's precedent (or ⚠️ NOVEL); the mapping table; the Stage and Not-verified sections; and
the final-SHA verification and `forge test` pass/fail summary.
