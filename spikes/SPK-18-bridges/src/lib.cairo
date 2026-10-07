//! SPK-18: bridges on two levels (ENG-08b, D-217). The level of a position kept in the words that
//! hold the position today, and the movement check with a level against the check of one level
//! that ENG-07 builds (D-225). A spike: nothing here is production code; ENG-07 (movement) and
//! ENG-09 (the authored zone's reveal) build from `docs/architecture/ADR-0008-bridges.md`.

pub mod level;
pub mod movement;
