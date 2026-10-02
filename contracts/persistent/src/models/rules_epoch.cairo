//! `Hub`'s rules epoch (D-169, CBT-02f): how many times `set_contracts` changed the configuration
//! the snapshot's flattening depends on, the `FlattenLibrary` class or the registry, modulo
//! `RULES_EPOCHS`. One slot (`Hub.rules_epoch`, ENG-01 §3.3), the value as a felt, 0 at
//! deployment. A stored snapshot carries the epoch it was flattened under in its kit word
//! (`models::snapshot`, bits 241–249), and `enter` refuses another.
//!
//! Its own model rather than a field of a configuration model: the other configuration of `Hub`
//! (the registry, `Instances`, `Market`, the randomness provider, the flattening's class) is one
//! full felt per slot, so a model holding them packs nothing, and its typed read would cost every
//! entrypoint that needs one address the reads of all of them.
//!
//! The wrap: 9 bits, 511 then 0. A snapshot left without `set_build` through exactly 512 changes
//! (and no change of an input) reads fresh again: an administrator-only path (ENG-01 §3.3).

use starknet::storage_access::StorePacking;
use starknet::{ClassHash, ContractAddress};
use super::snapshot::RULES_EPOCHS;

#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct RulesEpoch {
    /// 0 to `RULES_EPOCHS - 1`.
    pub value: u16,
}

#[generate_trait]
pub impl RulesEpochImpl of RulesEpochTrait {
    /// The epoch after a change of the flattening's configuration: one more, 511 wrapping to 0.
    #[inline(always)]
    fn next(self: RulesEpoch) -> RulesEpoch {
        RulesEpoch { value: (self.value + 1) % RULES_EPOCHS }
    }

    /// Whether `set_contracts` changes the configuration the flattening depends on: its class or
    /// the registry it reads (D-169).
    #[inline(always)]
    fn moves(
        flatten: ClassHash,
        stored_flatten: ClassHash,
        registry: ContractAddress,
        stored_registry: ContractAddress,
    ) -> bool {
        flatten != stored_flatten || registry != stored_registry
    }
}

pub impl RulesEpochStorePacking of StorePacking<RulesEpoch, felt252> {
    #[inline(always)]
    fn pack(value: RulesEpoch) -> felt252 {
        value.value.into()
    }
    #[inline(always)]
    fn unpack(value: felt252) -> RulesEpoch {
        RulesEpoch { value: value.try_into().unwrap() }
    }
}

#[cfg(test)]
mod tests {
    use starknet::storage_access::StorePacking;
    use super::super::snapshot::RULES_EPOCHS;
    use super::{RulesEpoch, RulesEpochTrait};

    // The epoch counts 0 to 511, then wraps to 0 (9 bits).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_rules_epoch_wraps() {
        assert(RulesEpoch { value: 0 }.next() == RulesEpoch { value: 1 }, '0 to 1');
        assert(RulesEpoch { value: 510 }.next() == RulesEpoch { value: 511 }, '510 to 511');
        assert(RulesEpoch { value: RULES_EPOCHS - 1 }.next() == RulesEpoch { value: 0 }, 'wraps');
    }

    // The slot holds the value as it is: the layout of a `u16` storage variable.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_rules_epoch_packing() {
        let widest = RulesEpoch { value: RULES_EPOCHS - 1 };
        assert(StorePacking::<RulesEpoch, felt252>::pack(widest) == 511, 'as a felt');
        assert(StorePacking::<RulesEpoch, felt252>::unpack(511) == widest, 'back');
        assert(StorePacking::<RulesEpoch, felt252>::unpack(0) == Default::default(), 'zero');
    }

    // A change of the class or of the registry moves it; the same two do not.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_rules_epoch_moves() {
        let (one, three) = (1_felt252.try_into().unwrap(), 3_felt252.try_into().unwrap());
        let (two, four) = (2_felt252.try_into().unwrap(), 4_felt252.try_into().unwrap());
        assert(!RulesEpochTrait::moves(one, one, two, two), 'the same');
        assert(RulesEpochTrait::moves(three, one, two, two), 'another class');
        assert(RulesEpochTrait::moves(one, one, four, two), 'another registry');
    }
}
