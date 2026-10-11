//! The goblin loader as a library class of this package (FIX-02b, D-269): `PlayLibrary` (`play`'s
//! two content rounds) and `Instances.instance_state` (VIEW-01's `window`, D-263) call
//! `GoblinsLibrary` by `library_call`, so this code runs in `Instances`' context and reads its
//! storage through `Instances`' own store, as `PlayLibrary` does. It writes nothing.
//!
//! **The goblins of a round** (`GoblinsTrait::goblins`; design/18, ENG-01 §3.2): the packs'
//! goblins of the chunks given, a record when `touched`, else derived from the placement (castes by
//! `PackTrait::caste`, at full health, their pack's state), and the stored goblins given; the
//! records they need read from the registry (pack templates, castes, their skills, held effects'
//! skills), and, in `play`'s rounds, **the skills of the chunks' unused terrain traps** (FIX-02,
//! D-266; design/19 §5.11: a terrain trap's `param` is its `SKILL`, 0 none: such a trap stays
//! inert), `MAX_READ` records a `bundle`. **A goblin the registry cannot load** (its caste, a caste
//! skill or its held effect's skill missing) **or a trap skill it lacks refuses the batch**
//! (`None`, `Stop::Invalid` in `play`).

use grimworld_logic::models::chunk::Features;
use grimworld_logic::models::index::GoblinWords;
use grimworld_logic::models::pack::Pack;
use grimworld_logic::types::InstanceId;
use grimworld_logic::types::tick::{CasteSheet, SkillSheet};
use crate::systems::instances::GoblinView;

#[starknet::interface]
pub trait IGoblinsLibrary<T> {
    /// A content round of `play` (`GoblinsTrait::goblins`, the terrain traps' skills read), in
    /// `Instances`' context: the batch's records so far go in (`packs`, `castes`, `skills`), the
    /// goblins and the records read for them come back. `None` when the registry cannot load one
    /// of the goblins or lacks a trap's skill.
    fn goblins(
        self: @T,
        slot: u32,
        packs: Span<(u16, Pack)>,
        castes: Span<CasteSheet>,
        skills: Span<SkillSheet>,
        chunks: Span<(u8, Features)>,
        stored: Array<GoblinWords>,
        skip: Span<u16>,
    ) -> Option<Loaded>;
    /// `instance_state`'s goblins (VIEW-01, D-263), in `Instances`' context:
    /// `GoblinsTrait::window`.
    /// `None` when the registry cannot load one of them.
    fn window(self: @T, instance_id: InstanceId) -> Option<Span<GoblinView>>;
}

/// What a content round read: its goblins and the records the batch did not hold yet.
#[derive(Drop, Serde)]
pub struct Loaded {
    pub goblins: Array<GoblinWords>,
    pub packs: Array<(u16, Pack)>,
    pub castes: Array<CasteSheet>,
    pub skills: Array<SkillSheet>,
}

#[starknet::contract]
pub mod GoblinsLibrary {
    use grimworld_logic::interface::IRegistryReadDispatcher;
    use grimworld_logic::models::chunk::Features;
    use grimworld_logic::models::index::GoblinWords;
    use grimworld_logic::models::pack::Pack;
    use grimworld_logic::types::tick::{CasteSheet, SkillSheet};
    use grimworld_logic::types::{InstanceId, instance_parts};
    use crate::store::InstancesStoreTrait;
    use crate::systems::instances::{GoblinView, Instances};
    use crate::systems::play::Book;
    use super::{GoblinsTrait, Loaded};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl GoblinsLibraryImpl of super::IGoblinsLibrary<ContractState> {
        fn goblins(
            self: @ContractState,
            slot: u32,
            packs: Span<(u16, Pack)>,
            castes: Span<CasteSheet>,
            skills: Span<SkillSheet>,
            chunks: Span<(u8, Features)>,
            stored: Array<GoblinWords>,
            skip: Span<u16>,
        ) -> Option<Loaded> {
            let mut instances = Instances::unsafe_new_contract_state();
            let registry = IRegistryReadDispatcher { contract_address: instances.get_registry() };
            let mut book = Book {
                packs: array![], castes: array![], skills: array![], potions: array![],
            };
            book.packs.append_span(packs);
            book.castes.append_span(castes);
            book.skills.append_span(skills);
            let goblins = GoblinsTrait::goblins(
                ref instances, slot, registry, ref book, chunks, stored, skip, true,
            )?;
            let Book {
                packs: all_packs, castes: all_castes, skills: all_skills, potions: _,
            } = book;
            let mut out = Loaded { goblins, packs: array![], castes: array![], skills: array![] };
            out
                .packs
                .append_span(all_packs.span().slice(packs.len(), all_packs.len() - packs.len()));
            out
                .castes
                .append_span(
                    all_castes.span().slice(castes.len(), all_castes.len() - castes.len()),
                );
            out
                .skills
                .append_span(
                    all_skills.span().slice(skills.len(), all_skills.len() - skills.len()),
                );
            Some(out)
        }

        fn window(self: @ContractState, instance_id: InstanceId) -> Option<Span<GoblinView>> {
            let mut instances = Instances::unsafe_new_contract_state();
            let (slot, _) = instance_parts(instance_id);
            Some(GoblinsTrait::window(ref instances, slot)?.span())
        }
    }
}
use grimworld_logic::content::{CASTE, MAX_READ, PACK, SKILL, exists};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
use grimworld_logic::models::chunk::{PackPlacementTrait, object};
use grimworld_logic::models::pack::{PackRecord, PackTrait};
use grimworld_logic::packing::LIVE;
use grimworld_logic::types::goblin_entity;
use grimworld_logic::types::reveal::board::BoardTrait as Bits;
use grimworld_logic::types::tick::{CasteSheetTrait, SkillSheetTrait};
use starknet::storage_access::StorePacking;
use crate::helpers::stored::StoredTrait;
use crate::models::member::{INSIDE, MemberState};
use crate::store::InstancesStoreTrait;
use crate::systems::instances::Instances::{ContractState as InstancesState, InternalTrait};
use crate::systems::play::{Book, PlayTrait};

/// `2^n` for the goblin words' offsets.
const P8: felt252 = 0x100;
const P24: felt252 = 0x1000000;
const P32: felt252 = 0x100000000;
const P48: felt252 = 0x1000000000000;
const P64: felt252 = 0x10000000000000000;
const P80: felt252 = 0x100000000000000000000;
/// A first record's timers (F-14): no activation (255), nothing held; stored, `LIVE + 255`.
const EMPTY_TIMERS: felt252 = LIVE + 255;

#[generate_trait]
pub impl GoblinsImpl of GoblinsTrait {
    /// `instance_state`'s goblins (VIEW-01, D-263): those a batch would load first (its `[Read]`
    /// of the goblins, by the same functions: `roster`, `ground`, `goblins`, `sorted`) for every
    /// member inside at once (a member down or gone plays no batch), the roster's and those of the
    /// revealed chunks of the 3 × 3 around each such member's tile, in ascending entity id, each
    /// said derived (no record: not in the roster, its `touched` bit clear) or stored. `goblins`
    /// runs a chunk at a time, then on the roster 30 goblins at a time, the content read carried
    /// in one `Book`: each of its `bundle`s stays within the registry's 32 records (2 templates,
    /// 10 castes a chunk), however many chunks the members' windows span; the goblins are the same
    /// as one call's. The terrain traps' skills are not read: the view lists goblins. `None` when
    /// the registry cannot load one of them, where `play` refuses the batch (`Stop::Invalid`).
    fn window(ref self: InstancesState, slot: u32) -> Option<Array<GoblinView>> {
        let header = self.get_header(slot);
        let registry = IRegistryReadDispatcher { contract_address: self.get_registry() };
        let revealed = self.get_revealed(slot).model().bits;
        let words = self.get_member_words(slot, header.members);
        let mut ground: Array<(u8, Features)> = array![];
        let mut m: u32 = 0;
        while m < header.members.into() {
            let member: MemberState = StorePacking::unpack(*words[8 * m]);
            if member.status == INSIDE {
                let more = PlayTrait::ground(
                    @self, slot, revealed, member.x, member.y, ground.span(),
                );
                ground.append_span(more.span());
            }
            m += 1;
        }
        let roster = PlayTrait::roster(@self, slot, header.roster_count);
        let mut book = Book {
            packs: array![], castes: array![], skills: array![], potions: array![],
        };
        let mut goblins: Array<GoblinWords> = array![];
        for entry in ground.span() {
            let chunk = Self::goblins(
                ref self,
                slot,
                registry,
                ref book,
                array![*entry].span(),
                array![],
                roster.span(),
                false,
            )?;
            goblins.append_span(chunk.span());
        }
        let mut from: u32 = 0;
        while from < roster.len() {
            let count = if roster.len() - from > 30 {
                30
            } else {
                roster.len() - from
            };
            let mut stored: Array<GoblinWords> = array![];
            for entity in roster.span().slice(from, count) {
                let (state, timers) = self.get_goblin_words(slot, *entity);
                stored.append(GoblinWords { entity: *entity, awake: false, state, timers });
            }
            let listed = Self::goblins(
                ref self, slot, registry, ref book, array![].span(), stored, roster.span(), false,
            )?;
            goblins.append_span(listed.span());
            from += count;
        }
        let mut out: Array<GoblinView> = array![];
        for goblin in PlayTrait::sorted(goblins.span()) {
            let GoblinWords { entity, awake: _, state, timers } = goblin;
            let derived = !PlayTrait::listed(roster.span(), entity)
                && PlayTrait::untouched(
                    ground.span(), PlayTrait::spawn_chunk(entity), PlayTrait::k_of(entity),
                );
            out.append(GoblinView { entity, derived, state, timers });
        }
        Some(out)
    }

    /// The goblins of `chunks` (their packs' goblins: a record when `touched`, else derived from
    /// the placement at full health, its pack's state) and `stored`, but those of `skip` (already
    /// held); the records they need read into `book` (pack templates, castes, their skills, held
    /// effects' skills, and with `traps` the skills of `chunks`' unused terrain traps: one `bundle`
    /// a kind missing, `MAX_READ` records a call). `None` when the registry cannot load one of
    /// them (a caste, a caste skill or a held effect's skill missing) or, with `traps`, lacks a
    /// trap's skill.
    fn goblins(
        ref self: InstancesState,
        slot: u32,
        registry: IRegistryReadDispatcher,
        ref book: Book,
        chunks: Span<(u8, Features)>,
        stored: Array<GoblinWords>,
        skip: Span<u16>,
        traps: bool,
    ) -> Option<Array<GoblinWords>> {
        let mut stored = stored;
        // The pack templates `book` lacks
        let missing = PlayTrait::templates(chunks, book.packs.span());
        if missing.len() > 0 {
            let mut requests: Array<(u8, u32)> = array![];
            for id in missing.span() {
                requests.append((PACK, *id));
            }
            let (_, _, parts) = registry.bundle(requests.span());
            let mut at: u32 = 0;
            for id in missing.span() {
                let record = parts.slice(at, 1);
                at += 1;
                if exists(record) {
                    book.packs.append(((*id).try_into().unwrap(), PackRecord::unpack(record)));
                }
            }
        }
        let mut derived: Array<(u16, u8, u8, u8, u16, u8)> = array![];
        let mut castes: Array<u32> = array![];
        for (chunk, features) in chunks {
            let mut p: u8 = 0;
            for pack in features.packs.span() {
                let template = PlayTrait::template(book.packs.span(), *pack.template);
                let mut i: u8 = 0;
                while i < *pack.count {
                    let k = 5 * p + i;
                    let entity = goblin_entity(*chunk, k);
                    if PlayTrait::listed(
                        skip, entity,
                    ) {} else if Bits::has((*features.touched).into(), k) {
                        let (state, timers) = self.get_goblin_words(slot, entity);
                        stored.append(GoblinWords { entity, awake: false, state, timers });
                    } else {
                        let template = template?;
                        let caste = template.caste(*pack.count, i);
                        let offset = Self::offset(*pack.offsets, i);
                        let (gx, gy) = Self::spawn(*chunk, *pack.tile, offset);
                        derived.append((entity, gx, gy, *pack.alert, caste, *pack.level));
                        if Self::sheet(book.castes.span(), caste).is_none() {
                            InternalTrait::add(ref castes, caste);
                        }
                    }
                    i += 1;
                }
                p += 1;
            }
        }
        for goblin in stored.span() {
            let caste = PlayTrait::caste_of(*goblin.state);
            if Self::sheet(book.castes.span(), caste).is_none() {
                InternalTrait::add(ref castes, caste);
            }
        }
        // The castes `book` lacks, then the skills it lacks
        let mut more: Array<u32> = array![];
        if castes.len() > 0 {
            let mut requests: Array<(u8, u32)> = array![];
            for id in castes.span() {
                requests.append((CASTE, *id));
            }
            let (_, _, parts) = registry.bundle(requests.span());
            let mut at: u32 = 0;
            for id in castes.span() {
                let record = parts.slice(at, 2);
                at += 2;
                if exists(record) {
                    let sheet = CasteSheetTrait::read((*id).try_into().unwrap(), record);
                    for skill in sheet.skills.span() {
                        let id: u32 = (*skill).into();
                        if id != 0 && !Self::holds_skill(book.skills.span(), id) {
                            PlayTrait::push(ref more, id);
                        }
                    }
                    book.castes.append(sheet);
                }
            }
        }
        for goblin in stored.span() {
            let effect = Self::effect_of(*goblin.timers);
            if effect != 0 && !Self::holds_skill(book.skills.span(), effect) {
                PlayTrait::push(ref more, effect);
            }
        }
        // The terrain traps' skills `book` lacks (FIX-02): an unused trap's `param`, 0 none
        let mut wanted: Array<u32> = array![];
        if traps {
            for (_, features) in chunks {
                for object in features.objects.span() {
                    let id: u32 = (*object.param).into();
                    if *object.kind == object::TRAP
                        && *object.state == 0
                        && id != 0
                        && !Self::holds_skill(book.skills.span(), id) {
                        PlayTrait::push(ref wanted, id);
                        PlayTrait::push(ref more, id);
                    }
                }
            }
        }
        let mut from: u32 = 0;
        while from < more.len() {
            let count = if more.len() - from > MAX_READ {
                MAX_READ
            } else {
                more.len() - from
            };
            let mut requests: Array<(u8, u32)> = array![];
            for id in more.span().slice(from, count) {
                requests.append((SKILL, *id));
            }
            let (_, _, parts) = registry.bundle(requests.span());
            let mut at: u32 = 0;
            for id in more.span().slice(from, count) {
                let record = parts.slice(at, 2);
                at += 2;
                if exists(record) {
                    book.skills.append(SkillSheetTrait::read((*id).try_into().unwrap(), record));
                }
            }
            from += count;
        }
        for id in wanted.span() {
            if !Self::holds_skill(book.skills.span(), *id) {
                return None;
            }
        }
        // The goblins, every one loadable
        let mut out: Array<GoblinWords> = array![];
        for entry in derived.span() {
            let (entity, gx, gy, alert, caste, level) = *entry;
            let sheet = Self::usable(book.castes.span(), book.skills.span(), caste, 0)?;
            let state = LIVE
                + gx.into()
                + gy.into() * P8
                + alert.into() * P24
                + sheet.max_health(level).into() * P32
                + (sheet.energy * 3).into() * P48
                + caste.into() * P64
                + level.into() * P80;
            out.append(GoblinWords { entity, awake: false, state, timers: EMPTY_TIMERS });
        }
        for goblin in stored.span() {
            let caste = PlayTrait::caste_of(*goblin.state);
            let effect = Self::effect_of(*goblin.timers);
            Self::usable(book.castes.span(), book.skills.span(), caste, effect)?;
            out.append(*goblin);
        }
        Some(out)
    }

    /// The sheet of caste `caste` if the content holds it, every skill of it and the skill
    /// `effect` (0 for none).
    fn usable(
        castes: Span<CasteSheet>, skills: Span<SkillSheet>, caste: u16, effect: u32,
    ) -> Option<CasteSheet> {
        let sheet = Self::sheet(castes, caste)?;
        for id in sheet.skills.span() {
            if *id != 0 && !Self::holds_skill(skills, (*id).into()) {
                return None;
            }
        }
        if effect != 0 && !Self::holds_skill(skills, effect) {
            return None;
        }
        Some(sheet)
    }

    fn holds_skill(skills: Span<SkillSheet>, id: u32) -> bool {
        for sheet in skills {
            if (*sheet.id).into() == id {
                return true;
            }
        }
        false
    }

    fn sheet(castes: Span<CasteSheet>, id: u16) -> Option<CasteSheet> {
        for sheet in castes {
            if *sheet.id == id {
                return Some(*sheet);
            }
        }
        None
    }

    /// Goblin `i`'s index in `OFFSETS` (5 bits each).
    fn offset(offsets: u32, i: u8) -> u8 {
        let mut rest = offsets;
        let mut k: u8 = 0;
        while k < i {
            rest /= 32;
            k += 1;
        }
        (rest % 32).try_into().unwrap()
    }

    /// The global tile of the goblin at `OFFSETS[offset]` from its pack's tile `tile` in `chunk`.
    fn spawn(chunk: u8, tile: u8, offset: u8) -> (u8, u8) {
        let (cy, cx) = DivRem::div_rem(chunk, 15);
        let (row, _) = DivRem::div_rem(tile, 15);
        let odd = (row + cy) % 2 == 1;
        let local = match PackPlacementTrait::member(tile, offset, odd) {
            Some(local) => local,
            None => tile,
        };
        let (ly, lx) = DivRem::div_rem(local, 15);
        (cx * 15 + lx, cy * 15 + ly)
    }

    /// A goblin's effect skill from its `GoblinTimers` (108–123).
    fn effect_of(timers: felt252) -> u32 {
        let wide: u256 = timers.into();
        ((wide.low / 0x1000000000000000000000000000) % 0x10000).try_into().unwrap()
    }
}
