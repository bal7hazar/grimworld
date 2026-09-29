//! Profession ids (design/03, *Professions*, D-30). The ids follow the order of design/03's table,
//! from 1: 0 is "none" in every layout that holds a profession (`AdventurerCore.profession`,
//! `secondary`; the snapshot). Only the MVP's professions are accepted at creation (D-32).
//! Q-12 (the Arcanist or the Cleric in the MVP) changes which ids are accepted, never an id: the
//! Cleric, 4th in the table, would take id 4.

pub const VANGUARD: u8 = 1;
pub const WARDEN: u8 = 2;
pub const ARCANIST: u8 = 3;

/// A primary profession a player may choose at creation: one of the MVP's three (D-30).
#[inline(always)]
pub fn is_playable(profession: u8) -> bool {
    profession >= VANGUARD && profession <= ARCANIST
}
