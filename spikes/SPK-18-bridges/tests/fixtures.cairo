//! The windows of the tests: the editor's bridge (CLI-09e §1 *Bridges*: a one-hex deck, the
//! southern end South-West of it, the northern end North-West of it, both ends in one column on
//! screen) at the window's centre, over a road (the ground beneath walkable: passed under) or over
//! a river (the ground beneath a wall); and a two-tile deck for the walk along it.

use hexx::board::bits::Bits;
use hexx::board::direction::Direction;
use hexx::board::layout::LayoutTrait;
use spk18::movement::{Bridged, Ground, HEIGHT, WIDTH};

/// The window's tile `(x, y)`.
pub fn at(x: u8, y: u8) -> u8 {
    15 * y + x
}

/// The neighbour of `tile` in `direction`, inside the window.
pub fn next(tile: u8, direction: Direction) -> u8 {
    LayoutTrait::neighbor(WIDTH, HEIGHT, tile, direction).unwrap()
}

/// The bitmap of a list of tiles.
pub fn mask(tiles: Span<u8>) -> u256 {
    let mut out: felt252 = 0;
    for tile in tiles {
        out += Bits::pow(*tile);
    }
    out.into()
}

/// Every interior tile of the window walkable (the ring is wall, ADR-0006 §4), but `walls`.
pub fn open(walls: Span<u8>) -> u256 {
    let mut out: felt252 = 0;
    for y in 1..HEIGHT - 1 {
        for x in 1..WIDTH - 1 {
            out += Bits::pow(at(x, y));
        }
    }
    for wall in walls {
        out -= Bits::pow(*wall);
    }
    out.into()
}

/// The deck's tile.
pub fn deck() -> u8 {
    at(7, 8)
}

/// The southern end and the northern end (CLI-09e: the deck North-East of the southern end, the
/// northern end North-West of the deck).
pub fn ends() -> (u8, u8) {
    (next(deck(), Direction::SouthWest), next(deck(), Direction::NorthWest))
}

/// The editor's bridge over a road: the ground under the deck walkable.
pub fn road(taken: Span<u8>, aloft: Span<u8>) -> Bridged {
    let (south, north) = ends();
    Bridged {
        open: open([].span()),
        taken: mask(taken),
        deck: mask([deck()].span()),
        ends: mask([south, north].span()),
        aloft: mask(aloft),
    }
}

/// The same bridge over a river: the ground under the deck a wall.
pub fn river() -> Bridged {
    let (south, north) = ends();
    Bridged {
        open: open([deck()].span()),
        taken: 0,
        deck: mask([deck()].span()),
        ends: mask([south, north].span()),
        aloft: 0,
    }
}

/// A two-tile deck, `deck()` and its North-East neighbour, over a river: the southern end as the
/// editor's, the northern end North-West of the second tile.
pub fn long() -> (Bridged, u8, u8) {
    let second = next(deck(), Direction::NorthEast);
    let (south, _) = ends();
    let north = next(second, Direction::NorthWest);
    let board = Bridged {
        open: open([deck(), second].span()),
        taken: 0,
        deck: mask([deck(), second].span()),
        ends: mask([south, north].span()),
        aloft: 0,
    };
    (board, second, north)
}

/// The window with no deck, as `Bridged` and as `Ground`.
pub fn plain() -> (Bridged, Ground) {
    let walls = [at(3, 3)].span();
    (
        Bridged { open: open(walls), taken: 0, deck: 0, ends: 0, aloft: 0 },
        Ground { open: open(walls), taken: 0 },
    )
}

/// The inputs of the costs, opaque to the compiler: a constant input would be folded at compile
/// time (`hexx`'s benchmarks, ENG-02's `Fixture::bench`).
#[inline(never)]
pub fn opaque(value: u8) -> u8 {
    value
}

#[inline(never)]
pub fn opaque_word(value: felt252) -> felt252 {
    value
}

#[inline(never)]
pub fn bench_ground() -> Ground {
    let (_, ground) = plain();
    ground
}

#[inline(never)]
pub fn bench_plain() -> Bridged {
    let (bridged, _) = plain();
    bridged
}

#[inline(never)]
pub fn bench_road() -> Bridged {
    road([].span(), [].span())
}
