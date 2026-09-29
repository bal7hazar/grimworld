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

/// Every purpose, for the test that they are distinct.
pub const PURPOSES: [felt252; 8] = [ENTRY, LOOT, CHEST, IDENTIFY, LIFT, BREW, HINT, RIFT_BOARD];

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
