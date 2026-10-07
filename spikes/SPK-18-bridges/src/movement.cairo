//! **Superseded by D-227** (one level): the two-level prototype of D-217, kept as history; its
//! "ADR-0008 rule N" are the rules of ADR-0008 at `38cfd13`.
//!
//! The movement check of one Move on the window (design/04 *Actions*: one tile, six directions),
//! on one level and on two (ADR-0008 rules 2 and 3). Positions are the window's (`15 y + x`,
//! `hexx`'s odd-r layout, ENG-02), bitmaps of 240 bits as `u256` (`hexx`'s `Bits`).
//!
//! - `Ground` is the check ENG-07 builds under D-225 (one level, the walkable plane): the next
//!   tile walkable and not taken. Not on main yet: this is its prototype, the comparison's base.
//! - `Bridged` adds the deck: `deck` (the window's tiles under a deck), `ends` (the window's
//!   bridge ends), `aloft` (the tiles taken on the deck level). With no deck in the window it is
//!   `Ground`'s check after one comparison. Otherwise (ADR-0008 rule 2):
//!   - on the ground, a step from an end onto its deck **climbs** (the deck's tile free aloft);
//!     a step between a deck's tile and an end on the ground is refused (the cut: the edge is the
//!     climb's); any other step is `Ground`'s, so a deck's tile with walkable ground beneath is
//!     passed **under**;
//!   - on the deck, a step goes to a deck tile (free aloft) or **descends** to an end (free on the
//!     ground); nothing else (the railings).
//!   ADR-0008's R-38 (two bridges' decks never adjacent, an end never on or next to another
//!   bridge's deck) makes the masks exact: a deck tile next to an end is that end's bridge's.
//!
//! The window's ring is wall on both levels: the assembly clears `deck` and `ends` there as it
//! does `open` (ADR-0006 §4).

use hexx::board::bits::Bits;
use hexx::board::direction::Direction;
use hexx::board::layout::LayoutTrait;
use crate::level::{DECK, GROUND};

/// The window's columns and rows (design/02, D-120).
pub const WIDTH: u8 = 15;
pub const HEIGHT: u8 = 16;

pub mod errors {
    pub const FACING: felt252 = 'movement: facing';
}

/// One level: the walkable plane and the tiles taken.
#[derive(Copy, Drop)]
pub struct Ground {
    pub open: u256,
    pub taken: u256,
}

/// Two levels: the ground's `open` and `taken`, the decks, their ends, the deck's tiles taken.
#[derive(Copy, Drop)]
pub struct Bridged {
    pub open: u256,
    pub taken: u256,
    pub deck: u256,
    pub ends: u256,
    pub aloft: u256,
}

#[generate_trait]
pub impl GroundImpl of GroundTrait {
    /// The tile a Move in `facing` reaches from `from`, `None` when it is refused.
    fn step(self: @Ground, from: u8, facing: u8) -> Option<u8> {
        let to = LayoutTrait::neighbor(WIDTH, HEIGHT, from, direction(facing))?;
        if Bits::get(*self.open, to) && !Bits::get(*self.taken, to) {
            Some(to)
        } else {
            None
        }
    }
}

#[generate_trait]
pub impl BridgedImpl of BridgedTrait {
    /// The tile and level a Move in `facing` reaches from `from` at `level`, `None` when it is
    /// refused.
    fn step(self: @Bridged, from: u8, level: u8, facing: u8) -> Option<(u8, u8)> {
        let to = LayoutTrait::neighbor(WIDTH, HEIGHT, from, direction(facing))?;
        let deck = *self.deck;
        // No deck in the window (every generated chunk, most of a zone): `Ground`'s check
        if deck == 0 {
            return if Bits::get(*self.open, to) && !Bits::get(*self.taken, to) {
                Some((to, GROUND))
            } else {
                None
            };
        }
        let ends = *self.ends;
        if level == GROUND {
            let onto_deck = Bits::get(deck, to);
            let from_end = Bits::get(ends, from);
            // The climb: from an end onto its deck
            if onto_deck && from_end {
                return if Bits::get(*self.aloft, to) {
                    None
                } else {
                    Some((to, DECK))
                };
            }
            // The cut: under a deck to its end, the edge being the climb's
            if Bits::get(deck, from) && Bits::get(ends, to) {
                return None;
            }
            if Bits::get(*self.open, to) && !Bits::get(*self.taken, to) {
                Some((to, GROUND))
            } else {
                None
            }
        } else if Bits::get(deck, to) {
            // Along the deck
            if Bits::get(*self.aloft, to) {
                None
            } else {
                Some((to, DECK))
            }
        } else if Bits::get(ends, to) {
            // The descent to an end
            if Bits::get(*self.taken, to) {
                None
            } else {
                Some((to, GROUND))
            }
        } else {
            None
        }
    }
}

/// A facing `0..=5` as `hexx`'s direction (ENG-02's order: East, North-East, North-West, West,
/// South-West, South-East).
fn direction(facing: u8) -> Direction {
    match facing {
        0 => Direction::East,
        1 => Direction::NorthEast,
        2 => Direction::NorthWest,
        3 => Direction::West,
        4 => Direction::SouthWest,
        5 => Direction::SouthEast,
        _ => {
            assert(false, errors::FACING);
            Direction::East
        },
    }
}
