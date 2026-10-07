//! Contracts of the ephemeral domain: entrypoints, access control, nothing else.

/// `Instances`: instances, chunks, goblins, members, and the entrypoints of play.
pub mod instances;
/// `PlayLibrary`: `play`'s body, called by `Instances` with `library_call` in its own context
/// (ENG-07, D-234, D-235).
pub mod play;
