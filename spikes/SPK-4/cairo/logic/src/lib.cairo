//! SPK-4: a representative piece of the game's logic, written once as a pure library (state in,
//! state out, no storage: ADR-0007 *Pure logic*), to measure how the client can reproduce it
//! exactly: a TypeScript mirror checked against vectors (option a) or this very code in a Cairo VM
//! compiled to WebAssembly (option b). Throwaway: the real core is CLI-02 and ENG-02.

pub mod board;
pub mod damage;
pub mod exec;
pub mod table;

#[cfg(test)]
mod tests;
