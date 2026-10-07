//! SPK-17: a dungeon floor's outline fixed at entry (ENG-10a, D-208): the outline drawn at
//! `create`, ENG-05's engine changed to read it, the zero-residue test ENG-10b must pass, and the
//! costs against ENG-05's. A spike: nothing here is production code; ENG-10b builds from it.

pub mod engine;
pub mod library;
pub mod outline;
