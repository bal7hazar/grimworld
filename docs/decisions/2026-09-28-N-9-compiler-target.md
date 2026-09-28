# N-9: the game cannot build the map library — arbitration

> **Void since D-123** (ADR-0007, the same day): the owner dropped Dojo; the game is on
> Cairo 2.19 and builds the library. Decisions 2, 3 and 4 below are cancelled. Kept for the
> record. What stays: `snforge_std` must be a dev-dependency of the library.

| | |
|---|---|
| Raised by | `[Opus 5.5]` game orchestrator, 2026-09-28, from `[Sonnet 5]` FND-01 (pull request #18); detail in [docs/needs/hexmap.md](../needs/hexmap.md), "N-9 in detail" |
| Arbitrated by | `[Fable 5.1]` project manager, 2026-09-28 |
| Left to the owner | The compiler target of the library, at gate L-G2, on the findings of LIB-03 (§3) |

## 1. Facts, checked

| | |
|---|---|
| The game's toolchain | Cairo 2.13.1, snforge 0.51.2: forced by Dojo 1.8 (`sozo` 1.8.7, `dojo_snf_test` 1.8.0), the newest published (SPK-5) |
| `origami_hexmap` 1.8.0 | The only published version. Its workspace asks `starknet ^2.19.4` and declares `snforge_std 0.61.0` as a regular dependency (`Scarb.toml` of `dojoengine/origami` at `04ab30c`) |
| Two failures | Version resolution next to `dojo_snf_test`; and, alone on Scarb 2.13.1, `core::internal::bounded_int::BoundedInt is not visible`, used by `map.cairo`, `helpers/bits.cairo`, `helpers/rng.cairo` |
| What was wrong in our documents | D-117 and D-119 said "the game consumes `origami_hexmap` 1.8.0 meanwhile". It never could |

## 2. Decided by the project manager

| # | Decision | Why |
|---|---|---|
| 1 | **The library must build with the compiler of its first consumer.** N-9 is a need of milestone L-M1: a published version that builds on the Cairo version Dojo imposes (2.13 today), with `snforge_std` as a dev-dependency | A library for Dojo games that a Dojo game cannot build answers no need. The dev-dependency is a defect whatever the compiler |
| 2 | **LIB-03 studies the compiler target before gate L-G2**: can the engine build on Cairo 2.13 (what replaces `BoundedInt`, at what cost in gas, with which results); one code base for 2.13 and 2.19 or two; CI on both; what it means for the crate `u252` | It is research, inside the porting plan already running. The answer is a fact to find, not a preference |
| 3 | **LIB-03 also prices one alternative**: the engine declared as its own class, compiled with the newer Cairo, and called by the game's systems through a library call | It is how the owner's physics game uses its engine. It would free the library from Dojo's compiler at the price of a call and a serialisation per use |
| 4 | **SPK-7 is not blocked**: it runs as a standalone package, outside the Dojo workspace, on Cairo 2.19.4 and snforge 0.61 (the machine's global toolchain), with `origami_hexmap` 1.8.0. Its report states that figures are measured on 2.19 and are orders of magnitude, to be measured again on the library's 2.13 release | SPK-7 answers "does the chunked map fit": algorithms, not storage. Waiting for a release would stop the game for a question a spike can answer now. Storage and the Dojo world are measured by SPK-2 on 2.13 |
| 5 | **The fallback of R-15 / R-18 is not triggered** (the game's own map code, rooms and corridors) | It would write in the game what the library exists for. It stays the fallback if gate L-G2 shows no release on 2.13 within the time of Phase 1 |
| 6 | **Waiting for a newer Cairo in Dojo is not a plan** | Nothing is announced; Katana 1.8 is still a release candidate. If it comes, the constraint relaxes by itself |
| 7 | ENG-02 and ENG-05 depend on the library's release that builds on the game's compiler (LIB-05), as the plan already says | Unchanged |

## 3. For the owner, at gate L-G2

With LIB-03's findings: the compiler floor of `hexx-cairo` (and of the crate `u252`), or the
separate class. Recommendation of the project manager today, before the findings: **a floor
at Dojo's Cairo, checked in CI**, unless the cost in gas of doing without `BoundedInt` is
high, in which case the separate class.
