//! Pure logic of Grim World: state in, state out, no storage and no contract (ADR-0007, *The
//! layering is kept*). The rules of a tick live here, so that tests need no deployment and the
//! client can mirror them (SPK-4). No game code yet.

/// The rules of a tick: state in, state out.
pub mod tick;
