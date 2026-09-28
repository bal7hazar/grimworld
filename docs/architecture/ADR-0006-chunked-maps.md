# ADR-0006 — Large maps in chunks

| | |
|---|---|
| Status | **Proposed** — the owner's requirement is accepted; the mechanism below is the orchestrator's proposal, to be validated by spike SPK-7 |
| Date | 2026-09-28 |
| Decides | How a location larger than one felt is stored, generated, simulated and shown |
| Supersedes | The room model of `docs/design/02-core-loop.md` (Map) and `docs/design/18-rooms.md` (size, entering a room, perception by room) |

## Requirement (owner, 2026-09-28)

| # | |
|---|---|
| R-1 | One room per felt was right for a prototype and is too small for the game |
| R-2 | Maps are large, of the order of **100 × 100** tiles, cut in **chunks** of about 15 × 15 |
| R-3 | A chunk is computed only when it becomes visible; in dungeons this gives a fog of war |
| R-4 | A chunk once loaded stays visible for the whole instance |
| R-5 | **Goblins cross from one chunk to another** |
| R-6 | The view is top-down with a camera that follows the adventurer |
| R-7 | Phone in portrait and desktop must not give an advantage to one over the other |

## Decision (proposed)

### 1. Three notions, one size

| Notion | What | Size |
|---|---|---|
| **Chunk** | Unit of **storage and generation** | 15 × 15 tiles = 225 bits, one felt per layer |
| **Window** | Unit of **simulation**: the board on which one tick is computed, centred on the adventurer | 15 × 15 tiles = one felt: what the map library handles |
| **Sight** | Unit of **information**: what the adventurer sees of the living world | A hexagon of **radius 6** around the adventurer, which fits in the window |

Coordinates are global: a tile is `(x, y)` in the location; its chunk is
`(x / 15, y / 15)`. A location of 105 × 105 tiles is 7 × 7 chunks.

### 2. Storage

| Layer | Per | Shared between instances |
|---|---|---|
| Terrain of a **fixed** location (zones) | Chunk | **Yes**: generated once by the first adventurer who sees it, read by everyone after |
| Terrain of a **shifting** location (nests, Rifts) | Chunk and instance | No |
| Occupied tiles, features | Chunk and instance | No |
| Goblins, adventurer | Entity, with global coordinates | No |

A chunk that has a terrain record is a chunk that has been seen (R-4): no separate
"explored" flag.

### 3. Generation

A chunk is generated **in the transaction of the move that brings it into sight**.
Moving diagonally near a corner can bring up to three chunks at once.

The library's generators build one closed board with a wall ring. Chunks must instead
**join without seams**, so that terrain and goblins continue across their edges. This
needs generation that depends only on **global coordinates and the seed**, not on the
order in which chunks are discovered:

| Step | |
|---|---|
| Base | For each tile, walkable or not from `hash(seed, x, y)` against the biome's density |
| Smoothing | Cellular passes, as the library's cave generator, computed on the chunk **plus a margin** of tiles taken from the base of its neighbours. Since the base is a pure function of coordinates, the margin does not need the neighbours to exist |
| Connectivity | Guaranteed per location, not per chunk: a registry-defined skeleton (paths between gates and landmarks) is carved on top |
| Placement | Packs and features of the chunk, from `hash(seed, chunk)` |

This is a **new capability for the map library** ("generation of a board given its
margins"), to specify with its author. Dungeons made of rooms and corridors can keep the
present generators, chunk by chunk, with openings carved on shared edges.

### 4. Simulation: the window

| | |
|---|---|
| Built from | The 1 to 4 chunks it overlaps: terrain and occupied tiles are cut and assembled into one board by shifts and masks |
| Edge | The outer ring of the window is treated as wall for the computation, as the library requires. Goblins there are 7 tiles from the adventurer |
| Pathfinding | One flood from the adventurer on that board, shared by all goblins (as before) |
| Awake | Goblins inside the window, at most 8: the nearest, ties by id. Others are frozen |
| Crossing chunks (R-5) | Free: a goblin has global coordinates. Moving writes the occupied bit of the chunk left and of the chunk entered |
| Re-centring | The window is stored and moves **only when the adventurer comes within 3 tiles of its edge**, so that it is not rebuilt at every step |
| Row parity | The window's origin stays on an even row, so that the hex neighbourhood of the library holds |

In the lore, this is the Hush: **things move near the living, and only there**.

Consequences for rules written earlier:

| Before (rooms) | Now |
|---|---|
| Only the current room is simulated | Only the window is |
| Goblins do not follow out of a room | They follow while the adventurer stays in their window; outrunning them is leaving it |
| The queue stops when entering a room | It stops when a new chunk is revealed, or when a goblin enters sight |
| Goblins at an entrance get a free attack on a fleeing adventurer | Dropped; fleeing is a matter of speed and terrain |
| The adventurer sees the whole room | The adventurer sees **terrain** of every revealed chunk, and **goblins within sight** (radius 6, line of sight not required) |

### 5. One rule of sight, two screens (R-7)

**What a player may know is set by the rules, in tiles. What a screen shows is comfort.**

| Principle | |
|---|---|
| Same information | Chunks revealed and goblins shown depend on the adventurer's position only: radius of sight 6, reveal of any chunk the sight touches. A larger screen shows **nothing more of the living world** |
| Sight is a hexagon | It fits in a square. A phone in portrait is limited by its width, a desktop by its height: **both show the same square**, and give what is left to the interface (below and above on the phone, left and right on the desktop) |
| Beyond sight | Revealed terrain, without goblins, dimmed. The phone reaches it by panning, the desktop sees more of it at once |
| No clock | The world waits. Panning and zooming cost nothing, so screen size changes comfort, not outcomes |

| | Phone, portrait | Desktop |
|---|---|---|
| Default zoom | The sight hexagon fills the width: 13 tiles across | The sight hexagon fills the height |
| Tile size | About 30 points at 390 points of width | Larger |
| Around the sight | Little | Remembered terrain |
| Gestures | Pinch to zoom, drag to pan, a button to re-centre | Wheel, drag |

Tiles of 30 points are under the 40-point target of the interface document. Answers, to
test in SPK-6: taps snap to the nearest valid tile; the preview (path, arc, range) is
always shown before the action is sent; a closer zoom level (9 tiles across) is one
pinch away.

No forced zoom is needed to equalise the two: the rule of sight already does it.

## Cost, unknown until measured

| Operation | When | To measure in SPK-7 |
|---|---|---|
| Generate a chunk with margins | On reveal, up to 3 in one move | Against the ~1.1M gas of a room today |
| Assemble the window | When it re-centres | 4 to 8 reads, shifts and masks |
| Tick | Each action | One flood on a 15 × 15 board, 8 goblins, two chunk writes per crossing |
| Storage of a location | Once for fixed zones | 49 felts of terrain for 7 × 7 chunks |

If the window's cost is too high, the fallback is a window of 11 × 11 with sight 5.

## What this changes elsewhere

| Document | Change |
|---|---|
| `design/02-core-loop.md` | Map and simulation budget sections follow this ADR |
| `design/18-rooms.md` | Becomes "terrain, features and perception"; sizes and "entering a room" are replaced |
| `design/11-interface.md` | The room view becomes a camera on the map; layout zones are unchanged |
| `design/04-combat.md` | Ranges are unchanged. Ranged range 6 equals sight |
| `design/01-world.md` | Locations are measured in chunks |
| Map library | Generation with margins; a helper to assemble a board from chunks; line of sight |

## Open

| # | Question |
|---|---|
| CM-1 | Chunk generation with margins: written in the map library, or in the game? Recommendation: in the library, by its author |
| CM-2 | Sizes of locations, in chunks: zone 7 × 7, nest floor 3 × 3, Rift floor 3 × 3? |
| CM-3 | Does revealed terrain of a fixed zone stay revealed for the adventurer across instances (a personal map), since the terrain is the same? Recommendation: yes |
