# Agents' notes

- Once per clone, enable the repository's hooks: `git config core.hooksPath .githooks`.
- Before every push, run `scripts/prepush.sh`. It decides from your diff which of CI's checks to run (format,
  script self-tests, the build of the Cairo packages you touched, the generated artefacts, the client) and prints
  each step's time. The pre-push hook runs it for you once the hooks are enabled.
- On the VPS the pre-push waits for the machine's build lock like any other Cairo build: every build goes
  through `scripts/lock.sh --heavy scarb build` (the `scarb` shim serialises builds: concurrent ones were
  OOM-killed), run from each package's own folder. It builds only the packages you touched and skips the
  compile when no Cairo source, Scarb manifest or lock, or `.tool-versions` changed. Never work around the lock.
- On the VPS it waits at most 90 s for that lock (`PREPUSH_LOCK_WAIT`, through `scripts/lock.sh --wait`, never around
  it); if the lock stays busy it skips the Cairo compile and the checks that build, prints one line, and CI compiles.
  fmt, the scripts' tests and any other failure still fail the push. Where there is no `flock` (the Mac has no build
  lock) the full check runs, builds included.
- The hook checks HEAD and the working tree, not the refs being pushed.
- Never push red: fix what it reports first. CI stays the gate; this is the same checks, earlier.
- `scripts/prepush.sh --all` runs every check whatever the diff: use it when you change the toolchain pins, a
  workflow or a script that the checks share.
- Heavy builds and tests go through `scripts/lock.sh`; the rules of the repository are in `docs/briefs/COMMON.md`
  and `OPERATIONS.md`.

## How tests are scoped

A thread runs locally only the tests of the parts it touched, never the whole suite at every step. The whole
suite is CI's, on the PR, gated by changed paths (`.github/ci/changes.py`, FND-18): a documents-only change runs
no test. `scripts/prepush.sh` is already scoped to the branch's own changes against origin/main (FND-21);
`--all` runs everything. The pre-push hook stays minimal (2026-10-02 rule) and is not a substitute for the scoped
tests. On the VPS, Cairo and pnpm runs go through `scripts/lock.sh` (one heavy run at a time, 90 s wait).

Exceptions, both on purpose: the gas check (`scripts/gas_budgets.py --check`, and the regeneration of `GAS.md`
and `docs/BUDGETS.md`) runs a whole package's suite with `--max-threads 2` (FND-20), so a Cairo change that moves
gas runs that package's suite whole once before the push; and `contracts/logic/vectors/check.py` runs on any
vector or logic change (the client mirror reads those tables).

| Part | Local test command | Known memory peak (source) |
|---|---|---|
| `contracts/logic`, `persistent`, `ephemeral` (Scarb workspace) | `cd contracts && snforge test -p grimworld_logic --max-threads 2` (or `grimworld_persistent`, `grimworld_ephemeral`; a filter goes last). The heavy vector and shape tests (window, hit, ENG-02's window tests) are not split yet (FND-23): run those modules with `snforge test <filter>` | Whole workspace, 2 threads: 4.88 GB capped; 8 threads: 8.29 GB, fails (`docs/reports/FND-20-tests-under-8gb.md`). One package alone: unknown, **measure first†** |
| `contracts/` gas, generated files | `python3 scripts/gas_budgets.py --check`; `python3 contracts/tools/exp2_table.py --check`; `python3 contracts/logic/vectors/check.py` | 4.88 GB; none recorded; 4.03 GB (same report) |
| `indexer/emitter` (Cairo 2.19) | `cd indexer/emitter && snforge test --max-threads 2` | unknown, **measure first†** |
| `client/sim` | `pnpm --filter @grimworld/sim test` | none recorded; under a minute (orchestrators) |
| `client/app` | `pnpm --filter @grimworld/app test`, plus `lint` and `typecheck` | none recorded; under a minute (orchestrators) |
| `client/app` `verify-*.mjs` | by hand only, they need the built atlas: only the screens the lot touches (`pnpm --filter @grimworld/app verify:<name>`, or `node verify-<name>.mjs` from `client/app` for the editor ones; one browser at a time; on the VPS, the site's atlas, read-only) | none recorded |
| `indexer` | `pnpm --filter @grimworld/indexer test` (`test:node` needs devnet: CI) | none recorded |
| `services/funder` | `pnpm --filter @grimworld/funder test` | none recorded |
| `tools/art` | `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests` (needs NumPy; no CI job runs it yet, only the pre-push hook where a venv with NumPy exists; a CI job is being added by track CV); atlas check `pnpm --dir tools/art/check check` | none recorded |
| `scripts/`, `.github/ci` | `scripts/prepush.sh --self-test`; `python3 scripts/gas_budgets.py --self-test`; `python3 .github/ci/changes.py --self-test`; Mac: `scripts/mac/test.sh` | none recorded |
| `spikes/*` (each its own Scarb or pnpm package) | from its folder: `snforge test` or `pnpm test`, only if you touched it | unknown, **measure first†** |
| `tools/site` | no tests | n/a |

† Measure first, capped (`prlimit --as=8589934592 -- /usr/bin/time -v …`) or on the Mac; never uncapped on the
VPS. The same for any build that may pass 8 GB.
