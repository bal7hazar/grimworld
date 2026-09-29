//! Events of `Instances`, frozen like an API (ADR-0007, *Events are an interface*). The first key
//! is the selector of the event's name; a change is a new event name. The client reads them from
//! its own receipts (design/02, *Reconciling*); the indexer needs none of them (SPK-11).

use grimworld_logic::types::{InstanceId, Outcome, Refusal, Stop};

/// An instance was created, at sequence 0 (design/02: the client takes the new id from it).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct InstanceEntered {
    #[key]
    pub instance_id: InstanceId,
    pub adventurer_id: u32,
    pub location: u16,
    pub gate: u16,
}

/// The summary of a `play` (design/02).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct BatchPlayed {
    #[key]
    pub instance_id: InstanceId,
    pub adventurer_id: u32,
    /// The sequence the batch was played from.
    pub from: u32,
    /// Actions that ran, 0 to 10.
    pub played: u8,
    pub stop: Stop,
    /// After the batch; on a mismatch, the instance's current one.
    pub sequence: u32,
    /// After the batch.
    pub clock: u32,
    /// The registry's content version the batch ran under; on `Stop::Version`, the current one
    /// the client must recompute under (D-141, E-5).
    pub version: u32,
}

/// A Fate or gate action refused before any draw; nothing changed (design/02).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct Refused {
    #[key]
    pub instance_id: InstanceId,
    pub adventurer_id: u32,
    pub from: u32,
    /// The instance's current sequence.
    pub sequence: u32,
    pub reason: Refusal,
}

/// A goblin died (design/02: each action emits what it emits alone). `tile` is where its remains
/// lie; `by` the entity whose action killed it (M-4 credit is the results').
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct GoblinKilled {
    #[key]
    pub instance_id: InstanceId,
    pub entity: u16,
    pub caste: u16,
    pub tile: u16,
    pub by: u16,
}

/// A chunk was revealed (generated) by a move.
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct ChunkRevealed {
    #[key]
    pub instance_id: InstanceId,
    pub chunk: u8,
}

/// A member was defeated (health reached 0).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct Defeated {
    #[key]
    pub instance_id: InstanceId,
    pub adventurer_id: u32,
}

/// An instance closed: returned, defeated, or left through a gate (then `InstanceEntered` of the
/// next one follows in the same invocation).
#[derive(Drop, Serde, Debug, PartialEq, starknet::Event)]
pub struct InstanceClosed {
    #[key]
    pub instance_id: InstanceId,
    pub outcome: Outcome,
}
