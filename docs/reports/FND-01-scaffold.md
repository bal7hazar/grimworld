# [Sonnet 5] FND-01 — Repository scaffold

## Summary
The repository now has the empty structure later tasks write into: the Dojo package `contracts/` (`grimworld`, two namespaces, layering per CONTEXT §4) and the pnpm workspace `client/` (`@grimworld/sim` apart from `@grimworld/app`). Both build and test green on the SPK-5 pins. **One part is not done: `origami_hexmap` 1.8.0 does not resolve or build on Cairo 2.13 (AC-2, escalated below).** The model is Sonnet 5, as the brief's title says. Pull request: https://github.com/bal7hazar/grimworld/pull/18 (no CI exists yet: FND-02, so `gh pr checks` reports none).

## Files changed
- `contracts/Scarb.toml`, `contracts/Scarb.lock`, `contracts/dojo_dev.toml`: package manifest as `spikes/SPK-5/`, namespace `grimworld` by default.
- `contracts/.gitignore`: `.snfoundry_cache/`.
- `contracts/src/lib.cairo` and one module file per layer (`systems`, `components`, `store`, `models`, `types`, `elements`, `helpers`, `registries`), plus `systems/{persistent,ephemeral}.cairo` and `models/{persistent,ephemeral}.cairo`; each has a doc comment and no code.
- `contracts/tests/test_world.cairo`: placeholder test spawning a world with both namespaces.
- `contracts/README.md`, `client/README.md`: layout, the two-domain rule (link to ADR-0001), build and test through `scripts/lock.sh`.
- `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`: root workspace, `packageManager` pnpm 12.5.1, `allowBuilds` false for the two optional build scripts (as SPK-5).
- `client/tsconfig.base.json`, `client/eslint.config.js`, `client/.prettierrc.json`: shared config.
- `client/sim/{package.json,tsconfig.json,src/index.ts,src/index.test.ts}`: placeholder `clamp` and its test.
- `client/app/{package.json,tsconfig.json,vite.config.ts,index.html,src/main.tsx,src/App.tsx,src/frame.ts,src/frame.test.ts}`: page rendering one static PixiJS frame on demand.
- `.gitignore`: `contracts/target/`, `node_modules/`, `client/*/dist/` (`.with-katana/` was already there).

## Commands run
- `scripts/lock.sh sozo build --manifest-path contracts/Scarb.toml` → `Finished dev profile target(s) in 17 seconds` (with the hexmap dependency: version solving failed, see Escalations).
- `scripts/lock.sh sozo test --manifest-path contracts/Scarb.toml` → `[PASS] grimworld_integrationtest::test_world::test_world_spawns_with_both_domains (l1_gas: ~0, l1_data_gas: ~1920, l2_gas: ~1763835)`, `Tests: 1 passed`. First run with `l2_gas: 1` failed with `Test cost exceeded the available gas` as expected.
- `scripts/lock.sh pnpm install --frozen-lockfile` → `Lockfile is up to date`, `Done`. The first install stopped on `ERR_PNPM_IGNORED_BUILDS` (msgpackr-extract, protobufjs) until `allowBuilds: false` was set.
- `pnpm -r test` → sim 2 passed, app 1 passed. `pnpm -r lint` and `pnpm -r typecheck` → both packages clean. `pnpm exec prettier --check client package.json pnpm-workspace.yaml` → clean.
- `scripts/lock.sh pnpm build` → vite `built in 383ms`, 725 modules.
- `pnpm --filter @grimworld/sim why pixi.js` → no output, exit 0.
- `git ls-files | grep -E '(^|/)(target|node_modules|dist)/'` → nothing.

## Cost
| Entrypoint or algorithm | Before | After | Budget | Note |
|---|---|---|---|---|
| `test_world_spawns_with_both_domains` (l2_gas) | — | 1763835 | 1852027 = ceil(1.05 × 1763835) | world spawn with two empty namespaces; l1_data_gas ~1920 |
| `sozo build` (contracts) | — | 16.9 s wall (`time`), 17.3 s user | — | warm caches; peak memory **not measured**: `/usr/bin/time` is refused by the profile |
| `pnpm build` (client) | — | vite 383 ms; 85.7 s wall through the lock, of which nearly all waiting for the lock (user 4.5 s) | — | peak memory not measured (same reason) |

## Acceptance criteria
- AC-1 met: `sozo build` and `sozo test` pass, the placeholder test has a budget.
- **AC-2 not met**: escalated, see below.
- AC-3 met: install with frozen lockfile, `pnpm -r test`, `lint`, `typecheck` pass (`scripts/lock.sh pnpm install|build` through the lock; test, lint and typecheck ran as `pnpm -r …` directly, since the lock only takes minutes-long jobs and these are seconds).
- AC-4 met: `why pixi.js` finds nothing in sim; `client/app` has no ticker or animation frame call (`autoStart: false`, one `app.render()`; the only occurrence of "ticker" in `src/` is a comment).
- AC-5 met with a caveat (first deviation below): the layer modules and both namespaces exist; no build output or image tracked.

## Deviations from the brief
- `models/persistent/`, `models/ephemeral/`, `systems/persistent/`, `systems/ephemeral/` are **module files** (`models/persistent.cairo`, …), not folders: Cairo has no `mod.cairo`, and git does not track empty folders. The folders appear with the first file placed in them. Stated in `contracts/README.md`.
- The two namespaces are declared in `contracts/dojo_dev.toml` (default `grimworld`) and exercised by the test (`NamespaceDef` for each); `grimworld_instance` has no resource yet to carry it into a manifest.
- TypeScript is pinned to 6.0.3, not the newest 7.0.2: `typescript-eslint` 8.70.1 declares `typescript >=4.8.4 <6.1.0`.
- ESLint and Prettier config live in `client/` (not the root), because the allowlist does not include root config files.
- `.npmrc` (`save-exact`) was not written: the harness refused the file as sensitive. Versions are exact in every `package.json` anyway.
- Dev-dependency list of the client is larger than "Vite, React, PixiJS": `@dojoengine/sdk`, `@dojoengine/grpc` and `starknet` 10.0.2 are declared as in the SPK-5 spike (`starknet` is a peer of the SDK).

## Escalations
**`origami_hexmap` 1.8.0 (AC-2, finding for track LIB / R-18).** Nothing was worked around.
1. Added next to `dojo 1.8.0` and `dojo_snf_test 1.8.0`: `scarb` version solving fails: *"origami_hexmap 1.8.0 depends on snforge_std >=0.61.0, <0.62.0 … grimworld 0.1.0 depends on snforge_std >=0.51.0, <0.52.0"*. The published package declares `snforge_std` as a regular dependency at 0.61; `dojo_snf_test 1.8.0` forces 0.51.2.
2. In an isolated scratch package with only `starknet = "2.13"` and `origami_hexmap = "1.8.0"` (deleted afterwards), it resolves but does not compile on Scarb 2.13.1: `error: Item core::internal::bounded_int::BoundedInt is not visible in this context` at `map.cairo:10`, `helpers/bits.cairo:12` and `helpers/rng.cairo:24`.
3. Cause: `/home/claude/git/origami/Scarb.toml` (workspace 1.8.0) targets `starknet ^2.19.4` and `snforge_std 0.61.0`, while SPK-5 fixed the whole game on Cairo 2.13 because Sozo 1.8.7 and `dojo_snf_test 1.8.0` need it.
Consequences: SPK-7 cannot start on `origami_hexmap` 1.8.0 in this package as its brief plans; SPK-7 depends on FND-01 proving it builds. Options for the orchestrator (not chosen by me): a `hexmap` release built for Cairo 2.13, the toolchain moving up once Dojo does, or the rooms-and-corridors fallback of ORCH-game.

No shared file needs a change.

## Open questions
- Whether the PR should wait for a `.npmrc` with `save-exact=true` (needs the orchestrator to write it).
