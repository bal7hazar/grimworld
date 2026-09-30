//! The snapshot stored with the adventurer (D-168): the flattening's three packed words
//! (`MemberStats`, `MemberBar`, `MemberKit`, `grimworld_logic::snapshot`), computed once by
//! `Hub.set_build` through `FlattenLibrary` and copied by `Hub.enter` to `Instances` (ADR-0001:
//! the ephemeral domain reads a snapshot taken at entry, here the stored one). Three slots under
//! the adventurer's id: docs/architecture/ENG-01-interfaces.md, *Hub storage*.
//!
//! The kit word carries the snapshot's state in bits the kit leaves free (its high limb ends at
//! bit 202): the registry's content version it was computed under at bits 208–239, the stale
//! mark at bit 240, `LIVE` at 250 (set by the packers). A slot never written is 0: no snapshot.
//! `Hub.enter` refuses a missing one, and a stale one: marked, of another content version, or of
//! another level than the adventurer's (D-168 2).

/// Offsets of the words of `StoredSnapshot` from its address.
pub const STATS_WORD: u8 = 0;
pub const BAR_WORD: u8 = 1;
pub const KIT_WORD: u8 = 2;

/// `2^208`: the content version's unit in the kit word (bits 208–239).
const VERSION_UNIT: felt252 = 0x10000000000000000000000000000000000000000000000000000;
/// `2^80`: the kit word's high limb above it is the state (version, stale mark, `LIVE`).
const STATE_SHIFT: u128 = 0x100000000000000000000;
/// `LIVE` in the state (bit 250 − 208).
const STATE_LIVE: u128 = 0x40000000000;

/// The kit word of a snapshot marked stale (bit 240, `LIVE`): an entrypoint that changes an input
/// of the flattening and does not recompute writes it, in one write, without reading (D-168 2).
pub const STALE_MARK: felt252 = 0x401000000000000000000000000000000000000000000000000000000000000;

pub mod errors {
    /// No snapshot: `set_build` was never called for the adventurer.
    pub const MISSING: felt252 = 'snapshot: missing';
    /// The snapshot is marked stale, of another content version, or of another level: the client
    /// sends `set_build` first (D-168 2).
    pub const STALE: felt252 = 'snapshot: stale';
}

/// Three consecutive slots under the adventurer's id, the words as stored.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct StoredSnapshot {
    pub stats: felt252,
    pub bar: felt252,
    pub kit: felt252,
}

#[generate_trait]
pub impl StoredSnapshotImpl of StoredSnapshotTrait {
    /// The stored kit word: the packed kit (`LIVE` set) and the content `version` it was computed
    /// under.
    #[inline(always)]
    fn seal(kit: felt252, version: u32) -> felt252 {
        kit + version.into() * VERSION_UNIT
    }

    /// The packed kit of a stored kit word `StoredSnapshotAssert::assert_fresh` accepted.
    #[inline(always)]
    fn kit(word: felt252, version: u32) -> felt252 {
        word - version.into() * VERSION_UNIT
    }
}

#[generate_trait]
pub impl StoredSnapshotAssert of StoredSnapshotAssertTrait {
    /// The stored kit word is a snapshot (`MISSING`) of the registry's content `version`, not
    /// marked stale (`STALE`). One conversion and one division.
    fn assert_fresh(word: felt252, version: u32) {
        assert(word != 0, errors::MISSING);
        let wide: u256 = word.into();
        let state = wide.high / STATE_SHIFT;
        assert(state == STATE_LIVE + version.into(), errors::STALE);
    }

    /// The snapshot was computed at the adventurer's `level` (a level up changes it, GLD-01).
    #[inline(always)]
    fn assert_level(snapshot: u8, level: u8) {
        assert(snapshot == level, errors::STALE);
    }
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::LIVE;
    use grimworld_logic::snapshot::{MemberKit, pack_kit, unpack_kit};
    use super::{STALE_MARK, StoredSnapshotAssert, StoredSnapshotTrait, errors};

    fn kit() -> felt252 {
        pack_kit(
            MemberKit {
                belt: [0xffffffff; 4],
                life_steal: 255,
                energy_on_hit: 255,
                condition: 15,
                condition_duration: 63,
                enchantment_duration: 63,
                double_adrenaline_every: 255,
                health_bonus: 0xffff,
                armor_stance: -1,
                armor_enchanted: -1,
                knockdown: 3,
                halving: true,
            },
        )
    }

    // Sealed with the widest kit and version, the kit comes back whole, and the state reads.
    #[test]
    #[available_gas(l2_gas: 160000)]
    fn test_seal_round_trip() {
        let version = 0xffffffff;
        let word = StoredSnapshotTrait::seal(kit(), version);
        StoredSnapshotAssert::assert_fresh(word, version);
        let back = StoredSnapshotTrait::kit(word, version);
        assert(back == kit(), 'kit');
        assert(unpack_kit(back) == unpack_kit(kit()), 'unpacked');
        let word = StoredSnapshotTrait::seal(kit(), 0);
        StoredSnapshotAssert::assert_fresh(word, 0);
    }

    #[test]
    #[available_gas(l2_gas: 40000)]
    #[should_panic(expected: 'snapshot: missing')]
    fn test_missing_refused() {
        StoredSnapshotAssert::assert_fresh(0, 0);
    }

    #[test]
    #[available_gas(l2_gas: 60000)]
    #[should_panic(expected: 'snapshot: stale')]
    fn test_stale_mark_refused() {
        StoredSnapshotAssert::assert_fresh(STALE_MARK, 0);
    }

    #[test]
    #[available_gas(l2_gas: 80000)]
    #[should_panic(expected: 'snapshot: stale')]
    fn test_other_version_refused() {
        StoredSnapshotAssert::assert_fresh(StoredSnapshotTrait::seal(kit(), 4), 5);
    }

    #[test]
    #[available_gas(l2_gas: 40000)]
    #[should_panic(expected: 'snapshot: stale')]
    fn test_other_level_refused() {
        StoredSnapshotAssert::assert_level(3, 4);
    }

    // The stale mark is `LIVE` and bit 240 alone.
    #[test]
    #[available_gas(l2_gas: 40000)]
    fn test_stale_mark_bits() {
        assert(STALE_MARK == LIVE + 0x1000000000000000000000000000000000000000000000000000000000000, 'mark');
        assert(errors::STALE != errors::MISSING, 'errors');
    }
}
