//! `Stored<M>`: the word of a one-felt model `M` as stored, the type `Instances` declares its
//! storage with (ENG-R1b, ENG-R1a's note 4; `quiver_quest` 0.2.0 declares its storage with its
//! slot types the same way). A slot declared `Stored<M>` is the slot a `Map<_, M>` would be, at the
//! same address and in the same layout (a struct's members are consecutive slots under the
//! entry's address), so ENG-01's layout is unchanged. The store reads and writes it typed, with no
//! address arithmetic: the word itself where a view returns it as stored or a path writes a
//! constant word, the model through `M`'s packer where a path needs its fields. `M` is a phantom:
//! it names the layout of the word, so that a header's word is never written where a quota's is.

use starknet::storage_access::StorePacking;

/// The word of a model `M` as stored. A slot never written reads 0, where `M`'s packer would give
/// `LIVE` at least: the views return it as such (ENG-01 §4.1).
pub struct Stored<M> {
    pub word: felt252,
}

impl StoredCopy<M> of Copy<Stored<M>>;
impl StoredDrop<M> of Drop<Stored<M>>;

impl StoredPartialEq<M> of PartialEq<Stored<M>> {
    #[inline(always)]
    fn eq(lhs: @Stored<M>, rhs: @Stored<M>) -> bool {
        *lhs.word == *rhs.word
    }
}

impl StoredDebug<M> of core::fmt::Debug<Stored<M>> {
    fn fmt(self: @Stored<M>, ref f: core::fmt::Formatter) -> Result<(), core::fmt::Error> {
        core::fmt::Debug::fmt(self.word, ref f)
    }
}

/// One felt in storage, the word as it is: no packer runs on a read or a write.
pub impl StoredStorePacking<M> of StorePacking<Stored<M>, felt252> {
    #[inline(always)]
    fn pack(value: Stored<M>) -> felt252 {
        value.word
    }

    #[inline(always)]
    fn unpack(value: felt252) -> Stored<M> {
        Stored { word: value }
    }
}

#[generate_trait]
pub impl StoredImpl<M, +StorePacking<M, felt252>, +Drop<M>> of StoredTrait<M> {
    /// The word of `model`, through its packer.
    #[inline(always)]
    fn new(model: M) -> Stored<M> {
        Stored { word: StorePacking::pack(model) }
    }

    /// The model the word holds, through its packer.
    #[inline(always)]
    fn model(self: Stored<M>) -> M {
        StorePacking::unpack(self.word)
    }
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{Bitmap, LIVE};
    use starknet::storage_access::StorePacking;
    use super::{Stored, StoredTrait};

    // The word is the model's packed word, both ways; a word never written reads 0, not `LIVE`.
    #[test]
    #[available_gas(l2_gas: 100000)]
    fn test_stored_word_and_model() {
        let bits = Bitmap { bits: 0x5 };
        let stored: Stored<Bitmap> = StoredTrait::new(bits);
        assert(stored.word == StorePacking::pack(bits), 'the packed word');
        assert(stored.word == LIVE + 0x5, 'with LIVE');
        assert(stored.model() == bits, 'the model back');
        let blank: Stored<Bitmap> = StorePacking::unpack(0);
        assert(blank.word == 0, 'never written');
        assert(StorePacking::pack(blank) == 0, 'as stored');
    }
}
