//! SPK-12 (D-161 §3, D-172 §3): client-side proving against L2 batches. A spike: nothing here
//! merges into the contracts or the client.
//!
//! - `fixtures`: CBT-02's representative and worst states, copied from its benchmarks;
//! - `segment`: the proved program, a deterministic segment of ticks from stored words to stored
//!   words, with a binding header as its public output (slingfall's chunk binding), and the
//!   executable that prints a scenario's arguments.

pub mod fixtures;
pub mod segment;
