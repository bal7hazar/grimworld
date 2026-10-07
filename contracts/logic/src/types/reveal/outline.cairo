//! A dungeon floor's outline, drawn once at `create` (ENG-10a, D-223; ADR-0006 §3, *A dungeon
//! floor's outline, fixed at entry*; built by ENG-10b): which chunks the floor holds and which
//! seams between them are open, from the instance's entry draw alone, so that no order of moves
//! changes it.
//!
//! **The draw** (`draw`), from `seed` (`EntropyTrait::outline`: `derive(entropy, domain(instance,
//! 227, REVEAL), 0)`, the word of no chunk; 225 is the hosts', 226 an authored zone's hosts',
//! SPK-16): the floor starts as its entry chunk and grows one chunk at a time until it holds `N`
//! (or the whole rectangle, when smaller: D-140). Its draws come from one stream, `hexx`'s `Rng`
//! seeded with `seed` (as a chunk's placement): at each step a **member** of the floor (the
//! **winding** law, D-223: the newest chunk with probability 1/2, else uniform by its rank in the
//! order added) and a **side** (uniform of 4) are drawn; the chunk beyond is kept when it is in
//! the rectangle and not in the floor, up to `TRIES` pairs, then the exact draw, uniform over the
//! frontier. The member is the new chunk's **parent**: their seam is open, so the floor is
//! connected; each other seam toward the floor is open but with probability 1 in 7
//! (`super::BORDER`, ENG-05's law of a dungeon's side).
//!
//! **Stored** as three felts (`Outline`, ENG-01 §3.2's `outline` slots): the chunks (bit
//! `15 cy + cx`), the open seams West (bit `c`: between `c` and `c + 1`) and North (bit `c`:
//! between `c` and `c + 15`).
//!
//! **Distances** (`far`, `layers`, `distance`): a breadth-first walk from the entry through the
//! open seams, bit-parallel (a layer is a bitmap); the floor is connected, so every chunk is
//! reached within `N − 1` layers. The last layer holds the chunks farthest from the entry on
//! foot, where the exit and the Heart are drawn (`placement::PlacementTrait::hosts`).

use hexx::board::rng::RngTrait;
use super::board::{BOARD, BoardTrait};

/// Words drawn for a member and a side before the exact draw over the frontier (`draw`; as
/// `placement::TRIES`).
pub const TRIES: u8 = 16;
/// Every chunk but those of column 0, of column 14, of row 0.
const NOT_COLUMN_0: felt252 = 0x1fffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffe;
const NOT_COLUMN_14: felt252 = 0xfffdfffbfff7ffefffdfffbfff7ffefffdfffbfff7ffefffdfffbfff;
const NOT_ROW_0: felt252 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffff8000;
/// `1 / 2` and `1 / 2^15` in the field: a bitmap with no bit in column 0 (row 0) moved one chunk
/// East (South) by a product, exact, as the board's shifts (`board.cairo`).
const INV_2: felt252 = 0x400000000000008800000000000000000000000000000000000000000000001;
const INV_32768: felt252 = 0x7fff00000000010ffde00000000000000000000000000000000000000000001;

/// A dungeon floor's outline (module doc), the three felts `create` stores.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Outline {
    pub chunks: felt252,
    pub west: felt252,
    pub north: felt252,
}

#[generate_trait]
pub impl OutlineImpl of OutlineTrait {
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
        let mut members: Array<u8> = array![entry];
        let mut chunks = BoardTrait::pow(entry);
        let mut west: felt252 = 0;
        let mut north: felt252 = 0;
        let mut rng = RngTrait::new(seed);
        let mut count: u8 = 1;
        while count < target {
            // [Compute] The chunk added and its parent: a member and a side, or the exact draw
            let mut found: Option<(u8, u8)> = Option::None;
            let mut tries: u8 = 0;
            while found.is_none() && tries != TRIES {
                let k = if rng.draw_byte(2) == 0 {
                    count - 1
                } else {
                    rng.draw_byte(count.try_into().unwrap())
                };
                let side = rng.draw_byte(4);
                let member = *members[k.into()];
                if let Option::Some(next) = Self::beside(member, side, width, height) {
                    if !BoardTrait::has(chunks, next) {
                        found = Option::Some((next, member));
                    }
                }
                tries += 1;
            }
            let (chunk, parent) = match found {
                Option::Some(pair) => pair,
                Option::None => {
                    let frontier = BoardTrait::minus(
                        BoardTrait::and(Self::around(chunks), rectangle), chunks,
                    );
                    let chunk = BoardTrait::nth(
                        frontier, rng.draw_byte(BoardTrait::count(frontier).try_into().unwrap()),
                    );
                    // Its parent: its first neighbour in the floor (ENG-01's order of the sides)
                    let mut parent: u8 = 255;
                    let mut side: u8 = 0;
                    while side != 4 {
                        if let Option::Some(next) = Self::beside(chunk, side, width, height) {
                            if parent == 255 && BoardTrait::has(chunks, next) {
                                parent = next;
                            }
                        }
                        side += 1;
                    }
                    (chunk, parent)
                },
            };
            // [Compute] Its seams toward the floor: the parent's open, each other but a border in 7
            let mut side: u8 = 0;
            while side != 4 {
                if let Option::Some(next) = Self::beside(chunk, side, width, height) {
                    if BoardTrait::has(chunks, next) {
                        let border = rng.draw_byte(7) == 0;
                        if next == parent || !border {
                            if side == 0 {
                                west += BoardTrait::pow(chunk);
                            } else if side == 1 {
                                west += BoardTrait::pow(next);
                            } else if side == 2 {
                                north += BoardTrait::pow(next);
                            } else {
                                north += BoardTrait::pow(chunk);
                            }
                        }
                    }
                }
                side += 1;
            }
            chunks += BoardTrait::pow(chunk);
            members.append(chunk);
            count += 1;
        }
        Outline { chunks, west, north }
    }

    /// The chunk beyond `side` of `chunk` (West `+1`, East `−1`, South `−15`, North `+15`) in
    /// the `width × height` rectangle.
    fn beside(chunk: u8, side: u8, width: u8, height: u8) -> Option<u8> {
        let (cy, cx) = DivRem::div_rem(chunk, 15);
        if side == 0 {
            if cx + 1 < width {
                return Option::Some(chunk + 1);
            }
        } else if side == 1 {
            if cx != 0 {
                return Option::Some(chunk - 1);
            }
        } else if side == 2 {
            if cy != 0 {
                return Option::Some(chunk - 15);
            }
        } else if cy + 1 < height {
            return Option::Some(chunk + 15);
        }
        Option::None
    }

    /// The chunks next to `set` (West, East, South, North), within the 15 × 15 board.
    fn around(set: felt252) -> felt252 {
        let west = BoardTrait::and(set, NOT_COLUMN_14) * 2;
        let east = BoardTrait::and(set, NOT_COLUMN_0) * INV_2;
        let north = BoardTrait::and(set * 0x8000, BOARD);
        let south = BoardTrait::and(set, NOT_ROW_0) * INV_32768;
        BoardTrait::or(BoardTrait::or(west, east), BoardTrait::or(north, south))
    }

    /// The chunks one open seam away from `layer`.
    fn step(self: @Outline, layer: felt252) -> felt252 {
        // West: `c + 1` when the seam `c` is open; East: `c − 1` when the seam `c − 1` is
        let west = BoardTrait::and(layer, *self.west) * 2;
        let east = BoardTrait::and(BoardTrait::and(layer, NOT_COLUMN_0) * INV_2, *self.west);
        let north = BoardTrait::and(layer, *self.north) * 0x8000;
        let south = BoardTrait::and(BoardTrait::and(layer, NOT_ROW_0) * INV_32768, *self.north);
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

    /// The chunks by distance from `entry` through the open seams, the farthest layer first, the
    /// entry's left out (where a dungeon's exit and Heart are drawn, `PlacementTrait::hosts`: never
    /// on the entry's chunk, whose anchor is on the spine's core; review t-0089, note 4).
    fn layers(self: @Outline, entry: u8) -> Array<felt252> {
        let mut near: Array<felt252> = array![];
        let mut seen = BoardTrait::pow(entry);
        let mut layer = BoardTrait::minus(self.step(seen), seen);
        seen = BoardTrait::or(seen, layer);
        while layer != 0 {
            near.append(layer);
            layer = BoardTrait::minus(self.step(layer), seen);
            seen = BoardTrait::or(seen, layer);
        }
        let mut out: Array<felt252> = array![];
        let mut k = near.len();
        while k != 0 {
            k -= 1;
            out.append(*near[k]);
        }
        out
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
}
