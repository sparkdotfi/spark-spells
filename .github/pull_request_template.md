# YYYY-MM-DD Spark Spell

## Forum Post

< forum post URL >

## Dependencies on Sky Core spell
- list of items (or None)

## Addresses

| variable name           | address    | network   | source of truth                 |
| ---                     | ---        | ---       | ---                             |
| `PT_SUSDE_MAR26`        | `0x123...` | `mainnet` | specified in forum post         |
| `PT_SUSDE_MAR26_ORACLE` | `0x456...` | `mainnet` | provided in TG chat with Pendle |

## Notes for reviewers
- Pay extra attention to: ...
- Extra feedback wanted on: ...

## Conditions for Spell Deployment
- [] All spell-specific tests passing.
- [] All E2E tests passing.
- [] All newly deployed addresses reviewed and added to spark-address-registry.
- [] Complete test coverage.
- [] At least three approvals from reviewers.

## Conditions for Spell Handoff to Sky
- [] Spells deployed and verified on Etherscan.
- [] All spell-specific tests passing (including spell bytecode verification).
- [] All E2E tests passing.
- [] Spell caster passing in CI.
- [] At least three approvals from reviewers on deployed spell.
- [] Comment from at least three reviewers confirming address of spell.

## Conditions for Spell Merge
- [] Spell handoff performed to Sky team on Discord.
- [] Spell handoff performed to Sky team on Signal.
- [] Spell address confirmed to be correct in spells-mainnet repo PR through comments by at least three reviewers.
- [] Sky deployed spell confirmed to contain correct Spark payload address by at least three reviewers in this PR.
