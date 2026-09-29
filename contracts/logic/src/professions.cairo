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

    /// The base energy of a primary profession (design/03, *Professions*): a table.
    fn energy(id: u8) -> u8 {
        match id {
            0 => core::panic_with_felt252(errors::BAD_PROFESSION),
            1 => 20,
            2 => 25,
            3 => 30,
            _ => core::panic_with_felt252(errors::BAD_PROFESSION),
        }
    }

    /// Its energy regeneration, in pips (design/03).
    fn energy_regen(id: u8) -> u8 {
        match id {
            0 => core::panic_with_felt252(errors::BAD_PROFESSION),
            1 => 2,
            2 => 3,
            3 => 4,
            _ => core::panic_with_felt252(errors::BAD_PROFESSION),
        }
    }

    /// How many attributes it has, its primary first (design/03, *Attributes*: 26 in all, D-157):
    /// a table over the six professions, since a secondary profession may be any of them.
    fn attributes(id: u8) -> u8 {
        match id {
            0 => core::panic_with_felt252(errors::BAD_PROFESSION),
            1 => 5,
            2 => 4,
            3 => 5,
            4 => 4,
            5 => 4,
            6 => 4,
            _ => core::panic_with_felt252(errors::BAD_PROFESSION),
        }
    }

    /// The armor of its armor class (design/03's table). design/03 says armor "scales with level"
    /// without a formula: the class's value is used at every level until one is written
    /// (escalated in ENG-06's report).
    fn armor(id: u8) -> u8 {
        match id {
            0 => core::panic_with_felt252(errors::BAD_PROFESSION),
            1 => 80,
            2 => 70,
            3 => 60,
            _ => core::panic_with_felt252(errors::BAD_PROFESSION),
        }
    }
}

#[generate_trait]
pub impl ProfessionAssert of ProfessionAssertTrait {
    fn assert_playable(id: u8) {
        assert(ProfessionTrait::is_playable(id), errors::BAD_PROFESSION);
    }
}
