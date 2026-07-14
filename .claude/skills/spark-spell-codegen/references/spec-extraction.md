# Spec extraction — turning the forum post into `spec.md`

> Ingestion procedure shared with `spark-spell-review` (its Phase 1) so both skills produce and
> consume the same artifact shape. If the review skill's procedure changes, re-sync.

The draft/forum post is the **sole specification**. Extract it into a working file once, up front,
and drive everything (Stage 0 derivation, codegen, Phase 8 mapping) from that extraction — never
from memory of the post.

## Fetching the post

Input may be a local file (use as-is) or a forum URL. The forum is Discourse, so a URL gets clean
structured content by appending `.json`:

```bash
curl -sfL "<forum-url>.json"     # e.g. .../t/<slug>/<topic-id>.json
```

- The specification is `post_stream.posts[0].cooked` (HTML — convert/read it fully).
- **Scan subsequent posts by the proposal author for amendments** ("updated the rate limit to…").
  The spec is the post **as amended** — an amendment silently missed is a wrong-constant spell.
- Record the post's `version`; if `> 1` note that it has been edited (and when vs. today).
- Fallbacks, in order: WebFetch on the plain URL; `curl` on the plain URL. If all fetches fail,
  STOP and ask the user for the post content — there is no spell without a spec.

## What `spec.md` must contain

Write to the spell directory as part of the patterns scratch file (or alongside it; delete before
PR). Per item, in the post's own numbering:

1. **Item number + title + chain(s)** — exactly as the post's Summary lists them, including the
   `(Recurring/Exec)` marker.
2. **Every parameter** with its exact value **and unit** as written (amounts, bps, slopes,
   caps, dates). Do not convert here — conversion happens in Stage 0 with the cheatsheet, so the
   raw post value stays available for the Phase 8 character-by-character comparison.
3. **Every address**, verbatim, each tagged with its status:
   - `registry?` — to be resolved against `lib/spark-address-registry` in Stage 0;
   - `raw` — supplied in the post, needs on-chain verification (sourcing.md §4);
   - `TBC` — the post says *to be confirmed*;
   - `TBD-deploy` — the post says *to be deployed / to be provided*.
4. **Execution constraints** — ordering, office hours, direct-execution notes, dependencies on
   other spells or prior votes, concurrent-execution assumptions (e.g. "settlement risk mitigated
   by concurrent execution of X and Y spells").
5. **Routing** — Snapshot-then-Exec vs recurring/direct-to-Exec, as stated or inferable.

Also extract document-level facts: the Forum URL + topic id (for the natspec header), any Vote /
Snapshot links, and the post version/fetch date.

## Readiness triage (applied immediately after extraction)

- An item whose required on-chain artifacts are `TBD-deploy` **and** cannot be deployed by the
  spell itself → **defer**: exclude from codegen, keep the post's numbering for the remaining
  items, and list the deferral prominently in Phase 5 and the final report.
- `TBC` values (recipients, multisigs) → the item stays in scope, but the value is a consolidated
  **Phase 5 question**; codegen proceeds only for parts not blocked by it, or waits if the value
  is load-bearing.
- Contradictions inside the post (prose says 100k, change summary says 155k) → always a Phase 5
  question. With no scope doc to adjudicate, never silently pick one reading.
