# ADR-0006 — Large maps in chunks

| | |
|---|---|
| Status | **Accepted in principle by the owner on 2026-09-28**, revised the same day: every location is generated, chunk by chunk, at reveal. Costs to be validated by spike SPK-7; the rule of sight is provisional until the owner has tested it |
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

### 2. Everything is generated, at reveal (D-106)

Zones and dungeons use **one engine**. No location has a layout written in advance.

| | |
|---|---|
| When | A chunk is generated in the transaction of the move that brings it into sight |
| From | **A random word drawn in that transaction** (Fate), and the edges of the neighbours already generated |
| Stored | Per instance: terrain, occupied tiles, features, goblins |
| Revealed | For the whole instance; forgotten with it. Nothing about a map is remembered from one instance to the next |

#### Why generating on-chain is not enough for a fog of war

Nothing on a chain is private. If a map is derived from a seed that is **already stored**,
anyone can run the generator off-chain and read the whole map before walking into it:
generating "on-chain" hides nothing.

A fog of war exists only if the information **does not exist yet**. Hence the rule:

> The content of a chunk is decided by a random word that is drawn when the chunk is
> revealed, not before.

This corrects ADR-0002, which accepted that layouts could be read in advance.

| Cost of a real fog | |
|---|---|
| A reveal is a Fate action | It carries a randomness request, so it cannot be predicted by the client: the queue stops, and the chunk appears when the chain answers |
| How often | A few times per location, not at every step. It reads as discovery |
| Dependency | The random source is on the path of plain movement. If it is down, exploring stops; fighting in known terrain goes on |

### 3. Constraints without a plan

The fear is legitimate: generating chunk by chunk while honouring constraints on the whole
map ("exactly one exit", "three level-10 goblins for the quest", "nothing above level 5
here") looks like it needs a global plan, which would have to be drawn in advance and
would therefore be readable.

It does not, if constraints are restricted to **three kinds**, each resolved locally.

#### Kind 1 — Bands: true of every chunk

| Example | Resolved |
|---|---|
| "Easy zone: no goblin above level 5" | The chunk draws within the band. Nothing global |
| "This biome: caves, density 45%" | Same |

#### Kind 2 — Quotas: a number over the whole location

The same method as alchemy discovery ([design/07](../design/07-loot-and-alchemy.md)):
sampling without replacement.

```
at each reveal, for each quota still open:
    place one here with probability  (left to place) / (chunks left to reveal)
```

| Property | |
|---|---|
| Guaranteed | When the chunks left equal what is left to place, the probability is 1: **the last chunks hold what is still owed** |
| Unpredictable | Nobody knows in which chunk, since it is drawn at reveal |
| State | Two counters per quota |

| Example | Quota |
|---|---|
| The exit of a dungeon floor | 1 |
| The Heart of a Rift | 1, on the last floor |
| A stillstone vein | 1 per floor |
| Quest: "three goblins of level 10" | 3, added to the location while the quest is active |
| Guild contract: "six pack leaders" | 6, added while the contract is held |
| A collector's camp | 1 per zone |

#### Kind 3 — Anchors: a place known in advance, a content that is not

| Example | Resolved |
|---|---|
| "The outpost is to the north" | The registry says which chunk holds the gate. What surrounds it is generated |
| "Harder further from the gate" | Level within the band grows with the chunk's distance to the entrance, which is known at reveal |

An anchor is public, and that is fine: knowing that the outpost lies north is a map, not a
spoiler.

#### What is deliberately not supported

| Constraint | Why not |
|---|---|
| "A river crossing the whole zone" | A shape spanning chunks needs a plan |
| "The boss at the far end of a winding path" | Same. Distance to the entrance (kind 3) is the available approximation |
| "Exactly this pack composition across three chunks" | Quotas count; they do not arrange |

#### Joining chunks

| | |
|---|---|
| Edges | A new chunk **copies the edge** of each neighbour already generated, and draws its other edges |
| Openings | Every edge shared by two chunks inside the location has **at least one opening**. The first of the two to be generated decides where. All chunks are therefore reachable |
| Border of the location | Closed, except gates |
| Smoothing | Cellular passes on the chunk with its known margins |

**Generation of a board given its margins is added to the map library by its author**
(owner's decision).

#### Set pieces: where level design comes back

A quota can place an **authored chunk** instead of a generated one: a ruined village, a
collector's camp, a boss arena, drawn by hand and stored in the registry. The engine
places it, rotates nothing, and joins its edges like any other. Level design is not lost;
it becomes a library of pieces that the generator lays out.

#### Judgement on complexity

| | |
|---|---|
| The engine | One, for zones and dungeons: one system to build, test and audit |
| Difficulty | **Moderate, provided constraints stay within the three kinds.** The hard part is not constraints; it is joining edges and cost |
| What it costs the design | Zones can no longer be learnt or mapped by the community. A zone has a character (biome, band, set pieces), not a geography |
| Real risks | Cost of a reveal (generation + random request), and quality: generated open zones can feel samey. Set pieces are the answer to the second |

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
| A chunk is revealed | When sight touches it |

### 5. One rule of sight, two screens (R-7)

**What a player may know is set by the rules, in tiles. What a screen shows is comfort.**

| Principle | |
|---|---|
| Status | **Provisional.** The owner will rule after testing on a phone and a desktop |
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
| Reveal: random request + generation with margins + quotas + placement | A few times per location; up to 3 chunks in one move | The heaviest transaction of the game |
| Assemble the window | When it re-centres | 4 to 8 reads, shifts and masks |
| Tick | Each action | One flood on a 15 × 15 board, 8 goblins, two chunk writes per crossing |
| Storage | Per instance, for every location | Terrain, occupied, features per revealed chunk; discarded with the instance |

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
| CM-2 | Sizes, in chunks: zone 7 × 7, dungeon floor 3 × 3? |
| CM-6 | One random word per reveal transaction, shared by the chunks revealed together: confirmed by SPK-3 |
| CM-7 | Format of authored chunks and the tool to draw them |
