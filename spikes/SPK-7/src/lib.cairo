//! SPK-7: the chunked map of ADR-0006 as decided on 2026-09-28 (D-120), measured. Throwaway.
//! Functions are named after the needs of the map library they prototype (docs/needs/hexmap.md):
//! `generate_chunk` (N-1, N-2), `assemble_window` (N-3), `line_of_sight` (N-5), `shared_flood`
//! (N-8).

pub mod boards;
pub mod chunk;
pub mod contract;
pub mod fixtures;
pub mod flood;
pub mod sight;
pub mod tables;
pub mod tick;
pub mod vectors;
pub mod window;
