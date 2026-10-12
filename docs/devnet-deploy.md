# Local-node deployment (OPS-01a)

`scripts/devnet_deploy.py` deploys and seeds the game on a local `starknet-devnet`, for the client's
tests. It is the local-node first part of OPS-01; Sepolia stays with OPS-01.

```
scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build     # once, the classes
scripts/with-node.sh python3 scripts/devnet_deploy.py --out deployment.json
```

Without `--out` the JSON goes to stdout. It refuses a node that is not on 127.0.0.1, never reads a
Sepolia variable, and runs once per node: a node whose first account has already sent a transaction
is refused (exit 1) and nothing is deployed. The node must be a devnet whose first predeployed account is the
`NODE_ACCOUNT_ADDRESS`, and the URL exactly `http://127.0.0.1:<port>`. The private key is written only to
`sncast`'s throwaway accounts file under the gitignored `.with-node/` log folder, never printed or put in
the JSON; the client reads it from `devnet_getPredeployedAccounts`. Never print, cat or commit the node's
`.with-node/node.log`: it begins with the predeployed accounts' private keys.

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

## `--build full` (OPS-01b)

`--build full` (the default is `--build empty`, unchanged) builds the adventurer before its entry, for track CV's chain
play tests. The pack is funded the way the lifecycle probe does it, with `Hub.report`, the only call that credits a
pack (the account is made the hub's `instances` for one Open report, then the real one again). The belt is the seed's
healing potion (item 1) x2 and the pack holds twice that (`pack`), so the entry debits the belt and one re-entry with it
is covered (`pack_after_entry`). The bar stays empty, and so do the activation, trap and REGENERATION skills and the
REGENERATION potion: the seed has one skill (id 1, an instant attack) and only healing potions, and nothing on chain
makes a skill known (`Hub.known_skills` is never written, `set_build` refuses an unknown skill, devnet has no
set-storage), so those are named under `build.dropped` and `build.skills_wanted`. The JSON's `build` key carries
`mode`, `bar` (8 skill ids by slot), `belt` and `pack` (`{item, count}`) and `dropped`; `--help` lists the same ids.
The seed is not changed.
