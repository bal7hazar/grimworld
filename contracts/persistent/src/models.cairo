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
/// Lots and trades.
pub mod market;
/// The snapshot stored with the adventurer (D-168).
pub mod snapshot;
