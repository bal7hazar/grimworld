# D-xxx (number given at acceptance): an authored zone's on-chain format

| | |
|---|---|
| Proposed by | ENG-08 (track game), 2026-10-07 |
| Decides | The records, checks, draws and export of an authored zone (ENG-08's brief, deliverables 1–5) |
| Status | **Proposed**: its number is given by the project manager at acceptance |
| Builds on | D-214 (the owner: zones authored), D-215 (the project manager's rulings on ENG-08's questions), D-216 (the editor's grid laid afterwards, any chunk set at a chosen origin), D-217 (bridges on two levels), D-220 (the bound on a zone's draws), D-208, D-209, D-210, D-134, D-144, D-200; the orchestrator's rulings 2, 6 and 8 of ENG-08's brief |

## Proposed

1. **The records** (ENG-01 §3.5, *Authored zones*): `ZONE_CHUNK` (kind 26, `location × 256 +
   chunk`, 2 parts: the walkable plane; spawn points, objects, a candidate tile per quota, the
   bridge count, two anchored gates), `BRIDGE` (27, one felt a bridge: deck and two ends),
   `CANDIDATES` (28, each quota's candidate chunks, 3 parts), the `LOCATION` marker (bits 144–151:
   0 generated, 1 authored version 1). No record passes 3 parts: `bundle`'s bound holds. A later
   plane is a third part of `ZONE_CHUNK`, flagged in part 0's reserved bits.
2. **The checks** (ENG-01 §3.5, the table R-11 … R-35; `spikes/SPK-16-authored-zone/map-format/
   checks.json`): each rule between two records checked at the write of either, the reverse
   check of each named in the table (ENG-09 builds them; the spike prototypes the `CANDIDATES` and
   `PACK` ones, review t-0084); the editor
   reproduces the same table; the converter refuses the same cases and checks the pipeline's
   (reachability, seams, a deck connected).
3. **R-30**: a location's quotas draw at most 640 times together at entry (D-220; generated
   zones too, D-221), measured:
   ENG-05's worst legal plan with the snapshot's eight task quotas is 99,673,404, at 640 draws
   95,799,175. It binds generated zones too (ENG-R1c builds it).
4. **The draws at entry** (D-215 rulings 3 and 4): hosts among candidates from `domain(instance,
   226, REVEAL)`, spawn points' level and count from `domain(instance, 256 + chunk, REVEAL)`; no
   order of moves changes any of them. A snapshot's task quota places nothing in an authored zone.
5. **D-134's corners lifted for authored chunks** (ruling 5 applied: only the generation and
   `SetPieceAssert` read them).
6. **The authored path in a class of its own**, `AuthoredLibrary` (24.95 % in the spike); ENG-09
   after ENG-05b (D-209: `Instances` at 50.35 %; D-221).
7. **The export** `grimworld-export` version 1 (`schema.json`, the converter, the kind table owned by
   the schema from now on), promoted to `tools/map-format/` by ENG-09.

## Questions raised, and how they were decided

The project manager's rulings on Q1, Q2, Q4 and Q5 are **D-221** (2026-10-07); Q3 and Q6 stand as
the orchestrator's.

| # | Question | Decider | Recommendation | Decided |
|---|---|---|---|---|
| Q1 | R-30 at 640 draws: also a check of generated zones (ENG-R1c), since ENG-05's worst legal plan with tasks is 0.33 % under D-220's 100 M | project manager (D-220) | Yes, 640, in ENG-R1c's bounds; reversed by a measure that puts 672 + tasks well under 100 M after ENG-05b | **Decided (D-221)**: R-30's 640 draws bind generated zones too, built in ENG-R1c (its PLAN row) |
| Q2 | Water (and any wall) blocks sight on chain, though a player sees across it | project manager (ruling 1's condition) | Keep (walls block sight) for version 1; if playtests want sight across water, a sight plane as `ZONE_CHUNK` part 2 | **Decided (D-221)**: accepted for v1, recorded in design/18 as a known design limit ("in v1 a lake hides what lies beyond it"); a sight plane only if a playtest asks |
| Q3 | At most one candidate of a quota in a chunk (the layout holds one tile a quota a chunk) | orchestrator | Keep; the author marks another chunk; a second tile costs 48 more bits a chunk | **Stands** (the orchestrator's) |
| Q4 | A snapshot's task quota places nothing in an authored zone (its landmarks are the author's; a task naming a landmark the zone does not hold is reached nowhere) | project manager | Keep; tasks name landmarks the zone holds (content pipeline's check) | **Decided (D-221)**: kept |
| Q5 | ENG-09 waits for ENG-05b (D-209's condition on `Instances`) | project manager | Yes; else ENG-09 measures `Instances`' growth first and brings it to the project manager | **Decided (D-221)**: ENG-09 after ENG-05b; the PLAN rows ordered so |
| Q6 | The draws' domains use `REVEAL` with counters 226 and 256 + chunk, not a purpose of their own (a new purpose shifts `fate.jsonl` for track CV) | orchestrator | Keep; ENG-09 may add `fate:authored` if a review asks, with the vector shift announced to CV | **Stands** (the orchestrator's) |

## What would reverse it

A measure of ENG-09 beyond what the project manager accepts under D-144 (the expedition's path); a
rule of ENG-08b that needs a plane the format does not reserve; the owner's word on D-214.

## Sources

`docs/briefs/ENG-08-authored-zones-format.md`, `spikes/SPK-16-authored-zone/README.md`, ENG-01
§1.3, §3.5, §10; ADR-0006 as amended (D-214); design/18 v0.5.
