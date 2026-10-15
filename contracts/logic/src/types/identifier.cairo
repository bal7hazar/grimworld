//! Instance ids and entity ids (M-1, M-5): the type is `types::InstanceId`, the bounds of entity
//! ids `constants::{FIRST_GOBLIN, GOBLINS_STRIDE}`.

use crate::constants::{FIRST_GOBLIN, GOBLINS_STRIDE};
use crate::types::InstanceId;

const TWO_POW_32: u64 = 0x100000000;

/// An instance id, `slot × 2^32 + generation`, and its parts.
#[generate_trait]
pub impl InstanceIdImpl of InstanceIdTrait {
    fn new(slot: u32, generation: u32) -> InstanceId {
        slot.into() * TWO_POW_32 + generation.into()
    }

    /// `(slot, generation)` of an instance id.
    fn parts(id: InstanceId) -> (u32, u32) {
        let (slot, generation) = DivRem::div_rem(id, TWO_POW_32.try_into().unwrap());
        (slot.try_into().unwrap(), generation.try_into().unwrap())
    }
}

/// An entity id inside an instance: a goblin's, `FIRST_GOBLIN + GOBLINS_STRIDE × chunk + k`.
#[generate_trait]
pub impl EntityImpl of EntityTrait {
    fn goblin(chunk: u8, k: u8) -> u16 {
        FIRST_GOBLIN + GOBLINS_STRIDE * chunk.into() + k.into()
    }
}

#[cfg(test)]
mod tests {
    use super::{EntityTrait, InstanceIdTrait};

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_identifiers() {
        let id = InstanceIdTrait::new(7, 3);
        assert(id == 7 * 0x100000000 + 3, 'instance id');
        assert(InstanceIdTrait::parts(id) == (7, 3), 'parts');
        assert(EntityTrait::goblin(0, 0) == 8, 'first goblin');
        assert(EntityTrait::goblin(224, 9) == 8 + 16 * 224 + 9, 'last goblin');
    }
}
