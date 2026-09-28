# SPK-4 — Parity spike

## Agent
Title: `[Opus 5.5] SPK-4 parity spike` · Profile: implement · Branch: `chore/spk-4-parity`

## Goal
After this task we know, measured on a representative piece of game logic, which of two
ways keeps the client's prediction identical to the chain (risk R-1, the main technical risk
of ADR-0001): **(a)** a TypeScript mirror checked against vectors generated from the Cairo
code, or **(b)** the Cairo code itself run in the client through a Cairo VM compiled to
WebAssembly. The answer decides how CLI-02 and every mirrored task are built.

## Context
- ADR-0001 *Consequences* (game logic exists twice; divergence is the main risk) and its
  validation row SPK-4 (**10 000 generated vectors, 0 divergence**); ADR-0003 *What a TypeScript
  mirror must reproduce* (overflow and underflow panic, truncating division, felt arithmetic
  for hashing and bitmaps only, Poseidon through `@scure/starknet`, bitmaps as `bigint`) and
  *Running the Cairo code in the client* (a search said WebAssembly support was removed from
  the VM in 3.2.0; **to be settled here**).
- **Prior art on this machine**: the owner's physics game measured cairo-vm 3.2.0 compiled to
  WebAssembly in Node and in a browser worker:
  `/home/claude/projects/slingfall/docs/research/03-spike-wasm-vm.md` (read it; its spike
  files are under `/home/claude/projects/pm/spikes/wasm-vm/`, read-only for you: copy nothing,
  rebuild what you need in your worktree). It found WebAssembly working, the same CASM as
  `scarb execute`, and memory as the limit on long runs.
- design/04 (*Damage formula* with the `2^(x/40)` lookup table, *Goblin AI* determinism and
  ties), design/02 (*The tick*), docs/CAIRO.md, COMMON §4 (determinism; game results are API).
- The toolchain: the game is on **Cairo 2.13** (SPK-5). Build the Cairo side as a **pure
  library** (state in, state out, no Dojo, no storage) so that it runs with `scarb execute` and
  in a VM. If the VM in WebAssembly requires another Cairo version, say which and why, and
  measure on it in a package of its own under `spikes/SPK-4/` (as D-122 allows for spikes),
  without changing the game's toolchain.
- Depends on: SPK-5 (merged), FND-01 (merged: `client/sim` is the future home of the
  simulation core; do not write into it here).

## Scope
- In, in `spikes/SPK-4/`:
  1. **The logic under test**, written once in Cairo as a pure library: the damage formula
     with its lookup table, armor and penetration, and one goblin step on a small hex board
     (the nearest free neighbour toward a target, ties by lowest tile index) — enough to
     exercise integer overflow, truncating division, tables and bitmaps.
  2. **Vectors**: a generator that produces **10 000** input/output pairs from the Cairo code
     (inputs chosen to cover boundaries and panics: an input that panics in Cairo must throw in
     the mirror), in a format both sides read.
  3. **Option (a)**: a TypeScript mirror under `spikes/SPK-4/ts/` following ADR-0003's table,
     replaying the 10 000 vectors: divergences counted, then fixed until 0, and the time to
     replay.
  4. **Option (b)**: the same Cairo run in the client through the VM in WebAssembly (Node
     worker; a headless browser if one is available on the machine, otherwise say so): time
     per call, memory, bundle size, first-call latency, and exact equality with `scarb
     execute` on the 10 000 vectors.
  5. **Maintenance cost** of each: what a rule change costs in each option (lines touched,
     where), and what the client needs besides the logic (serialisation of state in and out).
- `docs/research/SPK-4-parity.md`: both options measured side by side, the settled question
  of WebAssembly in cairo-vm 3.2.0 with sources, a recommendation for CLI-02 with its reasons,
  and what the choice imposes on ENG-02 and CBT-* (for example "the logic must be a pure library
  crate").
- Out: the real simulation core (CLI-02); game systems; `contracts/`, `client/`; any
  deployment.
- Allowlist: `spikes/SPK-4/**`, `docs/research/SPK-4-parity.md`. Anything else is an escalation.

## Acceptance criteria
- [ ] AC-1 10 000 vectors generated from the Cairo code, panicking cases included.
- [ ] AC-2 Option (a) replays them with **0 divergence**; the report lists every divergence
      found on the way and its cause.
- [ ] AC-3 Option (b) runs the same Cairo in WebAssembly and matches `scarb execute` on all
      vectors, with time per call, memory and bundle size measured.
- [ ] AC-4 The research file answers "is WebAssembly supported in cairo-vm 3.2.0" with a build
      and a run, not a citation.
- [ ] AC-5 A recommendation with the measurements it rests on.

## Verification
The commands that build the Cairo library, generate the vectors, run the mirror's replay and
the WebAssembly run, from the worktree root, each with its real output in the report.

## Report
`REPORT.md` as in `docs/briefs/COMMON.md` §7; the cost table has the Cairo steps and gas of the
logic under test, and the client-side times and sizes of both options.
