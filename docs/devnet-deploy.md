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

CI (SMOKE-CI, D-290): the job `devnet-smoke` of `.github/workflows/ci.yml` builds the classes and runs this smoke test alone
(it deploys on its own, so `devnet_deploy.py` is not run before it), on the pinned devnet, and feeds `ci result`. It runs
when `contracts/`, `scripts/devnet_*`, the smoke test, `scripts/with-node.sh` or the root `.tool-versions` change
(`devnet_smoke` of `.github/ci/changes.py`). The smoke test also checks the seed's potion words against `SEED_HEAL` and
`SEED_REGEN` in `contracts/logic/src/types/action.cairo`.

## `--build full` (OPS-01b, SEED-02)

`--build full` (the default is `--build empty`, unchanged) builds the adventurer before its entry, for track CV's chain
play tests. The pack and the gold are funded the way the lifecycle probe does it, with `Hub.report`, the only call that
credits either (the account is made the hub's `instances` for one Open report, then the real one again). The adventurer
then `buy_skill`s the four bar skills (D-275: the trainer is the only way a skill becomes known) and `set_build` puts
them on the bar, slots 0 to 3: the instant attack (skill 1), the activation skill (2), the trap (3) and the REGENERATION
skill (4), all of profession 1, the adventurer's. The belt is the healing potion (item 1) x2 and the REGENERATION potion
(item 23) x1, and the pack holds twice that (`pack`), so the entry debits the belt and one re-entry with it is covered
(`pack_after_entry`, derived by the script and listed in `build.derived`: no view reads a pack yet; the smoke test
checks the pack on chain through `set_build`). The ids come from the seed's tables, never hard-coded.

**The gold step is a devnet harness (D-280).** It credits 260 gold, the four skills at the trainer's prices (50 + 60 + 70
+ 80, D-277), with no margin. It refuses to run unless the URL is `http://127.0.0.1:<port>`, the RPC's chain id
(`starknet_chainId`, read at the step) is `SN_SEPOLIA` and the node answers `devnet_getPredeployedAccounts`; it
restores `Hub.instances` to the `Instances` address in a `finally`, reads the storage slot back and fails the run
unless it is that address. Never use it on Sepolia or later: it is removed when expedition rewards land.

The JSON's `build` key carries `mode`, `bar` (8 skill ids by slot), `belt` and `pack` (`{item, count}`), `gold` (the
harness's credit, all spent), `skills` (`{name: id}` of the bar) and `dropped` (empty); `--help` lists the same ids.
