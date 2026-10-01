# Draft issue for `starkware-libs/cairo`

> Prepared by SPK-13; **not filed**. Filing it is the owner's decision (D-154 §3). Everything
> below the line is the issue's text, written to be pasted as is.

---

## Title

bug: the Sierra program of a recursive call cycle depends on thread scheduling (`withdraw_gas` placement follows salsa intern order)

## Body

### Summary

Compiling the same sources twice with the same compiler binary can give two different Sierra
programs, and so two class hashes for a contract. The programs differ only in **which function of
a call-graph cycle receives the `withdraw_gas` check**. The choice follows the cycle's SCC
representative, picked by the lowest salsa internal id
(`cairo-lang-lowering/src/graph_algorithms/strongly_connected_components.rs`,
`lowered_scc_representative`: `.min_by(|x, y| x.get_internal_id().cmp(&y.get_internal_id()))`).
The feedback set is then computed from that representative
(`graph_algorithms/feedback_set.rs`, `function_with_body_feedback_set_of_representative`).
Intern ids are assigned in first-come order, and with more than one rayon thread the compiler's
parallel warm-up (`cairo-lang-compiler/src/lib.rs`: `ensure_diagnostics` →
`warmup_diagnostics_blocking`, and `get_sierra_program_for_functions` →
`warmup_functions_blocking`) interns the functions of a cycle in whatever order the threads reach
them. With `RAYON_NUM_THREADS=1` the warm-up is skipped (`should_warmup()`) and the output is
stable.

### Versions

- Scarb 2.19.4 (b45b74c03 2026-07-21), Cairo 2.19.4, Sierra 1.9.3
- `lowered_scc_representative` is unchanged on `main` (read 2026-10-01)
- Seen on aarch64-apple-darwin (12 CPUs); the two main values of the larger contract below were
  also produced on x86_64 Linux (GitHub `ubuntu-latest` and a Linux server), with the same sizes

### Minimal program

One package, one file. `Scarb.toml`:

```toml
[package]
name = "spk13_minimal"
version = "0.1.0"
edition = "2024_07"
cairo-version = "2.19"

[cairo]
sierra-replace-ids = true
```

`src/lib.cairo`:

```cairo
pub fn ping(n: u32) -> u32 {
    if n == 0 {
        return 0;
    }
    b::pong(n - 1)
}

pub mod b {
    pub fn pong(n: u32) -> u32 {
        if n == 0 {
            return 1;
        }
        super::ping(n - 1)
    }
}
```

Two mutually recursive functions **in two modules**. With both functions in the root module, 20
clean builds out of 20 gave the same program: the parallel diagnostics warm-up runs one task per
module, so the two functions must be lowered by different tasks for the race to exist.

### Steps to reproduce

On a machine with several cores (rayon's default: one thread per CPU), from the package's folder:

```sh
for i in $(seq 20); do
  scarb clean && scarb build >/dev/null
  shasum -a 256 target/dev/spk13_minimal.sierra.json
done
```

The JSON file differs on every build, partly because it writes the numeric intern id beside each
debug name. To see which builds differ as programs, print each one as Sierra text with its names
(`cairo_lang_sierra::program::VersionedProgram::into_v1()`, `DebugInfo::populate`, `Display`) and
compare which of `ping` and `pong` calls `withdraw_gas`. Then the control:

```sh
for i in $(seq 10); do
  scarb clean && RAYON_NUM_THREADS=1 scarb build >/dev/null
  shasum -a 256 target/dev/spk13_minimal.sierra.json
done
```

### Observed

On Apple silicon (aarch64-apple-darwin, 12 CPUs), Scarb 2.19.4 (Cairo 2.19.4):

| Threads | Builds | Program A: `withdraw_gas` in `ping` | Program B: `withdraw_gas` in `pong` |
|---|--:|--:|--:|
| default (12) | 20 | 9 | 11 |
| default (12), an earlier series under load | 20 | 16 | 4 |
| `RAYON_NUM_THREADS=1` | 10 | 10 (one file, byte for byte) | 0 |

Both programs have the same types, libfuncs and function declarations (90 statements each). In A,
`ping` starts with `withdraw_gas([0], [1]) { fallthrough(...) ... }` and calls the out-of-gas
panic (`panic_with_const_felt252::<375233589013918064796019>`, "Out of gas") and `pong` does not;
in B it is the other way round (`ping` 33 statements, `pong` 43, and the reverse). The order of
the type and libfunc declarations differs with it.

On a larger contract (≈ 98 functions, a few call cycles through loops), the class built by
10 clean builds on 12 threads took **three** values: 27,092 / 27,101 / 27,101 Sierra felts, with
CASM of 49,375 / 49,375 / 49,427 felts and three class hashes. The three programs have identical
type, libfunc and function declarations; each differs from the others only by one extra
`withdraw_gas` (and its out-of-gas branch) in a different function of the same cycle.
`RAYON_NUM_THREADS=1`: 10 builds out of 10 gave the same program.

### Expected

The same sources and compiler give the same Sierra program, whatever the number of threads and
their scheduling: a declared class should be rebuildable from its source.

### Why it matters

- A contract's class hash cannot be reproduced from its tagged source with certainty
  (verification services, audits, deterministic deployment pipelines).
- Gas measured by tests that reach such a cycle moves by a fraction of a percent between builds
  of the same commit, so exact gas snapshots flake.
- Machines differ in how often each value appears (thread count, CPU speed), so a project can see
  "one value in CI, another locally" and suspect its cache or its toolchain.

### Possible fix

Pick the SCC representative by a key that does not depend on interning order, for example the
smallest function by its full path and generic arguments (`full_path` of the concrete function,
or the `ConcreteFunctionWithBodyLongId` compared structurally), and make sure the feedback-set
DFS visits neighbours in a stable order. Any other `get_internal_id()`-based ordering that reaches
the output would need the same treatment.

### Workaround

Build with `RAYON_NUM_THREADS=1` (slower; no parallel warm-up).

### Related

- #10358 (absolute paths in closure type names broke deterministic compilation): another
  reproducibility bug, fixed; this one is independent of paths.
