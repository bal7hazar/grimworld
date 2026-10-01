//! SPK-15 (D-171): the tick's cost levers, measured before CBT-05. A spike: nothing here merges into
//! the contracts. The benchmarks are in `tests/`, as pairs of tests that differ by the measured call
//! alone (CBT-02d's lesson: a call measured with `get_available_gas` misses its straight-line part).
//!
//! - `cbt04`, `cbt03a`: CBT-04's and CBT-03a's functions, copied from their branches (not merged);
//! - `words`: lever 1, the frozen goblins kept as their words until a step or a hook touches them;
//! - `application`: lever 2, a condition's application on the member and the goblin, taken apart,
//!   and its alternatives;
//! - `executor`: lever 3, what CBT-05's executor adds around a hit and an application.

pub mod application;
pub mod cbt03a;
pub mod cbt04;
pub mod executor;
pub mod words;
