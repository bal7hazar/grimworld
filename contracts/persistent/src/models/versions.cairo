//! The registry's two versions (D-141, D-169), in one slot (`Registry.versions`, ENG-01 §3.5):
//! the **content version**, raised by every changed record, which a batch is computed and executed
//! under (E-5); and the **inputs version**, raised only by a changed record of a kind the
//! snapshot's flattening reads (`Inputs::includes`), which a stored snapshot is computed under
//! (`models::snapshot`). `Registry.bundle` returns both, read in one storage read; `set_record`
//! raises both in one write.
//!
//! Layout: the content version at bits 0–31, the inputs version at bits 32–63; no `LIVE`, a slot
//! never written reads both at 0 (deployment). Each refuses its overflow past `u32`, like the
//! content version alone did (4,294,967,295 changed records).

use grimworld_logic::packing::P32;
use starknet::storage_access::StorePacking;

#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Versions {
    /// Raised by every changed record (D-141).
    pub content: u32,
    /// Raised by a changed record of a kind the flattening reads (D-169).
    pub inputs: u32,
}

#[generate_trait]
pub impl VersionsImpl of VersionsTrait {
    /// The versions after a changed record: the content version raised, and the inputs version
    /// too when the record is an input of the flattening.
    #[inline(always)]
    fn raised(self: Versions, input: bool) -> Versions {
        let inputs = if input {
            self.inputs + 1
        } else {
            self.inputs
        };
        Versions { content: self.content + 1, inputs }
    }
}

pub impl VersionsStorePacking of StorePacking<Versions, felt252> {
    #[inline(always)]
    fn pack(value: Versions) -> felt252 {
        value.content.into() + value.inputs.into() * P32.into()
    }
    #[inline(always)]
    fn unpack(value: felt252) -> Versions {
        let wide: u64 = value.try_into().unwrap();
        let (inputs, content) = DivRem::div_rem(wide, 0x100000000);
        Versions { content: content.try_into().unwrap(), inputs: inputs.try_into().unwrap() }
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::{Versions, VersionsTrait};

    // Both fields at their widest come back whole; 0 is both at 0.
    #[test]
    #[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
    fn test_versions_round_trip() {
        let widest = Versions { content: 0xffffffff, inputs: 0xffffffff };
        assert(StorePacking::unpack(StorePacking::pack(widest)) == widest, 'widest');
        let v: Versions = StorePacking::unpack(0);
        assert(v == Default::default(), 'zero');
        let v = Versions { content: 7, inputs: 3 };
        assert(StorePacking::<Versions, felt252>::pack(v) == 7 + 3 * 0x100000000, 'layout');
    }

    // A changed record raises the content version; the inputs version only for an input.
    #[test]
    #[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
    fn test_versions_raised() {
        let v = Versions { content: 7, inputs: 3 };
        assert(v.raised(false) == Versions { content: 8, inputs: 3 }, 'not an input');
        assert(v.raised(true) == Versions { content: 8, inputs: 4 }, 'an input');
    }

    #[test]
    #[available_gas(l2_gas: 16086)] // ceil(1.05 × 15320 measured)
    #[should_panic]
    fn test_versions_inputs_overflow() {
        Versions { content: 0, inputs: 0xffffffff }.raised(true);
    }
}
