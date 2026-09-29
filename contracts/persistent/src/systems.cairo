//! Contracts of the persistent domain: entrypoints, access control, nothing else.

/// `TxHashFate`: the MVP's randomness provider, refused on mainnet.
pub mod fate;
/// `Hub`: accounts, adventurers, inventory, progress, services, results.
pub mod hub;
/// `Market`: the auction house and direct trades.
pub mod market;
/// `Registry`: content as data.
pub mod registry;
