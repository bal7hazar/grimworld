//! `vectors/tick.jsonl` (RV-03c, D-257): the ticks with a fight, `TickLibrary::ticks` as `play`
//! calls it (`SegmentTrait::ticks`): the words loaded through the content, `TickTrait::run` with
//! `Delegate` rules whose step 1 carries through the real `ExecutorLibrary`, whose step 2 runs in
//! the real `AiLibrary` (its carriers through `ExecutorLibrary`, a trap entered through the real
//! `TrapLibrary`), the words and the ground stored back; with its full inputs and outputs, for
//! the client's mirror of the class. And `SegmentTrait::ticks`' choice of path (`skip`): the
//! ticks `play` runs in process, without `TickLibrary`. Row 0 is the table's content. The
//! families, their order and the bounds each row sits on are in `vectors/README.md`.

use core::num::traits::Zero;
use snforge_std::{DeclareResultTrait, declare};
use starknet::ClassHash;
use crate::interface::{ITickLibraryDispatcherTrait, ITickLibraryLibraryDispatcher};
use crate::models::chunk::{Features, FeaturesTrait, Object};
use crate::models::goblin::{
    Goblin, GoblinPlaceTrait, GoblinTickTrait, GoblinTrait, GoblinWordsTrait,
};
use crate::models::member::{Member, MemberTrait, MemberWordsTrait};
use crate::types::combat::{Placer, PlacerTrait, activation, damage, skill_kind, weapon};
use crate::types::effect::{Entry, EntryTrait, filter, kind, shape, target};
use crate::types::executor::tests::body::{emit, finish};
use crate::types::executor::tests::{AT, BRACE, RING, SNARE, board, content, entry, skill, toward};
use crate::types::executor::{Board, BoardTrait};
use crate::types::play::{Classes, SegmentTrait};
use crate::types::tick::{CasteSheet, Content, ContentTrait, Held, PotionSheet, ai, flag, status};
use crate::types::trap::Ground;
use crate::types::window::WindowTrait;
use crate::types::world::fixtures::{Fixture, HOB, MemberSpec, RUNT, two};
use crate::types::world::{TickTrait, Words, WordsTrait, WorldStoreTrait};

/// The clock the words hold: the first tick is `T`.
const CLOCK: u32 = 200;
const T: u32 = 201;
/// The table's own skills, after the executor tests' (ids 80 on): an enchantment holding
/// `REGENERATION` 2 to 6 pips with the rank; a stance granting `BLOCK` 60 to 72 charges with the
/// rank (60 + rank), activation 1.
const MEND: u16 = 80;
const WALL: u16 = 81;
/// The belt's potion 101 (belt slot 1) holds `REGENERATION` 3.
const DRAUGHT: u32 = 101;
/// The level the calls pass (the location band's lower level).
const LEVEL: u8 = 20;

// ---- The table's content, its classes and its world.

/// The executor tests' content (`content(40, …)`: castes of armor 40 and a sword of 30 at rank
/// 12, Brace, Snare, Cinder Ring…), with the castes' skills made the AI's cases, and the table's.
/// Hob (caste 1, `k` 1): slot 0 skill 24, an attack skill of activation 2 and 1 strike (4
/// quarters); slot 1 skill 25, an instant fire spell (40 on a foe, range 2, 5 energy: 15
/// thirds); slot 2 skill 26, an instant trap skill (the AI skips it); slot 3 skill 27, an instant
/// shout on itself, recharge 20 (the fixtures'). Runt (caste 2, `k` 3): slot 0 skill 28, an
/// instant attack skill; slot 1 skill 29, an attack skill of activation 1 (FX-15's recovery,
/// `k ≥ n + 2`); slots 2 and 3 the fixtures'.
fn tick_content() -> Content {
    let none: Entry = Default::default();
    let draught = EntryTrait::new(
        kind::REGENERATION, 0, 3, 3, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    let potions = array![
        PotionSheet { id: DRAUGHT, regen: 3, entry: draught.pack(), ..Default::default() },
    ];
    let base = content(40, potions.span());
    let fire = entry(kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES);
    let trap = entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
    let earth = entry(
        kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
    );
    let mut skills = array![];
    for sheet in base.skills {
        let mut sheet = *sheet;
        if sheet.id == 24 {
            sheet.activation = 2;
            sheet.adrenaline = 1;
        } else if sheet.id == 25 {
            sheet = skill(25, skill_kind::SPELL, 2, [fire, none, none]);
            sheet.activation = 0;
            sheet.recharge = 6;
            sheet.energy = 5;
        } else if sheet.id == 26 {
            sheet = skill(26, skill_kind::TRAP, 3, [trap, earth, none]);
            sheet.activation = 0;
        } else if sheet.id == 28 {
            sheet.activation = 0;
        }
        skills.append(sheet);
    }
    let regen = EntryTrait::new(
        kind::REGENERATION, 0, 2, 6, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    let mut mend = skill(MEND, skill_kind::ENCHANTMENT, 0, [regen, none, none]);
    mend.regen0 = 2;
    mend.regen12 = 6;
    skills.append(mend);
    let block = EntryTrait::new(
        kind::BLOCK, 0, 60, 72, 10, 10, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    skills.append(skill(WALL, skill_kind::STANCE, 0, [block, none, none]));
    let mut castes = array![];
    for caste in base.castes {
        let mut caste = *caste;
        if caste.id == RUNT {
            caste = CasteSheet { weapon_ticks: 3, ..caste };
        }
        castes.append(caste);
    }
    Content { skills: skills.span(), potions: base.potions, castes: castes.span() }
}

#[derive(Drop)]
struct Table {
    tick: ClassHash,
    classes: Classes,
    content: Content,
}

fn class(name: ByteArray) -> ClassHash {
    *declare(name).unwrap().contract_class().class_hash
}

fn table() -> Table {
    Table {
        tick: class("TickLibrary"),
        classes: Classes {
            executor: class("ExecutorLibrary"),
            ai: class("AiLibrary"),
            trap: class("TrapLibrary"),
            action: Zero::zero(),
            tick: Zero::zero(),
        },
        content: tick_content(),
    }
}

/// The adventurer of `spec` on `AT` facing 0: the executor tests' member (level 20, a sword of
/// damage 27, range 1, strength 60, slashing), health 400 of 480, 30 energy thirds of 60
/// regenerating 2 a tick, bar 1–8 at rank 0, belt items 100–103 at count 0.
fn hero_of(spec: MemberSpec) -> Member {
    let mut member = Fixture::member(spec);
    let (x, y) = (AT % 15, AT / 15);
    member.words.state += x.into() * two(32) + y.into() * two(40);
    member.words.stats += 20 * two(64)
        + weapon::SWORD.into() * two(88)
        + 27 * two(96)
        + 1 * two(112)
        + 60 * two(120)
        + damage::SLASHING.into() * two(160)
        + 1 * two(176);
    member
}

fn hero() -> Member {
    hero_of(Fixture::spec())
}

/// The member on `position` instead.
fn moved(member: Member, position: u8) -> Member {
    let mut member = member;
    let (x, y) = (position % 15, position / 15);
    let (ox, oy) = (AT % 15, AT / 15);
    member.words.state += (x.into() - ox.into()) * two(32) + (y.into() - oy.into()) * two(40);
    member
}

/// Skill `id` on bar slot `slot` at `rank` (the words; the class loads them).
fn equip(ref member: Member, slot: u8, id: u16, rank: u8) {
    let old = member.skill(slot);
    member.words.bar += (id.into() - old.into()) * two(16 * slot.into());
    member.words.stats += rank.into() * two(128 + 4 * slot.into());
}

/// Activating bar slot `slot` on `target`, its deadline `deadline`.
fn activating(ref member: Member, slot: u8, target: u16, deadline: u32) {
    member.act_slot = slot;
    member.act_target = target;
    member.act_deadline = deadline;
}

fn holding(ref member: Member, slot: u8, carrier: u16, potion: bool, charges: u8, deadline: u32) {
    member.set_effect(slot, Held { carrier, potion, charges, deadline, rank: 12 }, 0);
}

/// Goblin `entity` of `caste` on `position` facing `facing`, in AI state `state` (awake when
/// neither asleep, on watch nor dead), health 100 of 280, no energy, no adrenaline, level 10.
fn gob(entity: u16, caste: u16, position: u8, facing: u8, state: u8) -> Goblin {
    let mut g = Fixture::goblin(entity, caste);
    let (x, y) = (position % 15, position / 15);
    g.state += x.into() + y.into() * two(8) + facing.into() * two(16);
    g.ai = state;
    g.awake = state != ai::ASLEEP && state != ai::WATCH && state < ai::DEAD;
    g
}

/// A Hob facing the adventurer.
fn hob(entity: u16, position: u8, state: u8) -> Goblin {
    gob(entity, HOB, position, toward(position, AT), state)
}

/// A Hob facing the adventurer with every caste slot recharging to `T` (`t > R` is false): its
/// weapon, or a step.
fn armed(entity: u16, position: u8) -> Goblin {
    let mut g = hob(entity, position, ai::ENGAGED);
    for slot in 0..4_u8 {
        g.set_recharge(slot, T);
    }
    g
}

fn words(members: Array<Member>, goblins: Array<Goblin>) -> Words {
    Fixture::world(CLOCK, members, goblins).store()
}

fn alone(member: Member) -> Words {
    words(array![member], array![])
}

/// The ground: chunk 0, empty.
fn empty() -> Ground {
    array![(0, FeaturesTrait::empty())]
}

/// One `ticks` row: `case` the call's arguments but the content and the classes: `Words`, the
/// `Board`, the level, the ground, `n`; `ok` what it returns: `Words`, the ground.
fn row(
    ref digest: Array<felt252>,
    ref id: u32,
    t: @Table,
    words: Words,
    board: Board,
    ground: Ground,
    n: u8,
) {
    let mut case = array![];
    Serde::serialize(@words, ref case);
    Serde::serialize(@board, ref case);
    case.append(LEVEL.into());
    Serde::serialize(@ground, ref case);
    case.append(n.into());
    let library = ITickLibraryLibraryDispatcher { class_hash: *t.tick };
    let (after, ground) = library.ticks(words, *t.content, board, *t.classes, LEVEL, ground, n);
    let mut ok = array![];
    Serde::serialize(@after, ref ok);
    Serde::serialize(@ground, ref ok);
    emit(ref digest, ref id, "ticks", case.span(), ok.span());
}

/// A row on the open board at the origin, the empty ground.
fn plain(ref digest: Array<felt252>, ref id: u32, t: @Table, words: Words, n: u8) {
    row(ref digest, ref id, t, words, board(), empty(), n);
}

/// One `skip` row: `SegmentTrait::ticks`' path for `n` ticks on `words` and `board`: `case` the
/// `Words`, the `Board`, `n`; `ok` the path (0 `TickLibrary`, 1 the fast path `TickTrait::idle`,
/// 2 none: `n` is 0 or the adventurer defeated), then the `Words` after it (the empty ground).
fn skip(ref digest: Array<felt252>, ref id: u32, t: @Table, words: Words, board: Board, n: u8) {
    let mut case = array![];
    Serde::serialize(@words, ref case);
    Serde::serialize(@board, ref case);
    case.append(n.into());
    let mut ok = array![];
    let (mut world, _, _) = words.clone().indexed(t.content);
    let after = if n == 0 || world.defeated {
        ok.append(2);
        words
    } else if SegmentTrait::idle(@world, @board) {
        ok.append(1);
        TickTrait::idle(ref world, n);
        world.store()
    } else {
        ok.append(0);
        let library = ITickLibraryLibraryDispatcher { class_hash: *t.tick };
        let (after, _) = library.ticks(words, *t.content, board, *t.classes, LEVEL, empty(), n);
        after
    };
    Serde::serialize(@after, ref ok);
    emit(ref digest, ref id, "skip", case.span(), ok.span());
}

/// The board whose window is open but on `position`.
fn walled(position: u8) -> Board {
    BoardTrait::new(
        WindowTrait::new(
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff - two(position.into()),
        ),
        0,
        0,
    )
}

/// The board whose window is open but on `positions`.
fn walls(positions: Array<u8>) -> Board {
    let mut bits: felt252 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    for position in positions {
        bits -= two(position.into());
    }
    BoardTrait::new(WindowTrait::new(bits), 0, 0)
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

// Row 0, the content; the member's steps alone: regeneration and its clamps, energy, the
// conditions, adrenaline's decay, the held `REGENERATION` effects, the flags.
#[test]
#[available_gas(l2_gas: 730628021)] // ceil(1.05 × 695836210 measured)
fn test_tick_vectors_0() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok = array![];
    Serde::serialize(@t.content, ref ok);
    emit(ref digest, ref id, "content", array![].span(), ok.span());
    // Alone, one tick: the clock to `T`, energy 30 → 32.
    plain(ref digest, ref id, @t, alone(hero()), 1);
    // Health regeneration (pips × 2): 3 pips from 400; from 473 (479), 474 (480: the max), 475
    // (481: clamped to 480).
    for health in array![400_u16, 473, 474, 475] {
        let mut spec = Fixture::spec();
        spec.health = health;
        spec.health_regen = 3;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    }
    // The clamp at ±10 pips: 10 (+20) and 11 (clamped: +20); −14 (Bleeding,
    // Poison and Burning: −3 − 4 − 7, clamped to −10: −20) and −10 with a regeneration
    // of 4.
    for (regen, conditions) in array![
        (10_i8, [0_u32, 0, 0, 0]), (11, [0, 0, 0, 0]), (0, [T, T, T, 0]), (4, [T, T, T, 0]),
    ] {
        let mut spec = Fixture::spec();
        spec.health_regen = regen;
        spec.conditions = conditions;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    }
    // Each condition to `T` (held at `T`: −3, −4, −7 pips) and to `T − 1` (ended).
    for conditions in array![
        [T, 0_u32, 0, 0], [T - 1, 0, 0, 0], [0, T, 0, 0], [0, T - 1, 0, 0], [0, 0, T, 0],
        [0, 0, T - 1, 0],
    ] {
        let mut spec = Fixture::spec();
        spec.conditions = conditions;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    }
    // Energy (thirds, 2 a tick, max 60): from 57 (59), 58 (60), 59 (61: clamped to 60), 60.
    for energy in array![57_u16, 58, 59, 60] {
        let mut spec = Fixture::spec();
        spec.energy = energy;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    }
    // Adrenaline's decay out of combat (1 quarter a tick, D-157 E): from 2 (to 1), 1 (to 0), 0
    // (stays 0); from 2 over 3 ticks (1, 0, 0).
    for (adrenaline, n) in array![(2_u16, 1_u8), (1, 1), (0, 1), (2, 3)] {
        let mut spec = Fixture::spec();
        spec.adrenaline = adrenaline;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), n);
    }
    // The flags: `TURNED`, `INSTANT` and `HIT` clear at step 0, `HALVED` is kept.
    let mut spec = Fixture::spec();
    spec.flags = flag::TURNED | flag::INSTANT | flag::HIT | flag::HALVED;
    plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    finish(digest, TICK_DIGEST_0);
}

// The held `REGENERATION` effects (track CV, after #442): the skill's at ranks 12 (6 pips) and 0
// (2), and the potion's (belt slot 1, 3 pips), each held to `T` (it regenerates) and to `T − 1`
// (ended); the clock's bounds; the member steps' stops.
#[test]
#[available_gas(l2_gas: 504807111)] // ceil(1.05 × 480768677 measured)
fn test_tick_vectors_1() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_1;
    for (deadline, rank) in array![(T, 12_u8), (T - 1, 12), (T, 0), (T + 1, 0)] {
        let mut m = hero();
        m.set_effect(0, Held { carrier: MEND, potion: false, charges: 0, deadline, rank }, 0);
        plain(ref digest, ref id, @t, alone(m), 1);
    }
    for deadline in array![T, T - 1] {
        let mut m = hero();
        holding(ref m, 1, 1, true, 0, deadline);
        plain(ref digest, ref id, @t, alone(m), 1);
    }
    // Both, the skill to `T + 1` over 3 ticks: 6 + 3 pips at `T` and `T + 1`, none at `T + 2`
    // past the potion's `T`… the potion's to `T`: 9 pips at `T`, 6 at `T + 1`, 0 at `T + 2`.
    let mut m = hero();
    m
        .set_effect(
            0, Held { carrier: MEND, potion: false, charges: 0, deadline: T + 1, rank: 12 }, 0,
        );
    holding(ref m, 1, 1, true, 0, T);
    plain(ref digest, ref id, @t, alone(m), 3);
    // `n`: 0 (nothing runs), 2, and 10 (the largest `play` passes: an action's ticks are at most
    // the weight, `MAX_WEIGHT`).
    for n in array![0_u8, 2, 10] {
        plain(ref digest, ref id, @t, alone(hero()), n);
    }
    // Stops: the adventurer at 0 before the tick (down, defeated, the clock kept), over 3 ticks;
    // at 1 with Bleeding, Poison and Burning to `T + 5`: down at step 3 of `T`, the 2 ticks after
    // not run; down (status 1) and gone (2) at 400: neither regenerates.
    let mut spec = Fixture::spec();
    spec.health = 0;
    plain(ref digest, ref id, @t, alone(hero_of(spec)), 3);
    let mut spec = Fixture::spec();
    spec.health = 1;
    spec.conditions = [T + 5, T + 5, T + 5, 0];
    plain(ref digest, ref id, @t, alone(hero_of(spec)), 3);
    for state in array![status::DOWN, status::GONE] {
        let mut spec = Fixture::spec();
        spec.status = state;
        spec.health_regen = 3;
        plain(ref digest, ref id, @t, alone(hero_of(spec)), 1);
    }
    // A companion (member 1 on 110) at 0 inside: the tick stops at once, the adventurer
    // defeated (any member inside at 0, FX-8); at 300 with 3 pips, both regenerate.
    for health in array![0_u16, 300] {
        let mut spec = Fixture::spec();
        spec.health = health;
        spec.health_regen = 3;
        let companion = moved(hero_of(spec), AT - 2);
        plain(ref digest, ref id, @t, words(array![hero(), companion], array![]), 1);
    }
    finish(digest, TICK_DIGEST_1);
}

/// Goblin `entity` of `caste` on the location's tile `(x, y)`, facing 0, in AI state `state`.
fn gob_at(entity: u16, x: u8, y: u8, state: u8) -> Goblin {
    let mut g = Fixture::goblin(entity, HOB);
    g.state += x.into() + y.into() * two(8);
    g.ai = state;
    g.awake = state != ai::ASLEEP && state != ai::WATCH && state < ai::DEAD;
    g
}

/// The facing opposite `facing`.
fn back(facing: u8) -> u8 {
    (facing + 3) % 6
}

// Step 0: perception (design/18's table) and the awake set. The goblins on the adventurer's row,
// East of it (`AT + d` is `d` tiles away), chunk 0's (entities 8–12 pack 0, 13–17 pack 1).
#[test]
#[available_gas(l2_gas: 663977683)] // ceil(1.05 × 632359698 measured)
fn test_tick_vectors_2() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_2;
    // Asleep: notices within 2 (wakes Engaged, joins the set and acts), not at 3.
    for d in array![2_u8, 3] {
        plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + d, ai::ASLEEP)]), 1);
    }
    // On watch: within 2 facing away; at 5 facing the adventurer (its front arc), at 6 not
    // (`range::ALERT`); at 5 facing away (its back), not; at 5 its sight blocked by a wall on
    // `AT + 3`, not.
    let mut g = hob(8, AT + 2, ai::WATCH);
    g.set_place(9, 7, back(toward(AT + 2, AT)));
    plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    for d in array![5_u8, 6] {
        plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + d, ai::WATCH)]), 1);
    }
    let mut g = hob(8, AT + 5, ai::WATCH);
    g.set_place(12, 7, back(toward(AT + 5, AT)));
    plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    row(
        ref digest,
        ref id,
        @t,
        words(array![hero()], array![hob(8, AT + 5, ai::WATCH)]),
        walled(AT + 3),
        empty(),
        1,
    );
    // At 5, turned one and two steps from the adventurer: the front-side arc notices, the
    // rear-side does not.
    for turn in array![1_u8, 2] {
        let mut g = hob(8, AT + 5, ai::WATCH);
        g.set_place(12, 7, (toward(AT + 5, AT) + turn) % 6);
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Alerted at 5 (no notice: awake all the same, it steps toward the adventurer); Returning
    // at 1 (awake, does nothing); dead at 1 (neither notices nor wakes).
    plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + 5, ai::ALERTED)]), 1);
    plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + 1, ai::RETURNING)]), 1);
    let mut dead = hob(8, AT + 1, ai::DEAD);
    dead.health = 0;
    plain(ref digest, ref id, @t, words(array![hero()], array![dead]), 1);
    // The pack: goblin 8 on watch at 2 notices; 9 (pack 0) asleep at 7 is engaged with it and
    // acts; 13 (pack 1) asleep at 6 is not.
    let goblins = array![
        hob(8, AT + 2, ai::WATCH), hob(9, AT + 7, ai::ASLEEP), hob(13, AT + 6, ai::ASLEEP),
    ];
    plain(ref digest, ref id, @t, words(array![hero()], goblins), 1);
    // The awake set: nine goblins Alerted, eight awake on the words, on the adventurer's row at
    // 2, 2, 3, 3, 4, 4, 5, 6 and 6 tiles (East and West): the eight nearest, the tie at the
    // set's edge (15 East, 16 West, at 6) to the lower id.
    let mut goblins = array![
        hob(8, AT + 2, ai::ALERTED), hob(9, AT - 2, ai::ALERTED), hob(10, AT + 3, ai::ALERTED),
        hob(11, AT - 3, ai::ALERTED), hob(12, AT + 4, ai::ALERTED), hob(13, AT - 4, ai::ALERTED),
        hob(14, AT + 5, ai::ALERTED), hob(15, AT + 6, ai::ALERTED),
    ];
    let mut last = hob(16, AT - 6, ai::ALERTED);
    last.awake = false;
    goblins.append(last);
    plain(ref digest, ref id, @t, words(array![hero()], goblins), 1);
    // A goblin Engaged outside the window (on (7, 20)): never in the set, it does not act.
    plain(ref digest, ref id, @t, words(array![hero()], array![gob_at(8, 7, 20, ai::ENGAGED)]), 1);
    finish(digest, TICK_DIGEST_2);
}

// Step 2, an Engaged goblin's act: its caste's priority list (slot 0 first: recharging, its
// adrenaline, its energy, its target in range; the trap skill skipped), its weapon in reach, else
// a step. A Hob adjacent East (`AT + 1`) with no energy and no adrenaline, unless a row says.
#[test]
#[available_gas(l2_gas: 633611744)] // ceil(1.05 × 603439756 measured)
fn test_tick_vectors_3() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_3;
    // Slots 0 (4 quarters short), 1 (15 thirds short) and 2 (the trap) skipped: the shout
    // (slot 3, instant, on itself), its recharge from `T`.
    plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + 1, ai::ENGAGED)]), 1);
    // The shout recharging to `T` (refused: `t > R`), to `T − 1` (used).
    for recharge in array![T, T - 1] {
        let mut g = hob(8, AT + 1, ai::ENGAGED);
        g.set_recharge(3, recharge);
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Slot 0, the attack skill (1 strike): adrenaline 4 (it starts, `A = T + 2`, 4 spent), 3
    // (the weapon), 5; slot 0 recharging to `T` with 4 (the weapon) and to `T − 1` (it starts).
    for (adrenaline, recharge) in array![(4_u8, 0_u32), (3, 0), (5, 0), (4, T), (4, T - 1)] {
        let mut g = armed(8, AT + 1);
        g.set_recharge(0, recharge);
        g.adrenaline = adrenaline;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Slot 1, the fire spell (range 2, 15 thirds): energy 15 (it lands now, 0 left, its recharge
    // from `T`), 14 (the weapon); at 2 tiles with 15 (lands), at 3 (out of range and reach: a
    // step).
    for (d, energy) in array![(1_u8, 15_u8), (1, 14), (2, 15), (3, 15)] {
        let mut g = armed(8, AT + d);
        g.set_recharge(1, 0);
        g.energy = energy;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // A Runt (`k` 3): slot 0, the instant attack skill (lands now, recovering to `T + 2`); every
    // slot recharging, its weapon (recovering to `T + 2`).
    let g = gob(8, RUNT, AT + 1, toward(AT + 1, AT), ai::ENGAGED);
    plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    let mut g = gob(8, RUNT, AT + 1, toward(AT + 1, AT), ai::ENGAGED);
    for slot in 0..4_u8 {
        g.set_recharge(slot, T);
    }
    plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    // The weapon on the adventurer (facing 0, toward `AT − 1`): from behind it (`AT + 1`) and
    // from its front (`AT − 1`).
    plain(ref digest, ref id, @t, words(array![hero()], array![armed(8, AT + 1)]), 1);
    plain(ref digest, ref id, @t, words(array![hero()], array![armed(8, AT - 1)]), 1);
    finish(digest, TICK_DIGEST_3);
}

// The weapon hit on a member holding Brace (`BLOCK`) in effect slot 0, the goblin in front of it:
// the block cap (track CV, 2026-10-11) at 63 charges (blocked, to 62) and 62 (to 61); 1 (to 0,
// the effect ended); knocked down to `T` (held: landed, the charges kept) and to `T − 1`
// (blocked); behind it (landed). The grant: Wall (`BLOCK` 60 + rank) concluding at `T` on bar
// slot 0 at ranks 2, 3 and 4: 62, 63 and 64 clamped to 63 (`MAX_BLOCK`), the most a member's
// charges reach. The member's activations: concluding at `T`, overdue (`T − 1`), not yet
// (`T + 1`); down, not concluded; Cinder Ring among three goblins (the carrier through
// `ExecutorLibrary`).
#[test]
#[available_gas(l2_gas: 558762708)] // ceil(1.05 × 532154960 measured)
fn test_tick_vectors_4() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_4;
    for (charges, knocked) in array![(63_u8, 0_u32), (62, 0), (1, 0), (63, T), (63, T - 1)] {
        let mut m = hero();
        holding(ref m, 0, BRACE, false, charges, T + 5);
        m.knocked = knocked;
        plain(ref digest, ref id, @t, words(array![m], array![armed(8, AT - 1)]), 1);
    }
    let mut m = hero();
    holding(ref m, 0, BRACE, false, 63, T + 5);
    plain(ref digest, ref id, @t, words(array![m], array![armed(8, AT + 1)]), 1);
    for rank in array![2_u8, 3, 4] {
        let mut m = hero();
        equip(ref m, 0, WALL, rank);
        activating(ref m, 0, 0, T);
        plain(ref digest, ref id, @t, alone(m), 1);
    }
    // Bar slot 1 (skill 2, recharge 12) on goblin 8 at 1: concluding at `T` (`R = T + 11`),
    // overdue at `T − 1` (`R = T + 10`), at `T + 1` (not yet); down at 400, not concluded.
    for deadline in array![T, T - 1, T + 1] {
        let mut m = hero();
        activating(ref m, 1, 8, deadline);
        plain(ref digest, ref id, @t, words(array![m], array![armed(8, AT + 1)]), 1);
    }
    let mut m = hero();
    activating(ref m, 1, 8, T);
    m.status = status::DOWN;
    plain(ref digest, ref id, @t, words(array![m], array![armed(8, AT + 1)]), 1);
    // Cinder Ring (fire 80, Burning 3 on `RING_1` around the member) at `T` on goblins 8 (East,
    // 90 health), 9 (West, 100) and 10 (on `AT + 15`, 280): 8 and 9 die, in tile
    // order, then 10 burns and acts.
    let mut m = hero();
    equip(ref m, 0, RING, 12);
    activating(ref m, 0, 0, T);
    let mut a = armed(8, AT + 1);
    a.health = 90;
    let b = armed(9, AT - 1);
    let mut c = armed(10, AT + 15);
    c.health = 280;
    plain(ref digest, ref id, @t, words(array![m], array![a, b, c]), 1);
    finish(digest, TICK_DIGEST_4);
}

// The AI's states and the goblins' step 1 and step 3: Alerted, fleeing (a step away; cornered,
// Engaged again), knocked down, an activation concluding, lapsed or not yet, a recovery ending;
// Runt's attack skill concluding into a recovery (FX-15); a goblin dying at step 3; energy,
// adrenaline's decay out of Engaged (track CV's segment2 mutant), the held `REGENERATION`.
#[test]
#[available_gas(l2_gas: 930198842)] // ceil(1.05 × 885903659 measured)
fn test_tick_vectors_5() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_5;
    // Fleeing at 2: a step away. Every tile around it walled but `AT + 1`, nearer the
    // adventurer: its one free neighbour, it steps there, still fleeing. Every tile around it
    // walled: cornered (no step), Engaged again.
    plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + 2, ai::FLEEING)]), 1);
    let around = crate::types::executor::tests::ring(AT + 2);
    let mut blocked = array![];
    let mut all = array![];
    for tile in around {
        if *tile != AT + 1 {
            blocked.append(*tile);
        }
        all.append(*tile);
    }
    for walled in array![blocked, all] {
        row(
            ref digest,
            ref id,
            @t,
            words(array![hero()], array![hob(8, AT + 2, ai::FLEEING)]),
            walls(walled),
            empty(),
            1,
        );
    }
    // Knocked down to `T` (no act), to `T − 1` (it acts).
    for knocked in array![T, T - 1] {
        let mut g = armed(8, AT + 1);
        g.knocked = knocked;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Slot 0 (24, recharge 10) activating on the adventurer: concluding at `T` (its weapon hit,
    // `R = T + 9`, no act after); lapsed from `T − 1` (FX-29: `R = T + 8`, then it acts); `T + 1`
    // (busy). Recovering to `T − 1` (cleared, it acts) and to `T` (busy).
    for deadline in array![T, T - 1, T + 1] {
        let mut g = hob(8, AT + 1, ai::ENGAGED);
        g.start(0, 0, 1, deadline - 1);
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    for deadline in array![T - 1, T] {
        let mut g = hob(8, AT + 1, ai::ENGAGED);
        g.act_slot = activation::RECOVERING;
        g.act_deadline = deadline;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // A Runt's slot 1 (29, activation 1, `k` 3 ≥ 1 + 2) concluding at `T`: recovering to
    // `T + 1`.
    let mut g = gob(8, RUNT, AT + 1, toward(AT + 1, AT), ai::ENGAGED);
    g.start(1, 0, 1, T - 1);
    plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    // Step 3: at 1 with Bleeding to `T` (dies: `DEAD`, in `killed`); to `T − 1` (lives).
    for bleeding in array![T, T - 1] {
        let mut g = hob(8, AT + 6, ai::ALERTED);
        g.health = 1;
        g.bleeding = bleeding;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Energy (1 a tick, max 30 thirds): from 29 and from 30; adrenaline Alerted (decays) from 2
    // and 1, Engaged (kept) from 2; the adventurer's adrenaline 2 beside an Engaged goblin
    // (kept: in combat) and beside an Alerted one (decays).
    for (energy, adrenaline, state) in array![
        (29_u8, 0_u8, ai::ALERTED), (30, 0, ai::ALERTED), (0, 2, ai::ALERTED), (0, 1, ai::ALERTED),
        (0, 2, ai::ENGAGED),
    ] {
        let mut g = hob(8, AT + 6, state);
        g.energy = energy;
        g.adrenaline = adrenaline;
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    for state in array![ai::ENGAGED, ai::ALERTED] {
        let mut spec = Fixture::spec();
        spec.adrenaline = 2;
        plain(
            ref digest, ref id, @t, words(array![hero_of(spec)], array![hob(8, AT + 6, state)]), 1,
        );
    }
    // A goblin holding the `REGENERATION` skill (rank 12, 6 pips) to `T` and to `T − 1`.
    for deadline in array![T, T - 1] {
        let mut g = hob(8, AT + 6, ai::ALERTED);
        g.set_effect(Held { carrier: MEND, potion: false, charges: 0, deadline, rank: 12 }, 0);
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    // Crippled to `T` (its step costs 2: recovering to `T + 1`) and to `T − 1` (1).
    for crippled in array![T, T - 1] {
        let mut g = hob(8, AT + 3, ai::ALERTED);
        g.set_crippled(crippled);
        plain(ref digest, ref id, @t, words(array![hero()], array![g]), 1);
    }
    finish(digest, TICK_DIGEST_5);
}

// Goblin order and the hooks over one goblin: two goblins stepping toward the same tiles, by
// ascending id (and the ids swapped); an asleep goblin's tile blocking a step; a member's trap
// entered (`TrapLibrary`), a terrain trap not (FX-34); the same goblin written by step 1, step 2
// and step 3 of one tick, and over two ticks (track CV's `fits` mutant); a defeat in step 1 and in
// step 2.
#[test]
#[available_gas(l2_gas: 394639866)] // ceil(1.05 × 375847491 measured)
fn test_tick_vectors_6() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_6;
    // Goblins 8 and 9 Alerted on `AT + 2` and `AT + 2 − 15` (rows 7 and 6), the tile West of
    // the second walled (`AT + 1 − 15`): both would step onto `AT + 1`; the lower id first, then
    // the ids swapped.
    for (first, second) in array![(8_u16, 9_u16), (9, 8)] {
        let goblins = if first < second {
            array![hob(first, AT + 2, ai::ALERTED), hob(second, AT + 2 - 15, ai::ALERTED)]
        } else {
            array![hob(second, AT + 2 - 15, ai::ALERTED), hob(first, AT + 2, ai::ALERTED)]
        };
        row(
            ref digest, ref id, @t, words(array![hero()], goblins), walled(AT + 1 - 15), empty(), 1,
        );
    }
    // Goblin 8 Alerted at 5; 13 (pack 1) asleep on `AT + 4`, the tile it would take (frozen:
    // not awake, its tile occupied).
    let goblins = array![hob(8, AT + 5, ai::ALERTED), hob(13, AT + 4, ai::ASLEEP)];
    plain(ref digest, ref id, @t, words(array![hero()], goblins), 1);
    // Goblin 8 Alerted at 3 steps onto `AT + 2`, holding the member's Snare (bar slot 0, placer
    // `(0, 0)`): it triggers through `TrapLibrary` (earth 10 to 40, Crippled 3; the trap used);
    // a terrain trap (skill 45) there: nothing (FX-34).
    let mut m = hero();
    equip(ref m, 0, SNARE, 12);
    let placer: u16 = Placer::Member((0, 0)).param();
    for (kind, param) in array![
        (crate::models::chunk::object::PLACED_TRAP, placer),
        (crate::models::chunk::object::TRAP, SNARE),
    ] {
        let trap = Object { tile: AT + 2, kind, state: 0, param };
        let ground = array![
            (
                0,
                Features {
                    objects: [trap, Default::default(), Default::default()],
                    ..FeaturesTrait::empty(),
                },
            ),
        ];
        row(
            ref digest,
            ref id,
            @t,
            words(array![m], array![hob(8, AT + 3, ai::ALERTED)]),
            board(),
            ground,
            1,
        );
    }
    // The same goblin three times in one tick: Cinder Ring concluding at `T` strikes goblin 8
    // (280 health, Burning 3), it acts in step 2 (its weapon), Burning and its regeneration at
    // step 3. Goblin 8 Alerted at 5 over 2 ticks: two steps.
    let mut m = hero();
    equip(ref m, 0, RING, 12);
    activating(ref m, 0, 0, T);
    let mut g = armed(8, AT + 1);
    g.health = 280;
    plain(ref digest, ref id, @t, words(array![m], array![g]), 1);
    plain(ref digest, ref id, @t, words(array![hero()], array![hob(8, AT + 5, ai::ALERTED)]), 2);
    // Defeats: goblin 8's attack skill concluding at `T` on the adventurer at 1 (down at step
    // 1: no step 2 or 3, the 2 ticks after not run); goblin 8's weapon at step 2 on it at 1:
    // goblin 9 (adjacent, `AT − 1`) does not act after it.
    let mut spec = Fixture::spec();
    spec.health = 1;
    let mut g = hob(8, AT + 1, ai::ENGAGED);
    g.start(0, 0, 1, T - 1);
    plain(ref digest, ref id, @t, words(array![hero_of(spec)], array![g]), 3);
    plain(
        ref digest,
        ref id,
        @t,
        words(array![hero_of(spec)], array![armed(8, AT + 1), armed(9, AT - 1)]),
        3,
    );
    finish(digest, TICK_DIGEST_6);
}

// `skip`: `SegmentTrait::ticks`' path. The fast path (no member activating, no goblin awake, no
// living goblin in the window) runs in process; `n` 0 and a defeated adventurer run nothing.
#[test]
#[available_gas(l2_gas: 273627793)] // ceil(1.05 × 260597898 measured)
fn test_tick_vectors_7() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_7;
    // Alone: the fast path, 1 and 10 ticks; `n` 0: none; defeated: none.
    for n in array![1_u8, 10, 0] {
        skip(ref digest, ref id, @t, alone(hero()), board(), n);
    }
    let mut w = alone(hero());
    w.defeated = true;
    skip(ref digest, ref id, @t, w, board(), 1);
    // Activating (bar slot 1 to `T + 3`): `TickLibrary`.
    let mut m = hero();
    activating(ref m, 1, 0, T + 3);
    skip(ref digest, ref id, @t, alone(m), board(), 1);
    // Outside the window (on (7, 20)): Engaged and awake, `TickLibrary` (not calm); asleep, the
    // fast path. Inside it (`AT + 6`): asleep or on watch, `TickLibrary` (a living goblin in the
    // window); dead, the fast path.
    for state in array![ai::ENGAGED, ai::ASLEEP] {
        skip(
            ref digest,
            ref id,
            @t,
            words(array![hero()], array![gob_at(8, 7, 20, state)]),
            board(),
            1,
        );
    }
    for state in array![ai::ASLEEP, ai::WATCH] {
        skip(
            ref digest,
            ref id,
            @t,
            words(array![hero()], array![hob(8, AT + 6, state)]),
            board(),
            1,
        );
    }
    let mut dead = hob(8, AT + 6, ai::DEAD);
    dead.health = 0;
    skip(ref digest, ref id, @t, words(array![hero()], array![dead]), board(), 1);
    finish(digest, TICK_DIGEST_7);
}

// The roster (D-238): goblin 248 (spawn chunk 15) Alerted on (7, 15), the adventurer on (7, 12)
// in chunk 0: its step leaves its spawn chunk and needs a roster entry. With 59 other goblins
// away from theirs (asleep on (100, 100), chunk 96: entities 24–33, 40–49, … of spawn chunks
// 1–6, outside the window), it steps; with 60, the roster is full: it holds its tile.
#[test]
#[available_gas(l2_gas: 640669436)] // ceil(1.05 × 610161367 measured)
fn test_tick_vectors_8() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_8;
    for count in array![59_u32, 60] {
        let mut goblins = array![];
        let mut k: u32 = 0;
        for chunk in 1..7_u16 {
            for slot in 0..10_u16 {
                if k < count {
                    goblins.append(gob_at(8 + 16 * chunk + slot, 100, 100, ai::ASLEEP));
                }
                k += 1;
            }
        }
        goblins.append(gob_at(248, 7, 15, ai::ALERTED));
        plain(ref digest, ref id, @t, words(array![moved(hero(), 187)], goblins), 1);
    }
    finish(digest, TICK_DIGEST_8);
}

/// The first id of each part, and each part's digest.
const TICK_PART_1: u32 = 25;
const TICK_PART_2: u32 = 41;
const TICK_PART_3: u32 = 56;
const TICK_PART_4: u32 = 72;
const TICK_PART_5: u32 = 86;
const TICK_PART_6: u32 = 110;
const TICK_PART_7: u32 = 119;
const TICK_PART_8: u32 = 129;
const TICK_DIGEST_0: felt252 =
    2137715165244208689709745686860470517894582999737742435757522380538417750806;
const TICK_DIGEST_1: felt252 =
    3009609747004963231434613867686976261609972322454295224762689629570822394141;
const TICK_DIGEST_2: felt252 =
    2464070503127361189018990603368040213276236672229521039792042149081524701296;
const TICK_DIGEST_3: felt252 =
    1581361779412042734771451779842351930137153259904382798530372651437484348452;
const TICK_DIGEST_4: felt252 =
    2912501553687549411360605587760355679227582680040058847133387902208105665510;
const TICK_DIGEST_5: felt252 =
    1036532419004570780675448629428909577341028595598302136564481700078945771263;
const TICK_DIGEST_6: felt252 =
    2538157155830053314170061708143468218737540156350474974906820625368615208501;
const TICK_DIGEST_7: felt252 =
    2098845368569173313750160501583154709918690736208069666979095817737906594175;
const TICK_DIGEST_8: felt252 =
    420744539860533300147543818911014254588995874583632251919375290186537202397;
