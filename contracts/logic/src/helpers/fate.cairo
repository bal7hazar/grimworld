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


#[generate_trait]
pub impl FateImpl of FateTrait {
    /// The domain of one draw: `poseidon(subject, counter, purpose)`.
    #[inline]
    fn domain(subject: felt252, counter: felt252, purpose: felt252) -> felt252 {
        poseidon_hash_span([subject, counter, purpose].span())
    }

    /// The value at `index` of a decision drawn under `domain`: `poseidon(word, domain, index)`.
    #[inline]
    fn derive(word: felt252, domain: felt252, index: u32) -> felt252 {
        poseidon_hash_span([word, domain, index.into()].span())
    }
}

/// An instance's entropy (ADR-0006 option C, ENG-01 §3.2): the entry draw plus one hash per
/// irreversible fact, a sum, so **a multiset** of facts: two facts fed in either order give the
/// same value (the order of two actions that reach the same state is no free choice), and the same
/// fact fed twice counts twice, so every feeder makes its facts unique (a kill names its goblin, a
/// chest its tile; audit #348, note 5). Every feeder (a kill, health lost, a consumable, loot, a
/// chest, a vein, in their lots) calls `feed` with a fact whose first felt is its own tag, so that
/// two kinds of fact never hash alike. **A reveal feeds nothing** (audit #348, major 1): the
/// chunks' words read the entropy, so a fed reveal would make the order of moves a free choice over
/// every later chunk.
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
        FateTrait::derive(entropy, FateTrait::domain(instance_id, chunk.into(), REVEAL), 0)
    }

    /// The seed of a zone's quota hosts (D-208, `PlacementTrait::hosts`), drawn once at `create`:
    /// `derive(entropy, domain(instance_id, 225, REVEAL), 0)`, the word of chunk 225, which no
    /// chunk has (chunks are 0–224).
    #[inline]
    fn hosts(entropy: felt252, instance_id: felt252) -> felt252 {
        Self::word(entropy, instance_id, 225)
    }

    /// The seed of an authored zone's quota hosts among the author's candidates (D-215 ruling 3,
    /// ENG-08's Q6, built by ENG-09), drawn once at `create`: `derive(entropy,
    /// domain(instance_id, 226, REVEAL), 0)`, the word of no chunk (0–224), nor of a generated
    /// zone's hosts (225).
    #[inline]
    fn authored_hosts(entropy: felt252, instance_id: felt252) -> felt252 {
        FateTrait::derive(entropy, FateTrait::domain(instance_id, 226, REVEAL), 0)
    }

    /// The word of an authored chunk's spawn points (D-215 ruling 4, ENG-08's Q6): their level
    /// and counts, `derive(entropy, domain(instance_id, 256 + chunk, REVEAL), 0)`, keyed by the
    /// chunk alone, so that no order of reveals changes it; counters 256–480 are no chunk's word,
    /// nor the hosts' (225, 226), nor the outline's (227).
    #[inline]
    fn spawns(entropy: felt252, instance_id: felt252, chunk: u8) -> felt252 {
        FateTrait::derive(entropy, FateTrait::domain(instance_id, 256 + chunk.into(), REVEAL), 0)
    }

    /// The seed of a dungeon floor's outline (ENG-10a, D-223, `reveal::outline::OutlineTrait`),
    /// drawn once at `create`: `derive(entropy, domain(instance_id, 227, REVEAL), 0)`, the word of
    /// no chunk (0–224), nor of the hosts (225), nor of an authored zone's hosts (226, SPK-16).
    /// A seam's openings are drawn from it too (D-224).
    #[inline]
    fn outline(entropy: felt252, instance_id: felt252) -> felt252 {
        Self::word(entropy, instance_id, 227)
    }
}

/// The vector table for the TypeScript mirror (VEC-01) is printed by `tests::test_vectors` and kept
/// in `contracts/logic/vectors/fate.jsonl` (`vectors/README.md`).
#[cfg(test)]
mod tests {
    use core::poseidon::poseidon_hash_span;
    use crate::helpers::packing::LIVE;
    use super::{FateTrait, LOOT, PURPOSES};

    #[generate_trait]
    impl FixtureImpl of Fixture {
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
            println!(
                "{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}",
                id,
                name,
                Self::hex(case),
                Self::hex(ok),
            );
            digest.append(poseidon_hash_span(case));
            digest.append(poseidon_hash_span(ok));
            id += 1;
        }

        fn all_distinct(values: Span<felt252>) -> bool {
            let n = values.len();
            for i in 0..n {
                for j in (i + 1)..n {
                    if *values.at(i) == *values.at(j) {
                        return false;
                    }
                }
            }
            true
        }
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
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 464531905)] // ceil(1.05 × 442411338 measured)
    fn test_vectors() {
        let mut digest: Array<felt252> = array![];
        let mut id: u32 = 0;
        // The purposes, by index.
        let mut i: felt252 = 0;
        for purpose in PURPOSES.span() {
            Fixture::emit(ref digest, ref id, "purpose", [i].span(), [*purpose].span());
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
                let ok = FateTrait::domain(subject, counter, *purpose);
                Fixture::emit(
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
                let ok = FateTrait::domain(*subject, *counter, entry);
                Fixture::emit(
                    ref digest, ref id, "domain", [*subject, *counter, entry].span(), [ok].span(),
                );
            }
        }
        // `derive`: words, domains and indices at their edges.
        let words: [felt252; 5] = [0, 1, 0x123456789, TWO_POW_128, MAX];
        let domains: [felt252; 3] = [0, FateTrait::domain(1, 0, entry), MAX];
        let indices: [u32; 6] = [0, 1, 7, 255, 65535, 0xffffffff];
        for word in words.span() {
            for dom in domains.span() {
                for index in indices.span() {
                    let ok = FateTrait::derive(*word, *dom, *index);
                    let index_felt: felt252 = (*index).into();
                    Fixture::emit(
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

    // ADR-0002, rule 2: one domain purpose per use of Fate, all distinct; `derive` gives a distinct
    // value per domain and per index, and is `poseidon(word, domain, index)` (the plain oracle).

    // The nine purposes (ENG-05 added the reveal's) are distinct, and so are their domains for one
    // subject and counter.
    #[test]
    // gas: raised, ENG-05: the reveal purpose (one more domain)
    #[available_gas(l2_gas: 454932)] // ceil(1.05 × 433268 measured)
    fn test_purposes_distinct() {
        let purposes = PURPOSES.span();
        assert(purposes.len() == 9, 'nine purposes');
        assert(Fixture::all_distinct(purposes), 'purposes distinct');
        let mut domains = array![];
        for purpose in purposes {
            domains.append(FateTrait::domain(0x100000001, 7, *purpose));
        }
        assert(Fixture::all_distinct(domains.span()), 'domains distinct');
    }

    // A domain binds its subject, its counter and their order: the same purpose in another
    // instance, at another sequence, or with subject and counter swapped, is another domain.
    #[test]
    #[available_gas(l2_gas: 95592)] // ceil(1.05 × 91040 measured)
    fn test_domain_binds_subject_and_counter() {
        let base = FateTrait::domain(1, 2, LOOT);
        assert(base == poseidon_hash_span(array![1, 2, LOOT].span()), 'poseidon(s, c, p)');
        assert(
            Fixture::all_distinct(
                array![
                    base, FateTrait::domain(3, 2, LOOT), FateTrait::domain(1, 3, LOOT),
                    FateTrait::domain(2, 1, LOOT),
                ]
                    .span(),
            ),
            'subject, counter, order',
        );
    }

    // derive is the plain poseidon of its three inputs.
    #[test]
    #[available_gas(l2_gas: 51314)] // ceil(1.05 × 48870 measured)
    fn test_derive_oracle() {
        let d = FateTrait::domain(1, 0, LOOT);
        assert(
            FateTrait::derive(0xabc, d, 0) == poseidon_hash_span(array![0xabc, d, 0].span()),
            'index 0',
        );
        assert(
            FateTrait::derive(0xabc, d, 9) == poseidon_hash_span(array![0xabc, d, 9].span()),
            'index 9',
        );
    }

    // One word, every purpose's domain, indices 0 to 3: 36 values, all distinct, and none equal to
    // the word itself or to a domain.
    #[test]
    // gas: raised, ENG-05: the reveal purpose (one more domain)
    #[available_gas(l2_gas: 4295970)] // ceil(1.05 × 4091400 measured)
    fn test_derive_distinct_per_domain_and_index() {
        let word = 0x5eed;
        let mut values = array![word];
        for purpose in PURPOSES.span() {
            let d = FateTrait::domain(0x100000001, 3, *purpose);
            values.append(d);
            for index in 0..4_u32 {
                values.append(FateTrait::derive(word, d, index));
            }
        }
        assert(values.len() == 46, 'forty-six');
        assert(Fixture::all_distinct(values.span()), 'all distinct');
    }

    // For any word and index, the next index and another word give other values; the same inputs
    // give the same value (determinism).
    #[test]
    #[fuzzer(runs: 64)]
    #[available_gas(l2_gas: 1099613)] // ceil(1.05 × 1047250 measured)
    fn test_derive_fuzz(word: felt252, index: u32) {
        let d = FateTrait::domain(1, 0, LOOT);
        let value = FateTrait::derive(word, d, index);
        assert(value == FateTrait::derive(word, d, index), 'deterministic');
        let next = if index == 0xffffffff {
            0
        } else {
            index + 1
        };
        assert(value != FateTrait::derive(word, d, next), 'index');
        assert(value != FateTrait::derive(word + 1, d, index), 'word');
    }
}
