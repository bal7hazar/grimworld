# SPK-13 — Builds of the same sources that differ (Scarb 2.19.4)

D-154, D-164; brief: [docs/briefs/SPK-13-compiler-determinism.md](../../docs/briefs/SPK-13-compiler-determinism.md).
A diagnostic spike: it changes nothing in the contracts or the library.

## The answer

**The toolchain, not our code, our cache or the platform.** The Cairo compiler 2.19.4 (in Scarb
2.19.4) decides which function of a recursive call cycle receives the `withdraw_gas` check from
the cycle's *representative*, the function with the lowest **salsa intern id**
(`cairo-lang-lowering` 2.19.4, `graph_algorithms/strongly_connected_components.rs`,
`lowered_scc_representative`: `.min_by(|x, y| x.get_internal_id().cmp(&y.get_internal_id()))`;
the feedback set of `graph_algorithms/feedback_set.rs` is computed from it). Intern ids are given
in first-come order, and when rayon has more than one thread the compiler warms its database up
in parallel (`cairo-lang-compiler` 2.19.4, `src/lib.rs`: `ensure_diagnostics` →
`warmup_diagnostics_blocking`, one task per module; `get_sierra_program_for_functions` →
`warmup_functions_blocking`): the order in which the functions of a cycle are interned is then
a race between threads. A different winner puts the `withdraw_gas` in another function of the
cycle: another Sierra program, another CASM, another class hash, other gas. With
`RAYON_NUM_THREADS=1` the warm-up is skipped (`should_warmup()`) and every build is the same.
`main` of `starkware-libs/cairo` still has the same `lowered_scc_representative` (read
2026-10-01); no issue upstream reports it (searched: `deterministic`, `reproducible`,
`withdraw_gas`; #10358 is another reproducibility bug, about absolute paths, fixed).

D-164's fact ("CI always 27,101, the VPS always 27,092") is the same race seen through two
machines' typical timings: the library's VPS builds go through its `scripts/lock.sh`, which sets
`RAYON_NUM_THREADS=4`; on the Mac 4 threads gave 27,092 in 6 builds out of 6, 12 threads gave
27,101 in 5 out of 6. CI is not "always" 27,101 either: the library's own report records a CI run
at 27,092 right after one at 27,101 (LIB-05-M1-T1c-REPORT, *The drift recurred*, item 3).

## Facts, method, table

FACTS_AND_TABLE

## The diff

DIFF_READING

## The minimal program

MINIMAL

## The cause, and the hypotheses refuted

CAUSE

## The VPS run (slot)

VPS_SLOT

## What lifts D-164's exception, and what the game does meanwhile

MEANWHILE

## Files

| File | |
|---|---|
| `builds.sh` | the reproduction: N clean builds per target and series, the environment, the table |
| `collect.py` | one row per artefact and build; the table of `builds-<machine>.txt` |
| `class_hash.py` | the class hash in pure Python (Poseidon, Keccak), checked against `starkli` |
| `sierra-dump/` | Rust, the compiler's own crates at 2.19.4: a class or a compiled test file as Sierra text, with names |
| `diff_sierra.py` | what differs between builds, function by function; CASM equal or not |
| `fetch-library.sh` | the library's clone at `310b5f1`, in the ignored `.work/` |
| `minimal/` | the minimal program (a Scarb package; its test runs in CI) |
| `builds-mac.txt` | the table on the Mac |
| `diffs/` | the diffs of the kept Sierra programs |
| `issue-draft.md` | the draft issue for `starkware-libs/cairo`, not filed |
