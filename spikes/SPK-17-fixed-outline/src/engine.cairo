//! **SPK-17 (ENG-10a): ENG-05's engine as ENG-10b would change it, a copy of
//! `grimworld_logic::types::reveal` at 44961f2 (its tests left out), changed only where the
//! dungeon's outline is fixed at entry.** The changes, each marked `ENG-10a` below: `Site` carries
//! a dungeon's outline (`chunk_set`, its chunks; `west` and `north`, its open seams; drawn at
//! `create`, `crate::outline`); a dungeon's chunk is inside when it is in its outline and
//! revealable as a zone's is (inside and not revealed: sight reveals it); a side not revealed is
//! open exactly when its seam is (no border drawn, no frontier, no guard: `grows`, `opens_growth`,
//! `widen` and `faced_open` are gone); the open edges are 0; a dungeon's quotas land on hosts drawn
//! at `create` as a zone's do (`placement`). The original documentation follows, as it was; where
//! it speaks of an emerging dungeon outline, the marked changes replace it.
//!
//! The chunk reveal engine (ENG-05; ADR-0006 §2–§3, design/18): **one engine for zones and
//! dungeons**. Since D-214 (the owner, 2026-10-05) zones are authored, not generated: a dungeon's
//! chunks and a zone not yet authored (no `LOCATION` marker, D-215 ruling 7) are generated here;
//! an authored zone's are copied from the registry by ENG-09's path (ENG-08's format). A chunk is
//! generated when sight first touches it, from a random word that does not exist before the reveal
//! (ADR-0006 option C, D-111: the entry draw and the player entropy, `fate::EntropyTrait::word`)
//! and from the edges of its revealed neighbours, in design/18's order:
//!
//! 1. the base from the chunk's word (`board::BoardTrait::base`, the biome's density);
//! 2. smoothing with the margins of the neighbours already revealed (`smooth`, the ring frozen to
//!    the sides decided first: copied, closed or drawn, step 3's decisions);
//! 3. edges and openings (`decide`: a side facing a revealed neighbour copies its decision; facing
//!    the location's border or a void chunk it is closed but for an anchor; any other side is
//!    drawn: in a zone open, with 1 or 2 openings; in a dungeon a border with probability 1 in 7,
//!    except that while fewer than `N` chunks are revealed one side stays open toward a chunk that
//!    can still grow, and every drawn edge a border once `N` are; a side the mask cuts whole is
//!    never opened), then every opening and anchor joined to the spine;
//! 4. the cut by the zone's outline (`cut`), then the component of the centre kept;
//! 5. the quotas (`placement::PlacementTrait::due`, drawn first: a set-piece quota lays an authored
//!    chunk instead of steps 1 and 2);
//! 6. the placement of packs and objects (`placement::PlacementTrait::place`).
//!
//! **The words.** One random word a chunk, read from the entropy at its reveal; it seeds four
//! streams, never shared (ADR-0002 rule 2): the `hades` permutations of `(word, 0)` and `(word,
//! 1)` are the base's bitmaps, and `mix(word, k)` seeds the draws (`RngTrait`) of the quotas (2),
//! the placement (3) and the ring (4). **No reveal feeds the entropy** (audit #348, major 1, the
//! orchestrator's ruling of 2026-10-03): the words read the entry draw and the irreversible facts
//! of other lots only, so the order of the reveals and the side a chunk is entered from change no
//! chunk's word; ADR-0006 lists moving and the order of actions among what must not steer. What
//! still depends on the order is the state a reveal reads: the neighbours known (their seams, as
//! the design accepts), and in a dungeon only (D-208, the project manager, 2026-10-03) its count
//! and frontier (`decide`) and its quotas (`PlacementTrait::due`): **a dungeon exit's position
//! stays order-dependent while the outline emerges from the order of the moves, accepted as the
//! dungeon's nature**. A zone's quotas land on hosts drawn once at entry, carried above each
//! chunk's mask (bit `225 + i`): order-free.
//!
//! **What is revealable** (`kind`): a zone's chunk inside the location and in its chunk set (the
//! whole rectangle when the location has no chunk set); a dungeon's entry chunk first, then a chunk
//! that a revealed neighbour faces with an open edge, while fewer than `N` are revealed. Anything
//! else is void (outside, outside the outline, beyond a border, or every chunk beyond the frontier
//! once `N` are revealed) or not yet decided (a dungeon chunk no revealed chunk faces yet). A chunk
//! that is not revealable is skipped, never generated (D-136: it stays wall in the window).
//!
//! **Sight** (`SightTrait::chunks`): the chunks a hexagon of radius 6 around a global tile touches
//! (at most 2 × 2), the tile's own first; ENG-07 reveals them at each move, `create` from the
//! entry tile.
//!
//! **D-140.** No word and no legal content panics: a side with no allowed tile has no opening, a
//! chunk whose centre is cut away keeps its floor as it is (`keep_component` needs a floor source),
//! a placement without room or tile is skipped. A neighbour revealed but not given in `known` is
//! the caller's error (asserted).


pub mod placement;
use hexx::board::bits::Bits;
use hexx::board::rng::{Rng, RngTrait};
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::models::chunk::{Features, Object, PackPlacement, Terrain};
use grimworld_logic::models::pack::Pack;
use grimworld_logic::models::quotas::{QuotaSet, kind as quota};
use grimworld_logic::models::set_piece::SetPiece;
use grimworld_logic::models::spawn_table::SpawnTable;
use grimworld_logic::snapshot::TaskEntry;
use grimworld_logic::types::ChunkKind;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait, CENTRE, INTERIOR};
use crate::engine::placement::PlacementTrait;

/// The sides of a chunk, in ENG-01's order of the edges (`Terrain.edges` bit `side`).
pub mod side {
    /// `+x`, column 14, the chunk `cx + 1` (`hexx`'s `Side::West`).
    pub const WEST: u8 = 0;
    /// `−x`, column 0, the chunk `cx − 1`.
    pub const EAST: u8 = 1;
    /// `−y`, row 0, the chunk `cy − 1`.
    pub const SOUTH: u8 = 2;
    /// `+y`, row 14, the chunk `cy + 1`.
    pub const NORTH: u8 = 3;
}

/// A dungeon's side is drawn as a border with probability 1 in `BORDER` (ADR-0006 *Outlines*).
pub const BORDER: u128 = 7;

pub mod errors {
    pub const NEIGHBOUR: felt252 = 'reveal: neighbour not given';
}

/// What the reveal reads of a location (the registry's records, read once an invocation).
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct Site {
    /// `N`, a dungeon floor's chunks; 0 for a zone (its outline is drawn, not emerging).
    pub target: u8,
    pub biome: u8,
    pub level_min: u8,
    pub level_max: u8,
    /// The location's extent in chunks.
    pub width: u8,
    pub height: u8,
    /// The instance's entry chunk (the bands' origin).
    pub entry_chunk: u8,
    /// A zone's chunk set (`OUTLINE` at `CHUNK_SET`), bit `15 cy + cx`; 0 for the whole rectangle.
    /// ENG-10a: a dungeon's outline, drawn at `create` (`crate::outline::Outline::chunks`).
    pub chunk_set: felt252,
    /// ENG-10a: a dungeon's open seams, drawn at `create`: bit `c` of `west`, the seam between `c`
    /// and `c + 1` (`c`'s West side); of `north`, between `c` and `c + 15`. 0 in a zone.
    pub west: felt252,
    pub north: felt252,
    /// The tile masks of the border chunks to reveal, `(chunk, mask)`; a chunk without one is
    /// whole.
    pub masks: Span<(u8, felt252)>,
    /// The anchors to keep open and reachable, `(chunk, tile)`: the entry tile, gates.
    pub anchors: Span<(u8, u8)>,
    pub quotas: QuotaSet,
    /// The snapshot's first 8 tasks (their quotas follow the location's).
    pub tasks: Span<TaskEntry>,
    pub spawn: SpawnTable,
    /// The pack templates the spawn table and the quotas name, `(id, template)`.
    pub packs: Span<(u16, Pack)>,
    /// The set pieces the quotas name, `(id, piece)`.
    pub pieces: Span<(u16, SetPiece)>,
}

/// What a reveal reads and writes of an instance: the revealed set and count, a dungeon's open
/// edges, what each quota has left to place, and the entropy.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Progress {
    /// Bit `15 cy + cx`.
    pub revealed: felt252,
    pub count: u8,
    /// Open edges of a dungeon's frontier toward chunks not revealed.
    pub open_edges: u8,
    /// Left to place of quota `i`: the location's 6, then the tasks' 8.
    pub left: [u8; 14],
    pub entropy: felt252,
}

/// A chunk revealed: its two words.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Revealed {
    pub chunk: u8,
    pub terrain: Terrain,
    pub features: Features,
}

#[generate_trait]
pub impl SiteImpl of SiteTrait {
    /// Whether the outline emerges (a dungeon floor, `N` > 0).
    #[inline(always)]
    fn emerging(self: @Site) -> bool {
        *self.target != 0
    }

    /// The chunk beyond `side` of `chunk`, if it is inside the location's rectangle.
    fn neighbour(self: @Site, chunk: u8, side: u8) -> Option<u8> {
        let (cy, cx) = DivRem::div_rem(chunk, 15);
        if side == side::WEST {
            if cx + 1 < *self.width {
                return Option::Some(chunk + 1);
            }
        } else if side == side::EAST {
            if cx != 0 {
                return Option::Some(chunk - 1);
            }
        } else if side == side::SOUTH {
            if cy != 0 {
                return Option::Some(chunk - 15);
            }
        } else if cy + 1 < *self.height {
            return Option::Some(chunk + 15);
        }
        Option::None
    }

    /// Whether `chunk` is inside the location: its rectangle, and a zone's chunk set.
    fn inside(self: @Site, chunk: u8) -> bool {
        let (cy, cx) = DivRem::div_rem(chunk, 15);
        if chunk >= 225 || cx >= *self.width || cy >= *self.height {
            return false;
        }
        // ENG-10a: a dungeon's chunk set is its outline (never 0)
        let set = *self.chunk_set;
        set == 0 || BoardTrait::has(set, chunk)
    }

    /// ENG-10a: whether the seam on `side` of `chunk`, toward `next`, is open in a dungeon's
    /// outline.
    fn seam(self: @Site, chunk: u8, side: u8, next: u8) -> bool {
        if side == side::WEST {
            BoardTrait::has(*self.west, chunk)
        } else if side == side::EAST {
            BoardTrait::has(*self.west, next)
        } else if side == side::SOUTH {
            BoardTrait::has(*self.north, next)
        } else {
            BoardTrait::has(*self.north, chunk)
        }
    }

    /// The chunks a location reveals in all: `N`, or the zone's chunk set.
    fn total(self: @Site) -> u8 {
        if self.emerging() {
            *self.target
        } else if *self.chunk_set == 0 {
            *self.width * *self.height
        } else {
            BoardTrait::count(*self.chunk_set)
        }
    }

    /// The mask word of `chunk` (the whole board without one): its tiles, and above the board
    /// (bits 225–238) a zone chunk's quota hosts, bit `225 + i` for quota `i` (D-208,
    /// `PlacementTrait::with_hosts`).
    fn mask(self: @Site, chunk: u8) -> felt252 {
        let mut mask = BOARD;
        for entry in *self.masks {
            let (at, value) = *entry;
            if at == chunk && value != 0 {
                mask = value;
            }
        }
        mask
    }

    /// The pack template `id`.
    fn pack(self: @Site, id: u16) -> Option<Pack> {
        let mut found: Option<Pack> = Option::None;
        for entry in *self.packs {
            let (at, pack) = *entry;
            if at == id && id != 0 {
                found = Option::Some(pack);
            }
        }
        found
    }

    /// The set piece `id`.
    fn piece(self: @Site, id: u16) -> Option<SetPiece> {
        let mut found: Option<SetPiece> = Option::None;
        for entry in *self.pieces {
            let (at, piece) = *entry;
            if at == id && id != 0 {
                found = Option::Some(piece);
            }
        }
        found
    }
}

#[generate_trait]
pub impl ProgressImpl of ProgressTrait {
    /// An instance before its first reveal: nothing revealed, each quota at its count (the tasks'
    /// after the location's), the entropy of the entry draw.
    fn new(site: @Site, entropy: felt252) -> Progress {
        Progress {
            revealed: 0, count: 0, open_edges: 0, left: PlacementTrait::start(site), entropy,
        }
    }

    #[inline(always)]
    fn is_revealed(self: @Progress, chunk: u8) -> bool {
        BoardTrait::has(*self.revealed, chunk)
    }
}

#[generate_trait]
pub impl RevealImpl of RevealTrait {
    /// The kind of `chunk` for the window and the views (module doc, *What is revealable*);
    /// `known`: the terrain of its revealed neighbours (a dungeon reads their edges).
    fn kind(site: @Site, progress: @Progress, _known: Span<(u8, Terrain)>, chunk: u8) -> ChunkKind {
        if !site.inside(chunk) {
            return ChunkKind::Void;
        }
        if progress.is_revealed(chunk) {
            return ChunkKind::Revealed;
        }
        // ENG-10a: a dungeon's chunk in its outline is known to exist, as a zone's
        ChunkKind::Unrevealed
    }

    /// Whether `chunk` can be revealed now: not revealed, and inside the location (ENG-10a: a
    /// dungeon's outline, as a zone's chunk set; sight reveals it).
    fn revealable(site: @Site, progress: @Progress, _known: Span<(u8, Terrain)>, chunk: u8) -> bool {
        !progress.is_revealed(chunk) && site.inside(chunk)
    }

    /// Reveals `chunks` in order: each that is revealable now is generated and known to the next
    /// ones. `known`: the terrain of every revealed neighbour of these chunks. Returns the chunks
    /// revealed. The entropy is read, never
    /// fed: a chunk's word does not depend on the order of the reveals (audit #348, major 1).
    fn reveal(
        site: @Site,
        ref progress: Progress,
        instance_id: felt252,
        known: Span<(u8, Terrain)>,
        chunks: Span<u8>,
    ) -> Array<Revealed> {
        let mut terrains: Array<(u8, Terrain)> = array![];
        for entry in known {
            terrains.append(*entry);
        }
        let mut out: Array<Revealed> = array![];
        for entry in chunks {
            let chunk = *entry;
            if Self::revealable(site, @progress, terrains.span(), chunk) {
                let revealed = Self::generate(
                    site, ref progress, instance_id, terrains.span(), chunk,
                );
                terrains.append((chunk, revealed.terrain));
                out.append(revealed);
            }
        }
        out
    }

    /// Generates one revealable chunk (module doc) and records it in `progress`.
    fn generate(
        site: @Site,
        ref progress: Progress,
        instance_id: felt252,
        known: Span<(u8, Terrain)>,
        chunk: u8,
    ) -> Revealed {
        let word = EntropyTrait::word(progress.entropy, instance_id, chunk);
        let (cy, _) = DivRem::div_rem(chunk, 15);
        let (_, parity) = DivRem::div_rem(cy, 2);
        let odd = parity == 1;
        let word_mask = site.mask(chunk);
        let mask = BoardTrait::and(word_mask, BOARD);
        // [Compute] 5. The quotas due here, drawn first: a set piece replaces the generation; a
        // zone's hosts ride above the mask's board (D-208)
        let mut quotas = RngTrait::new(RngTrait::mix(word, 2));
        let due = PlacementTrait::due(site, @progress, word_mask, ref quotas);
        let piece = Self::piece(site, due);
        // [Compute] 3. The ring: each side copied, closed or drawn; the anchors opened
        let mut draws = RngTrait::new(RngTrait::mix(word, 4));
        let (ring, edges, open_edges) = Self::decide(
            site, @progress, known, chunk, mask, ref draws,
        );
        let mut anchors: Array<u8> = array![];
        let mut ring = ring;
        let mut inner: felt252 = 0;
        for entry in *site.anchors {
            let (at, tile) = *entry;
            if at == chunk && tile < 225 {
                if BoardTrait::has(INTERIOR, tile) {
                    inner =
                        BoardTrait::or(
                            inner, BoardTrait::pow(tile) + BoardTrait::anchor_line(tile),
                        );
                    anchors.append(tile);
                } else if BoardTrait::has(BOARD - INTERIOR, tile) && !Self::corner(tile) {
                    ring = BoardTrait::or(ring, BoardTrait::pow(tile));
                }
            }
        }
        // [Compute] 1–2. The base and the smoothing with the ring frozen, or the set piece
        let interior = match piece {
            Option::Some((_, set)) => BoardTrait::and(BoardTrait::floor(set.walls), INTERIOR),
            Option::None => {
                let grid = BoardTrait::base(word, *site.biome) + ring;
                BoardTrait::and(BoardTrait::smooth(grid, odd), INTERIOR)
            },
        };
        // [Compute] 3. The openings and anchors joined to the spine
        let grid = BoardTrait::or(BoardTrait::or(interior, BoardTrait::lines(ring)), inner);
        // [Compute] 4. The cut by the outline, then the centre's component
        let cut = BoardTrait::cut(grid + ring, mask);
        let ring = BoardTrait::minus(cut, INTERIOR);
        let mut interior = BoardTrait::and(cut, INTERIOR);
        let root = Self::root(interior, anchors.span());
        if let Option::Some(root) = root {
            interior = BoardTrait::component(interior, root, odd);
        }
        let terrain = Terrain {
            walls: BOARD - interior - ring, edges: if site.emerging() {
                edges
            } else {
                0
            },
        };
        // [Compute] 6. The placement, on the floor away from the openings and anchors
        let near = BoardTrait::near_openings(ring, anchors.span(), odd);
        let allowed = BoardTrait::minus(interior, near);
        let mut draws = RngTrait::new(RngTrait::mix(word, 3));
        let placement = PlacementTrait::place(site, chunk, due, piece, allowed, odd, ref draws);
        let features = Self::features(placement.packs.span(), placement.objects.span());
        // [Compute] The instance's progress
        progress.left = PlacementTrait::spend(progress.left, placement.placed);
        progress.revealed += BoardTrait::pow(chunk);
        progress.count += 1;
        progress.open_edges = open_edges;
        Revealed { chunk, terrain, features }
    }

    /// The ring of a chunk and, for a dungeon, its edges (module doc, step 3). ENG-10a: the open
    /// edges are 0 (no frontier); the third value is kept so that `generate` reads as ENG-05's.
    fn decide(
        site: @Site,
        progress: @Progress,
        known: Span<(u8, Terrain)>,
        chunk: u8,
        mask: felt252,
        ref draws: Rng,
    ) -> (felt252, u8, u8) {
        let emerging = site.emerging();
        // The loops' state starts from `zero`, 0 for every chunk index but not a constant: a loop
        // whose state starts from constants is compiled twice (a copy specialised to them), which
        // cost this class about 1,900 CASM felts (D-200).
        let zero: u8 = chunk / 255;
        let mut ring: felt252 = zero.into();
        let mut edges: u8 = zero;
        let mut open: u8 = zero;
        let mut side: u8 = zero;
        let mut bit: u8 = zero + 1;
        while side != 4 {
            if let Option::Some(next) = site.neighbour(chunk, side) {
                if progress.is_revealed(next) {
                    // [Compute] Copied: the neighbour's facing tiles, its edge's decision
                    let terrain = Self::known(known, next);
                    ring += BoardTrait::copy(side, BoardTrait::floor(terrain.walls));
                    if Self::is_open(terrain.edges, Self::opposite(side)) {
                        edges += bit;
                    }
                } else if site.inside(next) {
                    // [Compute] ENG-10a: a zone's side is open; a dungeon's is open exactly when its
                    // seam is, drawn at `create`. ENG-05's border draw is kept, unread, so that a
                    // zone's streams do not move; a side the mask cuts whole is no side to open
                    let _border = draws.draw(BORDER.try_into().unwrap());
                    if BoardTrait::and(BoardTrait::side(side), mask) != 0
                        && (!emerging || site.seam(chunk, side, next)) {
                        open += bit;
                    }
                }
            }
            side += 1;
            bit *= 2;
        }
        // [Compute] The openings of the sides drawn open, 1 or 2 each, inside the mask
        let mut side: u8 = zero;
        let mut rest = open;
        while side != 4 {
            let (above, here) = DivRem::div_rem(rest, 2);
            rest = above;
            if here == 1 {
                let allowed = BoardTrait::and(BoardTrait::side(side), mask);
                let two = draws.draw_byte(2) == 1;
                if allowed != 0 {
                    let first = Self::opening(allowed, side, ref draws);
                    ring = BoardTrait::or(ring, BoardTrait::pow(first));
                    if two {
                        let second = Self::opening(allowed, side, ref draws);
                        ring = BoardTrait::or(ring, BoardTrait::pow(second));
                    }
                    edges += Self::pow2(side);
                }
            }
            side += 1;
        }
        (ring, edges, zero)
    }

    /// An opening on `side` among its `allowed` tiles (not empty): one of the side's 13 tiles drawn
    /// and kept if allowed, up to `placement::TRIES` draws, then the `n`-th allowed one (the whole
    /// side is allowed but in a cut chunk).
    fn opening(allowed: felt252, side: u8, ref draws: Rng) -> u8 {
        let wide: u256 = allowed.into();
        // The side's tile `i` (1–13): its first tile and the step between two.
        let (first, step) = match side {
            0 => (14, 15),
            1 => (0, 15),
            2 => (0, 1),
            _ => (210, 1),
        };
        let mut found: Option<u8> = Option::None;
        let mut tries: u8 = 0;
        while found.is_none() && tries != placement::TRIES {
            let tile = first + step * (1 + draws.draw_byte(13));
            if BoardTrait::has_wide(wide, tile) {
                found = Option::Some(tile);
            }
            tries += 1;
        }
        match found {
            Option::Some(tile) => tile,
            Option::None => {
                let count = BoardTrait::count(allowed);
                BoardTrait::nth(allowed, draws.draw_byte(count.try_into().unwrap()))
            },
        }
    }

    /// The set piece of the first set-piece quota due whose piece the site holds, with its slot.
    fn piece(site: @Site, due: u16) -> Option<(u8, SetPiece)> {
        let mut rest = due;
        let mut i: u8 = 0;
        let mut found: Option<(u8, SetPiece)> = Option::None;
        while rest != 0 {
            let (above, bit) = DivRem::div_rem(rest, 2);
            rest = above;
            if bit == 1 && found.is_none() {
                let (kind, param) = PlacementTrait::slot(site, i);
                if kind == quota::SET_PIECE {
                    if let Option::Some(set) = site.piece(param) {
                        found = Option::Some((i, set));
                    }
                }
            }
            i += 1;
        }
        found
    }

    /// The flood's source: the centre if it is floor, else the first interior anchor on floor.
    fn root(interior: felt252, anchors: Span<u8>) -> Option<u8> {
        if BoardTrait::has(interior, CENTRE) {
            return Option::Some(CENTRE);
        }
        let mut found: Option<u8> = Option::None;
        for tile in anchors {
            if found.is_none() && BoardTrait::has(interior, *tile) {
                found = Option::Some(*tile);
            }
        }
        found
    }

    /// The `Features` word of the packs and objects placed, nothing touched.
    fn features(packs: Span<PackPlacement>, objects: Span<Object>) -> Features {
        let mut all_packs: Array<PackPlacement> = array![];
        for i in 0..2_u32 {
            all_packs.append(if i < packs.len() {
                *packs[i]
            } else {
                Default::default()
            });
        }
        let mut all_objects: Array<Object> = array![];
        for i in 0..3_u32 {
            all_objects.append(if i < objects.len() {
                *objects[i]
            } else {
                Default::default()
            });
        }
        Features {
            packs: [*all_packs[0], *all_packs[1]],
            objects: [*all_objects[0], *all_objects[1], *all_objects[2]],
            touched: 0,
        }
    }

    /// The terrain of a revealed chunk given in `known`.
    fn known(known: Span<(u8, Terrain)>, chunk: u8) -> Terrain {
        let mut found: Option<Terrain> = Option::None;
        for entry in known {
            let (at, terrain) = *entry;
            if at == chunk {
                found = Option::Some(terrain);
            }
        }
        match found {
            Option::Some(terrain) => terrain,
            Option::None => core::panic_with_felt252(errors::NEIGHBOUR),
        }
    }

    /// Edge `side` of `edges` is open.
    #[inline(always)]
    fn is_open(edges: u8, side: u8) -> bool {
        (edges / Self::pow2(side)) % 2 == 1
    }

    /// The side facing `side` across a seam: West and East, South and North.
    #[inline(always)]
    fn opposite(side: u8) -> u8 {
        match side {
            0 => 1,
            1 => 0,
            2 => 3,
            _ => 2,
        }
    }

    #[inline(always)]
    fn pow2(side: u8) -> u8 {
        match side {
            0 => 1,
            1 => 2,
            2 => 4,
            _ => 8,
        }
    }

    /// A corner tile of the chunk, never open (D-134).
    #[inline(always)]
    fn corner(tile: u8) -> bool {
        tile == 0 || tile == 14 || tile == 210 || tile == 224
    }
}

/// The chunks that sight touches (design/18 *What the adventurer sees*: a hexagon of radius 6, line
/// of sight not required; D-136: the move that would bring sight onto a chunk reveals it).
#[generate_trait]
pub impl SightImpl of SightTrait {
    /// The chunks of a `width` × `height` location within 6 of the global tile `(x, y)`, its own
    /// chunk first, then by index; at most 4. A chunk diagonal to the tile's is touched when the
    /// hexagon's row nearest to it reaches its columns (the widest row of the hexagon inside it).
    fn chunks(x: u8, y: u8, width: u8, height: u8) -> Array<u8> {
        let (cy, cx) = (y / 15, x / 15);
        let own = cy * 15 + cx;
        let mut out: Array<u8> = array![own];
        // [Compute] The chunk rows and columns the hexagon's extent reaches
        let low_x = if x >= 6 {
            (x - 6) / 15
        } else {
            0
        };
        let high_x = (x + 6) / 15;
        let low_y = if y >= 6 {
            (y - 6) / 15
        } else {
            0
        };
        let high_y = (y + 6) / 15;
        let mut row = low_y;
        while row <= high_y && row < height {
            let mut column = low_x;
            while column <= high_x && column < width {
                let chunk = row * 15 + column;
                if chunk != own && Self::touches(x, y, column, row) {
                    out.append(chunk);
                }
                column += 1;
            }
            row += 1;
        }
        out
    }

    /// Whether the hexagon of radius 6 around `(x, y)` reaches chunk `(column, row)`, a neighbour
    /// of the tile's chunk: on the chunk's row nearest to `y`, the hexagon spans the columns
    /// `x + dq + ⌊y'/2⌋ − ⌊y/2⌋` for `dq` in `[max(−6, −6 − dr), min(6, 6 − dr)]`
    /// (axial, `dr =
    /// y' − y`), computed shifted by 12 and 6 so that nothing is negative.
    fn touches(x: u8, y: u8, column: u8, row: u8) -> bool {
        let (x, y, column, row): (u16, u16, u16, u16) = (
            x.into(), y.into(), column.into(), row.into(),
        );
        let top = row * 15;
        let near_y = if y < top {
            top
        } else if y > top + 14 {
            top + 14
        } else {
            y
        };
        // `dr + 6`, in `0..=12`
        let dr = near_y + 6 - y;
        if dr > 12 {
            return false;
        }
        // `dq + 6` at its lowest and highest
        let low_q = if dr >= 6 {
            0
        } else {
            6 - dr
        };
        let high_q = if dr <= 6 {
            12
        } else {
            18 - dr
        };
        // The hexagon's columns and the chunk's, both shifted by `6 + ⌊y/2⌋`.
        let first = x + low_q + near_y / 2;
        let last = x + high_q + near_y / 2;
        let left = column * 15 + 6 + y / 2;
        let right = left + 14;
        first <= right && last >= left
    }
}
