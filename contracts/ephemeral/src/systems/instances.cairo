//! `Instances`, the contract of the ephemeral domain (ADR-0001, ADR-0007): every instance, its
//! chunks, goblins and members, and the entrypoints of play (design/02). ENG-01 freezes its
//! interface, storage and events; every entrypoint reverts with `'not implemented'` until its lot
//! (ENG-06, ENG-07, CBT-*) writes it. docs/architecture/ENG-01-interfaces.md.

use core::num::traits::Zero;
use grimworld_logic::content::exists;
use grimworld_logic::models::location::{Location, LocationTrait};
use grimworld_logic::types::{ChunkKind, InstanceId, MAX_TASKS};
use starknet::{ClassHash, ContractAddress};
use crate::models::instance::errors as instance_errors;

/// Version of the interface, returned by `version`.
pub const VERSION: felt252 = 'grimworld-instances-1';
/// The revert of every entrypoint not written yet.
pub const NOT_IMPLEMENTED: felt252 = 'not implemented';
pub use errors::{NOT_ADMIN, ZERO_ADMIN};

/// The refusals of `Instances`' administration (ADR-0007, *Access control*). The lifecycle's are
/// `models::instance::errors`.
pub mod errors {
    /// An administrator's entrypoint called by anyone else.
    pub const NOT_ADMIN: felt252 = 'not admin';
    /// `set_admin` to the zero address would leave the role to nobody.
    pub const ZERO_ADMIN: felt252 = 'admin is zero';
}

/// The checks of `Instances`' callers and of `create`'s inputs, before any write (those of a gate
/// action are `HeaderAssert::refusal`'s, refusals and not reverts; the placement's are
/// `PlacementAssert`'s).
#[generate_trait]
pub impl InstancesAssert of InstancesAssertTrait {
    /// The caller is the administrator.
    #[inline(always)]
    fn assert_admin(caller: ContractAddress, admin: ContractAddress) {
        assert(caller == admin, errors::NOT_ADMIN);
    }

    /// A new administrator is not the zero address.
    #[inline(always)]
    fn assert_admin_not_zero(admin: ContractAddress) {
        assert(admin.is_non_zero(), errors::ZERO_ADMIN);
    }

    /// The caller is the registered hub (`create`, `set_controller`; ENG-01 §1.2).
    #[inline(always)]
    fn assert_hub(caller: ContractAddress, hub: ContractAddress) {
        assert(caller == hub, instance_errors::NOT_HUB);
    }

    /// No more task entries than a snapshot holds (D-131).
    #[inline(always)]
    fn assert_tasks(count: u32) {
        assert(count <= MAX_TASKS.into(), instance_errors::TOO_MANY_TASKS);
    }

    /// The registry holds the gate (`parts`, its record).
    #[inline(always)]
    fn assert_gate(parts: Span<felt252>) {
        assert(exists(parts), instance_errors::NO_GATE);
    }

    /// The registry holds the gate's destination (`parts`, its record).
    #[inline(always)]
    fn assert_location(parts: Span<felt252>) {
        assert(exists(parts), instance_errors::NO_LOCATION);
    }

    /// The destination has a map: a town or an outpost is not an instance (design/01).
    #[inline(always)]
    fn assert_map(location: @Location) {
        assert(location.has_map(), instance_errors::NO_MAP);
    }
}

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
    use grimworld_logic::content::{GATE, LOCATION, exists};
    use grimworld_logic::fate::{ENTRY, derive, domain};
    use grimworld_logic::interface::{
        IFateDispatcher, IFateDispatcherTrait, IInstanceEntry, IRegistryReadDispatcher,
        IRegistryReadDispatcherTrait, IResultsDispatcher, IResultsDispatcherTrait, Results, facts,
    };
    use grimworld_logic::models::gate::{Gate, GateRecord, GateTrait, kind as gate_kind};
    use grimworld_logic::models::location::{Location, LocationRecord, LocationTrait};
    use grimworld_logic::packing::{Bitmap, Counter, Lanes16};
    use grimworld_logic::snapshot::{SnapshotWords, TaskEntry, TaskPage};
    use grimworld_logic::types::{InstanceId, Outcome, Refusal, instance_id, instance_parts};
    use starknet::storage::Map;
    use starknet::storage_access::StorePacking;
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use crate::events::{
        BatchPlayed, ChunkRevealed, Defeated, GoblinKilled, InstanceClosed, InstanceEntered,
        Refused,
    };
    use crate::helpers::stored::{Stored, StoredTrait};
    use crate::models::chunk::Chunk;
    use crate::models::goblin::Goblin;
    use crate::models::instance::{
        DEFEATED, Header, HeaderAssert, HeaderTrait, Placement, PlacementAssert, PlacementTrait,
        Quotas, QuotasTrait, RETURNED, ROSTER_LANES, mask_roster_page,
    };
    use crate::models::member::{
        DOWN, GONE, MemberState, MemberStateTrait, StoredMember,
    };
    use crate::store::InstancesStoreTrait;
    use super::{InstanceView, InstancesAssert, NOT_IMPLEMENTED, RegionChunk, VERSION};

    /// Task entries on a stored page (`TaskPage`).
    const TASKS_PER_PAGE: u32 = 4;

    /// docs/architecture/ENG-01-interfaces.md, *Instances storage*. Every key starts with the
    /// instance's slot, except `placements` (by adventurer: its reference to an instance). Declared
    /// with the slot types the store reads and writes (`Stored<M>`, `StoredMember`: the words of
    /// the models `M`, `Member`, at the same addresses; ENG-R1b, `store.cairo`'s module doc). Read
    /// and written only by the store (`InstancesStoreTrait`).
    #[storage]
    pub struct Storage {
        pub admin: ContractAddress,
        pub hub: ContractAddress,
        pub registry: ContractAddress,
        pub fate: ContractAddress,
        /// The next slot handed out, at an adventurer's first entry; slots are never freed.
        pub next_slot: Counter,
        pub placements: Map<u32, Placement>,
        pub headers: Map<u32, Stored<Header>>,
        /// The entry draw plus the player entropy, a sum of hashes (a set, ADR-0006 option C).
        pub entropy: Map<u32, felt252>,
        /// Bit `15 cy + cx` for each chunk revealed in the current generation.
        pub revealed: Map<u32, Stored<Bitmap>>,
        pub quotas: Map<u32, Stored<Quotas>>,
        /// `(slot, page)`: pages 0-3, four tasks each.
        pub tasks: Map<(u32, u8), Stored<TaskPage>>,
        /// `(slot, member)`: eight consecutive slots each (`Member`'s).
        pub members: Map<(u32, u8), StoredMember>,
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
        self.initialize(admin, hub, registry, fate);
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

        /// Leaves through `gate` (design/02 *Ending an expedition*, D-02): the caller controls the
        /// member, then the instance's checks (`HeaderAssert::refusal`), then the gate from the
        /// registry, which must stand in this location with the member on its anchor
        /// (`GateTrait::can_leave`). Any refusal emits `Refused`, draws nothing, changes nothing
        /// and returns 0. A hub gate closes the instance (Returned, the hub reached and
        /// unlocked) and returns 0. A link closes it (Moved) and enters its destination in the
        /// same slot, the next generation, with its entry draw: nothing of the member carries
        /// but the belt's reserve (D-141, E-20); returns the new id. Calls: `Registry.record`
        /// (the gate; and the destination, through a link), `fate` (a link), `Hub.report`.
        fn leave(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            gate: u16,
        ) -> InstanceId {
            let Option::Some((slot, header, placement, state)) = self
                .admit(instance_id, adventurer_id, sequence) else {
                return 0;
            };
            let registry = IRegistryReadDispatcher { contract_address: self.get_registry() };
            let parts = registry.record(GATE, gate.into());
            if !exists(parts) {
                self.refuse(instance_id, adventurer_id, sequence, header.sequence, Refusal::Gate);
                return 0;
            }
            let record: Gate = GateRecord::unpack(parts);
            if !record.can_leave(header.location, state.x, state.y) {
                self.refuse(instance_id, adventurer_id, sequence, header.sequence, Refusal::Gate);
                return 0;
            }
            if record.kind == gate_kind::HUB {
                self
                    .close(
                        instance_id,
                        slot,
                        header,
                        placement,
                        state,
                        Outcome::Returned,
                        record.destination,
                        facts::HUB_REACHED,
                    );
                return 0;
            }
            let parts = registry.record(LOCATION, record.destination.into());
            if !exists(parts) {
                self.refuse(instance_id, adventurer_id, sequence, header.sequence, Refusal::Gate);
                return 0;
            }
            let location: Location = LocationRecord::unpack(parts);
            if !location.has_map() {
                self.refuse(instance_id, adventurer_id, sequence, header.sequence, Refusal::Gate);
                return 0;
            }

            self.emit(InstanceClosed { instance_id, outcome: Outcome::Moved });
            let (max_health, max_energy) = MemberStateTrait::maxima(
                self.get_stats(slot, placement.member).word,
            );
            let next = self
                .begin(
                    slot,
                    header.generation,
                    adventurer_id,
                    gate,
                    @record,
                    @location,
                    header.tasks,
                    max_health,
                    max_energy,
                    state.belt,
                );
            self.report(instance_id, adventurer_id, Outcome::Moved, 0, 0, 0, next, [0; 4]);
            next
        }

        /// Travels back to the last hub (design/02, D-04): the same checks as `leave`, then a
        /// sealed Red Rift refuses (`Refusal::Sealed`, design/17); otherwise the instance closes,
        /// Returned, and the hub places the adventurer in its last hub (`Results.hub` 0). No
        /// registry read: the seal is in the header. Calls: `Hub.report`.
        fn travel_back(
            ref self: ContractState, instance_id: InstanceId, adventurer_id: u32, sequence: u32,
        ) {
            let Option::Some((slot, header, placement, state)) = self
                .admit(instance_id, adventurer_id, sequence) else {
                return;
            };
            if header.is_sealed() {
                self.refuse(instance_id, adventurer_id, sequence, header.sequence, Refusal::Sealed);
                return;
            }
            self.close(instance_id, slot, header, placement, state, Outcome::Returned, 0, 0);
        }

        /// The stored words of the instance (ENG-01 §4.1), read through the gates of §2.1: an id
        /// whose generation is not the slot's current one answers nothing (every word 0, every
        /// list empty); task pages up to `⌈tasks / 4⌉`; the members' eight words; roster pages
        /// up to `⌈roster_count / 15⌉`, masked (F-13). The window's chunks and goblins are read
        /// only through `revealed`: nothing is revealed until ENG-05's reveal, so they are empty;
        /// ENG-05 and ENG-07 fill them.
        fn instance_state(self: @ContractState, instance_id: InstanceId) -> InstanceView {
            let (slot, generation) = instance_parts(instance_id);
            let stored = self.get_stored_header(slot);
            let header = stored.model();
            if generation == 0 || header.generation != generation {
                return InstanceView {
                    instance_id,
                    header: 0,
                    entropy: 0,
                    revealed: 0,
                    quotas: 0,
                    tasks: array![].span(),
                    members: array![].span(),
                    roster: array![].span(),
                    goblins: array![].span(),
                    chunks: array![].span(),
                };
            }
            let pages: u32 = (header.tasks.into() + TASKS_PER_PAGE - 1) / TASKS_PER_PAGE;
            let tasks = self.get_task_words(slot, pages.try_into().unwrap());
            let members = self.get_member_words(slot, header.members);
            let mut roster: Array<felt252> = array![];
            let lanes: u32 = ROSTER_LANES.into();
            let pages: u32 = (header.roster_count.into() + lanes - 1) / lanes;
            for page in 0..pages {
                let page: u8 = page.try_into().unwrap();
                let stored = self.get_roster_page(slot, page);
                roster
                    .append(
                        StorePacking::pack(mask_roster_page(stored, page, header.roster_count)),
                    );
            }
            InstanceView {
                instance_id,
                header: stored.word,
                entropy: self.get_entropy(slot),
                revealed: self.get_revealed(slot).word,
                quotas: self.get_quotas(slot).word,
                tasks,
                members,
                roster: roster.span(),
                goblins: array![].span(),
                chunks: array![].span(),
            }
        }

        fn instance_region(
            self: @ContractState, instance_id: InstanceId, first: u8, count: u8,
        ) -> Span<RegionChunk> {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }

        /// `(instance id, member, inside)`: the adventurer's last instance, 0 if it never entered.
        fn placement(self: @ContractState, adventurer_id: u32) -> (InstanceId, u8, bool) {
            let placement = self.get_placement(adventurer_id);
            if placement.slot == 0 {
                return (0, 0, false);
            }
            (
                instance_id(placement.slot, placement.generation),
                placement.member,
                placement.inside != 0,
            )
        }
    }

    #[abi(embed_v0)]
    impl InstanceEntryImpl of IInstanceEntry<ContractState> {
        /// `Hub` only (ENG-01 §1.2). The adventurer's slot, or a new one at its first entry
        /// (`next_slot`); the gate and its destination from the registry (a location with a
        /// map); the snapshot and the task pages (`⌈tasks / 4⌉`); then the new generation
        /// (`begin`), with the entry draw after every check. What a reused slot held is left
        /// unreachable (§2.1): the header, entropy, revealed set, quotas and the member's eight
        /// words are rewritten, the roster's count is 0, task pages beyond the count are never
        /// read. The entry chunk's reveal is ENG-05's: until then `revealed` is empty and no
        /// chunk word is written, so no chunk of an earlier generation is reachable.
        fn create(
            ref self: ContractState,
            adventurer_id: u32,
            controller: ContractAddress,
            gate: u16,
            snapshot: SnapshotWords,
            tasks: Span<TaskEntry>,
        ) -> InstanceId {
            InstancesAssert::assert_hub(get_caller_address(), self.get_hub());
            InstancesAssert::assert_tasks(tasks.len());
            let placement = self.get_placement(adventurer_id);
            placement.assert_outside();
            let registry = IRegistryReadDispatcher { contract_address: self.get_registry() };
            let parts = registry.record(GATE, gate.into());
            InstancesAssert::assert_gate(parts);
            let record: Gate = GateRecord::unpack(parts);
            let parts = registry.record(LOCATION, record.destination.into());
            InstancesAssert::assert_location(parts);
            let location: Location = LocationRecord::unpack(parts);
            InstancesAssert::assert_map(@location);

            let slot = if placement.slot != 0 {
                placement.slot
            } else {
                self.new_slot()
            };
            self.write_tasks(slot, tasks);
            // The snapshot's words as `Hub` stored them (D-168), written as they are.
            self.set_snapshot(slot, 0, @snapshot, controller);
            let (max_health, max_energy) = MemberStateTrait::maxima(snapshot.stats);
            let previous = self.get_header(slot).generation;
            self
                .begin(
                    slot,
                    previous,
                    adventurer_id,
                    gate,
                    @record,
                    @location,
                    tasks.len().try_into().unwrap(),
                    max_health,
                    max_energy,
                    snapshot.belt_counts,
                )
        }

        /// `Hub` only: the account changed owner while the adventurer is inside (A-7, M-6). One
        /// word, the member's controller.
        fn set_controller(
            ref self: ContractState, adventurer_id: u32, controller: ContractAddress,
        ) {
            InstancesAssert::assert_hub(get_caller_address(), self.get_hub());
            let placement = self.get_placement(adventurer_id);
            placement.assert_inside();
            self.set_member_controller(placement.slot, placement.member, controller);
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
            InstancesAssert::assert_admin(get_caller_address(), self.get_administrator());
            self.set_registered(hub, registry, fate);
        }

        /// Hands the administrator role over; the caller loses it. Administrator only.
        fn set_admin(ref self: ContractState, admin: ContractAddress) {
            InstancesAssert::assert_admin(get_caller_address(), self.get_administrator());
            InstancesAssert::assert_admin_not_zero(admin);
            self.set_administrator(admin);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            core::panic_with_felt252(NOT_IMPLEMENTED)
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        /// The access check of a gate action (M-6, ENG-01 §1.2), then its refusals: the caller
        /// must be the controller of the adventurer's member (a revert otherwise, not a refusal of
        /// the game), then `HeaderAssert::refusal`. A refusal emits `Refused` and returns `None`.
        /// Returns the instance's slot, its header, the adventurer's placement and its member
        /// state.
        fn admit(
            ref self: ContractState, instance_id: InstanceId, adventurer_id: u32, sequence: u32,
        ) -> Option<(u32, Header, Placement, MemberState)> {
            let (slot, generation) = instance_parts(instance_id);
            let placement = self.get_placement(adventurer_id);
            let state = self
                .get_controlled_state(placement.slot, placement.member, get_caller_address());
            let header = self.get_header(slot);
            match header.refusal(generation, @placement, slot, state.status, sequence) {
                Option::Some(reason) => {
                    self.refuse(instance_id, adventurer_id, sequence, header.sequence, reason);
                    Option::None
                },
                Option::None => Option::Some((slot, header, placement, state)),
            }
        }

        fn refuse(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            from: u32,
            sequence: u32,
            reason: Refusal,
        ) {
            self.emit(Refused { instance_id, adventurer_id, from, sequence, reason });
        }

        /// A new generation of `slot` after `previous` (ENG-01 §2.1): its header, the entry draw
        /// (`fate(poseidon(id, 0, ENTRY))`, ADR-0002; the entropy is the value derived from it),
        /// an empty revealed set, the location's quotas, and the member's four transient words
        /// for clock 0 (F-12, F-14): on the gate's entry tile, maxima from `stats`, the belt's
        /// `belt` counts, no activation, condition, effect or recharge. The placement follows.
        /// The caller has made every check: the draw comes last but for the writes it feeds.
        fn begin(
            ref self: ContractState,
            slot: u32,
            previous: u32,
            adventurer_id: u32,
            gate: u16,
            record: @Gate,
            location: @Location,
            tasks: u8,
            max_health: u16,
            max_energy: u8,
            belt: [u8; 4],
        ) -> InstanceId {
            let generation = previous + 1;
            let id = instance_id(slot, generation);
            let destination = *record.destination;
            self
                .set_header(
                    slot,
                    HeaderTrait::new(
                        generation,
                        destination,
                        tasks,
                        *location.sealed,
                        *record.entry_chunk,
                        *record.entry_tile,
                        gate,
                    ),
                );
            let draw = domain(id.into(), 0, ENTRY);
            let word = IFateDispatcher { contract_address: self.get_fate() }.fate(draw);
            self.set_entropy(slot, derive(word, draw, 0));
            self.set_revealed(slot, Bitmap { bits: 0 });
            self.set_quotas(slot, QuotasTrait::new(*location.target));
            let (x, y) = record.entry();
            self
                .set_entering(
                    slot,
                    0,
                    MemberStateTrait::entering(adventurer_id, x, y, max_health, max_energy, belt),
                );
            self.set_placement(adventurer_id, PlacementTrait::new(slot, generation));
            self
                .emit(
                    InstanceEntered { instance_id: id, adventurer_id, location: destination, gate },
                );
            id
        }

        /// **The closing path** of every way out that ends a member's presence: `leave` through a
        /// hub gate and `travel_back` (`Outcome::Returned`), and ENG-07's defeat
        /// (`Outcome::Defeated`, the member `DOWN`). The header's status, the member's status, the
        /// placement left, `InstanceClosed`, then one report to the hub with the belt's unused
        /// counts, credited back on return and on defeat alike (D-141, E-15). `hub` is where the
        /// adventurer goes: 0 for its last hub (travel back, defeat: D-04). `facts` is
        /// `HUB_REACHED` through a hub gate (that hub unlocked, design/01).
        fn close(
            ref self: ContractState,
            instance_id: InstanceId,
            slot: u32,
            header: Header,
            placement: Placement,
            state: MemberState,
            outcome: Outcome,
            hub: u16,
            facts: u32,
        ) {
            let (status, member_status) = match outcome {
                Outcome::Returned => (RETURNED, GONE),
                Outcome::Defeated => (DEFEATED, DOWN),
                _ => core::panic_with_felt252('close: not a closing outcome'),
            };
            self.set_header(slot, Header { status, ..header });
            self.set_member_state(slot, placement.member, MemberState { status: member_status, ..state });
            self.set_placement(state.adventurer, Placement { inside: 0, ..placement });
            self.emit(InstanceClosed { instance_id, outcome });
            self.report(instance_id, state.adventurer, outcome, hub, facts, hub, 0, state.belt);
        }

        /// One call to `Hub.report` (D-131: one a transaction) with what a lifecycle path has to
        /// settle: no loot, experience or task progress (ENG-07's and the Fate actions').
        fn report(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            outcome: Outcome,
            hub: u16,
            facts: u32,
            location: u16,
            next: InstanceId,
            belt: [u8; 4],
        ) {
            IResultsDispatcher { contract_address: self.get_hub() }
                .report(
                    Results {
                        instance_id,
                        contributors: array![adventurer_id].span(),
                        experience: 0,
                        gold: 0,
                        balances: array![].span(),
                        equipment: array![].span(),
                        tasks: array![].span(),
                        facts,
                        location,
                        outcome,
                        hub,
                        next,
                        belt,
                    },
                );
        }

        /// The task pages a snapshot needs, `⌈tasks / 4⌉`, the last one padded with empty
        /// entries.
        fn write_tasks(ref self: ContractState, slot: u32, tasks: Span<TaskEntry>) {
            let count = tasks.len();
            let mut first: u32 = 0;
            let mut page: u8 = 0;
            while first < count {
                let mut entries: Array<TaskEntry> = array![];
                for i in first..first + TASKS_PER_PAGE {
                    entries.append(if i < count {
                        *tasks[i]
                    } else {
                        Default::default()
                    });
                }
                self
                    .set_task_page(
                        slot,
                        page,
                        TaskPage { entries: [*entries[0], *entries[1], *entries[2], *entries[3]] },
                    );
                first += TASKS_PER_PAGE;
                page += 1;
            }
        }
    }
}

/// The closing path on defeat (ENG-07 calls it; no ENG-06 entrypoint reaches it): the header
/// `DEFEATED`, the member `DOWN`, the placement left, `InstanceClosed`, and one report whose belt
/// is the unused counts (D-141, E-15), to the last hub (`hub` 0, D-04). The hub's `report` is
/// mocked; its settlement is tested in `grimworld_persistent`.
#[cfg(test)]
mod close_tests {
    use grimworld_logic::types::{Outcome, instance_id};
    use snforge_std::{
        ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
        test_address,
    };
    use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::events::InstanceClosed;
    use crate::helpers::stored::StoredTrait;
    use crate::models::instance::{DEFEATED, HeaderTrait, OPEN, Placement, PlacementTrait};
    use crate::models::member::{DOWN, INSIDE, MemberState};
    use crate::store::InstancesStoreTrait;
    use super::Instances;
    use super::Instances::InternalTrait;

    #[starknet::interface]
    trait ISink<T> {
        /// `(reports, outcome index, hub, belt as a felt, the first contributor)`.
        fn last(self: @T) -> (u32, felt252, u16, felt252, u32);
    }

    /// Receives the report as the hub would and keeps what the closing path sends.
    #[starknet::contract]
    mod ReportSink {
        use grimworld_logic::interface::{IResults, Results};
        use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

        #[storage]
        struct Storage {
            count: u32,
            outcome: felt252,
            hub: u16,
            belt: felt252,
            adventurer: u32,
        }

        #[abi(embed_v0)]
        impl ResultsImpl of IResults<ContractState> {
            fn report(ref self: ContractState, results: Results) {
                let mut outcome = array![];
                results.outcome.serialize(ref outcome);
                let [a, b, c, d] = results.belt;
                self.count.write(self.count.read() + 1);
                self.outcome.write(*outcome[0]);
                self.hub.write(results.hub);
                self
                    .belt
                    .write(a.into() + b.into() * 0x100 + c.into() * 0x10000 + d.into() * 0x1000000);
                self.adventurer.write(*results.contributors[0]);
            }
            fn barter(ref self: ContractState, adventurer_id: u32, collector: u16) -> bool {
                false
            }
        }

        #[abi(embed_v0)]
        impl SinkImpl of super::ISink<ContractState> {
            fn last(self: @ContractState) -> (u32, felt252, u16, felt252, u32) {
                (
                    self.count.read(),
                    self.outcome.read(),
                    self.hub.read(),
                    self.belt.read(),
                    self.adventurer.read(),
                )
            }
        }
    }

    #[test]
    // gas: raised, CBT-01: the snapshot carries design/19's passives (FX-24)
    #[available_gas(l2_gas: 5046069)] // ceil(1.05 × 4805780 measured)
    fn test_close_on_defeat() {
        let class = declare("ReportSink").unwrap().contract_class();
        let (hub, _) = class.deploy(@array![]).unwrap();
        let mut state = Instances::contract_state_for_testing();
        // The test's setup writes the slots directly, as before the store (the measure is the
        // closing path's); the store is checked by `store`'s tests.
        state.hub.write(hub);
        let slot = 3;
        let id = instance_id(slot, 5);
        let header = HeaderTrait::new(5, 2, 0, false, 0, 105, 1);
        let placement = PlacementTrait::new(slot, 5);
        let member = MemberState {
            adventurer: 7, status: INSIDE, health: 0, belt: [1, 0, 3, 0], ..Default::default(),
        };
        state.set_header(slot, header);
        state.set_placement(7, placement);
        let mut spy = spy_events();
        state.close(id, slot, header, placement, member, Outcome::Defeated, 0, 0);

        assert(header.status == OPEN, 'was open');
        assert(state.get_header(slot).status == DEFEATED, 'defeated');
        let down = state.members.entry((slot, 0)).state.read().model();
        assert(down == MemberState { status: DOWN, ..member }, 'member down');
        assert(state.get_placement(7) == Placement { inside: 0, ..placement }, 'left');
        spy
            .assert_emitted(
                @array![
                    (
                        test_address(),
                        Instances::Event::InstanceClosed(
                            InstanceClosed { instance_id: id, outcome: Outcome::Defeated },
                        ),
                    ),
                ],
            );
        // One report: Defeated (variant 2), to the last hub (0), the belt's unused counts.
        let sink = ISinkDispatcher { contract_address: hub };
        assert(sink.last() == (1, 2, 0, 0x30001, 7), 'report on defeat');
    }
}
