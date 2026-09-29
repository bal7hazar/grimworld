//! Measurement probes of ENG-01, never deployed by the game: `ReuseProbe` prices a storage key
//! written, kept or zeroed, then written again (docs/architecture/ENG-01-interfaces.md, *Reuse,
//! measured*); `CallProbe` prices a view call from one contract to another (the registry read of
//! an invocation); `EventProbe` prices the per-action events. No game rule lives here.

#[starknet::interface]
pub trait IReuseProbe<T> {
    /// Writes `value` under the `count` keys `first`, `first + 1`, … (one storage write each).
    fn write(ref self: T, first: u32, count: u32, value: felt252);
    fn read(self: @T, key: u32) -> felt252;
}

#[starknet::contract]
pub mod ReuseProbe {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        slots: Map<u32, felt252>,
    }

    #[abi(embed_v0)]
    impl ReuseProbeImpl of super::IReuseProbe<ContractState> {
        fn write(ref self: ContractState, first: u32, count: u32, value: felt252) {
            let mut key = first;
            let end = first + count;
            while key != end {
                self.slots.write(key, value);
                key += 1;
            }
        }

        fn read(self: @ContractState, key: u32) -> felt252 {
            self.slots.read(key)
        }
    }
}

#[starknet::interface]
pub trait ICallProbe<T> {
    /// Reads `count` felts under consecutive keys of this contract's own storage.
    fn records(self: @T, first: u32, count: u32) -> Span<felt252>;
    /// The same records, read from another `CallProbe` through one view call.
    fn records_of(
        self: @T, other: starknet::ContractAddress, first: u32, count: u32,
    ) -> Span<felt252>;
    fn set(ref self: T, key: u32, value: felt252);
}

#[starknet::contract]
pub mod CallProbe {
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{ICallProbeDispatcher, ICallProbeDispatcherTrait};

    #[storage]
    struct Storage {
        slots: Map<u32, felt252>,
    }

    #[abi(embed_v0)]
    impl CallProbeImpl of super::ICallProbe<ContractState> {
        fn records(self: @ContractState, first: u32, count: u32) -> Span<felt252> {
            let mut out: Array<felt252> = array![];
            let mut key = first;
            let end = first + count;
            while key != end {
                out.append(self.slots.read(key));
                key += 1;
            }
            out.span()
        }

        fn records_of(
            self: @ContractState, other: ContractAddress, first: u32, count: u32,
        ) -> Span<felt252> {
            ICallProbeDispatcher { contract_address: other }.records(first, count)
        }

        fn set(ref self: ContractState, key: u32, value: felt252) {
            self.slots.write(key, value);
        }
    }
}

#[starknet::interface]
pub trait IEventProbe<T> {
    /// Emits `killed` events shaped as `GoblinKilled` and `revealed` shaped as `ChunkRevealed`.
    fn fire(ref self: T, killed: u32, revealed: u32);
}

/// Prices the per-action events of `Instances` (fix loop 1, F-7): the same call with and without
/// its events.
#[starknet::contract]
pub mod EventProbe {
    use crate::events::{ChunkRevealed, GoblinKilled};

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        GoblinKilled: GoblinKilled,
        ChunkRevealed: ChunkRevealed,
    }

    #[abi(embed_v0)]
    impl EventProbeImpl of super::IEventProbe<ContractState> {
        fn fire(ref self: ContractState, killed: u32, revealed: u32) {
            let mut i: u32 = 0;
            while i != killed {
                let entity: u16 = (8 + i).try_into().unwrap();
                self
                    .emit(
                        GoblinKilled {
                            instance_id: 0x100000001, entity, caste: 3, tile: 0x707, by: 0,
                        },
                    );
                i += 1;
            }
            let mut j: u32 = 0;
            while j != revealed {
                self.emit(ChunkRevealed { instance_id: 0x100000001, chunk: j.try_into().unwrap() });
                j += 1;
            }
        }
    }
}
