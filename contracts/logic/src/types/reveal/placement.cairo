//! The constraints and the placement of a reveal (ADR-0006 §3, design/18 *Features*): the quotas
//! drawn order-free, forced at the end, the band of a chunk, then the packs and the objects in the
//! `Features` word.
//!
//! - **Quotas** (`due`). In a zone (D-208, the project manager, 2026-10-03), each quota's host
//!   chunks are drawn once at `create` (`hosts`): `count` chunks of the zone, a uniform draw
//!   without replacement from the instance's entropy, one bitmap per quota; a chunk holds the
//!   quota when it is one of its hosts. Order-free: no move chooses where a zone's quota lands. In
//!   a dungeon, whose chunks are not known before they are revealed, each quota with a count draws
//!   `u = draw(N)` from the chunk's own word and is due when `u < count` and something is left.
//!   Both are **forced** when what is left reaches the chunks left (`left ≥ chunks left`), so the
//!   last chunks hold what is still owed (in a zone only after a placement found no room), and
//!   never placed with nothing left, so the count stays exact. At most one of each quota a chunk.
//!   "Chunks left" counts this chunk: `N − revealed` in a dungeon, the chunk set's count less the
//!   revealed in a zone. **A dungeon's quotas stay order-dependent** (D-208, accepted as the
//!   dungeon's nature): its outline emerges from the order of the moves, so the forced window (at
//!   most the last `count` chunks), a quota whose draws hit more chunks than its count (the first
//!   revealed take it) and the `N`-th chunk follow that order; an exit's position with them. A
//!   Heart's pack takes the band's top level wherever it lands, so that no order lowers the boss.
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

use core::poseidon::poseidon_hash_span;
use hexx::board::bits::Bits;
use hexx::board::rng::{Rng, RngTrait};
use crate::content::CRITERION_REACH_LANDMARK;
use crate::models::chunk::{CENTRE, NEAR, Object, PackPlacement, PackPlacementTrait, object};
use crate::models::location::biome;
use crate::models::pack::PackTrait;
use crate::models::quotas::kind as quota;
use crate::models::set_piece::SetPiece;
use crate::models::spawn_table::SpawnTableTrait;
use crate::types::{MAX_OBJECTS_PER_CHUNK, MAX_PACKS_PER_CHUNK};
use super::board::{BOARD, BoardTrait};
use super::{Progress, Site, SiteTrait};

/// Quotas of an instance: the location's 6, then 8 for the snapshotted tasks (ENG-01 §3.2).
pub const QUOTAS: u8 = 14;
/// The location's quotas come first.
pub const LOCATION_QUOTAS: u8 = 6;
/// Draws of a tile by rejection before the exact draw (`PlacementTrait::tile`).
pub const TRIES: u8 = 16;

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
        let revealed = *progress.count;
        let chunks: u8 = if total > revealed {
            total - revealed
        } else {
            1
        };
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
        let emerging = site.emerging();
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
                let u = rng.draw(bound);
                let hit = if emerging {
                    u < count.into()
                } else {
                    BoardTrait::has(mask, host)
                };
                if left != 0 && (hit || left >= chunks) {
                    due += bit;
                }
            }
            bit *= 2;
            host += 1;
        }
        due
    }

    /// A zone's quota hosts (D-208, module doc): for each quota's `count` (`start`'s, which a new
    /// `Progress` holds as `left`), `count` chunks of the zone (its chunk set, or its whole
    /// rectangle) drawn without replacement from `seed` (`EntropyTrait::hosts`) as a bitmap: try
    /// `t` reads `poseidon(seed, t)` as a row and a column of the rectangle, kept if the chunk is
    /// in the zone and not drawn yet, up to `16 + 4 count` tries (uniform over the zone; a quota
    /// above the zone's size keeps fewer hosts, and the forced rule places what stays owed).
    /// Computed once at `create`, by `Instances`.
    fn hosts(site: @Site, counts: Span<u8>, seed: felt252) -> Array<felt252> {
        let set = *site.chunk_set;
        let width: u128 = (*site.width).into();
        let height: u128 = (*site.height).into();
        let width: NonZero<u128> = width.try_into().unwrap();
        let height: NonZero<u128> = height.try_into().unwrap();
        let mut t: felt252 = 0;
        let mut out: Array<felt252> = array![];
        for count in counts {
            let mut mask: felt252 = 0;
            let mut k: u8 = 0;
            let mut tries: u16 = 16 + 4 * (*count).into();
            while k != *count && tries != 0 {
                let word: u256 = poseidon_hash_span([seed, t].span()).into();
                let (rest, cy) = DivRem::div_rem(word.low, height);
                let (_, cx) = DivRem::div_rem(rest, width);
                let cy: u8 = cy.try_into().unwrap();
                let cx: u8 = cx.try_into().unwrap();
                let chunk = 15 * cy + cx;
                if (set == 0 || BoardTrait::has(set, chunk)) && !BoardTrait::has(mask, chunk) {
                    // `2^chunk` as `2^cx · 2^(15 cy)`: short loops, no power table (D-200)
                    let mut bit: felt252 = 1;
                    for _ in 0..cx {
                        bit *= 2;
                    }
                    for _ in 0..cy {
                        bit *= 0x8000;
                    }
                    mask += bit;
                    k += 1;
                }
                t += 1;
                tries -= 1;
            }
            out.append(mask);
        }
        out
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
    /// room: its count drawn in the template's bounds, its goblins on allowed tiles within 2.
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
        let size = low + rng.draw_byte((high - low + 1).try_into().unwrap());
        if size == 0 {
            return false;
        }
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
        // [Compute] The quotas due, in order
        let mut i: u8 = 0;
        let mut rest = due;
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
