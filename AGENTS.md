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
| `contracts/logic`, `persistent`, `ephemeral` (Scarb workspace) | `cd contracts && snforge test -p grimworld_logic --max-threads 2` (or `grimworld_persistent`, `grimworld_ephemeral`; a filter goes last). The heavy vector and shape tests are split (FND-23: `types::window::tests::test_shapes_every_centre_0` to `_23`, `types::window::tests::test_vectors_0` to `_4`, `types::hit::tests::test_vectors_0` to `_4`): run them with `snforge test <filter>`, caps in the next column | Whole workspace, 2 threads: 4.88 GB VmPeak, capped, so `prlimit --as=8589934592` (8 GiB); 8 threads: 8.29 GB VmPeak, fails: Mac (`docs/reports/FND-20-tests-under-8gb.md`). One package alone: unknown, **measure first†**. FND-23, VPS, `--max-threads 2`, `/usr/bin/time -v` (cap = 1.5 × peak, rounded up, floor 8 GiB; the cap rule now sizes from VmPeak): `test_shapes_every_centre_0` before the split (one 40-centre part) 4.69 GB RSS, cap `--as=8589934592` (8 GiB); after: one 10-centre part 2.80 GB RSS, cap `--as=8589934592` (8 GiB, the floor); all 24 shape parts 4.79 GB RSS, cap 8 GiB; the window vector parts 2.78 GB RSS, cap 8 GiB; the hit vector parts 2.89 GB RSS, cap 8 GiB. A cold filtered run also compiles the package (about 4.6 GB): cap it at 8 GiB |
| `contracts/` gas, generated files | `python3 scripts/gas_budgets.py --check`; `python3 contracts/tools/exp2_table.py --check`; `python3 contracts/logic/vectors/check.py` | 4.88 GB VmPeak, cap `--as=8589934592` (8 GiB); none recorded; 4.80 GB since FND-23 (CBT-05d; 4.03 GB VmPeak before), cap `--as=8589934592` (8 GiB) (same report for the first two) |
| `indexer/emitter` (Cairo 2.19) | `cd indexer/emitter && snforge test --max-threads 2` | unknown, **measure first†** |
| `client/sim` | `pnpm --filter @grimworld/sim test` | 500 MB (mutation check, under a 1024 MB heap; CV t-0157), heap cap `--max-old-space-size=768`; under a minute (orchestrators) |
| `client/app` | `pnpm --filter @grimworld/app test`, plus `lint` and `typecheck` | none recorded; Node: heap cap at 1.5 × peak once measured; under a minute (orchestrators) |
| `client/app` `verify-*.mjs` | by hand only, they need the built atlas: only the screens the lot touches (`pnpm --filter @grimworld/app verify:<name>`, or `node verify-<name>.mjs` from `client/app` for the editor ones; one browser at a time; on the VPS, the site's atlas, read-only) | none recorded |
| `indexer` | `pnpm --filter @grimworld/indexer test` (`test:node` needs devnet: CI) | none recorded; Node: heap cap at 1.5 × peak once measured |
| `services/funder` | `pnpm --filter @grimworld/funder test` | none recorded; Node: heap cap at 1.5 × peak once measured |
| `tools/art` | `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests` (needs NumPy; no CI job runs it yet, only the pre-push hook where a venv with NumPy exists; a CI job is being added by track CV); atlas check `pnpm --dir tools/art/check check` | none recorded |
| `scripts/`, `.github/ci` | `scripts/prepush.sh --self-test`; `python3 scripts/gas_budgets.py --self-test`; `python3 .github/ci/changes.py --self-test`; Mac: `scripts/mac/test.sh` | none recorded |
| `spikes/*` (each its own Scarb or pnpm package) | from its folder: `snforge test` or `pnpm test`, only if you touched it | unknown, **measure first†** |
| `tools/site` | no tests | n/a |

† Memory rule (D-251 (2026-10-10), the organisation's rule). The address-space cap `prlimit --as` stops a runaway, it
does not measure. The peak that sizes a cap is the run's **VmPeak** (address space): `grep VmPeak /proc/<pid>/status`
during the run; it is not "Maximum resident set size" (RSS), which is smaller (a real 7.3 GB peak aborted under 8 GiB).
RSS still decides where a run goes: above about 8 GB RSS it runs on the Mac, never on the VPS. Measure every build or
test run first, on the Mac or on the VPS under `prlimit --as=8589934592 -- …` (8 GiB); if that capped run aborts,
measure on the Mac. Never measure an unknown peak on the VPS under a larger cap. A run under about 8 GB RSS may run on
the VPS under `prlimit --as` set to 1.5 × its VmPeak, rounded up, never below 8 GiB (8589934592) and at most 16 GiB (a
cap below 8 GiB made `scarb package -p hexx` abort in zstd, "Allocation error: not enough memory", at 2 GiB for a 0.81 GB
peak; it passed under 8 GiB). A capped run that makes no progress for 15 minutes is stopped by its own pid and moved: to
the Mac, or under a cap from its VmPeak. It is never left holding the heavy lock. Never uncapped on the VPS.

Node/V8 runs (pnpm, node): `prlimit --as` cannot cap them, because V8 reserves a large address space and Node aborts
at about 265 MB resident under `--as=8 GiB`. Cap the heap instead: `NODE_OPTIONS=--max-old-space-size=<MB>` at 1.5 × the
measured peak, with the peak from `/usr/bin/time -v`. Never use `prlimit --as` for a Node run. Cairo runs keep the
address-space cap. On the Mac, measure with `/usr/bin/time -l`, with no cap.
