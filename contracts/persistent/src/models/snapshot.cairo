//! The snapshot stored with the adventurer (D-168): the flattening's three packed words
//! (`MemberStats`, `MemberBar`, `MemberKit`, `grimworld_logic::snapshot`), computed once by
//! `Hub.set_build` through `FlattenLibrary` and copied by `Hub.enter` to `Instances` (ADR-0001:
//! the ephemeral domain reads a snapshot taken at entry, here the stored one). Three slots under
//! the adventurer's id: docs/architecture/ENG-01-interfaces.md, *Hub storage*.
//!
//! The kit word carries the snapshot's state in bits the kit leaves free (its high limb ends at
//! bit 202): the **flattening epoch** it was computed under (D-169), which is the registry's inputs
//! version at bits 208–239 (`Registry.bundle`, `models::versions`) and `Hub`'s rules epoch at
//! bits 241–249; the stale mark at bit 240; `LIVE` at 250 (set by the packers). A slot never
//! written is 0: no snapshot. `Hub.enter` refuses a missing one, and a stale one: marked, of
//! another flattening epoch (a record the flattening reads changed, or the flattening's class), or
//! of another level than the adventurer's (D-168 2).

use grimworld_logic::packing::{P64, byte_at, split};
use grimworld_logic::snapshot::SnapshotWords;

/// `2^208`: the flattening epoch's unit in the kit word (bits 208–249).
const EPOCH_UNIT: felt252 = 0x10000000000000000000000000000000000000000000000000000;
/// `2^80`: the kit word's high limb above it, `LIVE` removed, is the state (the inputs version,
/// the stale mark, the rules epoch).
const STATE_SHIFT: u128 = 0x100000000000000000000;
/// `2^33`: the rules epoch's unit in the flattening epoch (bit 241 of the kit word, above the
/// inputs version's 32 bits and the stale mark's one).
const RULES_UNIT: u64 = 0x200000000;
/// The rules epoch's values: 9 bits (241–249), 0 to 511, then 0 again (`RulesEpochTrait::next`).
pub const RULES_EPOCHS: u16 = 512;

/// The kit word of a snapshot marked stale (bit 240, `LIVE`): an entrypoint that changes an input
/// of the flattening and does not recompute writes it, in one write, without reading (D-168 2).
/// No flattening epoch has bit 32 set, so a marked word never reads fresh.
pub const STALE_MARK: felt252 = 0x401000000000000000000000000000000000000000000000000000000000000;

pub mod errors {
    /// No snapshot: `set_build` was never called for the adventurer.
    pub const MISSING: felt252 = 'snapshot: missing';
    /// The snapshot is marked stale, of another flattening epoch, or of another level: the client
    /// sends `set_build` first (D-168 2, D-169).
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
    /// The snapshot `set_build` stores: the flattening's three packed words, the kit sealed with
    /// the flattening `epoch` it was computed under.
    #[inline(always)]
    fn new(stats: felt252, bar: felt252, kit: felt252, epoch: u64) -> StoredSnapshot {
        StoredSnapshot { stats, bar, kit: Self::seal(kit, epoch) }
    }

    /// The flattening epoch (D-169): the registry's `inputs` version (`Registry.bundle`) and
    /// `Hub`'s `rules` epoch (`models::rules_epoch`, below `RULES_EPOCHS`), as the kit word holds
    /// them from bit 208.
    #[inline(always)]
    fn epoch(inputs: u32, rules: u16) -> u64 {
        inputs.into() + rules.into() * RULES_UNIT
    }

    /// What `Instances.create` receives of a snapshot `StoredSnapshotAssert::assert_fresh`
    /// accepted at `epoch`: the three words as packed, and the belt's counts.
    #[inline(always)]
    fn words(self: @StoredSnapshot, epoch: u64, belt_counts: [u8; 4]) -> SnapshotWords {
        SnapshotWords {
            stats: *self.stats, bar: *self.bar, kit: Self::kit(*self.kit, epoch), belt_counts,
        }
    }

    /// The stored kit word: the packed kit (`LIVE` set) and the flattening `epoch` it was computed
    /// under.
    #[inline(always)]
    fn seal(kit: felt252, epoch: u64) -> felt252 {
        kit + epoch.into() * EPOCH_UNIT
    }

    /// The packed kit of a stored kit word `StoredSnapshotAssert::assert_fresh` accepted.
    #[inline(always)]
    fn kit(word: felt252, epoch: u64) -> felt252 {
        word - epoch.into() * EPOCH_UNIT
    }
}

#[generate_trait]
pub impl StoredSnapshotAssert of StoredSnapshotAssertTrait {
    /// The stored kit word is a snapshot (`MISSING`) of the flattening `epoch`, not marked stale
    /// (`STALE`): the inputs version, the mark and the rules epoch compared at once. One split and
    /// one division.
    fn assert_fresh(word: felt252, epoch: u64) {
        assert(word != 0, errors::MISSING);
        let (_, high) = split(word);
        assert(high / STATE_SHIFT == epoch.into(), errors::STALE);
    }

    /// The stored stats word was computed at the adventurer's `level` (`MemberStats.level`, bits
    /// 64–71): a level up (GLD-01) leaves the snapshot stale without marking it.
    #[inline(always)]
    fn assert_level(stats: felt252, level: u8) {
        let (low, _) = split(stats);
        assert(byte_at(low, P64) == level, errors::STALE);
    }
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::LIVE;
    use grimworld_logic::snapshot::{MemberKit, MemberStats, pack_kit, pack_stats, unpack_kit};
    use super::{RULES_EPOCHS, STALE_MARK, StoredSnapshotAssert, StoredSnapshotTrait, errors};

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

    // Sealed with the widest kit and flattening epoch (the inputs version and the rules epoch at
    // their highest), the kit comes back whole, and the state reads.
    #[test]
    #[available_gas(l2_gas: 296510)] // ceil(1.05 × 282390 measured)
    fn test_seal_round_trip() {
        let epoch = StoredSnapshotTrait::epoch(0xffffffff, RULES_EPOCHS - 1);
        let word = StoredSnapshotTrait::seal(kit(), epoch);
        StoredSnapshotAssert::assert_fresh(word, epoch);
        let back = StoredSnapshotTrait::kit(word, epoch);
        assert(back == kit(), 'kit');
        assert(unpack_kit(back) == unpack_kit(kit()), 'unpacked');
        let word = StoredSnapshotTrait::seal(kit(), 0);
        StoredSnapshotAssert::assert_fresh(word, 0);
    }

    // The flattening epoch's layout: the inputs version at bits 208–239, the rules epoch at
    // 241–249, the mark's bit 240 between them, and nothing at 250 (`LIVE`) or above.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_epoch_bits() {
        let unit: felt252 = 0x10000000000000000000000000000000000000000000000000000; // 2^208
        let inputs = StoredSnapshotTrait::seal(0, StoredSnapshotTrait::epoch(0xffffffff, 0));
        assert(inputs == 0xffffffff * unit, 'inputs at 208-239');
        let rules = StoredSnapshotTrait::seal(0, StoredSnapshotTrait::epoch(0, RULES_EPOCHS - 1));
        assert(rules == 0x1ff * 0x200000000 * unit, 'rules at 241-249');
        // The widest epoch and the mark fill bits 208–249 exactly: 2^250 - 2^208.
        let widest = StoredSnapshotTrait::epoch(0xffffffff, RULES_EPOCHS - 1);
        assert(
            StoredSnapshotTrait::seal(0, widest) + (STALE_MARK - LIVE) == LIVE - unit, 'below LIVE',
        );
    }

    // A snapshot of another rules epoch, of the same inputs version, is stale.
    #[test]
    #[available_gas(l2_gas: 67011)] // ceil(1.05 × 63820 measured)
    #[should_panic(expected: 'snapshot: stale')]
    fn test_other_rules_refused() {
        let word = StoredSnapshotTrait::seal(kit(), StoredSnapshotTrait::epoch(4, 1));
        StoredSnapshotAssert::assert_fresh(word, StoredSnapshotTrait::epoch(4, 1));
        StoredSnapshotAssert::assert_fresh(word, StoredSnapshotTrait::epoch(4, 2));
    }

    // The mark is stale whatever the epoch, the widest included.
    #[test]
    #[available_gas(l2_gas: 12569)] // ceil(1.05 × 11970 measured)
    #[should_panic(expected: 'snapshot: stale')]
    fn test_stale_mark_refused_at_any_epoch() {
        StoredSnapshotAssert::assert_fresh(
            STALE_MARK, StoredSnapshotTrait::epoch(0xffffffff, RULES_EPOCHS - 1),
        );
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'snapshot: missing')]
    fn test_missing_refused() {
        StoredSnapshotAssert::assert_fresh(0, 0);
    }

    #[test]
    #[available_gas(l2_gas: 12464)] // ceil(1.05 × 11870 measured)
    #[should_panic(expected: 'snapshot: stale')]
    fn test_stale_mark_refused() {
        StoredSnapshotAssert::assert_fresh(STALE_MARK, 0);
    }

    #[test]
    #[available_gas(l2_gas: 62318)] // ceil(1.05 × 59350 measured)
    #[should_panic(expected: 'snapshot: stale')]
    fn test_other_version_refused() {
        StoredSnapshotAssert::assert_fresh(StoredSnapshotTrait::seal(kit(), 4), 5);
    }

    #[test]
    #[available_gas(l2_gas: 119763)] // ceil(1.05 × 114060 measured)
    #[should_panic(expected: 'snapshot: stale')]
    fn test_other_level_refused() {
        let stats = pack_stats(MemberStats { level: 3, ..Default::default() });
        StoredSnapshotAssert::assert_level(stats, 3);
        StoredSnapshotAssert::assert_level(stats, 4);
    }

    // The stale mark is `LIVE` and bit 240 alone.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_stale_mark_bits() {
        assert(
            STALE_MARK == LIVE + 0x1000000000000000000000000000000000000000000000000000000000000,
            'mark',
        );
        assert(errors::STALE != errors::MISSING, 'errors');
    }
}
