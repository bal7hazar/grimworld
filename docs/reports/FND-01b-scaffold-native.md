# [Sonnet 5] FND-01b — Scaffold as native contracts

## Summary
The FND-01 scaffold is native Starknet (ADR-0007). `contracts/` is a Scarb workspace on Cairo 2.19 of three packages: `grimworld_logic` (pure logic, no storage, depends on `origami_hexmap` 1.8.0), `grimworld_persistent` (contract `Persistent`) and `grimworld_ephemeral` (contract `Ephemeral`). Each contract has the ADR-0007 layering as modules (`systems`, `components`, `store`, `models`, `types`, `elements`, `helpers`, `registries`), one-line doc comments, no game code, and a placeholder `version() -> felt252` view with no storage and no access control. snforge tests declare and deploy both contracts and call the view; another calls `origami_hexmap`'s `distance`. `client/`: dojo.js removed, starknet.js 10.8.0 (SPK-5b's version), `createProvider` plus a test that builds a provider without network; `@grimworld/sim` untouched.

The model that ran is Sonnet 5, as the brief names.

Pull request: https://github.com/bal7hazar/grimworld/pull/27. No CI check ran on it (`gh pr checks 27` reported "no checks": the only workflow is `tooling.yml`; CI for contracts and client is FND-02), so the local runs below are the only gate.

## Files changed
- `contracts/Scarb.toml`: virtual workspace manifest (members, shared package fields, shared dependencies, `[cairo] sierra-replace-ids`, `allow-prebuilt-plugins`); `dojo`, `dojo_snf_test` and the world external contract removed.
- `contracts/Scarb.lock`: regenerated.
- `contracts/dojo_dev.toml`, `contracts/src/**`, `contracts/tests/test_world.cairo`: removed.
- `contracts/logic/`: `Scarb.toml`, `src/lib.cairo`, `src/tick.cairo` (empty, doc only), `tests/test_hexmap.cairo`.
- `contracts/persistent/`, `contracts/ephemeral/`: `Scarb.toml`, `src/lib.cairo`, `src/{systems,components,store,models,types,elements,helpers,registries}.cairo`, `src/systems/{persistent,ephemeral}.cairo` (interface, contract, `VERSION`), `tests/test_{persistent,ephemeral}.cairo`.
- `contracts/README.md`: layout, two-contract rule (ADR-0007, ADR-0001), build and test commands.
- `client/app/package.json`: `@dojoengine/*` removed, starknet.js 10.0.2 → 10.8.0.
- `client/app/src/chain.ts`, `chain.test.ts`: `createProvider(nodeUrl)` and its test.
- `client/README.md`: updated (and reformatted by Prettier).
- `pnpm-lock.yaml`: regenerated (no dojo, msgpackr-extract or protobufjs left).
- `pnpm-workspace.yaml`: `allowBuilds` block removed (it only existed for two dojo.js transitive packages, none in the lockfile now).

## Commands run
```
scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build
  Compiling grimworld_ephemeral / grimworld_logic / grimworld_persistent … Finished `dev` profile
cd contracts && snforge test
  [PASS] grimworld_ephemeral_integrationtest::test_ephemeral::test_ephemeral_deploys_and_answers_version (l1_gas: ~0, l1_data_gas: ~96, l2_gas: ~277140)
  [PASS] grimworld_logic_integrationtest::test_hexmap::test_hexmap_distance (l1_gas: ~0, l1_data_gas: ~0, l2_gas: ~13720)
  [PASS] grimworld_persistent_integrationtest::test_persistent::test_persistent_deploys_and_answers_version (l1_gas: ~0, l1_data_gas: ~96, l2_gas: ~277140)
  Tests summary: 3 passed, 0 failed
  (with a budget of 1 each test failed with "Test cost exceeded the available gas": budgets are enforced)
scripts/lock.sh pnpm install --frozen-lockfile   Lockfile is up to date, Done
pnpm -r test        sim 2 passed; app 2 files, 2 tests passed
pnpm -r lint        Done (both)
pnpm -r typecheck   Done (both)
scripts/lock.sh pnpm build   vite build, built in 746ms
pnpm exec prettier --check client   clean after --write on client/README.md
grep -ril dojo contracts client   contracts/README.md, client/README.md
```
`scripts/setup-toolchain.sh` was not run (the tools were already at the pinned versions: the build and tests above used Scarb 2.19.4 and snforge 0.61).

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| `test_persistent_deploys_and_answers_version` (l2 gas) | — | 277 140 | 290 997 | declare, deploy and one call; l1_data_gas ~96 |
| `test_ephemeral_deploys_and_answers_version` (l2 gas) | — | 277 140 | 290 997 | same |
| `test_hexmap_distance` (l2 gas) | — | 13 720 | 14 406 | five `Geometry::distance` calls |
| `test_world_spawns_with_both_domains` (Dojo, FND-01) | 1 763 835 | removed | — | replaced by the two deploy tests: 277 140 for a contract deployed, against 1.76 M for a Dojo world spawned (different things measured, not a gas comparison: that is SPK-2) |

## Acceptance criteria
- AC-1 ✔ `grep -ril dojo contracts client` lists only `contracts/README.md` and `client/README.md`, the sentences saying there is no Dojo and why.
- AC-2 ✔ `scripts/lock.sh scarb --manifest-path contracts/Scarb.toml build` and `snforge test` pass; both deploy tests declare and deploy their class; all three tests carry `#[available_gas(l2_gas: N)]`, `N = ceil(1.05 × measured)`.
- AC-3 ✔ `test_hexmap_distance` passes on Cairo 2.19 with `origami_hexmap = "1.8.0"` from the registry.
- AC-4 ✔ two contract packages and `grimworld_logic` with the layering. There is no storage struct in either contract (`Storage {}` is empty), so none mixes the two domains; neither package depends on the other.
- AC-5 ✔ commands above; `client/sim/package.json` has only vitest, and no import of starknet, PixiJS or React in `client/sim/src`.

## Deviations from the brief
- **A workspace of three packages rather than one package**, which the brief allows if justified: neither contract package can import the other's models (no dependency between them), each class is built and sized on its own (ADR-0007 *Class size*), and the pure logic is a package of its own that tests and the client can use without a contract. Reasons are also in `contracts/README.md`.
- **Contract names** are `Persistent` and `Ephemeral` (packages `grimworld_persistent`, `grimworld_ephemeral`), as the brief suggests; not refined.
- **The `origami_hexmap` dependency is in `grimworld_logic`, not in a contract package**, since the tick's rules (movement, ranges) will use it there; it is part of the game's workspace and compiler. Neither contract depends on `grimworld_logic` yet (an unused dependency would prove nothing).
- **`pnpm-workspace.yaml`'s `allowBuilds` removed** (in the allowlist): it only covered dojo.js's transitive packages.
- `client/app/src/chain.ts` exists although the brief says "a type import or a trivial provider construction in a test": it holds the one-line construction so the test has something to import; nothing else uses it.

## Escalations
- **CI**: no workflow builds or tests `contracts/` or `client/` on a pull request (FND-02), so this PR has no green check to wait for. The orchestrator should decide how to gate its merge.
- The gas figure of the deploy tests includes the `declare` and the deploy inside the test, as SPK-5b's did; an entrypoint's own cost is not separated from it yet (ENG-01's benchmarks will need the difference, for example a baseline deploy subtracted).

## Open questions
- SPK-5b's open question (does `sncast declare`'s `release` profile carry the `[cairo]` settings of `dev`?) is still open: with a workspace, `sierra-replace-ids` sits in the workspace manifest's `[cairo]` table (a `[cairo]` in a member package is ignored with a warning). OPS-01 should check it when it writes the declare script.
- Should ENG-01 keep three packages, or merge `logic` into a library module of each contract if the SPK-4 client mirror is not compiled from Cairo?
