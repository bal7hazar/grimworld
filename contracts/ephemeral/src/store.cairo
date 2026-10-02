//! The store (D-143, D-147; ENG-R1b on ENG-R1a's pattern, `quiver_quest` 0.2.0's): the only access
//! to the ephemeral package's storage, `get_x` and `set_x` per model, and focused reads and writes
//! where a path needs less than the model.
//!
//! **`Instances`' store is `InstancesStoreTrait`**, implemented on `Instances`' contract state as
//! `HubStoreTrait` is on `Hub`'s: a call is `self.get_header(slot)` inside the contract, with
//! nothing built and nothing looked up at run time. Every storage variable of `Instances` (ENG-01
//! §3.2) is read and written here, and nowhere else; `Instances`' systems hold models, never a
//! storage path or an offset.
//!
//! **Typed slots** (ENG-R1a's note 4, measured in ENG-R1b). `Instances` declares its storage with
//! the slot types it reads and writes, as `quiver_quest` does: a word that a view returns as stored,
//! or that a path writes as a constant, is declared `Stored<M>` (`helpers::stored`), the word of the
//! model `M` as stored, at the address and in the layout a `Map<_, M>` gives (`layout_tests`). So
//! the store does no address arithmetic: no `__storage_pointer_address__`, no word offset, no
//! `read_at_offset`. Declared so: the header, the revealed set, the quotas, the task pages, and the
//! member's eight slots (`StoredMember`). Declared as their models, because every path reads or
//! writes them whole through their packer: the configuration, `next_slot`, the placements, the
//! roster pages. `entropy` is a felt. **No slot keeps an offset access**: every one passed the rule
//! of ENG-R1b's *Scope* (its report gives the figures).
//!
//! **Models and words.** A path that needs a model's fields reads it through its packer
//! (`get_header`, `get_controller_state`); a view reads the words as stored (`get_stored_header`,
//! `get_member_words`): a slot never written reads 0 there, where a packer would give `LIVE`.
//!
//! **Tracking** (docs/CAIRO.md §7, D-147, D-149): **no model of `Instances` is tracked, so no
//! `set_x` here emits**. The indexer reads ENG-01's events, frozen (D-149), and none of them
//! matches the writes of one model: `InstanceEntered` follows `begin`'s writes of six models,
//! `InstanceClosed` follows a header's write but not every one (`create` writes headers through
//! `begin`), `Refused` writes nothing. The systems keep emitting them where they did. The lot that
//! tracks a model adds quiver's mechanism as `store.cairo` of the persistent package says.
//!
//! **Layers**: the store is implemented on `Instances`' state, so it depends on
//! `systems::instances`, which depends on it, as `HubStoreTrait` on `Hub`'s; it serves `Instances`
//! alone. The test of `Instances`' storage addresses (`layout_tests`) is here because the store is
//! what reads and writes them.

use grimworld_logic::packing::{Bitmap, Counter, Lanes16};
use grimworld_logic::snapshot::{MemberStats, SnapshotWords, TaskPage};
use starknet::ContractAddress;
use starknet::storage::{
    StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess, SubPointersForward,
    SubPointersMutForward,
};
use crate::helpers::stored::{Stored, StoredTrait};
use crate::models::instance::{Header, Placement, Quotas};
use crate::models::member::{
    EMPTY_EFFECTS, EMPTY_RECHARGES, EMPTY_TIMERS, MemberAssert, MemberState,
};
use crate::systems::instances::Instances::ContractState as InstancesState;

#[generate_trait]
pub impl InstancesStoreImpl of InstancesStoreTrait {
    // Configuration: one slot each

    /// The constructor's writes: the administrator, the three registered contracts, `next_slot` at
    /// 1.
    fn initialize(
        ref self: InstancesState,
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

    #[inline(always)]
    fn get_administrator(self: @InstancesState) -> ContractAddress {
        self.admin.read()
    }

    #[inline(always)]
    fn set_administrator(ref self: InstancesState, admin: ContractAddress) {
        self.admin.write(admin)
    }

    #[inline(always)]
    fn get_hub(self: @InstancesState) -> ContractAddress {
        self.hub.read()
    }

    #[inline(always)]
    fn get_registry(self: @InstancesState) -> ContractAddress {
        self.registry.read()
    }

    #[inline(always)]
    fn get_fate(self: @InstancesState) -> ContractAddress {
        self.fate.read()
    }

    /// `set_contracts`' writes, in its order.
    fn set_registered(
        ref self: InstancesState,
        hub: ContractAddress,
        registry: ContractAddress,
        fate: ContractAddress,
    ) {
        self.hub.write(hub);
        self.registry.write(registry);
        self.fate.write(fate);
    }

    /// A new slot, at an adventurer's first entry: `next_slot` read, then written one more. Slots
    /// are never freed.
    #[inline(always)]
    fn new_slot(ref self: InstancesState) -> u32 {
        let next = self.next_slot.read().value;
        self.next_slot.write(Counter { value: next + 1 });
        next.try_into().unwrap()
    }

    // Placements: `placements[adventurer]`, the adventurer's reference to its instance

    #[inline(always)]
    fn get_placement(self: @InstancesState, adventurer_id: u32) -> Placement {
        self.placements.entry(adventurer_id).read()
    }

    #[inline(always)]
    fn set_placement(ref self: InstancesState, adventurer_id: u32, placement: Placement) {
        self.placements.entry(adventurer_id).write(placement)
    }

    // The instance: `headers`, `entropy`, `revealed`, `quotas`, `tasks[(slot, page)]`, by slot

    /// The header through its packer: what every path but the view reads.
    #[inline(always)]
    fn get_header(self: @InstancesState, slot: u32) -> Header {
        self.headers.entry(slot).read().model()
    }

    /// The header as stored, for the view that returns its word (and decodes it once).
    #[inline(always)]
    fn get_stored_header(self: @InstancesState, slot: u32) -> Stored<Header> {
        self.headers.entry(slot).read()
    }

    #[inline(always)]
    fn set_header(ref self: InstancesState, slot: u32, header: Header) {
        self.headers.entry(slot).write(StoredTrait::new(header))
    }

    #[inline(always)]
    fn get_entropy(self: @InstancesState, slot: u32) -> felt252 {
        self.entropy.entry(slot).read()
    }

    #[inline(always)]
    fn set_entropy(ref self: InstancesState, slot: u32, entropy: felt252) {
        self.entropy.entry(slot).write(entropy)
    }

    #[inline(always)]
    fn get_revealed(self: @InstancesState, slot: u32) -> Stored<Bitmap> {
        self.revealed.entry(slot).read()
    }

    #[inline(always)]
    fn set_revealed(ref self: InstancesState, slot: u32, revealed: Bitmap) {
        self.revealed.entry(slot).write(StoredTrait::new(revealed))
    }

    #[inline(always)]
    fn get_quotas(self: @InstancesState, slot: u32) -> Stored<Quotas> {
        self.quotas.entry(slot).read()
    }

    #[inline(always)]
    fn set_quotas(ref self: InstancesState, slot: u32, quotas: Quotas) {
        self.quotas.entry(slot).write(StoredTrait::new(quotas))
    }

    /// The first `pages` task pages as stored, in order: the view's. Bound: 4 pages (`MAX_TASKS`).
    fn get_task_words(self: @InstancesState, slot: u32, pages: u8) -> Span<felt252> {
        let mut words: Array<felt252> = array![];
        for page in 0..pages {
            words.append(self.tasks.entry((slot, page)).read().word);
        }
        words.span()
    }

    #[inline(always)]
    fn set_task_page(ref self: InstancesState, slot: u32, page: u8, entries: TaskPage) {
        self.tasks.entry((slot, page)).write(StoredTrait::new(entries))
    }

    // Members: `members[(slot, member)]`, eight slots (`StoredMember`)

    /// The member's state through its packer, once its controller is checked to be `caller`
    /// (`MemberAssert::assert_controller`, M-6): a gate action's access check (`Instances`'
    /// `admit`). The two slots under one address, the check between the two reads, so that a
    /// caller who is not the controller reverts before the state is read.
    fn get_controlled_state(
        self: @InstancesState, slot: u32, member: u8, caller: ContractAddress,
    ) -> MemberState {
        let entry = self.members.entry((slot, member));
        MemberAssert::assert_controller(entry.controller.read(), caller);
        entry.state.read().model()
    }

    #[inline(always)]
    fn set_member_state(ref self: InstancesState, slot: u32, member: u8, state: MemberState) {
        self.members.entry((slot, member)).state.write(StoredTrait::new(state))
    }

    /// The member's stats as stored, one read: what its maxima are read from
    /// (`MemberStateTrait::maxima`), without unpacking the other fields.
    #[inline(always)]
    fn get_stats(self: @InstancesState, slot: u32, member: u8) -> Stored<MemberStats> {
        self.members.entry((slot, member)).stats.read()
    }

    /// The member's controller, one slot (`set_controller`, A-7).
    #[inline(always)]
    fn set_member_controller(
        ref self: InstancesState, slot: u32, member: u8, controller: ContractAddress,
    ) {
        self.members.entry((slot, member)).controller.write(controller)
    }

    /// The snapshot's three words as `Hub` stored them (D-168), packed by the flattening
    /// (`FlattenLibrary`), so written as they are, without unpacking; then the controller, under
    /// the same address (`create`).
    fn set_snapshot(
        ref self: InstancesState,
        slot: u32,
        member: u8,
        snapshot: @SnapshotWords,
        controller: ContractAddress,
    ) {
        let slots = self.members.entry((slot, member)).sub_pointers_mut();
        slots.stats.write(Stored { word: *snapshot.stats });
        slots.bar.write(Stored { word: *snapshot.bar });
        slots.kit.write(Stored { word: *snapshot.kit });
        slots.controller.write(controller);
    }

    /// A member entering a new generation (ENG-01 §2.1, F-12, F-14): its state, then the three
    /// empty transient words (`EMPTY_TIMERS`, `EMPTY_EFFECTS`, `EMPTY_RECHARGES`), written as they
    /// are stored, under one address.
    fn set_entering(ref self: InstancesState, slot: u32, member: u8, state: MemberState) {
        let slots = self.members.entry((slot, member)).sub_pointers_mut();
        slots.state.write(StoredTrait::new(state));
        slots.timers.write(Stored { word: EMPTY_TIMERS });
        slots.effects.write(Stored { word: EMPTY_EFFECTS });
        slots.recharges.write(Stored { word: EMPTY_RECHARGES });
    }

    /// The eight words of each of the first `members` members as stored, in `Member`'s order (the
    /// controller last): the view's. Bound: the header's members, 1 in the MVP (M-3).
    fn get_member_words(self: @InstancesState, slot: u32, members: u8) -> Span<felt252> {
        let mut words: Array<felt252> = array![];
        for member in 0..members {
            let entry = self.members.entry((slot, member)).read();
            words.append(entry.state.word);
            words.append(entry.timers.word);
            words.append(entry.effects.word);
            words.append(entry.recharges.word);
            words.append(entry.stats.word);
            words.append(entry.bar.word);
            words.append(entry.kit.word);
            words.append(entry.controller.into());
        }
        words.span()
    }

    // The roster: `roster[(slot, page)]`, a `Lanes16` of fifteen entity ids

    /// A roster page as stored, unmasked: the caller masks it (`mask_roster_page`, F-13).
    #[inline(always)]
    fn get_roster_page(self: @InstancesState, slot: u32, page: u8) -> Lanes16 {
        self.roster.entry((slot, page)).read()
    }
}

/// The storage layout of `Instances` is what docs/architecture/ENG-01-interfaces.md says: every
/// variable's name and keys, hence its address. Here since ENG-R1b: the store is what reads and
/// writes them.
#[cfg(test)]
mod layout_tests {
    use snforge_std::map_entry_address;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{StorageBaseAddress, storage_address_from_base};
    use crate::systems::instances::Instances;

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

/// ENG-R1a's note 4, measured (ENG-R1b): each path the typed slots replaced, run once through the
/// offset access it replaced (`__storage_pointer_address__` and `Store::<felt252>::read_at_offset`
/// or `write_at_offset` at `Member`'s offsets, kept here as the reference) and once through the
/// store, on the same state. A pair's two figures differ by the path's cost alone; the report gives
/// them.
#[cfg(test)]
mod note4_tests {
    use grimworld_logic::snapshot::SnapshotWords;
    use starknet::storage::{StorageAsPointer, StoragePathEntry};
    use starknet::storage_access::{Store, StorageBaseAddress};
    use starknet::{ContractAddress, SyscallResultTrait};
    use crate::helpers::stored::StoredTrait;
    use crate::models::instance::{Header, HeaderTrait, Quotas, QuotasTrait};
    use crate::models::member::{
        EMPTY_EFFECTS, EMPTY_RECHARGES, EMPTY_TIMERS, MemberState, MemberStateTrait,
    };
    use crate::systems::instances::Instances;
    use super::InstancesStoreTrait;

    const SLOT: u32 = 7;

    fn member(state: @Instances::ContractState) -> StorageBaseAddress {
        state.members.entry((SLOT, 0)).as_ptr().__storage_pointer_address__
    }

    fn word(base: StorageBaseAddress, offset: u8) -> felt252 {
        Store::<felt252>::read_at_offset(0, base, offset).unwrap_syscall()
    }

    fn set_word(base: StorageBaseAddress, offset: u8, value: felt252) {
        Store::<felt252>::write_at_offset(0, base, offset, value).unwrap_syscall()
    }

    fn snapshot() -> SnapshotWords {
        SnapshotWords {
            stats: 0x400000000000000000000000000000000000000000000000000000000640064,
            bar: 0x400000000000000000000000000000000000000000000000000000000000001,
            kit: 0x400000000000000000000000000000000000000000000000000000000000002,
            belt_counts: [1, 0, 0, 0],
        }
    }

    fn entering() -> MemberState {
        MemberStateTrait::entering(9, 3, 4, 100, 10, [1, 0, 0, 0])
    }

    fn controller() -> ContractAddress {
        0x123.try_into().unwrap()
    }

    // `create`'s snapshot and controller: three words and the controller.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_snapshot_by_offsets() {
        let mut state = Instances::contract_state_for_testing();
        let base = member(@state);
        let words = snapshot();
        set_word(base, 4, words.stats);
        set_word(base, 5, words.bar);
        set_word(base, 6, words.kit);
        Store::<ContractAddress>::write_at_offset(0, base, 7, controller()).unwrap_syscall();
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_snapshot_typed() {
        let mut state = Instances::contract_state_for_testing();
        state.set_snapshot(SLOT, 0, @snapshot(), controller());
    }

    // `begin`'s member: the state through its packer, then the three empty transient words.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_entering_by_offsets() {
        let mut state = Instances::contract_state_for_testing();
        let base = member(@state);
        Store::<MemberState>::write_at_offset(0, base, 0, entering()).unwrap_syscall();
        set_word(base, 1, EMPTY_TIMERS);
        set_word(base, 2, EMPTY_EFFECTS);
        set_word(base, 3, EMPTY_RECHARGES);
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_entering_typed() {
        let mut state = Instances::contract_state_for_testing();
        state.set_entering(SLOT, 0, entering());
    }

    // `leave`: the stats word, for the maxima.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_stats_by_offsets() {
        let state = Instances::contract_state_for_testing();
        assert(word(member(@state), 4) == 0, 'blank');
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_stats_typed() {
        let state = Instances::contract_state_for_testing();
        assert(state.get_stats(SLOT, 0).word == 0, 'blank');
    }

    // `instance_state`: one member's eight words.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_member_words_by_offsets() {
        let state = Instances::contract_state_for_testing();
        let base = member(@state);
        let mut words: Array<felt252> = array![];
        for offset in 0..8_u32 {
            words.append(word(base, offset.try_into().unwrap()));
        }
        assert(words.len() == 8, 'eight');
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_member_words_typed() {
        let state = Instances::contract_state_for_testing();
        assert(state.get_member_words(SLOT, 1).len() == 8, 'eight');
    }

    // `instance_state`: the header (its word, decoded once), the revealed set, the quotas, one
    // task page, as stored.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_view_words_by_offsets() {
        let state = @Instances::contract_state_for_testing();
        let header_word = word(state.headers.entry(SLOT).as_ptr().__storage_pointer_address__, 0);
        let header: Header = starknet::storage_access::StorePacking::unpack(header_word);
        let mut tasks: Array<felt252> = array![];
        for page in 0..1_u8 {
            tasks.append(word(state.tasks.entry((SLOT, page)).as_ptr().__storage_pointer_address__, 0));
        }
        let revealed = word(state.revealed.entry(SLOT).as_ptr().__storage_pointer_address__, 0);
        let quotas = word(state.quotas.entry(SLOT).as_ptr().__storage_pointer_address__, 0);
        assert(header.generation == 0 && revealed + quotas + *tasks[0] == 0, 'blank');
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_view_words_typed() {
        let state = Instances::contract_state_for_testing();
        let stored = state.get_stored_header(SLOT);
        let header = stored.model();
        let tasks = state.get_task_words(SLOT, 1);
        let revealed = state.get_revealed(SLOT).word;
        let quotas = state.get_quotas(SLOT).word;
        assert(header.generation == 0 && revealed + quotas + *tasks[0] == 0, 'blank');
    }

    // `begin`'s instance words: the header, the revealed set and the quotas through their packers.
    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_begin_words_by_model() {
        let state = @Instances::contract_state_for_testing();
        let header = HeaderTrait::new(2, 3, 0, false, 112, 112, 6);
        Store::<Header>::write(0, state.headers.entry(SLOT).as_ptr().__storage_pointer_address__, header)
            .unwrap_syscall();
        Store::<grimworld_logic::packing::Bitmap>::write(
            0,
            state.revealed.entry(SLOT).as_ptr().__storage_pointer_address__,
            grimworld_logic::packing::Bitmap { bits: 0 },
        )
            .unwrap_syscall();
        Store::<Quotas>::write(
            0, state.quotas.entry(SLOT).as_ptr().__storage_pointer_address__, QuotasTrait::new(6),
        )
            .unwrap_syscall();
    }

    #[test]
    #[available_gas(l2_gas: 1)]
    fn test_begin_words_typed() {
        let mut state = Instances::contract_state_for_testing();
        state.set_header(SLOT, HeaderTrait::new(2, 3, 0, false, 112, 112, 6));
        state.set_revealed(SLOT, grimworld_logic::packing::Bitmap { bits: 0 });
        state.set_quotas(SLOT, QuotasTrait::new(6));
    }
}
