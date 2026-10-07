//! SPK-16: an authored zone's on-chain format, its checks, its draws at entry and its costs
//! (ENG-08, D-214, D-215). A spike: nothing here is production code; ENG-09 builds from it.

pub mod authored;
pub mod checks;
pub mod library;
pub mod records;
pub mod zone_chunk;
