# D-173: `hexx` 0.1.0-rc.1 published on scarbs.xyz

| | |
|---|---|
| Decided by | `[Fable 5.1]` project manager, 2026-10-01, under D-132 as the owner narrowed it in the LIB orchestrator's session (release candidates delegated to the project manager; stable versions the owner's; to be confirmed by the owner to the project manager) |
| Asked by | `[Opus 5.5] Orchestrator — grimworld — LIB`, `hexx-cairo` `docs/decisions/PENDING-publish-hexx-0.1.0-rc.1.md` |
| The go | Written in that file by `hexx-cairo` #67, after the checklist of OPERATIONS §7 run by the project manager itself in a clean clone (its table is in the file): the commit on `main` with CI and the release check green on the sha; version and changelog at `0.1.0-rc.1`; `scarb package` from the clean checkout: 35 files, the same names, sizes and manifest as the release-check artifact, sha256 `9313e06b7b11282cb015f47af41fcd41a3162b627fb14b0734e35569f5ca1500`; no `hexx` on the registry; no regular dependency, `snforge_std` dev-only |
| Commit | `fe2b529de22db14ae29aa2072d75af10e50e4217` of `bal7hazar/hexx-cairo` |
| Published | 2026-10-01, by the orchestrator's session from a clean checkout; tag `v0.1.0-rc.1`, [release](https://github.com/bal7hazar/hexx-cairo/releases/tag/v0.1.0-rc.1) |
| Read back by the project manager | `https://scarbs.xyz/api/v1/index/he/xx/hexx.json`: version `0.1.0-rc.1`, cksum `sha256:9313e06b…1500` (equal to the go's), one dependency `snforge_std` of kind `test` |

## Content

The take-over of `origami_hexmap` 1.8.0, the mirror items of milestone L-M1, and the needs N-3
(assembly of the window), N-4 (`cut`), N-5 (line of sight), N-7 (directions, arcs, board
coordinates, distance), N-8 (the flood and the walkers' steps). Not in it: N-1 and N-2 (they wait
for the owner's decision on the chunk shape, D-165), N-6 (M1-T5, merged after Codex returns). The
library's part of a worst tick: 1.06M to 1.11M.

## What follows

- **ENG-02** (line of sight and arcs on the map library) may start: the game consumes `hexx`
  `0.1.0-rc.1` by published version (PLAN, track LIB: never by git revision).
- **M1-N9**: the library proves, on the artifact the registry serves, that a consumer builds it
  without `snforge_std` (N-9's real proof), after this publication.
- rc.2 (ENG-05's content: N-1, N-2) follows the owner's decision on the chunk shape.
