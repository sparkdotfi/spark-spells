# Precedent index & action-pattern catalog

> Catalog cards merged from `spark-gov-proposal/references/patterns.md` @ 2026-07-07 — keep the
> two in sync when either side learns a new pattern.

Two layers, used together in Stage A:

1. **Pointers** — which `archive/<date>/` spell exemplifies an item type. Pointers are not the
   pattern: always open the actual archive file and extract the verbatim code. Prefer the most
   recent match (conventions evolve).
2. **Pattern cards** — the canonical call sequence, rate-limit keys, units, and intake/`[TBD]`
   items per action type, mined from spell history. Cards anchor Stage 0 derivation; the archive
   file anchors the code shape. **Re-verify specifics against the live source** (`lib/` submodules,
   `src/SparkPayload*.sol`) — signatures and keys evolve; the cards are the map, not frozen truth.

**If an item matches no card and no archive grep hit → exploration mode:** mine `archive/` history
directly (greps below, then read candidates), and if genuinely nothing matches, the item is
**NOVEL**: build minimally from the audited product source (sourcing.md §2), cite file:line for
every signature used, and flag for thorough human review. Do not improvise an unmapped action.
Consider appending a new card here afterwards.

## Finding a precedent fast

- By action verb / helper: `grep -rl "setRateLimitData\|_transferFromSparkLendTreasury\|setSupplyCapConfig\|_configureERC4626Vault\|setReserveFactor\|bridgeERC20To\|setOTCBuffer" archive/`
- By product wording: grep the `@notice` headers across `archive/*/Spark*_*.sol`.
- By harness helper: grep `src/test-harness/` for a `_test*Integration` helper matching the item —
  its existence reveals the expected test shape even for first-time payload patterns.

## Pointer table — common item types

| Item type | Precedent pointer(s) | Base helper / call |
|---|---|---|
| Claim / consolidate SparkLend reserves | automatic in `SparkPayloadEthereum.execute()` since `20260326` — no payload code, no @notice bullet | `_transferFromSparkLendTreasury(aTokens, recipient)` |
| Foundation / grant USDS transfer | `archive/20260507`, `20260618` | `IERC20(Ethereum.USDS).transfer(recipient, amount)` |
| Transfer excess USDS for SPK buybacks | `archive/20260326`, `20260507`, `20260604` | `IERC20(USDS).transfer(...)` from SubDAO proxy |
| Update SLL rate limits (PSM/mint/transfer/swap) | `archive/20260604`, `20260409`, `20260226` | `RateLimits.setRateLimitData(key, max, slope)`, keys via `RateLimitHelpers` / controller `LIMIT_*` |
| OTC buffer onboarding (exchange integration) | `archive/20260618` | card 2 below |
| Remove excess L2 liquidity (L2→L1 withdrawal) | `archive/20260618` (Unichain/Optimism/Base) | card 4 below |
| Cap automator params | `archive/20260604` | `ICapAutomator.setSupplyCapConfig / setBorrowCapConfig` |
| Deprecate asset / e-mode / reserve factor / LTV | `archive/20260604` | `LISTING_ENGINE.POOL_CONFIGURATOR()....` |
| Killswitch oracle add/config | `archive/20260115`, `20260312` | killswitch oracle mechanism |
| Onboard SLL venue — ERC4626 vault | (grep `_configureERC4626Vault` in archive) | `_configureERC4626Vault(...)` |
| Onboard SLL venue — Curve pool | (grep `_configureCurvePool`) | `_configureCurvePool(...)` |
| Onboard SLL venue — Morpho vault | (grep `_setUpNewMorphoVault` / `V2`) | `_setUpNewMorphoVault(...)` / `V2` |
| Onboard SLL venue — Uniswap v4 pool | `archive/20260129` | Uniswap v4 pool onboarding |
| Onboard SLL venue — Aave market | (grep `_configureAaveToken`) | `_configureAaveToken(...)` |
| Upgrade ALM controller version | `archive/20260129` (v1.9.0), `20260312` (v1.10) | controller upgrade pattern |
| Upgrade ALM Proxy Freezable | `archive/20260604` | freezable migration pattern |
| Cross-chain mint / seed L2 PSM3 (outbound) | `archive/20260115` | SLL cross-chain mint + bridge |
| IRM retarget | `archive/20260423`, `20251113`, `20250807` | card 6 below |
| L2 Savings vault (SparkVaultV2) onboarding | `archive/20251002`, `20251016` | card 7 below |
| Bridge-route rate limit (LayerZero / CCTP) | `archive/20250220` (CCTP shape) | card 3 below |

## Meta-pattern: cross-chain dispatch

Almost every multi-chain spell is driven from the **Ethereum spell**. Its constructor sets
`PAYLOAD_<CHAIN> = 0x…` (the deployed foreign payload address) per L2 item;
`SparkPayloadEthereum.execute()` bridges each non-zero payload to that chain's `SPARK_EXECUTOR`.
Mainnet actions run as the Spark Proxy; L2 actions are a *separate foreign payload* relayed in.
The foreign payload addresses are deploy-time **intake** items: at pre-deployment stage the
constructor stays unwired (`address(0)` → the test harness simulates foreign execution) and
`test_ETHEREUM_PayloadsConfigured` stays red until finalize — expected, see conventions.md
lifecycle section.

## Pattern cards

### 1. SLL rate-limit set (foundation)
The primitive under OTC, bridge routes, vault take/transfer, PSM, mint, etc.
- **Contracts:** `ALM_RATE_LIMITS` (`IRateLimits`); keys/limits on `MainnetController`/`ForeignController`; helpers `SLLHelpers.setRateLimitData`, `RateLimitHelpers` (`makeAssetKey`, `makeAddressKey`, `makeAddressAddressKey`, `makeDomainKey`/`makeUint32Key`, `makeAssetDestinationKey`, `makeBytes32Key`).
- **Calls:** finite → `rateLimits.setRateLimitData(key, maxAmount, slopePerSecond)` (or the `SLLHelpers` 5-arg wrapper with decimals); unlimited → `setUnlimitedRateLimitData(key)`.
- **Units:** amounts in the limit's normalization (check the controller — some limits are 1e18-normalized regardless of token decimals); `slope` is per-second = `uint256(<per-day>) / 1 days`.
- **Key:** `keccak256(abi.encode(LIMIT_<NAME>, <operand(s)>))`. **Verify operand arity** — some keys are 1-field, most 2-field (helper), a few 3-field with **no helper** (hand-roll, see card 3).

### 2. OTC buffer onboarding (Ethereum)
Six admin calls, in order: `OTCBuffer.approve(asset, type(uint256).max)` ×2 (buffer allowance to
ALM Proxy, for `otcClaim`); `setRateLimitData(makeAddressKey(LIMIT_OTC_SWAP, exchange), max, slope)`;
`setMaxSlippage(exchange, wad)`; `setOTCBuffer(exchange, buffer)`; `setOTCRechargeRate(exchange,
perSecond18)`; `setOTCWhitelistedAsset(exchange, asset, true)` ×2 (**requires buffer already set**).
- **Intake:** buffer + exchange addresses (verify on-chain: buffer `almProxy()`, admin roles, proxy implementation).
- **Test:** pre/post config asserts + `_testOTCIntegration(OTCE2ETestParams({...}))`, one test per swap direction.
- **Example:** `archive/20260618/SparkEthereum_20260618.sol`.

### 3. SLL bridge-route rate limit (LayerZero/OFT e.g. USDT0; CCTP for USDC)
- **When:** enable/cap a token bridge route between Ethereum and an L2. **USDC uses CCTP** (`LIMIT_USDC_TO_DOMAIN` + Circle domain id via `makeDomainKey`/`makeUint32Key`, paired with `setMintRecipient`). **USDT0 / OFT uses LayerZero** (below).
- **Key (LayerZero):** `keccak256(abi.encode(controller.LIMIT_LAYERZERO_TRANSFER(), oftAddress, dstEndpointId))` — **3 fields, no `RateLimitHelpers` builder; hand-roll it** to match `LayerZeroLib`.
- **Calls — outbound (rate-limited), on the sending chain's spell:**
  1. `controller.setLayerZeroRecipient(dstEid, SLLHelpers.addrToBytes32(<dstChain>.ALM_PROXY))`
  2. set the 3-field key's rate limit (finite, token decimals).
- **Calls — inbound (unlimited return), on the receiving chain's spell:** `setLayerZeroRecipient(ENDPOINT_ID_ETHEREUM, addrToBytes32(Ethereum.ALM_PROXY))` + `setUnlimitedRateLimitData(<3-field key with the local OFT + ETH EID>)`.
- **Id spaces (footguns §5):** LayerZero **EIDs** (30101 Ethereum, 30110 Arbitrum, …) ≠ CCTP domains (0 Ethereum, 3 Arbitrum, 6 Base, …) ≠ EVM chain ids. Confirm each against official docs; EIDs for new chains are intake, not guesses.
- **Intake:** OFT adapter + token addresses per chain, destination EID. Each direction needs its own key + recipient — setting one side does not enable the return route.
- **Closest analog:** `archive/20250220` (USDC/CCTP outbound shape).

### 4. Remove excess L2 liquidity (USDS/sUSDS → Ethereum), incl. PSM3 sweep
- **Simple (ALM-Proxy-only) sequence — `execute()` on the foreign payload:**
  1. `almProxy.grantRole(almProxy.CONTROLLER(), address(this))`
  2. `almProxy.doCall(USDS, abi.encodeCall(IERC20.approve, (TOKEN_BRIDGE, amount)))`
  3. `almProxy.doCall(TOKEN_BRIDGE, abi.encodeCall(ITokenBridgeLike.bridgeERC20To, (<Chain>.USDS, Ethereum.USDS, Ethereum.ALM_PROXY, amount, uint32(500_000), bytes(""))))`
  4. repeat 2–3 for sUSDS
  5. `almProxy.revokeRole(almProxy.CONTROLLER(), address(this))`
- **Full balance incl. PSM3:** before bridging, sweep PSM3 into the proxy per asset via
  `doCall(PSM3, abi.encodeCall(IPSM3.withdraw, (asset, <Chain>.ALM_PROXY, type(uint256).max)))`
  (caps at the withdrawable position), then bridge the **live re-read** balance. `[VERIFY]` whether
  to bypass controller rate limits (direct `doCall`) or use `ForeignController.withdrawPSM`
  (decrements `LIMIT_PSM_WITHDRAW` — a large sweep may exceed it).
- **Amounts:** never hardcode a post snapshot for "full balance" items (sourcing.md, balance rule).
- **Gotchas:** `bridgeERC20To` only *initiates* — OP-stack 7-day challenge + prove/finalize before
  funds land on L1. Always revoke the temporary role. Tests must zero the **other** OP-stack
  chains' payloads (shared `0x4200…0007` L2 messenger — footguns §5) and use
  `OptimismBridgeTesting.relayMessagesToSource(bridges[0], false)` then assert L1 arrival.
- **Example:** `archive/20260618/Spark{Unichain,Optimism,Base}_20260618.sol` (flat 10k each).

### 5. SparkLend — claim reserves (recurring)
Automatic in `SparkPayloadEthereum.execute()` since `20260326`: stablecoin spTokens → `ALM_PROXY`
(DAI via `DAI_TREASURY`, others via `TREASURY`), remaining aTokens → `ALM_OPS_MULTISIG`. **No
payload code, no @notice bullet**; the inherited `test_ETHEREUM_sparkLend_withdrawAllReserves`
covers it.

### 6. SparkLend — interest rate model (IRM) retarget
Strategies are **immutable** → deploy new + repoint. New IRM address is a pre-deployed **intake**
item (verify constructor params on-chain — they are not in the diff). In `_postExecute`:
`LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.<ASSET>, NEW_IRM)`.
Units in **ray** (1e27). Reuse the prior IRM's `RATE_SOURCE()` unless intentionally re-anchoring.
Examples: `archive/20260423` (Kink IRMs), `20251113`, `20250807`.

### 7. Spark Savings — onboard SparkVaultV2 vault on an L2 (spUSDT-style)
Vault assumed pre-deployed; the (foreign) spell configures + seeds it:
- **Roles:** `DEFAULT_ADMIN` = chain executor (already held); `SETTER_ROLE` → per post (ops multisig
  or ALM Proxy Freezable); `TAKER_ROLE` → `ALM_PROXY`.
- **Yield/cap:** `setVsrBounds(minVsr, maxVsr)` (per-second ray; `1e27` = 0% floor — compute, don't
  hand-pick); `setDepositCap(cap)` in asset decimals. Seed: `safeIncreaseAllowance` +
  `vault.deposit(seed, address(1))` (anti-inflation dead deposit — footguns §9).
- **SLL limits (usually unlimited):** take → `makeAssetKey(LIMIT_SPARK_VAULT_TAKE, vault)`;
  transfer → `makeAssetDestinationKey(LIMIT_ASSET_TRANSFER, vault.asset(), vault)`; plus the
  bridge/return route (card 3) and CCTP onboarding if it's a brand-new chain
  (`ForeignControllerInit.initAlmSystem` first).
- **Intake:** vault proxy address, setter address, seed amounts, VSR bounds, return-route addresses.
- **Examples:** `archive/20251002` (mainnet `_configureVaultsV2`), `20251016` (Avalanche foreign variant).

### 8. Treasury grant / transfer (recurring)
`IERC20(Ethereum.USDS).transfer(recipient, amount)` as Spark Proxy; recipients from registry
(`SPARK_FOUNDATION_MULTISIG`, `SPARK_ASSET_FOUNDATION_MULTISIG`, `ALM_OPS_MULTISIG`); per-tranche
amounts from the post's change summary. Example: `archive/20260507`, `20260618`.

### 9. Governance bridge — add timelock + guardian
`spark-gov-relay` `Executor` is self-administered; the relayed spell calls
`IExecutor(executor).updateDelay(newDelay)` and `grantRole(GUARDIAN_ROLE(), guardianMultisig)`
(guardian = pure veto: can only `cancel` queued sets). **No production example in archive yet** —
NOVEL-adjacent; confirm the flow with the governance/relay team. Don't confuse with Morpho vault
timelock/guardian (different system).
