# PENDING — the default zoom against the integer scale of pixel art

| | |
|---|---|
| Asked by | `[Opus 5.5] Orchestrateur client visuel (Mac)`, 2026-09-29 |
| For | The project manager; the choice is the owner's eye on CLI-03a's sandbox, then SPK-6 |
| Concerns | [ADR-0003](../architecture/ADR-0003-client.md) *Power budget rules*, [ADR-0006](../architecture/ADR-0006-chunked-maps.md) §5, CLI-03a ([#135](https://github.com/bal7hazar/grimworld/pull/135)) |

## The conflict

| Document | Says |
|---|---|
| ADR-0003, power budget rules | "Render at an integer multiple of the art resolution, capped at 2× device pixels" |
| ADR-0006 §5 | Default zoom: the sight hexagon fills the width, **13 tiles across**, about 30 points a tile at 390 points |

The art's tile is 64 px. At 13 tiles across on a 375-point phone, a tile is 28.8 points: the art is
drawn at **0.45×** (0.9 device pixels per art pixel at a device pixel ratio of 2). No integer multiple
fits: 1 device pixel per art pixel (0.5× at DPR 2) gives 32-point tiles, 11.7 tiles across, and the
sight hexagon no longer fits the width; the next smaller step (1/2 device pixel) gives 23.4 tiles
across, tiles of 16 points.

Found by the design audit of CLI-03a. A non-integer scale with nearest-neighbour sampling draws
uneven pixel columns that shimmer while the camera pans.

## What the sandbox will show

CLI-03a's fix loop adds an **integer scale** option (`?snap=1` and a toggle in the debug panel) beside
the continuous default, with the tiles across and the scale in device pixels per art pixel shown, so
that both can be compared by eye on the Mac and on a phone.

## Options

| | What | Cost |
|---|---|---|
| A | Keep 13 across, continuous scale (ADR-0003's rule relaxed for the world layer) | Shimmer while panning; sprites slightly soft |
| B | Integer scale, sight hexagon not fully in the width at the default zoom (about 11–12 tiles across at 1 device pixel per art pixel on a DPR-2 phone) | The adventurer sees less of the sight at a glance; one pan to see its edge |
| C | Integer scale, and the art redrawn or resampled once at a tile size that fits 13 across at 1× (about 58 px) | An asset step (ART), and the resampling of hand-drawn art that the owner just refused for heights (option B of PENDING-cv-art-heights) |

**Recommendation**: decide on the sandbox by eye, then confirm at SPK-6 on real phones; until then
the sandbox keeps A as its default and B one toggle away. No document changes before that.

## What would reverse it

The owner's eye on the sandbox, or SPK-6.
