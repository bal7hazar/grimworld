# SPK-13 — Builds of the same sources that differ (Scarb 2.19.4)

D-154, D-164; brief: [docs/briefs/SPK-13-compiler-determinism.md](../../docs/briefs/SPK-13-compiler-determinism.md).
A diagnostic spike: it changes nothing in the contracts or the library. The draft issue for the
compiler is [issue-draft.md](issue-draft.md) (not filed: the owner's decision).

## The answer

**The toolchain, not our code, our cache or the platform.** The Cairo compiler 2.19.4 (in Scarb
2.19.4) chooses which function of a recursive call cycle gets the `withdraw_gas` check from the
cycle's *representative*: the function with the lowest **salsa intern id**
(`cairo-lang-lowering` 2.19.4, `graph_algorithms/strongly_connected_components.rs`,
`lowered_scc_representative`: `.min_by(|x, y| x.get_internal_id().cmp(&y.get_internal_id()))`).
The feedback set (`graph_algorithms/feedback_set.rs`) is computed from that representative, and
`needs_withdraw_gas` is "the function is in the feedback set". Intern ids are handed out in
first-come order. When rayon has more than one thread, the compiler warms its database up in
parallel (`cairo-lang-compiler` 2.19.4, `src/lib.rs`: `ensure_diagnostics` →
`warmup_diagnostics_blocking`, one task per module, and `get_sierra_program_for_functions` →
`warmup_functions_blocking`), so the order in which the functions of a cycle are interned is a race
between threads. A different winner puts the `withdraw_gas` in another function of the cycle:
another Sierra program, another CASM, another class hash, other gas. With `RAYON_NUM_THREADS=1`
the warm-up is skipped (`should_warmup()` is `rayon::current_num_threads() > 1`) and every build
was the same. `main` of `starkware-libs/cairo` has the same `lowered_scc_representative` (read
2026-10-01). No upstream issue reports it (searched `deterministic`, `reproducible`,
`withdraw_gas`); #10358 is a different reproducibility bug, about absolute paths, already fixed.

**D-164's fact** ("CI always gives 27,101 and the VPS always 27,092") is this race seen through
two machines' usual timing. It is not a property of the environment. On the Mac the same binary,
cache and sources gave both values (and a third) from one clean build to the next. The library's
own record has CI at 27,092 in the run right after one at 27,101
(`docs/reports/LIB-05-M1-T1c-REPORT.md` of the library, *The drift recurred*, item 3). How often
each value appears depends on the thread count and the timing: on the Mac, 4 and 8 threads gave
27,092 in 10 builds out of 10 each, and 12 threads (rayon's default here) gave 27,101 in 7 builds
out of 10. The library's `scripts/lock.sh` sets `RAYON_NUM_THREADS=4`, which would explain the VPS
always giving 27,092, but that is an inference: whether the VPS builds behind `gas/bytecode.size`
ran with 4 threads is not recorded. The VPS run below records it.

**The game's contracts are not affected today.** 23 clean builds of `contracts/` (each Starknet
class and each compiled test file) gave one program per artefact, and CI on x86_64 gives the same
class sizes. Whether the game's code has a recursive cycle across modules was not inspected; the
builds show that no current class is affected. A game contract that later gets such a cycle (one
that calls the map generator, whose `Digger` has one) would be exposed.

## Facts, method, table

Method (`builds.sh`, the full table is [builds-mac.txt](builds-mac.txt)): every build starts
from `scarb clean`. For each Starknet class and each compiled Sierra program (the compiled test
files included), it records the file's sha256 and the sha256 of the program **as text**
(`sierra-dump`: the program printed by the compiler's own crates at 2.19.4, with debug names;
types and libfuncs without one are named after their long ids). It also records the Sierra size
(felts of a class, statements of a program), the number of `withdraw_gas` statements, the CASM
felts and sha256, and the class hash (`starkli class-hash`; `class_hash.py` is its pure-Python
fallback, checked equal to starkli on four classes, see the report). Series:

- `clean`: the machine's Scarb cache;
- `fresh-cache`: `SCARB_CACHE` pointed at a new empty folder for every build (registry, git
  checkouts and corelib copy all fetched again);
- `one-thread`: `RAYON_NUM_THREADS=1`;
- `--threads 4` and `--threads 8` for the library's consumer.

The Mac: aarch64-apple-darwin, 12 CPUs, Scarb 2.19.4 (b45b74c03), binary
`~/.asdf/installs/scarb/2.19.4/bin/scarb` with sha256 `e74277a0…7e63be`, no build lock (no
`flock` on macOS). Library `bal7hazar/hexx-cairo` at `310b5f1`; the game's `contracts/` at
`90b4974` (the branch's base, working tree identical).

| Target | Series (threads) | Builds | Artefacts | What varied |
|---|---|--:|--:|---|
| library `consumer`, release | clean (12) | 10 | 9 classes | `HexxGenerators`: 3 programs: 27,101 felts / CASM 49,375 (6 builds), 27,092 / 49,375 (3), 27,101 / 49,427 (1); 3 class hashes. The 8 other classes: 1 each |
| | fresh-cache (12) | 10 | 9 | `HexxGenerators`: 27,092 (5), 27,101 (5) |
| | clean (4) | 10 | 9 | none: 27,092 in all 10 |
| | clean (8) | 10 | 9 | none: 27,092 in all 10 |
| | one-thread | 10 | 9 | none: 27,092 in all 10, one file byte for byte |
| library `consumer`, dev | clean (12) | 10 | 9 | `HexxGenerators`: 27,092 (5), 27,101 (5); same class hashes as release |
| library `hexx`, tests | HEXX_ROWS |
| game `contracts/` (build + test build) | clean (12) | 10 | 51: 10 classes, 33 test classes, 2 Sierra programs, 6 compiled test files | no program varied. The 8 Sierra programs and test files wrote a different file on every build with **one text**: only the numbers of the ids differ |
| | fresh-cache (12) | 10 | 51 | the same |
| | one-thread | 3 | 51 | the same (the id numbers of 6 files still differ, the texts do not) |
| minimal program | clean (12) | 20 | 1 program | 2 programs: 11 and 9 builds |
| | one-thread | 10 | 1 | none, one file byte for byte |

The library's four metrics for the class (`scripts/bytecode_size.py`: Sierra felts, CASM felts,
compact class bytes, compact CASM bytes), computed on the Mac's kept files, match its records
exactly: 27,092 / 49,375 / 1,395,788 / 997,126 is `gas/bytecode.size` (the VPS's builds), and
27,101 / 49,375 / 1,396,211 / 997,304 is `gas/bytecode.builds` (CI's). The third value,
27,101 / 49,427 / 1,396,259 / 998,243, had not been recorded before. The game's CI (pull request
#252, run 36844387465, x86_64) printed the same Sierra and CASM felts as the Mac for all ten game
classes.

What D-154 saw as "four builds, four hashes of the compiled test files" is two effects. A compiled
test file writes the compiler's numeric ids (`sierra-replace-ids` names the ids but keeps the
numbers beside the names, and types and libfuncs carry no names in test files), so its sha256
changes on almost every build even when the program is the same. On top of that, some builds
really do change the program through the race above, and only those change gas.

## The diff

[diffs/](diffs/): `HexxGenerators.diff_sierra.txt` (release), `HexxGenerators-dev.diff_sierra.txt`
(dev, with names), the two unified diffs of the Sierra text, and the minimal program's two
programs and their diff. Read with `diff_sierra.py`:

- **Types, libfuncs and function declarations** (names, signatures, order): equal in all three
  programs. No function is added or removed (no dead-code or inlining difference) and no
  declaration moves.
- **Statements**: one function differs per pair. In the 27,092 program the cycle
  `DiggerInternal::iter → branch::<…> → visit::<…> → iter` (six headings) gets checks in `iter`
  and in the `inward` loop. The 27,101 program also checks in
  `visit::<SouthWestHeading>` (791 → 811 statements: `withdraw_gas` and its branch that calls
  `panic_with_const_felt252::<375233589013918064796019>`, "Out of gas"). The 27,101 / 49,427
  program instead checks in `branch::<SouthWestHeading, SouthEastHeading, EastHeading>`
  (1,016 → 1,035). The feedback set is not minimal: computed from another representative, it
  gains a vertex.
- **CASM**: same length (49,375) with 18,475 felts different for the first pair (the gas costs
  and offsets after the inserted code move); 49,427 felts with 30,992 different for the second.
- **Kind**: neither an inlining decision nor a dead-function elimination. It is a **placement of
  the gas check** decided by an ordering (the lowest intern id), and that ordering comes from a
  parallel race.

## The minimal program

[minimal/](minimal/) (`src/lib.cairo`, 15 lines, no dependency): `ping` in the root module and
`pong` in `mod b`, calling each other. 20 clean builds gave two programs (11 and 9), which differ
only in which of the two carries `withdraw_gas`. With `RAYON_NUM_THREADS=1`, 10 builds out of 10
gave one file. Its test (`tests/test_minimal.cairo`, l2 gas 34,220, budget 35,931) runs in CI;
it lives in `tests/` so that `src/lib.cairo` stays the issue's program line for line.

How it was reached, each step measured on the Mac at 12 threads:

| Step | Program | Builds | Programs seen |
|---|---|--:|--:|
| 1 | two files `a.cairo`/`b.cairo`, `ping`/`pong` with an accumulator | 10 | 2 (9 + 1) |
| 2 | one file, `pong` in an inline `mod b`, no accumulator | 20 | 2 (16 + 4; under the load of another build on the machine) |
| 3 | one file, both in the root module | 20 | 1 |

Step 3 shows where minimisation stops: the two functions must be in different modules, because
the parallel diagnostics warm-up runs one task per module. Step 2 is what was kept.

## The cause, and the hypotheses refuted

**Supported**: a race in the compiler's parallel warm-up decides the salsa intern order. The SCC
representative is chosen by that order, so the feedback set, and with it the `withdraw_gas`
placement, follow the race.

| Hypothesis | Experiment | Result |
|---|---|---|
| The compiler binary differs between machines | One binary (one sha256) on the Mac | both values (and a third) from the same binary. Across machines, the two values are byte-equal in the library's four metrics on arm64 and x86_64 |
| The platform (arm64 against x86_64) | The Mac's kept classes against the library's VPS and CI records, and the game's CI | identical sizes on both platforms. The one-thread VPS run (below) is the byte-level check |
| Our cache (`~/.cache/scarb`, registry and git checkouts, corelib copy) | `fresh-cache` series; `one-thread` with the machine's cache | both values with a new empty cache every build (5 + 5); one value with the old cache and one thread (10/10) |
| Scarb's incremental cache, the target folder | Every build after `scarb clean` | still varies |
| A dependency resolved differently, `Scarb.lock` | `Scarb.lock` hash recorded per target, unchanged across builds | varies with an identical lock |
| The sources' order on disk, the path | Same worktree path for every build | varies at one path, so neither is needed |
| An unordered iteration that varies between runs in one environment | 12-thread series | **yes**: varies run to run on one machine, against D-164's assumption |
| Inlining or optimisation reading the environment | The diff | no inlining difference, only the `withdraw_gas` placement. What the environment changes is the thread count and timing |
| The thread count | 1, 4, 8, 12 threads | 1: always one program; 4 and 8: one value in 10 builds each on the Mac; 12: three values |
| Our code | The minimal program, with neither the game's code nor the library's | varies. Our code only provides a cycle across modules (`Digger`) |

So it is **the toolchain**: a fix belongs in the compiler (the draft issue), not in our code or
our cache.

## The VPS run (slot)

The orchestrator runs, on the VPS, unchanged:

```
spikes/SPK-13/fetch-library.sh
spikes/SPK-13/builds.sh --target consumer --n 10 --out spikes/SPK-13/.work/out-vps
spikes/SPK-13/builds.sh --target consumer --series clean --threads 8 --from 11 --n 10 --out spikes/SPK-13/.work/out-vps
spikes/SPK-13/builds.sh --target minimal --series clean,one-thread --n 10 --out spikes/SPK-13/.work/out-vps
cp spikes/SPK-13/.work/out-vps/builds.txt spikes/SPK-13/builds-vps.txt
```

(builds go through `scripts/lock.sh`, which sets `RAYON_NUM_THREADS=4` unless it is given;
`sierra-dump` is built once with `cargo build --release --manifest-path
spikes/SPK-13/sierra-dump/Cargo.toml`; without starkli the class hashes come from
`class_hash.py`.) What it must show to close the platform question byte for byte:

1. the `one-thread` `HexxGenerators` and the minimal program's `one-thread` program have the
   **same class hash / text sha256 as the Mac's** (`0x018c238f1c99…`, text `0945b06edbcd…`;
   minimal text `aaaa1965d1b6…`). Equal: the platform plays no part. Different: a platform
   difference on top of the race, to add to the issue;
2. the default series (4 threads through the lock) gives 27,092 every time, matching the library's
   VPS record, and `--threads 8` shows whether more threads bring 27,101 on that machine.

builds-vps.txt: *(left for the orchestrator)*.

CI's figures are the third environment: the library's CI recorded both 27,092 and 27,101, and
the game's CI matches the Mac on all ten game classes (pull request #252).

## What lifts D-164's exception, and what the game does meanwhile

**D-164's exception rests on a wrong premise.** It accepts "two observed values, any third fails",
but the Mac produced a third value in 10 builds (27,101 / 49,427). The values are not "one per
environment": they are the possible placements of a gas check in a cycle, and the number of
placements is not bounded by two. What would lift it:

- **now**: build the library's class-size gate (`scripts/bytecode_size.py`) and gas snapshots with
  `RAYON_NUM_THREADS=1`. Every one-thread build gave one value (27,092, the committed snapshot),
  so the snapshot can go back to one exact value. That is the library orchestrator's call (their
  scripts and CI), and it is decided by the project manager;
- **for good**: the compiler fix (the draft issue). The pin moves when a Scarb release with it
  exists.

**What the game does meanwhile** (proposals, not made here, since `scripts/` and `.github/` are
outside this spike's allowlist):

1. **A deployment build is a one-thread build**: `RAYON_NUM_THREADS=1 scarb build` from a clean
   `target/`. The class hash it declares can then be rebuilt from the commit by anyone.
2. **Record at every deployment** (D-154 §4, extended): the commit, the class hash, the Sierra
   felts and CASM felts, `scarb --version` (Cairo and Sierra versions), and the build's
   `RAYON_NUM_THREADS`. A later check rebuilds with the same settings and compares class hashes.
3. **Gates**: a class-size or gas gate on code that reaches a cross-module cycle (any contract
   that calls the map generator: ENG-05) builds with `RAYON_NUM_THREADS=1`. It stays exact: one
   value, no list of accepted values, no tolerance. CI can export the variable in the job, which
   costs build time, measured here only on the minimal program and the consumer.
4. Today's game contracts are not exposed (above): nothing to change before they call the
   generator.

## Files

| File | |
|---|---|
| `builds.sh` | the reproduction: N clean builds per target and series, the environment, the table |
| `collect.py` | one row per artefact and build (file and text sha256, sizes, `withdraw_gas`, CASM, class hash); the table |
| `class_hash.py` | the class hash in pure Python (Poseidon, Keccak), `--check` against starkli |
| `sierra-dump/` | Rust, the compiler's crates at 2.19.4: a class or a compiled Sierra program as text, with names |
| `diff_sierra.py` | what differs between builds, function by function, and whether the CASM is equal |
| `fetch-library.sh` | the library's clone at `310b5f1` in the ignored `.work/` |
| `minimal/` | the minimal program (a Scarb package; its test runs in CI) |
| `builds-mac.txt` | the table on the Mac |
| `diffs/` | the diffs of the kept Sierra programs |
| `issue-draft.md` | the draft issue for `starkware-libs/cairo`, not filed |
