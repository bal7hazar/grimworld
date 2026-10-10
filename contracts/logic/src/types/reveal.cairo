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
//!    drawn: in a zone open, with 1 or 2 openings from the chunk's stream; in a dungeon open
//!    exactly when its seam is in the outline drawn at `create` (`outline`, ENG-10a, D-223), its
//!    1 or 2 openings from the seam's own stream (D-224), so both chunks of a seam draw the same
//!    tiles whichever is revealed first; a side the mask cuts whole is never opened), then every
//!    opening and anchor joined to the spine;
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
//! the design accepts). **A dungeon floor's outline is drawn at `create`** (ENG-10a, D-223, built
//! by ENG-10b): its chunks, its open seams and its quotas' hosts, the exit's and the Heart's among
//! its farthest chunks, read the entry draw alone, and a seam's openings its own stream (D-224):
//! no order of moves changes which chunks a floor holds, where its exit lands, how far it is from
//! the entry, in chunks or in tiles (the dungeon residue of #348's re-audits, removed). Every
//! quota lands on hosts drawn once at entry, carried above each chunk's mask (bit `225 + i`):
//! order-free.
//!
//! **What is revealable** (`kind`): a chunk inside the location and in its chunk set (a zone's,
//! the whole rectangle when the location has none; a dungeon's outline), not yet revealed: sight
//! reveals it. Anything else is void (outside the rectangle, the chunk set or the outline). A chunk
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

/// The reveal of an authored zone (D-214, D-215; ENG-09).
pub mod authored;
pub mod board;
pub mod outline;
pub mod placement;
use core::poseidon::poseidon_hash_span;
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
    /// `N`, a dungeon floor's chunks; 0 for a zone.
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
    /// A dungeon floor's outline (`outline::Outline::chunks`, drawn at `create`, ENG-10b).
    pub chunk_set: felt252,
    /// A dungeon floor's open seams, drawn at `create` (`outline::Outline`): bit `c` of `west`,
    /// the seam between `c` and `c + 1` (`c`'s West side); of `north`, between `c` and `c + 15`.
    /// 0 in a zone.
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
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Progress {
    /// Bit `15 cy + cx`.
    pub revealed: felt252,
    pub count: u8,
    /// ENG-05's open edges of a dungeon's frontier: 0 since ENG-10b (a floor's outline is drawn at
    /// `create`), the field kept for the `Quotas` word's layout.
    pub open_edges: u8,
    /// Left to place of quota `i`: the location's 6, then the tasks' 8.
    pub left: [u8; 14],
    pub entropy: felt252,
}

/// `Progress`' Serde, the derived one's encoding (`left`'s 14 values one felt each, no length),
/// its 14 values taken in one `multi_pop_front`: the derived `[u8; 14]` went through one generic
/// function a remaining length, ~1,100 CASM felts of `Instances` (ENG-05b, D-209).
pub impl ProgressSerde of Serde<Progress> {
    fn serialize(self: @Progress, ref output: Array<felt252>) {
        output.append(*self.revealed);
        output.append((*self.count).into());
        output.append((*self.open_edges).into());
        let [l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13] = *self.left;
        output.append(l0.into());
        output.append(l1.into());
        output.append(l2.into());
        output.append(l3.into());
        output.append(l4.into());
        output.append(l5.into());
        output.append(l6.into());
        output.append(l7.into());
        output.append(l8.into());
        output.append(l9.into());
        output.append(l10.into());
        output.append(l11.into());
        output.append(l12.into());
        output.append(l13.into());
        output.append(*self.entropy);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<Progress> {
        let revealed = Serde::deserialize(ref serialized)?;
        let count = Serde::deserialize(ref serialized)?;
        let open_edges = Serde::deserialize(ref serialized)?;
        let [l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13] = *serialized
            .multi_pop_front::<14>()?
            .as_snapshot()
            .unbox();
        let entropy = Serde::deserialize(ref serialized)?;
        Option::Some(
            Progress {
                revealed,
                count,
                open_edges,
                left: [
                    l0.try_into()?, l1.try_into()?, l2.try_into()?, l3.try_into()?, l4.try_into()?,
                    l5.try_into()?, l6.try_into()?, l7.try_into()?, l8.try_into()?, l9.try_into()?,
                    l10.try_into()?, l11.try_into()?, l12.try_into()?, l13.try_into()?,
                ],
                entropy,
            },
        )
    }
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
    /// Whether the site is a dungeon floor (`N` > 0; ENG-05's name, from when its outline emerged:
    /// since ENG-10b it is drawn at `create`).
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
        // A dungeon's chunk set is its outline (never 0)
        let set = *self.chunk_set;
        set == 0 || BoardTrait::has(set, chunk)
    }

    /// Whether the seam on `side` of `chunk`, toward `next`, is open in a dungeon's outline.
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
        ChunkKind::Unrevealed
    }

    /// Whether `chunk` can be revealed now: not revealed, and inside the location (a zone's
    /// chunk set or a dungeon's outline; sight reveals it).
    fn revealable(
        site: @Site, progress: @Progress, _known: Span<(u8, Terrain)>, chunk: u8,
    ) -> bool {
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
            site, @progress, instance_id, known, chunk, mask, ref draws,
        );
        let mut anchors: Array<u8> = array![];
        let mut ring = ring;
        let mut inner: felt252 = 0;
        for entry in *site.anchors {
            let (at, tile) = *entry;
            if at == chunk && tile < 225 {
                if BoardTrait::has(INTERIOR, tile) {
                    // The line holds the tile (`anchor_line`), so one or joins both (ENG-05c:
                    // ENG-05's `pow(tile) + anchor_line(tile)` carried).
                    inner = BoardTrait::or(inner, BoardTrait::anchor_line(tile));
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

    /// The ring of a chunk and, for a dungeon, its edges (module doc, step 3). ENG-10b: the open
    /// edges are 0 (no frontier); the third value is kept so that `generate` reads as ENG-05's.
    fn decide(
        site: @Site,
        progress: @Progress,
        instance_id: felt252,
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
                    // [Compute] ENG-10b: a zone's side is open; a dungeon's is open exactly when
                    // its seam is, drawn at `create`. ENG-05's border draw is kept, unread, so that
                    // a zone's streams do not move; a side the mask cuts whole is no side to open
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
        // [Compute] The openings of the sides drawn open, 1 or 2 each, inside the mask. D-224: a
        // dungeon's from its seam's own stream, keyed by the seam (its lower chunk, its axis) and
        // the outline's seed, so that both chunks of a seam draw the same tiles, whichever is
        // revealed first; a zone's from the chunk's stream, as before
        let seams = if emerging {
            EntropyTrait::outline(*progress.entropy, instance_id)
        } else {
            0
        };
        let mut side: u8 = zero;
        let mut rest = open;
        while side != 4 {
            let (above, here) = DivRem::div_rem(rest, 2);
            rest = above;
            if here == 1 {
                let allowed = BoardTrait::and(BoardTrait::side(side), mask);
                let drawn = if emerging {
                    let (low, axis): (u8, u8) = if side == side::WEST {
                        (chunk, 0)
                    } else if side == side::EAST {
                        (chunk - 1, 0)
                    } else if side == side::SOUTH {
                        (chunk - 15, 1)
                    } else {
                        (chunk, 1)
                    };
                    let mut seam = RngTrait::new(
                        poseidon_hash_span([seams, low.into(), axis.into()].span()),
                    );
                    Self::openings(allowed, side, ref seam)
                } else {
                    Self::openings(allowed, side, ref draws)
                };
                if drawn != 0 {
                    ring = BoardTrait::or(ring, drawn);
                    edges += Self::pow2(side);
                }
            }
            side += 1;
        }
        (ring, edges, zero)
    }

    /// A side's openings among its `allowed` tiles, 1 or 2 drawn from `draws` (0 when none is
    /// allowed; the draw of the count made either way, as before).
    fn openings(allowed: felt252, side: u8, ref draws: Rng) -> felt252 {
        let two = draws.draw_byte(2) == 1;
        if allowed == 0 {
            return 0;
        }
        let first = Self::opening(allowed, side, ref draws);
        let mut ring = BoardTrait::pow(first);
        if two {
            let second = Self::opening(allowed, side, ref draws);
            ring = BoardTrait::or(ring, BoardTrait::pow(second));
        }
        ring
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
    use super::outline::{Outline, OutlineTrait};
    use super::placement::{CORE, PlacementTrait};
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
            west: 0,
            north: 0,
            masks: array![].span(),
            anchors: array![].span(),
            quotas,
            tasks: array![].span(),
            spawn: spawn(160),
            packs: packs(),
            pieces: array![].span(),
        }
    }

    /// A dungeon floor of `n` chunks entered at chunk 112, tile 112, as `create` makes it from
    /// `entropy` (ENG-10b; `HostsLibrary::floor`'s computation): its outline drawn
    /// (`EntropyTrait::outline`), its quotas' hosts over it (`EntropyTrait::hosts`, the exit and
    /// the Heart first, among its farthest chunks), each chunk of it with its hosts above its mask.
    pub fn dungeon(n: u8, quotas: QuotaSet, entropy: felt252) -> Site {
        let outline = OutlineTrait::draw(112, n, 15, 15, EntropyTrait::outline(entropy, INSTANCE));
        let mut site = Site {
            target: n,
            biome: biome::CAVE,
            level_min: 3,
            level_max: 5,
            width: 15,
            height: 15,
            entry_chunk: 112,
            chunk_set: outline.chunks,
            west: outline.west,
            north: outline.north,
            masks: array![].span(),
            anchors: array![(112, 112)].span(),
            quotas,
            tasks: array![].span(),
            spawn: spawn(160),
            packs: packs(),
            pieces: array![].span(),
        };
        let progress = ProgressTrait::new(@site, entropy);
        let hosts = PlacementTrait::floor_hosts(
            outline.chunks,
            PlacementTrait::plan(@site, progress.left.span()),
            site.pieces,
            EntropyTrait::hosts(entropy, INSTANCE),
            outline.layers(112).span(),
        )
            .span();
        let mut masks: Array<(u8, felt252)> = array![];
        let count = BoardTrait::count(outline.chunks);
        let mut i: u8 = 0;
        while i != count {
            let chunk = BoardTrait::nth(outline.chunks, i);
            masks.append((chunk, PlacementTrait::with_hosts(0, hosts, chunk)));
            i += 1;
        }
        site.masks = masks.span();
        site
    }

    /// A dungeon site's outline.
    pub fn outline_of(site: @Site) -> Outline {
        Outline { chunks: *site.chunk_set, west: *site.west, north: *site.north }
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
    // gas: raised, ENG-10b: each floor built as create makes it, its outline and hosts first
    #[available_gas(l2_gas: 104228639)] // ceil(1.05 × 99265370 measured)
    fn test_edges_against_hexx_sides() {
        let sides = [Side::West, Side::East, Side::South, Side::North];
        let mut seed: felt252 = 0;
        while seed != 12 {
            let site = dungeon(12, no_quotas(), seed);
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
    #[available_gas(l2_gas: 174093178)] // ceil(1.05 × 165803026 measured)
    fn test_invariants_meadow() {
        check_zone_words(biome::MEADOW, 0, 6);
    }

    #[test]
    #[available_gas(l2_gas: 178061873)] // ceil(1.05 × 169582736 measured)
    fn test_invariants_forest() {
        check_zone_words(biome::FOREST, 100, 6);
    }

    #[test]
    #[available_gas(l2_gas: 179421533)] // ceil(1.05 × 170877650 measured)
    fn test_invariants_cave() {
        check_zone_words(biome::CAVE, 200, 6);
    }

    #[test]
    #[available_gas(l2_gas: 182237334)] // ceil(1.05 × 173559365 measured)
    fn test_invariants_ruin() {
        check_zone_words(biome::RUIN, 300, 6);
    }

    // The location's border and a void chunk close a side (D-134); an anchor on it stays open.
    #[test]
    #[available_gas(l2_gas: 58145701)] // ceil(1.05 × 55376858 measured)
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
    #[available_gas(l2_gas: 43915968)] // ceil(1.05 × 41824731 measured)
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

    // ENG-10b: a dungeon floor revealed whole, its chunks by index. Exactly the outline's chunks
    // are revealable, all of them; once `N` are revealed nothing is; the exit lands once, in the
    // farthest layer, on the spine's core; nothing is owed; each chunk's edge toward a chunk of the
    // outline is open exactly when its seam is, every other edge closed; across each open seam the
    // two chunks carry the same opening tiles, each facing the other's (`hexx`'s seams, N-2).
    fn check_dungeon(n: u8, first: felt252, words: felt252) {
        let sides = [Side::West, Side::East, Side::South, Side::North];
        let mut seed = first;
        while seed != first + words {
            let site = dungeon(n, exit_quota(), seed);
            let (far, _) = outline_of(@site).far(112);
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            let mut exits: u8 = 0;
            let mut veins: u8 = 0;
            let mut chunk: u8 = 0;
            while chunk != 225 {
                let inside = BoardTrait::has(site.chunk_set, chunk);
                assert(
                    RevealTrait::revealable(@site, @progress, known.span(), chunk) == inside,
                    'revealable: the outline',
                );
                if inside {
                    let r = one(@site, ref progress, known.span(), chunk);
                    check_chunk(@r);
                    for item in r.features.objects.span() {
                        if *item.kind == object::EXIT {
                            exits += 1;
                            assert(BoardTrait::has(far, chunk), 'the exit at the farthest');
                            assert(BoardTrait::has(CORE, *item.tile), 'the exit on the core');
                        }
                        if *item.kind == object::VEIN {
                            veins += 1;
                        }
                    }
                    known.append((chunk, r.terrain));
                } else {
                    assert(
                        RevealTrait::kind(@site, @progress, known.span(), chunk) == ChunkKind::Void,
                        'void outside the outline',
                    );
                }
                chunk += 1;
            }
            assert(progress.count == n, 'N revealed');
            assert(progress.revealed == site.chunk_set, 'the outline revealed');
            assert(progress.open_edges == 0, 'no open edges');
            assert(exits == 1 && veins == 1, 'quotas placed');
            assert(progress.left == [0; 14], 'nothing owed');
            let mut chunk: u8 = 0;
            while chunk != 225 {
                assert(
                    !RevealTrait::revealable(@site, @progress, known.span(), chunk),
                    'nothing more at N',
                );
                chunk += 1;
            }
            for entry in known.span() {
                let (chunk, terrain) = *entry;
                let mut s: u8 = 0;
                while s != 4 {
                    let open = RevealTrait::is_open(terrain.edges, s);
                    match site.neighbour(chunk, s) {
                        Option::Some(next) => {
                            if BoardTrait::has(site.chunk_set, next) {
                                assert(open == site.seam(chunk, s, next), 'edges: the seams');
                                let other = RevealTrait::known(known.span(), next);
                                let ground = floor(@terrain);
                                assert(
                                    BoardTrait::and(
                                        ground, BoardTrait::side(s),
                                    ) == BoardTrait::copy(s, floor(@other)),
                                    'the same openings',
                                );
                                if open {
                                    assert(
                                        SeamTrait::is_open_across(
                                            15,
                                            15,
                                            ground,
                                            floor(@other),
                                            *sides.span()[s.into()],
                                            odd(chunk),
                                        ),
                                        'open across the seam',
                                    );
                                }
                            } else {
                                assert(!open, 'closed outside the outline');
                            }
                        },
                        Option::None => { assert(!open, 'closed at the border'); },
                    }
                    s += 1;
                }
            }
            seed += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 340149737)] // ceil(1.05 × 323952130 measured)
    fn test_dungeon_revealed_whole_n_6() {
        check_dungeon(6, 0, 4);
    }

    #[test]
    #[available_gas(l2_gas: 276837866)] // ceil(1.05 × 263655110 measured)
    fn test_dungeon_revealed_whole_n_12() {
        check_dungeon(12, 50, 2);
    }

    // ENG-10b: a dungeon's revealable chunks are its outline's, whatever is revealed: a chunk of
    // the outline that no open seam joins to a revealed chunk (beyond a closed seam) is revealable,
    // as a zone's chunk is when sight touches it (D-223, ruling 3); a chunk outside it is void.
    #[test]
    #[available_gas(l2_gas: 228650379)] // ceil(1.05 × 217762265 measured)
    fn test_dungeon_revealable_is_the_outline() {
        let mut seed: felt252 = 0;
        while seed != 8 {
            let site = dungeon(12, no_quotas(), seed);
            let progress = ProgressTrait::new(@site, seed);
            let mut chunk: u8 = 0;
            while chunk != 225 {
                let inside = BoardTrait::has(site.chunk_set, chunk);
                assert(
                    RevealTrait::revealable(@site, @progress, array![].span(), chunk) == inside,
                    'revealable: the outline',
                );
                let kind = RevealTrait::kind(@site, @progress, array![].span(), chunk);
                assert(
                    (kind == ChunkKind::Unrevealed) == inside
                        && (kind == ChunkKind::Void) == !inside,
                    'the kinds',
                );
                chunk += 1;
            }
            seed += 1;
        }
    }

    // D-224 amended (the project manager, 2026-10-07): a floor's seam openings derived, over its
    // whole life. Each reveal in a dungeon computes the outline's seed once (`decide`), and each
    // open seam's openings are drawn once, by the first of its two chunks revealed (the second
    // copies them): `N` seeds and one stream a seam. Storing them instead would draw the same
    // streams at `create`, then write and read a slot: this test, less its baseline (the floor
    // built, nothing derived), is the derivation's whole cost on a floor of 12.
    fn seams_life(site: @Site, entropy: felt252) {
        let count = BoardTrait::count(*site.chunk_set);
        let mut i: u8 = 0;
        while i != count {
            let _seed = EntropyTrait::outline(entropy, INSTANCE);
            i += 1;
        }
        let seams = EntropyTrait::outline(entropy, INSTANCE);
        let mut i: u8 = 0;
        let west = BoardTrait::count(*site.west);
        while i != west {
            let low = BoardTrait::nth(*site.west, i);
            let mut rng = RngTrait::new(poseidon_hash_span([seams, low.into(), 0].span()));
            RevealTrait::openings(BoardTrait::side(side::WEST), side::WEST, ref rng);
            i += 1;
        }
        let mut i: u8 = 0;
        let north = BoardTrait::count(*site.north);
        while i != north {
            let low = BoardTrait::nth(*site.north, i);
            let mut rng = RngTrait::new(poseidon_hash_span([seams, low.into(), 1].span()));
            RevealTrait::openings(BoardTrait::side(side::NORTH), side::NORTH, ref rng);
            i += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 9388375)] // ceil(1.05 × 8941309 measured)
    fn test_cost_seams_derived_n12() {
        let site = dungeon(12, no_quotas(), 'seams');
        seams_life(@site, 'seams');
        println!(
            "seams: {} West and {} North open",
            BoardTrait::count(site.west),
            BoardTrait::count(site.north),
        );
    }

    // The derivation's part that storing would save: the outline's seed, once a chunk revealed.
    #[test]
    #[available_gas(l2_gas: 5880783)] // ceil(1.05 × 5600745 measured)
    fn test_cost_seams_seeds_n12() {
        let site = dungeon(12, no_quotas(), 'seams');
        let count = BoardTrait::count(site.chunk_set);
        let mut i: u8 = 0;
        while i != count {
            let _seed = EntropyTrait::outline('seams', INSTANCE);
            i += 1;
        }
    }

    #[test]
    #[available_gas(l2_gas: 5628650)] // ceil(1.05 × 5360619 measured)
    fn test_cost_seams_baseline_n12() {
        let _site = dungeon(12, no_quotas(), 'seams');
    }

    // The last chunks hold what is owed: a zone's quotas are all placed when every chunk is
    // revealed, whatever the order.
    #[test]
    #[available_gas(l2_gas: 45668733)] // ceil(1.05 × 43494031 measured)
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
    #[available_gas(l2_gas: 199668)] // ceil(1.05 × 190160 measured)
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
    #[available_gas(l2_gas: 7298373)] // ceil(1.05 × 6950831 measured)
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
    #[available_gas(l2_gas: 70798341)] // ceil(1.05 × 67426991 measured)
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
    #[available_gas(l2_gas: 8008222)] // ceil(1.05 × 7626878 measured)
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
    #[available_gas(l2_gas: 13833381)] // ceil(1.05 × 13174648 measured)
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
    // once at `create`. A 3 × 3 zone with quotas of 6 (drawn as its complement, D-220), 2 and 1,
    // revealed forward and backward over 6 entropies: each quota has `count` hosts, and in both
    // orders every chunk holds exactly the quotas it hosts, nothing forced, nothing owed at the
    // end.
    #[test]
    #[available_gas(l2_gas: 285487039)] // ceil(1.05 × 271892418 measured)
    fn test_zone_quota_hosts_order_free() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 6 },
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
            assert(BoardTrait::count(*hosts[0]) == 6, 'six collector hosts');
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

    // CBT-05g (D-240): a reveal in play reads the hosts of the quotas the stored progress still
    // owes, 0 for the others (`HostsLibrary.reveal`). A 3 × 3 zone with quotas of 6, 2 and 1, its
    // first four chunks revealed, then the five others twice from that progress: with every host,
    // and with the hosts of the quotas with nothing left zeroed. The two give the same chunks and
    // the same progress; over 6 entropies, some quota is spent before the second part.
    #[test]
    #[available_gas(l2_gas: 219777297)] // ceil(1.05 × 209311711 measured)
    fn test_spent_quota_hosts_unread() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 6 },
                Quota { kind: quota::LANDMARK, param: 4, count: 2 },
                Quota { kind: quota::VEIN, param: 0, count: 1 }, Default::default(),
                Default::default(), Default::default(),
            ],
        };
        let first = array![0_u8, 1, 2, 15].span();
        let rest = array![16_u8, 17, 30, 31, 32].span();
        let mut spent: u32 = 0;
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut site = zone(biome::MEADOW, 3, 3, quotas);
            let hosts = hosted(ref site, seed);
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            for chunk in first {
                let r = one(@site, ref progress, known.span(), *chunk);
                known.append((*chunk, r.terrain));
            }
            // The hosts as `PlayLibrary` reads them now: those of the quotas still owed
            let mut owed: Array<felt252> = array![];
            let mut i: u32 = 0;
            while i != hosts.len() {
                if *progress.left.span()[i] > 0 {
                    owed.append(*hosts[i]);
                } else {
                    owed.append(0);
                    if *hosts[i] != 0 {
                        spent += 1;
                    }
                }
                i += 1;
            }
            let mut unread = zone(biome::MEADOW, 3, 3, quotas);
            let mut masks: Array<(u8, felt252)> = array![];
            for (chunk, _) in site.masks {
                masks.append((*chunk, PlacementTrait::with_hosts(0, owed.span(), *chunk)));
            }
            unread.masks = masks.span();
            let mut all = progress;
            let mut some = progress;
            let mut known_all = known.clone();
            let mut known_some = known;
            for chunk in rest {
                let a = one(@site, ref all, known_all.span(), *chunk);
                let b = one(@unread, ref some, known_some.span(), *chunk);
                assert(a == b, 'a spent host was read');
                known_all.append((*chunk, a.terrain));
                known_some.append((*chunk, b.terrain));
            }
            assert(all == some, 'the same progress');
            seed += 1;
        }
        assert(spent > 0, 'no quota spent');
    }

    // The re-audit at 46d7d89 (major 1): a host must be able to lay its quota. A 2 × 1 zone with a
    // set piece of three objects (the objects' cap) and a collector, each once: the collector is
    // never drawn onto the set piece's chunk (refused, its successor taken), and lands on the
    // other chunk in both orders, nothing owed.
    #[test]
    #[available_gas(l2_gas: 80948486)] // ceil(1.05 × 77093796 measured)
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
    #[available_gas(l2_gas: 51060423)] // ceil(1.05 × 48628974 measured)
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

    // The re-audit at 1d1e38e (major 1): a Heart on a template whose castes' minimums sum to 0
    // used to draw an empty pack from a stream the order of the draws before it moved, and was
    // dropped. A 2 × 1 zone, a Heart (template 3: one caste, 0 to 2) and a collector of 2, so the
    // Heart shares its host with a collector: revealed in both orders, the Heart is laid each time.
    #[test]
    #[available_gas(l2_gas: 51831086)] // ceil(1.05 × 49362939 measured)
    fn test_heart_on_a_min_zero_template() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 2 },
                Quota { kind: quota::HEART, param: 3, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(),
            ],
        };
        let empty = Pack {
            castes: [
                PackCaste { caste: 1, min: 0, max: 2 }, Default::default(), Default::default(),
                Default::default(), Default::default(),
            ],
            level: 0,
        };
        let mut seed: felt252 = 0;
        while seed != 6 {
            let mut site = zone(biome::MEADOW, 2, 1, quotas);
            site.packs = array![(3, empty)].span();
            let hosts = hosted(ref site, seed);
            assert(BoardTrait::count(*hosts[1]) == 1, 'one Heart host');
            for order in array![array![0_u8, 1].span(), array![1_u8, 0].span()] {
                let mut progress = ProgressTrait::new(@site, seed);
                let mut known: Array<(u8, Terrain)> = array![];
                let mut hearts: u8 = 0;
                for chunk in order {
                    let r = one(@site, ref progress, known.span(), *chunk);
                    for pack in r.features.packs.span() {
                        if *pack.template == 3 && *pack.count != 0 {
                            hearts += 1;
                        }
                    }
                    known.append((*chunk, r.terrain));
                }
                assert(hearts == 1, 'the Heart laid');
                assert(progress.left == [0; 14], 'nothing owed');
            }
            seed += 1;
        }
    }

    // The review t-0078 (minor 1) and the re-audit t-0079 (minor 2): a chunk set with a member
    // outside the rectangle (chunk 5 of a 3 × 1 zone) and a vein of 3, above the 2 members inside:
    // the draw ends with 2 hosts, the rest kept owed, no endless draw.
    #[test]
    #[available_gas(l2_gas: 584723)] // ceil(1.05 × 556879 measured)
    fn test_hosts_above_the_members() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::VEIN, param: 0, count: 3 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::MEADOW, 3, 1, quotas);
        site.chunk_set = BoardTrait::pow(0) + BoardTrait::pow(1) + BoardTrait::pow(5);
        let hosts = hosted(ref site, 'above');
        assert(*hosts[0] == BoardTrait::pow(0) + BoardTrait::pow(1), 'the two members');
    }

    /// A 15 × 15 zone with six collector quotas of `count` and eight landmark tasks.
    fn crowded(count: u8) -> Array<felt252> {
        let full = Quota { kind: quota::COLLECTOR, param: 1, count };
        let quotas = QuotaSet { quotas: [full; 6] };
        let mut site = zone(biome::MEADOW, 15, 15, quotas);
        let mut tasks: Array<TaskEntry> = array![];
        let mut k: u32 = 0;
        while k != 8 {
            tasks.append(TaskEntry { task: k, kind: 2, param: 1 });
            k += 1;
        }
        site.tasks = tasks.span();
        let start = ProgressTrait::new(@site, 'worst');
        PlacementTrait::hosts(
            0, 15, 15, PlacementTrait::plan(@site, start.left.span()), array![].span(), 'worst',
        )
    }

    // The re-audit t-0079 (note 6) and the review t-0078 (note 4): the draw's worst plans on a
    // 15 × 15 zone, far above its capacity (3 objects a chunk). Quotas of 255 (the registry's
    // largest): each of the first three takes every member without drawing, the rest find none
    // allowed. Quotas of 224, one below the members: the first three draw 224 hosts each, the
    // most draws a legal plan asks; the rest take the few members left or find none. Their gas
    // is the draw's worst case (ENG-05's report).
    #[test]
    #[available_gas(l2_gas: 2075561)] // ceil(1.05 × 1976724 measured)
    fn test_hosts_worst_plan() {
        let hosts = crowded(255);
        assert(BoardTrait::count(*hosts[0]) == 225, 'every chunk');
        assert(*hosts[3] == 0, 'no room left');
    }

    #[test]
    #[available_gas(l2_gas: 2761322)] // ceil(1.05 × 2629830 measured)
    fn test_hosts_worst_draws() {
        let hosts = crowded(224);
        assert(BoardTrait::count(*hosts[0]) == 224, 'all but one');
        let mut objects: u32 = 0;
        for mask in hosts.span() {
            objects += BoardTrait::count(*mask).into();
        }
        assert(objects <= 3 * 225, 'within the caps');
    }

    // Every cap at once: three object quotas, two Hearts (packs) and a set piece, each of 224:
    // six passes of 224 draws, the caps of objects, packs and set pieces being apart.
    fn mixed(count: u8) -> Array<felt252> {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count },
                Quota { kind: quota::VEIN, param: 0, count },
                Quota { kind: quota::EXIT, param: 1, count },
                Quota { kind: quota::HEART, param: 1, count },
                Quota { kind: quota::HEART, param: 2, count },
                Quota { kind: quota::SET_PIECE, param: 9, count },
            ],
        };
        let site = zone(biome::MEADOW, 15, 15, quotas);
        let start = ProgressTrait::new(@site, 'worst');
        PlacementTrait::hosts(
            0, 15, 15, PlacementTrait::plan(@site, start.left.span()), array![].span(), 'worst',
        )
    }

    // Under D-220's complement draw the most draws a pass asks is at half the members: six
    // passes of 112 draws, the mixed plan at 112.
    #[test]
    #[available_gas(l2_gas: 103052507)] // ceil(1.05 × 98145244 measured)
    fn test_hosts_worst_half() {
        let hosts = mixed(112);
        assert(BoardTrait::count(*hosts[5]) == 112, 'six passes');
    }

    #[test]
    #[available_gas(l2_gas: 1970295)] // ceil(1.05 × 1876471 measured)
    fn test_hosts_worst_mixed() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::COLLECTOR, param: 1, count: 224 },
                Quota { kind: quota::VEIN, param: 0, count: 224 },
                Quota { kind: quota::EXIT, param: 1, count: 224 },
                Quota { kind: quota::HEART, param: 1, count: 224 },
                Quota { kind: quota::HEART, param: 2, count: 224 },
                Quota { kind: quota::SET_PIECE, param: 9, count: 224 },
            ],
        };
        let site = zone(biome::MEADOW, 15, 15, quotas);
        let start = ProgressTrait::new(@site, 'worst');
        let hosts = PlacementTrait::hosts(
            0, 15, 15, PlacementTrait::plan(@site, start.left.span()), array![].span(), 'worst',
        );
        assert(BoardTrait::count(*hosts[5]) == 224, 'six passes');
    }

    // D-220: `subset` gives every `count`-subset equally. Exhaustive over a set of 5 members:
    // for each count 1 to 4 (1 and 2 drawn as the subset, 3 and 4 as the members to leave out),
    // every index sequence the draw can read, each subset reached the same number of times.
    #[test]
    #[available_gas(l2_gas: 7611037)] // ceil(1.05 × 7248606 measured)
    fn test_subset_uniform() {
        let allowed = BoardTrait::pow(0)
            + BoardTrait::pow(1)
            + BoardTrait::pow(2)
            + BoardTrait::pow(15)
            + BoardTrait::pow(16);
        // (count, its subsets C(5, count), the sequences: the product of 5, 4, … over the draws)
        for case in array![(1_u8, 5_u32, 5_u32), (2, 10, 20), (3, 10, 20), (4, 5, 5)].span() {
            let (count, subsets, sequences) = *case;
            let draws: u8 = if count * 2 > 5 {
                5 - count
            } else {
                count
            };
            let mut tally: Felt252Dict<u32> = Default::default();
            let mut seen: Array<felt252> = array![];
            let mut code: u32 = 0;
            while code != sequences {
                let mut rest = code;
                let mut indices: Array<u8> = array![];
                let mut k: u8 = 0;
                while k != draws {
                    let size: u32 = (5 - k).into();
                    indices.append((rest % size).try_into().unwrap());
                    rest /= size;
                    k += 1;
                }
                let mask = PlacementTrait::subset(allowed, 5, count, indices.span());
                assert(BoardTrait::count(mask) == count, 'a count-subset');
                assert(BoardTrait::minus(mask, allowed) == 0, 'of the members');
                let times = tally.get(mask);
                if times == 0 {
                    seen.append(mask);
                }
                tally.insert(mask, times + 1);
                code += 1;
            }
            assert(seen.len() == subsets, 'every subset');
            for mask in seen.span() {
                assert(tally.get(*mask) == sequences / subsets, 'equally');
            }
        }
    }

    // D-208: a Heart's pack takes the band's top level wherever it lands (band 3 to 5). ENG-10b:
    // its host drawn first, among the outline's farthest chunks, and laid first in its chunk, so
    // that chunk's first pack is the Heart (template 2, which the spawn table names too).
    #[test]
    // gas: raised, ENG-10b: the floor revealed whole, the Heart hosted at the farthest
    #[available_gas(l2_gas: 121846959)] // ceil(1.05 × 116044722 measured)
    fn test_heart_at_the_band_top() {
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::HEART, param: 2, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut seed: felt252 = 0;
        while seed != 4 {
            let site = dungeon(6, quotas, seed);
            let (far, _) = outline_of(@site).far(112);
            // The Heart's host: the chunk whose mask carries quota 0 (bit 225)
            let mut host: u8 = 255;
            for entry in site.masks {
                let (chunk, mask) = *entry;
                let wide: u256 = mask.into();
                if BoardTrait::has_wide(wide, 225) {
                    host = chunk;
                }
            }
            assert(BoardTrait::has(far, host), 'hosted at the farthest');
            let mut progress = ProgressTrait::new(@site, seed);
            let mut known: Array<(u8, Terrain)> = array![];
            let mut chunk: u8 = 0;
            while chunk != 225 {
                if RevealTrait::revealable(@site, @progress, known.span(), chunk) {
                    let r = one(@site, ref progress, known.span(), chunk);
                    if chunk == host {
                        let heart = *r.features.packs.span()[0];
                        assert(heart.template == 2 && heart.count != 0, 'the Heart first');
                        assert(heart.level == 5, 'the band top');
                    }
                    known.append((chunk, r.terrain));
                }
                chunk += 1;
            }
            assert(progress.left == [0; 14], 'the Heart placed');
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
    #[available_gas(l2_gas: 138279157)] // ceil(1.05 × 131694435 measured)
    fn test_biome_shares_meadow_forest() {
        let meadow = share(biome::MEADOW, 24);
        println!("meadow {}", meadow);
        assert(meadow >= 800 && meadow <= 900, 'meadow');
        let forest = share(biome::FOREST, 24);
        println!("forest {}", forest);
        assert(forest >= 600 && forest <= 700, 'forest');
    }

    #[test]
    #[available_gas(l2_gas: 140905480)] // ceil(1.05 × 134195695 measured)
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

    // ---- ENG-05c: the reach of the anchor's fix -------------------------------------------------

    /// A chunk's walls as `generate` computes them (no set piece), its interior anchors joined by
    /// their line (`fixed`, ENG-05c) and by ENG-05's `pow(tile) + anchor_line(tile)`, which
    /// carries (`carried`): `(fixed, carried)`.
    fn walls_both(
        site: @Site, progress: @Progress, known: Span<(u8, Terrain)>, chunk: u8,
    ) -> (felt252, felt252) {
        let word = EntropyTrait::word(*progress.entropy, INSTANCE, chunk);
        let odd = odd(chunk);
        let mask = BoardTrait::and(site.mask(chunk), BOARD);
        let mut draws = RngTrait::new(RngTrait::mix(word, 4));
        let (ring, _, _) = RevealTrait::decide(
            site, progress, INSTANCE, known, chunk, mask, ref draws,
        );
        let mut ring = ring;
        let mut fixed: felt252 = 0;
        let mut carried: felt252 = 0;
        let mut anchors: Array<u8> = array![];
        for entry in *site.anchors {
            let (at, tile) = *entry;
            if at == chunk && tile < 225 {
                if BoardTrait::has(INTERIOR, tile) {
                    fixed = BoardTrait::or(fixed, BoardTrait::anchor_line(tile));
                    carried =
                        BoardTrait::or(
                            carried, BoardTrait::pow(tile) + BoardTrait::anchor_line(tile),
                        );
                    anchors.append(tile);
                } else if BoardTrait::has(BOARD - INTERIOR, tile) && !RevealTrait::corner(tile) {
                    ring = BoardTrait::or(ring, BoardTrait::pow(tile));
                }
            }
        }
        let grid = BoardTrait::base(word, *site.biome) + ring;
        let interior = BoardTrait::and(BoardTrait::smooth(grid, odd), INTERIOR);
        let joined = BoardTrait::or(interior, BoardTrait::lines(ring));
        let grid = BoardTrait::or(joined, fixed);
        let walls = finish(grid, ring, mask, anchors.span(), odd);
        let old = BoardTrait::or(joined, carried);
        if old == grid {
            (walls, walls)
        } else {
            (walls, finish(old, ring, mask, anchors.span(), odd))
        }
    }

    /// `generate`'s step 4 on a joined grid: the cut, the component of the root; the walls.
    fn finish(
        grid: felt252, ring: felt252, mask: felt252, anchors: Span<u8>, odd: bool,
    ) -> felt252 {
        let cut = BoardTrait::cut(grid + ring, mask);
        let ring = BoardTrait::minus(cut, INTERIOR);
        let mut interior = BoardTrait::and(cut, INTERIOR);
        if let Option::Some(root) = RevealTrait::root(interior, anchors) {
            interior = BoardTrait::component(interior, root, odd);
        }
        BOARD - interior - ring
    }

    /// The site of one measured generation: a 3 × 2 zone (the seed's location 2) or a dungeon
    /// floor of `n` (the seed's locations 3 and 4), of biome `kind`, its entry anchor at
    /// `(chunk, tile)`.
    fn measured(kind: u8, n: u8, chunk: u8, tile: u8, seed: felt252) -> Site {
        let mut site = if n == 0 {
            zone(kind, 3, 2, no_quotas())
        } else {
            dungeon(n, no_quotas(), seed)
        };
        site.biome = kind;
        site.entry_chunk = chunk;
        site.anchors = array![(chunk, tile)].span();
        site
    }

    /// ENG-05c's measure of the fix's reach: `count` generations from entropy `first`, each its
    /// entry chunk, the first a generation reveals (nothing known) and the only one with an anchor,
    /// so the only one the fix can change: `inner` is 0 in a chunk without one. The anchor at
    /// `(chunk, tile)`, or at an interior tile drawn from the entropy when `tile` is 0. Returns
    /// how many chunks' walls the fix changes. Each chunk's walls with the fix are `generate`'s
    /// (`test_walls_both_is_generate`); in a dungeon its interior is one component that holds the
    /// centre and the anchor: the floor stays connected from entry to exit (its other chunks
    /// unchanged, `check_dungeon`).
    fn reach(kind: u8, n: u8, chunk: u8, tile: u8, first: felt252, count: u32) -> u32 {
        let mut changed: u32 = 0;
        let mut seed = first;
        while seed != first + count.into() {
            let anchor = if tile == 0 {
                let wide: u256 = poseidon_hash_span([seed, 'anchor'].span()).into();
                let (_, k) = DivRem::div_rem(wide.low, 169);
                BoardTrait::nth(INTERIOR, k.try_into().unwrap())
            } else {
                tile
            };
            let site = measured(kind, n, chunk, anchor, seed);
            let progress = ProgressTrait::new(@site, seed);
            let (fixed, carried) = walls_both(@site, @progress, array![].span(), chunk);
            if fixed != carried {
                changed += 1;
            }
            if n != 0 {
                let interior = BoardTrait::minus(INTERIOR, fixed);
                assert(BoardTrait::has(interior, anchor), 'the anchor is floor');
                assert(
                    BoardTrait::component(interior, CENTRE, odd(chunk)) == interior,
                    'one component',
                );
            }
            seed += 1;
        }
        changed
    }

    // `walls_both`'s fixed walls are `generate`'s, in zones and floors, with anchors on the ring,
    // on the spine and off it.
    #[test]
    #[available_gas(l2_gas: 30495933)] // ceil(1.05 × 29043745 measured)
    fn test_walls_both_is_generate() {
        let configs: [(u8, u8, u8, u8); 6] = [
            (biome::MEADOW, 0, 16, 110), (biome::FOREST, 0, 0, 105), (biome::RUIN, 0, 16, 48),
            (biome::CAVE, 0, 1, 186), (biome::CAVE, 6, 112, 112), (biome::RUIN, 8, 112, 48),
        ];
        let mut seed: felt252 = 0;
        for config in configs.span() {
            let (kind, n, chunk, tile) = *config;
            let site = measured(kind, n, chunk, tile, seed);
            let mut progress = ProgressTrait::new(@site, seed);
            let (fixed, _) = walls_both(@site, @progress, array![].span(), chunk);
            let r = one(@site, ref progress, array![].span(), chunk);
            assert(r.terrain.walls == fixed, 'generate');
            seed += 1;
        }
    }

    // The measure (ENG-05c), each biome's zones and floors a test, run on demand past snforge's
    // default step limit (`snforge test reveal::tests::test_reach --include-ignored --max-n-steps
    // 2000000000`; output in `contracts/tools/anchor-reach-output.txt`): the seed's anchors, a zone
    // entered at (16, 110) (gate 4) and at (0, 105) (gate 1), a floor of 6 at (112, 112) (gates 3
    // and 5), 250 generations each, 250 floors of 8; and 250 zones entered at a tile of the
    // interior drawn at random (no gate has one yet).
    fn measure_zones(kind: u8) {
        let zone_110 = reach(kind, 0, 16, 110, 0, 250);
        let zone_105 = reach(kind, 0, 0, 105, 1000, 250);
        let any = reach(kind, 0, 16, 0, 4000, 250);
        println!(
            "reach biome {}: zone (16, 110) {}/250, zone (0, 105) {}/250, zone at a random interior tile {}/250",
            kind,
            zone_110,
            zone_105,
            any,
        );
    }

    // The floors, apart from the zones: 1,250 generations in one test exceed the VM's memory.
    fn measure_floors(kind: u8) {
        let floor_6 = reach(kind, 6, 112, 112, 2000, 250);
        let floor_8 = reach(kind, 8, 112, 112, 3000, 250);
        println!(
            "reach biome {}: floor 6 (112, 112) {}/250, floor 8 (112, 112) {}/250",
            kind,
            floor_6,
            floor_8,
        );
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 1037050979)] // ceil(1.05 × 987667599 measured)
    fn test_reach_meadow_zones() {
        measure_zones(biome::MEADOW);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 2541333578)] // ceil(1.05 × 2420317693 measured)
    fn test_reach_meadow_floors() {
        measure_floors(biome::MEADOW);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 1066416521)] // ceil(1.05 × 1015634781 measured)
    fn test_reach_forest_zones() {
        measure_zones(biome::FOREST);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 2552140451)] // ceil(1.05 × 2430609953 measured)
    fn test_reach_forest_floors() {
        measure_floors(biome::FOREST);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 1077574459)] // ceil(1.05 × 1026261389 measured)
    fn test_reach_cave_zones() {
        measure_zones(biome::CAVE);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 2555512333)] // ceil(1.05 × 2433821269 measured)
    fn test_reach_cave_floors() {
        measure_floors(biome::CAVE);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 1081886402)] // ceil(1.05 × 1030368001 measured)
    fn test_reach_ruin_zones() {
        measure_zones(biome::RUIN);
    }

    #[test]
    #[ignore]
    #[available_gas(l2_gas: 2554478978)] // ceil(1.05 × 2432837121 measured)
    fn test_reach_ruin_floors() {
        measure_floors(biome::RUIN);
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
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 152336967)] // ceil(1.05 × 145082825 measured)
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
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 257502067)] // ceil(1.05 × 245240063 measured)
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

    /// Part 2: a dungeon floor of `N` 6, its outline drawn at `create` (ENG-10b), revealed whole
    /// by index; a zone's quotas on their hosts (D-208), a set piece, a task's landmark.
    #[test]
    #[available_gas(l2_gas: 311827906)] // ceil(1.05 × 296978958 measured)
    fn test_vectors_2() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_2;
        let site = dungeon(6, exit_quota(), 'dungeon');
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
        assert(progress.count == 6, 'the outline revealed');
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
        // ENG-05c: its host above a chunk's mask (D-208), so that the piece is laid
        let _hosts = hosted(ref site, 'piece');
        let mut progress = ProgressTrait::new(@site, 'piece');
        emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![(0), (1)].span(),
        );
        assert(progress.left == [0; 14], 'the piece laid');
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_2, 'vectors moved: regenerate');
    }

    /// Part 3 (ENG-05c): the cases of track CV's surviving mutants (CLI-02b's report), in zones:
    /// sight and a member at a chunk's side; a chunk asked twice; an anchor on a corner; an
    /// interior anchor off the spine (tile 48), whole and in a chunk whose mask cuts its centre; a
    /// set piece on an odd chunk row; pack templates of minimums 0 and maximums above 5; a Heart
    /// of offset 0 below the band's top with both spawn rolls passing; a spawn roll equal to the
    /// density.
    #[test]
    #[available_gas(l2_gas: 149967213)] // ceil(1.05 × 142825917 measured)
    fn test_vectors_3() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_3;
        for position in array![(12_u8, 9_u8), (0, 9)].span() {
            let (x, y) = *position;
            let touched = SightTrait::chunks(x, y, 15, 15);
            let mut ok: Array<felt252> = array![];
            for chunk in touched.span() {
                ok.append((*chunk).into());
            }
            emit(ref digest, ref id, "sight", [x.into(), y.into(), 15, 15].span(), ok.span());
        }
        let mut ok: Array<felt252> = array![];
        PackPlacementTrait::member(13, 11, false).serialize(ref ok);
        emit(ref digest, ref id, "member", [13, 11, 0].span(), ok.span());
        // A chunk asked twice in one call: revealed once.
        let site = zone(biome::MEADOW, 3, 3, no_quotas());
        let mut progress = ProgressTrait::new(@site, 'twice');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![16, 16].span(),
        );
        assert(out.len() == 1, 'revealed once');
        // An anchor on a corner (tile 14): wall (D-134).
        let mut site = zone(biome::MEADOW, 2, 2, no_quotas());
        site.anchors = array![(0, 14)].span();
        let mut progress = ProgressTrait::new(@site, 'corner');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![0].span(),
        );
        assert(BoardTrait::has(*out[0].terrain.walls, 14), 'the corner walled');
        // An interior anchor off row 7 and column 7 (tile 48: row 3, column 3), joined to the spine
        // by its line, the tiles within 2 of it kept clear of a spawn of density 255.
        let mut site = zone(biome::CAVE, 3, 3, no_quotas());
        site.anchors = array![(16, 48)].span();
        site.spawn = spawn(255);
        let mut progress = ProgressTrait::new(@site, 'anchor');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![16].span(),
        );
        let line = BoardTrait::anchor_line(48);
        assert(BoardTrait::and(floor(out[0].terrain), line) == line, 'the anchor joined');
        // The same anchor in a chunk whose mask keeps columns 0 to 5: its centre cut, the flood
        // from the anchor, a pocket of floor outside its component dropped (the entropy chosen for
        // it); its West side cut whole, its South and North sides kept in part.
        let mut mask: felt252 = 0;
        let mut row: u8 = 0;
        while row != 15 {
            mask += Bits::pow(row * 15) * 0x3f;
            row += 1;
        }
        let mut site = zone(biome::RUIN, 3, 3, no_quotas());
        site.masks = array![(16, mask)].span();
        site.anchors = array![(16, 48)].span();
        let mut progress = ProgressTrait::new(@site, 'cut centre11');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![16].span(),
        );
        assert(!BoardTrait::has(floor(out[0].terrain), CENTRE), 'the centre cut');
        assert(BoardTrait::has(floor(out[0].terrain), 48), 'the anchor kept');
        // A set piece on an odd chunk row (chunk 15, its host drawn there), its floor two tiles
        // that the global row parity joins or not: (8, 4), next to the spine, and (9, 3), its
        // neighbour on the odd layout only, so (9, 3) is not kept.
        let walls = BOARD - Bits::pow(8 * 15 + 4) - Bits::pow(9 * 15 + 3);
        let piece = SetPiece {
            walls,
            packs: [Default::default(), Default::default()],
            objects: [Default::default(), Default::default(), Default::default()],
        };
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::SET_PIECE, param: 5, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::RUIN, 1, 2, quotas);
        site.pieces = array![(5, piece)].span();
        let hosts = array![Bits::pow(15)].span();
        site
            .masks =
                array![
                    (0, PlacementTrait::with_hosts(0, hosts, 0)),
                    (15, PlacementTrait::with_hosts(0, hosts, 15)),
                ]
            .span();
        let mut progress = ProgressTrait::new(@site, 'odd piece');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![15].span(),
        );
        assert(BoardTrait::has(floor(out[0].terrain), 8 * 15 + 4), 'the piece laid');
        assert(!BoardTrait::has(floor(out[0].terrain), 9 * 15 + 3), 'the global parity');
        // Pack templates whose minimums are all 0 (3) and whose maximums sum to 6 (4), every
        // spawn roll passing.
        let mut site = zone(biome::MEADOW, 2, 1, no_quotas());
        site
            .packs =
                array![
                    (
                        3,
                        Pack {
                            castes: [
                                PackCaste { caste: 1, min: 0, max: 2 },
                                PackCaste { caste: 2, min: 0, max: 1 }, Default::default(),
                                Default::default(), Default::default(),
                            ],
                            level: 0,
                        },
                    ),
                    (
                        4,
                        Pack {
                            castes: [
                                PackCaste { caste: 1, min: 1, max: 3 },
                                PackCaste { caste: 2, min: 0, max: 3 }, Default::default(),
                                Default::default(), Default::default(),
                            ],
                            level: 0,
                        },
                    ),
                ]
            .span();
        site
            .spawn =
                SpawnTable {
                    spawns: [
                        Spawn { template: 3, weight: 1 }, Spawn { template: 4, weight: 1 },
                        Default::default(), Default::default(), Default::default(),
                        Default::default(), Default::default(),
                    ],
                    density: 255,
                };
        let mut progress = ProgressTrait::new(@site, 'templates');
        emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![0, 1].span());
        // A Heart on a template of offset 0 (template 1), hosted below the band's farthest chunk,
        // with both spawn rolls passing: its pack at the band's top, a third pack refused (E-3).
        let quotas = QuotaSet {
            quotas: [
                Quota { kind: quota::HEART, param: 1, count: 1 }, Default::default(),
                Default::default(), Default::default(), Default::default(), Default::default(),
            ],
        };
        let mut site = zone(biome::MEADOW, 3, 3, quotas);
        site.spawn = spawn(255);
        let hosts = hosted(ref site, 'heart1');
        let host = BoardTrait::nth(*hosts[0], 0);
        assert(PlacementTrait::level(@site, host) < 5, 'the Heart below the top');
        let mut progress = ProgressTrait::new(@site, 'heart1');
        let out = emit_reveal(
            ref digest, ref id, @site, ref progress, array![].span(), array![host].span(),
        );
        let heart = *out[0].features.packs.span()[0];
        assert(heart.template == 1 && heart.level == 5, 'the Heart at the top');
        // A spawn roll equal to the density: the density set to the first roll of chunk 0's
        // placement stream (`mix(word, 3)`, its first draw with no quota), so that it places
        // nothing there.
        let mut site = zone(biome::MEADOW, 1, 1, no_quotas());
        let word = EntropyTrait::word('roll', INSTANCE, 0);
        let roll: u8 = RngTrait::new(RngTrait::mix(word, 3)).draw(256).try_into().unwrap();
        site.spawn = spawn(roll);
        let mut progress = ProgressTrait::new(@site, 'roll');
        emit_reveal(ref digest, ref id, @site, ref progress, array![].span(), array![0].span());
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_3, 'vectors moved: regenerate');
    }

    /// Part 4 (ENG-05c): a cave dungeon floor of `N` 6 whose outline holds two neighbouring
    /// chunks with their seam closed, revealed whole by decreasing index, so that each chunk is
    /// revealed before its South and East neighbours (its seams drawn from their own streams,
    /// D-224), and the band runs over `N − 1`.
    #[test]
    #[available_gas(l2_gas: 175153413)] // ceil(1.05 × 166812774 measured)
    fn test_vectors_4() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = PART_4;
        let site = dungeon(6, exit_quota(), FLOOR_SEED);
        assert(closed_seam(@site), 'a closed seam');
        let mut progress = ProgressTrait::new(@site, FLOOR_SEED);
        let mut known: Array<(u8, Terrain)> = array![];
        let mut chunk: u8 = 225;
        while chunk != 0 {
            chunk -= 1;
            if RevealTrait::revealable(@site, @progress, known.span(), chunk) {
                let out = emit_reveal(
                    ref digest, ref id, @site, ref progress, known.span(), array![chunk].span(),
                );
                known.append((chunk, *out[0].terrain));
            }
        }
        assert(progress.count == 6, 'the outline revealed');
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST_4, 'vectors moved: regenerate');
    }

    /// Whether a dungeon's outline holds two neighbouring chunks with their seam closed.
    fn closed_seam(site: @Site) -> bool {
        let set = *site.chunk_set;
        let mut found = false;
        let mut chunk: u8 = 0;
        while chunk != 225 {
            if BoardTrait::has(set, chunk) {
                if let Option::Some(next) = site.neighbour(chunk, side::WEST) {
                    found = found
                        || (BoardTrait::has(set, next) && !site.seam(chunk, side::WEST, next));
                }
                if let Option::Some(next) = site.neighbour(chunk, side::NORTH) {
                    found = found
                        || (BoardTrait::has(set, next) && !site.seam(chunk, side::NORTH, next));
                }
            }
            chunk += 1;
        }
        found
    }

    const PART_1: u32 = 171;
    const PART_2: u32 = 186;
    const PART_3: u32 = 197;
    const PART_4: u32 = 208;
    const FLOOR_SEED: felt252 = 15;
    const DIGEST_3: felt252 =
        373751706693600581171786682490285631373917093504969551187281382165112423875;
    const DIGEST_4: felt252 =
        3544417685008436817138242476357257570762962652172485010072620730429193143830;
    const DIGEST_0: felt252 =
        1099007504077458561703646988744304604964174275844371738808055141155867483297;
    // ENG-05b: `Progress`' hand-written Serde keeps the derived encoding, `left` one felt a value
    // with no length, and refuses a value above a byte.
    #[test]
    #[available_gas(l2_gas: 118314)] // ceil(1.05 × 112680 measured)
    fn test_progress_serde() {
        let progress = Progress {
            revealed: 0x10001,
            count: 2,
            open_edges: 0,
            left: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 255],
            entropy: 'entropy',
        };
        let mut out: Array<felt252> = array![];
        progress.serialize(ref out);
        let expected = array![
            0x10001, 2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 255, 'entropy',
        ];
        assert(out == expected, 'encoding');
        let mut words = out.span();
        assert(Serde::<Progress>::deserialize(ref words) == Option::Some(progress), 'decoded');
        assert(words.len() == 0, 'consumed');
        let mut wrong = array![0x10001, 2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 256, 'e']
            .span();
        assert(Serde::<Progress>::deserialize(ref wrong).is_none(), 'byte');
        let mut short = array![0x10001, 2, 0, 1, 2].span();
        assert(Serde::<Progress>::deserialize(ref short).is_none(), 'short');
    }

    const DIGEST_1: felt252 =
        3406219353955151080332403134172067514426351653970253477291706690989101018180;
    const DIGEST_2: felt252 =
        170139148758665691845217810894711728109179173361979681415172906251723928882;
}
