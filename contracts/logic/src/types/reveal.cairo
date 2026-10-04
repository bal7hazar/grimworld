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
    fn kind(site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8) -> ChunkKind {
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
    fn revealable(site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8) -> bool {
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
        // The loops' state starts from `zero`, 0 for every chunk index but not a constant: a loop
        // whose state starts from constants is compiled twice (a copy specialised to them), which
        // cost this class about 1,900 CASM felts (D-200).
        let zero: u8 = chunk / 255;
        let mut ring: felt252 = zero.into();
        let mut edges: u8 = zero;
        let mut copied: u8 = zero;
        // Drawable sides as bits, and those drawn open.
        let mut free: u8 = zero;
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
                        copied += 1;
                    }
                } else if site.inside(next) {
                    // [Compute] Drawn: a zone's side is open; a dungeon's a border in 7, every one
                    // once `N` are revealed; a side the mask cuts whole is no side to open (the
                    // guard below widens only toward a side it can open)
                    let border = draws.draw(BORDER.try_into().unwrap()) == 0;
                    if BoardTrait::and(BoardTrait::side(side), mask) != 0 {
                        free += bit;
                        if !emerging || (!last && !border) {
                            open += bit;
                        }
                    }
                }
            }
            side += 1;
            bit *= 2;
        }
        // [Compute] A dungeon never closes before `N` (audit #348, minor 3, and its delta review):
        // before `N`, a chunk with a side it can open keeps one open toward a chunk that can still
        // grow (a neighbour inside the rectangle, not revealed, not this chunk). Always, not only
        // when the frontier looks short: its open edges are not chunks (two edges into one
        // enclosed chunk passed that comparison), and counting the distinct chunks behind them put
        // `RevealLibrary` at 51.20 % (D-200)
        let frontier = if *progress.open_edges > copied {
            *progress.open_edges - copied
        } else {
            0
        };
        if emerging && !last && free != 0 {
            if !Self::opens_growth(site, progress, chunk, open) {
                open += Self::widen(site, progress, chunk, free, open);
            }
        }
        // [Compute] The openings of the sides drawn open, 1 or 2 each, inside the mask
        let mut drawn: u8 = zero;
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

    /// Whether `next`, once revealed, could open toward a chunk still to reveal: a neighbour inside
    /// the rectangle, not revealed, not `chunk` (which this reveal fills).
    fn grows(site: @Site, progress: @Progress, chunk: u8, next: u8) -> bool {
        let mut found = false;
        // From a value that is not a constant: `decide`'s note on specialised loops (D-200).
        let mut side: u8 = next / 255;
        while side != 4 {
            if let Option::Some(other) = site.neighbour(next, side) {
                if other != chunk && !progress.is_revealed(other) {
                    found = true;
                }
            }
            side += 1;
        }
        found
    }

    /// Whether one of `chunk`'s `open` sides faces a chunk that can grow.
    fn opens_growth(site: @Site, progress: @Progress, chunk: u8, open: u8) -> bool {
        let mut found = false;
        let mut side: u8 = chunk / 255;
        let mut bit: u8 = side + 1;
        while side != 4 {
            if (open / bit) % 2 == 1
                && Self::grows(site, progress, chunk, site.neighbour(chunk, side).unwrap()) {
                found = true;
            }
            side += 1;
            bit *= 2;
        }
        found
    }

    /// The free side to open: the first (ENG-01's order) not open yet whose chunk can grow, else
    /// the first not open yet; 0 when every free side is open.
    fn widen(site: @Site, progress: @Progress, chunk: u8, free: u8, open: u8) -> u8 {
        let mut side: u8 = chunk / 255;
        let mut first: u8 = side;
        let mut growing: u8 = side;
        let mut bit: u8 = side + 1;
        while side != 4 {
            if (free / bit) % 2 == 1 && (open / bit) % 2 == 0 {
                if first == 0 {
                    first = bit;
                }
                if growing == 0
                    && Self::grows(site, progress, chunk, site.neighbour(chunk, side).unwrap()) {
                    growing = bit;
                }
            }
            side += 1;
            bit *= 2;
        }
        if growing != 0 {
            growing
        } else {
            first
        }
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
    fn faced_open(site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8) -> bool {
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

#[cfg(test)]
pub mod tests {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use core::poseidon::poseidon_hash_span;
    use hexx::board::bits::Bits;
    use hexx::board::rng::RngTrait;
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
    use super::placement::PlacementTrait;
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
                        PackCaste { caste: 1, min: 1, max: 2 },
                        PackCaste { caste: 2, min: 1, max: 3 }, Default::default(),
                        Default::default(), Default::default(),
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
                    let member = PackPlacementTrait::member(
                        *pack.tile, index.try_into().unwrap(), row_odd,
                    )
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
        site: @Site, ref progress: Progress, known: Span<(u8, Terrain)>, chunk: u8,
    ) -> Revealed {
        let out = RevealTrait::reveal(site, ref progress, INSTANCE, known, array![chunk].span());
        assert(out.len() == 1, 'revealed');
        *out[0]
    }

    // The order of the edges (ENG-01: West, East, South, North) against `hexx`'s sides: a dungeon
    // chunk's edge bit `s` is open exactly when side `s` of its ring holds an opening.
    #[test]
    #[available_gas(l2_gas: 46703143)] // ceil(1.05 × 44479183 measured)
    fn test_edges_against_hexx_sides() {
        let sides = [Side::West, Side::East, Side::South, Side::North];
        let mut seed: felt252 = 0;
        while seed != 12 {
            let site = dungeon(12, no_quotas());
            let mut progress = ProgressTrait::new(@site, seed);
            let revealed = one(@site, ref progress, array![].span(), 112);
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
            let a = one(@site, ref progress, array![].span(), 16);
            check_chunk(@a);
            let b = one(@site, ref progress, array![(16, a.terrain)].span(), 17);
            check_chunk(@b);
            let c = one(@site, ref progress, array![(16, a.terrain)].span(), 31);
            check_chunk(@c);
            let d = one(@site, ref progress, array![(17, b.terrain), (31, c.terrain)].span(), 32);
            check_chunk(@d);
            // Every shared edge open across its seam, from both sides (`hexx`'s seams, N-2).
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@b.terrain), floor(@a.terrain), Side::East, true,
                ),
                'a-b from b',
            );
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@a.terrain), floor(@b.terrain), Side::West, true,
                ),
                'a-b from a',
            );
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@c.terrain), floor(@a.terrain), Side::South, false,
                ),
                'a-c from c',
            );
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@a.terrain), floor(@c.terrain), Side::North, true,
                ),
                'a-c from a',
            );
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@d.terrain), floor(@b.terrain), Side::South, false,
                ),
                'b-d from d',
            );
            assert(
                SeamTrait::is_open_across(
                    15, 15, floor(@d.terrain), floor(@c.terrain), Side::East, false,
                ),
                'c-d from d',
            );
            // A side at the location's edge (chunk 16's East is chunk 15, inside; chunk 0's East is
            // outside): closed.
            seed += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 181878289)] // ceil(1.05 × 173217418 measured)
    fn test_invariants_meadow() {
        check_zone_words(biome::MEADOW, 0, 6);
    }

    #[test]
    #[available_gas(l2_gas: 186463802)] // ceil(1.05 × 177584573 measured)
    fn test_invariants_forest() {
        check_zone_words(biome::FOREST, 100, 6);
    }

    #[test]
    #[available_gas(l2_gas: 188891351)] // ceil(1.05 × 179896524 measured)
    fn test_invariants_cave() {
        check_zone_words(biome::CAVE, 200, 6);
    }

    #[test]
    #[available_gas(l2_gas: 191597372)] // ceil(1.05 × 182473687 measured)
    fn test_invariants_ruin() {
        check_zone_words(biome::RUIN, 300, 6);
    }

    // The location's border and a void chunk close a side (D-134); an anchor on it stays open.
    #[test]
    #[available_gas(l2_gas: 60921420)] // ceil(1.05 × 58020400 measured)
    fn test_border_and_void_closed_but_anchors() {
        // Chunks (0, 0), (1, 0) and (0, 1) of a 2 × 2 zone; (1, 1) is outside the outline.
        let mut site = zone(biome::FOREST, 2, 2, no_quotas());
        site.chunk_set = 1 + 2 + Bits::pow(15);
        site.anchors = array![(0, 105)].span();
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut progress = ProgressTrait::new(@site, seed);
            let a = one(@site, ref progress, array![].span(), 0);
            check_chunk(@a);
            let ground = floor(@a.terrain);
            // East (outside) and South (outside) closed, but the anchor (row 7, column 0).
            assert(
                BoardTrait::and(ground, super::board::EAST) == Bits::pow(105), 'east: the anchor',
            );
            assert(BoardTrait::and(ground, super::board::SOUTH) == 0, 'south closed');
            let b = one(@site, ref progress, array![(0, a.terrain)].span(), 1);
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
    #[available_gas(l2_gas: 46300917)] // ceil(1.05 × 44096111 measured)
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
            let a = one(@site, ref progress, array![].span(), 2);
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
                        let r = one(@site, ref progress, known.span(), chunk);
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
                                RevealTrait::is_open(
                                    terrain.edges, s,
                                ) == RevealTrait::is_open(other.edges, RevealTrait::opposite(s)),
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

    /// Grows a dungeon from `progress` until nothing is revealable.
    fn grow(site: @Site, ref progress: Progress, ref known: Array<(u8, Terrain)>) {
        let mut grew = true;
        while grew {
            grew = false;
            let mut chunk: u8 = 0;
            while chunk != 225 {
                if RevealTrait::revealable(site, @progress, known.span(), chunk) {
                    let r = one(site, ref progress, known.span(), chunk);
                    known.append((chunk, r.terrain));
                    grew = true;
                }
                chunk += 1;
            }
        }
    }

    // Audit #348, minor 3: the enclosure. Six chunks revealed: (7, 7), (8, 7), (9, 7), (9, 8),
    // (7, 8), (7, 9), every side a border but those named; (8, 7) and (7, 8) open into (8, 8),
    // which every neighbour but (8, 9) surrounds; (7, 9) opens into (8, 9). Were (8, 9)'s three
    // drawn sides borders, the frontier would be (8, 8) alone, which cannot grow, and the floor
    // would close at 8 of 12. Over many words it reaches exactly `N`.
    #[test]
    #[available_gas(l2_gas: 718823410)] // ceil(1.05 × 684593723 measured)
    fn test_dungeon_enclosure_keeps_growing() {
        // (chunk, edges): West 1, East 2, South 4, North 8.
        let state: [(u8, u8); 6] = [
            (112, 1 + 8), (113, 2 + 8 + 1), (114, 2 + 8), (129, 4), (127, 4 + 1 + 8), (142, 4 + 1),
        ];
        let mut seed: felt252 = 0;
        while seed != 12 {
            let site = dungeon(12, no_quotas());
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            for entry in state.span() {
                let (chunk, edges) = *entry;
                known.append((chunk, Terrain { walls: BOARD, edges }));
                progress.revealed += BoardTrait::pow(chunk);
            }
            progress.count = 6;
            progress.open_edges = 3;
            let r = one(@site, ref progress, known.span(), 143);
            known.append((143, r.terrain));
            grow(@site, ref progress, ref known);
            assert(progress.count == 12, 'the enclosure grows to N');
            seed += 1;
        }
    }

    // The randomness re-audit of #348 (t-0075, minor 2): its hand trace on a 3 × 2 rectangle, `N`
    // 6, entered at chunk 16 (1, 1). Revealed: 16 (East into 15 and South into 1 open, West into 17
    // a border), 15 (South into 0 open), 1 (East into 0 and West into 2 open); 3 open edges, 2 of
    // them into 0. Revealing 2 then: the old guard read 2 edges against 2 chunks owed and let 2
    // draw its North side (into 17) a border; 0 then closed the floor at 5 of 6, 17 faced only by
    // borders. 17 cannot grow (its other neighbours are revealed), so no open side of 2 faces
    // growth and the guard keeps North open: every floor reaches `N`.
    #[test]
    #[available_gas(l2_gas: 330842682)] // ceil(1.05 × 315088268 measured)
    fn test_dungeon_reaudit_trace_keeps_growing() {
        // (chunk, edges): West 1, East 2, South 4, North 8.
        let state: [(u8, u8); 3] = [(16, 2 + 4), (15, 1 + 4), (1, 8 + 2 + 1)];
        let mut seed: felt252 = 0;
        while seed != 12 {
            let mut site = dungeon(6, no_quotas());
            site.width = 3;
            site.height = 2;
            site.entry_chunk = 16;
            site.anchors = array![(16, 112)].span();
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            for entry in state.span() {
                let (chunk, edges) = *entry;
                known.append((chunk, Terrain { walls: BOARD, edges }));
                progress.revealed += BoardTrait::pow(chunk);
            }
            progress.count = 3;
            progress.open_edges = 3;
            let r = one(@site, ref progress, known.span(), 2);
            assert(r.terrain.edges / 8 == 1, 'North kept open');
            known.append((2, r.terrain));
            grow(@site, ref progress, ref known);
            assert(progress.count == 6, 'the trace grows to N');
            seed += 1;
        }
    }

    /// A dungeon of `N` 12 in a 5 × 5 rectangle, entered at its centre (2, 2): crowded, so that
    /// enclosures are frequent.
    fn small_dungeon() -> Site {
        let mut site = dungeon(12, exit_quota());
        site.width = 5;
        site.height = 5;
        site.entry_chunk = 32;
        site.anchors = array![(32, 112)].span();
        site
    }

    fn sweep(first: felt252, words: felt252) {
        let mut seed = first;
        while seed != first + words {
            let site = small_dungeon();
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            grow(@site, ref progress, ref known);
            assert(progress.count == 12, 'closes exactly at N');
            assert(progress.left == [0; 14], 'nothing owed');
            seed += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 346056356)] // ceil(1.05 × 329577481 measured)
    fn test_dungeon_sweep_small_rectangle_0() {
        sweep(1000, 5);
    }

    #[test]
    #[available_gas(l2_gas: 349098280)] // ceil(1.05 × 332474552 measured)
    fn test_dungeon_sweep_small_rectangle_1() {
        sweep(2000, 5);
    }

    /// Grows a dungeon from `progress` one chunk at a time until nothing is revealable, each time
    /// the first revealable chunk (`order` 0), the last (1), or one drawn from `seed` (2).
    fn grow_in_order(
        site: @Site,
        ref progress: Progress,
        ref known: Array<(u8, Terrain)>,
        order: u8,
        seed: felt252,
    ) {
        let mut step: felt252 = 0;
        loop {
            let mut revealable: Array<u8> = array![];
            let mut chunk: u8 = 0;
            while chunk != 225 {
                if RevealTrait::revealable(site, @progress, known.span(), chunk) {
                    revealable.append(chunk);
                }
                chunk += 1;
            }
            let n = revealable.len();
            if n == 0 {
                break;
            }
            let at: u32 = if order == 0 {
                0
            } else if order == 1 {
                n - 1
            } else {
                let hash: u256 = poseidon_hash_span([seed, step].span()).into();
                (hash % n.into()).try_into().unwrap()
            };
            let chunk = *revealable[at];
            let r = one(site, ref progress, known.span(), chunk);
            known.append((chunk, r.terrain));
            step += 1;
        }
    }

    /// A dungeon of `N` 12 in a `width × height` rectangle entered at (1, 1): `N` close to the
    /// area, so that enclosures are frequent.
    fn tight_dungeon(width: u8, height: u8) -> Site {
        let mut site = dungeon(12, exit_quota());
        site.width = width;
        site.height = height;
        site.entry_chunk = 16;
        site.anchors = array![(16, 112)].span();
        site
    }

    fn sweep_in_order(width: u8, height: u8, first: felt252, words: felt252, order: u8) {
        let mut seed = first;
        while seed != first + words {
            let site = tight_dungeon(width, height);
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            grow_in_order(@site, ref progress, ref known, order, seed);
            if progress.count != 12 {
                println!(
                    "closed at {} of 12: {} x {}, seed {}, order {}",
                    progress.count,
                    width,
                    height,
                    seed,
                    order,
                );
            }
            assert(progress.count == 12, 'closes exactly at N');
            assert(progress.left == [0; 14], 'nothing owed');
            seed += 1;
        }
    }

    // The delta review of #348: `N` close to the rectangle's area (12 of 16, 12 of 15), the reveals
    // in descending and in drawn orders, so that a closure before `N` would show. At `N` equal to
    // the area (12 of 4 × 3) a floor can close early (word 5100, a drawn order: 11 of 12): the
    // guard is local, and the last chunks can be walled in by their revealed neighbours' borders;
    // ENG-05's report proposes a content rule (a floor's rectangle larger than `N`).
    #[test]
    #[available_gas(l2_gas: 1007107555)] // ceil(1.05 × 959150052 measured)
    fn test_dungeon_sweep_tight_descending() {
        sweep_in_order(4, 4, 3000, 6, 1);
    }

    #[test]
    #[available_gas(l2_gas: 993693215)] // ceil(1.05 × 946374490 measured)
    fn test_dungeon_sweep_tight_drawn() {
        sweep_in_order(4, 4, 4000, 6, 2);
    }

    #[test]
    #[available_gas(l2_gas: 989363329)] // ceil(1.05 × 942250789 measured)
    fn test_dungeon_sweep_near_area() {
        sweep_in_order(5, 3, 5000, 3, 1);
        sweep_in_order(5, 3, 5100, 3, 2);
    }

    // The delta review of #348: two open edges into one chunk. Revealed: (7, 8) = 127 opening West
    // and (9, 8) = 129 opening East into (8, 8) = 128, (8, 7) = 113 closed toward it, (9, 9) = 144
    // opening East into (8, 9) = 143, (7, 9) = 142 closed toward it; every other side a border.
    // Revealing 143 with `N` 8: 2 chunks owed after it, 2 open edges left, but one chunk behind
    // them, which cannot grow (its neighbours are revealed). The old guard compared edges (2) with
    // chunks (2) and let 143 draw its North side a border: then 128 alone was left and the floor
    // closed at 7 of 8. The guard keeps growth always: 143 keeps North open whenever its draw is a
    // border.
    #[test]
    #[available_gas(l2_gas: 813587258)] // ceil(1.05 × 774845007 measured)
    fn test_dungeon_two_edges_into_one_chunk() {
        let state: [(u8, u8); 5] = [(127, 1), (129, 2), (113, 0), (144, 2), (142, 0)];
        let revealed = BoardTrait::pow(127)
            + BoardTrait::pow(129)
            + BoardTrait::pow(113)
            + BoardTrait::pow(144)
            + BoardTrait::pow(142);
        let mut widened: u8 = 0;
        let mut seed: felt252 = 0;
        while seed != 16 {
            let site = dungeon(8, no_quotas());
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            for entry in state.span() {
                let (chunk, edges) = *entry;
                known.append((chunk, Terrain { walls: BOARD, edges }));
            }
            progress.revealed = revealed;
            progress.count = 5;
            progress.open_edges = 3;
            // 143's ring draws: South (into 128), then North; a border is a draw of 0
            let word = EntropyTrait::word(seed, INSTANCE, 143);
            let mut draws = RngTrait::new(RngTrait::mix(word, 4));
            let _south = draws.draw(7);
            let north_border = draws.draw(7) == 0;
            let r = one(@site, ref progress, known.span(), 143);
            if north_border {
                assert(r.terrain.edges / 8 == 1, 'North kept open');
                widened += 1;
            }
            known.append((143, r.terrain));
            grow(@site, ref progress, ref known);
            assert(progress.count == 8, 'grows to N');
            seed += 1;
        }
        assert(widened != 0, 'the old guard closed one');
    }

    #[test]
    #[available_gas(l2_gas: 323999616)] // ceil(1.05 × 308571062 measured)
    fn test_dungeon_closes_at_n_6() {
        check_dungeon(6, 0, 4);
    }

    #[test]
    #[available_gas(l2_gas: 248456640)] // ceil(1.05 × 236625371 measured)
    fn test_dungeon_closes_at_n_12() {
        check_dungeon(12, 50, 2);
    }

    // The last chunks hold what is owed: a zone's quotas are all placed when every chunk is
    // revealed, whatever the order.
    #[test]
    #[available_gas(l2_gas: 55536103)] // ceil(1.05 × 52891526 measured)
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
            let mut site = zone(biome::MEADOW, 3, 2, quotas);
            let _hosts = hosted(ref site, seed);
            let mut progress = ProgressTrait::new(@site, seed);
            assert(progress.left == [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 'start');
            let mut known: Array<(u8, Terrain)> = array![];
            let mut collectors: u8 = 0;
            let mut landmarks: u8 = 0;
            for chunk in array![16_u8, 0, 2, 15, 1, 17].span() {
                let r = one(@site, ref progress, known.span(), *chunk);
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
                    TaskEntry { task: 1, kind: 1, param: 3 },
                    TaskEntry { task: 2, kind: 2, param: 7 },
                ]
            .span();
        let progress = ProgressTrait::new(@site, 0);
        assert(progress.left == [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], 'landmark task');
    }

    // A set piece's quota lays the authored chunk: its interior kept but for the openings' lines,
    // its placements kept, its edges joined.
    #[test]
    #[available_gas(l2_gas: 7804984)] // ceil(1.05 × 7433318 measured)
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
                crate::models::chunk::Object {
                    tile: 100, kind: object::LANDMARK, state: 0, param: 3,
                },
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
        let _hosts = hosted(ref site, 7);
        let mut progress = ProgressTrait::new(@site, 7);
        let a = one(@site, ref progress, array![].span(), 0);
        check_chunk(@a);
        assert(BoardTrait::and(floor(@a.terrain), walls - (BOARD - INTERIOR)) == 0, 'block kept');
        let [first, _, _] = a.features.objects;
        assert(first.tile == 100 && first.kind == object::LANDMARK, 'landmark kept');
        assert(progress.left == [0; 14], 'laid');
    }

    // D-140: no word panics, with any mask on any chunk.
    #[test]
    #[available_gas(l2_gas: 73572985)] // ceil(1.05 × 70069509 measured)
    fn test_no_panic_any_mask() {
        let mut seed: felt252 = 0;
        while seed != 12 {
            let mask = poseidon_hash_span([seed, 'mask'].span());
            let mut site = zone(biome::CAVE, 2, 2, exit_quota());
            site.masks = array![(0, mask), (1, BoardTrait::and(mask, INTERIOR))].span();
            site.anchors = array![(0, 0), (0, 7), (1, 112)].span();
            let mut progress = ProgressTrait::new(@site, seed);
            let a = one(@site, ref progress, array![].span(), 0);
            let b = one(@site, ref progress, array![(0, a.terrain)].span(), 1);
            assert(BoardTrait::minus(floor(@a.terrain), mask) == 0, 'cut');
            assert(
                BoardTrait::and(
                    floor(@b.terrain), 1 + Bits::pow(14) + Bits::pow(210) + Bits::pow(224),
                ) == 0,
                'corners',
            );
            seed += 1;
        }
    }

    // AC-4: the same chunk under the same entropy gives the same words; the feed is a set; a
    // reveal's word is under its own domain (never the entry draw's, never another chunk's).
    #[test]
    #[available_gas(l2_gas: 9491645)] // ceil(1.05 × 9039661 measured)
    fn test_word_and_feed() {
        let site = zone(biome::FOREST, 3, 2, no_quotas());
        let mut first = ProgressTrait::new(@site, 'entropy');
        let mut second = ProgressTrait::new(@site, 'entropy');
        let a = one(@site, ref first, array![].span(), 1);
        let b = one(@site, ref second, array![].span(), 1);
        assert(a == b, 'same entropy, same words');
        assert(first == second, 'same progress');
        // Another entropy, another chunk.
        let mut other = ProgressTrait::new(@site, 'other');
        let c = one(@site, ref other, array![].span(), 1);
        assert(c.terrain != a.terrain, 'another entropy');
        // A reveal feeds nothing: the entropy is the entry draw's (audit #348, major 1).
        assert(first.entropy == 'entropy', 'not fed');
        // The feed is a multiset: order-free, each fact counted.
        let f = ['fact:test', 3].span();
        let g = ['fact:test', 4].span();
        assert(
            EntropyTrait::feed(
                EntropyTrait::feed(9, f), g,
            ) == EntropyTrait::feed(EntropyTrait::feed(9, g), f),
            'order independent',
        );
        assert(EntropyTrait::feed(9, f) != EntropyTrait::feed(9, g), 'facts differ');
        assert(
            EntropyTrait::feed(EntropyTrait::feed(9, f), f) != EntropyTrait::feed(9, f),
            'a fact twice counts twice',
        );
        // The word's domain is the reveal's, per chunk.
        assert(domain(INSTANCE, 1, REVEAL) != domain(INSTANCE, 1, ENTRY), 'not the entry');
        assert(
            EntropyTrait::word(5, INSTANCE, 1) != EntropyTrait::word(5, INSTANCE, 2), 'per chunk',
        );
    }

    // The order of the reveals is no free choice (audit #348, major 1): in a 3 × 1 zone, chunks 0
    // and 2 revealed in either order, then chunk 1 between them (the same neighbours known), give
    // the same words for every chunk.
    #[test]
    #[available_gas(l2_gas: 14076947)] // ceil(1.05 × 13406616 measured)
    fn test_reveal_order_free() {
        let site = zone(biome::CAVE, 3, 1, no_quotas());
        let mut ab = ProgressTrait::new(@site, 'order');
        let a = one(@site, ref ab, array![].span(), 0);
        let b = one(@site, ref ab, array![].span(), 2);
        let middle = one(@site, ref ab, array![(0, a.terrain), (2, b.terrain)].span(), 1);
        let mut ba = ProgressTrait::new(@site, 'order');
        let b2 = one(@site, ref ba, array![].span(), 2);
        let a2 = one(@site, ref ba, array![].span(), 0);
        let middle2 = one(@site, ref ba, array![(2, b2.terrain), (0, a2.terrain)].span(), 1);
        assert(a == a2 && b == b2, 'the first two');
        assert(middle == middle2, 'the one between');
        assert(ab == ba, 'the same progress');
    }

    /// A zone's hosts as `Instances` draws them at `create` (D-208, D-210), from the progress's
    /// entropy `entropy`: `site`'s masks rebuilt for every chunk of the zone, each carrying the
    /// quotas the chunk hosts. Returns the hosts.
    pub fn hosted(ref site: Site, entropy: felt252) -> Array<felt252> {
        let start = ProgressTrait::new(@site, entropy);
        let hosts = PlacementTrait::hosts(
            site.chunk_set,
            site.width,
            site.height,
            PlacementTrait::plan(@site, start.left.span()),
            site.pieces,
            EntropyTrait::hosts(entropy, INSTANCE),
        );
        let mut masks: Array<(u8, felt252)> = array![];
        let mut cy: u8 = 0;
        while cy != site.height {
            let mut cx: u8 = 0;
            while cx != site.width {
                let chunk = 15 * cy + cx;
                if site.chunk_set == 0 || BoardTrait::has(site.chunk_set, chunk) {
                    let mut mask: felt252 = 0;
                    for entry in site.masks {
                        let (at, value) = *entry;
                        if at == chunk {
                            mask = value;
                        }
                    }
                    masks.append((chunk, PlacementTrait::with_hosts(mask, hosts.span(), chunk)));
                }
                cx += 1;
            }
            cy += 1;
        }
        site.masks = masks.span();
        hosts
    }

    /// The quota objects each chunk of `order` holds (collector, landmark, vein: bits 1, 2, 4),
    /// revealed in that order, each knowing the ones before it; and the progress at the end.
    fn zone_objects(site: @Site, seed: felt252, order: Span<u8>) -> (Felt252Dict<u8>, Progress) {
        let mut progress = ProgressTrait::new(site, seed);
        let mut known: Array<(u8, Terrain)> = array![];
        let mut held: Felt252Dict<u8> = Default::default();
        for chunk in order {
            let r = one(site, ref progress, known.span(), *chunk);
            let mut bits: u8 = 0;
            for item in r.features.objects.span() {
                if *item.kind == object::COLLECTOR {
                    bits += 1;
                } else if *item.kind == object::LANDMARK {
                    bits += 2;
                } else if *item.kind == object::VEIN {
                    bits += 4;
                }
            }
            held.insert((*chunk).into(), bits);
            known.append((*chunk, r.terrain));
        }
        (held, progress)
    }

    // D-208 (the project manager, 2026-10-03): a zone's quotas land exactly on their hosts, drawn
    // once at `create`. A 3 × 3 zone with quotas of 3, 2 and 1, revealed forward and backward over
    // 6 entropies: each quota has `count` hosts, and in both orders every chunk holds exactly the
    // quotas it hosts, nothing forced, nothing owed at the end.
    #[test]
    #[available_gas(l2_gas: 318207046)] // ceil(1.05 × 303054329 measured)
    fn test_zone_quota_hosts_order_free() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 3 },
                Quota { kind: quota::LANDMARK, param: 4, count: 2 },
                Quota { kind: quota::VEIN, param: 0, count: 1 }, Default::default(),
                Default::default(), Default::default(),
            ],
        };
        let forward = array![0_u8, 1, 2, 15, 16, 17, 30, 31, 32].span();
        let backward = array![32_u8, 31, 30, 17, 16, 15, 2, 1, 0].span();
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut site = zone(biome::MEADOW, 3, 3, quotas);
            let hosts = hosted(ref site, seed);
            assert(BoardTrait::count(*hosts[0]) == 3, 'three collector hosts');
            assert(BoardTrait::count(*hosts[1]) == 2, 'two landmark hosts');
            assert(BoardTrait::count(*hosts[2]) == 1, 'one vein host');
            let (mut a, end_a) = zone_objects(@site, seed, forward);
            let (mut b, end_b) = zone_objects(@site, seed, backward);
            for chunk in forward {
                let key: felt252 = (*chunk).into();
                let mut expected: u8 = 0;
                if BoardTrait::has(*hosts[0], *chunk) {
                    expected += 1;
                }
                if BoardTrait::has(*hosts[1], *chunk) {
                    expected += 2;
                }
                if BoardTrait::has(*hosts[2], *chunk) {
                    expected += 4;
                }
                assert(a.get(key) == expected, 'forward: on its hosts');
                assert(b.get(key) == expected, 'backward: on its hosts');
            }
            assert(end_a.left == [0; 14] && end_b.left == [0; 14], 'nothing owed');
            seed += 1;
        }
    }

    // The re-audit at 46d7d89 (major 1): a host must be able to lay its quota. A 2 × 1 zone with a
    // set piece of three objects (the objects' cap) and a collector, each once: the collector is
    // never drawn onto the set piece's chunk (refused, its successor taken), and lands on the
    // other chunk in both orders, nothing owed.
    #[test]
    #[available_gas(l2_gas: 89715796)] // ceil(1.05 × 85443615 measured)
    fn test_hosts_respect_the_caps() {
        let mut walls = BOARD - INTERIOR;
        walls += Bits::pow(2 * 15 + 2) * 7;
        let piece = SetPiece {
            walls,
            packs: [Default::default(), Default::default()],
            objects: [
                crate::models::chunk::Object {
                    tile: 100, kind: object::LANDMARK, state: 0, param: 3,
                },
                crate::models::chunk::Object {
                    tile: 101, kind: object::LANDMARK, state: 0, param: 3,
                },
                crate::models::chunk::Object {
                    tile: 102, kind: object::LANDMARK, state: 0, param: 3,
                },
            ],
        };
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::SET_PIECE, param: 4, count: 1 },
                Quota { kind: quota::COLLECTOR, param: 9, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut seed: felt252 = 0;
        while seed != 8 {
            let mut site = zone(biome::RUIN, 2, 1, quotas);
            site.pieces = array![(4, piece)].span();
            let hosts = hosted(ref site, seed);
            assert(*hosts[0] != 0 && *hosts[1] != 0, 'both hosted');
            assert(*hosts[0] != *hosts[1], 'not on the set piece');
            let collector: u8 = if BoardTrait::has(*hosts[1], 0) {
                0
            } else {
                1
            };
            for order in array![array![0_u8, 1].span(), array![1_u8, 0].span()] {
                let mut progress = ProgressTrait::new(@site, seed);
                let mut known: Array<(u8, Terrain)> = array![];
                for chunk in order {
                    let r = one(@site, ref progress, known.span(), *chunk);
                    let mut collectors: u8 = 0;
                    for item in r.features.objects.span() {
                        if *item.kind == object::COLLECTOR {
                            collectors += 1;
                        }
                    }
                    assert(
                        collectors == if *chunk == collector {
                            1
                        } else {
                            0
                        },
                        'the collector on its host',
                    );
                    known.append((*chunk, r.terrain));
                }
                assert(progress.left == [0; 14], 'nothing owed');
            }
            seed += 1;
        }
    }

    // The re-audit at 46d7d89 (major 1) and the review's minor 1: an exact draw over the zone's
    // members, no cap on the draws. A 15 × 15 rectangle whose chunk set is 16 chunks, a quota of
    // 4: every quota finds its 4 hosts, all in the set.
    #[test]
    #[available_gas(l2_gas: 62124437)] // ceil(1.05 × 59166130 measured)
    fn test_hosts_in_a_sparse_set() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 4 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut set: felt252 = 0;
        for chunk in array![
            0_u8, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 14, 224,
        ] {
            set += BoardTrait::pow(chunk);
        }
        let mut seed: felt252 = 0;
        while seed != 8 {
            let mut site = zone(biome::MEADOW, 15, 15, quotas);
            site.chunk_set = set;
            let hosts = hosted(ref site, seed);
            assert(BoardTrait::count(*hosts[0]) == 4, 'four hosts');
            assert(BoardTrait::minus(*hosts[0], set) == 0, 'in the set');
            seed += 1;
        }
    }

    // D-208: a Heart's pack takes the band's top level wherever it lands, here the entry chunk of
    // a dungeon (band 3 to 5, distance 0: level 3), its Heart forced there (6 owed of 6 chunks).
    #[test]
    #[available_gas(l2_gas: 17309254)] // ceil(1.05 × 16485003 measured)
    fn test_heart_at_the_band_top() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::HEART, param: 2, count: 6 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut seed: felt252 = 0;
        while seed != 4 {
            let site = dungeon(6, quotas);
            let mut progress = ProgressTrait::new(@site, seed);
            let r = one(@site, ref progress, array![].span(), 112);
            let heart = *r.features.packs.span()[0];
            assert(heart.template == 2, 'the Heart first');
            assert(heart.level == 5, 'the band top');
            seed += 1;
        }
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
            let r = one(@site, ref progress, array![].span(), chunk);
            total += BoardTrait::count(BoardTrait::and(floor(@r.terrain), INTERIOR)).into();
            seed += 1;
        }
        // Per thousand.
        total * 1000 / (169 * words)
    }

    #[test]
    #[available_gas(l2_gas: 154705958)] // ceil(1.05 × 147339007 measured)
    fn test_biome_shares_meadow_forest() {
        let meadow = share(biome::MEADOW, 24);
        println!("meadow {}", meadow);
        assert(meadow >= 800 && meadow <= 900, 'meadow');
        let forest = share(biome::FOREST, 24);
        println!("forest {}", forest);
        assert(forest >= 600 && forest <= 700, 'forest');
    }

    #[test]
    #[available_gas(l2_gas: 157579021)] // ceil(1.05 × 150075258 measured)
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
                if tx >= 0 && ty >= 0 && tx < 15
                    * width.into() && ty < 15
                    * height.into() && distance(x, y, tx, ty) <= 6 {
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
    #[available_gas(l2_gas: 123959335)] // ceil(1.05 × 118056509 measured)
    fn test_sight_against_a_scan() {
        let positions: [(u8, u8); 14] = [
            (21, 21), (15, 15), (29, 29), (15, 29), (29, 15), (20, 16), (24, 28), (16, 23),
            (28, 22), (0, 0), (7, 7), (0, 40), (44, 44), (17, 19),
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
        chunks: Span<u8>,
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
                let ok = EntropyTrait::feed(*entropy, ['fact:test', 17, s.into()].span());
                emit(
                    ref digest,
                    ref id,
                    "feed",
                    [*entropy, 'fact:test', 17, s.into()].span(),
                    [ok].span(),
                );
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
    #[available_gas(l2_gas: 255133799)] // ceil(1.05 × 242984570 measured)
    fn test_vectors_1() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_1;
        let mut kind: u8 = 1;
        while kind != 5 {
            let site = zone(kind, 3, 3, no_quotas());
            let mut progress = ProgressTrait::new(@site, kind.into());
            let out = emit_reveal(
                ref digest, ref id, @site, ref progress, array![].span(), array![16].span(),
            );
            emit_reveal(
                ref digest,
                ref id,
                @site,
                ref progress,
                array![(16, *out[0].terrain)].span(),
                array![1].span(),
            );
            kind += 1;
        }
        // Chunk 16 after its South, East, West and North neighbours, one at a time.
        let site = zone(biome::FOREST, 3, 3, no_quotas());
        let mut progress = ProgressTrait::new(@site, 'sides');
        let mut known: Array<(u8, Terrain)> = array![];
        for chunk in array![1_u8, 15, 17, 31].span() {
            let out = emit_reveal(
                ref digest, ref id, @site, ref progress, known.span(), array![(*chunk)].span(),
            );
            known.append((*chunk, *out[0].terrain));
        }
        emit_reveal(ref digest, ref id, @site, ref progress, known.span(), array![16].span());
        // The edge of a 2 × 2 zone with (1, 1) outside its outline, an anchor on the East side.
        let mut site = zone(biome::MEADOW, 2, 2, no_quotas());
        site.chunk_set = 1 + 2 + Bits::pow(15);
        site.anchors = array![(0, 105)].span();
        let mut progress = ProgressTrait::new(@site, 'edge');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![(0), (16), (1)].span(),
        );
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
        emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![(2), (1)].span(),
        );
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_1, 'vectors moved: regenerate');
    }

    /// Part 2: a dungeon floor of `N` 6 to its close (the frontier's rules at `N − 1` and `N`),
    /// a zone's quotas on their hosts (D-208), a set piece, a task's landmark.
    #[test]
    #[available_gas(l2_gas: 320278864)] // ceil(1.05 × 305027489 measured)
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
                    let out = emit_reveal(
                        ref digest, ref id, @site, ref progress, known.span(), array![chunk].span(),
                    );
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
        // The zone's hosts above each chunk's mask (D-208), as `Instances` gives them
        let _hosts = hosted(ref site, 'quotas');
        let mut progress = ProgressTrait::new(@site, 'quotas');
        let mut known: Array<(u8, Terrain)> = array![];
        for chunk in array![0_u8, 1, 15, 16].span() {
            let out = emit_reveal(
                ref digest, ref id, @site, ref progress, known.span(), array![(*chunk)].span(),
            );
            known.append((*chunk, *out[0].terrain));
        }
        assert(progress.left == [0; 14], 'all placed');
        let mut walls = BOARD - INTERIOR;
        walls += Bits::pow(2 * 15 + 2) * 7;
        let piece = SetPiece {
            walls,
            packs: [
                crate::models::set_piece::SetPack { tile: 120, template: 1 }, Default::default(),
            ],
            objects: [
                crate::models::chunk::Object {
                    tile: 100, kind: object::COLLECTOR, state: 0, param: 3,
                },
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
        emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![(0), (1)].span(),
        );
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_2, 'vectors moved: regenerate');
    }

    const PART_1: u32 = 171;
    const PART_2: u32 = 186;
    const DIGEST_0: felt252 =
        1099007504077458561703646988744304604964174275844371738808055141155867483297;
    const DIGEST_1: felt252 =
        499845782167855331826439961529088808781201279688007834938530756287138363393;
    const DIGEST_2: felt252 =
        1650752973733343143218738346291621832024875186682030611912877301196377371421;
}
