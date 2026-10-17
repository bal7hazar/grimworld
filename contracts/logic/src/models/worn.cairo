//! `Worn`, an item worn as `Hub.set_build` reads it, and the passives the worn items hold, for
//! the flattening (`models::build`; CBT-02c's wiring, D-168).

use crate::models::held_passive::HeldPassive;
use crate::models::index::Modifier;
use crate::models::modifier::{ModifierRecord, ModifierTrait};
use crate::types::passive::{Passive, Source};

pub mod errors {
    /// A modifier on the item that the registry does not hold.
    pub const NO_MODIFIER: felt252 = 'item: no such modifier';
    /// An insignia made for another piece than the one it is worn on (DS-23, D-160).
    pub const INSIGNIA_PIECE: felt252 = 'item: insignia piece';
    /// A modifier in a slot of another type than its record's (ENG-01 §3.3).
    pub const SLOT_TYPE: felt252 = 'item: modifier slot type';
    /// A benefit's rolled value outside its record's range (design/19 §4).
    pub const VALUE: felt252 = 'item: modifier value';
}

/// An item worn, as `Hub.set_build` reads it (ENG-01 §3.3): its lane of `equipped` (0 the weapon
/// … 6 the feet), its slot (`base::slot`, copied from its `BASE` at creation, D-158), and its
/// `ItemMods`: the modifier id and the rolled value of each slot type in order (prefix, suffix,
/// inscription, insignia, rune), id 0 for an empty slot.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Worn {
    pub lane: u8,
    pub slot: u8,
    pub ids: [u16; 5],
    pub values: [u8; 5],
}

#[generate_trait]
pub impl WornImpl of WornTrait {
    /// The passives the worn items hold, for the flattening (design/19 §4, §7.2; design/20
    /// §1.2):
    /// each modifier's benefit, its value the item's rolled byte, and its cost, fixed by its
    /// record; their source the record's slot type; one instance a modifier, numbered
    /// `5 × lane + slot`, so upward; an insignia's piece the item's slot (DS-23). `ids` are the
    /// distinct modifier ids the items hold and `records` their `MODIFIER` records, one part each,
    /// in the same order (`Hub.set_build` asks the registry for them once, however many items
    /// hold one). Bound: 7 items, 5 modifiers an item, 15 records.
    fn held(worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>) -> Array<HeldPassive> {
        let mut modifiers: Array<Modifier> = array![];
        for part in records {
            WornAssert::assert_exists(*part);
            modifiers.append(ModifierRecord::unpack(array![*part].span()));
        }
        let modifiers = modifiers.span();
        let mut out: Array<HeldPassive> = array![];
        for item in worn {
            let first = *item.lane * 5;
            let values = item.values.span();
            let mut slot: u8 = 0;
            for id in item.ids.span() {
                let id = *id;
                if id != 0 {
                    let mut k = 0;
                    while *ids[k] != id {
                        k += 1;
                    }
                    let record = modifiers[k];
                    let value = *values[slot.into()];
                    WornAssert::assert_slot(*record.slot, slot);
                    WornAssert::assert_value(value, record.benefit);
                    let source = record.source().unwrap();
                    let piece = if source == Source::Insignia {
                        WornAssert::assert_piece(*record.piece, *item.slot);
                        *item.slot
                    } else {
                        0
                    };
                    let instance = first + slot;
                    let benefit = Passive { max: value.into(), ..*record.benefit };
                    out
                        .append(
                            HeldPassive {
                                passive: benefit,
                                source,
                                instance,
                                modifier: id.into(),
                                benefit: true,
                                piece,
                            },
                        );
                    if record.has_cost() {
                        out
                            .append(
                                HeldPassive {
                                    passive: *record.cost,
                                    source,
                                    instance,
                                    modifier: id.into(),
                                    benefit: false,
                                    piece,
                                },
                            );
                    }
                }
                slot += 1;
            }
        }
        out
    }
}

#[generate_trait]
pub impl WornAssert of WornAssertTrait {
    /// A modifier an item holds is a record of the registry (its part 0 is not 0).
    #[inline(always)]
    fn assert_exists(part: felt252) {
        assert(part != 0, errors::NO_MODIFIER);
    }

    /// A modifier sits in the slot of its record's type: `ItemMods`' five slots are the five
    /// slot types in order (`modifier::slot::PREFIX` … `RUNE`, ENG-01 §3.3), so an item holds at
    /// most one of each. `position` is the slot's, from 0.
    #[inline(always)]
    fn assert_slot(slot_type: u8, position: u8) {
        assert(slot_type == position + 1, errors::SLOT_TYPE);
    }

    /// The benefit's rolled value lies within its record's range (design/19 §4): the per-source
    /// bounds the registry checked on the record (D-166) then bound it.
    #[inline(always)]
    fn assert_value(value: u8, benefit: @Passive) {
        let value: i16 = value.into();
        assert(value >= *benefit.min && value <= *benefit.max, errors::VALUE);
    }

    /// DS-23 (D-160): an insignia is worn on the piece its record names (`base::slot::CHEST` …
    /// `FEET`), the item's slot.
    #[inline(always)]
    fn assert_piece(piece: u8, slot: u8) {
        assert(piece == slot, errors::INSIGNIA_PIECE);
    }
}

#[cfg(test)]
pub mod tests {
    use crate::models::base::slot as base_slot;
    use crate::models::build::tests::BuildFixture;
    use crate::models::held_passive::HeldPassive;
    use crate::models::index::Modifier;
    use crate::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
    use crate::types::combat::damage;
    use crate::types::passive::{Passive, PassiveTrait, Source, id};
    use super::{Worn, WornTrait};

    // ---- the items worn (CBT-02e, D-168: `WornTrait::held`) ---------------------------------

    #[generate_trait]
    pub impl WornFixtureImpl of WornFixture {
        /// The `MODIFIER` records of the tests below, one part each as the registry stores them: 1
        /// a prefix and 2 a suffix (life steal 1…5, costing 7 armor against cold), 3 an insignia
        /// made for the chest (armor against fire 1…7, no cost), 4 a rune (fire 1…7, costing 7
        /// against cold).
        fn worn_records() -> (Span<u16>, Span<felt252>) {
            let cold = PassiveTrait::new(id::ARMOR_VS, damage::COLD, 0, 0, 7, 7);
            let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 1, 5);
            let fire = PassiveTrait::new(id::ARMOR_VS, damage::FIRE, 0, 0, 1, 7);
            let none: Passive = Default::default();
            let records: Array<Modifier> = array![
                ModifierTrait::new(modifier_slot::PREFIX, steal, cold),
                ModifierTrait::new(modifier_slot::SUFFIX, steal, cold),
                ModifierTrait::insignia(base_slot::CHEST, fire, none),
                ModifierTrait::new(modifier_slot::RUNE, fire, cold),
            ];
            let mut parts = array![];
            for record in records.span() {
                parts.append(*ModifierRecord::pack(record)[0]);
            }
            (array![1, 2, 3, 4].span(), parts.span())
        }

        /// A sword (lane 0) holding modifiers 1 and 2 rolled at 5 and 3, and a chest (lane 2)
        /// holding the insignia rolled at 6 and the rune at 7.
        fn worn_items() -> Span<Worn> {
            array![
                Worn {
                    lane: 0, slot: base_slot::WEAPON, ids: [1, 2, 0, 0, 0], values: [5, 3, 0, 0, 0],
                },
                Worn {
                    lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 3, 4], values: [0, 0, 0, 6, 7],
                },
            ]
                .span()
        }
    }

    // Each modifier's benefit at its rolled value, then its cost; instances `5 × lane + slot`; the
    // insignia's piece the chest's slot.
    #[test]
    #[available_gas(l2_gas: 710777)] // ceil(1.05 × 676930 measured)
    fn test_worn_held() {
        let (ids, records) = WornFixture::worn_records();
        let held_passives = WornTrait::held(WornFixture::worn_items(), ids, records);
        let cold = BuildFixture::passive(id::ARMOR_VS, damage::COLD, 7);
        let expected = array![
            BuildFixture::held(
                PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 1, 5), Source::Prefix, 0, 1,
            ),
            BuildFixture::cost(cold, Source::Prefix, 0, 1),
            BuildFixture::held(
                PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 1, 3), Source::Suffix, 1, 2,
            ),
            BuildFixture::cost(cold, Source::Suffix, 1, 2),
            HeldPassive {
                passive: PassiveTrait::new(id::ARMOR_VS, damage::FIRE, 0, 0, 1, 6),
                source: Source::Insignia,
                instance: 13,
                modifier: 3,
                benefit: true,
                piece: base_slot::CHEST,
            },
            BuildFixture::held(
                PassiveTrait::new(id::ARMOR_VS, damage::FIRE, 0, 0, 1, 7), Source::Rune, 14, 4,
            ),
            BuildFixture::cost(cold, Source::Rune, 14, 4),
        ];
        assert(held_passives == expected, 'held');
    }

    #[test]
    #[available_gas(l2_gas: 357903)] // ceil(1.05 × 340860 measured)
    #[should_panic(expected: 'item: no such modifier')]
    fn test_worn_unknown_modifier_refused() {
        let (ids, _) = WornFixture::worn_records();
        WornTrait::held(WornFixture::worn_items(), ids, array![0, 0, 0, 0].span());
    }

    // A rune (4) in the insignia's slot.
    #[test]
    #[available_gas(l2_gas: 546851)] // ceil(1.05 × 520810 measured)
    #[should_panic(expected: 'item: modifier slot type')]
    fn test_worn_slot_type_refused() {
        let (ids, records) = WornFixture::worn_records();
        let item = Worn {
            lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 4, 0], values: [0, 0, 0, 7, 0],
        };
        WornTrait::held(array![item].span(), ids, records);
    }

    // Fire 1…7: 8 is refused, and 0 (`test_worn_value_below_refused`).
    #[test]
    #[available_gas(l2_gas: 540120)] // ceil(1.05 × 514400 measured)
    #[should_panic(expected: 'item: modifier value')]
    fn test_worn_value_above_refused() {
        let (ids, records) = WornFixture::worn_records();
        let item = Worn {
            lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 4], values: [0, 0, 0, 0, 8],
        };
        WornTrait::held(array![item].span(), ids, records);
    }

    #[test]
    #[available_gas(l2_gas: 539627)] // ceil(1.05 × 513930 measured)
    #[should_panic(expected: 'item: modifier value')]
    fn test_worn_value_below_refused() {
        let (ids, records) = WornFixture::worn_records();
        let item = Worn {
            lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 4], values: [0, 0, 0, 0, 0],
        };
        WornTrait::held(array![item].span(), ids, records);
    }

    // DS-23: the chest's insignia on the legs.
    #[test]
    #[available_gas(l2_gas: 544394)] // ceil(1.05 × 518470 measured)
    #[should_panic(expected: 'item: insignia piece')]
    fn test_worn_insignia_piece_refused() {
        let (ids, records) = WornFixture::worn_records();
        let item = Worn {
            lane: 3, slot: base_slot::LEGS, ids: [0, 0, 0, 3, 0], values: [0, 0, 0, 6, 0],
        };
        WornTrait::held(array![item].span(), ids, records);
    }
}
