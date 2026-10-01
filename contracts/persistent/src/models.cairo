//! Storage records of the persistent domain: layout, packing, invariants (ENG-01). None holds a
//! field of the ephemeral domain: an adventurer references its instance by id only.

/// Accounts, and the owner keys of balances.
pub mod account;
/// Adventurers.
pub mod adventurer;
/// Pages of balances: the pack's, the vault's, escrow's.
pub mod balance;
/// Equipment entities, grimoires, gold, Rift boards.
pub mod item;
/// Pages of seven `u32` lanes, and their stored word.
pub mod lanes;
/// Lots and trades.
pub mod market;
/// `Hub`'s rules epoch (D-169).
pub mod rules_epoch;
/// The snapshot stored with the adventurer (D-168).
pub mod snapshot;
/// The registry's content and inputs versions (D-141, D-169).
pub mod versions;
