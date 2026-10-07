//! SPK-18: bridges (ENG-08b). **Superseded by D-227** (the owner, 2026-10-07: bridges have one
//! level, a deck is walkable ground over water): this Cairo part is the two-level prototype of
//! D-217, kept as history with its measured figures (`pairs.txt`, README). Nothing builds on it;
//! ADR-0008's one-level rules need no code in play. What still serves is `reach.py` (P-1 with
//! decks walkable, R-37).
//!
//! What it measured: the level of a position kept in the words that hold the position today, and
//! the movement check with a level against the check of one level that ENG-07 builds (D-225).

pub mod level;
pub mod movement;
