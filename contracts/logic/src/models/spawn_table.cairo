//! `SPAWN_TABLE`: its constructor, its checks and its record (layout: `models::index::SpawnTable`).
//! A location's packs (design/18 *Features*): each of a chunk's two pack slots holds a pack with
//! probability `density / 256`, its template drawn by weight (`types::reveal`).

use crate::content::{Record, SPAWN_TABLE};
use crate::packing::{P16, P24, P48, P72, P8, P96, join, peel, split};
pub use super::index::{Spawn, SpawnTable};

/// Entries of a spawn table.
pub const COUNT: u8 = 7;

#[generate_trait]
pub impl SpawnTableImpl of SpawnTableTrait {
    fn new(spawns: [Spawn; 7], density: u8) -> SpawnTable {
        SpawnTable { spawns, density }
    }

    /// The sum of the weights (at most 7 × 255).
    fn weight(self: @SpawnTable) -> u16 {
        let mut total: u16 = 0;
        for spawn in self.spawns.span() {
            if *spawn.template != 0 {
                total += (*spawn.weight).into();
            }
        }
        total
    }

    /// The template at `draw`, below `weight()`: entries in order, each over its weight.
    fn pick(self: @SpawnTable, draw: u16) -> u16 {
        let mut left = draw;
        let mut template: u16 = 0;
        for spawn in self.spawns.span() {
            if template == 0 && *spawn.template != 0 {
                let weight: u16 = (*spawn.weight).into();
                if left < weight {
                    template = *spawn.template;
                } else {
                    left -= weight;
                }
            }
        }
        template
    }
}

/// Its bits in a record's limb, and back (the field order of the record's layout).
#[generate_trait]
pub impl SpawnBits of SpawnBitsTrait {
    #[inline(never)]
    fn bits(spawn: @Spawn) -> u128 {
        (*spawn.template).into() + (*spawn.weight).into() * P16
    }

    #[inline(never)]
    fn peel(ref rest: u128) -> Spawn {
        let template = peel(ref rest, P16.try_into().unwrap());
        let weight = peel(ref rest, P8.try_into().unwrap());
        Spawn { template: template.try_into().unwrap(), weight: weight.try_into().unwrap() }
    }
}

pub impl SpawnTableRecord of Record<SpawnTable> {
    const KIND: u8 = SPAWN_TABLE;

    fn pack(self: @SpawnTable) -> Span<felt252> {
        let [s0, s1, s2, s3, s4, s5, s6] = self.spawns;
        let low = SpawnBitsTrait::bits(s0) + SpawnBitsTrait::bits(s1) * P24 + SpawnBitsTrait::bits(s2) * P48 + SpawnBitsTrait::bits(s3) * P72 + SpawnBitsTrait::bits(s4) * P96;
        let high = SpawnBitsTrait::bits(s5) + SpawnBitsTrait::bits(s6) * P24 + (*self.density).into() * P48;
        array![join(low, high)].span()
    }

    fn unpack(parts: Span<felt252>) -> SpawnTable {
        let (mut low, mut high) = split(*parts[0]);
        let s0 = SpawnBitsTrait::peel(ref low);
        let s1 = SpawnBitsTrait::peel(ref low);
        let s2 = SpawnBitsTrait::peel(ref low);
        let s3 = SpawnBitsTrait::peel(ref low);
        let s4 = SpawnBitsTrait::peel(ref low);
        let s5 = SpawnBitsTrait::peel(ref high);
        let s6 = SpawnBitsTrait::peel(ref high);
        let density = peel(ref high, P8.try_into().unwrap());
        SpawnTable {
            spawns: [s0, s1, s2, s3, s4, s5, s6], density: density.try_into().unwrap(),
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::packing::LIVE;
    use super::{Spawn, SpawnTableRecord, SpawnTableTrait};

    #[test]
    #[available_gas(l2_gas: 136143)] // ceil(1.05 × 129660 measured)
    fn test_spawn_table_bits_and_round_trip() {
        let first = Spawn { template: 0xabcd, weight: 0x12 };
        let last = Spawn { template: 0x1234, weight: 0xff };
        let table = SpawnTableTrait::new(
            [first, Default::default(), Default::default(), Default::default(), Default::default(), Default::default(), last],
            0x80,
        );
        let parts = table.pack();
        let high: felt252 = (0x1234 + 0xff * 0x10000) * 0x1000000 + 0x80 * 0x1000000000000;
        assert(
            *parts[0] == 0xabcd + 0x12 * 0x10000 + high * 0x100000000000000000000000000000000 + LIVE,
            'bits',
        );
        assert(SpawnTableRecord::unpack(parts) == table, 'round trip');
    }

    #[test]
    #[available_gas(l2_gas: 87024)] // ceil(1.05 × 82880 measured)
    fn test_spawn_table_pick_by_weight() {
        let table = SpawnTableTrait::new(
            [
                Spawn { template: 3, weight: 2 }, Spawn { template: 0, weight: 9 },
                Spawn { template: 5, weight: 1 }, Default::default(), Default::default(),
                Default::default(), Default::default(),
            ],
            64,
        );
        assert(table.weight() == 3, 'weight skips empty entries');
        assert(table.pick(0) == 3, '0');
        assert(table.pick(1) == 3, '1');
        assert(table.pick(2) == 5, '2');
    }
}
