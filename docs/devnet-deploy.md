# Local-node deployment (OPS-01a)

`scripts/devnet_deploy.py` deploys and seeds the game on a local `starknet-devnet`, for the client's
tests. It is the local-node first part of OPS-01; Sepolia stays with OPS-01.

```
scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build     # once, the classes
scripts/with-node.sh python3 scripts/devnet_deploy.py --out deployment.json
```

Without `--out` the JSON goes to stdout. It refuses a node that is not on 127.0.0.1, never reads a
Sepolia variable, and runs once per node: a node whose first account has already sent a transaction
is refused (exit 1) and nothing is deployed. It writes no private key; the client reads the key from
`devnet_getPredeployedAccounts`.

Order (the lifecycle probe's, `contracts/tools/lifecycle_probe.py`): `Registry`, `set_zone_checks`
(before any record), `TxHashFate`, the libraries, `Hub`, `Instances`, `Hub.set_contracts`, the play
classes (`set_play_class` 0-5), the records of `contracts/seed/` (test region and the fight content),
`register`, one adventurer, `set_build` (empty), `enter` through gate 1. The record builders are shared
with the probe in `contracts/tools/seed_records.py`.

JSON keys: `node_url`, `chain_id`, `commit`, `account` (address only), `classes` (`registry`,
`zone_checks`, `tx_hash_fate`, `hub`, `instances`, `reveal_library`, `hosts_library`, `trap_library`,
`flatten_library`, `play_library`, `tick_library`, `ai_library`, `action_library`, `executor_library`,
`segment_library`), `contracts` (`registry`, `tx_hash_fate`, `hub`, `instances`), `adventurer_id`,
`instance_id`, `slot` (`instance_id >> 32`).

Smoke test: `scripts/with-node.sh python3 scripts/tests/devnet_deploy_smoke.py` (about 2 minutes on
the VPS after the build): deploys, asserts a second run refuses, reads `Instances.instance_state`.
