// ADR-0002, rule 2: one domain purpose per use of Fate, all distinct; `derive` gives a distinct
// value per domain and per index, and is `poseidon(word, domain, index)` (the plain oracle).
use core::poseidon::poseidon_hash_span;
use grimworld_logic::fate::{LOOT, PURPOSES, derive, domain};

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

// The eight purposes are distinct, and so are their domains for one subject and counter.
#[test]
#[available_gas(l2_gas: 379645)] // ceil(1.05 × 361566 measured)
fn test_purposes_distinct() {
    let purposes = PURPOSES.span();
    assert(purposes.len() == 8, 'eight purposes');
    assert(all_distinct(purposes), 'purposes distinct');
    let mut domains = array![];
    for purpose in purposes {
        domains.append(domain(0x100000001, 7, *purpose));
    }
    assert(all_distinct(domains.span()), 'domains distinct');
}

// A domain binds its subject, its counter and their order: the same purpose in another instance,
// at another sequence, or with subject and counter swapped, is another domain.
#[test]
#[available_gas(l2_gas: 95592)] // ceil(1.05 × 91040 measured)
fn test_domain_binds_subject_and_counter() {
    let base = domain(1, 2, LOOT);
    assert(base == poseidon_hash_span(array![1, 2, LOOT].span()), 'poseidon(s, c, p)');
    assert(
        all_distinct(
            array![base, domain(3, 2, LOOT), domain(1, 3, LOOT), domain(2, 1, LOOT)].span(),
        ),
        'subject, counter, order',
    );
}

// derive is the plain poseidon of its three inputs.
#[test]
#[available_gas(l2_gas: 51314)] // ceil(1.05 × 48870 measured)
fn test_derive_oracle() {
    let d = domain(1, 0, LOOT);
    assert(derive(0xabc, d, 0) == poseidon_hash_span(array![0xabc, d, 0].span()), 'index 0');
    assert(derive(0xabc, d, 9) == poseidon_hash_span(array![0xabc, d, 9].span()), 'index 9');
}

// One word, every purpose's domain, indices 0 to 3: 32 values, all distinct, and none equal to
// the word itself or to a domain.
#[test]
#[available_gas(l2_gas: 3483995)] // ceil(1.05 × 3318090 measured)
fn test_derive_distinct_per_domain_and_index() {
    let word = 0x5eed;
    let mut values = array![word];
    for purpose in PURPOSES.span() {
        let d = domain(0x100000001, 3, *purpose);
        values.append(d);
        for index in 0..4_u32 {
            values.append(derive(word, d, index));
        }
    }
    assert(values.len() == 41, 'forty-one');
    assert(all_distinct(values.span()), 'all distinct');
}

// For any word and index, the next index and another word give other values; the same inputs
// give the same value (determinism).
#[test]
#[fuzzer(runs: 64)]
#[available_gas(l2_gas: 1099613)] // ceil(1.05 × 1047250 measured)
fn test_derive_fuzz(word: felt252, index: u32) {
    let d = domain(1, 0, LOOT);
    let value = derive(word, d, index);
    assert(value == derive(word, d, index), 'deterministic');
    let next = if index == 0xffffffff {
        0
    } else {
        index + 1
    };
    assert(value != derive(word, d, next), 'index');
    assert(value != derive(word + 1, d, index), 'word');
}
