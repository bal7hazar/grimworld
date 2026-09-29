//! Storage records of the persistent domain: layout, packing, invariants (ENG-01). None holds a
//! field of the ephemeral domain: an adventurer references its instance by id only.

/// Accounts, and the owner keys of balances.
pub mod account;
/// Adventurers.
pub mod adventurer;
/// Equipment entities, grimoires, gold, Rift boards.
pub mod item;
/// Lots and trades.
pub mod market;
