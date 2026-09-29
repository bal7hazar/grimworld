# SPK-4 — Parity between the client's prediction and the chain

Spike of risk R-1 ([ADR-0001](../architecture/ADR-0001-execution-layer.md), validation row SPK-4:
10 000 generated vectors, 0 divergence). Run on 2026-09-29 on the shared VPS (8 vCPU, load average
1.2 to 1.8 during the final runs). Everything is in [`spikes/SPK-4/`](../../spikes/SPK-4/).

## Summary

| | (a) TypeScript mirror + vectors | (b) the Cairo code in cairo-vm, compiled to WebAssembly |
|---|---|---|
| Divergences on 10 000 vectors (1 246 panics) | **0**, from the first pass; panic data equal too | **0** through `step`, **0** through `batch` (the artifact and arguments `scarb execute` ran), 200/200 against `scarb execute` of `step` itself |
| Time per call, Node 24 (worker) | **2.4 µs** mean (replay of 10 000 in 24 ms) | **460 µs** mean, p50 344 µs, p95 915 µs (damage 269 µs, goblin step 654 µs) |
| Time per call, Firefox 156 headless (Web Worker) | not measured | **464 µs** mean (the clock is coarsened to 1 ms: p50 and p95 are not meaningful there) |
| First call, cold | 0.24 ms | 118 ms Node (instantiate 33, load executable 19, first run 66), 80 ms Firefox |
| Memory | Negligible (bigints) | 25 MB of WebAssembly memory; Node process peak RSS 167 MB |
| Shipped | 9.1 KB raw, **3.6 KB gzip** (logic, integer helpers, table) | 1.37 MB wasm (**527 KB gzip**, no `wasm-opt`) + 8.7 KB bindings + the executable (115 KB raw, **8.8 KB gzip**) |
| Maintenance | Every rule written twice; vectors regenerated and replayed | Every rule written once; the executable rebuilt and shipped |
| Upstream status | — | **WebAssembly support was removed from cairo-vm in 3.2.0**: it still builds and runs, unsupported |

**Recommendation for CLI-02: option (a)**, a TypeScript mirror gated by vectors generated from the
Cairo library, with the cairo-vm runner kept **natively** as the fast vector generator and oracle
(below). Reasons: it is 190 times faster per call and 150 times smaller, it starts cold in a
fraction of a millisecond, it is the proven practice (ADR-0003 *How other on-chain games predict*),
and the vectors make its main weakness, drift, measurable: they caught all 16 typical mirror mistakes
seeded into it. Option (b) works and is exact by construction, but on a library its maintainers no
longer support on WebAssembly, and at a cost per call that the real tick (8 goblins, a flood) will
multiply.

## The logic under test

A pure library, state in and state out, no storage ([ADR-0007](../architecture/ADR-0007-native-starknet.md)
*Pure logic*), in [`spikes/SPK-4/cairo/logic`](../../spikes/SPK-4/cairo/logic/src/):

- **Damage** (design/04 *Damage formula*): `armor + bonus − penetration` in u16 (overflow and
  underflow panic), `x = strength − armor` in i32 clamped to [−160, +80], `2^(x/40)` read from a
  table of 241 entries with 16 fractional bits, `base × factor` in u32 (overflow panics) truncated
  by `/ 2^16`, then the percent modifiers (+40 critical, −33 weakness) by a **signed truncating
  division**, the result narrowed to u16 (negative or too large panics).
- **One goblin step** on the window of D-120 (15 × 16 pointy-top hexes, SPK-7's conventions): the
  free neighbour nearest to the target by hex distance, ties by lowest tile index (design/04
  *Goblin AI*); holds when adjacent or when no neighbour is nearer. Layers are **felt bitmaps**
  read through a u256 view (240 tiles do not fit a u128); the occupied layer is updated by felt
  arithmetic `occupied − 2^from + 2^to`, which **wraps modulo P** when the goblin's own tile was
  not marked (377 of the 4 763 goblin steps that return, 7.9 %, move from an unmarked tile and wrap).
- **Decoding** (`exec::run`): a case `[op, args...]` of felts, each argument narrowed to its type
  (`Option::unwrap failed.` when outside it), unknown ops and wrong arities panic.

Its cost on the chain (snforge, l2 gas; Cairo steps from `scarb execute` of `step`, which adds the
executable's decoding):

| Algorithm | l2 gas (benchmark test) | Cairo steps per call (mean / max over the vectors) |
|---|---:|---:|
| `damage`, every operation | 23 990 | 353 / 355 |
| `goblin_step`, six neighbours weighed | 58 526 | 1 224 / 1 714 |

The steps of WebAssembly are `scarb execute`'s minus 3 on every sampled case (the entry wrapper);
the outputs are identical.

## The vectors

[`spikes/SPK-4/generate.py`](../../spikes/SPK-4/generate.py) chooses the inputs; **every output
is what `scarb execute` printed**. The `batch` executable runs many cases and prints each result as
it is computed; a panic ends the run, so the case after the last print is the one that panicked,
its panic data is read from scarb's error, and the next run starts after it. 10 000 cases, 1 246
runs of `scarb execute`, 671 s.

| Kind | Returned | Panicked |
|---|---:|---:|
| Damage | 3 991 | 1 076 |
| Goblin step | 4 763 | 155 |
| Unknown op, wrong arity | 0 | 15 |

Inputs lean on boundaries: the table's ends (x = −160, 80 and beyond), armor + bonus at 65 535,
penetration just above armor, products just over 2^32, modifiers −100, −101, i16 limits, tiles on
the edges and corners of the window, bits above tile 239 in the layers, targets adjacent, goblins
whose own tile is not marked, tiles 240 and above, arguments one past their type. Format
(`vectors/vectors.jsonl`, 1.7 MB): one JSON line per case, felts in hex, `ok` or `panic` with the
panic data.

## Option (a): the TypeScript mirror

[`spikes/SPK-4/ts/`](../../spikes/SPK-4/ts/): `cairo.ts` (Cairo's integer semantics on `bigint`,
ADR-0003's table: range-checked operations that throw a `CairoPanic` carrying Cairo's panic data,
truncating division, felt arithmetic modulo P for bitmaps only), `logic.ts` (the three functions,
same order of operations and types), `table.ts` (generated from the same script as the Cairo table:
content is data, the table cannot diverge). No dependency: Node 24 runs the `.ts` files directly.

```
$ node spikes/SPK-4/ts/replay.ts
{ "vectors": 10000, "panics": 1246, "divergences": 0, "panic_data_differs": 0,
  "first_call_ms": 0.235, "replay_ms_median": 24.4, "per_call_us": 2.44, "reps": 5, "node": "v24.21.0" }
```

**Divergences found on the way: none in the mirror.** The mirror replayed the first set of
vectors with 0 divergence and 0 difference of panic data on its first run. What the spike did
find on the way is listed here, since the brief asks for every one:

| Found | Where | Cause | Fix |
|---|---|---|---|
| A mirror that skips the type check of the arguments survived every vector but 3, and those 3 caught it only by the panic data | The first set of vectors | The malformed cases rarely put an out-of-type value where nothing else panicked | `decoding_case` in the generator: one argument just outside its type, the rest chosen so that only decoding can panic; vectors regenerated. The mutant is now caught by 20 vectors on the throw alone |
| `scarb execute` printed three sampled results as negative numbers | `scarb execute --print-program-output` | Scarb prints a felt above P/2 as `−(P − x)` | Read modulo P (`vm/scarb_sample.py`). A trap for any client that parses Scarb's output; the `println!` of the vectors prints felts unsigned |
| Two expectations of the Cairo tests were wrong (a distance of 22 for 21, a bit written 2^123 for 2^127) | `cairo/logic/src/tests.cairo`, before the first commit | Hand arithmetic | The tests take bits from the table |

**The vectors are strong enough to be trusted as a gate.** [`ts/mutants.ts`](../../spikes/SPK-4/ts/mutants.ts)
seeds 16 mistakes a hand-written mirror typically makes and replays each against the vectors:

| # | Mutant | Vectors that catch it | Caught only by the panic data |
|---|---|---:|---:|
| 1 | signed division floors instead of truncating | 1068 | 0 |
| 2 | unsigned division rounds instead of truncating | 1031 | 0 |
| 3 | u32 product not range-checked | 33 | 141 |
| 4 | u16 sum not range-checked | 42 | 75 |
| 5 | armor below zero clamps instead of panicking | 173 | 45 |
| 6 | result not narrowed to u16 | 388 | 0 |
| 7 | table clamp one short at the top | 1296 | 54 |
| 8 | table computed at run time with floating point, floored | 33 | 0 |
| 9 | ties broken by highest tile | 2208 | 0 |
| 10 | ties broken by neighbour order | 785 | 0 |
| 11 | felt subtraction without the modulus | 71 | 0 |
| 12 | goblin next to the target still steps | 326 | 0 |
| 13 | odd and even rows swapped | 2772 | 0 |
| 14 | arguments not checked against their type | 20 | 2 |
| 15 | negative i16 argument read as unsigned | 1324 | 5 |
| 16 | tile outside the window not rejected | 69 | 0 |

16 killed, 0 survived. Mutants 3 and 8 are caught by 33 vectors only: the boundaries of a rule
must be generated on purpose, random inputs alone would miss them.

Caveat: the mirror was written by the author of the Cairo code, in one sitting, with the ADR's
table in hand. A 0 on the first pass says the method works on this logic; it does not say a
different author, or a rule changed months later, gets 0 on the first pass. That is what the
vectors are for.

## Option (b): the Cairo code in cairo-vm, compiled to WebAssembly

[`spikes/SPK-4/vm/runner`](../../spikes/SPK-4/vm/runner/src/lib.rs) is a crate of 350 lines over
**cairo-vm 3.2.0** (crates.io) and cairo-lang-casm 2.19.6. It runs Scarb's `executable.json`
(CASM and hints, the artifact `scarb execute` runs) from the `Bootloader` entrypoint: core hints
go to cairo-vm's `Cairo1HintProcessor`, and the four hints of the executable's wrapper that the VM
does not know are handled in the crate (`WriteRunParam` for the arguments, `AddMarker` for the
panic data, `AddRelocationRule`, `DebugPrint` for `println!`). The method is the owner's physics
spike's (slingfall `docs/research/03-spike-wasm-vm.md`), rebuilt here; nothing was copied. The
executables are in [`spikes/SPK-4/exec`](../../spikes/SPK-4/exec/src/lib.cairo): `step` (one case,
as the client would call it) and `batch` (the generator's).

Build (Rust 1.89.0, the toolchain with the wasm32 target on the machine; `-j 4`):

```
$ spikes/SPK-4/vm/build.sh          # native: 3 min 11 s cold; wasm32-unknown-unknown: 2 min 15 s
    Finished `release` profile [optimized] target(s) in 2m 15s
-rw-rw-r-- 1 claude claude 1371766 Sep 29 03:22 spikes/SPK-4/vm/pkg-web/spk4_runner_bg.wasm
```

The only WebAssembly-specific dependency is `getrandom 0.2` with its `js` feature (cairo-vm pulls
`rand 0.8`; nothing draws randomness on this path). wasm-bindgen 0.2.129, `wasm-bindgen-cli`
0.2.129 installed under `spikes/SPK-4/vm/tools`. No `wasm-opt` on the machine: the size is
unoptimised.

Measurements, the final runs ([`vm/js/bench-core.mjs`](../../spikes/SPK-4/vm/js/bench-core.mjs),
the same code in both hosts):

| | Node 24.21, worker thread | Firefox 156.0.1 headless, module Web Worker | Native (release) |
|---|---:|---:|---:|
| `step` on 10 000 vectors: divergences | 0 | 0 | 0 |
| `batch` with the generator's arguments (1 246 runs): divergences | 0 | 0 | — |
| `scarb execute` of `step`, 200 sampled cases: outputs differing | 0 | 0 | — |
| Steps, `scarb execute` − WebAssembly | 3 on every case | 3 on every case | — |
| Instantiate the module | 33 ms | 21 ms | — |
| Load the executable (parse 5 059 felts of bytecode) | 19 ms | 9 ms | 5 ms |
| First call | 66 ms | 50 ms | — |
| Mean per call | 460 µs | 464 µs | 229 µs |
| p50 / p95 / max per call | 344 / 915 / 2 672 µs | coarsened clock | — |
| Damage / goblin step, mean | 269 / 654 µs | 461 / 889 µs | — |
| WebAssembly memory | 25.0 MB | 25.0 MB | — |
| Process peak RSS | 167 MB (Node) | 1 481 MB (whole headless Firefox) | — |

An earlier run under more load gave 726 µs mean in Node (p95 1.6 ms): the VPS is shared, the
figures are an order of magnitude, not a benchmark. Most of a call is fixed cost (a new
`CairoRunner`, the program loaded into VM memory, the security check): a damage of 350 steps
costs 269 µs, a goblin step of 1 220 steps 654 µs. Reusing the runner's memory between calls is a
lever the spike did not pull.

### Is WebAssembly supported in cairo-vm 3.2.0?

**It builds and it runs, but it is no longer supported.** Settled here by a build and a run:
cairo-vm 3.2.0 from crates.io compiles for `wasm32-unknown-unknown` with no source change and runs
the 10 000 vectors in Node and in Firefox with 0 divergence (above). What the search had read is
true too: the cairo-vm changelog for 3.2.0 (2026-03-03) lists **"Remove WASM support
[#2328](https://github.com/lambdaclass/cairo-vm/pull/2328)"** and **"Remove no_std support
[#2326](https://github.com/lambdaclass/cairo-vm/pull/2326)"**, and the crate's features lost `std`
and `default` between 3.1.0 and 3.2.0 (crates.io API). A `std` build for wasm32 works because
Rust's standard library exists for that target; what upstream dropped is the no-std path, the demo
and, by the changelog's words, the support: nothing in their CI keeps wasm32 building. The
owner's physics spike reached the same result on a clone of 3.2.0 (commit `f7ac327f`). Consequence:
option (b) would pin cairo-vm and carry the risk that a later version stops compiling for wasm32.

## Maintenance cost

Counted from the spike's code, for a rule change such as "armor below zero clamps at 0 instead of
panicking" (one line of `damage`):

| | (a) mirror | (b) VM |
|---|---|---|
| Lines touched | 1 in `damage.cairo`, 1 in `logic.ts` | 1 in `damage.cairo` |
| Then | Rebuild the executables; regenerate the vectors (11 min through `scarb execute`, 2.3 s through the native runner); replay (0.03 s); a divergence names the case | Rebuild the executables; ship the new `step.executable.json` (8.8 KB gzip) with the client |
| Risk | The two lines disagree: the vectors catch it if they cover the new boundary (add the boundary to the generator) | None on the logic; the executable must match the deployed class exactly (versioning of the artifact) |
| New rule | The function in Cairo, its mirror in TypeScript (the spike: 49 + 136 + 40 Cairo lines, 133 + 68 TypeScript lines), a generator for its inputs, a mutant or two | The function in Cairo, its entry in the executable's `run` |

What the client needs besides the logic, in both options: **the serialisation of state in and
out as felts**, with Cairo's Serde layout (an array is its length, then its elements; an i16 is
the felt `P − x` when negative; a u8 read from a felt panics above 255), and the panic data as the
reason of a refused action. Option (a) needs it only at the edges (reading the chain's state,
comparing with the vectors); option (b) needs it on every call, since every call crosses into the
VM as felts and comes back as felts to decode.

## Recommendation for CLI-02

**Option (a)**: the simulation core in TypeScript, gated by vectors from the Cairo library.

1. **Cost per call.** 2.4 µs against 460 µs. The real tick is 8 awake goblins and one flood of
   15 layers (design/02): at the goblin step's 654 µs, 8 goblins are already about 5 ms per tick
   in (b) before the flood, and a planned queue walked ahead by the client multiplies it. (a) stays
   in microseconds.
2. **Size and start.** 3.6 KB gzip against 536 KB, and 0.24 ms against 80 to 118 ms for the first
   call, on a mobile-first client (ADR-0003).
3. **Upstream.** WebAssembly support was removed from cairo-vm 3.2.0; building a client on it means
   owning that port.
4. **Drift is measurable.** 10 000 vectors from the Cairo code, boundaries generated on purpose,
   and the mutation check that proves the vectors would catch the usual mistakes (16 of 16).

Keep of option (b), natively: **the runner as the vector generator and oracle in CI**. It ran the
same CASM as `scarb execute` with identical outputs (200 of 200 sampled, 10 000 of 10 000 against
the `batch` outputs) in 2.3 s for 10 000 cases, against 11 minutes through `scarb execute`. It also
remains the fallback if a rule proves too hard to mirror (a Poseidon-heavy one, say): that rule
alone could run in the VM.

## What the choice imposes on ENG-02 and CBT-*

- **The logic is a pure library crate** (no storage, no syscalls, no events): state in, state out,
  as `cairo/logic` here, so that it runs under `snforge`, `scarb execute` and the runner alike. The
  contracts call it; they add nothing to a rule.
- **A thin executable package over it** exposing each rule as a case (`run([op, args...])`), for
  the vectors. The CI does not gate such a package today (escalation below).
- **Every rule ships with its vector generator** (inputs at its boundaries, its panics included), its
  mirror, and at least one mutant that proves the vectors see the rule. A rule without vectors is
  not mirrored.
- **Panic data is API.** The mirror reproduces Cairo's panic data (`u16_sub Overflow`,
  `Option::unwrap failed.`, the game's own short strings); a change of message moves the vectors.
- **Tables are generated once** for both sides (`gen_table.py`); a table is never retyped.
- **Integer types are part of the rule.** The mirror mirrors the type of every intermediate value
  (u16 sum, u32 product, i32 modifier): changing a type in Cairo changes where it panics, and moves
  the vectors (COMMON §4, game results are API).
- **Felts only for bitmaps and hashes** (ADR-0003); the wrap modulo P of the occupied layer is
  reproduced exactly, and must be.

## Open questions (design/04 is silent; spike choices, not rules)

1. Fixed point of the damage table: 16 fractional bits, rounded to nearest, here.
2. Armor below zero (penetration above armor + bonus): a panic here; a clamp at 0 is as likely to be
   meant, and it is a rule.
3. The order of modifiers: here the table's product is truncated first, then the percent modifiers
   are summed and applied once with a truncating division. Critical ×1.4 and weakness −33 % could be
   applied in sequence, which gives other results.
4. Damage that does not fit a u16, or a negative total: a panic here.
5. A goblin whose own tile is not marked occupied: here the layer wraps modulo P; the contracts
   should assert the invariant instead.

## Reproduce

From the worktree root:

```
python3 spikes/SPK-4/gen_table.py && scripts/lock.sh scarb --manifest-path spikes/SPK-4/cairo/Scarb.toml fmt --workspace
cd spikes/SPK-4/cairo && snforge test                                          # 17 tests
python3 scripts/gas_budgets.py --check --workspace spikes/SPK-4/cairo --budgets spikes/SPK-4/BUDGETS.md
scripts/lock.sh scarb --manifest-path spikes/SPK-4/exec/Scarb.exec.toml build
python3 spikes/SPK-4/generate.py --count 10000 --seed 4                        # 11 min
node spikes/SPK-4/ts/replay.ts && node spikes/SPK-4/ts/mutants.ts
spikes/SPK-4/vm/build.sh
spikes/SPK-4/vm/runner/target/release/spk4-run spikes/SPK-4/exec/target/dev/step.executable.json vectors spikes/SPK-4/vectors/vectors.jsonl
python3 spikes/SPK-4/vm/scarb_sample.py --count 200
node spikes/SPK-4/vm/js/node-bench.mjs
python3 spikes/SPK-4/vm/browser_bench.py
python3 spikes/SPK-4/sizes.py
```
