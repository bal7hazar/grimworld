# ADR-0006 — Large maps in chunks

| | |
|---|---|
| Status | **Accepted in principle by the owner on 2026-09-28**, revised the same day (and again by D-120: the window follows the adventurer, is 15 × 16 and is not stored): every location is generated, chunk by chunk, at reveal. Costs to be validated by spike SPK-7; the rule of sight is provisional until the owner has tested it. **Amended by the project manager, 2026-10-03 (D-208)**: §2's fog and what feeds the value, §3's quotas, as ENG-05 builds them. **Amended by the owner, 2026-10-05 (D-214), for zones only**: zones are **authored** with the map editor and held in the registry; dungeons stay generated; the format is ENG-08's (D-215, the project manager's rulings; `docs/decisions/2026-10-07-authored-zones-format.md`, proposed). **Amendment proposed by ENG-10a, 2026-10-07 (D-208's PLAN item; its design choices ruled by the project manager, D-223 and D-224; built by ENG-10b): a dungeon floor's outline is drawn at entry** (§3 *A dungeon floor's outline, fixed at entry*), which removes §3's dungeon exception and the residue of #348's re-audits |
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

### 1. Three notions

| Notion | What | Size |
|---|---|---|
| **Chunk** | Unit of **storage and generation** | 15 × 15 tiles = 225 bits, one felt per layer |
| **Window** | Unit of **simulation**: the board on which one tick is computed. It **follows the adventurer** and is **never stored**: it is assembled from the chunks at each tick (D-120) | **15 columns × 16 rows** = 240 tiles, one felt (the library's limit is 251) |
| **Sight** | Unit of **information**: what the adventurer sees of the living world | A hexagon of **radius 6** around the adventurer, **always inside the ring of the window**, wherever the adventurer stands |

Coordinates are global: a tile is `(x, y)` in the location; its chunk is
`(x / 15, y / 15)`. A location of 105 × 105 tiles is 7 × 7 chunks.

The window does not have the size of a chunk, and need not: it shares the chunk's **width**,
which is what makes assembly a one-dimensional shift (§4).

### 2. Everything is generated, at reveal (D-106)

> **Amended by the owner, 2026-10-05 (D-214), marked D-214 and D-215.** This section, and D-106,
> now hold for **dungeons only**. A **zone is authored**: drawn with the map editor (TOOL-01,
> CLI-09), exported, converted and written to the registry as one `ZONE_CHUNK` record a chunk (its
> walkable plane and its features), with the zone's `CANDIDATES` and its `OUTLINE` (ENG-01 §3.5,
> proposed by ENG-08, built by ENG-09). At reveal an authored chunk's walkable plane is **copied**
> into the instance's chunk (D-215 ruling 2), not generated; what stays random is drawn at entry
> (§3, *Quotas*, as amended). Towns are drawn with the same editor and stay client-only (D-03,
> D-202). Until every zone is authored, a zone without the `LOCATION` marker is generated as
> below (D-215 ruling 7). The fog of an authored zone holds no terrain: the map is public
> before any instance, as the world map is (D-213's display rule unchanged).

Dungeons use **one engine**; until D-214 zones did too. No dungeon has a layout written in advance.

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
| A reveal is a Fate action (option A, **not retained**) | It carries a randomness request, so it cannot be predicted by the client: the queue stops, and the chunk appears when the chain answers. Under the decided option C (D-111) a reveal is computed: the client predicts it and it can ride in a batch (D-133) |
| How often | A few times per location, not at every step. It reads as discovery |
| Dependency | The random source is on the path of plain movement. If it is down, exploring stops; fighting in known terrain goes on |

#### Where the random word comes from (D-111: option C)

| | A. Verifiable random function | B. **Player entropy** (owner's idea) | C. Entry draw + player entropy |
|---|---|---|---|
| Source | A random word requested at each reveal | A value accumulated from the adventurer's **irreversible** actions in the instance | One verifiable draw when entering; inside, B seeded by it |
| Can the next chunk be read in advance? | **No** | **Yes, one chunk ahead**, by a modified client: the value is on-chain, the generator is public | Same as B |
| Can the instance be chosen before entering? | No | Yes: the starting value is known | **No** |
| Can the next chunk be steered? | No | Yes, at the price of playing badly | Same as B |
| Reveal on screen | Waits for the chain | **Instant**: the client computes it | Instant |
| External dependency while exploring | Yes | **None** | None after entry |
| Cost of a reveal | Generation + request | Generation | Generation |

**Rule of option B.** Only what cannot be undone or repeated for free feeds the value:

| Feeds the value | Does not |
|---|---|
| A goblin killed (which one) | Moving, turning, going back and forth |
| Health lost | Waiting |
| A consumable used | Using a skill out of combat (energy comes back by waiting) |
| Remains looted, a chest opened, a vein mined | The tick count, the position |
| ~~The chunk revealed and the side it was entered from~~ (amended, D-208: no reveal feeds the value) | The order of two actions that lead to the same state |

The value is a **set**, not a sequence: killing A then B gives the same value as B then
A, so that order cannot be used as free choice.

**What B cannot give.** The world waits: a program has all the time it needs to try, off
chain, every irreversible option within reach and keep the one that leads to the best
next chunk. The number of cheap options is small but not zero (leave this goblin asleep or
kill it; take this hit or not; loot now or later). Steering is made **costly, not
impossible**, and reading one chunk ahead is free.

**Why it may still be the right choice.** What a better chunk is worth is bounded by the
design: five Rifts a day per account; loot, identification and alchemy stay on
verifiable randomness, so rewards cannot be steered; nothing is competitive. Against that:
instant reveals, and exploration that depends on nobody.

**Decision (owner, 2026-09-28): C, for now.** Reading one chunk ahead is accepted. A
better scheme in the same spirit, a value fixed in advance but tied to gameplay, will be
looked for as features settle. In the MVP the draw at entry uses the provisional source
of ADR-0002.

One draw when entering, which is a moment where waiting
is natural and which prevents choosing one's instance; player entropy inside. The fog of
war is then a fog **for honest clients and one chunk deep for the others**, stated as
such. D-107 ("must resist reading the chain") is met for everything beyond the next chunk.

> **Amended by the project manager, 2026-10-03 (D-208).** As ENG-05 builds it (audit of #348,
> major 1): **no reveal feeds the value**, and no production feeder exists yet, so every chunk's
> word is fixed at entry: `derive(entropy, domain(instance, chunk, REVEAL), 0)`, the entropy being
> the entry draw. The fog is **0 chunks deep** for a client that reads the chain: the whole
> location, its terrain and its contents, is readable from the entry draw on. What it buys: no
> order of moves, no side entered and no reveal changes any chunk, so the order is no free choice
> (only what §3's dungeon exception keeps). A later feeder (a kill, a chest, in their lots) must
> make its facts unique, and changes the words of the chunks revealed after it.

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

> **Amended by the project manager, 2026-10-03 (D-208): the quota distribution as built (ENG-05).**
>
> | | Zones | Dungeons |
> |---|---|---|
> | Where a quota lands | Its **hosts**: `count` members of the zone (its chunk set, or its rectangle), drawn **once at the instance's start** by their own library class, `HostsLibrary` (D-210): an exact draw without replacement from the entry draw (`derive(entropy, domain(instance, 225, REVEAL), 0)`, the word of no chunk) over the quota's **allowed** members, those its kind would not push past a chunk's caps (3 objects, 2 packs, one set piece, a set piece's own objects and packs counted); **no cap on the draws**: a quota stops when it has its hosts or no allowed member is left (a determination of the caps). Above half the allowed members, the members to leave out are drawn instead (D-220), the same uniform law. One bitmap per quota, kept with the instance | Hit or forced: each chunk draws `u` in `[0, N)` from its own word; the quota is due when `u < count` and something is left |
> | Guarantee | Every host can lay its quota (the caps are respected at the draw; a pack, the Heart's included, holds at least one goblin); **nothing is ever forced on the last chunks**. A quota with fewer allowed members than its count keeps fewer hosts, and **the rest stays owed for good, never placed**; a set-piece quota whose piece is not in the registry stays owed; a host whose chunk has no allowed tile left (its terrain, unknown at entry) does not lay it | **Forced** when what is left reaches the chunks left: the last chunks hold what is still owed; never more than `count` |
> | Order of moves | **Free of it**: the hosts are fixed at entry and a chunk holds exactly the quotas it hosts, so no order chooses where a zone's quota lands | Depends on it: the forced window (at most the last `count` chunks), a quota whose draws hit more chunks than its count (the first revealed take it), and which chunk is the `N`-th |
> | State | Left to place, per quota; the hosts | Left to place, per quota; the revealed count |
>
> **The dungeon exception and its reason.** A dungeon's outline emerges from the order of the
> moves (option (i), D-111): its chunks are not known before they are revealed, so no host can be
> drawn at entry. Its quotas stay order-dependent, **a dungeon exit's position with them**,
> accepted as the dungeon's nature (D-208). A Heart's pack takes the band's top level wherever it
> lands, so that steering it near the entry does not lower the boss. A fixed dungeon outline at
> entry, which would remove the exception, is a design change on the project manager's plan.
>
> **ENG-10a (proposed; ENG-10b builds it).** The exception goes: a floor's outline, its exit and
> its quotas' hosts are drawn once at entry (*A dungeon floor's outline, fixed at entry*, below), so a
> dungeon's quotas take the zone column of this table (hosts, never forced; the exit and the Heart
> among the outline's farthest chunks), and no order of moves chooses where the exit lands or how far
> it is from the entry.

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

#### Outlines

> **D-214, D-215 (ruling 6).** An authored zone keeps this table's zone column: its chunk set and
> its border chunks' tile masks in `OUTLINE`, no other outline record. The converter derives both
> from the painted map (the editor lays the 15 × 15 chunk grid afterwards, at an origin on an even
> row, D-216) and the registry refuses a mask that disagrees with the chunk's walls (R-20). "Cut by
> its mask" becomes: every tile outside the mask is a wall in the authored plane.

| | Zones | Dungeons |
|---|---|---|
| Outline | **Drawn in advance**, in the registry: an irregular shape, any size | **Emerges** during exploration |
| Known before entering | Yes: the map of the world can be drawn from the outlines of all zones, without knowing what any of them contains | No |
| Stored as | The list of chunks of the zone; for each chunk on the border, a **mask** of the tiles that belong to the zone (one felt) | A target number of chunks `N`, by grade: **6 to 12** |
| At reveal | The generated chunk is cut by its mask; what is outside is impassable | Each free edge of the new chunk is a border with a probability (initially 1 in 7), except where a neighbour already decided |
| Gates | Anchors on the outline | The entrance; the exit is a quota |

Rules that keep an emerging outline sound:

| Rule | Why |
|---|---|
| An edge facing an existing neighbour copies that neighbour's decision: open if it is open, border if it is border | Consistency |
| While fewer than `N` chunks are revealed, the last open edge of the frontier **cannot** be drawn as a border. *Amended (D-208, as ENG-05 builds it): a chunk with a side it can open always keeps one open toward a chunk that can still grow; a side its mask cuts whole is never opened* | The dungeon cannot close before it is complete (but when `N` equals its rectangle's area, the last chunks can be walled in: a content rule is proposed) |
| When `N` chunks are revealed, every remaining open edge becomes a border | The dungeon ends |
| Quotas count on `N` | "Chunks left to reveal" stays a known number, so guarantees hold |
| State | Revealed count, open-edge count |

> **ENG-10a (proposed; ENG-10b builds it).** A dungeon's outline no longer emerges: it is drawn at
> entry (below). The table above and its rules hold until ENG-10b merges; after it, the dungeon
> column reads: *Outline* drawn at the instance's entry, from its entry draw; *Known before entering*
> no (it is drawn at entry, a new one each instance); *Stored as* `N` in the registry, and per instance
> the floor's three felts and its hosts; *At reveal* each side toward a chunk of the outline is open exactly when its
> seam is, every other side closed; *Gates* the entrance, and the exit a quota on a chunk drawn at
> entry. The rules that keep an emerging outline sound have nothing left to keep: a drawn outline
> holds its `N` chunks, connected, before the first reveal.

#### A dungeon floor's outline, fixed at entry (ENG-10a, proposed; D-223, D-224; ENG-10b builds it)

The measured residue (#348's re-audits t-0077 and t-0082, D-208's record): with the outline emerging
from the order of the moves, a modified client keeps a neighbour of the entry for the `N`-th reveal,
where the exit still owed is forced, and puts the exit **1 chunk** from the entry, up to `N − 2` = 10
chunks closer than the worst honest floor at `N` = 12. It blocks any non-test deployment until
ENG-10b merges (the Overseer, 2026-10-07). SPK-17 reproduces it on ENG-05's merged engine
(`test_residue_eng05`, below) and removes it.

| | |
|---|---|
| **The rule** | A dungeon floor's chunks, the seams open between them, and every quota's host chunks, the exit's and the Heart's among them, are **drawn once at the instance's entry**, from its entry draw alone, and stored with the instance. A reveal reads them and draws none of them. The chunk set, each seam, each host, the exit's chunk and tile and its distance from the entry are then functions of the entry draw: **no order of moves changes them** |
| **The draw** (`spikes/SPK-17-fixed-outline/src/outline.cairo`) | Seed `derive(entropy, domain(instance, 227, REVEAL), 0)`, the word of no chunk (0–224), nor of ENG-05's hosts (225), nor of an authored zone's (226, SPK-16); its draws one `hexx` `Rng` stream, as a chunk's placement. The floor starts as its entry chunk and grows one chunk at a time until it holds `N` (or its whole rectangle, when smaller: D-140): at each step a **member** of the floor (**winding**, D-223: the newest chunk with probability 1/2, else uniform by its rank in the order added) and a **side** (uniform of 4) are drawn, and the chunk beyond is kept when it is in the rectangle and not in the floor (each frontier chunk weighted by the floor's sides facing it), up to 16 pairs, then the exact draw, uniform over the frontier. The member is the new chunk's **parent**: their seam is open, so the floor is connected; each other seam toward the floor is open but with probability 1 in 7, ENG-05's law of a dungeon's side (`BORDER`) |
| **Distances** | A walk from the entry through the open seams, a layer a step (bit-parallel: a layer is a bitmap). The **farthest** chunks are its last layer |
| **The exit and the Heart** (D-223) | **ENG-05's "exit on any chunk" is superseded.** Their hosts are drawn as a zone's (`PlacementTrait::hosts`, D-208, D-210, D-220: an exact draw without replacement, the caps respected, seed `derive(entropy, domain(instance, 225, REVEAL), 0)`), but **first, before every other quota**, so that no cap blocks them (review t-0088, major 1; the orchestrator, 2026-10-07: a set piece of 2 packs or 3 objects listed before them, hosted on a farthest layer of one chunk, would otherwise leave them no host), **in the farthest layer that has an allowed chunk**: the farthest; if it cannot take them, the next farthest, and so on, the entry's layer left out (review t-0089, note 4): **never owed for a count of 1**, the count of both in every floor's content. The other quotas (a vein, a set piece, the tasks' landmarks) follow in their order, among the whole outline. In its chunk the exit, then the Heart, is laid **first**, before a set piece's own packs and objects, on a tile of the spine's **core** (rows and columns 3 to 11 of row 7 and column 7, 17 tiles) less the set piece's own tiles: the spine is floor in every generated chunk and the core is at least 3 tiles from the ring, so no opening comes within 2 of it whatever the seams, and no layer drawn from is the entry's (its anchor). Both always land, on a tile drawn from the chunk's word: no order moves it. A Heart keeps the band's top level (D-208) |
| **Stored** (ENG-01 §3.2) | **Three felts** a floor, `outline` `(slot, 0–2)`: its chunks (bit `15 cy + cx`), its open seams West (bit `c`: between `c` and `c + 1`) and North (bit `c`: between `c` and `c + 15`); and its hosts **as a zone's**, one `hosts` slot a quota with a count. Written at `create` (every entry that creates a floor), read by every invocation that reveals in a dungeon. Two felts would hold it all (the seams and the hosts by the chunks' rank in the outline, a floor having at most 12 chunks), but packing and unpacking cost more than the slots they save (measured, ENG-01 §10) |
| **Class** | The draw at `create` joins `HostsLibrary` (D-210), called once at `create` in a dungeon as in a zone with a quota: the outline, its farthest chunks, the hosts and the entry reveal's masks in one call. The reveal's dungeon code shrinks: no border drawn, no frontier, no guard. Measured in SPK-17's build (ENG-01 §1.3) |
| **A reveal** | A dungeon's chunk is **inside** when it is in its outline, and **revealable as a zone's is**: inside and not revealed, sight reveals it (no "faced by an open edge"). A side toward an outline chunk not yet revealed is open exactly when its seam is; toward any other chunk closed; toward a revealed chunk copied, as before. A dungeon's quotas are due on their hosts (the mask word's bits `225 + i`, set from the stored hosts as a zone's are, `PlacementTrait::with_hosts`), never forced. The open edges and the frontier's guard are gone. The bands keep their law (`d` the chunk's distance in chunks to the entry, `D = N − 1`) |
| **The fog** | Unchanged in substance: since D-208 every chunk's word is fixed at entry and readable ("0 chunks deep" for a client that reads the chain). The outline adds nothing such a client could not already compute; an honest client shows a chunk when sight touches it, as in a zone. What changes is display only: a chunk of the outline beyond a closed seam is revealed when sight touches it, as a zone's chunk is (accepted, D-223) |

**What stays random, and why it is order-free.** The draws of the outline, of the seams and of the
hosts read the entry draw only. Every chunk's word reads the entry draw only (D-208), so its base, its
smoothing seed, its quotas' stream and its placement stream are fixed at entry too. **D-224 (the
project manager, 2026-10-07): each open seam's openings (1 or 2, which tiles) are drawn from the
seam's own stream**, `Rng` seeded with `poseidon(outline seed, the seam's lower chunk, its axis)`,
fixed at create, so both chunks of a seam draw the same tiles whichever is revealed first, and the
second's copy of the first's ring is what it would draw itself. Before D-224 the first chunk revealed
drew them from its own stream, and through them the floor's tiles near the seam and the placements'
tiles moved with the order (the residue in tiles, below); with it, nothing a reveal reads moves with
the order. **How they are kept**: SPK-17 derives them from the outline's seed at each reveal (no slot,
no cost at create, one `Rng` a dungeon side opened: measured in ENG-01 §10); D-224 says "stored with
the outline". The two give the same tiles; storing them is ENG-10b's to measure if the project
manager keeps it (an open question of ENG-10a's report).

**The zero-residue test** (deliverable 2, ENG-10b's merge gate): for a set of entropies and `N` in
{6, 12}, every one of seven orders of the reveals (by index, backward, nearest first, farthest first,
two drawn, and **t-0077's forcing order**, the entry's first neighbour kept for the last reveal; review
t-0088, minor 3), the entry first, gives the same chunk set (the outline), the same exit chunk and
Heart chunk (one each, in the farthest layer), the same exit-to-entry distance in chunks through the
revealed edges (the farthest distance), and the same edges in every chunk. SPK-17's
`test_zero_residue_*` passes it on the changed engine: 16 floors, and 6 more whose farthest layer is
one chunk with a set piece of 2 packs and 3 objects listed before the exit and the Heart (review
t-0088, major 1), 154 orders in all. **The same comparison with the same seven orders fails on
ENG-05's merged engine** (`test_zero_residue_on_eng05_*`, `N` = 12, four floors: 5, 5, 5 and 6 of
the six other orders differ from the first). There, t-0077's forcing order (keep the entry's first
open neighbour for the `N`-th reveal, avoid the chunks whose draw hits the exit) puts the exit **1
chunk** from the entry on **8 of 8** floors, where the honest order (the lowest revealable index
first) put it at 11, 7, 10, 11 and 11 chunks on five of them, **45 chunks gained in all**, and at 1 on
the other three (`test_residue_eng05`). The forcing order is free: no kill, no health, no item.

**The residue in tiles** (review t-0088, minor 2; D-224): **zero in chunks and in tiles (D-224).**
SPK-17's zero-residue test asserts the walked distance from the entry tile to the exit's tile (a
breadth-first walk on the revealed floor) equal in every order: on the 22 floors, 7 orders each, it
is. **Measured without D-224** (the openings drawn by whichever chunk of a seam was revealed first,
SPK-17 at `a2d740b`): at most **24 tiles** over 22 floors and 7 orders (73 to 97 tiles on one floor of
12), the spreads 1 to 24, the walks 29 to 124 tiles: a sample, not a bound, kept as the residue of the
design without D-224. ENG-10b re-measures on the real path.

**The shape this draw gives** (SPK-17 `test_outline_*`, 64 entropies each). **The law is the
winding growth** (D-223, the project manager, 2026-10-07; SPK-17's `draw_winding`): the farthest
distance, where the exit lies, is 2 to 5 chunks at `N` = 6 (mean 3.38) and 3 to 9 at `N` = 12 (5.16),
for 2,393,509 L2 gas at `N` = 12 (ENG-01 §10). **Uniform growth was measured and not kept**: 2 to 5
at `N` = 6 (2.81), 2 to 6 at `N` = 9 (3.56), 3 to 6 at `N` = 12 (4.20), compact floors, 2,801,446 at
`N` = 12. A corridor or room layout proper is ENG-11's (dungeon room kinds). **Any law drawn at
entry keeps the residue at zero.**

#### Joining chunks

| | |
|---|---|
| Edges | A new chunk **copies the edge** of each neighbour already generated, and draws its other edges |
| Openings | Every edge shared by two chunks inside the location has **at least one opening**. The first of the two to be generated decides where. All chunks are therefore reachable |
| Border of the location | Closed, except gates. Beyond it lies a **margin of void chunks**: wall everywhere, never revealed, never stored (D-134) |
| Corners | **The four corner tiles of a chunk are always wall** (D-134): chunks connect through their edges only, so a reveal never depends on a diagonal neighbour |
| Smoothing | Cellular passes on the chunk with its known margins |

**Generation of a board given its margins is added to the map library by its author**
(owner's decision).

#### Set pieces: where level design comes back

> **D-214.** In a zone, level design is the whole map: a zone has no set-piece quota (R-29). Set
> pieces stay a dungeon's: a `SET_PIECE` record (one authored chunk, D-134's corners kept), drawn
> with the same editor and exported as `kind: set_piece` (ENG-08's export, CM-7).

A quota can place an **authored chunk** instead of a generated one: a ruined village, a
collector's camp, a boss arena, drawn by hand and stored in the registry. The engine
places it, rotates nothing, and joins its edges like any other. Level design is not lost;
it becomes a library of pieces that the generator lays out.

#### Judgement on complexity

| | |
|---|---|
| The engine | One, for zones and dungeons: one system to build, test and audit |
| Difficulty | **Moderate, provided constraints stay within the three kinds.** The hard part is not constraints; it is joining edges and cost |
| What it costs the design | ~~Zones can no longer be learnt or mapped by the community.~~ **Reversed by D-214 for zones**: an authored zone has a geography the community can learn and map; its quotas' places (among the author's candidates) and its packs' levels and counts change with each instance (D-215). Dungeons keep this row: a character (biome, band, set pieces), not a geography |
| Real risks | Cost of a reveal (generation + random request), and quality: generated open zones can feel samey. Set pieces are the answer to the second |

### 4. Simulation: the window

| | |
|---|---|
| Built from | The 2 to 4 chunks it overlaps (16 rows always span two rows of chunks): terrain and occupied tiles are cut and assembled into one board. **No loop over rows** (docs/CAIRO.md): for each chunk overlapped and each layer, one mask taken from a table of constants, then one shift by multiplication or division by a power of two; window and chunk share the width 15, so moving a chunk by `(dx, dy)` is a shift by `15·dy + dx`; the pieces are disjoint and are added |
| Position | **Columns**: the adventurer is on the centre column (7 of 0…14), 7 columns from the ring on each side. **Rows**: the origin of the window must be on an even global row (below), so the adventurer is on local row **7 when its global row is odd, 8 when it is even**. Rows 1 to 14 are inside the ring: sight (13 rows, 13 columns) always fits |
| Edge | The outer ring of the window is treated as wall for the computation, as the library requires. A tile of the ring is 7 tiles or more from the adventurer: **never in sight** |
| Pathfinding | One flood from the adventurer on that board, shared by all goblins (as before), computed on the occupancy frozen at the start of the tick, and **stopped at 15 layers** (D-127): on a winding board a goblin 7 tiles away can be 45 steps away on foot, and a layer costs about 19k. A goblin not reached holds its position |
| Awake | Goblins inside the window, at most 8: the nearest, ties by id. Others are frozen |
| Crossing chunks (R-5) | Free: a goblin has global coordinates. Moving writes the occupied bit of the chunk left and of the chunk entered |
| Follow | **The window follows the adventurer at every move.** There is no margin and no re-centring rule. What is simulated, shown and targetable depends on the adventurer's position only, never on a state the player cannot know |
| Storage | **None.** The window is recomputed at each tick from the chunks: reads instead of one write per move |
| A chunk that is not revealed | **Wall in the window**, in zones and dungeons alike (D-136): a constant in the assembly. Sight never reaches it: the move that would bring sight onto it reveals it |
| At the edge of a location | The window stays centred: the chunks it overlaps beyond the edge, or outside the outline of a zone, are void and enter the assembly as a constant, without a read (D-134) |
| Row parity | The window's origin stays on an even global row, so that the hex neighbourhood of the library holds: the library derives every neighbour from the parity of the **local** row. The origin therefore moves vertically by two rows at a time; the sixteenth row absorbs the difference |

In the lore, this is the Hush: **things move near the living, and only there**.

#### Why 15 × 16, and what was dropped (D-120, 2026-09-28)

The first version of this section stored a 15 × 15 window and moved it only when the
adventurer came within 3 tiles of its edge. Two defects, found by the analysis of the map
library (LIB-02):

| Defect | |
|---|---|
| Sight left the window | An adventurer 3 tiles from the edge saw, and could shoot, 3 tiles beyond the window, where goblins are frozen and no board is assembled |
| Even centred, 15 rows are one too few | The origin must be on an even row. For half of the adventurer's positions a 15-row window puts it on local row 6 or 8, 6 rows from the ring: sight of radius 6 reaches the ring, where a goblin would be shown and not simulated |

| Option | Verdict |
|---|---|
| **The window follows the adventurer, 15 × 16** | **Kept** |
| Keep the margin of 3 and cut sight at the ring | Rejected by the owner: what the player sees would depend on where the window happens to be |
| 15 × 15 with an odd origin allowed by a parity flag in the layout | Not kept. Same cost per flood layer, but the library accepts no odd origin today: the flag would go through the layout, the neighbours, the backtracking of both finders and the distance, each with a second set of results to freeze and test. 15 × 16 is a board the library already accepts, so the finders are taken over unchanged. The flag stays needed for the **generation and seams** of chunks that start on an odd row, where it does not reach the tick |

Checked in the library's code by its orchestrator: `bal7hazar/hexx-cairo`,
`docs/research/window-parity-check.md` (`[Fable 5.1]`, read-only; nothing measured).

Consequences to keep in mind:

| | |
|---|---|
| The adventurer is not at a fixed local tile | Local `(7, 7)` or `(7, 8)`. Anything indexed "from the centre" (sight and range masks, line-of-sight tables) takes the local position, or the parity of the adventurer's row, as input |
| Assembly refuses an odd origin | Rather than return a board that is a different hex grid from the map |
| Limb path | 240 tiles are on the two-limb path, as 225 were: the cost of a flood layer does not change |

Consequences for rules written earlier:

| Before (rooms) | Now |
|---|---|
| Only the current room is simulated | Only the window is |
| Goblins do not follow out of a room | They follow while they are in the window, which moves with the adventurer; outrunning them is putting them out of it |
| The queue stops when entering a room | A **planned queue** stops when a new chunk is revealed, or when a goblin enters sight; the client evaluates the condition (D-133, design/02). A played batch has no stop condition but validity |
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
| Assemble the window | **At each tick** | Worst case: 4 chunks overlapped, two layers each (terrain, occupied): 8 reads, 8 masks and shifts. The figure of about 40k is an estimate. SPK-7 measures it, and compares **with and without a stored window** |
| Tick | Each action | One flood on a 15 × 16 board, 8 awake goblins, two chunk writes per crossing |
| Storage | Per instance, for every location | Terrain, occupied, features per revealed chunk; discarded with the instance |

If the window's cost is too high, the fallback keeps the same rule (the window follows,
is not stored) with a **sight of radius 5 on a window of 13 × 14**. A sight of radius `r`
needs `2r + 3` columns and `2r + 4` rows to stay inside the ring; a window of 11 × 12 holds
a sight of radius 4. Both are still on the library's two-limb path (more than 128 tiles):
a smaller window saves flood layers, not the cost of a layer. The single-limb path is
reached only by 11 × 11 with an odd origin allowed, which is the one case where the parity
flag in the tick would be worth its price; SPK-7 says whether it is ever needed.

## Measured (SPK-7, gathered by FND-04 on 2026-09-29)

Figures and their sources only; no decision is changed. SPK-7's figures are from snforge (in
memory, Sierra gas) and from transactions on the local node, whose meter is not Sepolia's (SPK-2
§8.2).

| Operation | Measured | Source |
|---|---|---|
| Assemble the window, in memory | **65,224** L2 gas, for 2 chunks as for 4 (the estimate above was about 40k) | SPK-7 §2.1 |
| The window in the tick, as transactions | **+720,000 L2 gas and +256 L1 data gas per tick with goblins awake**, +14.0 % on SPK-2's worst tick | SPK-7 summary, local node |
| A stored window (B, B′) against assembling it (A) | B +440,000 waiting, +320,000 moving; B′ −640,000 standing, up to 4,848,960 when it writes 4 chunks back | SPK-7 summary |
| Reveal | One chunk **2,455,200**, three chunks **5,919,680** (cave), as transactions; generation 390k to 447k per chunk in memory | SPK-7 summary |
| A chunk's storage, **SPK-7's observed layout** | 2 slots per chunk (terrain, occupied) under one key. **`reveal` writes the terrain slot of each chunk (new) and the revealed bitmap once per transaction** (new at the instance's first reveal, overwritten after); occupancy is written when goblins move, not at reveal. On Sepolia's slot prices (FND-04, D): 907,048 for one chunk at the first reveal, 485,596 after, 1,392,644 for three after | SPK-7 `contract.cairo` `reveal`; FND-04 §4 |
| A future layout that also writes occupancy at reveal | +1 new slot a chunk, about 0.45M: **an assumption**, not SPK-7's layout | [cost-budget.md](cost-budget.md) §2 |
| Shared flood, line of sight | 26,452 per layer + 59,380; the capped worst case 634,655. Line of sight 9,716 | SPK-7 summary |
| **R-12** | **Partly realised, not a blocker, on two conditions**: that the fallback (sight 5, 13 × 14) is not needed, which rests on an analysis, not a measurement; and that **D-133's batches carry the cost per transaction** | SPK-7 §3 |
| The window against a batch's target | The window follows the adventurer and is **assembled at every tick** (D-120), inside a batch too. SPK-7's +720,000 is a whole-transaction difference on a one-tick transaction: chunk reads, assembly (65,224 in memory) and storage effects together. A batch of 10 worst ticks is estimated at **37.6M to 44.2M** (E), against design/02's 40M: the lower figure if a batch pays the reads and slot changes once and only the assembly per tick, the higher if it pays all 720,000 per tick. Not measured | [cost-budget.md](cost-budget.md) §2, CB-3 |

## What this changes elsewhere

| Document | Change |
|---|---|
| `design/02-core-loop.md` | Map and simulation budget sections follow this ADR |
| `design/18-rooms.md` | Becomes "terrain, features and perception"; sizes and "entering a room" are replaced |
| `design/11-interface.md` | The room view becomes a camera on the map; layout zones are unchanged |
| `design/04-combat.md` | Ranges are unchanged. Ranged range 6 equals sight |
| `design/01-world.md` | Locations are measured in chunks |
| Map library | Generation with margins; a helper to assemble a board of 15 × 16 from chunks of 15 × 15, the parity of the origin being an explicit constraint; line of sight |

## Open

| # | Question |
|---|---|
| CM-7 | ~~Format of authored chunks and outline masks, and the tool to draw them~~ **Answered by ENG-08 (D-214, D-215)**: the records `ZONE_CHUNK`, `BRIDGE` and `CANDIDATES` and the `LOCATION` marker (ENG-01 §3.5, proposed), the export `grimworld-export` version 1 and its converter (`spikes/SPK-16-authored-zone/map-format/`, promoted to `tools/map-format/` by ENG-09); the tool is CLI-09 (track CV). Open in it: a bridge's rules (ENG-08b) |
| CM-9 | Exact `N` per grade within 6 to 12 |
| CM-10 | A value fixed in advance and tied to gameplay, stronger than the present player entropy: to look for |
