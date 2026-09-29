# SPK-4 — Parity between the client's prediction and the chain

Spike of risk R-1 ([ADR-0001](../architecture/ADR-0001-execution-layer.md), validation row SPK-4:
10 000 generated vectors, 0 divergence). Run on 2026-09-29 on the shared VPS (8 vCPU; load average
between 1.2 and 5.8 during the runs, so every time below is an order of magnitude, not a benchmark).
Everything is in [`spikes/SPK-4/`](../../spikes/SPK-4/). Revised by fix loop 1 of the
[GPT-6-Astra] audit: the window's ring is wall, the empty case is checked on both sides, every
checker fails on a divergence, the cold start is split with the same boundaries for both options.

## Summary

| | (a) TypeScript mirror + vectors | (b) the Cairo code in cairo-vm, compiled to WebAssembly |
|---|---|---|
| Divergences on 10 000 vectors (1 308 panics) | **0**, panic data equal too | **0** through `step`, **0** through `batch` (the artifact and arguments `scarb execute` ran), 200/200 against `scarb execute` of `step` itself |
| Time per call, Node 24 worker | **3.2 µs** mean (replay of 10 000 in 32 ms) | **411 µs** mean, p50 305 µs, p95 896 µs (damage 295 µs, goblin step 747 µs) |
| Time per call, Firefox 156 headless (Web Worker) | not measured | **494 µs** mean (the clock is coarsened to 1 ms: p50 and p95 are not meaningful there) |
| Cold start, same boundaries (Node) | init 9.7 ms (import the modules), load 0, serialise 0.03 ms, first execution 0.15 ms | init 30.0 ms (instantiate), load 20.1 ms (parse the executable), serialise 0.16 ms, first execution 9.4 ms |
| Memory | Negligible (bigints) | 25 MB of WebAssembly memory; Node process peak RSS 170 MB |
| Shipped | 9.6 KB raw, **3.8 KB gzip** (logic, integer helpers, tables) | 1.37 MB wasm (**527 KB gzip**, no `wasm-opt`) + 8.7 KB bindings + the executable (119 KB raw, **9.1 KB gzip**) |
| Maintenance | Every rule written twice; vectors regenerated and replayed | Every rule written once; the executable rebuilt and shipped |
| Upstream status | — | **WebAssembly support was removed from cairo-vm in 3.2.0**: it still builds and runs, unsupported |

**Recommendation for CLI-02: option (a)**, a TypeScript mirror gated by vectors generated from the
Cairo library, with the cairo-vm runner kept **natively** as the fast vector generator and oracle
(below). It is about 130 times faster per call on the measured primitives, 140 times smaller, it
starts cold in 10 ms against 60 ms, it is the proven practice (ADR-0003 *How other on-chain games
predict*), and the vectors make its main weakness, drift, measurable: they caught all 20 typical
mirror mistakes seeded into it. Option (b) works and is exact by construction, but on a library
whose maintainers no longer support WebAssembly.

**What was not measured**: the TypeScript cost of a **full tick** (8 awake goblins, the 15-layer
flood of design/02) and **Poseidon parity** (`@scure/starknet` against Cairo). The recommendation
rests on the two primitives measured here; CLI-02's first benchmark must confirm the full tick.

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
  *Goblin AI*); holds when adjacent or when no neighbour is nearer. **The outer ring of the window
  (columns 0 and 14, rows 0 and 15) is wall for the computation** (ADR-0006 §4): a goblin standing
  on it is shown, not simulated, and holds; no goblin steps onto it, whatever the walkable layer
  says. There is no unrestricted board routine: this is the D-120 window's. Layers are **felt
  bitmaps** read through a u256 view (240 tiles do not fit a u128), masked by the interior; the
  occupied layer is updated by felt arithmetic `occupied − 2^from + 2^to`, which **wraps modulo P**
  when the goblin's own tile was not marked.
- **Decoding** (`exec::run`): a case `[op, args...]` of felts. An empty case panics with
  `exec: empty case`, an explicit check (Cairo's own `*case[0]` would panic with the core's
  `Index out of bounds`, which the mirror had not reproduced); each argument is narrowed to its type
  (`Option::unwrap failed.` when outside it); unknown ops and wrong arities panic.

Its cost on the chain (snforge, l2 gas; Cairo steps as the WebAssembly run counts them over all
successful vectors, and as `scarb execute` counts them on the sample, below):

| Algorithm | l2 gas (benchmark test) | Cairo steps per successful call, WebAssembly (mean / max) |
|---|---:|---:|
| `damage`, every operation | 23 990 | 357 / 359 |
| `goblin_step`, six neighbours weighed | 62 645 (58 526 before the ring check) | 925 / 1 758 |

## The vectors

[`spikes/SPK-4/generate.py`](../../spikes/SPK-4/generate.py) chooses the inputs; **every output
is what `scarb execute` printed**. The `batch` executable runs many cases and prints each result as
it is computed; a panic ends the run, so the case after the last print is the one that panicked,
its panic data is read from scarb's error, and the next run starts after it. 10 000 cases, 1 309
runs of `scarb execute`, 607 s.

| Kind | Returned | Panicked |
|---|---:|---:|
| Damage | 3 694 | 1 101 |
| Goblin step (the ring cases included) | 4 998 | 163 |
| Empty case | 0 | 11 |
| Unknown op, wrong arity | 0 | 33 |

Inputs lean on boundaries: the table's ends (x = −160, 80 and beyond), armor + bonus at 65 535,
penetration just above armor, products just over 2^32, modifiers −100, −101, i16 limits, tiles on
the edges and corners of the window, bits above tile 239 in the layers, targets adjacent, goblins
whose own tile is not marked, tiles 240 and above, arguments one past their type, and (fix loop 1)
**explicit ring cases**: goblins on the ring, and goblins next to it whose best step, were the ring
open, would land on it, often with the ring marked walkable. [`ring_stats.py`](../../spikes/SPK-4/ring_stats.py)
checks the Cairo outputs: 1 799 successful goblin steps start on the ring, none moves; 2 565 moves
start in the interior, none lands on the ring; the 11 empty cases all panic with `exec: empty case`.

Format (`vectors/vectors.jsonl`): one JSON line per case, felts in hex, `ok` or `panic` with the
panic data.

## Option (a): the TypeScript mirror

[`spikes/SPK-4/ts/`](../../spikes/SPK-4/ts/): `cairo.ts` (Cairo's integer semantics on `bigint`,
ADR-0003's table: range-checked operations that throw a `CairoPanic` carrying Cairo's panic data,
truncating division, felt arithmetic modulo P for bitmaps only), `logic.ts` (the three functions,
same order of operations and types, the ring and the empty check included), `table.ts` (generated
from the same script as the Cairo tables: the damage table and the window's interior). No
dependency: Node 24 runs the `.ts` files directly.

```
$ node spikes/SPK-4/ts/replay.ts
{ "vectors": 10000, "panics": 1308, "divergences": 0, "panic_data_differs": 0,
  "cold": { "init_ms": 9.696, "load_executable_ms": 0, "serialise_first_input_ms": 0.025, "first_execution_ms": 0.146 },
  "replay_ms_median": 32.3, "per_call_us": 3.23, "reps": 5, "node": "v24.21.0" }
```

`replay.ts` reads the file it is given (`node spikes/SPK-4/ts/replay.ts FILE [--reps N]`), exits 1 on
a divergence or a panic-data difference, 2 on a missing, empty or unreadable file or a usage error.

**Divergences found on the way.** The mirror replayed the first vectors with 0 divergence on its
first run. What was found since:

| Found | Where | Cause | Fix |
|---|---|---|---|
| A mirror that skips the type check of the arguments survived every vector but 3, caught only by the panic data | The first vectors | The malformed cases rarely put an out-of-type value where nothing else panicked | `decoding_case` in the generator; the mutant is now caught by 29 vectors on the throw alone |
| `scarb execute` printed three sampled results as negative numbers | `scarb execute --print-program-output` | Scarb prints a felt above P/2 as `−(P − x)` | Read modulo P (`vm/scarb_sample.py`) |
| Two expectations of the Cairo tests were wrong | `tests.cairo`, before the first commit | Hand arithmetic | The tests take bits from the table |
| **The ring of the window was playable** (audit, major 1): 1 422 successful vectors moved a goblin that started on the ring | Both sides, the same wrong rule | ADR-0006 §4 (the ring is wall for the computation) was not applied | The interior mask in Cairo and in the mirror, ring cases in the generator, three ring mutants; vectors regenerated |
| **The empty case diverged** (audit, major 2): Cairo panicked `Index out of bounds`, the mirror `exec: unknown op` | `exec::run` | The mirror did not reproduce the panic of an out-of-range index | An explicit `exec: empty case` check on both sides, empty cases in the vectors |

The empty case shows the limit of a throw-only check: without the check, the mirror still throws
(`exec: unknown op`), and only the panic data tells the two apart (mutant 19). The replay counts a
panic-data difference as a failure for that reason.

**The vectors are strong enough to be trusted as a gate.** [`ts/mutants.ts`](../../spikes/SPK-4/ts/mutants.ts)
seeds 20 mistakes a hand-written mirror typically makes and replays each against the vectors:

| # | Mutant | Vectors that catch it | Caught only by the panic data |
|---|---|---:|---:|
| 1 | signed division floors instead of truncating | 981 | 0 |
| 2 | unsigned division rounds instead of truncating | 940 | 0 |
| 3 | u32 product not range-checked | 25 | 156 |
| 4 | u16 sum not range-checked | 39 | 45 |
| 5 | armor below zero clamps instead of panicking | 184 | 45 |
| 6 | result not narrowed to u16 | 328 | 0 |
| 7 | table clamp one short at the top | 1280 | 52 |
| 8 | table computed at run time with floating point, floored | 30 | 0 |
| 9 | ties broken by highest tile | 1450 | 0 |
| 10 | ties broken by neighbour order | 529 | 0 |
| 11 | felt subtraction without the modulus | 43 | 0 |
| 12 | goblin next to the target still steps | 191 | 0 |
| 13 | odd and even rows swapped | 1800 | 0 |
| 14 | arguments not checked against their type | 29 | 5 |
| 15 | negative i16 argument read as unsigned | 1241 | 8 |
| 16 | goblin on the ring simulated (ring ignored for the goblin) | 1053 | 0 |
| 17 | ring tiles walkable (ring ignored for the step) | 69 | 0 |
| 18 | ring ignored entirely (an unrestricted board) | 1528 | 0 |
| 19 | empty case not checked | 0 | 11 |
| 20 | tile outside the window not rejected | 64 | 0 |

Mutants 3, 8 and 17 are caught by fewer than 70 vectors: the boundaries of a rule must be generated
on purpose, random inputs alone would miss them.

Caveat: the mirror was written by the author of the Cairo code, with the ADR's table in hand. A 0
on the first pass says the method works on this logic; it does not say a different author, or a
rule changed months later, gets 0 on the first pass. The ring shows the other limit: when both sides
share the same wrong reading of the design, the vectors agree with both. Parity is not correctness;
the Cairo tests against the design are.

## Option (b): the Cairo code in cairo-vm, compiled to WebAssembly

[`spikes/SPK-4/vm/runner`](../../spikes/SPK-4/vm/runner/src/lib.rs) is a crate of 350 lines over
**cairo-vm 3.2.0** (crates.io) and cairo-lang-casm 2.19.6. It runs Scarb's `executable.json`
(CASM and hints, the artifact `scarb execute` runs) from its `Bootloader` entrypoint: core hints go
to cairo-vm's `Cairo1HintProcessor`, and the four hints of the executable's wrapper that the VM does
not know are handled in the crate (`WriteRunParam`, `AddMarker` for the panic data,
`AddRelocationRule`, `DebugPrint`). The method is the owner's physics spike's (slingfall
`docs/research/03-spike-wasm-vm.md`), rebuilt here; nothing was copied. The executables are in
[`spikes/SPK-4/exec`](../../spikes/SPK-4/exec/src/lib.cairo): `step` (one case, as the client would
call it) and `batch` (the generator's).

Build (Rust 1.89.0, the toolchain with the wasm32 target on the machine; `-j 4`):

```
$ spikes/SPK-4/vm/build.sh          # first build: native 3 min 11 s, wasm32-unknown-unknown 2 min 15 s
-rw-rw-r-- 1 claude claude 1371766 Sep 29 04:34 spikes/SPK-4/vm/pkg-web/spk4_runner_bg.wasm
```

The only WebAssembly-specific dependency is `getrandom 0.2` with its `js` feature (cairo-vm pulls
`rand 0.8`; nothing draws randomness on this path). wasm-bindgen 0.2.129. No `wasm-opt` on the
machine: the size is unoptimised.

Measurements, the final runs ([`vm/js/bench-core.mjs`](../../spikes/SPK-4/vm/js/bench-core.mjs),
the same code in both hosts). Cold start uses the replay's boundaries: files read and first vector
parsed before the clock; the corpus is prepared after the first execution.

| | Node 24.21, worker thread | Firefox 156.0.1 headless, module Web Worker | Native (release) |
|---|---:|---:|---:|
| `step` on 10 000 vectors: divergences | 0 | 0 | 0 |
| `batch` with the generator's arguments (1 309 runs): divergences | 0 | 0 | — |
| `scarb execute` of `step`, 200 sampled cases: outputs differing | 0 | 0 | — |
| Steps, `scarb execute` − WebAssembly, on the 173 sampled successful runs | 3 on every one | 3 on every one | — |
| Init (instantiate the module) | 30.0 ms | 29 ms | — |
| Load the executable (5 258 felts of bytecode) | 20.1 ms | 30 ms | 4.6 ms |
| Serialise the first input | 0.16 ms | 1 ms (coarse clock) | — |
| First execution | 9.4 ms | 2 ms (coarse clock) | — |
| Mean per call | 411 µs | 494 µs | 216 µs |
| p50 / p95 / max per call | 305 / 896 / 2 393 µs | coarsened clock | — |
| Damage / goblin step, mean | 295 / 747 µs | 406 / 767 µs | — |
| WebAssembly memory | 25.0 MB | 25.0 MB | — |
| Process peak RSS | 170 MB (Node) | 1 559 MB (whole headless Firefox) | — |

The first version of this file reported a "first call" of 66 ms in Node: it included parsing and
serialising the whole corpus. Split as above, the first execution is 9.4 ms. Most of a warm call is
fixed cost (a new `CairoRunner`, the program loaded into VM memory, the security check): a damage of
357 steps costs 295 µs, a goblin step of 925 steps 747 µs.

**The three steps.** `scarb execute` runs the `Standalone` entrypoint by default (355 steps for the
same damage case with and without `--target standalone`; `--target bootloader` runs the whole
bootloader, 86 301 steps). The runner starts at the `Bootloader` entrypoint (offset 6), which is
the body the `Standalone` one calls. The `Standalone` entrypoint (offset 0) adds exactly three
instructions before and after it: `ap += 3` (`0x40780017fff7fff`, 3), `call rel 4`
(`0x1104800180018000`, 4) and `jmp rel 0` (`0x10780017fff7fff`, 0), the end loop. The difference is
checked only on the sampled successful runs (173 of 200; `scarb execute` prints no resources for a
panic). The sample is committed: [`vectors/scarb-sample.jsonl`](../../spikes/SPK-4/vectors/scarb-sample.jsonl).

**Every checker fails when it should** (fix loop 1): the native runner, `node-bench.mjs`,
`browser_bench.py` and `scarb_sample.py` exit non-zero on a divergence, on a browser error or
timeout, and on an incomplete verification (no sample, an empty sample or vector file, a sampled id
absent). Each was run against [`fixtures/wrong-expectation.jsonl`](../../spikes/SPK-4/fixtures/)
(one expectation deliberately wrong) and failed; the commands and outputs are in the fix loop's
report.

### Is WebAssembly supported in cairo-vm 3.2.0?

**It builds and it runs, but it is no longer supported.** Settled here by a build and a run:
cairo-vm 3.2.0 from crates.io compiles for `wasm32-unknown-unknown` with no source change and runs
the 10 000 vectors in Node and in Firefox with 0 divergence (above). What the search had read is
true too: the cairo-vm changelog for 3.2.0 (2026-03-03) lists **"Remove WASM support
[#2328](https://github.com/lambdaclass/cairo-vm/pull/2328)"** and **"Remove no_std support
[#2326](https://github.com/lambdaclass/cairo-vm/pull/2326)"**, and the crate's features lost `std`
and `default` between 3.1.0 and 3.2.0 (crates.io API). A `std` build for wasm32 works because
Rust's standard library exists for that target; what upstream dropped is the no-std path, the demo
and, by the changelog's words, the support: nothing in their CI keeps wasm32 building. The owner's
physics spike reached the same result on a clone of 3.2.0. Consequence: option (b) would pin
cairo-vm and carry the risk that a later version stops compiling for wasm32.

## Maintenance cost

Counted from the spike's code, for a rule change such as "armor below zero clamps at 0 instead of
panicking" (one line of `damage`):

| | (a) mirror | (b) VM |
|---|---|---|
| Lines touched | 1 in `damage.cairo`, 1 in `logic.ts` | 1 in `damage.cairo` |
| Then | Rebuild the executables; regenerate the vectors (10 min through `scarb execute`, 2.2 s through the native runner); replay (0.03 s); a divergence names the case | Rebuild the executables; ship the new `step.executable.json` (9.1 KB gzip) with the client |
| Risk | The two lines disagree: the vectors catch it if they cover the new boundary (add the boundary to the generator) | None on the logic; the executable must match the deployed class exactly (versioning of the artifact) |
| New rule | The function in Cairo, its mirror in TypeScript, a generator for its inputs, a mutant or two. The ring of fix loop 1: 8 lines of Cairo, 3 of TypeScript, 20 of generator, 3 mutants | The function in Cairo, its entry in the executable's `run` |

What the client needs besides the logic, in both options: **the serialisation of state in and out
as felts**, with Cairo's Serde layout (an array is its length, then its elements; an i16 is the felt
`P − x` when negative; a u8 read from a felt panics above 255), and the panic data as the reason of a
refused action. Option (a) needs it only at the edges; option (b) on every call.

## Recommendation for CLI-02

**Option (a)**: the simulation core in TypeScript, gated by vectors from the Cairo library.

1. **Cost per call**, on the two measured primitives: 3.2 µs against 411 µs. As an **illustrative
   estimate only**, not a measurement: eight goblin steps at the measured 747 µs would be about 6 ms
   per tick in (b) before any flood, and a planned queue walked ahead by the client multiplies it.
   The full tick was measured in neither option.
2. **Size and start.** 3.8 KB gzip against 536 KB; cold start 10 ms against 60 ms on the same
   boundaries, on a mobile-first client (ADR-0003).
3. **Upstream.** WebAssembly support was removed from cairo-vm 3.2.0.
4. **Drift is measurable.** 10 000 vectors from the Cairo code, boundaries generated on purpose,
   and the mutation check that proves the vectors would catch the usual mistakes (20 of 20).

Keep of option (b), natively: **the runner as the vector generator and oracle in CI**. It ran the
same CASM as `scarb execute` with identical outputs in 2.2 s for 10 000 cases, against 10 minutes
through `scarb execute`. It also remains the fallback if a rule proves too hard to mirror (a
Poseidon-heavy one, say): that rule alone could run in the VM.

## What the choice imposes on ENG-02 and CBT-*

- **The logic is a pure library crate** (no storage, no syscalls, no events): state in, state out,
  as `cairo/logic` here, so that it runs under `snforge`, `scarb execute` and the runner alike.
- **A thin executable package over it** exposing each rule as a case (`run([op, args...])`), for the
  vectors. The CI does not gate such a package today (REPORT, escalation).
- **Every rule ships with its vector generator** (inputs at its boundaries, its panics included), its
  mirror, and at least one mutant that proves the vectors see the rule.
- **Every checker fails loudly**: a divergence, an error, a timeout or a verification that verified
  nothing is a non-zero exit, tested with a deliberately wrong fixture.
- **Panic data is API**, and so is the handling of empty and malformed input: explicit checks with
  the game's own short strings, reproduced by the mirror.
- **Tables and masks are generated once** for both sides (`gen_table.py`); never retyped.
- **Integer types are part of the rule.** Changing a type in Cairo changes where it panics, and moves
  the vectors (COMMON §4, game results are API).
- **Felts only for bitmaps and hashes** (ADR-0003); the wrap modulo P is reproduced exactly.
- **Design rules the window imposes** (the ring, D-120) are applied in the routine, not left to the
  caller.

## Open questions (design/04 is silent; spike choices, not rules)

1. Fixed point of the damage table: 16 fractional bits, rounded to nearest, here.
2. Armor below zero (penetration above armor + bonus): a panic here; a clamp at 0 is as likely.
3. The order of modifiers: summed and applied once with a truncating division here; critical ×1.4 and
   weakness −33 % could be applied in sequence, which gives other results.
4. Damage that does not fit a u16, or a negative total: a panic here.
5. A goblin whose own tile is not marked occupied: the layer wraps modulo P here; the contracts should
   assert the invariant instead.
6. A target on the ring: allowed here (goblins move toward it without stepping onto the ring); the
   adventurer is never on the ring, other targets might be.

## Reproduce

From the worktree root:

```
python3 spikes/SPK-4/gen_table.py && scripts/lock.sh scarb --manifest-path spikes/SPK-4/cairo/Scarb.toml fmt --workspace
cd spikes/SPK-4/cairo && snforge test                                          # 20 tests
python3 scripts/gas_budgets.py --check --workspace spikes/SPK-4/cairo --budgets spikes/SPK-4/BUDGETS.md
scripts/lock.sh scarb --manifest-path spikes/SPK-4/exec/Scarb.exec.toml build
python3 spikes/SPK-4/generate.py --count 10000 --seed 4                        # 10 min
python3 spikes/SPK-4/ring_stats.py
node spikes/SPK-4/ts/replay.ts && node spikes/SPK-4/ts/mutants.ts
spikes/SPK-4/vm/build.sh
spikes/SPK-4/vm/runner/target/release/spk4-run spikes/SPK-4/exec/target/dev/step.executable.json vectors spikes/SPK-4/vectors/vectors.jsonl
python3 spikes/SPK-4/vm/scarb_sample.py --count 200
python3 spikes/SPK-4/make_fixtures.py                                          # the negative checks' fixtures
node spikes/SPK-4/vm/js/node-bench.mjs
python3 spikes/SPK-4/vm/browser_bench.py
python3 spikes/SPK-4/sizes.py
```
