# Spark Spells

Governance spells for SparkDAO.

## Spell caster

Spells are automatically casted on a shareable forked network on each PR.

Do it manually by following [spell-caster readme](https://github.com/marsfoundation/spell-caster).

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*

forge create RateTargetBaseInterestRateStrategy --broadcast --ledger --mnemonic-derivation-path $LEDGER_PATH --constructor-args $PROVIDER $RATE_SOURCE 800000000000000000000000000 0 7500000000000000000000000 150000000000000000000000000

forge create RateTargetKinkInterestRateStrategy --broadcast --ledger --mnemonic-derivation-path $LEDGER_PATH --constructor-args $PROVIDER $RATE_SOURCE 800000000000000000000000000 0 7500000000000000000000000 150000000000000000000000000

