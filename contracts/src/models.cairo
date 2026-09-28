//! State and invariants (asserts) per model. One folder per domain; no model mixes fields of both.

/// Models of the ephemeral domain (namespace `grimworld_instance`): instance state.
pub mod ephemeral;
/// Models of the persistent domain (namespace `grimworld`): adventurer, inventory, progress.
pub mod persistent;
