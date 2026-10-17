# Agents' notes

- The clone's hooks (`core.hooksPath .githooks`) are set by the project's coordinator with clone-repair; never run `git config`.
- Before every push, run `scripts/prepush.sh`. It decides from your diff which of CI's checks to run (format,
  script self-tests, the build of the Cairo packages you touched, the generated artefacts, the client) and prints
  each step's time. The pre-push hook runs it for you once the hooks are enabled.
- On the VPS the pre-push waits for the machine's build lock like any other Cairo build: every build goes
  through `scripts/lock.sh --heavy scarb build` (the `scarb` shim serialises builds: concurrent ones were
  OOM-killed), run from each package's own folder. It builds only the packages you touched and skips the
  compile when no Cairo source, Scarb manifest or lock, or `.tool-versions` changed. Never work around the lock.
- On the VPS it waits at most 15 s per lock, once per run (`PREPUSH_LOCK_WAIT`, through `scripts/lock.sh --wait`, never
  around it). Once a lock is found busy, every later locked step is skipped at once with one line, and CI runs them;
  the Cairo compile and the checks that build are skipped and CI compiles.
  fmt, the scripts' tests and any other failure still fail the push. Where there is no `flock` (the Mac has no build
  lock) the full check runs, builds included.
- The hook checks HEAD and the working tree, not the refs being pushed.
- Never push red: fix what it reports first. CI stays the gate; this is the same checks, earlier.
- `scripts/prepush.sh --all` runs every check whatever the diff: use it when you change the toolchain pins, a
  workflow or a script that the checks share.
- On the Mac, scripts/lock.sh runs the command without a lock: the one-build rule is the VPS's, and the Mac's shims cap memory.
- Heavy builds and tests go through `scripts/lock.sh`; the rules of the repository are in `docs/briefs/COMMON.md`
  and `OPERATIONS.md`.

## How tests are scoped

A thread runs locally only the tests of the parts it touched, never the whole suite at every step. The whole
suite is CI's, on the PR, gated by changed paths (`.github/ci/changes.py`, FND-18): a documents-only change runs
no test. `scripts/prepush.sh` is already scoped to the branch's own changes against origin/main (FND-21);
`--all` runs everything. The pre-push hook stays minimal (2026-10-02 rule) and is not a substitute for the scoped
tests. On the VPS, Cairo and pnpm runs go through `scripts/lock.sh` (one heavy run at a time, 15 s wait in the pre-push).

Exceptions, both on purpose: the gas check (`scripts/gas_budgets.py --check`, and the regeneration of `GAS.md`
and `docs/BUDGETS.md`) runs a whole package's suite with `--max-threads 2` (FND-20), so a Cairo change that moves
gas runs that package's suite whole once before the push; and `contracts/logic/vectors/check.py` runs on any
vector or logic change (the client mirror reads those tables).

| Part | Local test command | Known memory peak (source) |
|---|---|---|
| `contracts/logic`, `persistent`, `ephemeral` (Scarb workspace) | `cd contracts && snforge test -p grimworld_logic --max-threads 2` (or `grimworld_persistent`, `grimworld_ephemeral`; a filter goes last). The heavy vector and shape tests are split (FND-23: `types::window::tests::test_shapes_every_centre_0` to `_23`, `types::window::tests::test_vectors_0` to `_4`, `types::hit::tests::test_vectors_0` to `_4`): run them with `snforge test <filter>`, caps in the next column | Whole workspace, 2 threads: 4.88 GB VmPeak, capped, so `prlimit --as=8589934592` (8 GiB); 8 threads: 8.29 GB VmPeak, fails: Mac (`docs/reports/FND-20-tests-under-8gb.md`). One package alone: unknown, **measure first†**. FND-23, VPS, `--max-threads 2`, `/usr/bin/time -v` (cap = 1.5 × peak, rounded up, floor 8 GiB; the cap rule now sizes from VmPeak): `test_shapes_every_centre_0` before the split (one 40-centre part) 4.69 GB RSS, cap `--as=8589934592` (8 GiB); after: one 10-centre part 2.80 GB RSS, cap `--as=8589934592` (8 GiB, the floor); all 24 shape parts 4.79 GB RSS, cap 8 GiB; the window vector parts 2.78 GB RSS, cap 8 GiB; the hit vector parts 2.89 GB RSS, cap 8 GiB. A cold filtered run also compiles the package: for `grimworld_logic` it no longer fits in 8 GiB (on ENG-R1c-2 PR 8's branch one aborted at 5.71 GB RSS under 8 GiB), so it takes the 12 GiB cap below; `persistent` and `ephemeral` compile in about 4.6 GB: cap them at 8 GiB. `snforge test -p grimworld_logic --max-threads 2`, a filtered logic compile or test run, and `contracts/logic/vectors/check.py`: cap `prlimit --as=12884901888` (12 GiB), D-306 after ENG-R1c-2 PR 8 (2026-10-16; 11 GiB, `--as=11811160064`, on 2026-10-15). Measured on the VPS, one run each, through the shim, `/usr/bin/time -v`, VmPeak sampled every 2 s from `/proc/<pid>/status` (so a lower bound): main de7571c (passed, 1011 tests): maximum RSS 6.70 GiB (7,020,844 kB), VmPeak at least 9.56 GiB (10,028,748 kB), 11 GiB cap; ENG-R1c-2 PR 8's branch, 1f5632c, a cold build with 194 tests moved into the crate: RSS 7.08 GiB (7,420,384 kB), VmPeak at least 10.50 GiB (11,013,880 kB), passed under 11 GiB at 95.5 % of the cap; ENG-R1c-2 PR 9's tree, 7b731c0, a warm run: RSS 4.21 GiB (4,411,612 kB), VmPeak at least 7.84 GiB (8,222,684 kB), passed under 12 GiB. On the Mac at de7571c, uncapped: maximum RSS 6.93 GiB, peak footprint 4.42 GiB. D-306 sets this cap from RSS (1.5 × 6.93 GiB, rounded up), **as an exception to D-251's 1.5 × VmPeak**; the PR 8 measure raised it to 12 GiB, the maximum. 12 GiB is the ceiling on the VPS: if a logic run aborts under the 12 GiB `--as` or under the `snforge` shim's 8 GiB cgroup limit on resident memory (`MemoryMax=8G`), logic tests leave the VPS and run in CI |
| `contracts/` gas, generated files | `python3 scripts/gas_budgets.py --check`; `python3 contracts/tools/exp2_table.py --check`; `python3 contracts/logic/vectors/check.py` | 4.88 GB VmPeak, cap `--as=8589934592` (8 GiB); none recorded; 4.80 GB since FND-23 (CBT-05d; 4.03 GB VmPeak before), cap `--as=8589934592` (8 GiB) (same report for the first two) |
| `indexer/emitter` (Cairo 2.19) | `cd indexer/emitter && snforge test --max-threads 2` | unknown, **measure first†** |
| `client/sim` | `pnpm --filter @grimworld/sim test` | 701 MB (CV t-0222, CLI-02g-F, VPS, `/usr/bin/time -v`, under a 1024 MB heap: 701,416 KB maximum RSS; the mutation check's 692 mutants, 156 of them the tick's, run in at most four worker threads of the test's process, from memory; 591 MB at t-0207 with 536 mutants, 490 MB at t-0201 with 383, 2435 MB before FND-MUT), heap cap `--max-old-space-size=1280` (1.5 × 701, rounded up to a multiple of 256); 98 s wall (41 s at t-0207: each mutant now replays `tick.jsonl` too) |
| `client/app` | `pnpm --filter @grimworld/app test`, plus `lint` and `typecheck`. The preview's node test (CLI-10b), only when the preview, the mirror or the game's contracts change, after the classes are built (`scripts/lock.sh --heavy scarb --manifest-path contracts/Scarb.toml build` under `prlimit --as=8589934592`): `scripts/with-node.sh bash -c 'python3 scripts/devnet_deploy.py --out "$PWD/.with-node/deployment.json" && GRIMWORLD_DEPLOYMENT="$PWD/.with-node/deployment.json" pnpm --filter @grimworld/app test:node:preview'` | 487 MB maximum RSS (CV t-0195, VPS, `/usr/bin/time -v`, under a 700 MB heap; 473 and 467 MB in earlier runs, 466 MB at t-0182), heap cap `--max-old-space-size=768` (1.5 × 487, rounded up to a multiple of 256); 28 s (20 s in an earlier run, 24 s at t-0182). Node test: 235 MB maximum RSS (CV t-0195, VPS, `/usr/bin/time -v` around the pnpm command, under a 1536 MB heap; 232 MB under a 512 MB heap in a later run, 230 MB at t-0187), heap cap `--max-old-space-size=512`; 10.1 s after a deployment (18.8 s in a later run) (7.3 s at t-0187, after a deployment of 35.5 s) (classes built; 251 MB RSS); the class build 5.43 GB VmPeak, 2.40 GB RSS (sampled every 2 s), cap 8 GiB |
| `client/app` `verify-*.mjs` | by hand only, they need the built atlas: only the screens the lot touches (`pnpm --filter @grimworld/app verify:<name>`, or `node verify-<name>.mjs` from `client/app` for the editor ones; one browser at a time; on the VPS, the site's atlas, read-only) | none recorded |
| `indexer` | `pnpm --filter @grimworld/indexer test` (`test:node` needs devnet: CI) | none recorded; Node: heap cap at 1.5 × peak once measured |
| `services/funder` | `pnpm --filter @grimworld/funder test` | none recorded; Node: heap cap at 1.5 × peak once measured |
| `tools/art` | `tools/art/.venv/bin/python -m unittest discover -s tools/art/tests` (needs NumPy; no CI job runs it yet, only the pre-push hook where a venv with NumPy exists; a CI job is being added by track CV); atlas check `pnpm --dir tools/art/check check` | none recorded |
| `scripts/`, `.github/ci` | `scripts/prepush.sh --self-test`; `python3 scripts/gas_budgets.py --self-test`; `python3 .github/ci/changes.py --self-test`; Mac: `scripts/mac/test.sh` | none recorded |
| `spikes/*` (each its own Scarb or pnpm package) | from its folder: `snforge test` or `pnpm test`, only if you touched it | unknown, **measure first†** |
| `tools/site` | no tests | n/a |

† Memory rule (D-251 (2026-10-10), the organisation's rule). The address-space cap `prlimit --as` stops a runaway, it
does not measure. The peak that sizes a cap is the run's **VmPeak** (address space): `grep VmPeak /proc/<pid>/status`
during the run; it is not "Maximum resident set size" (RSS), which is smaller (a real 7.3 GB peak aborted under 8 GiB). `grimworld_logic` alone is the exception set by D-306 (see its row above).
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
