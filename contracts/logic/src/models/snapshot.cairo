//! `Snapshot`, the snapshot an instance takes of an adventurer at entry (ADR-0001: the ephemeral
//! domain never reads persistent state during play): the member's three words
//! (`models::member_stats`, `models::member_bar`, `models::member_kit`) and the belt's counts. The
//! persistent contract builds them (`models::build`, the flattening), the ephemeral contract stores
//! them in the member's record, packed (`models::snapshot_words`); both use these layouts, which is
//! why they live in the shared package. Bit offsets are in docs/architecture/ENG-01-interfaces.md,
//! *Member*.

use crate::models::member_bar::{MemberBar, MemberBarTrait};
use crate::models::member_kit::{MemberKit, MemberKitTrait};
use crate::models::member_stats::{MemberStats, MemberStatsTrait};
use crate::models::snapshot_words::SnapshotWords;
use crate::types::profession::ProfessionTrait;

/// What the persistent contract hands to the ephemeral one at entry (the snapshot).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Snapshot {
    pub stats: MemberStats,
    pub bar: MemberBar,
    pub kit: MemberKit,
    /// Potions carried in each belt slot: debited from the pack in the entry transaction (the
    /// reserve), credited back unused by the closing report (`Results.belt`).
    pub belt_counts: [u8; 4],
}

/// Health at level 1, and what each level above adds (design/03, *Base stats*).
pub const BASE_HEALTH: u16 = 100;
pub const HEALTH_PER_LEVEL: u16 = 20;
/// `MemberStats.health_regen` is the pips plus 10: no regeneration nor degeneration.
pub const NO_HEALTH_REGEN: u8 = 10;

#[generate_trait]
pub impl SnapshotImpl of SnapshotTrait {
    /// The snapshot of an adventurer without equipment, from its level and primary profession
    /// (ENG-06): health, energy, regeneration and armor (design/03); its bar, elite slot and belt
    /// copied; what equipment, attribute ranks and set bonuses add, 0. The tests' snapshot:
    /// `Hub.enter` copies the one `set_build` stored (D-168).
    fn new(
        level: u8,
        profession: u8,
        skills: [u16; 8],
        elite_slot: u8,
        belt: [u32; 4],
        belt_counts: [u8; 4],
    ) -> Snapshot {
        let stats = MemberStats {
            max_health: BASE_HEALTH + HEALTH_PER_LEVEL * (level.into() - 1),
            max_energy: ProfessionTrait::energy(profession),
            energy_regen: ProfessionTrait::energy_regen(profession),
            health_regen: NO_HEALTH_REGEN,
            level,
            profession,
            ..Default::default(),
        };
        // The class's armor is the unguarded armor, in `MemberBar` since FX-24 (design/19 §7.2).
        let armor: u8 = ProfessionTrait::armor(profession);
        Snapshot {
            stats,
            bar: MemberBar {
                skills,
                elite_slot,
                damage: [0; 6],
                penetration: [0; 3],
                quick_cast: [Default::default(); 2],
                armor: armor.into(),
            },
            kit: MemberKit { belt, ..Default::default() },
            belt_counts,
        }
    }

    /// The snapshot as `Instances.create` receives it: its three words packed.
    fn words(self: @Snapshot) -> SnapshotWords {
        SnapshotWords {
            stats: MemberStatsTrait::pack(*self.stats),
            bar: MemberBarTrait::pack(*self.bar),
            kit: MemberKitTrait::pack(*self.kit),
            belt_counts: *self.belt_counts,
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::models::member_bar::MemberBarTrait;
    use crate::models::member_kit::MemberKitTrait;
    use crate::models::member_stats::MemberStatsTrait;
    use super::SnapshotTrait;

    // `SnapshotTrait::words` packs the three words of a snapshot and keeps the belt's counts.
    #[test]
    #[available_gas(l2_gas: 475934)] // ceil(1.05 × 453270 measured)
    fn test_snapshot_words() {
        let snapshot = SnapshotTrait::new(
            3, 1, [1, 2, 0, 0, 0, 0, 0, 0], 255, [7; 4], [1, 2, 3, 4],
        );
        let words = snapshot.words();
        assert(MemberStatsTrait::unpack(words.stats) == snapshot.stats, 'stats');
        assert(MemberBarTrait::unpack(words.bar) == snapshot.bar, 'bar');
        assert(MemberKitTrait::unpack(words.kit) == snapshot.kit, 'kit');
        assert(words.belt_counts == [1, 2, 3, 4], 'counts');
    }
}
