//! `AdventurerPlace` as stored (`StoredPlace`): one word, the model's packer layout with `LIVE`
//! (`models::adventurer`). Entering an instance, moving to the next one, being in a hub and
//! unlocking one change it by arithmetic, where the packer decodes and encodes every field
//! (measured in ENG-R1a, l2 gas: 18,000 to unpack and 15,000 to pack). The model and its packer
//! stay the layout and the oracle: each method is pinned against the packer in the tests. Only the
//! store reads and writes it (`HubStoreTrait::get_place`).

use grimworld_logic::packing::{P64, P80, P96, byte_at, join, low_field, split, u16_at};

/// `AdventurerPlace` as stored, one word.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct StoredPlace {
    pub word: felt252,
}

/// Entering an instance, moving to the next one, being in a hub, unlocking one (ENG-06).
#[generate_trait]
pub impl StoredPlaceImpl of StoredPlaceTrait {
    /// `inside`, without decoding the other fields.
    fn is_inside(self: @StoredPlace) -> bool {
        let (low, _) = split(*self.word);
        byte_at(low, P96) != 0
    }

    /// `(instance, hub, last hub, inside)`.
    fn fields(self: @StoredPlace) -> (u64, u16, u16, bool) {
        let (low, _) = split(*self.word);
        (
            low_field(low, P64.try_into().unwrap()).try_into().unwrap(),
            u16_at(low, P64),
            u16_at(low, P80),
            byte_at(low, P96) != 0,
        )
    }

    /// The place of a new adventurer: in `hub`, its last hub, `hub` unlocked (D-144: region 1's
    /// town, unlocked from creation).
    fn new(hub: u16) -> StoredPlace {
        StoredPlace { word: join(hub.into() * P64 + hub.into() * P80, Self::bit(hub)) }
    }

    /// Inside `instance`, entered from its hub: `hub` 0, `last_hub` the hub it left, `inside` 1.
    fn entered(self: StoredPlace, instance: u64) -> StoredPlace {
        let (low, high) = split(self.word);
        StoredPlace { word: join(instance.into() + u16_at(low, P64).into() * P80 + P96, high) }
    }

    /// Still inside, its instance now `instance` (a gate to another location, D-02).
    fn moved(self: StoredPlace, instance: u64) -> StoredPlace {
        let (low, high) = split(self.word);
        let (above, _) = DivRem::div_rem(low, P64.try_into().unwrap());
        StoredPlace { word: join(above * P64 + instance.into(), high) }
    }

    /// In `hub`, which is also its last hub: no instance, not inside.
    fn located(self: StoredPlace, hub: u16) -> StoredPlace {
        let (_, high) = split(self.word);
        StoredPlace { word: join(hub.into() * P64 + hub.into() * P80, high) }
    }

    /// The hub a report closing the presence sends it to: the one reported, else its last hub
    /// (D-04).
    fn return_hub(self: @StoredPlace, reported: u16) -> u16 {
        if reported != 0 {
            return reported;
        }
        let (_, _, last_hub, _) = self.fields();
        last_hub
    }

    /// Back in `hub`, which is also its last hub; `location` unlocked when the report says a hub
    /// was reached (design/01: reaching a hub gate unlocks the hub).
    fn returned(self: StoredPlace, hub: u16, reached: bool, location: u16) -> StoredPlace {
        let located = self.located(hub);
        if reached {
            located.unlocked(location)
        } else {
            located
        }
    }

    /// `hub` unlocked for map travel (design/01: reaching a hub gate unlocks the hub).
    fn unlocked(self: StoredPlace, hub: u16) -> StoredPlace {
        let (low, high) = split(self.word);
        StoredPlace { word: join(low, high | Self::bit(hub)) }
    }

    fn is_unlocked(self: @StoredPlace, hub: u16) -> bool {
        let (_, high) = split(*self.word);
        hub < 64 && high & Self::bit(hub) != 0
    }

    /// Bit `hub` of `unlocked`: a table (docs/CAIRO.md §3); a hub id of 64 or more is refused.
    fn bit(hub: u16) -> u128 {
        match hub {
            0 => 0x1,
            1 => 0x2,
            2 => 0x4,
            3 => 0x8,
            4 => 0x10,
            5 => 0x20,
            6 => 0x40,
            7 => 0x80,
            8 => 0x100,
            9 => 0x200,
            10 => 0x400,
            11 => 0x800,
            12 => 0x1000,
            13 => 0x2000,
            14 => 0x4000,
            15 => 0x8000,
            16 => 0x10000,
            17 => 0x20000,
            18 => 0x40000,
            19 => 0x80000,
            20 => 0x100000,
            21 => 0x200000,
            22 => 0x400000,
            23 => 0x800000,
            24 => 0x1000000,
            25 => 0x2000000,
            26 => 0x4000000,
            27 => 0x8000000,
            28 => 0x10000000,
            29 => 0x20000000,
            30 => 0x40000000,
            31 => 0x80000000,
            32 => 0x100000000,
            33 => 0x200000000,
            34 => 0x400000000,
            35 => 0x800000000,
            36 => 0x1000000000,
            37 => 0x2000000000,
            38 => 0x4000000000,
            39 => 0x8000000000,
            40 => 0x10000000000,
            41 => 0x20000000000,
            42 => 0x40000000000,
            43 => 0x80000000000,
            44 => 0x100000000000,
            45 => 0x200000000000,
            46 => 0x400000000000,
            47 => 0x800000000000,
            48 => 0x1000000000000,
            49 => 0x2000000000000,
            50 => 0x4000000000000,
            51 => 0x8000000000000,
            52 => 0x10000000000000,
            53 => 0x20000000000000,
            54 => 0x40000000000000,
            55 => 0x80000000000000,
            56 => 0x100000000000000,
            57 => 0x200000000000000,
            58 => 0x400000000000000,
            59 => 0x800000000000000,
            60 => 0x1000000000000000,
            61 => 0x2000000000000000,
            62 => 0x4000000000000000,
            63 => 0x8000000000000000,
            _ => StoredPlaceAssert::hub_above_63(),
        }
    }
}

pub mod errors {
    /// `AdventurerPlace.unlocked` holds hub ids below 64.
    pub const HUB_ABOVE_63: felt252 = 'hub above 63';
    /// Map travel to a hub not unlocked (design/01 *Connectivity*).
    pub const NOT_UNLOCKED: felt252 = 'hub not unlocked';
    /// A report for an adventurer not inside that instance.
    pub const NOT_ITS_INSTANCE: felt252 = 'not its instance';
}

#[generate_trait]
pub impl StoredPlaceAssert of StoredPlaceAssertTrait {
    /// Map travel goes to an unlocked hub (design/01 *Connectivity*).
    fn assert_unlocked(self: @StoredPlace, hub: u16) {
        assert(self.is_unlocked(hub), errors::NOT_UNLOCKED);
    }

    /// A report is about the instance its first contributor is inside (ENG-01 §6).
    fn assert_in_instance(self: @StoredPlace, instance: u64) {
        let (current, _, _, inside) = self.fields();
        assert(inside && current == instance, errors::NOT_ITS_INSTANCE);
    }

    /// The refusal of a hub id of 64 or more (`AdventurerPlace.unlocked` holds bits 0-63): the
    /// last arm of `StoredPlaceTrait::bit`, which never returns.
    fn hub_above_63() -> core::never {
        core::panic_with_felt252(errors::HUB_ABOVE_63)
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::super::adventurer::AdventurerPlace;
    use super::{StoredPlace, StoredPlaceTrait};

    fn stored_place(model: AdventurerPlace) -> StoredPlace {
        StoredPlace { word: StorePacking::pack(model) }
    }

    // ENG-06: entering, moving, located, unlocked, against the packer; the bit table against the
    // powers of two.
    #[test]
    #[available_gas(l2_gas: 2676855)] // ceil(1.05 × 2549385 measured)
    fn test_place_words() {
        let start = AdventurerPlace { instance: 0, hub: 5, last_hub: 5, inside: 0, unlocked: 0x20 };
        let stored = StoredPlaceTrait::new(5);
        assert(stored == stored_place(start), 'new');
        assert(stored.fields() == (0, 5, 5, false), 'fields');

        let unlocked = AdventurerPlace { unlocked: 0x8000000000000021, ..start };
        let id: u64 = 0xFFFFFFFF00000007;
        let inside = AdventurerPlace { instance: id, hub: 0, last_hub: 5, inside: 1, ..unlocked };
        let entered = stored_place(unlocked).entered(id);
        assert(entered == stored_place(inside), 'entered');
        assert(entered.fields() == (id, 0, 5, true), 'inside fields');
        assert(entered.is_inside(), 'inside');

        let next: u64 = 0x100000008;
        let moved = entered.moved(next);
        assert(moved == stored_place(AdventurerPlace { instance: next, ..inside }), 'moved');

        let located = moved.located(9);
        let back = AdventurerPlace { instance: 0, hub: 9, last_hub: 9, inside: 0, ..unlocked };
        assert(located == stored_place(back), 'located');
        assert(!located.is_unlocked(9), 'not yet');
        let opened = located.unlocked(9);
        assert(
            opened == stored_place(AdventurerPlace { unlocked: 0x8000000000000221, ..back }),
            'unlock',
        );
        assert(opened.is_unlocked(9), 'unlocked');
        assert(opened.is_unlocked(63), 'bit 63');
        assert(!opened.is_unlocked(64), 'no hub 64');
        assert(opened.unlocked(9) == opened, 'twice');
        for hub in 0..64_u16 {
            let bit: u128 = StoredPlaceTrait::bit(hub);
            assert(bit == core::num::traits::Pow::pow(2_u128, hub.into()), 'bit table');
        }
    }

    #[test]
    #[should_panic(expected: 'hub above 63')]
    #[available_gas(l2_gas: 23783)] // ceil(1.05 × 22650 measured)
    fn test_place_hub_above_63_refused() {
        StoredPlaceTrait::new(64);
    }

    // The report's return: the hub reported, else the last one; unlocked when a hub was reached.
    #[test]
    #[available_gas(l2_gas: 110666)] // ceil(1.05 × 105396 measured)
    fn test_place_returned() {
        let inside = stored_place(
            AdventurerPlace { instance: 9, hub: 0, last_hub: 5, inside: 1, unlocked: 0x20 },
        );
        assert(inside.return_hub(0) == 5 && inside.return_hub(7) == 7, 'return hub');
        assert(inside.returned(5, false, 3) == inside.located(5), 'located');
        assert(inside.returned(7, true, 3) == inside.located(7).unlocked(3), 'reached');
    }
}
