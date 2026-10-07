# ENG-10b — A dungeon floor's outline fixed at entry: the engine

> Written by ENG-10a (`spikes/SPK-17-fixed-outline/`, the design in ADR-0006 §3 *A dungeon floor's
> outline, fixed at entry* and ENG-01 §1.3, §3.2 and §10, all marked "ENG-10a, proposed"). PLAN's
> ENG-10b row: queued right after ENG-10a, ahead of CBT-05b and ENG-07.
> **The dungeon residue blocks any non-test deployment until this lot merges** (the Overseer,
> 2026-10-07; D-208's record, CONTEXT, OPERATIONS). **Its merge gate is a randomness re-audit that
> measures the residue at zero.** Decisions: ADR-0006 (D-106, D-111, D-120, amended by D-208, D-214
> and, proposed, ENG-10a), D-134, D-136, D-140, D-144, D-200, D-208, D-209, D-210, D-220, **D-223**
> (the project manager's rulings on ENG-10a's questions, 2026-10-07, below); pins on
> Linux only (OPERATIONS.md §3). Profile: impl-opus, the VPS (pins and measures).

## Decided before the lot starts (D-223, the project manager and the orchestrator, 2026-10-07)
| # | Ruling | By |
|---|---|---|
| 1 | **The winding growth is the law** (SPK-17's `draw_winding`: the member is the newest chunk with probability 1/2, else uniform). Uniform growth was measured and not kept | the project manager, D-223 |
| 2 | **The exit and the Heart among the outline's farthest chunks, laid on the spine's core**; ENG-05's "exit on any chunk" is superseded | the project manager, D-223 |
| 3 | **Sight reveals an outline chunk across a closed seam**, as in a zone (display only) | the project manager, D-223 |
| 4 | **D-144 accepted in principle**: this lot measures the entry that creates a floor on the node, tries the one-Poseidon-word-a-step lever first, and brings the figure to the project manager **before its merge** | the project manager, D-223 |
| 5 | **ENG-10b before ENG-05b**; the bound `N ≤ 12` is this lot's | the orchestrator |
| 6 | The merge gate: the zero-residue test on the real path (A1, A2) and the randomness re-audit | the Overseer; the orchestrator |

## Goal
After this lot a dungeon floor's chunks, the seams open between them and every quota's host chunks,
the exit's and the Heart's among them, are **drawn once at `create` from the entry draw and stored
with the instance**; a reveal reads them and draws none of them. **No order of moves changes which
chunks a floor holds, where its exit lands, or how far the exit is from the entry**: the residue of
#348's re-audits (t-0077, t-0082: the exit forced 1 chunk from the entry, up to `N − 2` closer) is 0,
and the re-audit measures it so.

## Context
- **The design** is ENG-10a's, in ADR-0006 §3 (*A dungeon floor's outline, fixed at entry*): read it
  whole first. SPK-17 is its working model: `src/outline.cairo` (the draw, the distances),
  `src/engine.cairo` and `src/engine/placement.cairo` (ENG-05's engine at `44961f2` with the
  changes marked `ENG-10a`), `src/library.cairo` (the classes), `tests/` (the zero-residue test, the
  negative control, the costs). Build from it; do not copy the spike's tests' fixtures into
  production without the repository's conventions (docs/CAIRO.md).
- **ENG-05 as merged** (`9ffd4ff`) and **ENG-08** (`44961f2`): `grimworld_logic::types::reveal`
  (`RevealTrait`, `Site`, `Progress`, `decide` and its guard), `reveal/placement.cairo` (`due`, `hosts`,
  `with_hosts`, `place`), `systems/hosts.cairo` (`HostsLibrary`), `systems/reveal.cairo`
  (`RevealLibrary`), `fate.cairo` (`EntropyTrait::word`, `hosts`), `contracts/ephemeral/src/systems/
  instances.cairo` (`begin`, `site`, `chunk_kind`, `instance_region`) and `store.cairo`.
- **The measured residue** (D-208's record): SPK-17's `test_residue_eng05` on ENG-05's merged engine
  puts the exit 1 chunk from the entry on 8 of 8 floors at `N` = 12, where the honest order put it at 7 to 11 chunks on five of them (45 chunks gained in all): the residue the gate removes.
- **The cost rules**: D-144 (every rise on the expedition's path, `enter` and `leave` included, is
  the project manager's before the merge); D-200, D-209 (`RevealLibrary` ≤ 50.5 %, `Instances` ≤ 51 %),
  D-210 (`HostsLibrary` < 50 %). The ENG-05 ceilings of ENG-01 §10 (*The D-144 ceilings of ENG-05*).
- **Lots nearby.** ENG-05b (bit-parallel placement, before ENG-07) also changes
  `reveal/placement.cairo`: ENG-10b goes first (D-223, ruling 5); ENG-05b merges it. ENG-R1c holds the content
  bounds (a floor's `N` at most 12 is this lot's, below). ENG-11 (dungeon room kinds) may change the
  winding law later: any law drawn at entry keeps the residue at zero.

## Scope
- In:
  1. **The draw** in `grimworld_logic` (`types/reveal/outline.cairo` or the module the code layout
     gives it, docs/CAIRO.md §7): the **winding** law (D-223, ruling 1: SPK-17's
     `draw_winding`), `far`, `distance` as SPK-17's; **the lever to try first** (ruling 4): draw each
     step from one Poseidon word instead of the `Rng` stream (an earlier SPK-17 build measured about
     2.50 M at `N` = 12 that way, uniform growth, against the stream's 2.80 M; not kept, not
     re-measured; the winding law measured 2,393,509 on the stream); the seed
     `EntropyTrait::outline(entropy, instance)` = `derive(entropy, domain(instance, 227, REVEAL), 0)`;
     the test that 227 is no other counter's word (SPK-17 `test_entropy_word_apart`).
  2. **`HostsLibrary`** gains the dungeon's call at `create` (`IHostsLibrary::floor`, as SPK-17's
     `FloorLibrary::floor`): the outline, its farthest chunks, the hosts (`PlacementTrait::hosts` with
     `far`: the exit and the Heart among the farthest), and the masks of the chunks the entry reveals
     with their hosts. The zone call is unchanged.
  3. **The engine**: SPK-17's changes marked `ENG-10a`, in `types/reveal.cairo` and
     `reveal/placement.cairo`: `Site.west`, `Site.north` (a dungeon's `chunk_set` its outline); a
     dungeon's chunk inside when in its outline, revealable as a zone's; a side toward an outline chunk
     not revealed open exactly when its seam is; no border drawn (ENG-05's draw kept, unread, so a
     zone's streams do not move), no guard (`grows`, `opens_growth`, `widen`, `faced_open` removed),
     open edges 0; `due` on hosts for both kinds; `place` lays a dungeon's exit, then its Heart, first,
     on `CORE` less the set piece's own tiles.
  4. **`Instances`**: `begin` calls `HostsLibrary::floor` in a dungeon (one call, as the zone block)
     and writes the outline's three felts (`outline`, `(slot, 0–2)`, ENG-01 §3.2 as proposed) and the
     hosts (`hosts`, as a zone's: a quota with a count only); every invocation that reveals in a
     dungeon reads the three felts into `Site` and sets each revealed chunk's hosts above its mask
     (`with_hosts`, from `get_hosts` of the current generation's quotas with a count, ENG-01 §3.2);
     `chunk_kind` and `instance_region` read a dungeon's outline (void outside it; not revealed inside);
     the `Quotas` word's open edges stay 0 in both kinds.
  5. **The content bound** `N ≤ 12` for a dungeon floor (CM-9; the registry's `LOCATION` check;
     D-223, ruling 5: this lot's), with its refusal test.
  6. **Tests** (docs/CAIRO.md §2, tests first): the zero-residue test (acceptance 1) at the logic
     level and through `Instances`; the dungeon tests of `types/reveal.cairo` that test the emerging
     outline (`test_dungeon_*`: enclosure, re-audit trace, sweeps, two edges, closes at N) replaced by
     the outline's properties (SPK-17 `test_outline_*`) and the engine's (every chunk of the outline
     revealed, edges equal to the seams); `test_lifecycle`'s dungeon entry; the vectors
     (`contracts/logic/vectors/reveal.jsonl`: `Site` gains two felts, so every line's input moves; a
     zone's outputs must not; regenerate and check with `check.py`; no TypeScript mirror of the
     reveal exists yet: `client/sim` mirrors `fate` only).
  7. **The documents**: ADR-0006 and ENG-01's "ENG-10a, proposed" marked built with the measured
     figures; D-208's record (the residue removed, with the re-audit's figure); PLAN's ENG-10b row;
     STATUS; GAS.md and `docs/BUDGETS.md` regenerated (`scripts/gas_budgets.py`).
- Out: the growth law's shape (ENG-11); the bit-parallel placement (ENG-05b); ENG-07's in-play
  reveal (it reads the outline as `create` does); authored zones (ENG-09).

## Files it touches (allowlist)
- `contracts/logic/src/types/reveal.cairo`, `contracts/logic/src/types/reveal/placement.cairo`, a new
  `contracts/logic/src/types/reveal/outline.cairo` (or its place under §7), `contracts/logic/src/fate.cairo`,
  `contracts/logic/src/systems/hosts.cairo`, `contracts/logic/src/interface.cairo` (`IHostsLibrary`),
  `contracts/logic/src/lib.cairo` if a module is added, their tests and `contracts/logic/tests/**`
  that test the reveal or the hosts.
- `contracts/ephemeral/src/systems/instances.cairo`, `contracts/ephemeral/src/store.cairo`, their
  models if the `outline` slot takes a typed slot, `contracts/ephemeral/tests/**` (lifecycle, cost).
- `contracts/persistent/src/**` only for the bound `N ≤ 12` (item 5), with its test.
- `contracts/logic/vectors/reveal.jsonl`, `contracts/logic/vectors/README.md`.
- `contracts/logic/GAS.md`, `contracts/*/GAS.md` and `docs/BUDGETS.md` as regenerated; the
  lifecycle probe's figures (`lifecycle_probe.py`, read-only use).
- `docs/architecture/ADR-0006-chunked-maps.md`, `docs/architecture/ENG-01-interfaces.md`,
  `docs/decisions/2026-10-03-eng-05-randomness.md` (D-208's record), PLAN's ENG-10b row, STATUS.
- Anything else is an escalation in the report.

## Acceptance criteria
| # | Criterion | Shown by |
|---|---|---|
| A1 | **The zero-residue test**, named `test_zero_residue` (split by `N` and by seeds as the build's memory needs, FND-23): for at least 8 entropies at `N` = 6 and at least 8 at `N` = 12, every order of the reveals among at least seven (by index, backward, nearest first, farthest first, two drawn, and **t-0077's forcing order**: the entry's first neighbour kept for the last reveal; review t-0088, minor 3), the entry first, gives **the same chunk set (the outline), the same exit chunk (exactly one exit, among the farthest), the same exit-to-entry distance through the revealed edges (the farthest distance), and the same edges in every chunk**; the walked distance in tiles from the entry tile to the exit's tile printed for every order (not compared: see the gate). On `RevealTrait` with the `Site` that `Instances` builds (its hosts from `HostsLibrary::floor`), not on a fixture that bypasses them | snforge, the test's output |
| A2 | The same through `Instances`: a dungeon instance created (`leave` to a floor, or the entry that creates one), its stored outline and hosts equal to the pure draw from its entry draw; its chunks revealed in two orders give A1's outcome | `contracts/ephemeral/tests/`, snforge |
| A3 | A zone is unchanged: every zone vector's output and every zone test's assertion unchanged; a zone's reveal gas within ±1 % (the kept draws) | `vectors/check.py`, the zone tests, GAS.md diff |
| A4 | The exit and the Heart always land (review t-0088, major 1; the orchestrator: their hosts drawn **first**, before every other quota, in the farthest layer with an allowed chunk, never owed): over the A1 entropies, one exit and one Heart on their host chunks, in the farthest layer; **and a fixture of its own in the zero-residue test: floors whose farthest layer is a single chunk, with a set piece (2 packs, 3 objects) listed before the exit and the Heart, both placed in every order** (SPK-17 `test_zero_residue_piece_*`); with a set piece hosted on the exit's chunk, the set piece's own elements keep their tiles; the Heart at the band's top | snforge |
| A5 | D-140: no panic on any legal content; a rectangle smaller than `N` gives the whole rectangle, connected | snforge (SPK-17 `test_outline_small_rectangle`) |
| A6 | Classes: `RevealLibrary` under its D-209 ceiling and expected under 50 % (SPK-17: 39,878 felts, 48.68 %, against 41,109), `HostsLibrary` under 50 % (SPK-17: 11,372 felts, 13.88 %, against 6,580), `Instances` under D-209's 51 %; measured by `class_sizes.py` on Linux | CI's class-artefacts, the report |
| A7 | Gas (D-223, ruling 4): the entry that creates a floor measured on the node (`lifecycle_probe.py`, three runs each), after the one-Poseidon-word lever is tried; the D-144 table below filled with those figures and sent to the project manager **before** the merge with the cause of each rise | the report, ENG-01 §10 |
| A8 | The documents of scope item 7 | the PR's diff |

## The re-audit gate (the merge gate)
A **randomness re-audit** (lens: randomness and determinism, Opus) of the PR's head, before the merge,
whose report states **in one sentence with a figure what a modified client can still gain in a
dungeon**: **zero in chunks** (no chunk, seam, host, exit chunk or exit-to-entry distance in chunks
that an order of moves changes) **and, in tiles, at most the measured bound** (review t-0088, minor
2: the openings' tiles on a seam are drawn by whichever of its chunks is revealed first, so the walked
distance from the entry tile to the exit's tile moves with the order: SPK-17 measured at most
TILES_X tiles over the required orders; the re-audit re-measures it on the real path and states it
as such, never as zero). A residue above zero in chunks stops the merge; the tile figure goes to
the project manager, who takes it to the Overseer. It checks: the seeds (227 for the outline, 225 for the hosts) read the entry
draw only and are computed once; nothing a reveal reads is written after `create` but by the reveal's
own chunk words; the exit's and the Heart's tiles are drawn from the chunk's word on `CORE` whatever
the seams; A1 and A2 test the real path. A verdict FAIL, or a residue above zero in chunks, stops the merge
(the Overseer, 2026-10-07).

## D-144: the rises it expects (E, from SPK-17; accepted in principle, D-223; the node's figures replace them before the merge)
| Entrypoint | ENG-05's ceiling | What moves | Expected |
|---|---:|---|---:|
| `leave` to a dungeon floor | 8,276,640 | `HostsLibrary::floor` (4.10 M in snforge), the outline's 3 slots and one `hosts` slot a quota with a count (about 0.48 M each when new), the entry reveal without the guard (less) | about +7.0 M when the slots are new: ≈ 15.3 M (E) |
| `enter` or `enter_rift` into a dungeon floor (a gate whose destination has `N`) | no dungeon figure (the probe's `enter` is the zone's) | the same | the same rise over its own figure, measured first |
| A reveal in play (ENG-07) in a dungeon | none yet | three slots read, the hosts' masks set; no guard | measured by ENG-07 |
| A zone's `create`, `enter`, `leave` | ENG-05's | nothing (the kept draws) | 0 (A3) |

## Measure first
Cairo builds and tests go through `scripts/lock.sh`, capped (`prlimit --as=8589934592`), with
`--max-threads 2` (SPK-17 aborted on an 8 GiB allocation without it); SPK-17's whole suite peaked at
2.15–2.22 GB resident (`/usr/bin/time -v`, two clean runs), 1 to 1.5 minutes. Keep generated tests small (FND-23): the zero-residue test is about 1.05 × 10⁹ L2 gas a
group of four floors of 12 in SPK-17; split it by seeds.

## Report
The repository's thread report, with: each acceptance criterion and its evidence; the class sizes;
the D-144 table with the node's figures; the re-audit's verdict and figure once it has run.
