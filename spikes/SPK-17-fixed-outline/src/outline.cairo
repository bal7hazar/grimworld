//! A dungeon floor's outline, drawn once at `create` (ENG-10a; ADR-0006 *Outlines*, as ENG-10a
//! amends it): which chunks the floor holds and which seams between them are open, from the
//! instance's entry draw alone, so that no order of moves changes it.
//!
//! **The draw** (`draw`), from `seed` (`seed`: `derive(entropy, domain(instance, 227, REVEAL), 0)`,
//! the word of no chunk; 225 is the hosts', 226 an authored zone's hosts', SPK-16): the floor starts
//! as its entry chunk and grows one chunk at a time until it holds `N` (or the whole rectangle,
//! when smaller): the chunk added is drawn uniformly among the **frontier**, the chunks of the
//! rectangle next to the floor and not in it (a random growth from the entry, an Eden growth). The
//! chunk's seams toward the floor: one of them, drawn uniformly, its **parent**, is open, so the
//! floor is connected; each other is open but with probability 1 in 7 (`BORDER`, ENG-05's law of a
//! dungeon's side). Draw `t` reads `poseidon(seed, t).low` modulo its bound (a bias at most
//! 225 / 2^128), `t` growing across the whole draw, so no word is read twice.
//!
//! **Stored** as three felts (`Outline`): the chunks (bit `15 cy + cx`), the open seams West (bit
//! `c`: between `c` and `c + 1`) and North (bit `c`: between `c` and `c + 15`).
//!
//! **Distances** (`far`, `distance`): a breadth-first walk from the entry through the open seams,
//! bit-parallel (a layer is a bitmap); the floor is connected, so every chunk is reached within
//! `N − 1` layers. `far` is the last layer: the chunks farthest from the entry on foot, where the
//! exit and the Heart are drawn (`engine::placement::PlacementTrait::hosts`).

use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::EntropyTrait;
use grimworld_logic::types::reveal::board::{BOARD, BoardTrait};

/// The counter of the outline's seed: the word of no chunk (0–224), nor of ENG-05's hosts (225),
/// nor of an authored zone's (226, SPK-16).
pub const COUNTER: u8 = 227;
/// A seam that is not a parent is a border with probability 1 in `BORDER` (ENG-05's `BORDER`).
pub const BORDER: u128 = 7;
/// Every chunk but those of column 0, of column 14, of row 0.
const NOT_COLUMN_0: felt252 = 0x1fffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffe;
const NOT_COLUMN_14: felt252 = 0xfffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff;
const NOT_ROW_0: felt252 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffff8000;

/// A dungeon floor's outline (module doc), the three felts `create` stores.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Outline {
    pub chunks: felt252,
    pub west: felt252,
    pub north: felt252,
}

#[generate_trait]
pub impl OutlineImpl of OutlineTrait {
    /// The outline's seed (module doc).
    #[inline]
    fn seed(entropy: felt252, instance_id: felt252) -> felt252 {
        EntropyTrait::word(entropy, instance_id, COUNTER)
    }

    /// The `width × height` rectangle's chunks.
    fn rectangle(width: u8, height: u8) -> felt252 {
        let row = BoardTrait::pow(width) - 1;
        let mut rectangle: felt252 = 0;
        let mut cy: u8 = 0;
        while cy != height {
            rectangle += row * BoardTrait::pow(15 * cy);
            cy += 1;
        }
        rectangle
    }

    /// The outline of a floor of `n` chunks entered at `entry`, in a `width × height` rectangle,
    /// drawn from `seed` (module doc).
    fn draw(entry: u8, n: u8, width: u8, height: u8, seed: felt252) -> Outline {
        let rectangle = Self::rectangle(width, height);
        let area = BoardTrait::count(rectangle);
        let target = if n < area {
            n
        } else {
            area
        };
        let mut chunks = BoardTrait::pow(entry);
        let mut west: felt252 = 0;
        let mut north: felt252 = 0;
        let mut t: felt252 = 0;
        let mut count: u8 = 1;
        while count < target {
            // [Compute] The chunk added: uniform over the frontier
            let frontier = BoardTrait::minus(
                BoardTrait::and(Self::around(chunks), rectangle), chunks,
            );
            let j = Self::draw_below(seed, ref t, BoardTrait::count(frontier));
            let chunk = BoardTrait::nth(frontier, j);
            // [Compute] Its seams toward the floor: the parent's open, the others but a border in 7
            let (cy, cx) = DivRem::div_rem(chunk, 15);
            let mut sides: Array<(u8, u8)> = array![];
            if cx + 1 < width && BoardTrait::has(chunks, chunk + 1) {
                sides.append((0, chunk));
            }
            if cx != 0 && BoardTrait::has(chunks, chunk - 1) {
                sides.append((0, chunk - 1));
            }
            if cy != 0 && BoardTrait::has(chunks, chunk - 15) {
                sides.append((1, chunk - 15));
            }
            if cy + 1 < height && BoardTrait::has(chunks, chunk + 15) {
                sides.append((1, chunk));
            }
            let parent = Self::draw_below(seed, ref t, sides.len().try_into().unwrap());
            let mut k: u8 = 0;
            for entry in sides {
                let (axis, at) = entry;
                let open = k == parent || Self::draw_below(seed, ref t, 7) != 0;
                if open {
                    if axis == 0 {
                        west += BoardTrait::pow(at);
                    } else {
                        north += BoardTrait::pow(at);
                    }
                }
                k += 1;
            }
            chunks += BoardTrait::pow(chunk);
            count += 1;
        }
        Outline { chunks, west, north }
    }

    /// Draw `t` of `seed` below `bound` (not 0), `t` then advanced.
    fn draw_below(seed: felt252, ref t: felt252, bound: u8) -> u8 {
        let word: u256 = poseidon_hash_span([seed, t].span()).into();
        t += 1;
        let bound: u128 = bound.into();
        let (_, j) = DivRem::div_rem(word.low, bound.try_into().unwrap());
        j.try_into().unwrap()
    }

    /// The chunks next to `set` (West, East, South, North), within the 15 × 15 board.
    fn around(set: felt252) -> felt252 {
        let west = BoardTrait::and(set, NOT_COLUMN_14) * 2;
        let wide: u256 = BoardTrait::and(set, NOT_COLUMN_0).into();
        let east: felt252 = (wide / 2).try_into().unwrap();
        let north = BoardTrait::and(set * 0x8000, BOARD);
        let wide: u256 = BoardTrait::and(set, NOT_ROW_0).into();
        let south: felt252 = (wide / 0x8000).try_into().unwrap();
        BoardTrait::or(BoardTrait::or(west, east), BoardTrait::or(north, south))
    }

    /// The chunks one open seam away from `layer`.
    fn step(self: @Outline, layer: felt252) -> felt252 {
        // West: `c + 1` when the seam `c` is open; East: `c − 1` when the seam `c − 1` is
        let west = BoardTrait::and(layer, *self.west) * 2;
        let wide: u256 = BoardTrait::and(layer, NOT_COLUMN_0).into();
        let east = BoardTrait::and((wide / 2).try_into().unwrap(), *self.west);
        let north = BoardTrait::and(layer, *self.north) * 0x8000;
        let wide: u256 = BoardTrait::and(layer, NOT_ROW_0).into();
        let south = BoardTrait::and((wide / 0x8000).try_into().unwrap(), *self.north);
        BoardTrait::and(
            BoardTrait::or(BoardTrait::or(west, east), BoardTrait::or(north, south)), *self.chunks,
        )
    }

    /// The chunks farthest from `entry` through the open seams, and their distance.
    fn far(self: @Outline, entry: u8) -> (felt252, u8) {
        let mut layer = BoardTrait::pow(entry);
        let mut seen = layer;
        let mut depth: u8 = 0;
        loop {
            let next = BoardTrait::minus(self.step(layer), seen);
            if next == 0 {
                break;
            }
            seen = BoardTrait::or(seen, next);
            layer = next;
            depth += 1;
        }
        (layer, depth)
    }

    /// The distance from `entry` to `chunk` through the open seams; 255 when not reached.
    fn distance(self: @Outline, entry: u8, chunk: u8) -> u8 {
        let mut layer = BoardTrait::pow(entry);
        let mut seen = layer;
        let mut depth: u8 = 0;
        let mut found: u8 = 255;
        while found == 255 && layer != 0 {
            if BoardTrait::has(layer, chunk) {
                found = depth;
            } else {
                layer = BoardTrait::minus(self.step(layer), seen);
                seen = BoardTrait::or(seen, layer);
                depth += 1;
            }
        }
        found
    }

    /// The outline whose seams are the open edges of revealed chunks (`Terrain.edges`: West, East,
    /// South, North): what a client reads back from the chain after the reveals.
    fn from_edges(chunks: Span<(u8, u8)>) -> Outline {
        let mut set: felt252 = 0;
        let mut west: felt252 = 0;
        let mut north: felt252 = 0;
        for entry in chunks {
            let (chunk, edges) = *entry;
            set = BoardTrait::or(set, BoardTrait::pow(chunk));
            if edges % 2 == 1 {
                west = BoardTrait::or(west, BoardTrait::pow(chunk));
            }
            if (edges / 2) % 2 == 1 {
                west = BoardTrait::or(west, BoardTrait::pow(chunk - 1));
            }
            if (edges / 4) % 2 == 1 {
                north = BoardTrait::or(north, BoardTrait::pow(chunk - 15));
            }
            if (edges / 8) % 2 == 1 {
                north = BoardTrait::or(north, BoardTrait::pow(chunk));
            }
        }
        Outline { chunks: set, west, north }
    }
}
