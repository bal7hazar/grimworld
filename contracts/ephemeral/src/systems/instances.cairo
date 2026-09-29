//! `Instances`, the contract of the ephemeral domain (ADR-0001, ADR-0007): every instance, its
//! chunks, goblins and members, and the entrypoints of play (design/02). ENG-01 freezes its
//! interface, storage and events; every entrypoint reverts with `'not implemented'` until its lot
//! (ENG-06, ENG-07, CBT-*) writes it. docs/architecture/ENG-01-interfaces.md.

use grimworld_logic::types::{ChunkKind, InstanceId};
use starknet::{ClassHash, ContractAddress};

/// Version of the interface, returned by `version`.
pub const VERSION: felt252 = 'grimworld-instances-1';
/// The revert of every entrypoint not written yet.
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';
/// The revert of an administrator's entrypoint called by anyone else (ADR-0007, *Access control*).
pub const NOT_ADMIN: felt252 = 'not admin';
/// `set_admin` to the zero address would leave the role to nobody.
pub const ZERO_ADMIN: felt252 = 'admin is zero';

/// A goblin as stored, or as derived from its chunk when it has no record (`derived`).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct GoblinView {
    pub entity: u16,
    pub derived: bool,
    /// `GoblinState` and `GoblinTimers`, in their stored layout.
    pub state: felt252,
    pub timers: felt252,
}

/// A chunk of `instance_region`: its kind, and for a revealed one its stored words and every
/// goblin standing in it, frozen or not (design/02).
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct RegionChunk {
    pub chunk: u8,
    pub kind: ChunkKind,
    pub terrain: felt252,
    pub features: felt252,
    pub goblins: Span<GoblinView>,
}

/// `instance_state`: everything a played action depends on, in one call (design/02). Words are
/// in their stored layout (the client decodes them with the same layouts).
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct InstanceView {
    pub instance_id: InstanceId,
    /// `Header`, the entropy, the revealed set, `Quotas`.
    pub header: felt252,
    pub entropy: felt252,
    pub revealed: felt252,
    pub quotas: felt252,
    /// `TaskPage`s, as many as the header's task count needs.
    pub tasks: Span<felt252>,
    /// Eight words per member, in `Member`'s order (the controller last).
    pub members: Span<felt252>,
    /// The roster pages, **masked** (F-13): lanes of entries at or beyond the header's roster count
    /// are zeros, whatever an earlier generation left in them
    /// (`models::instance::mask_roster_page`).
    /// Pages beyond `⌈roster_count / 15⌉` are not returned.
    pub roster: Span<felt252>,
    /// Every goblin of the members' windows: the untouched ones derived, the touched ones and the
    /// roster's (read through masked pages only) stored.
    pub goblins: Span<GoblinView>,
    /// The chunks the members' windows overlap (revealed ones with their words).
    pub chunks: Span<RegionChunk>,
}

/// The entrypoints of play. Every one takes the adventurer's entity id and the sequence the
/// client played from; the caller must control that adventurer, and it must be in that instance
/// (M-6, design/02 item 9).
#[starknet::interface]
pub trait IInstances<T> {
    /// A played batch: `actions` is 1 to 10 actions in one felt (`grimworld_logic::actions`).
    /// `version` is the content version the batch was computed under (D-141, E-5): the one
    /// `bundle` returns in the call every invocation makes; a different one refuses the batch
    /// whole, before any action runs (`Stop::Version`), like a sequence mismatch.
    /// Checks the sequence, runs the actions in order, stops at the first invalid one or when the
    /// weight would pass 10, never reverts for invalidity in the game; emits `BatchPlayed`.
    fn play(
        ref self: T,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        actions: felt252,
    );
    /// Fate: loot a goblin's remains (target: its entity id). Every precondition before the draw.
    fn loot(ref self: T, instance_id: InstanceId, adventurer_id: u32, sequence: u32, target: u16);
    /// Fate: open the chest on `tile`. `open`, `mine` and `barter` carry the content version their
    /// tick(s) or price were computed under (D-141, design/02 *Which entrypoints carry it*): a
    /// different one is refused before any tick (`Refusal::Version`), changing nothing.
    fn open(
        ref self: T,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        tile: u16,
    );
    /// Mine the vein on `tile` (design/17: 3 ticks, sent alone).
    fn mine(
        ref self: T,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        tile: u16,
    );
    /// Barter with the collector on `tile` (design/15): its price comes from the pack.
    fn barter(
        ref self: T,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        tile: u16,
    );
    /// Leave through `gate`: closes the instance; a gate to another location enters it in the
    /// same invocation (entry draw) and returns the new id, in the same slot; 0 to a hub. The new
    /// generation initialises every transient member word for its clock 0 (state from the
    /// snapshot, timers, effects, recharges): nothing of the old location carries but the belt's
    /// reserve (fix loop 2, F-12).
    fn leave(
        ref self: T, instance_id: InstanceId, adventurer_id: u32, sequence: u32, gate: u16,
    ) -> InstanceId;
    /// Travel back to the last hub (refused in a sealed Red Rift).
    fn travel_back(ref self: T, instance_id: InstanceId, adventurer_id: u32, sequence: u32);

    /// One call, readable at a block hash or `pre_confirmed` (design/02).
    fn instance_state(self: @T, instance_id: InstanceId) -> InstanceView;
    /// Chunks `first .. first + count` (index `15 cy + cx`), `count` at most `REGION_PAGE`. Goblins
    /// and remains lying in a chunk away from their spawn are found through the roster, read
    /// through masked pages only (F-6, F-13).
    fn instance_region(
        self: @T, instance_id: InstanceId, first: u8, count: u8,
    ) -> Span<RegionChunk>;
    /// `(instance id, member index, inside)` of an adventurer; id 0 if it never entered.
    fn placement(self: @T, adventurer_id: u32) -> (InstanceId, u8, bool);
}

/// Administration: one role (who holds it is Q-08).
#[starknet::interface]
pub trait IInstancesAdmin<T> {
    fn version(self: @T) -> felt252;
    /// The registered contracts: the hub that may create instances and receives results, the
    /// registry, the randomness provider (configuration, ADR-0002).
    fn set_contracts(
        ref self: T, hub: ContractAddress, registry: ContractAddress, fate: ContractAddress,
    );
    fn set_admin(ref self: T, admin: ContractAddress);
    /// Upgrade by class replacement: the address, hence the indexer's source, stays (SPK-11 §6).
    fn upgrade(ref self: T, class_hash: ClassHash);
}

#[starknet::contract]
pub mod Instances {
    use core::num::traits::Zero;
    use grimworld_logic::interface::IInstanceEntry;
    use grimworld_logic::packing::{Bitmap, Counter, Lanes16};
    use grimworld_logic::snapshot::{Snapshot, TaskEntry, TaskPage};
    use grimworld_logic::types::InstanceId;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::events::{
        BatchPlayed, ChunkRevealed, Defeated, GoblinKilled, InstanceClosed, InstanceEntered,
        Refused,
    };
    use crate::models::chunk::Chunk;
    use crate::models::goblin::Goblin;
    use crate::models::instance::{Header, Placement, Quotas};
    use crate::models::member::Member;
    use super::{InstanceView, NOT_IMPLEMENTED, RegionChunk, VERSION};

    /// docs/architecture/ENG-01-interfaces.md, *Instances storage*. Every key starts with the
    /// instance's slot, except `placements` (by adventurer: its reference to an instance).
    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        pub hub: ContractAddress,
        pub registry: ContractAddress,
        pub fate: ContractAddress,
        /// The next slot handed out, at an adventurer's first entry; slots are never freed.
        pub next_slot: Counter,
        pub placements: Map<u32, Placement>,
        pub headers: Map<u32, Header>,
        /// The entry draw plus the player entropy, a sum of hashes (a set, ADR-0006 option C).
        pub entropy: Map<u32, felt252>,
        /// Bit `15 cy + cx` for each chunk revealed in the current generation.
        pub revealed: Map<u32, Bitmap>,
        pub quotas: Map<u32, Quotas>,
        /// `(slot, page)`: pages 0-3, four tasks each.
        pub tasks: Map<(u32, u8), TaskPage>,
        /// `(slot, member)`: eight consecutive slots each.
        pub members: Map<(u32, u8), Member>,
        /// `(slot, page)`: pages 0-3, fifteen entity ids each, compact: entries beyond
        /// `header.roster_count` are never read. Goblins displaced from their spawn, alive or dead
        /// and not looted (how a view finds remains away from their spawn chunk).
        pub roster: Map<(u32, u8), Lanes16>,
        /// `(slot, chunk)`: two consecutive slots each.
        pub chunks: Map<(u32, u8), Chunk>,
        /// `(slot, entity)`: two consecutive slots each.
        pub goblins: Map<(u32, u16), Goblin>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        InstanceEntered: InstanceEntered,
        BatchPlayed: BatchPlayed,
        Refused: Refused,
        InstanceClosed: InstanceClosed,
        GoblinKilled: GoblinKilled,
        ChunkRevealed: ChunkRevealed,
        Defeated: Defeated,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        hub: ContractAddress,
        registry: ContractAddress,
        fate: ContractAddress,
    ) {
        self.admin.write(admin);
        self.hub.write(hub);
        self.registry.write(registry);
        self.fate.write(fate);
        self.next_slot.write(Counter { value: 1 });
    }

    #[abi(embed_v0)]
    impl InstancesImpl of super::IInstances<ContractState> {
        fn play(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            version: u32,
            actions: felt252,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn loot(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            target: u16,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn open(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            version: u32,
            tile: u16,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn mine(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            version: u32,
            tile: u16,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn barter(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            version: u32,
            tile: u16,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn leave(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            gate: u16,
        ) -> InstanceId {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn travel_back(
            ref self: ContractState, instance_id: InstanceId, adventurer_id: u32, sequence: u32,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn instance_state(self: @ContractState, instance_id: InstanceId) -> InstanceView {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn instance_region(
            self: @ContractState, instance_id: InstanceId, first: u8, count: u8,
        ) -> Span<RegionChunk> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn placement(self: @ContractState, adventurer_id: u32) -> (InstanceId, u8, bool) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl InstanceEntryImpl of IInstanceEntry<ContractState> {
        fn create(
            ref self: ContractState,
            adventurer_id: u32,
            controller: ContractAddress,
            gate: u16,
            snapshot: Snapshot,
            tasks: Span<TaskEntry>,
        ) -> InstanceId {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        fn set_controller(
            ref self: ContractState, adventurer_id: u32, controller: ContractAddress,
        ) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[abi(embed_v0)]
    impl InstancesAdminImpl of super::IInstancesAdmin<ContractState> {
        fn version(self: @ContractState) -> felt252 {
            VERSION
        }

        fn set_contracts(
            ref self: ContractState,
            hub: ContractAddress,
            registry: ContractAddress,
            fate: ContractAddress,
        ) {
            assert(get_caller_address() == self.admin.read(), super::NOT_ADMIN);
            self.hub.write(hub);
            self.registry.write(registry);
            self.fate.write(fate);
        }

        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            assert(get_caller_address() == self.admin.read(), super::NOT_ADMIN);
            assert(admin.is_non_zero(), super::ZERO_ADMIN);
            self.admin.write(admin);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }
}

/// The storage layout of `Instances` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address (a unit test: the storage is visible from here).
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use super::Instances;

    fn address_of(base: StorageBaseAddress) -> felt252 {
        storage_address_from_base(base).into()
    }

    // Every map is named and keyed as documented: slot first (M-1), adventurer only for placements.
    #[test]
    #[available_gas(l2_gas: 193242)] // ceil(1.05 × 184040 measured)
    fn test_instances_storage_addresses() {
        let state = @Instances::contract_state_for_testing();
        assert(
            address_of(
                state.placements.entry(42).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("placements"), array![42].span()),
            'placements',
        );
        assert(
            address_of(
                state.headers.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("headers"), array![7].span()),
            'headers',
        );
        assert(
            address_of(
                state.entropy.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("entropy"), array![7].span()),
            'entropy',
        );
        assert(
            address_of(
                state.revealed.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("revealed"), array![7].span()),
            'revealed',
        );
        assert(
            address_of(
                state.quotas.entry(7).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("quotas"), array![7].span()),
            'quotas',
        );
        assert(
            address_of(
                state.tasks.entry((7, 3)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("tasks"), array![7, 3].span()),
            'tasks',
        );
        assert(
            address_of(
                state.members.entry((7, 0)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("members"), array![7, 0].span()),
            'members',
        );
        assert(
            address_of(
                state.roster.entry((7, 1)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("roster"), array![7, 1].span()),
            'roster',
        );
        assert(
            address_of(
                state.chunks.entry((7, 224)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("chunks"), array![7, 224].span()),
            'chunks',
        );
        assert(
            address_of(
                state.goblins.entry((7, 3601)).as_ptr().__storage_pointer_address__,
            ) == map_entry_address(selector!("goblins"), array![7, 3601].span()),
            'goblins',
        );
    }
}
