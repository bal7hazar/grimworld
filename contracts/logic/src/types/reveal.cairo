//! The chunk reveal engine (ENG-05; ADR-0006 §2–§3, design/18): **one engine for zones and
//! dungeons**. A chunk is generated when sight first touches it, from a random word that does not
//! exist before the reveal (ADR-0006 option C, D-111: the entry draw and the player entropy,
//! `fate::EntropyTrait::word`) and from the edges of its revealed neighbours, in design/18's order:
//!
//! 1. the base from the chunk's word (`board::BoardTrait::base`, the biome's density);
//! 2. smoothing with the margins of the neighbours already revealed (`smooth`, the ring frozen to
//!    the sides decided first: copied, closed or drawn, step 3's decisions);
//! 3. edges and openings (`decide`: a side facing a revealed neighbour copies its decision; facing
//!    the location's border or a void chunk it is closed but for an anchor; any other side is
//!    drawn: in a zone open, with 1 or 2 openings; in a dungeon a border with probability 1 in 7,
//!    except the last open edge of the frontier while fewer than `N` chunks are revealed, and every
//!    drawn edge a border once `N` are), then every opening and anchor joined to the spine;
//! 4. the cut by the zone's outline (`cut`), then the component of the centre kept;
//! 5. the quotas (`placement::PlacementTrait::due`, drawn first: a set-piece quota lays an authored
//!    chunk instead of steps 1 and 2);
//! 6. the placement of packs and objects (`placement::PlacementTrait::place`).
//!
//! **The words.** One random word a chunk, read from the entropy at its reveal; it seeds four
//! streams, never shared (ADR-0002 rule 2): the `hades` permutations of `(word, 0)` and `(word,
//! 1)` are the base's bitmaps, and `mix(word, k)` seeds the draws (`RngTrait`) of the quotas (2),
//! the placement (3) and the ring (4). After the chunk, its fact (the
//! chunk and the side it was entered from) is fed into the entropy, so the next chunk's word
//! differs.
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

pub mod board;
pub mod placement;

use hexx::board::bits::Bits;
use hexx::board::rng::{Rng, RngTrait};
use crate::fate::EntropyTrait;
use crate::models::chunk::{Features, Object, PackPlacement, Terrain};
use crate::models::pack::Pack;
use crate::models::quotas::{QuotaSet, kind as quota};
use crate::models::set_piece::SetPiece;
use crate::models::spawn_table::SpawnTable;
use crate::snapshot::TaskEntry;
use crate::types::ChunkKind;
use crate::types::reveal::board::{BOARD, BoardTrait, CENTRE, INTERIOR};
use crate::types::reveal::placement::PlacementTrait;

/// The sides of a chunk, in ENG-01's order of the edges (`Terrain.edges` bit `side`), and the side
/// a reveal was entered from.
pub mod side {
    /// `+x`, column 14, the chunk `cx + 1` (`hexx`'s `Side::West`).
    pub const WEST: u8 = 0;
    /// `−x`, column 0, the chunk `cx − 1`.
    pub const EAST: u8 = 1;
    /// `−y`, row 0, the chunk `cy − 1`.
    pub const SOUTH: u8 = 2;
    /// `+y`, row 14, the chunk `cy + 1`.
    pub const NORTH: u8 = 3;
    /// No side: the entry reveal.
    pub const NONE: u8 = 4;
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
    pub chunk_set: felt252,
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
        self.emerging() || *self.chunk_set == 0 || BoardTrait::has(*self.chunk_set, chunk)
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

    /// The tile mask of `chunk` (the whole board without one).
    fn mask(self: @Site, chunk: u8) -> felt252 {
        let mut mask = BOARD;
        for entry in *self.masks {
            let (at, value) = *entry;
            if at == chunk && value != 0 {
                mask = BoardTrait::and(value, BOARD);
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
    fn kind(
        site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8,
    ) -> ChunkKind {
        if !site.inside(chunk) {
            return ChunkKind::Void;
        }
        if progress.is_revealed(chunk) {
            return ChunkKind::Revealed;
        }
        if !site.emerging() {
            return ChunkKind::Unrevealed;
        }
        if *progress.count >= *site.target {
            return ChunkKind::Void;
        }
        // [Compute] Faced by a revealed neighbour: open, border, or not yet
        let mut faced = false;
        let mut open = false;
        let mut side: u8 = 0;
        while side != 4 {
            if let Option::Some(next) = site.neighbour(chunk, side) {
                if progress.is_revealed(next) {
                    faced = true;
                    let terrain = Self::known(known, next);
                    if Self::is_open(terrain.edges, Self::opposite(side)) {
                        open = true;
                    }
                }
            }
            side += 1;
        }
        if open || !faced {
            ChunkKind::Unrevealed
        } else {
            ChunkKind::Void
        }
    }

    /// Whether `chunk` can be revealed now: not revealed, and a zone's chunk inside the location,
    /// or a dungeon's entry chunk first, then a chunk faced by an open edge, before `N`.
    fn revealable(
        site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8,
    ) -> bool {
        if progress.is_revealed(chunk) || !site.inside(chunk) {
            return false;
        }
        if !site.emerging() {
            return true;
        }
        if *progress.count >= *site.target {
            return false;
        }
        if *progress.count == 0 {
            return chunk == *site.entry_chunk;
        }
        Self::faced_open(site, progress, known, chunk)
    }

    /// Reveals `chunks`, `(chunk, side entered)`, in order: each that is revealable now is
    /// generated, its fact fed into the entropy, and it is known to the next ones. `known`: the
    /// terrain of every revealed neighbour of these chunks. Returns the chunks revealed.
    fn reveal(
        site: @Site,
        ref progress: Progress,
        instance_id: felt252,
        known: Span<(u8, Terrain)>,
        chunks: Span<(u8, u8)>,
    ) -> Array<Revealed> {
        let mut terrains: Array<(u8, Terrain)> = array![];
        for entry in known {
            terrains.append(*entry);
        }
        let mut out: Array<Revealed> = array![];
        for entry in chunks {
            let (chunk, entered) = *entry;
            if Self::revealable(site, @progress, terrains.span(), chunk) {
                let revealed = Self::generate(
                    site, ref progress, instance_id, terrains.span(), chunk, entered,
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
        entered: u8,
    ) -> Revealed {
        let word = EntropyTrait::word(progress.entropy, instance_id, chunk);
        let (cy, _) = DivRem::div_rem(chunk, 15);
        let (_, parity) = DivRem::div_rem(cy, 2);
        let odd = parity == 1;
        let mask = site.mask(chunk);
        // [Compute] 5. The quotas due here, drawn first: a set piece replaces the generation
        let mut quotas = RngTrait::new(RngTrait::mix(word, 2));
        let due = PlacementTrait::due(site, @progress, ref quotas);
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
                    inner = BoardTrait::or(inner, BoardTrait::pow(tile) + BoardTrait::anchor_line(tile));
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
        progress
            .entropy = EntropyTrait::feed(progress.entropy, EntropyTrait::reveal_fact(chunk, entered));
        Revealed { chunk, terrain, features }
    }

    /// The ring of a chunk and, for a dungeon, its edges and the frontier's open edges after it
    /// (module doc, step 3).
    fn decide(
        site: @Site,
        progress: @Progress,
        known: Span<(u8, Terrain)>,
        chunk: u8,
        mask: felt252,
        ref draws: Rng,
    ) -> (felt252, u8, u8) {
        let emerging = site.emerging();
        let last = *progress.count + 1 >= *site.target;
        let mut ring: felt252 = 0;
        let mut edges: u8 = 0;
        let mut copied: u8 = 0;
        // Drawable sides as bits, and those drawn open.
        let mut free: u8 = 0;
        let mut open: u8 = 0;
        let mut side: u8 = 0;
        let mut bit: u8 = 1;
        while side != 4 {
            if let Option::Some(next) = site.neighbour(chunk, side) {
                if progress.is_revealed(next) {
                    // [Compute] Copied: the neighbour's facing tiles, its edge's decision
                    let terrain = Self::known(known, next);
                    ring += BoardTrait::copy(side, BoardTrait::floor(terrain.walls));
                    if Self::is_open(terrain.edges, Self::opposite(side)) {
                        edges += bit;
                        copied += 1;
                    }
                } else if site.inside(next) {
                    // [Compute] Drawn: a zone's side is open; a dungeon's a border in 7, every one
                    // once `N` are revealed
                    free += bit;
                    let border = draws.draw(BORDER.try_into().unwrap()) == 0;
                    if !emerging || (!last && !border) {
                        open += bit;
                    }
                }
            }
            side += 1;
            bit *= 2;
        }
        // [Compute] A dungeon never closes before `N`: the last open edge of the frontier is kept
        let frontier = if *progress.open_edges > copied {
            *progress.open_edges - copied
        } else {
            0
        };
        if emerging && !last && open == 0 && frontier == 0 && free != 0 {
            open = Self::lowest(free);
        }
        // [Compute] The openings of the sides drawn open, 1 or 2 each, inside the mask
        let mut drawn: u8 = 0;
        let mut side: u8 = 0;
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
                    drawn += 1;
                }
            }
            side += 1;
        }
        let open_edges = if !emerging || last {
            0
        } else {
            frontier + drawn
        };
        (ring, edges, open_edges)
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

    /// Whether a revealed neighbour faces `chunk` with an open edge.
    fn faced_open(
        site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8,
    ) -> bool {
        let mut open = false;
        let mut side: u8 = 0;
        while side != 4 {
            if let Option::Some(next) = site.neighbour(chunk, side) {
                if progress.is_revealed(next) {
                    let terrain = Self::known(known, next);
                    if Self::is_open(terrain.edges, Self::opposite(side)) {
                        open = true;
                    }
                }
            }
            side += 1;
        }
        open
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

    /// The lowest set bit of a 4-bit set.
    #[inline(always)]
    fn lowest(bits: u8) -> u8 {
        if bits % 2 == 1 {
            1
        } else if bits % 4 != 0 {
            2
        } else if bits % 8 != 0 {
            4
        } else {
            8
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
    /// `x + dq + ⌊y'/2⌋ − ⌊y/2⌋` for `dq` in `[max(−6, −6 − dr), min(6, 6 − dr)]` (axial, `dr =
    /// y' − y`), computed shifted by 12 and 6 so that nothing is negative.
    fn touches(x: u8, y: u8, column: u8, row: u8) -> bool {
        let (x, y, column, row): (u16, u16, u16, u16) = (x.into(), y.into(), column.into(), row.into());
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

#[cfg(test)]
pub mod tests {
    use core::poseidon::poseidon_hash_span;
    use hexx::board::bits::Bits;
    use hexx::board::seams::{SeamTrait, Side};
    use crate::fate::{ENTRY, EntropyTrait, REVEAL, domain};
    use crate::models::chunk::{PackPlacementTrait, Terrain, object};
    use crate::models::location::biome;
    use crate::models::pack::{Pack, PackCaste};
    use crate::models::quotas::{Quota, QuotaSet, kind as quota};
    use crate::models::set_piece::SetPiece;
    use crate::models::spawn_table::{Spawn, SpawnTable};
    use crate::snapshot::TaskEntry;
    use crate::types::ChunkKind;
    use super::board::{BOARD, BoardTrait, CENTRE, INTERIOR};
    use super::{Progress, ProgressTrait, RevealTrait, Revealed, SightTrait, Site, SiteTrait, side};

    pub const INSTANCE: felt252 = 0x100000001;

    pub fn no_quotas() -> QuotaSet {
        QuotaSet { quotas: [Default::default(); 6] }
    }

    pub fn packs() -> Span<(u16, Pack)> {
        array![
            (
                1,
                Pack {
                    castes: [
                        PackCaste { caste: 1, min: 1, max: 2 }, PackCaste { caste: 2, min: 1, max: 3 },
                        Default::default(), Default::default(), Default::default(),
                    ],
                    level: 0,
                },
            ),
            (
                2,
                Pack {
                    castes: [
                        PackCaste { caste: 3, min: 1, max: 1 }, Default::default(),
                        Default::default(), Default::default(), Default::default(),
                    ],
                    level: 2,
                },
            ),
        ]
            .span()
    }

    pub fn spawn(density: u8) -> SpawnTable {
        SpawnTable {
            spawns: [
                Spawn { template: 1, weight: 3 }, Spawn { template: 2, weight: 1 },
                Default::default(), Default::default(), Default::default(), Default::default(),
                Default::default(),
            ],
            density,
        }
    }

    /// A zone of `width` × `height` chunks, every chunk in it, entered at chunk 0.
    pub fn zone(kind: u8, width: u8, height: u8, quotas: QuotaSet) -> Site {
        Site {
            target: 0,
            biome: kind,
            level_min: 1,
            level_max: 5,
            width,
            height,
            entry_chunk: 0,
            chunk_set: 0,
            masks: array![].span(),
            anchors: array![].span(),
            quotas,
            tasks: array![].span(),
            spawn: spawn(160),
            packs: packs(),
            pieces: array![].span(),
        }
    }

    /// A dungeon floor of `n` chunks, entered at chunk 112, tile 112.
    pub fn dungeon(n: u8, quotas: QuotaSet) -> Site {
        Site {
            target: n,
            biome: biome::CAVE,
            level_min: 3,
            level_max: 5,
            width: 15,
            height: 15,
            entry_chunk: 112,
            chunk_set: 0,
            masks: array![].span(),
            anchors: array![(112, 112)].span(),
            quotas,
            tasks: array![].span(),
            spawn: spawn(160),
            packs: packs(),
            pieces: array![].span(),
        }
    }

    pub fn exit_quota() -> QuotaSet {
        QuotaSet {
            quotas: [
                Quota { kind: quota::EXIT, param: 5, count: 1 },
                Quota { kind: quota::VEIN, param: 0, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
        }
    }

    pub fn floor(terrain: @Terrain) -> felt252 {
        BOARD - *terrain.walls
    }

    fn odd(chunk: u8) -> bool {
        let (cy, _) = DivRem::div_rem(chunk, 15);
        let (_, parity) = DivRem::div_rem(cy, 2);
        parity == 1
    }

    /// The invariants of one revealed chunk (ENG-05 *Scope*, tests): corners wall; the interior
    /// floor one component that holds the centre; every ring opening next to it; nothing placed on
    /// a wall, on the ring or within 2 of an opening; E-3.
    pub fn check_chunk(revealed: @Revealed) {
        let ground = floor(revealed.terrain);
        let corners = 1 + Bits::pow(14) + Bits::pow(210) + Bits::pow(224);
        assert(BoardTrait::and(ground, corners) == 0, 'corners are wall');
        let odd = odd(*revealed.chunk);
        let interior = BoardTrait::and(ground, INTERIOR);
        let ring = ground - interior;
        if BoardTrait::has(interior, CENTRE) {
            assert(BoardTrait::component(interior, CENTRE, odd) == interior, 'one component');
        }
        // Each opening's next tile inward is floor (its line).
        let mut tile: u8 = 0;
        while tile != 225 {
            if BoardTrait::has(ring, tile) {
                let (row, column) = DivRem::div_rem(tile, 15);
                let inward = if column == 0 {
                    tile + 1
                } else if column == 14 {
                    tile - 1
                } else if row == 0 {
                    tile + 15
                } else {
                    tile - 15
                };
                assert(BoardTrait::has(interior, inward), 'opening reaches inside');
            }
            tile += 1;
        }
        let near = BoardTrait::near_openings(ring, array![].span(), odd);
        let features = *revealed.features;
        assert(features.touched == 0, 'touched cleared');
        for pack in features.packs.span() {
            assert(*pack.count <= 5, 'E-3 pack size');
            if *pack.count != 0 {
                let (row, _) = DivRem::div_rem(*pack.tile, 15);
                let (_, parity) = DivRem::div_rem(row, 2);
                let row_odd = (parity == 1) != odd;
                let mut k: u8 = 0;
                let mut offsets = *pack.offsets;
                while k != *pack.count {
                    let (rest, index) = DivRem::div_rem(offsets, 32);
                    offsets = rest;
                    let member = PackPlacementTrait::member(*pack.tile, index.try_into().unwrap(), row_odd)
                        .unwrap();
                    assert(BoardTrait::has(interior, member), 'member on floor');
                    assert(!BoardTrait::has(near, member), 'member near an opening');
                    k += 1;
                }
            }
        }
        for item in features.objects.span() {
            if *item.kind != 0 {
                assert(BoardTrait::has(interior, *item.tile), 'object on floor');
                assert(!BoardTrait::has(near, *item.tile), 'object near an opening');
            }
        }
    }

    /// Reveals one chunk with the given terrains known; it must be revealed.
    pub fn one(
        site: @Site, ref progress: Progress, known: Span<(u8, Terrain)>, chunk: u8, entered: u8,
    ) -> Revealed {
        let out = RevealTrait::reveal(site, ref progress, INSTANCE, known, array![(chunk, entered)].span());
        assert(out.len() == 1, 'revealed');
        *out[0]
    }

    // The order of the edges (ENG-01: West, East, South, North) against `hexx`'s sides: a dungeon
    // chunk's edge bit `s` is open exactly when side `s` of its ring holds an opening.
    #[test]
    #[available_gas(l2_gas: 35294686)] // ceil(1.05 × 33613986 measured)
    fn test_edges_against_hexx_sides() {
        let sides = [Side::West, Side::East, Side::South, Side::North];
        let mut seed: felt252 = 0;
        while seed != 12 {
            let site = dungeon(12, no_quotas());
            let mut progress = ProgressTrait::new(@site, seed);
            let revealed = one(@site, ref progress, array![].span(), 112, side::NONE);
            let ground = floor(@revealed.terrain);
            let mut s: u8 = 0;
            for hexx_side in sides.span() {
                let mask = SeamTrait::side(15, 15, *hexx_side);
                let open = BoardTrait::and(ground, mask) != 0;
                assert(open == RevealTrait::is_open(revealed.terrain.edges, s), 'edge bit');
                s += 1;
            }
            assert(revealed.terrain.edges != 0, 'the first chunk is open');
            seed += 1;
        }
    }

    // The invariants over many words, each biome, both parities, 0 to 4 known sides.
    fn check_zone_words(kind: u8, first: felt252, words: felt252) {
        let site = zone(kind, 15, 3, no_quotas());
        let mut seed = first;
        while seed != first + words {
            let mut progress = ProgressTrait::new(@site, seed);
            // A chunk with nothing known (four sides drawn; East at the location's edge), then its
            // West and North neighbours, then the chunk between them (two sides copied).
            let a = one(@site, ref progress, array![].span(), 16, side::NONE);
            check_chunk(@a);
            let b = one(@site, ref progress, array![(16, a.terrain)].span(), 17, side::EAST);
            check_chunk(@b);
            let c = one(@site, ref progress, array![(16, a.terrain)].span(), 31, side::SOUTH);
            check_chunk(@c);
            let d = one(
                @site, ref progress, array![(17, b.terrain), (31, c.terrain)].span(), 32, side::EAST,
            );
            check_chunk(@d);
            // Every shared edge open across its seam, from both sides (`hexx`'s seams, N-2).
            assert(
                SeamTrait::is_open_across(15, 15, floor(@b.terrain), floor(@a.terrain), Side::East, true),
                'a-b from b',
            );
            assert(
                SeamTrait::is_open_across(15, 15, floor(@a.terrain), floor(@b.terrain), Side::West, true),
                'a-b from a',
            );
            assert(
                SeamTrait::is_open_across(15, 15, floor(@c.terrain), floor(@a.terrain), Side::South, false),
                'a-c from c',
            );
            assert(
                SeamTrait::is_open_across(15, 15, floor(@a.terrain), floor(@c.terrain), Side::North, true),
                'a-c from a',
            );
            assert(
                SeamTrait::is_open_across(15, 15, floor(@d.terrain), floor(@b.terrain), Side::South, false),
                'b-d from d',
            );
            assert(
                SeamTrait::is_open_across(15, 15, floor(@d.terrain), floor(@c.terrain), Side::East, false),
                'c-d from d',
            );
            // A side at the location's edge (chunk 16's East is chunk 15, inside; chunk 0's East is
            // outside): closed.
            seed += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 138336266)] // ceil(1.05 × 131748824 measured)
    fn test_invariants_meadow() {
        check_zone_words(biome::MEADOW, 0, 6);
    }

    #[test]
    #[available_gas(l2_gas: 140829007)] // ceil(1.05 × 134122863 measured)
    fn test_invariants_forest() {
        check_zone_words(biome::FOREST, 100, 6);
    }

    #[test]
    #[available_gas(l2_gas: 142507484)] // ceil(1.05 × 135721413 measured)
    fn test_invariants_cave() {
        check_zone_words(biome::CAVE, 200, 6);
    }

    #[test]
    #[available_gas(l2_gas: 141835360)] // ceil(1.05 × 135081295 measured)
    fn test_invariants_ruin() {
        check_zone_words(biome::RUIN, 300, 6);
    }

    // The location's border and a void chunk close a side (D-134); an anchor on it stays open.
    #[test]
    #[available_gas(l2_gas: 49843579)] // ceil(1.05 × 47470075 measured)
    fn test_border_and_void_closed_but_anchors() {
        // Chunks (0, 0), (1, 0) and (0, 1) of a 2 × 2 zone; (1, 1) is outside the outline.
        let mut site = zone(biome::FOREST, 2, 2, no_quotas());
        site.chunk_set = 1 + 2 + Bits::pow(15);
        site.anchors = array![(0, 105)].span();
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut progress = ProgressTrait::new(@site, seed);
            let a = one(@site, ref progress, array![].span(), 0, side::NONE);
            check_chunk(@a);
            let ground = floor(@a.terrain);
            // East (outside) and South (outside) closed, but the anchor (row 7, column 0).
            assert(BoardTrait::and(ground, super::board::EAST) == Bits::pow(105), 'east: the anchor');
            assert(BoardTrait::and(ground, super::board::SOUTH) == 0, 'south closed');
            let b = one(@site, ref progress, array![(0, a.terrain)].span(), 1, side::EAST);
            // (1, 0)'s North faces (1, 1), void: closed.
            assert(BoardTrait::and(floor(@b.terrain), super::board::NORTH) == 0, 'north void');
            assert(
                RevealTrait::kind(@site, @progress, array![].span(), 16) == ChunkKind::Void,
                'void outside the outline',
            );
            assert(
                RevealTrait::kind(@site, @progress, array![].span(), 15) == ChunkKind::Unrevealed,
                'unrevealed',
            );
            assert(
                RevealTrait::kind(@site, @progress, array![].span(), 2) == ChunkKind::Void,
                'void beyond the edge',
            );
            seed += 1;
        }
    }

    // A border chunk is cut by its tile mask after its edges are opened (N-4): nothing outside the
    // mask is floor, the ring included; a chunk of the set without a mask is whole.
    #[test]
    #[available_gas(l2_gas: 34719335)] // ceil(1.05 × 33066033 measured)
    fn test_cut_by_the_outline() {
        // Columns 0 to 11 of the chunk, as the test region's chunk (2, 0).
        let mut mask: felt252 = 0;
        let mut row: u8 = 0;
        while row != 15 {
            mask += Bits::pow(row * 15) * 0xfff;
            row += 1;
        }
        let mut site = zone(biome::MEADOW, 3, 1, no_quotas());
        site.masks = array![(2, mask)].span();
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut progress = ProgressTrait::new(@site, seed);
            let a = one(@site, ref progress, array![].span(), 2, side::NONE);
            check_chunk(@a);
            assert(BoardTrait::minus(floor(@a.terrain), mask) == 0, 'cut');
            assert(a.terrain.edges == 0, 'a zone has no edges');
            seed += 1;
        }
    }

    // A dungeon never closes before `N` and always closes at `N`: revealing every revealable chunk
    // reaches exactly `N`, then nothing is revealable and the frontier is closed; the edges agree
    // across every seam; the quotas are all placed.
    fn check_dungeon(n: u8, first: felt252, words: felt252) {
        let mut seed = first;
        while seed != first + words {
            let site = dungeon(n, exit_quota());
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            let mut exits: u8 = 0;
            let mut veins: u8 = 0;
            let mut grew = true;
            while grew {
                grew = false;
                let mut chunk: u8 = 0;
                while chunk != 225 {
                    if RevealTrait::revealable(@site, @progress, known.span(), chunk) {
                        let r = one(@site, ref progress, known.span(), chunk, side::NONE);
                        check_chunk(@r);
                        for item in r.features.objects.span() {
                            if *item.kind == object::EXIT {
                                exits += 1;
                            }
                            if *item.kind == object::VEIN {
                                veins += 1;
                            }
                        }
                        known.append((chunk, r.terrain));
                        grew = true;
                    }
                    chunk += 1;
                }
            }
            assert(progress.count == n, 'closes exactly at N');
            assert(progress.open_edges == 0, 'frontier closed');
            assert(exits == 1 && veins == 1, 'quotas placed');
            assert(progress.left == [0; 14], 'nothing owed');
            // Edges agree across each seam between two revealed chunks.
            for entry in known.span() {
                let (chunk, terrain) = *entry;
                let mut s: u8 = 0;
                while s != 4 {
                    if let Option::Some(next) = site.neighbour(chunk, s) {
                        if progress.is_revealed(next) {
                            let other = RevealTrait::known(known.span(), next);
                            assert(
                                RevealTrait::is_open(terrain.edges, s) == RevealTrait::is_open(
                                    other.edges, RevealTrait::opposite(s),
                                ),
                                'edges agree',
                            );
                        }
                    }
                    s += 1;
                }
            }
            seed += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 254365151)] // ceil(1.05 × 242252524 measured)
    fn test_dungeon_closes_at_n_6() {
        check_dungeon(6, 0, 4);
    }

    #[test]
    #[available_gas(l2_gas: 185108355)] // ceil(1.05 × 176293671 measured)
    fn test_dungeon_closes_at_n_12() {
        check_dungeon(12, 50, 2);
    }

    // The last chunks hold what is owed: a zone's quotas are all placed when every chunk is
    // revealed, whatever the order.
    #[test]
    #[available_gas(l2_gas: 45518654)] // ceil(1.05 × 43351099 measured)
    fn test_zone_quotas_all_placed() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 9, count: 1 },
                Quota { kind: quota::LANDMARK, param: 4, count: 2 }, Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut seed: felt252 = 0;
        while seed != 3 {
            let site = zone(biome::MEADOW, 3, 2, quotas);
            let mut progress = ProgressTrait::new(@site, seed);
            assert(progress.left == [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 'start');
            let mut known: Array<(u8, Terrain)> = array![];
            let mut collectors: u8 = 0;
            let mut landmarks: u8 = 0;
            for chunk in array![16_u8, 0, 2, 15, 1, 17].span() {
                let r = one(@site, ref progress, known.span(), *chunk, side::NONE);
                for item in r.features.objects.span() {
                    if *item.kind == object::COLLECTOR {
                        assert(*item.param == 9, 'collector id');
                        collectors += 1;
                    }
                    if *item.kind == object::LANDMARK {
                        landmarks += 1;
                    }
                }
                known.append((*chunk, r.terrain));
            }
            assert(collectors == 1 && landmarks == 2, 'owed placed');
            assert(progress.left == [0; 14], 'nothing owed');
            seed += 1;
        }
    }

    // A task to reach a landmark adds its quota after the location's (Open question 7); a caste
    // to kill names no template, so it adds nothing.
    #[test]
    #[available_gas(l2_gas: 208289)] // ceil(1.05 × 198370 measured)
    fn test_task_quotas() {
        let mut site = zone(biome::MEADOW, 3, 2, no_quotas());
        site
            .tasks =
                array![
                    TaskEntry { task: 1, kind: 1, param: 3 }, TaskEntry { task: 2, kind: 2, param: 7 },
                ]
            .span();
        let progress = ProgressTrait::new(@site, 0);
        assert(progress.left == [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], 'landmark task');
    }

    // A set piece's quota lays the authored chunk: its interior kept but for the openings' lines,
    // its placements kept, its edges joined.
    #[test]
    #[available_gas(l2_gas: 5453276)] // ceil(1.05 × 5193596 measured)
    fn test_set_piece_laid() {
        // An authored arena: the interior open but a wall block at rows 2–4, columns 2–4.
        let mut walls = BOARD - INTERIOR;
        let mut row: u8 = 2;
        while row != 5 {
            walls += Bits::pow(row * 15 + 2) * 7;
            row += 1;
        }
        let piece = SetPiece {
            walls,
            packs: [Default::default(), Default::default()],
            objects: [
                crate::models::chunk::Object { tile: 100, kind: object::LANDMARK, state: 0, param: 3 },
                Default::default(), Default::default(),
            ],
        };
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::SET_PIECE, param: 4, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::RUIN, 1, 1, quotas);
        site.pieces = array![(4, piece)].span();
        let mut progress = ProgressTrait::new(@site, 7);
        let a = one(@site, ref progress, array![].span(), 0, side::NONE);
        check_chunk(@a);
        assert(BoardTrait::and(floor(@a.terrain), walls - (BOARD - INTERIOR)) == 0, 'block kept');
        let [first, _, _] = a.features.objects;
        assert(first.tile == 100 && first.kind == object::LANDMARK, 'landmark kept');
        assert(progress.left == [0; 14], 'laid');
    }

    // D-140: no word panics, with any mask on any chunk.
    #[test]
    #[available_gas(l2_gas: 65883025)] // ceil(1.05 × 62745738 measured)
    fn test_no_panic_any_mask() {
        let mut seed: felt252 = 0;
        while seed != 12 {
            let mask = poseidon_hash_span([seed, 'mask'].span());
            let mut site = zone(biome::CAVE, 2, 2, exit_quota());
            site.masks = array![(0, mask), (1, BoardTrait::and(mask, INTERIOR))].span();
            site.anchors = array![(0, 0), (0, 7), (1, 112)].span();
            let mut progress = ProgressTrait::new(@site, seed);
            let a = one(@site, ref progress, array![].span(), 0, side::NONE);
            let b = one(@site, ref progress, array![(0, a.terrain)].span(), 1, side::EAST);
            assert(BoardTrait::minus(floor(@a.terrain), mask) == 0, 'cut');
            assert(BoardTrait::and(floor(@b.terrain), 1 + Bits::pow(14) + Bits::pow(210) + Bits::pow(224)) == 0, 'corners');
            seed += 1;
        }
    }

    // AC-4: the same chunk under the same entropy gives the same words; the feed is a set; a
    // reveal's word is under its own domain (never the entry draw's, never another chunk's).
    #[test]
    #[available_gas(l2_gas: 8566244)] // ceil(1.05 × 8158327 measured)
    fn test_word_and_feed() {
        let site = zone(biome::FOREST, 3, 2, no_quotas());
        let mut first = ProgressTrait::new(@site, 'entropy');
        let mut second = ProgressTrait::new(@site, 'entropy');
        let a = one(@site, ref first, array![].span(), 1, side::NONE);
        let b = one(@site, ref second, array![].span(), 1, side::NONE);
        assert(a == b, 'same entropy, same words');
        assert(first == second, 'same progress');
        // Another entropy, another chunk.
        let mut other = ProgressTrait::new(@site, 'other');
        let c = one(@site, ref other, array![].span(), 1, side::NONE);
        assert(c.terrain != a.terrain, 'another entropy');
        // The feed is a set.
        let f = EntropyTrait::reveal_fact(3, side::WEST);
        let g = EntropyTrait::reveal_fact(4, side::NONE);
        assert(
            EntropyTrait::feed(EntropyTrait::feed(9, f), g) == EntropyTrait::feed(
                EntropyTrait::feed(9, g), f,
            ),
            'order independent',
        );
        assert(EntropyTrait::feed(9, f) != EntropyTrait::feed(9, g), 'facts differ');
        assert(
            EntropyTrait::feed(9, f) != EntropyTrait::feed(9, EntropyTrait::reveal_fact(3, side::EAST)),
            'the side counts',
        );
        // The word's domain is the reveal's, per chunk.
        assert(domain(INSTANCE, 1, REVEAL) != domain(INSTANCE, 1, ENTRY), 'not the entry');
        assert(
            EntropyTrait::word(5, INSTANCE, 1) != EntropyTrait::word(5, INSTANCE, 2), 'per chunk',
        );
        // The reveal fed its fact: the entropy moved by exactly it.
        assert(
            first.entropy == EntropyTrait::feed('entropy', EntropyTrait::reveal_fact(1, side::NONE)),
            'fed',
        );
    }

    // Each biome's walkable share of the interior (design/18 *Biomes*) on the mean of 24 words, a
    // chunk with nothing known: meadow 80–90 %, forest 60–70 %, cave 45–55 %, ruin 40–50 %.
    fn share(kind: u8, words: u32) -> u32 {
        let site = zone(kind, 15, 15, no_quotas());
        let mut total: u32 = 0;
        let mut seed: u32 = 0;
        while seed != words {
            let mut progress = ProgressTrait::new(@site, seed.into());
            let chunk: u8 = if seed % 2 == 0 {
                112
            } else {
                97
            };
            let r = one(@site, ref progress, array![].span(), chunk, side::NONE);
            total += BoardTrait::count(BoardTrait::and(floor(@r.terrain), INTERIOR)).into();
            seed += 1;
        }
        // Per thousand.
        total * 1000 / (169 * words)
    }

    #[test]
    #[available_gas(l2_gas: 138132323)] // ceil(1.05 × 131554593 measured)
    fn test_biome_shares_meadow_forest() {
        let meadow = share(biome::MEADOW, 24);
        println!("meadow {}", meadow);
        assert(meadow >= 800 && meadow <= 900, 'meadow');
        let forest = share(biome::FOREST, 24);
        println!("forest {}", forest);
        assert(forest >= 600 && forest <= 700, 'forest');
    }

    #[test]
    #[available_gas(l2_gas: 139786515)] // ceil(1.05 × 133130014 measured)
    fn test_biome_shares_cave_ruin() {
        let cave = share(biome::CAVE, 24);
        println!("cave {}", cave);
        assert(cave >= 450 && cave <= 550, 'cave');
        let ruin = share(biome::RUIN, 24);
        println!("ruin {}", ruin);
        assert(ruin >= 400 && ruin <= 500, 'ruin');
    }

    // The chunks sight touches, against a scan of every tile within 6 (axial distance on global
    // coordinates), for positions across a chunk and its corners.
    fn distance(x0: i32, y0: i32, x1: i32, y1: i32) -> i32 {
        let q0 = x0 - floor_half(y0);
        let q1 = x1 - floor_half(y1);
        let dq = q1 - q0;
        let dr = y1 - y0;
        let ds = dq + dr;
        let m = if abs(dq) > abs(dr) {
            abs(dq)
        } else {
            abs(dr)
        };
        if abs(ds) > m {
            abs(ds)
        } else {
            m
        }
    }

    fn abs(v: i32) -> i32 {
        if v < 0 {
            -v
        } else {
            v
        }
    }

    fn floor_half(y: i32) -> i32 {
        if y >= 0 {
            y / 2
        } else {
            (y - 1) / 2
        }
    }

    fn oracle(x: u8, y: u8, width: u8, height: u8) -> felt252 {
        let mut touched: felt252 = 0;
        let (x, y): (i32, i32) = (x.into(), y.into());
        let mut ty = y - 6;
        while ty <= y + 6 {
            let mut tx = x - 9;
            while tx <= x + 9 {
                if tx >= 0 && ty >= 0 && tx < 15 * width.into() && ty < 15 * height.into()
                    && distance(x, y, tx, ty) <= 6 {
                    let chunk: u8 = ((ty / 15) * 15 + tx / 15).try_into().unwrap();
                    if !BoardTrait::has(touched, chunk) {
                        touched += Bits::pow(chunk);
                    }
                }
                tx += 1;
            }
            ty += 1;
        }
        touched
    }

    #[test]
    #[available_gas(l2_gas: 108751817)] // ceil(1.05 × 103573159 measured)
    fn test_sight_against_a_scan() {
        let positions: [(u8, u8); 14] = [
            (21, 21), (15, 15), (29, 29), (15, 29), (29, 15), (20, 16), (24, 28), (16, 23), (28, 22),
            (0, 0), (7, 7), (0, 40), (44, 44), (17, 19),
        ];
        for position in positions.span() {
            let (x, y) = *position;
            let chunks = SightTrait::chunks(x, y, 3, 3);
            let mut got: felt252 = 0;
            for chunk in chunks.span() {
                got += Bits::pow(*chunk);
            }
            assert(got == oracle(x, y, 3, 3), 'sight');
            assert(*chunks[0] == (y / 15) * 15 + x / 15, 'own chunk first');
        }
    }

    // ---- The vector table, `contracts/logic/vectors/reveal.jsonl` (README) --------------------

    fn hex(felts: Span<felt252>) -> ByteArray {
        let mut out: ByteArray = "[";
        let mut first = true;
        for felt in felts {
            if !first {
                out.append(@",");
            }
            first = false;
            let wide: u256 = (*felt).into();
            out.append(@format!("\"0x{:x}\"", wide));
        }
        out.append(@"]");
        out
    }

    /// Prints one vector and adds it to the digest.
    fn emit(
        ref digest: Array<felt252>,
        ref id: u32,
        name: ByteArray,
        case: Span<felt252>,
        ok: Span<felt252>,
    ) {
        println!("{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}", id, name, hex(case), hex(ok));
        digest.append(poseidon_hash_span(case));
        digest.append(poseidon_hash_span(ok));
        id += 1;
    }

    /// One `reveal` vector: the call's arguments and its results, in Cairo `Serde`.
    fn emit_reveal(
        ref digest: Array<felt252>,
        ref id: u32,
        site: @Site,
        ref progress: Progress,
        known: Span<(u8, Terrain)>,
        chunks: Span<(u8, u8)>,
    ) -> Array<Revealed> {
        let mut case: Array<felt252> = array![];
        site.serialize(ref case);
        progress.serialize(ref case);
        INSTANCE.serialize(ref case);
        known.serialize(ref case);
        chunks.serialize(ref case);
        let out = RevealTrait::reveal(site, ref progress, INSTANCE, known, chunks);
        let mut ok: Array<felt252> = array![];
        progress.serialize(ref ok);
        out.span().serialize(ref ok);
        emit(ref digest, ref id, "reveal", case.span(), ok.span());
        out
    }

    /// Part 0: the word, the feed, the base, sight, a pack's member tiles (ids from 0).
    #[test]
    #[available_gas(l2_gas: 147678374)] // ceil(1.05 × 140646070 measured)
    fn test_vectors() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        let entropies: [felt252; 3] = [0, 'entropy', -1];
        let ids: [felt252; 2] = [INSTANCE, 0x700000003];
        let chunks: [u8; 3] = [0, 112, 224];
        for entropy in entropies.span() {
            for instance in ids.span() {
                for chunk in chunks.span() {
                    let ok = EntropyTrait::word(*entropy, *instance, *chunk);
                    emit(
                        ref digest,
                        ref id,
                        "word",
                        [*entropy, *instance, (*chunk).into()].span(),
                        [ok].span(),
                    );
                }
            }
        }
        for entropy in entropies.span() {
            let mut s: u8 = 0;
            while s != 5 {
                let ok = EntropyTrait::feed(*entropy, EntropyTrait::reveal_fact(17, s));
                emit(ref digest, ref id, "feed", [*entropy, 17, s.into()].span(), [ok].span());
                s += 1;
            }
        }
        let words: [felt252; 3] = [0, 'word', -1];
        for word in words.span() {
            let mut kind: u8 = 1;
            while kind != 5 {
                let ok = BoardTrait::base(*word, kind);
                emit(ref digest, ref id, "base", [*word, kind.into()].span(), [ok].span());
                kind += 1;
            }
        }
        let positions: [(u8, u8); 12] = [
            (0, 0), (0, 105), (7, 7), (21, 21), (15, 15), (29, 29), (15, 29), (29, 15), (20, 16),
            (44, 44), (112, 112), (224, 224),
        ];
        for position in positions.span() {
            let (x, y) = *position;
            let touched = SightTrait::chunks(x, y, 15, 15);
            let mut ok: Array<felt252> = array![];
            for chunk in touched.span() {
                ok.append((*chunk).into());
            }
            emit(ref digest, ref id, "sight", [x.into(), y.into(), 15, 15].span(), ok.span());
        }
        let tiles: [u8; 3] = [112, 97, 16];
        for tile in tiles.span() {
            let mut k: u8 = 0;
            while k != 19 {
                let mut parity: u8 = 0;
                while parity != 2 {
                    let member = PackPlacementTrait::member(*tile, k, parity == 1);
                    let mut ok: Array<felt252> = array![];
                    member.serialize(ref ok);
                    emit(
                        ref digest,
                        ref id,
                        "member",
                        [(*tile).into(), k.into(), parity.into()].span(),
                        ok.span(),
                    );
                    parity += 1;
                }
                k += 1;
            }
        }
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_0, 'vectors moved: regenerate');
    }

    /// Part 1: whole reveals in zones: each biome on both row parities with nothing known; a chunk
    /// with 1 to 4 sides known; the location's edge, a void chunk and an anchor; a cut.
    #[test]
    #[available_gas(l2_gas: 275319056)] // ceil(1.05 × 262208624 measured)
    fn test_vectors_1() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_1;
        let mut kind: u8 = 1;
        while kind != 5 {
            let site = zone(kind, 3, 3, no_quotas());
            let mut progress = ProgressTrait::new(@site, kind.into());
            let out = emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![(16, side::NONE)].span());
            emit_reveal(ref digest, ref id, @site, ref progress, array![(16, *out[0].terrain)].span(), array![(1, side::NONE)].span());
            kind += 1;
        }
        // Chunk 16 after its South, East, West and North neighbours, one at a time.
        let site = zone(biome::FOREST, 3, 3, no_quotas());
        let mut progress = ProgressTrait::new(@site, 'sides');
        let mut known: Array<(u8, Terrain)> = array![];
        for chunk in array![1_u8, 15, 17, 31].span() {
            let out = emit_reveal(ref digest, ref id, @site, ref progress, known.span(), array![(*chunk, side::NONE)].span());
            known.append((*chunk, *out[0].terrain));
        }
        emit_reveal(ref digest, ref id, @site, ref progress, known.span(), array![(16, side::NORTH)].span());
        // The edge of a 2 × 2 zone with (1, 1) outside its outline, an anchor on the East side.
        let mut site = zone(biome::MEADOW, 2, 2, no_quotas());
        site.chunk_set = 1 + 2 + Bits::pow(15);
        site.anchors = array![(0, 105)].span();
        let mut progress = ProgressTrait::new(@site, 'edge');
        let out = emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![(0, side::NONE), (16, side::NONE), (1, side::EAST)].span());
        assert(out.len() == 2, 'void skipped');
        // A cut: columns 0 to 11.
        let mut mask: felt252 = 0;
        let mut row: u8 = 0;
        while row != 15 {
            mask += Bits::pow(row * 15) * 0xfff;
            row += 1;
        }
        let mut site = zone(biome::RUIN, 3, 1, no_quotas());
        site.masks = array![(2, mask)].span();
        let mut progress = ProgressTrait::new(@site, 'cut');
        emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![(2, side::NONE), (1, side::WEST)].span());
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_1, 'vectors moved: regenerate');
    }

    /// Part 2: a dungeon floor of `N` 6 to its close (the frontier's rules at `N − 1` and `N`), the
    /// quotas' draws in a zone, a set piece, a task's landmark.
    #[test]
    #[available_gas(l2_gas: 300340784)] // ceil(1.05 × 286038841 measured)
    fn test_vectors_2() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_2;
        let site = dungeon(6, exit_quota());
        let mut progress = ProgressTrait::new(@site, 'dungeon');
        let mut known: Array<(u8, Terrain)> = array![];
        let mut grew = true;
        while grew {
            grew = false;
            let mut chunk: u8 = 0;
            while chunk != 225 && !grew {
                if RevealTrait::revealable(@site, @progress, known.span(), chunk) {
                    let out = emit_reveal(ref digest, ref id, @site, ref progress, known.span(), array![(chunk, side::NONE)].span());
                    known.append((chunk, *out[0].terrain));
                    grew = true;
                }
                chunk += 1;
            }
        }
        assert(progress.count == 6, 'closed at N');
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 9, count: 1 },
                Quota { kind: quota::LANDMARK, param: 4, count: 2 },
                Quota { kind: quota::HEART, param: 2, count: 1 }, Default::default(),
                Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::MEADOW, 2, 2, quotas);
        site.tasks = array![TaskEntry { task: 1, kind: 2, param: 12 }].span();
        let mut progress = ProgressTrait::new(@site, 'quotas');
        let mut known: Array<(u8, Terrain)> = array![];
        for chunk in array![0_u8, 1, 15, 16].span() {
            let out = emit_reveal(ref digest, ref id, @site, ref progress, known.span(), array![(*chunk, side::NONE)].span());
            known.append((*chunk, *out[0].terrain));
        }
        assert(progress.left == [0; 14], 'all placed');
        let mut walls = BOARD - INTERIOR;
        walls += Bits::pow(2 * 15 + 2) * 7;
        let piece = SetPiece {
            walls,
            packs: [crate::models::set_piece::SetPack { tile: 120, template: 1 }, Default::default()],
            objects: [
                crate::models::chunk::Object { tile: 100, kind: object::COLLECTOR, state: 0, param: 3 },
                Default::default(), Default::default(),
            ],
        };
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::SET_PIECE, param: 4, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::RUIN, 2, 1, quotas);
        site.pieces = array![(4, piece)].span();
        let mut progress = ProgressTrait::new(@site, 'piece');
        emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![(0, side::NONE), (1, side::EAST)].span());
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_2, 'vectors moved: regenerate');
    }

    const PART_1: u32 = 171;
    const PART_2: u32 = 186;
    const DIGEST_0: felt252 =
        436879411965584264744368046098895752638038888232554053137264668756436767440;
    const DIGEST_1: felt252 =
        2118439584713985996522206844831907832133690588005866000966461853720682050692;
    const DIGEST_2: felt252 =
        2487151069656850120620354454503529463977834951226227166098748903113865454350;
}
