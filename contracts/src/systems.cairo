//! Thin contracts: entrypoints, access control, nothing else. One folder per domain.

/// Systems of the persistent domain (namespace `grimworld`).
pub mod persistent;
/// Systems of the ephemeral domain (namespace `grimworld_instance`).
pub mod ephemeral;
