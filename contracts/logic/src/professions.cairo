//! Professions (design/03, *Professions*, D-30). Their ids follow the order of design/03's table,
//! from 1: 0 is "none" in every layout that holds a profession (`AdventurerCore.profession`,
//! `secondary`; the snapshot). Only the MVP's professions are accepted at creation (D-32).
//! Q-12 (the Arcanist or the Cleric in the MVP) changes which ids are accepted, never an id: the
//! Cleric, 4th in the table, would take id 4.

/// The MVP's professions (D-30), in design/03's order.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Profession {
    Vanguard,
    Warden,
    Arcanist,
}

/// A profession's id in every layout (1, 2, 3).
pub impl ProfessionIntoU8 of Into<Profession, u8> {
    fn into(self: Profession) -> u8 {
        match self {
            Profession::Vanguard => 1,
            Profession::Warden => 2,
            Profession::Arcanist => 3,
        }
    }
}

pub mod errors {
    /// Not one of the MVP's professions.
    pub const BAD_PROFESSION: felt252 = 'bad profession';
}

#[generate_trait]
pub impl ProfessionImpl of ProfessionTrait {
    /// A primary profession a player may choose at creation: the id of one of the MVP's three.
    #[inline(always)]
    fn is_playable(id: u8) -> bool {
        id >= 1 && id <= 3
    }
}

#[generate_trait]
pub impl ProfessionAssert of ProfessionAssertTrait {
    fn assert_playable(id: u8) {
        assert(ProfessionTrait::is_playable(id), errors::BAD_PROFESSION);
    }
}
