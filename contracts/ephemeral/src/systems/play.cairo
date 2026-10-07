//! `play`'s body as a library class of this package (ENG-07; D-234, D-235): `Instances.play` makes
//! its admission checks and calls `PlayLibrary` by `library_call`, so this code runs in `Instances`'
//! context: its storage, through `Instances`' own store (`InstancesStoreTrait`, on the state
//! `Instances::unsafe_new_contract_state` gives), and its events, emitted from its address. The
//! layout and the events are `Instances`' (ENG-01 §3.2, §5), unchanged.
//!
//! **A batch** (design/02 *Executing a batch*, ENG-01 §4.1):
//! 1. the content (D-145), read once in three `bundle` calls: the location, its zone's chunk set,
//!    the pack templates of the area's chunks, the member's skills and potions; then the castes of
//!    the area's goblins; then their skills. A content version that differs from the batch's stops
//!    it before any action (`Stop::Version`);
//! 2. the area (`types::play::Area`): the 3 × 3 chunks around the adventurer's, their terrain and
//!    features read once; the goblins of those chunks, stored (`touched`) or derived from their
//!    pack placement (design/18, ENG-01 §3.2: castes by `PackTrait::caste`, at full health, their
//!    pack's state), and the roster's (displaced);
//! 3. the segments (`types::play::SegmentTrait`): the actions in order, a tick without a goblin in
//!    the window here, one with a fight in `TickLibrary` (D-235); between two segments, the chunks
//!    sight touches revealed (`RevealLibrary`, as `create` does: a zone's hosts from the stored
//!    bitmaps of the quotas the generation counts, a dungeon floor's from its stored outline, A7,
//!    A8), or the area moved when the window leaves it;
//! 4. the words written back: the member's four, each goblin whose words changed (its spawn chunk's
//!    `touched` bit; the roster when it stands away from its spawn chunk), each chunk whose objects
//!    changed, the header (sequence, clock, counts); then `GoblinKilled`, `ChunkRevealed`,
//!    `BatchPlayed` and, on a defeat, `Defeated` and the closing report.
//!
//! **Readings this lot fixed** (the report lists them): a `GoblinKilled`'s `by` is 0, the member
//! (the MVP's goblins are killed by the member's carriers or its traps); a reveal's weight (2 a
//! chunk) is taken from the weight left after the Move that caused it, floored at 0; E-16's cap and
//! E-1's first-record weight are not built (the report's escalation).

use grimworld_logic::types::InstanceId;

#[starknet::interface]
pub trait IPlayLibrary<T> {
    /// `play`'s body, its admission first (ENG-01 §4.1; D-236), in `Instances`' context.
    fn play(
        ref self: T,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        actions: felt252,
    );
}

#[starknet::contract]
pub mod PlayLibrary {
    use grimworld_logic::types::InstanceId;
    use crate::systems::instances::Instances;
    use super::PlayTrait;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl PlayLibraryImpl of super::IPlayLibrary<ContractState> {
        fn play(
            ref self: ContractState,
            instance_id: InstanceId,
            adventurer_id: u32,
            sequence: u32,
            version: u32,
            actions: felt252,
        ) {
            let mut instances = Instances::unsafe_new_contract_state();
            PlayTrait::play(ref instances, instance_id, adventurer_id, sequence, version, actions);
        }
    }
}

use grimworld_logic::actions::decode_batch;
use grimworld_logic::content::{CASTE, ITEM, LOCATION, OUTLINE, PACK, SKILL, exists};
use grimworld_logic::interface::{
    IRegistryReadDispatcher, IRegistryReadDispatcherTrait, IRevealLibraryDispatcherTrait,
    IRevealLibraryLibraryDispatcher,
};
use grimworld_logic::models::chunk::{
    Features, FeaturesStorePacking, PackPlacementTrait, Terrain, TerrainStorePacking,
};
use grimworld_logic::models::index::{GoblinWords, MemberWords};
use grimworld_logic::models::location::{Location, LocationRecord};
use grimworld_logic::models::member::{MemberTrait, MemberWordsTrait};
use grimworld_logic::models::outline::{CHUNK_SET, OutlineTrait};
use grimworld_logic::models::pack::{Pack, PackRecord, PackTrait};
use grimworld_logic::packing::{Bitmap, LIVE, Lanes16};
use grimworld_logic::types::play::{Area, Classes};
use grimworld_logic::types::reveal::ProgressTrait;
use grimworld_logic::types::reveal::SightTrait;
use grimworld_logic::types::reveal::board::BoardTrait as Bits;
use grimworld_logic::types::reveal::placement::PlacementTrait as QuotaPlacementTrait;
use grimworld_logic::types::tick::{
    CasteSheet, CasteSheetTrait, Content, PotionSheet, PotionSheetTrait, SkillSheet,
    SkillSheetTrait,
};
use grimworld_logic::types::world::Words;
use grimworld_logic::interface::{ISegmentLibraryDispatcherTrait, ISegmentLibraryLibraryDispatcher};
use grimworld_logic::types::{MAX_WEIGHT, Refusal, Stop, goblin_entity};
use starknet::storage_access::StorePacking;
use crate::events::{BatchPlayed, ChunkRevealed, Defeated, GoblinKilled};
use crate::models::instance::{
    Header, HeaderAssertTrait, QuotasTrait, ROSTER_LANES, RosterTrait,
};
use crate::models::member::MemberState;
use crate::helpers::stored::StoredTrait;
use crate::store::InstancesStoreTrait;
use starknet::event::EventEmitter;
use crate::systems::instances::Instances::{ContractState as InstancesState, InternalTrait};
use crate::systems::instances::play_class;

/// The bits of a chunk's 225 tiles.
const TILES: felt252 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
/// `2^n` for the goblin and member words' offsets.
const P8: felt252 = 0x100;
const P16: felt252 = 0x10000;
const P24: felt252 = 0x1000000;
const P32: felt252 = 0x100000000;
const P48: felt252 = 0x1000000000000;
const P64: felt252 = 0x10000000000000000;
const P80: felt252 = 0x100000000000000000000;
/// A first record's timers (F-14): no activation (255), nothing held; stored, `LIVE + 255`.
const EMPTY_TIMERS: felt252 = LIVE + 255;

/// What the batch read of the instance, kept for the write-back.
#[derive(Drop)]
struct Read {
    header: Header,
    location: Location,
    area: Area,
    /// Each area chunk's `Features`, as read (the ground the segments carry and write).
    ground: Array<(u8, Features)>,
    /// The goblins as they came in, and the roster.
    goblins: Span<GoblinWords>,
    roster: Array<u16>,
}

#[generate_trait]
pub impl PlayImpl of PlayTrait {
    fn play(
        ref self: InstancesState,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        actions: felt252,
    ) {
        // The admission (D-236, from `Instances`): the caller controls the member, then the
        // instance's checks; a refusal is a `BatchPlayed` that ran nothing.
        let (slot, generation) = grimworld_logic::types::instance_parts(instance_id);
        let placement = self.get_placement(adventurer_id);
        let member = placement.member;
        let mstate = self
            .get_controlled_state(placement.slot, placement.member, starknet::get_caller_address());
        let header = self.get_header(slot);
        if let Option::Some(reason) = header
            .refusal(generation, @placement, slot, mstate.status, sequence) {
            let stop = if reason == Refusal::Sequence {
                Stop::Sequence
            } else {
                Stop::Closed
            };
            self.played(instance_id, adventurer_id, sequence, @header, 0, stop, version);
            return;
        }
        let registry = IRegistryReadDispatcher { contract_address: self.get_registry() };
        // [Read] The member, the area and its goblins
        let words = self.get_member_words(slot, header.members);
        let mut members: Array<MemberWords> = array![];
        let mut m: u32 = 0;
        while m < header.members.into() {
            members
                .append(
                    MemberWords {
                        state: *words[8 * m],
                        timers: *words[8 * m + 1],
                        effects: *words[8 * m + 2],
                        recharges: *words[8 * m + 3],
                        stats: *words[8 * m + 4],
                        bar: *words[8 * m + 5],
                        kit: *words[8 * m + 6],
                    },
                );
            m += 1;
        }
        let first = *members[member.into()];
        let (x, y) = Self::place(first.state);
        let revealed = self.get_revealed(slot).model().bits;
        let ground = Self::ground(@self, slot, revealed, x, y);
        // [Read] The content, first call: the location, a zone's chunk set, the area's pack
        // templates, the members' skills and potions
        let mut requests: Array<(u8, u32)> = array![
            (LOCATION, header.location.into()),
            (OUTLINE, OutlineTrait::id(header.location, CHUNK_SET)),
        ];
        let mut templates: Array<u32> = array![];
        for (_, features) in ground.span() {
            for pack in features.packs.span() {
                if *pack.count > 0 {
                    InternalTrait::add(ref templates, *pack.template);
                }
            }
        }
        for id in templates.span() {
            requests.append((PACK, *id));
        }
        let mut skills: Array<u32> = array![];
        let mut potions: Array<u32> = array![];
        for words in members.span() {
            Self::member_content(words, ref skills, ref potions);
        }
        for id in skills.span() {
            requests.append((SKILL, *id));
        }
        for id in potions.span() {
            requests.append((ITEM, *id));
        }
        let (current, _, parts) = registry.bundle(requests.span());
        if current != version {
            self.played(instance_id, adventurer_id, sequence, @header, 0, Stop::Version, current);
            return;
        }
        let location: Location = LocationRecord::unpack(parts.slice(0, 2));
        let mut at: u32 = 3;
        let set = if location.target == 0 {
            InternalTrait::bitmap(parts.slice(2, 1))
        } else {
            self.get_outline_chunks(slot)
        };
        let mut packs: Array<(u16, Pack)> = array![];
        for id in templates.span() {
            let record = parts.slice(at, 1);
            at += 1;
            if exists(record) {
                packs.append(((*id).try_into().unwrap(), PackRecord::unpack(record)));
            }
        }
        let mut skill_sheets: Array<SkillSheet> = array![];
        for id in skills.span() {
            let record = parts.slice(at, 2);
            at += 2;
            if exists(record) {
                skill_sheets.append(SkillSheetTrait::read((*id).try_into().unwrap(), record));
            }
        }
        let mut potion_sheets: Array<PotionSheet> = array![];
        for id in potions.span() {
            // An `ITEM` record is one part.
            let record = parts.slice(at, 1);
            at += 1;
            if exists(record) {
                potion_sheets.append(PotionSheetTrait::read(*id, record));
            }
        }
        // [Read] The goblins: the roster's, then the area chunks', stored or derived
        let roster = Self::roster(@self, slot, header.roster_count);
        let mut stored: Array<GoblinWords> = array![];
        for entity in roster.span() {
            let (state, timers) = self.get_goblin_words(slot, *entity);
            stored.append(GoblinWords { entity: *entity, awake: false, state, timers });
        }
        // The castes the goblins need, second call
        let mut castes: Array<u32> = array![];
        let mut derived: Array<(u16, u8, u8, u8, u16, u8, u8)> = array![];
        for (chunk, features) in ground.span() {
            let mut p: u8 = 0;
            for pack in features.packs.span() {
                let template = Self::template(packs.span(), *pack.template);
                let mut i: u8 = 0;
                while i < *pack.count {
                    let k = 5 * p + i;
                    let entity = goblin_entity(*chunk, k);
                    if Bits::has((*features.touched).into(), k) {
                        if !Self::listed(roster.span(), entity) {
                            let (state, timers) = self.get_goblin_words(slot, entity);
                            stored.append(GoblinWords { entity, awake: false, state, timers });
                        }
                    } else if let Some(template) = template {
                        let caste = template.caste(*pack.count, i);
                        InternalTrait::add(ref castes, caste);
                        let offset = Self::offset(*pack.offsets, i);
                        let (gx, gy) = Self::spawn(*chunk, *pack.tile, offset);
                        derived.append((entity, gx, gy, *pack.alert, caste, *pack.level, 0));
                    }
                    i += 1;
                }
                p += 1;
            }
        }
        for goblin in stored.span() {
            InternalTrait::add(ref castes, Self::caste_of(*goblin.state));
        }
        let mut requests: Array<(u8, u32)> = array![];
        for id in castes.span() {
            requests.append((CASTE, *id));
        }
        let mut caste_sheets: Array<CasteSheet> = array![];
        let mut more: Array<u32> = array![];
        if requests.len() > 0 {
            let (_, _, parts) = registry.bundle(requests.span());
            let mut at: u32 = 0;
            for id in castes.span() {
                let record = parts.slice(at, 2);
                at += 2;
                if exists(record) {
                    let sheet = CasteSheetTrait::read((*id).try_into().unwrap(), record);
                    for skill in sheet.skills.span() {
                        let id: u32 = (*skill).into();
                        if id != 0 && !Self::has(skills.span(), id) {
                            Self::push(ref more, id);
                        }
                    }
                    caste_sheets.append(sheet);
                }
            }
        }
        for goblin in stored.span() {
            let effect = Self::effect_of(*goblin.timers);
            if effect != 0 && !Self::has(skills.span(), effect) {
                Self::push(ref more, effect);
            }
        }
        // Their skills, third call (32 records a call at most)
        let mut from: u32 = 0;
        while from < more.len() {
            let count = if more.len() - from > 32 {
                32
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
                    skill_sheets.append(SkillSheetTrait::read((*id).try_into().unwrap(), record));
                }
            }
            from += count;
        }
        let content = Content {
            skills: skill_sheets.span(), potions: potion_sheets.span(), castes: caste_sheets.span(),
        };
        // The derived goblins at full health, their pack's state
        let mut goblins: Array<GoblinWords> = array![];
        let mut all: Array<GoblinWords> = array![];
        // A goblin whose caste, a skill of its caste or its held effect's skill the registry does
        // not hold is left out of the batch's world: it is neither read nor written (the tick's
        // load would refuse it).
        let held = skill_sheets.span();
        for entry in derived.span() {
            let (entity, gx, gy, alert, caste, level, _) = *entry;
            if let Some(sheet) = Self::usable(caste_sheets.span(), held, caste, 0) {
                let state = LIVE
                    + gx.into()
                    + gy.into() * P8
                    + alert.into() * P24
                    + sheet.max_health(level).into() * P32
                    + (sheet.energy * 3).into() * P48
                    + caste.into() * P64
                    + level.into() * P80;
                all.append(GoblinWords { entity, awake: false, state, timers: EMPTY_TIMERS });
            }
        }
        for goblin in stored.span() {
            let caste = Self::caste_of(*goblin.state);
            let effect = Self::effect_of(*goblin.timers);
            if Self::usable(caste_sheets.span(), held, caste, effect).is_some() {
                all.append(*goblin);
            }
        }
        // Ascending entity id, as the tick takes them
        let mut last: u32 = 0;
        let mut first = true;
        while goblins.len() < all.len() {
            let mut least: u32 = 0x10000;
            let mut pick: Option<GoblinWords> = None;
            for goblin in all.span() {
                let e: u32 = (*goblin.entity).into();
                if (first || e > last) && e < least {
                    least = e;
                    pick = Some(*goblin);
                }
            }
            match pick {
                Some(goblin) => goblins.append(goblin),
                None => { break; },
            }
            last = least;
            first = false;
        }
        let actions = match decode_batch(actions) {
            Some(actions) => actions,
            None => {
                self.played(instance_id, adventurer_id, sequence, @header, 0, Stop::Invalid, version);
                return;
            },
        };
        let area = Self::area(@self, slot, @location, set, revealed, @ground);
        let read = Read {
            header, location, area, ground, goblins: goblins.span(), roster,
        };
        self.run(instance_id, adventurer_id, sequence, version, slot, member, members, content, actions.span(), read);
    }

    /// The segments, the reveals between them, the write-back and the events.
    fn run(
        ref self: InstancesState,
        instance_id: InstanceId,
        adventurer_id: u32,
        sequence: u32,
        version: u32,
        slot: u32,
        member: u8,
        members: Array<MemberWords>,
        content: Content,
        actions: Span<Action>,
        read: Read,
    ) {
        let Read { mut header, location, mut area, ground, goblins, mut roster } = read;
        let mut words = Words {
            clock: header.clock,
            members,
            goblins: Self::copy(goblins),
            killed: array![],
            defeated: false,
        };
        let initial = ground.span();
        let mut ground = Self::copy_ground(initial);
        let classes = Classes {
            executor: self.get_play_class(play_class::EXECUTOR),
            ai: self.get_play_class(play_class::AI),
            trap: self.get_trap_library(),
            action: self.get_play_class(play_class::ACTION),
            tick: self.get_play_class(play_class::TICK),
        };
        let segment = ISegmentLibraryLibraryDispatcher {
            class_hash: self.get_play_class(play_class::SEGMENT),
        };
        let mut start: u32 = 0;
        let mut owed: u8 = 0;
        let mut weight = MAX_WEIGHT;
        let mut played: u8 = 0;
        let mut stop = Stop::None;
        let mut revealed: Array<u8> = array![];
        loop {
            // One call a segment: the words go in and come back, never loaded here (D-236)
            let (out, next, done) = segment
                .segment(
                    words,
                    content,
                    area,
                    classes,
                    location.level_min,
                    ground,
                    actions.slice(start, actions.len() - start),
                    owed,
                    weight,
                );
            words = out;
            ground = next;
            played += done.played;
            start += done.played.into();
            weight = done.weight;
            owed = done.owed;
            if done.illegal.is_some() {
                stop = Stop::Invalid;
                break;
            }
            if done.heavy {
                stop = Stop::Weight;
                break;
            }
            if words.defeated {
                stop = Stop::Defeated;
                break;
            }
            if !done.reveal {
                break;
            }
            // Between two segments: the chunks sight touches revealed, the area moved
            let (x, y) = Self::place(*words.members[member.into()].state);
            let mut chunks: Array<u8> = array![];
            for chunk in SightTrait::chunks(x, y, area.width, area.height) {
                if Bits::has(area.known, chunk) && !Bits::has(area.revealed, chunk) {
                    chunks.append(chunk);
                }
            }
            if chunks.len() > 0 {
                let cost: u8 = 2 * chunks.len().try_into().unwrap();
                weight = if weight > cost {
                    weight - cost
                } else {
                    0
                };
                self.reveal(slot, instance_id, ref header, @location, ref area, ref ground, chunks.span());
                for chunk in chunks {
                    revealed.append(chunk);
                }
            }
            let more = Self::ground(@self, slot, area.revealed, x, y);
            for (chunk, features) in more {
                if !Self::holds(ground.span(), chunk) {
                    ground.append((chunk, features));
                }
            }
            area = Self::area(@self, slot, @location, area.known, area.revealed, @ground);
        };
        let out = words;
        // [Effect] The words written back
        let mut m: u8 = 0;
        for words in out.members.span() {
            self.set_member_words(slot, m, *words.state, *words.timers, *words.effects, *words.recharges);
            m += 1;
        }
        let mut k: u32 = 0;
        for after in out.goblins.span() {
            let before = goblins[k];
            if *after.state != *before.state || *after.timers != *before.timers {
                self.set_goblin_words(slot, *after.entity, *after.state, *after.timers);
                let spawn = Self::spawn_chunk(*after.entity);
                let bit = Self::k_of(*after.entity);
                Self::touch(ref self, slot, ref ground, spawn, bit);
                let (gx, gy) = Self::place_goblin(*after.state);
                let here: u8 = (gy / 15) * 15 + gx / 15;
                let listed = Self::listed(roster.span(), *after.entity);
                if here != spawn && !listed && roster.len() < 60 {
                    roster.append(*after.entity);
                }
            }
            k += 1;
        }
        for (chunk, features) in ground.span() {
            let mut changed = true;
            for (c, before) in initial {
                if *c == *chunk {
                    changed = *features != *before;
                    break;
                }
            }
            if changed {
                self.set_features(slot, *chunk, StorePacking::pack(*features));
            }
        }
        if roster.len() != header.roster_count.into() {
            Self::write_roster(ref self, slot, roster.span());
        }
        let header = Header {
            sequence: header.sequence + played.into(),
            clock: out.clock,
            roster_count: roster.len().try_into().unwrap(),
            ..header
        };
        self.set_header(slot, header);
        // [Interaction] The events
        for entity in out.killed.span() {
            let (caste, tile) = Self::killed(out.goblins.span(), *entity);
            self.emit(GoblinKilled { instance_id, entity: *entity, caste, tile, by: 0 });
        }
        for chunk in revealed {
            self.emit(ChunkRevealed { instance_id, chunk });
        }
        self.played(instance_id, adventurer_id, sequence, @header, played, stop, version);
        if out.defeated {
            self.emit(Defeated { instance_id, adventurer_id });
            let placement = self.get_placement(adventurer_id);
            let state: MemberState = StorePacking::unpack(*out.members[member.into()].state);
            self.close(instance_id, slot, header, placement, state, Outcome::Defeated, 0, 0);
        }
    }

    /// `BatchPlayed` (always, ENG-01 §4.1).
    fn played(
        ref self: InstancesState,
        instance_id: InstanceId,
        adventurer_id: u32,
        from: u32,
        header: @Header,
        played: u8,
        stop: Stop,
        version: u32,
    ) {
        self
            .emit(
                BatchPlayed {
                    instance_id,
                    adventurer_id,
                    from,
                    played,
                    stop,
                    sequence: *header.sequence,
                    clock: *header.clock,
                    version,
                },
            );
    }

    /// Reveals `chunks` in play (ENG-05's engine, `create`'s path): the location's site, the
    /// progress from the stored quotas; a zone's hosts from the stored bitmaps of the quotas the
    /// generation counts only (a reused slot's stale bitmaps never read, A7), a dungeon floor's
    /// outline and hosts from storage, drawing nothing (A8, D-229). Writes the chunks, the revealed
    /// set, the header's count and the quotas; adds the chunks to the area and the ground.
    fn reveal(
        ref self: InstancesState,
        slot: u32,
        instance_id: InstanceId,
        ref header: Header,
        location: @Location,
        ref area: Area,
        ref ground: Array<(u8, Features)>,
        chunks: Span<u8>,
    ) {
        let read: u8 = if header.tasks < 8 {
            header.tasks
        } else {
            8
        };
        let tasks = self.get_tasks(slot, read);
        let mut site = self
            .site(header.location, location, header.entry_chunk, header.entry_tile, tasks, chunks);
        let entropy = self.get_entropy(slot);
        let start = ProgressTrait::new(@site, entropy);
        let mut hosts: Array<felt252> = array![];
        let mut quota: u8 = 0;
        for count in start.left.span() {
            hosts.append(if *count > 0 {
                self.get_hosts(slot, quota)
            } else {
                0
            });
            quota += 1;
        }
        let hosts = hosts.span();
        let mut masks: Array<(u8, felt252)> = array![];
        if *location.target != 0 {
            let (set, west, north) = self.get_outline(slot);
            site.chunk_set = set;
            site.west = west;
            site.north = north;
            for chunk in chunks {
                masks.append((*chunk, QuotaPlacementTrait::with_hosts(0, hosts, *chunk)));
            }
        } else {
            for (chunk, mask) in site.masks {
                masks.append((*chunk, QuotaPlacementTrait::with_hosts(*mask, hosts, *chunk)));
            }
        }
        site.masks = masks.span();
        let progress = self
            .get_quotas(slot)
            .model()
            .progress(area.revealed, header.revealed_count, entropy);
        // The terrain of every revealed neighbour of the chunks (their seams)
        let mut known: Array<(u8, Terrain)> = array![];
        for chunk in chunks {
            let (cy, cx) = DivRem::div_rem(*chunk, 15);
            let mut around: Array<u8> = array![];
            if cx > 0 {
                around.append(*chunk - 1);
            }
            if cx < 14 {
                around.append(*chunk + 1);
            }
            if cy > 0 {
                around.append(*chunk - 15);
            }
            if cy < 14 {
                around.append(*chunk + 15);
            }
            for near in around {
                if Bits::has(area.revealed, near) && !Self::knows(known.span(), near) {
                    known.append((near, self.get_terrain(slot, near)));
                }
            }
        }
        let (progress, out) = IRevealLibraryLibraryDispatcher { class_hash: self.get_reveal() }
            .reveal(site, progress, instance_id.into(), known.span(), chunks);
        for chunk in out {
            let (index, terrain, features) = *chunk;
            self.set_chunk(slot, index, terrain, features);
            ground.append((index, StorePacking::unpack(features)));
        }
        header = Header { revealed_count: progress.count, ..header };
        area.revealed = progress.revealed;
        self.set_revealed(slot, Bitmap { bits: progress.revealed });
        self.set_quotas(slot, QuotasTrait::from_progress(*location.target, @progress));
    }

    /// The `Features` of the revealed chunks of the 3 × 3 around the tile `(x, y)`'s chunk.
    fn ground(self: @InstancesState, slot: u32, revealed: felt252, x: u8, y: u8) -> Array<(u8, Features)> {
        let mut ground: Array<(u8, Features)> = array![];
        for chunk in Self::around(x, y) {
            if Bits::has(revealed, chunk) {
                let (_, features) = self.get_chunk_words(slot, chunk);
                ground.append((chunk, StorePacking::unpack(features)));
            }
        }
        ground
    }

    /// The area of the batch: the location's extent, its chunks not void (a zone's set within its
    /// rectangle, a floor's outline), the revealed set, the walkable tiles of the revealed chunks
    /// of `ground`.
    fn area(
        self: @InstancesState,
        slot: u32,
        location: @Location,
        set: felt252,
        revealed: felt252,
        ground: @Array<(u8, Features)>,
    ) -> Area {
        let mut known: felt252 = 0;
        let mut cy: u8 = 0;
        while cy < *location.height {
            let mut cx: u8 = 0;
            while cx < *location.width {
                let chunk = cy * 15 + cx;
                if set == 0 || Bits::has(set, chunk) {
                    known += Self::pow(chunk);
                }
                cx += 1;
            }
            cy += 1;
        }
        let mut chunks: Array<(u8, felt252)> = array![];
        for (chunk, _) in ground.span() {
            let terrain = self.get_terrain(slot, *chunk);
            chunks.append((*chunk, TILES - terrain.walls));
        }
        Area {
            width: *location.width,
            height: *location.height,
            known,
            revealed,
            chunks: chunks.span(),
        }
    }

    /// The 3 × 3 chunks around the tile `(x, y)`'s, inside the 15 × 15 grid.
    fn around(x: u8, y: u8) -> Array<u8> {
        let (cx, cy) = (x / 15, y / 15);
        let mut out: Array<u8> = array![];
        let mut dy: u8 = 0;
        while dy < 3 {
            let mut dx: u8 = 0;
            while dx < 3 {
                if cx + dx >= 1 && cy + dy >= 1 && cx + dx <= 15 && cy + dy <= 15 {
                    out.append((cy + dy - 1) * 15 + cx + dx - 1);
                }
                dx += 1;
            }
            dy += 1;
        }
        out
    }

    /// The roster's entities, masked (F-13).
    fn roster(self: @InstancesState, slot: u32, count: u8) -> Array<u16> {
        let mut out: Array<u16> = array![];
        let lanes: u32 = ROSTER_LANES.into();
        let pages: u32 = (count.into() + lanes - 1) / lanes;
        let mut page: u32 = 0;
        while page < pages {
            let index: u8 = page.try_into().unwrap();
            let lanes = RosterTrait::mask(self.get_roster_page(slot, index), index, count);
            for lane in lanes.lanes.span() {
                if *lane != 0 {
                    out.append(*lane);
                }
            }
            page += 1;
        }
        out
    }

    /// The roster as a compact list, page by page.
    fn write_roster(ref self: InstancesState, slot: u32, roster: Span<u16>) {
        let mut page: u8 = 0;
        let mut from: u32 = 0;
        while from < roster.len() {
            let mut lanes: Array<u16> = array![];
            let mut k: u32 = 0;
            while k < 15 {
                lanes.append(if from + k < roster.len() {
                    *roster[from + k]
                } else {
                    0
                });
                k += 1;
            }
            self
                .set_roster_page(
                    slot,
                    page,
                    Lanes16 {
                        lanes: [
                            *lanes[0], *lanes[1], *lanes[2], *lanes[3], *lanes[4], *lanes[5],
                            *lanes[6], *lanes[7], *lanes[8], *lanes[9], *lanes[10], *lanes[11],
                            *lanes[12], *lanes[13], *lanes[14],
                        ],
                    },
                );
            from += 15;
            page += 1;
        }
    }

    /// Sets the `touched` bit `k` of `chunk` (in the ground, else in storage).
    fn touch(ref self: InstancesState, slot: u32, ref ground: Array<(u8, Features)>, chunk: u8, k: u8) {
        let bit: u16 = Self::pow16(k);
        let mut next: Array<(u8, Features)> = array![];
        let mut found = false;
        for (c, features) in ground.span() {
            let mut features = *features;
            if *c == chunk {
                found = true;
                if features.touched & bit == 0 {
                    features.touched += bit;
                }
            }
            next.append((*c, features));
        }
        ground = next;
        if !found {
            let (_, word) = self.get_chunk_words(slot, chunk);
            let mut features: Features = StorePacking::unpack(word);
            if features.touched & bit == 0 {
                features.touched += bit;
                self.set_features(slot, chunk, StorePacking::pack(features));
            }
        }
    }

    /// The skills and potions a member's load needs: its bar's, its held effects' carriers.
    fn member_content(words: @MemberWords, ref skills: Array<u32>, ref potions: Array<u32>) {
        let mut slot: u8 = 0;
        while slot < 8 {
            let id = MemberTrait::bar_skill(*words.bar, slot);
            if id != 0 {
                InternalTrait::add(ref skills, id);
            }
            slot += 1;
        }
        let mut slot: u16 = 0;
        while slot < 4 {
            let item = MemberWordsTrait::kit_item(*words.kit, slot);
            if item != 0 {
                Self::push_unique(ref potions, item);
            }
            let held = MemberWordsTrait::held(*words.effects, slot.try_into().unwrap());
            if !held.potion && held.carrier != 0 {
                InternalTrait::add(ref skills, held.carrier);
            }
            slot += 1;
        }
    }

    /// The pack template `id` read, if the registry holds it.
    fn template(packs: Span<(u16, Pack)>, id: u16) -> Option<Pack> {
        for (template, pack) in packs {
            if *template == id {
                return Some(*pack);
            }
        }
        None
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

    #[inline(always)]
    fn spawn_chunk(entity: u16) -> u8 {
        ((entity - 8) / 16).try_into().unwrap()
    }

    #[inline(always)]
    fn k_of(entity: u16) -> u8 {
        ((entity - 8) % 16).try_into().unwrap()
    }

    /// A member's tile from its `MemberState` (x 32–39, y 40–47).
    fn place(state: felt252) -> (u8, u8) {
        let wide: u256 = state.into();
        let x = (wide.low / 0x100000000) % 0x100;
        let y = (wide.low / 0x10000000000) % 0x100;
        (x.try_into().unwrap(), y.try_into().unwrap())
    }

    /// A goblin's tile from its `GoblinState` (x 0–7, y 8–15).
    fn place_goblin(state: felt252) -> (u8, u8) {
        let wide: u256 = state.into();
        ((wide.low % 0x100).try_into().unwrap(), ((wide.low / 0x100) % 0x100).try_into().unwrap())
    }

    /// A goblin's caste from its `GoblinState` (64–79).
    fn caste_of(state: felt252) -> u16 {
        let wide: u256 = state.into();
        ((wide.low / 0x10000000000000000) % 0x10000).try_into().unwrap()
    }

    /// A goblin's effect skill from its `GoblinTimers` (108–123).
    fn effect_of(timers: felt252) -> u32 {
        let wide: u256 = timers.into();
        ((wide.low / 0x1000000000000000000000000000) % 0x10000).try_into().unwrap()
    }

    /// A killed goblin's caste and tile (`x + 256 y`).
    fn killed(goblins: Span<GoblinWords>, entity: u16) -> (u16, u16) {
        for goblin in goblins {
            if *goblin.entity == entity {
                let (x, y) = Self::place_goblin(*goblin.state);
                return (Self::caste_of(*goblin.state), x.into() + 256 * y.into());
            }
        }
        (0, 0)
    }

    fn listed(roster: Span<u16>, entity: u16) -> bool {
        for e in roster {
            if *e == entity {
                return true;
            }
        }
        false
    }

    fn holds(ground: Span<(u8, Features)>, chunk: u8) -> bool {
        for (c, _) in ground {
            if *c == chunk {
                return true;
            }
        }
        false
    }

    fn knows(known: Span<(u8, Terrain)>, chunk: u8) -> bool {
        for (c, _) in known {
            if *c == chunk {
                return true;
            }
        }
        false
    }

    fn has(ids: Span<u32>, id: u32) -> bool {
        for i in ids {
            if *i == id {
                return true;
            }
        }
        false
    }

    fn push(ref ids: Array<u32>, id: u32) {
        if !Self::has(ids.span(), id) {
            ids.append(id);
        }
    }

    fn push_unique(ref ids: Array<u32>, id: u32) {
        Self::push(ref ids, id);
    }

    fn pow(n: u8) -> felt252 {
        let mut value: felt252 = 1;
        let mut k: u8 = 0;
        while k < n {
            value *= 2;
            k += 1;
        }
        value
    }

    fn copy_ground(ground: Span<(u8, Features)>) -> Array<(u8, Features)> {
        let mut out = array![];
        out.append_span(ground);
        out
    }

    fn copy(goblins: Span<GoblinWords>) -> Array<GoblinWords> {
        let mut out = array![];
        out.append_span(goblins);
        out
    }

    fn pow16(n: u8) -> u16 {
        let mut value: u16 = 1;
        let mut k: u8 = 0;
        while k < n {
            value *= 2;
            k += 1;
        }
        value
    }
}

use grimworld_logic::actions::Action;
use grimworld_logic::types::Outcome;
