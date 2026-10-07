//! **SPK-17 (ENG-10a): a copy of `grimworld_logic::types::reveal::placement` at 44961f2 (its
//! tests left out), changed where a dungeon's outline is fixed at entry, each change marked
//! `ENG-10a`:** `due` takes a dungeon's quotas from its hosts as a zone's (no forced window);
//! `hosts` takes `layers`, the outline's chunks by distance from the entry, farthest first: a
//! dungeon's exit and Heart are drawn first of all the quotas, in the farthest layer with an
//! allowed chunk (review t-0088, major 1);
//! `place` lays a dungeon's exit and Heart first, on the spine's core (`CORE`). The original
//! documentation follows, as it was; where it speaks of a dungeon's forced quotas, the marked
//! changes replace it.
//!
//! The constraints and the placement of a reveal (ADR-0006 §3, design/18 *Features*): the quotas
//! (a zone's on hosts drawn at entry, a dungeon's hit or forced), the band of a chunk, then the
//! packs and the objects in the `Features` word.
//!
//! - **Quotas** (`due`). **In a zone** (D-208, D-210, D-220, the project manager): each quota's
//!   host chunks are drawn once at `create` by `HostsLibrary` (`hosts`): its `count` members of
//!   the zone among those it would not push past a chunk's caps (3 objects, 2 packs, one set
//!   piece, a set piece's own objects and packs counted), an exact draw without replacement from
//!   the instance's entropy, no cap on the draws (a quota stops when no allowed member is left;
//!   above half of them, the members to leave out are drawn, `subset`); one bitmap per quota,
//!   carried above each chunk's mask (bit `225 + i`). A chunk holds the quota exactly when it
//!   hosts it, and nothing is ever forced on "the last chunks": no order of moves chooses where a
//!   zone's quota lands. A quota with fewer allowed members than its count keeps fewer hosts, the
//!   rest owed for good, never placed; a set-piece quota whose piece is not in the registry stays
//!   owed; a host whose chunk has no allowed tile left (the terrain, which no draw at entry
//!   knows) does not lay it. A pack, the Heart's included, holds at least one goblin. **In a
//!   dungeon**, whose chunks are not known before they are revealed, each quota with a count draws
//!   `u = draw(N)` from the chunk's own word and is due when `u < count` and something is left,
//!   and is **forced** when
//!   what is left reaches the chunks left (`left ≥ chunks left`, "chunks left" counting this one:
//!   `N − revealed`), so the last chunks hold what is still owed; never placed with nothing left.
//!   At most one of each quota a chunk. **A dungeon's quotas stay order-dependent** (D-208,
//!   accepted as the dungeon's nature): its outline emerges from the order of the moves, so the
//!   forced window (at most the last `count` chunks), a quota whose draws hit more chunks than its
//!   count (the first revealed take it) and the `N`-th chunk follow that order; an exit's position
//!   with them. A Heart's pack takes the band's top level wherever it lands, so that no order
//!   lowers the boss.
//! - **Bands** (`level`): `level_min + (level_max − level_min) × min(d, D) / D`, `d` the chunk's
//!   distance in chunks to the entry chunk (`|dcx| + |dcy|`), `D` the farthest a chunk can be (a
//!   zone: `width + height − 2`; a dungeon: `N − 1`); a pack adds its template's offset, held
//!   in the band.
//! - **Placement** (`place`), on the tiles allowed: the chunk's reachable interior floor, not
//! within
//!   2 of an opening or an anchor, not taken. In order: a set piece's own packs and objects; the
//!   quotas due, in their order (an object, or a pack for a Heart); the spawn table's two pack
//!   slots (each with probability `density / 256`, the template by weight); then a chest (1 chunk
//!   in 6), a gathering node (zones, 1 in 4), a terrain trap (ruins and caves, 1 in 3). Never more
//!   than 2 packs of 5 goblins and 3 objects (E-3): what finds no room, or no tile, is not placed,
//!   and a quota keeps it owed. A pack's goblin 0 stands on the pack's tile, the others on allowed
//!   tiles within 2 of it, drawn without replacement (`PackPlacement.offsets`); asleep or on watch.
//!   Every draw of a roll is made whether it can be placed or not, so that one roll never moves
//!   another.

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::poseidon::poseidon_hash_span;
use grimworld_logic::content::CRITERION_REACH_LANDMARK;
use grimworld_logic::models::chunk::{
    CENTRE, NEAR, Object, PackPlacement, PackPlacementTrait, object,
};
use grimworld_logic::models::location::biome;
use grimworld_logic::models::pack::PackTrait;
use grimworld_logic::models::quotas::kind as quota;
use grimworld_logic::models::set_piece::SetPiece;
use grimworld_logic::models::spawn_table::SpawnTableTrait;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};
use grimworld_logic::types::{MAX_OBJECTS_PER_CHUNK, MAX_PACKS_PER_CHUNK};
use hexx::board::bits::Bits;
use hexx::board::rng::{Rng, RngTrait};
use super::{Progress, Site, SiteTrait};

/// Quotas of an instance: the location's 6, then 8 for the snapshotted tasks (ENG-01 §3.2).
pub const QUOTAS: u8 = 14;
/// The location's quotas come first.
pub const LOCATION_QUOTAS: u8 = 6;
/// Draws of a tile by rejection before the exact draw (`PlacementTrait::tile`).
pub const TRIES: u8 = 16;
/// ENG-10a: the spine's core, rows and columns 3 to 11 of row 7 and column 7 (17 tiles): floor in
/// every generated chunk (`BoardTrait::lines` lays the spine, the centre's component holds it) and
/// at least 3 from the ring, so never within 2 of an opening; a dungeon's exit and Heart are laid
/// on it (`place`).
pub const CORE: felt252 = 0x100020004000801ff002000400080010000000000000;

/// What a reveal places in a chunk, built in order.
#[derive(Drop)]
pub struct Placement {
    pub packs: Array<PackPlacement>,
    pub objects: Array<Object>,
    /// The tiles still allowed.
    pub allowed: felt252,
    /// Bit `i`: quota `i` placed here.
    pub placed: u16,
    /// Whether the chunk's local row 0 is a global odd row.
    pub odd: bool,
    pub level: u8,
}

#[generate_trait]
pub impl PlacementImpl of PlacementTrait {
    /// What quota slot `i` places: `(kind, param)`, 0 for nothing. The location's 6 from `QUOTAS`;
    /// then task `i − 6` of the snapshot: a landmark to reach places that landmark (ENG-05 Open
    /// question 7; a caste to kill names no pack template, so it places nothing yet).
    fn slot(site: @Site, i: u8) -> (u8, u16) {
        if i < LOCATION_QUOTAS {
            let entry = *site.quotas.quotas.span()[i.into()];
            return (entry.kind, entry.param);
        }
        let k: u32 = (i - LOCATION_QUOTAS).into();
        if k >= (*site.tasks).len() {
            return (0, 0);
        }
        let task = *(*site.tasks)[k];
        if task.kind == CRITERION_REACH_LANDMARK {
            (quota::LANDMARK, task.param)
        } else {
            (0, 0)
        }
    }

    /// What each quota starts with: the location's counts, then one for each task that places
    /// something (`slot`).
    fn start(site: @Site) -> [u8; 14] {
        let mut left: Array<u8> = array![];
        for entry in site.quotas.quotas.span() {
            left.append(if *entry.kind == 0 {
                0
            } else {
                *entry.count
            });
        }
        let mut i = LOCATION_QUOTAS;
        while i != QUOTAS {
            let (kind, _) = Self::slot(site, i);
            left.append(if kind == 0 {
                0
            } else {
                1
            });
            i += 1;
        }
        Self::fixed(left.span())
    }

    /// Bit `i` set: quota `i` is due in this chunk (module doc), with `progress.count` chunks
    /// revealed before it; `mask`, the chunk's mask word, in a zone the quotas it hosts above the
    /// board (bit `225 + i`, D-208). A draw for every quota with a count, so that no draw moves
    /// another.
    fn due(site: @Site, progress: @Progress, mask: felt252, ref rng: Rng) -> u16 {
        let total = site.total();
        let bound: u128 = if total == 0 {
            1
        } else {
            total.into()
        };
        let bound: NonZero<u128> = bound.try_into().unwrap();
        // Each quota's count as `start` gives it: the location's, then the tasks' (one drawing
        // loop, D-200)
        let mut counts: Array<u8> = array![];
        for entry in site.quotas.quotas.span() {
            counts.append(if *entry.kind == 0 {
                0
            } else {
                *entry.count
            });
        }
        for task in *site.tasks {
            counts.append(if *task.kind == CRITERION_REACH_LANDMARK {
                1
            } else {
                0
            });
        }
        let mut lefts = progress.left.span();
        let mut due: u16 = 0;
        let mut bit: u16 = 1;
        let mut host: u8 = 225;
        for count in counts {
            let left = match lefts.pop_front() {
                Option::Some(left) => *left,
                Option::None => { break; },
            };
            if count != 0 {
                // ENG-05's draw kept, unread, so that a zone's streams do not move
                let _u = rng.draw(bound);
                // A quota on its hosts alone (D-208; ENG-10a: a dungeon's too, drawn at
                // `create` over its outline): never forced on the last chunks
                if left != 0 && BoardTrait::has(mask, host) {
                    due += bit;
                }
            }
            bit *= 2;
            host += 1;
        }
        due
    }

    /// The quotas' plan for `hosts` (D-210): quota `i` of `counts` (`start`'s, which a new
    /// `Progress` holds as `left`) as its count, kind and param in 32 bits, quotas 0–6 in the
    /// first felt and 7–13 in the second; the location's quotas from `QUOTAS`, a task's a
    /// landmark (`slot`). `(0, 0)` when nothing is owed. The library call's input.
    fn plan(site: @Site, counts: Span<u8>) -> (felt252, felt252) {
        let mut low: felt252 = 0;
        let mut high: felt252 = 0;
        let mut shift: felt252 = 1;
        let mut quotas = site.quotas.quotas.span();
        let mut i: u8 = 0;
        for count in counts {
            if i == 7 {
                shift = 1;
            }
            let (kind, param): (u8, u16) = match quotas.pop_front() {
                Option::Some(entry) => (*entry.kind, *entry.param),
                Option::None => (quota::LANDMARK, 0),
            };
            let entry = shift * ((*count).into() + 0x100 * kind.into() + 0x10000 * param.into());
            if *count == 0 {} else if i < 7 {
                low += entry;
            } else {
                high += entry;
            }
            shift *= 0x100000000;
            i += 1;
        }
        (low, high)
    }

    /// A zone's quota hosts (D-208, D-210, module doc), drawn once at `create` by `HostsLibrary`:
    /// for each quota of the plan (`plan`), in order, its `count` chunks of the zone (`zone`, its
    /// chunk set within the `width × height` rectangle, or 0 for the whole rectangle), an exact
    /// draw without replacement from `seed` (`EntropyTrait::hosts`) over the quota's **allowed**
    /// members: the members not yet at a cap the quota would pass (3 objects, 2 packs, one set
    /// piece; what the quotas before it lay there, a set piece's own objects and packs from
    /// `pieces`, counted in bitmaps of the chunks at each level). Draw `t` takes the `j`-th
    /// allowed member left, `j` read from `poseidon(seed, t)` modulo how many are left, through
    /// `subset` (D-220: above half the allowed members, the members to leave out are drawn
    /// instead; a count at or above them takes them all, without drawing); no cap on the draws. A
    /// quota stops when it has its hosts or no allowed member is left:
    /// a determination of the caps, not a cap of the draws. Every host can lay its quota, whatever
    /// the order of the reveals; a quota with fewer allowed members than its count keeps fewer
    /// hosts, and the rest stays owed for good, never placed (nothing falls on "the last chunks").
    fn hosts(
        zone: felt252,
        width: u8,
        height: u8,
        plan: (felt252, felt252),
        pieces: Span<(u16, SetPiece)>,
        seed: felt252,
        layers: Span<felt252>,
    ) -> Array<felt252> {
        // [Compute] The zone: its rectangle's rows, and its chunk set within them
        let row = BoardTrait::pow(width) - 1;
        let mut rectangle: felt252 = 0;
        let mut cy: u8 = 0;
        while cy != height {
            rectangle += row * BoardTrait::pow(15 * cy);
            cy += 1;
        }
        let zone = if zone == 0 {
            rectangle
        } else {
            BoardTrait::and(zone, rectangle)
        };
        // The chunks at each level: 1, 2, 3 objects; 1, 2 packs; a set piece
        let mut objects: [felt252; 3] = [0, 0, 0];
        let mut packs: [felt252; 2] = [0, 0];
        let mut piece: felt252 = 0;
        let (first, second) = plan;
        let mut rest: u256 = first.into();
        let mut next: u256 = second.into();
        // [Compute] The plan's entries, by quota (a shorter list: the quotas after hold nothing)
        let mut entries: Array<u256> = array![];
        let mut i: u8 = 0;
        while rest != 0 || next != 0 {
            if i == 7 {
                rest = next;
                next = 0;
            }
            i += 1;
            let (above, entry) = DivRem::div_rem(rest, 0x100000000);
            rest = above;
            entries.append(entry);
        }
        // ENG-10a (review t-0088, major 1; the orchestrator): in a dungeon (`layers` not empty) the
        // exit's and the Heart's hosts are drawn first, before every other quota, so that no cap
        // blocks them; a zone's quotas keep their order and their draws
        let dungeon = layers.len() != 0;
        let mut masks: Felt252Dict<felt252> = Default::default();
        let mut t: felt252 = 0;
        for pass in 0..2_u8 {
            let mut i: felt252 = 0;
            for entry in entries.span() {
                let entry = *entry;
                let (above, count) = DivRem::div_rem(entry, 0x100);
                let (param, kind) = DivRem::div_rem(above, 0x100);
                let kind: u8 = kind.try_into().unwrap();
                let early = dungeon && (kind == quota::EXIT || kind == quota::HEART);
                if entry != 0 && (pass == 0) == early {
                    let count: u8 = count.try_into().unwrap();
                    let need = Self::need(kind, param.try_into().unwrap(), pieces);
                    let (rest_need, n_objects) = DivRem::div_rem(need, 4);
                    let (n_pieces, n_packs) = DivRem::div_rem(rest_need, 4);
                    // [Compute] The allowed members: not at a level the quota would pass
                    let [o1, o2, o3] = objects;
                    let [p1, p2] = packs;
                    let mut blocked: felt252 = 0;
                    if n_objects == 1 {
                        blocked = o3;
                    } else if n_objects == 2 {
                        blocked = o2;
                    } else if n_objects >= 3 {
                        blocked = o1;
                    }
                    if n_packs == 1 {
                        blocked = BoardTrait::or(blocked, p2);
                    } else if n_packs >= 2 {
                        blocked = BoardTrait::or(blocked, p1);
                    }
                    if n_pieces != 0 {
                        blocked = BoardTrait::or(blocked, piece);
                    }
                    // ENG-10a: a dungeon's exit and Heart in the outline's farthest layer that has
                    // an allowed chunk (`layers`, farthest first, the entry's last): never owed
                    let allowed = if early {
                        let mut found: felt252 = 0;
                        for layer in layers {
                            if found == 0 {
                                found = BoardTrait::minus(BoardTrait::and(zone, *layer), blocked);
                            }
                        }
                        found
                    } else {
                        BoardTrait::minus(zone, blocked)
                    };
                    let left: u8 = BoardTrait::count(allowed);
                    // [Compute] The indices the draw takes: as many as the subset or its
                    // complement holds
                    let wide: u16 = count.into() * 2;
                    let draws: u8 = if count >= left {
                        0
                    } else if wide > left.into() {
                        left - count
                    } else {
                        count
                    };
                    let mut indices: Array<u8> = array![];
                    let mut k: u8 = 0;
                    while k != draws {
                        let word: u256 = poseidon_hash_span([seed, t].span()).into();
                        t += 1;
                        let bound: u128 = (left - k).into();
                        let (_, j) = DivRem::div_rem(word.low, bound.try_into().unwrap());
                        indices.append(j.try_into().unwrap());
                        k += 1;
                    }
                    let mask = Self::subset(allowed, left, count, indices.span());
                    // [Compute] The levels after this quota's hosts
                    let [mut o1, mut o2, mut o3] = objects;
                    for _ in 0..n_objects {
                        let at_two = BoardTrait::and(mask, o2);
                        let at_one = BoardTrait::and(mask, o1);
                        o3 = BoardTrait::or(o3, at_two);
                        o2 = BoardTrait::or(o2, at_one);
                        o1 = BoardTrait::or(o1, mask);
                    }
                    objects = [o1, o2, o3];
                    let [mut p1, mut p2] = packs;
                    for _ in 0..n_packs {
                        p2 = BoardTrait::or(p2, BoardTrait::and(mask, p1));
                        p1 = BoardTrait::or(p1, mask);
                    }
                    packs = [p1, p2];
                    if n_pieces != 0 {
                        piece = BoardTrait::or(piece, mask);
                    }
                    masks.insert(i, mask);
                }
                i += 1;
            }
        }
        let mut out: Array<felt252> = array![];
        let mut i: felt252 = 0;
        for _ in entries.span() {
            out.append(masks.get(i));
            i += 1;
        }
        out
    }

    /// The `count` members of `allowed` (`left` of them) a draw takes (`hosts`, D-220): all of them
    /// when `count ≥ left`, the draw's only outcome; else, from `indices` (index `k` below
    /// `left − k`), the members drawn one by one, each the `j`-th left: the subset itself when
    /// `count ≤ left / 2`, else the members to leave out (`left − count` draws, the
    /// complement), so that a pass draws at most half the members. Either way a uniform
    /// `count`-subset.
    fn subset(allowed: felt252, left: u8, count: u8, indices: Span<u8>) -> felt252 {
        if count >= left {
            return allowed;
        }
        let mut pool = allowed;
        let mut drawn: felt252 = 0;
        for j in indices {
            let bit = BoardTrait::pow(BoardTrait::nth(pool, *j));
            pool -= bit;
            drawn += bit;
        }
        let wide: u16 = count.into() * 2;
        if wide > left.into() {
            allowed - drawn
        } else {
            drawn
        }
    }

    /// What a quota of `kind` and `param` lays in its chunk, as `hosts` counts it: objects + 4 ×
    /// packs + 16 × set pieces; a set piece with its own objects and packs (laid first, `place`).
    fn need(kind: u8, param: u16, pieces: Span<(u16, SetPiece)>) -> u8 {
        if kind == quota::HEART {
            4
        } else if kind == quota::SET_PIECE {
            let mut need: u8 = 16;
            for entry in pieces {
                let (at, set) = *entry;
                if at == param {
                    for pack in set.packs.span() {
                        if *pack.template != 0 {
                            need += 4;
                        }
                    }
                    for object in set.objects.span() {
                        if *object.kind != 0 {
                            need += 1;
                        }
                    }
                }
            }
            need
        } else if kind == 0 {
            0
        } else {
            1
        }
    }

    /// `mask`, a zone chunk's tile mask (0 for the whole board), with the quotas `chunk` hosts
    /// above the board (bit `225 + i` for quota `i`, D-208): what `Site.masks` carries for it.
    fn with_hosts(mask: felt252, hosts: Span<felt252>, chunk: u8) -> felt252 {
        let mut word = if mask == 0 {
            BOARD
        } else {
            BoardTrait::and(mask, BOARD)
        };
        let mut bit: felt252 = 0x200000000000000000000000000000000000000000000000000000000;
        for host in hosts {
            if *host != 0 && BoardTrait::has(*host, chunk) {
                word += bit;
            }
            bit *= 2;
        }
        word
    }

    /// `left` less one for each quota placed (`placed`).
    fn spend(left: [u8; 14], placed: u16) -> [u8; 14] {
        let mut out: Array<u8> = array![];
        let mut rest = placed;
        for value in left.span() {
            let (above, bit) = DivRem::div_rem(rest, 2);
            out.append(*value - bit.try_into().unwrap());
            rest = above;
        }
        Self::fixed(out.span())
    }

    fn fixed(values: Span<u8>) -> [u8; 14] {
        [
            *values[0], *values[1], *values[2], *values[3], *values[4], *values[5], *values[6],
            *values[7], *values[8], *values[9], *values[10], *values[11], *values[12], *values[13],
        ]
    }

    /// The band's level of a chunk (module doc).
    fn level(site: @Site, chunk: u8) -> u8 {
        let (cy, cx) = DivRem::div_rem(chunk, 15);
        let (ey, ex) = DivRem::div_rem(*site.entry_chunk, 15);
        let dx = if cx > ex {
            cx - ex
        } else {
            ex - cx
        };
        let dy = if cy > ey {
            cy - ey
        } else {
            ey - cy
        };
        let distance: u16 = dx.into() + dy.into();
        let far: u16 = if *site.target != 0 {
            (*site.target).into() - 1
        } else {
            (*site.width).into() + (*site.height).into() - 2
        };
        let low = *site.level_min;
        let high = *site.level_max;
        if far == 0 || high <= low {
            return low;
        }
        let distance = if distance > far {
            far
        } else {
            distance
        };
        let span: u16 = (high - low).into();
        low + (span * distance / far).try_into().unwrap()
    }

    /// A pack's level: the band's plus its template's offset, held in the location's band.
    fn pack_level(site: @Site, level: u8, offset: i8) -> u8 {
        let sum: i16 = level.into() + offset.into();
        let low: i16 = (*site.level_min).into();
        let high: i16 = (*site.level_max).into();
        let held = if sum < low {
            low
        } else if sum > high {
            high
        } else {
            sum
        };
        held.try_into().unwrap()
    }

    /// One tile drawn among those allowed, then taken: a tile of the chunk drawn uniformly and
    /// kept if allowed, up to `TRIES` draws; then, if none was, the `n`-th allowed tile, `n` drawn
    /// (the exact draw, dearer: `count` and `nth`). Uniform over the allowed tiles either way.
    fn tile(ref self: Placement, ref rng: Rng) -> Option<u8> {
        if self.allowed == 0 {
            return Option::None;
        }
        let allowed: u256 = self.allowed.into();
        let mut found: Option<u8> = Option::None;
        let mut tries: u8 = 0;
        while found.is_none() && tries != TRIES {
            let tile = rng.draw_byte(225);
            if BoardTrait::has_wide(allowed, tile) {
                found = Option::Some(tile);
            }
            tries += 1;
        }
        let tile = match found {
            Option::Some(tile) => tile,
            Option::None => {
                let count = BoardTrait::count(self.allowed);
                BoardTrait::nth(self.allowed, rng.draw_byte(count.try_into().unwrap()))
            },
        };
        self.allowed -= BoardTrait::pow(tile);
        Option::Some(tile)
    }

    /// Takes `tile` if it is allowed.
    fn take(ref self: Placement, tile: u8) -> bool {
        if tile >= 225 || !BoardTrait::has_wide(self.allowed.into(), tile) {
            return false;
        }
        self.allowed -= BoardTrait::pow(tile);
        true
    }

    /// An object on a drawn tile, if there is room.
    fn object(ref self: Placement, ref rng: Rng, kind: u8, param: u16) -> bool {
        if self.objects.len() >= MAX_OBJECTS_PER_CHUNK.into() {
            return false;
        }
        match self.tile(ref rng) {
            Option::Some(tile) => {
                self.objects.append(Object { tile, kind, state: 0, param });
                true
            },
            Option::None => false,
        }
    }

    /// A pack of `template` (from the site's templates), on `at` or on a drawn tile, if there is
    /// room: its count drawn in the template's bounds, at least one, its goblins on allowed tiles
    /// within 2.
    fn pack(ref self: Placement, ref rng: Rng, site: @Site, template: u16, at: Option<u8>) -> bool {
        if self.packs.len() >= MAX_PACKS_PER_CHUNK.into() {
            return false;
        }
        let Option::Some(pack) = site.pack(template) else {
            return false;
        };
        let (low, high) = pack.bounds();
        if high == 0 {
            return false;
        }
        // At least one goblin (#348's re-audit at 1d1e38e, major 1): a pack drawn empty would leave
        // a Heart to the order of the draws before it; no pack is laid empty
        let low = if low == 0 {
            1
        } else {
            low
        };
        let size = low + rng.draw_byte((high - low + 1).try_into().unwrap());
        let tile = match at {
            Option::Some(tile) => {
                if !self.take(tile) {
                    return false;
                }
                tile
            },
            Option::None => {
                match self.tile(ref rng) {
                    Option::Some(tile) => tile,
                    Option::None => { return false; },
                }
            },
        };
        // [Compute] Goblin 0 on the pack's tile, the others among the allowed tiles within 2
        let (row, _) = DivRem::div_rem(tile, 15);
        let (_, parity) = DivRem::div_rem(row, 2);
        let odd = (parity == 1) != self.odd;
        // The allowed tiles within 2, each tested once: `(offset, tile)`.
        let allowed: u256 = self.allowed.into();
        let mut candidates: Array<(u8, u8)> = array![];
        let mut k: u8 = 0;
        while k != NEAR {
            if k != CENTRE {
                if let Option::Some(member) = PackPlacementTrait::member(tile, k, odd) {
                    if BoardTrait::has_wide(allowed, member) {
                        candidates.append((k, member));
                    }
                }
            }
            k += 1;
        }
        // Drawn without replacement: `chosen` marks the candidates taken, by their index.
        let mut offsets: u32 = CENTRE.into();
        let mut count: u8 = 1;
        let mut shift: u32 = 32;
        let mut chosen: u32 = 0;
        let total = candidates.len();
        let mut taken: u32 = 0;
        while count != size && taken != total {
            let left: u8 = (total - taken).try_into().unwrap();
            let mut pick = rng.draw_byte(left.try_into().unwrap());
            let mut i: u32 = 0;
            let mut bit: u32 = 1;
            let mut found: u32 = 0;
            let mut done = false;
            while !done {
                if (chosen / bit) % 2 == 0 {
                    if pick == 0 {
                        found = i;
                        done = true;
                    } else {
                        pick -= 1;
                    }
                }
                if !done {
                    i += 1;
                    bit *= 2;
                }
            }
            chosen += bit;
            let (index, member) = *candidates[found];
            self.allowed -= BoardTrait::pow(member);
            offsets += index.into() * shift;
            shift *= 32;
            count += 1;
            taken += 1;
        }
        let alert = rng.draw_byte(2);
        let level = Self::pack_level(site, self.level, pack.level);
        self.packs.append(PackPlacement { tile, template, level, count, offsets, alert });
        true
    }

    /// Places everything of a chunk (module doc). `due`: the quotas drawn for it; `piece`: the set
    /// piece laid by quota `piece_slot`, if any. Returns the packs, the objects and the quotas
    /// placed.
    fn place(
        site: @Site,
        chunk: u8,
        due: u16,
        piece: Option<(u8, SetPiece)>,
        allowed: felt252,
        odd: bool,
        ref rng: Rng,
    ) -> Placement {
        let mut placement = Placement {
            packs: array![],
            objects: array![],
            allowed,
            placed: 0,
            odd,
            level: Self::level(site, chunk),
        };
        // [Compute] ENG-10a: a dungeon's exit and Heart first, each on a tile of the spine's core
        // (`CORE`), which no opening and no anchor of a chunk that is not the entry's comes within
        // 2 of, whatever the seams, less the set piece's own tiles: both always land, on a tile
        // that no order of the reveals moves (the Heart's goblins beyond goblin 0 among the
        // allowed tiles, as before)
        let mut first: u16 = 0;
        if site.emerging() {
            let mut reserved: felt252 = 0;
            if let Option::Some((_, set)) = piece {
                for entry in set.packs.span() {
                    if *entry.template != 0 {
                        reserved = BoardTrait::or(reserved, BoardTrait::pow(*entry.tile));
                    }
                }
                for entry in set.objects.span() {
                    if *entry.kind != 0 {
                        reserved = BoardTrait::or(reserved, BoardTrait::pow(*entry.tile));
                    }
                }
            }
            let mut core = BoardTrait::minus(CORE, reserved);
            let mut i: u8 = 0;
            let mut rest = due;
            while i != QUOTAS {
                let (above, bit) = DivRem::div_rem(rest, 2);
                rest = above;
                if bit == 1 {
                    let (kind, param) = Self::slot(site, i);
                    if kind == quota::EXIT || kind == quota::HEART {
                        // The tile drawn among the core's, then taken from what is allowed
                        let allowed = placement.allowed;
                        placement.allowed = core;
                        let drawn = placement.tile(ref rng);
                        core = placement.allowed;
                        placement.allowed = BoardTrait::minus(allowed, reserved);
                        let done = match drawn {
                            Option::None => false,
                            Option::Some(tile) => {
                                if kind == quota::EXIT {
                                    if placement.take(tile) {
                                        placement
                                            .objects
                                            .append(
                                                Object {
                                                    tile, kind: object::EXIT, state: 0, param,
                                                },
                                            );
                                        true
                                    } else {
                                        false
                                    }
                                } else {
                                    let band = placement.level;
                                    placement.level = *site.level_max;
                                    let done = placement
                                        .pack(ref rng, site, param, Option::Some(tile));
                                    placement.level = band;
                                    done
                                }
                            },
                        };
                        placement
                            .allowed =
                                BoardTrait::or(
                                    placement.allowed, BoardTrait::and(allowed, reserved),
                                );
                        if done {
                            placement.placed += Self::bit(i);
                        }
                        first += Self::bit(i);
                    }
                }
                i += 1;
            }
        }
        // [Compute] The set piece's own packs and objects
        if let Option::Some((slot, set)) = piece {
            placement.placed += Self::bit(slot);
            for entry in set.packs.span() {
                if *entry.template != 0 {
                    placement.pack(ref rng, site, *entry.template, Option::Some(*entry.tile));
                }
            }
            for entry in set.objects.span() {
                if *entry.kind != 0
                    && placement.objects.len() < MAX_OBJECTS_PER_CHUNK.into()
                    && placement.take(*entry.tile) {
                    placement.objects.append(Object { state: 0, ..*entry });
                }
            }
        }
        // [Compute] The quotas due, in order (ENG-10a: but those laid first)
        let mut i: u8 = 0;
        let mut rest = due - first;
        while i != QUOTAS {
            let (above, bit) = DivRem::div_rem(rest, 2);
            rest = above;
            if bit == 1 {
                let (kind, param) = Self::slot(site, i);
                let done = if kind == quota::EXIT {
                    placement.object(ref rng, object::EXIT, param)
                } else if kind == quota::VEIN {
                    placement.object(ref rng, object::VEIN, 0)
                } else if kind == quota::COLLECTOR {
                    placement.object(ref rng, object::COLLECTOR, param)
                } else if kind == quota::LANDMARK {
                    placement.object(ref rng, object::LANDMARK, param)
                } else if kind == quota::HEART {
                    // The band's top wherever the Heart lands (D-208): no order lowers the boss
                    let band = placement.level;
                    placement.level = *site.level_max;
                    let done = placement.pack(ref rng, site, param, Option::None);
                    placement.level = band;
                    done
                } else {
                    // A set piece is laid before the terrain (`RevealTrait`), or stays owed.
                    false
                };
                if done {
                    placement.placed += Self::bit(i);
                }
            }
            i += 1;
        }
        // [Compute] The spawn table's two slots
        let spawn = site.spawn;
        let weight = spawn.weight();
        for _ in 0..MAX_PACKS_PER_CHUNK {
            let roll = rng.draw(256);
            let pick: u16 = if weight == 0 {
                0
            } else {
                let bound: u128 = weight.into();
                rng.draw(bound.try_into().unwrap()).try_into().unwrap()
            };
            if weight != 0 && roll < (*spawn.density).into() {
                placement.pack(ref rng, site, spawn.pick(pick), Option::None);
            }
        }
        // [Compute] The objects by frequency
        let chest = rng.draw6() == 0;
        let node = rng.draw_byte(4) == 0;
        let trap = rng.draw_byte(3) == 0;
        if chest {
            let level = placement.level;
            placement.object(ref rng, object::CHEST, level.into());
        }
        if node && *site.target == 0 {
            placement.object(ref rng, object::NODE, 0);
        }
        if trap && (*site.biome == biome::RUIN || *site.biome == biome::CAVE) {
            placement.object(ref rng, object::TRAP, 0);
        }
        placement
    }

    #[inline(always)]
    fn bit(i: u8) -> u16 {
        let mut bit: u16 = 1;
        let mut k = i;
        while k != 0 {
            bit *= 2;
            k -= 1;
        }
        bit
    }
}
