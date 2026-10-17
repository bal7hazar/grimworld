//! `Loadout`, what the flattening reads of a build besides the passives it holds (`models::build`):
//! `Hub.set_build` builds it, `FlattenLibrary` flattens it; `LoadoutAssert` holds the bounds it
//! owns.

pub mod errors {
    pub const POINTS: felt252 = 'build: points above 12';
    pub const WEAPON_DAMAGE: felt252 = 'build: weapon damage above 27';
    pub const RATING: felt252 = 'build: rating above 560';
}

/// The weighted rating of the pieces and the shield, personalised (F-21: 255 + 25 + 255 + 25).
pub const MAX_RATING: u16 = 560;
/// Attribute points give a rank of at most 12 (design/03; design/20 §1.2's build B).
pub const MAX_POINTS_RANK: u8 = 12;
/// A weapon's base damage at its requirement, at most the maul's 27 (design/15; design/20 row 9).
pub const MAX_WEAPON_BASE_DAMAGE: u8 = 27;

/// What the flattening reads besides the passives (design/03, design/15).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Loadout {
    pub level: u8,
    /// A primary profession of the MVP (1–3).
    pub profession: u8,
    /// The build's attribute points by attribute id, the primary first (design/03). A
    /// quick-cast pair's attribute is its index here, the build-local index of D-157 A.
    pub points: Span<(u8, u8)>,
    /// The attribute of each bar skill (0 for an empty slot), for `MemberStats.ranks` and the
    /// attribute mappings (`quick_cast_slots`, `weapon_required`).
    pub bar_attributes: [u8; 8],
    /// The bar slots holding an attack skill (design/19 §3.4's kind 1), slot `i` at bit `i`.
    pub bar_attacks: u8,
    pub skills: [u16; 8],
    pub elite_slot: u8,
    /// The weapon: class, damage at its requirement (before personalisation), ticks, range, type,
    /// attribute, whether the requirement is met, whether it is personalised.
    pub weapon: u8,
    pub weapon_damage: u8,
    pub weapon_ticks: u8,
    pub weapon_range: u8,
    pub damage_type: u8,
    pub weapon_attribute: u8,
    pub requirement_met: u8,
    pub personalised: bool,
    /// design/04's level cap on weapon strength (DS-9); its curve is BAL-01's (escalated).
    pub strength_cap: u8,
    /// The weighted rating of the pieces and the shield, personalised (design/15, F-21).
    pub rating: u16,
    pub set_bonuses: u16,
    pub belt: [u32; 4],
    pub belt_counts: [u8; 4],
}

#[generate_trait]
pub impl LoadoutAssert of LoadoutAssertTrait {
    /// The build's own bounds design/20 §1 sums from (B, row 9, F-21): each attribute's points
    /// give a rank of at most 12, the weapon's base damage at most 27, the rating at most 560.
    fn assert_loadout(loadout: @Loadout) {
        for (_, points) in *loadout.points {
            assert(*points <= MAX_POINTS_RANK, errors::POINTS);
        }
        assert(*loadout.weapon_damage <= MAX_WEAPON_BASE_DAMAGE, errors::WEAPON_DAMAGE);
        assert(*loadout.rating <= MAX_RATING, errors::RATING);
    }
}
