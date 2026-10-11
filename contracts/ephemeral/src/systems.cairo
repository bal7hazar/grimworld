//! Contracts of the ephemeral domain: entrypoints, access control, nothing else.

/// `GoblinsLibrary`: the goblin loader of `play`'s content rounds and of `instance_state`, called
/// with `library_call` in `Instances`' context (FIX-02b, D-269).
pub mod goblins;
/// `Instances`: instances, chunks, goblins, members, and the entrypoints of play.
pub mod instances;
/// `PlayLibrary`: `play`'s body, called by `Instances` with `library_call` in its own context
/// (ENG-07, D-234, D-235).
pub mod play;
