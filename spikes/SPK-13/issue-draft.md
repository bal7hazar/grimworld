# Draft issue for `starkware-libs/cairo`

> Prepared by SPK-13; Filed as https://github.com/starkware-libs/cairo/issues/10434, 2026-10-02, from bal7hazar. Filing it is the owner's decision (D-154 §3). Everything
> below the line is the issue's text, written to be pasted as is.
>
> D-180 (2026-10-01): re-tested on Scarb 2.20.1 (Cairo 2.20.0), the latest 2.20 release; the drift
> remains there, with the same code at tag v2.20.0 (and v2.19.6). Both versions and their output
> are in the text below.
>
> Maintainer note (not part of the issue): the second observation confirms #10358, whose fix
> #10359 (f9347a8, 2026-09-03) is on upstream `main`. Before filing, check which release first
> ships f9347a8, starting with Scarb v2.19.5 (17 Sep 2026) and v2.19.6 (28 Sep 2026), both released
> after f9347a8 was merged, and whether the thread-order drift still reproduces there; the owner decides.
>
> Answered 2026-10-02: no released Scarb carries f9347a8 (checked by the Overseer).

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
- Scarb 2.20.1 (dd18779a1 2026-08-21), Cairo 2.20.0, Sierra 1.9.3: the same behaviour (output below)
- `lowered_scc_representative` and the warm-up functions are unchanged at the tags v2.20.0 and
  v2.19.6 and on `main` (read 2026-10-01)
- Measured on aarch64-apple-darwin (12 CPUs). The two main values of the larger contract below
  were also *recorded* on x86_64 Linux (GitHub `ubuntu-latest` and a Linux server), with the same
  sizes; those observations come from the library's own records, not from a run for this issue

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

On a machine with several cores (rayon's default: one thread per CPU), in the package's folder,
save as `reproduce.sh` (Python 3 standard library only). For each clean build it prints the
sha256 of the Sierra file and the function(s) holding a `withdraw_gas` invocation, found by
comparing each invocation's statement index with each function's entry point:

```sh
#!/usr/bin/env bash
# reproduce.sh N [threads]
set -euo pipefail
for _ in $(seq "$1"); do
  scarb clean
  if [ -n "${2:-}" ]; then RAYON_NUM_THREADS=$2 scarb build >/dev/null; else scarb build >/dev/null; fi
  python3 - <<'PY'
import hashlib, json
raw = open("target/dev/spk13_minimal.sierra.json", "rb").read()
p = json.loads(raw)
wg = {l["id"]["id"] for l in p["libfunc_declarations"] if l["long_id"]["generic_id"] == "withdraw_gas"}
funcs = sorted((f["entry_point"], f["id"]["debug_name"]) for f in p["funcs"])
at = [i for i, s in enumerate(p["statements"])
      if "Invocation" in s and s["Invocation"]["libfunc_id"]["id"] in wg]
holders = [max(f for f in funcs if f[0] <= i)[1] for i in at]
print(hashlib.sha256(raw).hexdigest()[:16], "withdraw_gas in:", ", ".join(holders))
PY
done
```

```sh
./reproduce.sh 12      # default thread count
./reproduce.sh 6 1     # RAYON_NUM_THREADS=1
```

### Observed

On Apple silicon (aarch64-apple-darwin, 12 CPUs), Scarb 2.19.4 (b45b74c03 2026-07-21), Cairo
2.19.4, Sierra 1.9.3. `./reproduce.sh 12` (Scarb's `Removing`/`Cleaning` lines left out):

```
cc84d4998d887ef7 withdraw_gas in: spk13_minimal::ping
4ea841fa598a9432 withdraw_gas in: spk13_minimal::b::pong
d56f79567e6181b3 withdraw_gas in: spk13_minimal::ping
55e726f6e626198b withdraw_gas in: spk13_minimal::b::pong
4001df20512a533f withdraw_gas in: spk13_minimal::b::pong
2cf990d2848e8002 withdraw_gas in: spk13_minimal::b::pong
0b5c625c397d5859 withdraw_gas in: spk13_minimal::ping
9ada092d9c5b5cae withdraw_gas in: spk13_minimal::b::pong
83f73d1ca1e02da7 withdraw_gas in: spk13_minimal::ping
7f4f5b6776edff14 withdraw_gas in: spk13_minimal::ping
8907b7064d85d4af withdraw_gas in: spk13_minimal::b::pong
b5422d51771a6269 withdraw_gas in: spk13_minimal::b::pong
```

`./reproduce.sh 6 1`:

```
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
12ec3e1650a18599 withdraw_gas in: spk13_minimal::ping
```

On Scarb 2.20.1 (dd18779a1 2026-08-21), Cairo 2.20.0, same machine. `./reproduce.sh 12`:

```
00e2e8e902e98256 withdraw_gas in: spk13_minimal::ping
9903cf3bca46958a withdraw_gas in: spk13_minimal::ping
ae1e6af352e82826 withdraw_gas in: spk13_minimal::b::pong
cae67c3eb8f303ca withdraw_gas in: spk13_minimal::b::pong
8c19ba8c1aec3297 withdraw_gas in: spk13_minimal::ping
810332a4f12e23ec withdraw_gas in: spk13_minimal::ping
4d8779d0476e70c9 withdraw_gas in: spk13_minimal::b::pong
9900fe9ac9aa78b7 withdraw_gas in: spk13_minimal::b::pong
39d2eb57aa625343 withdraw_gas in: spk13_minimal::b::pong
f65d78e57ab107cc withdraw_gas in: spk13_minimal::ping
06600e72e692bd37 withdraw_gas in: spk13_minimal::ping
02ee609e3c1a22ed withdraw_gas in: spk13_minimal::b::pong
```

`./reproduce.sh 6 1`:

```
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
ecdb2df475027c55 withdraw_gas in: spk13_minimal::ping
```

On both versions, on several threads, the gas check moves between `ping` and `pong` from one build
to the next (5 / 7 builds on 2.19.4, 6 / 6 on 2.20.1), and the file differs on every build (it also writes the numeric intern id beside
each debug name). On one thread the file is identical, byte for byte, when built from the same directory. Earlier series on the same
machine: 9 / 11 out of 20 builds, and 16 / 4 out of 20 while another build loaded the machine;
`RAYON_NUM_THREADS=1`, 10 out of 10 identical.

The two programs (check in `ping`, check in `pong`) have the same types, libfuncs and function
declarations, 90 statements each, printed as Sierra text with their names. The function that
holds the check begins with `withdraw_gas([0], [1]) { fallthrough(...) ... }`, calls the out-of-gas
panic (`panic_with_const_felt252::<375233589013918064796019>`, "Out of gas") and has 43
statements; the other has 33. The order of the type and libfunc declarations differs with it.

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

### A second observation, not part of the reproduction

A different cause, independent of threads, and a known one: the closure-path bug of #10358
(absolute paths in closure type names). It is **still present in Scarb 2.19.4 (measured here) and 2.20.1 (per #10358's own sweep)**. Its
fix, #10359 (f9347a8, "Name generated functions by a rustc-style path instead of their source
location"), is on upstream `main` and was merged after both of those releases.

The compiler names a closure type `{closure@<root>/src/lib.cairo:L:C: L:C}` (`<root>` is the
absolute path of the package's folder) and gives it the Sierra user-type id
`ut@[starknet_keccak(name)]`. The id is a type of the program, so the build directory is in the
Sierra text and in the class hash. Minimal description (not reduced to a standalone package for
this issue): a contract whose code contains one closure, bound to a local and called directly; the
same commit, `Scarb.lock`, Scarb version and `RAYON_NUM_THREADS=1`, built from two different
directories, gives two Sierra texts and two class hashes. An artefact is affected exactly when it
holds a closure type; the other artefacts of the same workspace had the same Sierra text at every
path (two of them had varying file bytes with equal text).

Evidence, from a larger private project (51 artefacts, Scarb 2.19.4, `RAYON_NUM_THREADS=1`): 7
artefacts held a closure type (one contract class, one program and the test builds that contain
it). Built at four different absolute paths on x86_64 Linux, those 7 gave four different Sierra
texts and file hashes, with the class hash of the contract class changing too. With the root
replaced by a placeholder in every closure name and each id recomputed, the texts of the builds at
two Linux paths and at two macOS paths were equal, one text per artefact; a third Linux path
matched the text predicted this way before it was built. A Linux build also predicts the macOS
Sierra text exactly when the macOS root is put in (macOS rewrites `/tmp` to `/private/tmp`, so no
literal equal path was built). So the platform is not the cause: the macOS/Linux difference first
seen in that project was a difference of build paths, and it was the whole of it. What changes with
the path: the file bytes, the Sierra text hash and the class hash. What does not: the Sierra felt
count, the CASM felts and the CASM hash (the id is one felt at any path length, and the path does
not reach the CASM).

### Workaround

Build with `RAYON_NUM_THREADS=1` (slower; no parallel warm-up).

### Related

- #10358 (absolute paths in closure type names broke deterministic compilation): another
  reproducibility bug, fixed upstream by #10359 (f9347a8, after Scarb 2.20.1); still present in
  2.19.4 (measured here) and 2.20.1 (per #10358's own sweep), see the second observation. The thread-order drift is independent of paths.
