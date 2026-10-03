//! Values from a Fate word (ADR-0002, rule 2). A contract calls the provider's `fate(domain)` once
//! per decision it draws for, with a domain that names that decision, and derives every value it
//! needs from the one word: `derive(word, domain, index)`. A value is never used for two decisions.
//!
//! A domain is `poseidon(subject, counter, purpose)` (docs/architecture/ENG-01-interfaces.md §7):
//! in an instance `(instance_id, sequence, purpose)`; in the hub `(adventurer_id, counter,
//! purpose)`, or the account and the day for a Rift board. The purposes below are distinct: two
//! uses never share a domain, whatever their subject and counter, short of a Poseidon collision.

use core::poseidon::poseidon_hash_span;

/// The entry draw of a location: `create`, and `leave` through a gate to a location (design/02).
pub const ENTRY: felt252 = 'fate:entry';
/// What remains hold, a boss's drop included (`loot`, design/15, D-37, D-50).
pub const LOOT: felt252 = 'fate:loot';
/// A chest's content (`open`, design/18).
pub const CHEST: felt252 = 'fate:chest';
/// Identifying an item: its modifiers and value (`identify`, design/15).
pub const IDENTIFY: felt252 = 'fate:identify';
/// Lifting a modifier without a stillstone: whether the item is destroyed (`lift_modifier`,
/// design/15).
pub const LIFT: felt252 = 'fate:lift';
/// Brewing a pair not yet tried (`brew`, design/07).
pub const BREW: felt252 = 'fate:brew';
/// A hint of a book (`buy_hint`, design/07).
pub const HINT: felt252 = 'fate:hint';
/// The day's five Rift identities, by the first board action of the day (design/17, *On-chain*).
pub const RIFT_BOARD: felt252 = 'fate:rift-board';

/// A chunk's random word at its reveal (ENG-05; ADR-0006 option C, D-111): not a call to the
/// provider but `derive(entropy, domain(instance_id, chunk, REVEAL), 0)`, the entropy read at the
/// reveal (`EntropyTrait::word`).
pub const REVEAL: felt252 = 'fate:reveal';

/// Every purpose, for the test that they are distinct.
pub const PURPOSES: [felt252; 9] = [
    ENTRY, LOOT, CHEST, IDENTIFY, LIFT, BREW, HINT, RIFT_BOARD, REVEAL,
];


/// The domain of one draw: `poseidon(subject, counter, purpose)`.
#[inline]
pub fn domain(subject: felt252, counter: felt252, purpose: felt252) -> felt252 {
    poseidon_hash_span([subject, counter, purpose].span())
}

/// The value at `index` of a decision drawn under `domain`: `poseidon(word, domain, index)`.
#[inline]
pub fn derive(word: felt252, domain: felt252, index: u32) -> felt252 {
    poseidon_hash_span([word, domain, index.into()].span())
}

/// An instance's entropy (ADR-0006 option C, ENG-01 §3.2): the entry draw plus one hash per
/// irreversible fact, a sum, so **a multiset** of facts: two facts fed in either order give the same
/// value (the order of two actions that reach the same state is no free choice), and the same fact
/// fed twice counts twice, so every feeder makes its facts unique (a kill names its goblin, a chest
/// its tile; audit #348, note 5). Every feeder (a kill, health lost, a consumable, loot, a chest, a
/// vein, in their lots) calls `feed` with a fact whose first felt is its own tag, so that two kinds
/// of fact never hash alike. **A reveal feeds nothing** (audit #348, major 1): the chunks' words read
/// the entropy, so a fed reveal would make the order of moves a free choice over every later chunk.
#[generate_trait]
pub impl EntropyImpl of EntropyTrait {
    /// The entropy with one more fact: `entropy + poseidon(fact)`.
    #[inline]
    fn feed(entropy: felt252, fact: Span<felt252>) -> felt252 {
        entropy + poseidon_hash_span(fact)
    }

    /// The random word of chunk `chunk` of `instance_id`'s instance, from the entropy read at its
    /// reveal (ENG-05 Open question 2): `derive(entropy, domain(instance_id, chunk, REVEAL), 0)`.
    /// The chunk is the counter, never the sequence or the clock.
    #[inline]
    fn word(entropy: felt252, instance_id: felt252, chunk: u8) -> felt252 {
        derive(entropy, domain(instance_id, chunk.into(), REVEAL), 0)
    }
}

/// The vector table for the TypeScript mirror (VEC-01) is printed by `tests::test_vectors` and kept
/// in `contracts/logic/vectors/fate.jsonl` (`vectors/README.md`).
#[cfg(test)]
mod tests {
    use core::poseidon::poseidon_hash_span;
    use crate::packing::LIVE;
    use super::{PURPOSES, derive, domain};

    fn hex(felts: Span<felt252>) -> ByteArray {
        let mut out: ByteArray = "[";
        let mut first = true;
        for felt in felts {
            if !first {
                out.append(@",");
            }
            first = false;
            let wide: u256 = (*felt).into();
            out.append(@format!("\"0x{:x}\"", wide));
        }
        out.append(@"]");
        out
    }

    /// Prints one vector and adds it to the digest.
    fn emit(
        ref digest: Array<felt252>,
        ref id: u32,
        name: ByteArray,
        case: Span<felt252>,
        ok: Span<felt252>,
    ) {
        println!("{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}", id, name, hex(case), hex(ok));
        digest.append(poseidon_hash_span(case));
        digest.append(poseidon_hash_span(ok));
        id += 1;
    }

    // The last felt below the field's prime, `P - 1`.
    const MAX: felt252 = -1;
    const TWO_POW_32: felt252 = 0x100000000;
    const TWO_POW_64: felt252 = 0x10000000000000000;
    const TWO_POW_128: felt252 = 0x100000000000000000000000000000000;

    // The vector table, one JSON line per case (`{"id", "fn", "case", "ok"}`), and a digest of
    // every case and outcome: a change to a derivation or to the cases fails here until
    // `contracts/logic/vectors/fate.jsonl` is regenerated.
    #[test]
    #[available_gas(l2_gas: 447769148)] // ceil(1.05 × 426446807 measured)
    fn test_vectors() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        // The purposes, by index.
        let mut i: felt252 = 0;
        for purpose in PURPOSES.span() {
            emit(ref digest, ref id, "purpose", [i].span(), [*purpose].span());
            i += 1;
        }
        // `domain`: every purpose over a spread of subjects and counters.
        let pairs: [(felt252, felt252); 8] = [
            (0, 0), (1, 0), (0, 1), (MAX, MAX), (TWO_POW_128, TWO_POW_64), (0xabc, 255),
            (LIVE, TWO_POW_32), (2, 0xffffffff),
        ];
        for purpose in PURPOSES.span() {
            for pair in pairs.span() {
                let (subject, counter) = *pair;
                let ok = domain(subject, counter, *purpose);
                emit(
                    ref digest, ref id, "domain", [subject, counter, *purpose].span(), [ok].span(),
                );
            }
        }
        // `domain`: the grid of subjects and counters under one purpose.
        let subjects: [felt252; 8] = [0, 1, 2, 0xabc, TWO_POW_64, TWO_POW_128, LIVE, MAX];
        let counters: [felt252; 7] = [0, 1, 2, 255, TWO_POW_32, TWO_POW_64, MAX];
        let entry = *PURPOSES.span()[0];
        for subject in subjects.span() {
            for counter in counters.span() {
                let ok = domain(*subject, *counter, entry);
                emit(ref digest, ref id, "domain", [*subject, *counter, entry].span(), [ok].span());
            }
        }
        // `derive`: words, domains and indices at their edges.
        let words: [felt252; 5] = [0, 1, 0x123456789, TWO_POW_128, MAX];
        let domains: [felt252; 3] = [0, domain(1, 0, entry), MAX];
        let indices: [u32; 6] = [0, 1, 7, 255, 65535, 0xffffffff];
        for word in words.span() {
            for dom in domains.span() {
                for index in indices.span() {
                    let ok = derive(*word, *dom, *index);
                    let index_felt: felt252 = (*index).into();
                    emit(
                        ref digest, ref id, "derive", [*word, *dom, index_felt].span(), [ok].span(),
                    );
                }
            }
        }
        let digest = poseidon_hash_span(digest.span());
        println!("digest {}", digest);
        assert(digest == DIGEST, 'vectors moved: regenerate');
    }

    const DIGEST: felt252 =
        1839100577459864661906567117798787229400223419200535450393868919826041224050;
}
