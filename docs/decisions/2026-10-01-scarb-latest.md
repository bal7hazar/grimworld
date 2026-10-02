# D-180: the drift tested on the latest Scarb before any issue; every repository on the latest Scarb

| | |
|---|---|
| Decided by | The owner, 2026-10-01, reading SPK-13's draft issue; recorded by the `[Fable 5.1]` project manager |
| Versions on 2026-10-01 | Pinned: Scarb 2.19.4, starknet-foundry 0.61.0 (`.tool-versions`). Latest published: Scarb **2.20.1**, starknet-foundry **0.64.0** (`asdf list all`) |

## Decided

1. **Before any issue is filed**, SPK-13 runs its minimal case (`spikes/SPK-13/minimal`,
   `reproduce.sh`) on the latest Scarb: if the drift is gone, the issue has no point and the
   draft is kept as a record; if it remains, the draft says so (versions tested) and the owner
   reads it again before the go. SPK-13 also reads the Cairo compiler's changelog between 2.19.4
   and the latest for a fix of `lowered_scc_representative` or the warm-up.
2. **Every repository migrates to the latest Scarb** (and the starknet-foundry that goes with it),
   a rule of the owner for the whole organisation, raised to the Overseer for the other projects.
   In this project: **FND-11** (grimworld: `.tool-versions`, `scripts/setup-toolchain.sh`, CI,
   the shims' expectations, starknet-devnet's compatibility with the classes of the new compiler;
   every gas budget and class-size snapshot re-measured, since a new compiler moves them, and
   written down), **LIB-04e** (`hexx-cairo`: the same, with its gas gate and parity table; a
   published version is not rebuilt: the next candidate carries the new compiler), **ARC-10**
   (`quiver`: the same; if a figure of `GAS.md` moves, the 0.2.0 publications carry it and say so).
   The migrations start after SPK-13's test, so that D-176's single-thread pin is kept or dropped
   with knowledge: kept if the drift remains on the latest Scarb.
3. Sonnet 5.5 for the three migrations (mechanical); the review as the gate; no audit (D-177).

## What would reverse it

The latest Scarb breaking a dependency (`snforge_std`, `origami`'s take-over tests) with no fix
within the lot: then the repository stays one version behind, said in the lot's report.
