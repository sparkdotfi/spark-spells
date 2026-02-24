# YYYY-MM-DD Spark Spell

## Forum Post
< Forum post URL >

## Dependencies on Sky Core spell
- List of items (or None)

## Addresses

| Variable name           | Address    | Network   | Source of truth                 |
| ---                     | ---        | ---       | ---                             |
| `PT_SUSDE_MAR26`        | `0x123...` | `mainnet` | specified in forum post         |
| `PT_SUSDE_MAR26_ORACLE` | `0x456...` | `mainnet` | provided in TG chat with Pendle |

## Notes for Reviewers
- Pay extra attention to: ...
- Extra feedback wanted on: ...

## Conditions for Spell Deployment
- [ ] All spell-specific tests are passing.
- [ ] All E2E tests are passing.
- [ ] All newly deployed addresses have been reviewed and added to the spark-address-registry in a PR that has been merged.
- [ ] All newly deployed addresses have been added to the Immunefi bug bounty program.
- [ ] There is complete test coverage of all changes in the spell, including any relevant edge cases.
- [ ] At least three approvals have been given from reviewers.
- [ ] CODE_RABBIT.md comment has been posted, AI review performed.
- [ ] Octane review performed.

## Conditions for Spell Handoff to Sky
- [ ] All spells payloads have been deployed and verified on Etherscan.
- [ ] All spell-specific tests are passing (including spell bytecode verification).
- [ ] All E2E tests are passing.
- [ ] Spell caster is passing in CI.
- [ ] At least three approvals have been given from reviewers on deployed spell.
- [ ] Comment from at least three reviewers confirming address of mainnet spell payload.

## Conditions for Spell Merge
- [ ] Spell handoff performed to Sky team on Discord.
- [ ] Spell handoff performed to Sky team on Signal.
- [ ] Spell address confirmed to be correct in sky-ecosystem/spells-mainnet repo open PR through comments by at least three reviewers.
- [ ] Sky deployed spell confirmed through a comment in this PR to contain correct Spark payload address by at least three reviewers.
