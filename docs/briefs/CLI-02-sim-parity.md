# CLI-02 — The client's simulation core and its parity harness

Written by a thread of track CV for the orchestrator of track CV, on 2026-10-02, at `main`
`f55176c`. PLAN.md row CLI-02: "Client simulation core mirroring ENG-05/07 + parity harness. SPK-4 /
D-140: a TypeScript mirror checked by vectors generated from the Cairo code (option (a)); measure the
full tick in TypeScript and Poseidon, which the spike did not." It depends on ENG-02 (merged, #246)
and SPK-4 (merged, #82). ENG-05 and ENG-07 are still todo, so the task is **split into three lots**:
CLI-02a now, CLI-02b when ENG-05 lands, CLI-02c when ENG-07 lands.

**It is a task of the game lent to track CV** (ORCH-client-visual §8 names it as the next candidate:
"CLI-02 (the client's mirror, after ENG-02)"). `client/sim/**` is under *Never* in the mandate's §1;
the project manager lent it to track CV for CLI-02a, b and c on 2026-10-02 (question 1 below).

## Goal

After the three lots, `client/sim` computes **what the chain computes, bit for bit**, for every rule
the client predicts: the geometry of the window, one hit, the reveal of a chunk, a whole tick. Each
rule is proved equal to the Cairo code by the vector tables the Cairo tests print, replayed in CI on
every pull request, and each lot leaves a mutation check proving the vectors would see the usual
mistakes. CLI-02c also measures what SPK-4 left open: a full tick in TypeScript, Poseidon included.

CLI-03 (the sandbox wired to `client/sim` and the chain) then replaces
`client/app/src/sandbox/placeholders.ts` with this package. CLI-02 does not touch `client/app`.

## Context

- **D-140** (CONTEXT, `docs/decisions/2026-09-29-damage-edges.md`): a rule never panics on a legal
  action; the edges of damage (16 fractional bits rounded to nearest, armor floored at 0, percent
  modifiers summed and applied once truncating, a hit saturated to [0, 65,535]); the client's
  simulation is a TypeScript mirror checked by vectors from the Cairo code. "The full tick in
  TypeScript and Poseidon were not measured by the spike: CLI-02 measures them."
- **SPK-4** (`docs/briefs/SPK-4-parity.md`, `docs/reports/SPK-4-parity.md`,
  `docs/research/SPK-4-parity.md`): option (a), 10,000 vectors, 0 divergence, 2.4 µs a call,
  3.6 KB gzip; the **mutation harness** (`spikes/SPK-4/ts/mutants.ts`: 16, then 20 typical mirror
  mistakes, all caught); *What the choice imposes*: panic data is API, tables and masks generated
  once for both sides, integer types are part of the rule, felts only for bitmaps and hashes with the
  wrap modulo P reproduced, every checker fails loudly. Its open questions: the full tick, and
  Poseidon's parity through `@scure/starknet`. Read its `ts/` for the shape of a mirror; copy nothing
  blindly, the game's rules differ from the spike's.
- **ADR-0003** *What a TypeScript mirror must reproduce*: overflow and underflow throw, truncating
  division, felt arithmetic for hashing and bitmaps only, Poseidon through `@scure/starknet`, bitmaps
  as `bigint`.
- **What the game already gives the mirror** (on `main`):
  - `contracts/logic/vectors/` (README, `check.py`): JSON lines `{"id", "fn"?, "case", "ok"}`, every
    felt in hexadecimal, a negative integer as `P − |v|`.
    - `window.jsonl`, **2,065 cases** (ENG-02): `sight`, `reach`, `arc`, `facing`, `front`,
      `distance`, `shape` over `WindowTrait` (`contracts/logic/src/types/window.cairo`; the frozen
      signature in `docs/reports/ENG-02-geometry.md` *The rules and the frozen signature*). Positions
      are the window's index `15 y + x` (0–239, 240 and above outside), facings `0..=5` from East
      counter-clockwise, `open` the walkable bitmap; one fixture with seven walls.
    - `hit.jsonl`, **200 cases** (CBT-03a): the `Serde` of `(Hit, HitTarget)`, 28 felts, and of
      `HitOutcome` (`contracts/logic/src/types/hit.cairo`, its module documentation lists every felt).
      D-179 (`docs/decisions/2026-10-01-cbt-03a-hit-questions.md`) froze five readings; its point 5
      (a sleeping target neither blocks nor evades its first hit) **moves one vector at CBT-05a**.
  - CI's `contracts` job runs `python3 contracts/logic/vectors/check.py`: a committed table that
    differs from what the Cairo tests print fails. The tables are therefore always the code's.
  - `client/sim/src/exp2.ts`: the `2^(x/40)` table and its clamped lookup, written by
    `contracts/tools/exp2_table.py` for both sides (ENG-02a), checked by `--check` in CI.
  - `contracts/logic/src/fate.cairo`: `domain(subject, counter, purpose)` and
    `derive(word, domain, index)`, both `poseidon_hash_span` (ENG-01 §7). **No vector table** for
    them yet. `contracts/logic/src/packing.cairo`: `split`, `join`, `peel`, the lanes; **no vector
    table** either.
- **`client/sim` as it is**: `@grimworld/sim`, vitest 5.0.2, `src/index.ts` (a `clamp` placeholder),
  `src/exp2.ts` and its test. CI's `client` job runs `pnpm lint`, `typecheck`, `test`, `build` and
  `prettier --check client indexer` on **every pull request** (no path filter): a test of `client/sim`
  that reads `contracts/logic/vectors/*.jsonl` runs whenever either side changes. `@scure/starknet`
  1.1.0 is already in `pnpm-lock.yaml` (through starknet.js).
- **The mandate's §6** (ORCH-client-visual): every rule the chain decides is computed only in
  `client/sim`; no randomness and no clock in it; the renderer's view state is `client/app`'s and is
  produced from `client/sim`'s state by CLI-03.
- **Programme rule (pins on Linux only)**: every committed pin of a hash, a size or a checksum is
  generated and checked on Linux (the VPS or CI), never on the Mac. The Mac may run the tests.
- OPERATIONS.md §2 (models), §6 (the review, the few audits, D-177); `docs/briefs/COMMON.md`.

## The lots

| Lot | When | What | Profile | Gate |
|---|---|---|---|---|
| **CLI-02a** | **Now** | The parity harness, wired in CI; the mirror of what is merged: the window's geometry (ENG-02), one hit (CBT-03a), the table (ENG-02a); `domain` and `derive` (Poseidon) and the packing if their vectors are on `main` at launch; Poseidon timed | `impl-opus` | Review (`review`, Sonnet). No audit |
| **CLI-02b** | ENG-05 merged | The reveal of a chunk: the random word's use, generation with margins, edges and openings, bands, quotas, anchors, placement, D-134's void chunks; `derive` and packing here if CLI-02a could not take them | `impl-opus` | Review (`review`, Sonnet). Audit only if the reveal's vectors do not cover its branches (D-177) |
| **CLI-02c** | ENG-07 merged | The tick: movement, facing, the window's assembly (15 × 16), the action queue and its stop conditions, perception and the goblins' steps, the flood, the executor's hits (CBT-05a); **the full tick measured in TypeScript, Poseidon included** | `impl-opus` | Review (`review`, Sonnet) **and an audit**, determinism and cost (`audit`, Opus): the measurement is a result others depend on |

The profiles: the mirror is game logic written twice, with ties, signed felts and truncation where
the usual mistakes hide (OPERATIONS §2: game logic, Opus 5.5; PLAN names Opus 5.5). The review runs on
another model than the implementer's (Sonnet). D-177: CLI-02a and CLI-02b are rules as pure code
whose parity the vectors carry (with the mutation check), so the review is their gate; CLI-02c's
measurement of the full tick is "a cost or a determinism that only a measurement proves", and the
programme's choice of option (a) (D-140) rests on it, so it gets one audit. No lot needs the Mac:
all run on the VPS (Node 24, pnpm, and `snforge` for `check.py`).

## CLI-02a — the harness and the mirror of what is merged

### Agent
Title: `[Opus 5.5] CLI-02a sim parity harness` · Profile: `impl-opus` · Branch:
`cv/cli-02a-sim-parity` · Machine: the VPS

### Scope
- **In**:
  1. **The harness** (`client/sim/src/parity/`): a reader of the JSON-lines tables **in place** in
     `contracts/logic/vectors/` (no copy in `client/sim`: the tables are already checked against the
     code by `check.py`, so a copy would only add a second pin), the felt decoding (hex → `bigint`,
     signed `P − |v|`, `Option` as `[0, a]` / `[1]`, booleans, enums by index), and a replay that
     calls the mirror per table (and per `fn` where the table has one; `hit.jsonl` has none) and
     compares the whole `ok` array. It **fails loudly**: an unknown
     `fn`, a malformed line, an empty table, a table with fewer cases than a floor written in the test,
     a case that throws where Cairo returned, each fails the test with the case's `id`. If a table
     gains panicking cases later (an `err` field), the replay compares the thrown panic data; write
     the reader so that it accepts that field now.
  2. **The felt helpers** (`client/sim/src/felt.ts`): `P`, the integer types the mirror uses (`u8`,
     `u16`, `u32`, `u128`, `i32` as Cairo bounds them) with checks that throw where Cairo panics,
     truncating division, signed encoding.
  3. **The window's geometry** (`client/sim/src/window.ts`): every function of ENG-02's frozen
     `WindowTrait` that the table exercises (`inside`, `distance`, `sight`, `reach`, `arc`, `front`,
     `facing`, `shape`, `tiles`), `open` as a `bigint`, the line's tie rule (the lower tile index),
     `FAR` = 255 outside the window, a wall at either end blocking sight. Parity on **all 2,065**
     cases of `window.jsonl`.
  4. **One hit** (`client/sim/src/hit.ts`): `Hit`, `HitTarget`, `HitOutcome` and the resolution of
     design/19 §5.5–§5.6 as CBT-03a wrote it, on `exp2.ts`. Parity on **all 200** cases of
     `hit.jsonl`.
  5. **Fate and packing, if their vectors exist at launch**: `domain` and `derive` through
     `@scure/starknet`'s Poseidon (`client/sim/src/fate.ts`), the packing helpers the mirror needs
     (`client/sim/src/packing.ts`), each with parity on its table. If the tables are not on `main`
     when you start (question 2), leave both out, say so, and they move to CLI-02b.
  6. **The mutation check** (`client/sim/src/parity/mutants.test.ts`, as SPK-4's `mutants.ts`): at
     least 12 seeded mistakes, each a one-line change behind a flag, and the test fails if the
     vectors do not catch every one. At least: the line's tie taking the higher index; the arc's
     variant order; a wall at an end not blocking; `FAR` returned as the true distance; truncation
     replaced by floor on a negative modifier; modifiers applied in sequence instead of summed (D-140
     #3); armor not floored at 0; the hit not saturated; a signed felt decoded as unsigned; the
     table's clamp removed; the shape not clipped to the window; the facing turning on a tie the
     other way. A mutant that survives is not hidden: it is reported, and the missing cases are asked
     of track game (escalation), never added to the tables by this lot.
  7. **Poseidon timed** (no pin): `derive` per call in Node, median of repeated runs, with
     `@scure/starknet`'s version and the machine named, in the report. If `derive` is out of this
     lot (item 5), time `poseidonHashMany` on three felts alone and say so.
  8. **The package**: `@scure/starknet` as a direct dependency of `@grimworld/sim` (the version already
     in the lockfile); `src/index.ts` exports the mirror and drops the `clamp` placeholder (and its
     test); a short `client/sim/README.md`: what is mirrored, where the vectors come from, how to
     add a table.
- **Out**: `contracts/` (the tables and their tests are track game's, question 2); `client/app`
  (CLI-03 replaces the placeholders); any rule without a vector table; the chain and accounts
  (CLI-01); `.github/` (no change is needed: the `client` job already runs `pnpm test` on every pull
  request).
- **Allowlist**: `client/sim/**`; `pnpm-lock.yaml` for `@scure/starknet` only; `docs/reports/CLI-02a-*`
  (the report, archived by the orchestrator). Anything else is an escalation.

### Interfaces
- The mirror's functions keep the Cairo names and argument order of the vectors (`sight(open, from,
  to)`, `arc(source, target, facing)`, …), plain `number` for `u8` positions and facings, `bigint`
  for felts and bitmaps, so that CLI-03 can call them without a wrapper and a vector reads like a
  call.
- `Arc` is `0 Front, 1 FrontSide, 2 RearSide, 3 Back` (frozen with the vectors, PLAN CBT-03); a
  facing is `0..=5` from East counter-clockwise; a position is the window's index.
- A Cairo panic is a thrown `CairoPanic` carrying the panic data as Cairo's short strings, so that a
  future `err` field compares exactly.
- The harness's reader is one exported function, `readTable(name)`, used by every lot after this one.

### Acceptance criteria
- [ ] AC-1 The harness reads `window.jsonl` and `hit.jsonl` in place and fails loudly (a test per
      failure mode: unknown `fn`, malformed line, empty table, a count under the floor, a divergence
      reporting its `id`).
- [ ] AC-2 **Parity on all 2,065** cases of `window.jsonl`: 0 divergence.
- [ ] AC-3 **Parity on all 200** cases of `hit.jsonl`: 0 divergence.
- [ ] AC-4 If their tables exist: parity on every case of the fate and packing tables; otherwise the
      report says they moved to CLI-02b.
- [ ] AC-5 The mutation check: at least 12 mutants, every one killed, the table in the report.
- [ ] AC-6 Poseidon timed in Node on the VPS, with its command and real output; the replay time of
      each table and the mirror's gzip size, measured the same way. No figure committed as a pin.
- [ ] AC-7 `client/app` untouched; `@scure/starknet` the only dependency added, named in the PR.
- [ ] AC-8 The verification commands below pass; CI green.

### Verification
From the worktree root, on the VPS:
```
pnpm install --frozen-lockfile
pnpm --filter @grimworld/sim test
pnpm --filter @grimworld/sim lint
pnpm --filter @grimworld/sim typecheck
pnpm exec prettier --check client indexer
python3 contracts/logic/vectors/check.py          # the tables are the code's (snforge)
python3 contracts/tools/exp2_table.py --check
```

## CLI-02b — the reveal (when ENG-05 is merged)

- **In**: the mirror of ENG-05's reveal on the vectors ENG-05 prints (question 4): the random
  word's derivation (`derive`), generation with margins, edges and openings, bands, quotas, anchors,
  placement; D-134 (void chunks around every location and outside a zone's outline, a chunk's four
  corner tiles always wall, an unrevealed chunk is wall in the window: D-136); the packing of a
  chunk's words. `domain`, `derive` and the packing join here if CLI-02a could not take them. Mutants
  for each rule; the reveal's time per chunk in Node.
- **Allowlist**: `client/sim/**`, `docs/reports/CLI-02b-*`.
- **Acceptance**: parity on every case of the reveal's tables; mutants all killed; the time per
  chunk measured. Written in full when ENG-05's brief and vectors exist.

## CLI-02c — the tick and the measurement (when ENG-07 is merged)

- **In**: the mirror of ENG-07 and of the executor it calls (CBT-05a): movement and facing, the
  window's assembly (15 × 16, origin on an even global row, never clamped, void chunks as a constant;
  the location's axis orientation kept, as ENG-02's report asks of ENG-07), the action queue and its
  stop conditions, the instance clock, perception and the selection of at most 8 awake goblins, the
  flood capped at 15 layers (D-127: a walker beyond it holds), the hits of the tick; parity on the
  tick's tables.
- **The measurement D-140 asks for**: a full tick in TypeScript, Poseidon included, in Node on the
  VPS and in a browser worker (the Mac, `--machine mac`), on ENG-07's **worst tick** and on its
  **representative fight tick** (D-172); median and p95, cold first call, the mirror's gzip size;
  against SPK-4's 2.4 µs a primitive and the threshold of question 5: **10 queued actions (D-133)
  walked ahead within one 60 Hz frame (16.7 ms)**, in Node and in a browser worker. Measurements are reported, never
  committed as pins.
- **Allowlist**: `client/sim/**`, `docs/reports/CLI-02c-*`.
- **Audit**: determinism and cost (`audit`, Opus), once, on the measurement and the parity of the
  tick. Written in full when ENG-07's brief and vectors exist.

## Rules of every lot

- Foreground only; `gh pr checks <n> --watch --interval 30` in the foreground. Never merge.
- The mirror never edits a table, a digest or a Cairo test: a missing or wrong case is an escalation
  to track game through the orchestrator.
- No randomness, no clock, no I/O in `client/sim/src` outside the test files and the harness's
  reader (mandate §6).
- Pins on Linux only: if a lot commits a count, a checksum or a size, it is generated on the VPS or
  in CI.
- The pull request's body says why there is or is not an audit (D-177) and names every dependency
  added.

## Report

`REPORT.md` as in `docs/briefs/COMMON.md` §7, header `[<Model>] CLI-02<lot> — <title>`: the
summary and the pull request's URL; the files changed; the mirror's functions and the tables they
pass, with their counts; the mutation table; the measurements with their commands and real output;
the commands refused by the profile; deviations, escalations, open questions.

## Questions and their answers

Raised by this brief; answered by the project manager on 2026-10-02, or asked of track game.

1. **The lending.** **Decided**: `client/sim/**` is lent to track CV for CLI-02a, b and c;
   `contracts/` and `contracts/logic/vectors/` stay the game's. Reversed if a game lot must change
   `client/sim` (it then asks track CV).
2. **Fate and packing vectors** (`fate.jsonl`, `packing.jsonl` as tests of `grimworld_logic` and
   entries of `check.py`'s `TABLES`). **Asked of track game through the project manager.** Until they
   are on `main`, CLI-02a ships without Poseidon's parity and it moves to CLI-02b.
3. **Who updates the mirror when the game moves a vector.** **Decided**: a game pull request that
   moves a vector updates the TypeScript mirror itself when the change is a few lines; a new rule gets
   a paired CV pull request. CI couples the tables and `client/sim` once CLI-02a merges (the first
   case: CBT-05a's `hit.jsonl` vector, D-179 #5).
4. **The vectors of ENG-05 and ENG-07** (the reveal; a tick, the worst tick and D-172's
   representative fight tick among them; the flood, perception, the executor's hits; same JSON-lines
   format, checked by `check.py`). **Asked of track game through the project manager.**
5. **A threshold for the full tick.** **Decided**: 10 queued actions walked ahead within one 60 Hz
   frame (16.7 ms), in Node and in a browser worker. Re-checked on a phone when phone work
   resumes (phone work suspended by the owner, 2026-10-02).
6. **Enough hit cases?** SPK-4 validated parity on 10,000 vectors; `hit.jsonl` has 200. Open:
   CLI-02a's mutation check says whether they see every rule; if a mutant survives, the game is asked
   for more cases (an escalation through the orchestrator, not an edit by CLI-02a).
