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
use crate::types::executor::tests::body::BodyFixture;
use crate::types::executor::tests::{AT, BRACE, ExecutorFixture, RING, SNARE};
use crate::types::executor::{Board, BoardTrait};
use crate::types::play::{Classes, SegmentTrait};
use crate::types::tick::{CasteSheet, Content, ContentTrait, Held, PotionSheet, ai, flag, status};
use crate::types::trap::Ground;
use crate::types::window::WindowTrait;
use crate::types::world::fixtures::{Fixture, HOB, MemberSpec, RUNT};
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

#[generate_trait]
impl VectorFixtureImpl of VectorFixture {
    /// The executor tests' content (`content(40, …)`: castes of armor 40 and a sword of 30 at
    /// rank 12, Brace, Snare, Cinder Ring…), with the castes' skills made the AI's cases, and the
    /// table's.
    /// Hob (caste 1, `k` 1): slot 0 skill 24, an attack skill of activation 2 and 1 strike (4
    /// quarters); slot 1 skill 25, an instant fire spell (40 on a foe, range 2, 5 energy: 15
    /// thirds); slot 2 skill 26, an instant trap skill (the AI skips it); slot 3 skill 27, an
    /// instant shout on itself, recharge 20 (the fixtures'). Runt (caste 2, `k` 3): slot 0 skill
    /// 28, an instant attack skill; slot 1 skill 29, an attack skill of activation 1 (FX-15's
    /// recovery, `k ≥ n + 2`); slots 2 and 3 the fixtures'.
    fn tick_content() -> Content {
        let none: Entry = Default::default();
        let draught = EntryTrait::new(
            kind::REGENERATION, 0, 3, 3, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        let potions = array![
            PotionSheet { id: DRAUGHT, regen: 3, entry: draught.pack(), ..Default::default() },
        ];
        let base = ExecutorFixture::content(40, potions.span());
        let fire = ExecutorFixture::entry(
            kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let trap = ExecutorFixture::entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
        let earth = ExecutorFixture::entry(
            kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let mut skills = array![];
        for sheet in base.skills {
            let mut sheet = *sheet;
            if sheet.id == 24 {
                sheet.activation = 2;
                sheet.adrenaline = 1;
            } else if sheet.id == 25 {
                sheet = ExecutorFixture::skill(25, skill_kind::SPELL, 2, [fire, none, none]);
                sheet.activation = 0;
                sheet.recharge = 6;
                sheet.energy = 5;
            } else if sheet.id == 26 {
                sheet = ExecutorFixture::skill(26, skill_kind::TRAP, 3, [trap, earth, none]);
                sheet.activation = 0;
            } else if sheet.id == 28 {
                sheet.activation = 0;
            }
            skills.append(sheet);
        }
        let regen = EntryTrait::new(
            kind::REGENERATION, 0, 2, 6, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        let mut mend = ExecutorFixture::skill(
            MEND, skill_kind::ENCHANTMENT, 0, [regen, none, none],
        );
        mend.regen0 = 2;
        mend.regen12 = 6;
        skills.append(mend);
        let block = EntryTrait::new(
            kind::BLOCK, 0, 60, 72, 10, 10, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        skills.append(ExecutorFixture::skill(WALL, skill_kind::STANCE, 0, [block, none, none]));
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

    fn class(name: ByteArray) -> ClassHash {
        *declare(name).unwrap().contract_class().class_hash
    }

    fn table() -> Table {
        Table {
            tick: Self::class("TickLibrary"),
            classes: Classes {
                executor: Self::class("ExecutorLibrary"),
                ai: Self::class("AiLibrary"),
                trap: Self::class("TrapLibrary"),
                action: Zero::zero(),
                tick: Zero::zero(),
            },
            content: Self::tick_content(),
        }
    }

    /// The adventurer of `spec` on `AT` facing 0: the executor tests' member (level 20, a sword of
    /// damage 27, range 1, strength 60, slashing), health 400 of 480, 30 energy thirds of 60
    /// regenerating 2 a tick, bar 1–8 at rank 0, belt items 100–103 at count 0.
    fn hero_of(spec: MemberSpec) -> Member {
        let mut member = Fixture::member(spec);
        let (x, y) = (AT % 15, AT / 15);
        member.words.state += x.into() * Fixture::two(32) + y.into() * Fixture::two(40);
        member.words.stats += 20 * Fixture::two(64)
            + weapon::SWORD.into() * Fixture::two(88)
            + 27 * Fixture::two(96)
            + 1 * Fixture::two(112)
            + 60 * Fixture::two(120)
            + damage::SLASHING.into() * Fixture::two(160)
            + 1 * Fixture::two(176);
        member
    }

    fn hero() -> Member {
        Self::hero_of(Fixture::spec())
    }

    /// The member on `position` instead.
    fn moved(member: Member, position: u8) -> Member {
        let mut member = member;
        let (x, y) = (position % 15, position / 15);
        let (ox, oy) = (AT % 15, AT / 15);
        member.words.state += (x.into() - ox.into()) * Fixture::two(32)
            + (y.into() - oy.into()) * Fixture::two(40);
        member
    }

    /// Skill `id` on bar slot `slot` at `rank` (the words; the class loads them).
    fn equip(ref member: Member, slot: u8, id: u16, rank: u8) {
        let old = member.skill(slot);
        member.words.bar += (id.into() - old.into()) * Fixture::two(16 * slot.into());
        member.words.stats += rank.into() * Fixture::two(128 + 4 * slot.into());
    }

    /// Activating bar slot `slot` on `target`, its deadline `deadline`.
    fn activating(ref member: Member, slot: u8, target: u16, deadline: u32) {
        member.act_slot = slot;
        member.act_target = target;
        member.act_deadline = deadline;
    }

    fn holding(
        ref member: Member, slot: u8, carrier: u16, potion: bool, charges: u8, deadline: u32,
    ) {
        member.set_effect(slot, Held { carrier, potion, charges, deadline, rank: 12 }, 0);
    }

    /// Goblin `entity` of `caste` on `position` facing `facing`, in AI state `state` (awake when
    /// neither asleep, on watch nor dead), health 100 of 280, no energy, no adrenaline, level 10.
    fn gob(entity: u16, caste: u16, position: u8, facing: u8, state: u8) -> Goblin {
        let mut g = Fixture::goblin(entity, caste);
        let (x, y) = (position % 15, position / 15);
        g.state += x.into() + y.into() * Fixture::two(8) + facing.into() * Fixture::two(16);
        g.ai = state;
        g.awake = state != ai::ASLEEP && state != ai::WATCH && state < ai::DEAD;
        g
    }

    /// A Hob facing the adventurer.
    fn hob(entity: u16, position: u8, state: u8) -> Goblin {
        Self::gob(entity, HOB, position, ExecutorFixture::toward(position, AT), state)
    }

    /// A Hob facing the adventurer with every caste slot recharging to `T` (`t > R` is false): its
    /// weapon, or a step.
    fn armed(entity: u16, position: u8) -> Goblin {
        let mut g = Self::hob(entity, position, ai::ENGAGED);
        for slot in 0..4_u8 {
            g.set_recharge(slot, T);
        }
        g
    }

    fn words(members: Array<Member>, goblins: Array<Goblin>) -> Words {
        Fixture::world(CLOCK, members, goblins).store()
    }

    fn alone(member: Member) -> Words {
        Self::words(array![member], array![])
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
        BodyFixture::emit(ref digest, ref id, "ticks", case.span(), ok.span());
    }

    /// A row on the open board at the origin, the empty ground.
    fn plain(ref digest: Array<felt252>, ref id: u32, t: @Table, words: Words, n: u8) {
        Self::row(ref digest, ref id, t, words, ExecutorFixture::board(), Self::empty(), n);
    }

    /// One `skip` row: `SegmentTrait::ticks`' path for `n` ticks on `words` and `board`: `case` the
    /// `Words`, the `Board`, `n`; `ok` the path (0 `TickLibrary`, 1 the fast path
    /// `TickTrait::idle`, 2 none: `n` is 0 or the adventurer defeated), then the `Words` after it
    /// (the empty ground).
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
            let (after, _) = library
                .ticks(words, *t.content, board, *t.classes, LEVEL, Self::empty(), n);
            after
        };
        Serde::serialize(@after, ref ok);
        BodyFixture::emit(ref digest, ref id, "skip", case.span(), ok.span());
    }

    /// The board whose window is open but on `position`.
    fn walled(position: u8) -> Board {
        BoardTrait::new(
            WindowTrait::new(
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                    - Fixture::two(position.into()),
            ),
            0,
            0,
        )
    }

    /// The board whose window is open but on `positions`.
    fn walls(positions: Array<u8>) -> Board {
        let mut bits: felt252 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        for position in positions {
            bits -= Fixture::two(position.into());
        }
        BoardTrait::new(WindowTrait::new(bits), 0, 0)
    }

    /// Goblin `entity` of `caste` on the location's tile `(x, y)`, facing 0, in AI state `state`.
    fn gob_at(entity: u16, x: u8, y: u8, state: u8) -> Goblin {
        let mut g = Fixture::goblin(entity, HOB);
        g.state += x.into() + y.into() * Fixture::two(8);
        g.ai = state;
        g.awake = state != ai::ASLEEP && state != ai::WATCH && state < ai::DEAD;
        g
    }

    /// The facing opposite `facing`.
    fn back(facing: u8) -> u8 {
        (facing + 3) % 6
    }

    /// Row 131's content: row 0's with RV-03d's skills and castes appended.
    fn rv03d_content() -> Content {
        let base = Self::tick_content();
        let none: Entry = Default::default();
        let mut skills = array![];
        skills.append_span(base.skills);
        let bolt = ExecutorFixture::entry(
            kind::DAMAGE, damage::FIRE, 20, 80, target::FOE, shape::SINGLE, filter::FOES,
        );
        let mut sheet = ExecutorFixture::skill(BOLT, skill_kind::SPELL, 2, [bolt, none, none]);
        sheet.activation = 0;
        sheet.recharge = 6;
        skills.append(sheet);
        let mut sheet = ExecutorFixture::skill(SLOW_BOLT, skill_kind::SPELL, 2, [bolt, none, none]);
        sheet.recharge = 6;
        skills.append(sheet);
        let scorch = ExecutorFixture::entry(
            kind::DAMAGE, damage::FIRE, 40, 40, target::TILE, shape::SINGLE, filter::FOES,
        );
        let mut sheet = ExecutorFixture::skill(SCORCH, skill_kind::SPELL, 2, [scorch, none, none]);
        sheet.activation = 0;
        skills.append(sheet);
        skills.append(ExecutorFixture::skill(HOWL, skill_kind::SHOUT, 0, [none, none, none]));
        let haste = EntryTrait::new(
            kind::MOVEMENT, 0, 0, 0, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        skills
            .append(ExecutorFixture::skill(HASTE, skill_kind::ENCHANTMENT, 0, [haste, none, none]));
        let blast = ExecutorFixture::entry(
            kind::DAMAGE, damage::FIRE, 40, 40, target::SELF, shape::RING_1, filter::ALLIES,
        );
        skills.append(ExecutorFixture::skill(BLAST, skill_kind::SPELL, 0, [blast, none, none]));
        let fire = ExecutorFixture::entry(
            kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let heal = ExecutorFixture::entry(
            kind::HEAL, 0, 30, 30, target::SELF, shape::SINGLE, filter::ALLIES,
        );
        skills.append(ExecutorFixture::skill(SIPHON, skill_kind::SPELL, 6, [fire, heal, none]));
        let mut castes = array![];
        castes.append_span(base.castes);
        let hob = *base.castes[0];
        castes
            .append(
                CasteSheet {
                    id: SHAMAN,
                    health_regen: 13,
                    weapon_ticks: 3,
                    skills: [BOLT, SLOW_BOLT, SCORCH, HOWL],
                    ..hob,
                },
            );
        castes.append(CasteSheet { id: GAP, skills: [24, 25, 0, 27], ..hob });
        Content { skills: skills.span(), potions: base.potions, castes: castes.span() }
    }

    /// The table's classes with row 131's content.
    fn rv03d_table() -> Table {
        Table { content: Self::rv03d_content(), ..Self::table() }
    }

    /// The member on the location's tile `(x, y)` instead (outside the window too).
    fn placed(member: Member, x: u8, y: u8) -> Member {
        let mut member = member;
        let (ox, oy) = (AT % 15, AT / 15);
        member.words.state += (x.into() - ox.into()) * Fixture::two(32)
            + (y.into() - oy.into()) * Fixture::two(40);
        member
    }

    /// A member at `health` on `position`: the adventurer's companion.
    fn companion(position: u8, health: u16) -> Member {
        let mut spec = Fixture::spec();
        spec.health = health;
        Self::moved(Self::hero_of(spec), position)
    }

    /// The adventurer at 1 health.
    fn frail() -> Member {
        let mut spec = Fixture::spec();
        spec.health = 1;
        Self::hero_of(spec)
    }

    /// A goblin of `caste` facing the adventurer, Engaged, on `position`.
    fn engaged(entity: u16, caste: u16, position: u8) -> Goblin {
        Self::gob(entity, caste, position, ExecutorFixture::toward(position, AT), ai::ENGAGED)
    }

    /// A Hob activating its slot 0 (the attack skill) on the adventurer, concluding at `T`.
    fn concluding(entity: u16, position: u8) -> Goblin {
        let mut g = Self::hob(entity, position, ai::ENGAGED);
        g.start(0, 0, 1, T - 1);
        g
    }

    /// The roster's frozen goblins (as rows 129 and 130): `count` goblins away from their spawn
    /// chunk (asleep on (100, 100), chunk 96: entities 24–33, 40–49, … of spawn chunks
    /// 1–6), after `first`
    /// and before `last` (ascending entity id).
    fn roster(count: u32, first: Array<Goblin>, last: Array<Goblin>) -> Array<Goblin> {
        let mut goblins = first;
        let mut k: u32 = 0;
        for chunk in 1..7_u16 {
            for slot in 0..10_u16 {
                if k < count {
                    goblins.append(Self::gob_at(8 + 16 * chunk + slot, 100, 100, ai::ASLEEP));
                }
                k += 1;
            }
        }
        for goblin in last {
            goblins.append(goblin);
        }
        goblins
    }
}

#[derive(Drop)]
struct Table {
    tick: ClassHash,
    classes: Classes,
    content: Content,
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

// Row 0, the content; the member's steps alone: regeneration and its clamps, energy, the
// conditions, adrenaline's decay, the held `REGENERATION` effects, the flags.
#[test]
#[available_gas(l2_gas: 730628021)] // ceil(1.05 × 695836210 measured)
fn test_tick_vectors_0() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok = array![];
    Serde::serialize(@t.content, ref ok);
    BodyFixture::emit(ref digest, ref id, "content", array![].span(), ok.span());
    // Alone, one tick: the clock to `T`, energy 30 → 32.
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero()), 1);
    // Health regeneration (pips × 2): 3 pips from 400; from 473 (479), 474 (480: the max), 475
    // (481: clamped to 480).
    for health in array![400_u16, 473, 474, 475] {
        let mut spec = Fixture::spec();
        spec.health = health;
        spec.health_regen = 3;
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
        );
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
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
        );
    }
    // Each condition to `T` (held at `T`: −3, −4, −7 pips) and to `T − 1` (ended).
    for conditions in array![
        [T, 0_u32, 0, 0], [T - 1, 0, 0, 0], [0, T, 0, 0], [0, T - 1, 0, 0], [0, 0, T, 0],
        [0, 0, T - 1, 0],
    ] {
        let mut spec = Fixture::spec();
        spec.conditions = conditions;
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
        );
    }
    // Energy (thirds, 2 a tick, max 60): from 57 (59), 58 (60), 59 (61: clamped to 60), 60.
    for energy in array![57_u16, 58, 59, 60] {
        let mut spec = Fixture::spec();
        spec.energy = energy;
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
        );
    }
    // Adrenaline's decay out of combat (1 quarter a tick, D-157 E): from 2 (to 1), 1 (to 0), 0
    // (stays 0); from 2 over 3 ticks (1, 0, 0).
    for (adrenaline, n) in array![(2_u16, 1_u8), (1, 1), (0, 1), (2, 3)] {
        let mut spec = Fixture::spec();
        spec.adrenaline = adrenaline;
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), n,
        );
    }
    // The flags: `TURNED`, `INSTANT` and `HIT` clear at step 0, `HALVED` is kept.
    let mut spec = Fixture::spec();
    spec.flags = flag::TURNED | flag::INSTANT | flag::HIT | flag::HALVED;
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_0);
}

// The held `REGENERATION` effects (track CV, after #442): the skill's at ranks 12 (6 pips) and 0
// (2), and the potion's (belt slot 1, 3 pips), each held to `T` (it regenerates) and to `T − 1`
// (ended); the clock's bounds; the member steps' stops.
#[test]
#[available_gas(l2_gas: 504807111)] // ceil(1.05 × 480768677 measured)
fn test_tick_vectors_1() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_1;
    for (deadline, rank) in array![(T, 12_u8), (T - 1, 12), (T, 0), (T + 1, 0)] {
        let mut m = VectorFixture::hero();
        m.set_effect(0, Held { carrier: MEND, potion: false, charges: 0, deadline, rank }, 0);
        VectorFixture::plain(ref digest, ref id, @t, VectorFixture::alone(m), 1);
    }
    for deadline in array![T, T - 1] {
        let mut m = VectorFixture::hero();
        VectorFixture::holding(ref m, 1, 1, true, 0, deadline);
        VectorFixture::plain(ref digest, ref id, @t, VectorFixture::alone(m), 1);
    }
    // Both, the skill to `T + 1` over 3 ticks: 6 + 3 pips at `T` and `T + 1`, none at `T + 2`
    // past the potion's `T`… the potion's to `T`: 9 pips at `T`, 6 at `T + 1`, 0 at `T + 2`.
    let mut m = VectorFixture::hero();
    m
        .set_effect(
            0, Held { carrier: MEND, potion: false, charges: 0, deadline: T + 1, rank: 12 }, 0,
        );
    VectorFixture::holding(ref m, 1, 1, true, 0, T);
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::alone(m), 3);
    // `n`: 0 (nothing runs), 2, and 10 (the largest `play` passes: an action's ticks are at most
    // the weight, `MAX_WEIGHT`).
    for n in array![0_u8, 2, 10] {
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero()), n,
        );
    }
    // Stops: the adventurer at 0 before the tick (down, defeated, the clock kept), over 3 ticks;
    // at 1 with Bleeding, Poison and Burning to `T + 5`: down at step 3 of `T`, the 2 ticks after
    // not run; down (status 1) and gone (2) at 400: neither regenerates.
    let mut spec = Fixture::spec();
    spec.health = 0;
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 3,
    );
    let mut spec = Fixture::spec();
    spec.health = 1;
    spec.conditions = [T + 5, T + 5, T + 5, 0];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 3,
    );
    for state in array![status::DOWN, status::GONE] {
        let mut spec = Fixture::spec();
        spec.status = state;
        spec.health_regen = 3;
        VectorFixture::plain(
            ref digest, ref id, @t, VectorFixture::alone(VectorFixture::hero_of(spec)), 1,
        );
    }
    // A companion (member 1 on 110) at 0 inside: the tick stops at once, the adventurer
    // defeated (any member inside at 0, FX-8); at 300 with 3 pips, both regenerate.
    for health in array![0_u16, 300] {
        let mut spec = Fixture::spec();
        spec.health = health;
        spec.health_regen = 3;
        let companion = VectorFixture::moved(VectorFixture::hero_of(spec), AT - 2);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero(), companion], array![]),
            1,
        );
    }
    BodyFixture::finish(digest, TICK_DIGEST_1);
}

// Step 0: perception (design/18's table) and the awake set. The goblins on the adventurer's row,
// East of it (`AT + d` is `d` tiles away), chunk 0's (entities 8–12 pack 0, 13–17 pack 1).
#[test]
#[available_gas(l2_gas: 663977683)] // ceil(1.05 × 632359698 measured)
fn test_tick_vectors_2() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_2;
    // Asleep: notices within 2 (wakes Engaged, joins the set and acts), not at 3.
    for d in array![2_u8, 3] {
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + d, ai::ASLEEP)],
            ),
            1,
        );
    }
    // On watch: within 2 facing away; at 5 facing the adventurer (its front arc), at 6 not
    // (`range::ALERT`); at 5 facing away (its back), not; at 5 its sight blocked by a wall on
    // `AT + 3`, not.
    let mut g = VectorFixture::hob(8, AT + 2, ai::WATCH);
    g.set_place(9, 7, VectorFixture::back(ExecutorFixture::toward(AT + 2, AT)));
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    for d in array![5_u8, 6] {
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + d, ai::WATCH)],
            ),
            1,
        );
    }
    let mut g = VectorFixture::hob(8, AT + 5, ai::WATCH);
    g.set_place(12, 7, VectorFixture::back(ExecutorFixture::toward(AT + 5, AT)));
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 5, ai::WATCH)],
        ),
        VectorFixture::walled(AT + 3),
        VectorFixture::empty(),
        1,
    );
    // At 5, turned one and two steps from the adventurer: the front-side arc notices, the
    // rear-side does not.
    for turn in array![1_u8, 2] {
        let mut g = VectorFixture::hob(8, AT + 5, ai::WATCH);
        g.set_place(12, 7, (ExecutorFixture::toward(AT + 5, AT) + turn) % 6);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Alerted at 5 (no notice: awake all the same, it steps toward the adventurer); Returning
    // at 1 (awake, does nothing); dead at 1 (neither notices nor wakes).
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 5, ai::ALERTED)],
        ),
        1,
    );
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 1, ai::RETURNING)],
        ),
        1,
    );
    let mut dead = VectorFixture::hob(8, AT + 1, ai::DEAD);
    dead.health = 0;
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![VectorFixture::hero()], array![dead]),
        1,
    );
    // The pack: goblin 8 on watch at 2 notices; 9 (pack 0) asleep at 7 is engaged with it and
    // acts; 13 (pack 1) asleep at 6 is not.
    let goblins = array![
        VectorFixture::hob(8, AT + 2, ai::WATCH), VectorFixture::hob(9, AT + 7, ai::ASLEEP),
        VectorFixture::hob(13, AT + 6, ai::ASLEEP),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // The awake set: nine goblins Alerted, eight awake on the words, on the adventurer's row at
    // 2, 2, 3, 3, 4, 4, 5, 6 and 6 tiles (East and West): the eight nearest, the tie at the
    // set's edge (15 East, 16 West, at 6) to the lower id.
    let mut goblins = array![
        VectorFixture::hob(8, AT + 2, ai::ALERTED), VectorFixture::hob(9, AT - 2, ai::ALERTED),
        VectorFixture::hob(10, AT + 3, ai::ALERTED), VectorFixture::hob(11, AT - 3, ai::ALERTED),
        VectorFixture::hob(12, AT + 4, ai::ALERTED), VectorFixture::hob(13, AT - 4, ai::ALERTED),
        VectorFixture::hob(14, AT + 5, ai::ALERTED), VectorFixture::hob(15, AT + 6, ai::ALERTED),
    ];
    let mut last = VectorFixture::hob(16, AT - 6, ai::ALERTED);
    last.awake = false;
    goblins.append(last);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // A goblin Engaged outside the window (on (7, 20)): never in the set, it does not act.
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::gob_at(8, 7, 20, ai::ENGAGED)],
        ),
        1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_2);
}

// Step 2, an Engaged goblin's act: its caste's priority list (slot 0 first: recharging, its
// adrenaline, its energy, its target in range; the trap skill skipped), its weapon in reach, else
// a step. A Hob adjacent East (`AT + 1`) with no energy and no adrenaline, unless a row says.
#[test]
#[available_gas(l2_gas: 633611744)] // ceil(1.05 × 603439756 measured)
fn test_tick_vectors_3() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_3;
    // Slots 0 (4 quarters short), 1 (15 thirds short) and 2 (the trap) skipped: the shout
    // (slot 3, instant, on itself), its recharge from `T`.
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 1, ai::ENGAGED)],
        ),
        1,
    );
    // The shout recharging to `T` (refused: `t > R`), to `T − 1` (used).
    for recharge in array![T, T - 1] {
        let mut g = VectorFixture::hob(8, AT + 1, ai::ENGAGED);
        g.set_recharge(3, recharge);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Slot 0, the attack skill (1 strike): adrenaline 4 (it starts, `A = T + 2`, 4 spent), 3
    // (the weapon), 5; slot 0 recharging to `T` with 4 (the weapon) and to `T − 1` (it starts).
    for (adrenaline, recharge) in array![(4_u8, 0_u32), (3, 0), (5, 0), (4, T), (4, T - 1)] {
        let mut g = VectorFixture::armed(8, AT + 1);
        g.set_recharge(0, recharge);
        g.adrenaline = adrenaline;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Slot 1, the fire spell (range 2, 15 thirds): energy 15 (it lands now, 0 left, its recharge
    // from `T`), 14 (the weapon); at 2 tiles with 15 (lands), at 3 (out of range and reach: a
    // step).
    for (d, energy) in array![(1_u8, 15_u8), (1, 14), (2, 15), (3, 15)] {
        let mut g = VectorFixture::armed(8, AT + d);
        g.set_recharge(1, 0);
        g.energy = energy;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // A Runt (`k` 3): slot 0, the instant attack skill (lands now, recovering to `T + 2`); every
    // slot recharging, its weapon (recovering to `T + 2`).
    let g = VectorFixture::gob(8, RUNT, AT + 1, ExecutorFixture::toward(AT + 1, AT), ai::ENGAGED);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let mut g = VectorFixture::gob(
        8, RUNT, AT + 1, ExecutorFixture::toward(AT + 1, AT), ai::ENGAGED,
    );
    for slot in 0..4_u8 {
        g.set_recharge(slot, T);
    }
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // The weapon on the adventurer (facing 0, toward `AT − 1`): from behind it (`AT + 1`) and
    // from its front (`AT − 1`).
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::armed(8, AT + 1)],
        ),
        1,
    );
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::armed(8, AT - 1)],
        ),
        1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_3);
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
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_4;
    for (charges, knocked) in array![(63_u8, 0_u32), (62, 0), (1, 0), (63, T), (63, T - 1)] {
        let mut m = VectorFixture::hero();
        VectorFixture::holding(ref m, 0, BRACE, false, charges, T + 5);
        m.knocked = knocked;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![m], array![VectorFixture::armed(8, AT - 1)]),
            1,
        );
    }
    let mut m = VectorFixture::hero();
    VectorFixture::holding(ref m, 0, BRACE, false, 63, T + 5);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m], array![VectorFixture::armed(8, AT + 1)]),
        1,
    );
    for rank in array![2_u8, 3, 4] {
        let mut m = VectorFixture::hero();
        VectorFixture::equip(ref m, 0, WALL, rank);
        VectorFixture::activating(ref m, 0, 0, T);
        VectorFixture::plain(ref digest, ref id, @t, VectorFixture::alone(m), 1);
    }
    // Bar slot 1 (skill 2, recharge 12) on goblin 8 at 1: concluding at `T` (`R = T + 11`),
    // overdue at `T − 1` (`R = T + 10`), at `T + 1` (not yet); down at 400, not concluded.
    for deadline in array![T, T - 1, T + 1] {
        let mut m = VectorFixture::hero();
        VectorFixture::activating(ref m, 1, 8, deadline);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![m], array![VectorFixture::armed(8, AT + 1)]),
            1,
        );
    }
    let mut m = VectorFixture::hero();
    VectorFixture::activating(ref m, 1, 8, T);
    m.status = status::DOWN;
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m], array![VectorFixture::armed(8, AT + 1)]),
        1,
    );
    // Cinder Ring (fire 80, Burning 3 on `RING_1` around the member) at `T` on goblins 8 (East,
    // 90 health), 9 (West, 100) and 10 (on `AT + 15`, 280): 8 and 9 die, in tile
    // order, then 10 burns and acts.
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, RING, 12);
    VectorFixture::activating(ref m, 0, 0, T);
    let mut a = VectorFixture::armed(8, AT + 1);
    a.health = 90;
    let b = VectorFixture::armed(9, AT - 1);
    let mut c = VectorFixture::armed(10, AT + 15);
    c.health = 280;
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![m], array![a, b, c]), 1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_4);
}

// The AI's states and the goblins' step 1 and step 3: Alerted, fleeing (a step away; cornered,
// Engaged again), knocked down, an activation concluding, lapsed or not yet, a recovery ending;
// Runt's attack skill concluding into a recovery (FX-15); a goblin dying at step 3; energy,
// adrenaline's decay out of Engaged (track CV's segment2 mutant), the held `REGENERATION`.
#[test]
#[available_gas(l2_gas: 930198842)] // ceil(1.05 × 885903659 measured)
fn test_tick_vectors_5() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_5;
    // Fleeing at 2: a step away. Every tile around it walled but `AT + 1`, nearer the
    // adventurer: its one free neighbour, it steps there, still fleeing. Every tile around it
    // walled: cornered (no step), Engaged again.
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 2, ai::FLEEING)],
        ),
        1,
    );
    let around = crate::types::executor::tests::ExecutorFixture::ring(AT + 2);
    let mut blocked = array![];
    let mut all = array![];
    for tile in around {
        if *tile != AT + 1 {
            blocked.append(*tile);
        }
        all.append(*tile);
    }
    for walled in array![blocked, all] {
        VectorFixture::row(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 2, ai::FLEEING)],
            ),
            VectorFixture::walls(walled),
            VectorFixture::empty(),
            1,
        );
    }
    // Knocked down to `T` (no act), to `T − 1` (it acts).
    for knocked in array![T, T - 1] {
        let mut g = VectorFixture::armed(8, AT + 1);
        g.knocked = knocked;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Slot 0 (24, recharge 10) activating on the adventurer: concluding at `T` (its weapon hit,
    // `R = T + 9`, no act after); lapsed from `T − 1` (FX-29: `R = T + 8`, then it acts); `T + 1`
    // (busy). Recovering to `T − 1` (cleared, it acts) and to `T` (busy).
    for deadline in array![T, T - 1, T + 1] {
        let mut g = VectorFixture::hob(8, AT + 1, ai::ENGAGED);
        g.start(0, 0, 1, deadline - 1);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    for deadline in array![T - 1, T] {
        let mut g = VectorFixture::hob(8, AT + 1, ai::ENGAGED);
        g.act_slot = activation::RECOVERING;
        g.act_deadline = deadline;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // A Runt's slot 1 (29, activation 1, `k` 3 ≥ 1 + 2) concluding at `T`: recovering to
    // `T + 1`.
    let mut g = VectorFixture::gob(
        8, RUNT, AT + 1, ExecutorFixture::toward(AT + 1, AT), ai::ENGAGED,
    );
    g.start(1, 0, 1, T - 1);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // Step 3: at 1 with Bleeding to `T` (dies: `DEAD`, in `killed`); to `T − 1` (lives).
    for bleeding in array![T, T - 1] {
        let mut g = VectorFixture::hob(8, AT + 6, ai::ALERTED);
        g.health = 1;
        g.bleeding = bleeding;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Energy (1 a tick, max 30 thirds): from 29 and from 30; adrenaline Alerted (decays) from 2
    // and 1, Engaged (kept) from 2; the adventurer's adrenaline 2 beside an Engaged goblin
    // (kept: in combat) and beside an Alerted one (decays).
    for (energy, adrenaline, state) in array![
        (29_u8, 0_u8, ai::ALERTED), (30, 0, ai::ALERTED), (0, 2, ai::ALERTED), (0, 1, ai::ALERTED),
        (0, 2, ai::ENGAGED),
    ] {
        let mut g = VectorFixture::hob(8, AT + 6, state);
        g.energy = energy;
        g.adrenaline = adrenaline;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    for state in array![ai::ENGAGED, ai::ALERTED] {
        let mut spec = Fixture::spec();
        spec.adrenaline = 2;
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero_of(spec)], array![VectorFixture::hob(8, AT + 6, state)],
            ),
            1,
        );
    }
    // A goblin holding the `REGENERATION` skill (rank 12, 6 pips) to `T` and to `T − 1`.
    for deadline in array![T, T - 1] {
        let mut g = VectorFixture::hob(8, AT + 6, ai::ALERTED);
        g.set_effect(Held { carrier: MEND, potion: false, charges: 0, deadline, rank: 12 }, 0);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    // Crippled to `T` (its step costs 2: recovering to `T + 1`) and to `T − 1` (1).
    for crippled in array![T, T - 1] {
        let mut g = VectorFixture::hob(8, AT + 3, ai::ALERTED);
        g.set_crippled(crippled);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    BodyFixture::finish(digest, TICK_DIGEST_5);
}

// Goblin order and the hooks over one goblin: two goblins stepping toward the same tiles, by
// ascending id (and the ids swapped); an asleep goblin's tile blocking a step; a member's trap
// entered (`TrapLibrary`), a terrain trap not (FX-34); the same goblin written by step 1, step 2
// and step 3 of one tick, and over two ticks (track CV's `fits` mutant); a defeat in step 1 and in
// step 2.
#[test]
#[available_gas(l2_gas: 394639866)] // ceil(1.05 × 375847491 measured)
fn test_tick_vectors_6() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_6;
    // Goblins 8 and 9 Alerted on `AT + 2` and `AT + 2 − 15` (rows 7 and 6), the tile West of
    // the second walled (`AT + 1 − 15`): both would step onto `AT + 1`; the lower id first, then
    // the ids swapped.
    for (first, second) in array![(8_u16, 9_u16), (9, 8)] {
        let goblins = if first < second {
            array![
                VectorFixture::hob(first, AT + 2, ai::ALERTED),
                VectorFixture::hob(second, AT + 2 - 15, ai::ALERTED),
            ]
        } else {
            array![
                VectorFixture::hob(second, AT + 2 - 15, ai::ALERTED),
                VectorFixture::hob(first, AT + 2, ai::ALERTED),
            ]
        };
        VectorFixture::row(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], goblins),
            VectorFixture::walled(AT + 1 - 15),
            VectorFixture::empty(),
            1,
        );
    }
    // Goblin 8 Alerted at 5; 13 (pack 1) asleep on `AT + 4`, the tile it would take (frozen:
    // not awake, its tile occupied).
    let goblins = array![
        VectorFixture::hob(8, AT + 5, ai::ALERTED), VectorFixture::hob(13, AT + 4, ai::ASLEEP),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // Goblin 8 Alerted at 3 steps onto `AT + 2`, holding the member's Snare (bar slot 0, placer
    // `(0, 0)`): it triggers through `TrapLibrary` (earth 10 to 40, Crippled 3; the trap used);
    // a terrain trap (skill 45) there: nothing (FX-34).
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, SNARE, 12);
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
        VectorFixture::row(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![m], array![VectorFixture::hob(8, AT + 3, ai::ALERTED)]),
            ExecutorFixture::board(),
            ground,
            1,
        );
    }
    // The same goblin three times in one tick: Cinder Ring concluding at `T` strikes goblin 8
    // (280 health, Burning 3), it acts in step 2 (its weapon), Burning and its regeneration at
    // step 3. Goblin 8 Alerted at 5 over 2 ticks: two steps.
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, RING, 12);
    VectorFixture::activating(ref m, 0, 0, T);
    let mut g = VectorFixture::armed(8, AT + 1);
    g.health = 280;
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], array![g]), 1);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 5, ai::ALERTED)],
        ),
        2,
    );
    // Defeats: goblin 8's attack skill concluding at `T` on the adventurer at 1 (down at step
    // 1: no step 2 or 3, the 2 ticks after not run); goblin 8's weapon at step 2 on it at 1:
    // goblin 9 (adjacent, `AT − 1`) does not act after it.
    let mut spec = Fixture::spec();
    spec.health = 1;
    let mut g = VectorFixture::hob(8, AT + 1, ai::ENGAGED);
    g.start(0, 0, 1, T - 1);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![VectorFixture::hero_of(spec)], array![g]),
        3,
    );
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero_of(spec)],
            array![VectorFixture::armed(8, AT + 1), VectorFixture::armed(9, AT - 1)],
        ),
        3,
    );
    BodyFixture::finish(digest, TICK_DIGEST_6);
}

// `skip`: `SegmentTrait::ticks`' path. The fast path (no member activating, no goblin awake, no
// living goblin in the window) runs in process; `n` 0 and a defeated adventurer run nothing.
#[test]
#[available_gas(l2_gas: 273627793)] // ceil(1.05 × 260597898 measured)
fn test_tick_vectors_7() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_7;
    // Alone: the fast path, 1 and 10 ticks; `n` 0: none; defeated: none.
    for n in array![1_u8, 10, 0] {
        VectorFixture::skip(
            ref digest,
            ref id,
            @t,
            VectorFixture::alone(VectorFixture::hero()),
            ExecutorFixture::board(),
            n,
        );
    }
    let mut w = VectorFixture::alone(VectorFixture::hero());
    w.defeated = true;
    VectorFixture::skip(ref digest, ref id, @t, w, ExecutorFixture::board(), 1);
    // Activating (bar slot 1 to `T + 3`): `TickLibrary`.
    let mut m = VectorFixture::hero();
    VectorFixture::activating(ref m, 1, 0, T + 3);
    VectorFixture::skip(
        ref digest, ref id, @t, VectorFixture::alone(m), ExecutorFixture::board(), 1,
    );
    // Outside the window (on (7, 20)): Engaged and awake, `TickLibrary` (not calm); asleep, the
    // fast path. Inside it (`AT + 6`): asleep or on watch, `TickLibrary` (a living goblin in the
    // window); dead, the fast path.
    for state in array![ai::ENGAGED, ai::ASLEEP] {
        VectorFixture::skip(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero()], array![VectorFixture::gob_at(8, 7, 20, state)],
            ),
            ExecutorFixture::board(),
            1,
        );
    }
    for state in array![ai::ASLEEP, ai::WATCH] {
        VectorFixture::skip(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(
                array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 6, state)],
            ),
            ExecutorFixture::board(),
            1,
        );
    }
    let mut dead = VectorFixture::hob(8, AT + 6, ai::DEAD);
    dead.health = 0;
    VectorFixture::skip(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![VectorFixture::hero()], array![dead]),
        ExecutorFixture::board(),
        1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_7);
}

// The roster (D-238): goblin 248 (spawn chunk 15) Alerted on (7, 15), the adventurer on (7, 12)
// in chunk 0: its step leaves its spawn chunk and needs a roster entry. With 59 other goblins
// away from theirs (asleep on (100, 100), chunk 96: entities 24–33, 40–49, … of spawn chunks
// 1–6, outside the window), it steps; with 60, the roster is full: it holds its tile.
#[test]
// gas: raised, RV-03a2: regenerated from one run (#456's review, minor 2)
#[available_gas(l2_gas: 640670696)] // ceil(1.05 × 610162567 measured)
fn test_tick_vectors_8() {
    let t = VectorFixture::table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_8;
    for count in array![59_u32, 60] {
        let mut goblins = array![];
        let mut k: u32 = 0;
        for chunk in 1..7_u16 {
            for slot in 0..10_u16 {
                if k < count {
                    goblins
                        .append(VectorFixture::gob_at(8 + 16 * chunk + slot, 100, 100, ai::ASLEEP));
                }
                k += 1;
            }
        }
        goblins.append(VectorFixture::gob_at(248, 7, 15, ai::ALERTED));
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::moved(VectorFixture::hero(), 187)], goblins),
            1,
        );
    }
    BodyFixture::finish(digest, TICK_DIGEST_8);
}

// ---- RV-03d (D-257): rows for track CV's surviving mutants of the tick port (#459), after every
// earlier id. Row 131 is a second content row: every row from 131 on reads it (the last `content`
// row before it), rows 1–130 read row 0's.

/// RV-03d's skills, after row 0's (ids 90 on), none mixing `TILE` with `FOE` or `ALLY` (D-271):
/// Shaman's slot 0, an instant spell of fire 20 to 80 with the rank on a foe, range 2; slot 1, the
/// same at activation 1; slot 2, an instant spell of fire 40 on a `SINGLE` `TILE`, range 2; slot 3,
/// a shout on itself at activation 1. An enchantment holding `MOVEMENT`. The member's: a spell of
/// fire 40 on `RING_1` around its source, filter `ALLIES`, activation 1; a spell of fire 40 on a
/// foe then a heal of 30 on itself, range 6, activation 1.
const BOLT: u16 = 90;
const SLOW_BOLT: u16 = 91;
const SCORCH: u16 = 92;
const HOWL: u16 = 93;
const HASTE: u16 = 94;
const BLAST: u16 = 95;
const SIPHON: u16 = 96;
/// RV-03d's castes, the Hob's but: Shaman (3), `k` 3, health regeneration 3 pips (13), skills
/// 90–93; Gap (4), its slot 2 empty (skills 24, 25, none, 27).
const SHAMAN: u16 = 3;
const GAP: u16 = 4;

// Row 131, the content; the stops with a companion (member 1) alive; the order of step 1;
// a resolved goblin and a dead one against step 2; a concluding activation's target no longer
// legal; the goblins' target; perception with two members, two chunks' packs, an Alerted goblin
// of a noticing pack; combat; an unwalkable adventurer.
#[test]
#[available_gas(l2_gas: 849188006)] // ceil(1.05 × 808750481 measured)
fn test_tick_vectors_9() {
    let t = VectorFixture::rv03d_table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_9;
    let mut ok = array![];
    Serde::serialize(@t.content, ref ok);
    BodyFixture::emit(ref digest, ref id, "content", array![].span(), ok.span());
    // Goblin 8's weapon downs the adventurer (at 1) in step 2: goblin 9, beside member 1 (on
    // `AT − 2`), does not act after it (132). Goblin 8's attack skill downs it in step 1: no step
    // 2, goblin 9 does not act (133).
    let goblins = array![VectorFixture::armed(8, AT + 1), VectorFixture::armed(9, AT - 3)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::frail(), VectorFixture::companion(AT - 2, 400)], goblins,
        ),
        1,
    );
    let goblins = array![VectorFixture::concluding(8, AT + 1), VectorFixture::armed(9, AT - 3)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::frail(), VectorFixture::companion(AT - 2, 400)], goblins,
        ),
        1,
    );
    // The member's spell (fire 40 on `RING_1`, `ALLIES`) concluding at `T` downs member 1 (on
    // `AT − 1`, at 1): step 1 stops before goblin 8's activation concluding at `T` (134).
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, BLAST, 12);
    VectorFixture::activating(ref m, 0, 0, T);
    let goblins = array![VectorFixture::concluding(8, AT + 1)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m, VectorFixture::companion(AT - 1, 1)], goblins),
        1,
    );
    // Goblins 8 and 9 concluding at `T` on the adventurer at 1: goblin 8's hit downs it, goblin
    // 9's activation is not concluded (135).
    let goblins = array![
        VectorFixture::concluding(8, AT + 1), VectorFixture::concluding(9, AT - 1),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::frail()], goblins), 1,
    );
    // Goblin 8 concludes at `T` (resolved: no act in step 2); goblin 9 is free and acts (136).
    let goblins = array![VectorFixture::concluding(8, AT + 1), VectorFixture::armed(9, AT - 1)];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // Cinder Ring concluding at `T` kills goblin 8 (90 health), activating to `T`: its activation
    // neither concludes nor lapses (137); kills goblin 9 (90, on `AT + 1`): goblin 8, Alerted on
    // `AT + 2`, steps onto its tile (138).
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, RING, 12);
    VectorFixture::activating(ref m, 0, 0, T);
    let mut g = VectorFixture::concluding(8, AT + 1);
    g.health = 90;
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], array![g]), 1);
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, RING, 12);
    VectorFixture::activating(ref m, 0, 0, T);
    let mut dying = VectorFixture::armed(9, AT + 1);
    dying.health = 90;
    let goblins = array![VectorFixture::hob(8, AT + 2, ai::ALERTED), dying];
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    // A concluding activation whose target is no longer legal: nothing runs. The member's spell
    // (fire on a foe, then a heal of 30 on itself) on goblin 8, dead (139); goblin 8's attack
    // skill on the adventurer, 2 tiles away (out of its weapon's reach) (140).
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, SIPHON, 12);
    VectorFixture::activating(ref m, 0, 8, T);
    let mut dead = VectorFixture::hob(8, AT + 3, ai::DEAD);
    dead.health = 0;
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], array![dead]), 1);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::concluding(8, AT + 2)],
        ),
        1,
    );
    // The goblins' target, the first member alive in the window: member 0 outside it (on
    // (7, 20); `play` never passes one) (141), member 0 down (status 1) (142); goblin 8 armed
    // beside member 1 attacks member 1.
    let m = VectorFixture::placed(VectorFixture::hero(), 7, 20);
    let goblins = array![VectorFixture::armed(8, AT + 1)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m, VectorFixture::moved(VectorFixture::hero(), AT)], goblins),
        1,
    );
    let mut spec = Fixture::spec();
    spec.status = status::DOWN;
    let goblins = array![VectorFixture::armed(8, AT - 3)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero_of(spec), VectorFixture::companion(AT - 2, 400)], goblins,
        ),
        1,
    );
    // Perception: goblin 8 asleep 2 tiles from member 0 and 7 from member 1 (on `AT − 5`):
    // it notices (143). Goblin 8 on watch at 2 notices: goblin 24 (chunk 1's pack 0) asleep at 4
    // is not engaged (144); goblin 9 (pack 0) Alerted at 5 is (145).
    let goblins = array![VectorFixture::hob(8, AT + 2, ai::ASLEEP)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero(), VectorFixture::companion(AT - 5, 400)], goblins,
        ),
        1,
    );
    let goblins = array![
        VectorFixture::hob(8, AT + 2, ai::WATCH), VectorFixture::hob(24, AT + 4, ai::ASLEEP),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    let goblins = array![
        VectorFixture::hob(8, AT + 2, ai::WATCH), VectorFixture::hob(9, AT + 5, ai::ALERTED),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // The adventurer's adrenaline 2 beside an Engaged goblin outside the window (out of the set):
    // out of combat, it decays (146).
    let mut spec = Fixture::spec();
    spec.adrenaline = 2;
    let goblins = array![VectorFixture::gob_at(8, 7, 20, ai::ENGAGED)];
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![VectorFixture::hero_of(spec)], goblins),
        1,
    );
    // The adventurer on a tile the window does not hold walkable (`play` never passes one): no
    // flood, goblin 8 Alerted at 3 holds (147).
    VectorFixture::row(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 3, ai::ALERTED)],
        ),
        VectorFixture::walled(AT),
        VectorFixture::empty(),
        1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_9);
}

// The goblins' skills (row 131's content): the facing of a weapon and of a skill; a lapse below a
// stored recharge; a Runt's activation of 1 and its instant shout; an empty caste slot; the
// caste's rank now and at a conclusion; FX-15's recovery of a spell; a `TILE` skill; a slot 3
// activation; the caste's regeneration; a `MOVEMENT` effect on both sides of its deadline.
#[test]
#[available_gas(l2_gas: 523246500)] // ceil(1.05 × 498330000 measured)
fn test_tick_vectors_10() {
    let t = VectorFixture::rv03d_table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_10;
    // Facing away from the adventurer: the weapon (148), the fire spell (slot 1, 15 thirds) (149).
    let mut g = VectorFixture::armed(8, AT + 1);
    g.set_place(8, 7, VectorFixture::back(ExecutorFixture::toward(AT + 1, AT)));
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let mut g = VectorFixture::armed(8, AT + 1);
    g.set_place(8, 7, VectorFixture::back(ExecutorFixture::toward(AT + 1, AT)));
    g.set_recharge(1, 0);
    g.energy = 15;
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // Slot 0 lapsed from `T − 1` (`A + r − 1 = T + 8`), its recharge stored to `T + 50`: kept
    // (150).
    let mut g = VectorFixture::hob(8, AT + 1, ai::ENGAGED);
    g.start(0, 0, 1, T - 2);
    g.set_recharge(0, T + 50);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // A Runt, slot 0 recharging: slot 1 (activation 1) starts, `A = T + 1` (151); slots 0–2
    // recharging: slot 3, the instant shout (no recovery: not an attack) (152).
    let mut g = VectorFixture::engaged(8, RUNT, AT + 1);
    g.set_recharge(0, T);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let mut g = VectorFixture::engaged(8, RUNT, AT + 1);
    for slot in 0..3_u8 {
        g.set_recharge(slot, T);
    }
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // Gap: slots 0 and 1 short, slot 2 empty (skipped), the shout (153).
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::engaged(8, GAP, AT + 1)],
        ),
        1,
    );
    // Shaman: slot 0 lands now at the caste's rank 12 (fire 80) (154); slot 1 (activation 1)
    // concluding at `T` (rank 12; a spell: no recovery, `k` 3 ≥ 1 + 2) (155); slots 0 and 1
    // recharging: slot 2 on the adventurer's tile `x + 256 y` (156); slot 3's activation (the
    // shout) concluding at `T` (157); Alerted at 6, its regeneration (3 pips) (158).
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::engaged(8, SHAMAN, AT + 1)],
        ),
        1,
    );
    let mut g = VectorFixture::engaged(8, SHAMAN, AT + 1);
    g.start(1, 0, 1, T - 1);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let mut g = VectorFixture::engaged(8, SHAMAN, AT + 1);
    g.set_recharge(0, T);
    g.set_recharge(1, T);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let mut g = VectorFixture::engaged(8, SHAMAN, AT + 1);
    g.start(3, 8, 1, T - 1);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    let g = VectorFixture::gob(8, SHAMAN, AT + 6, ExecutorFixture::toward(AT + 6, AT), ai::ALERTED);
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], array![g]), 1,
    );
    // Crippled to `T`, holding the `MOVEMENT` enchantment to `T` (its step costs 1) and to
    // `T − 1` (2: recovering to `T + 1`) (159, 160).
    for deadline in array![T, T - 1] {
        let mut g = VectorFixture::hob(8, AT + 3, ai::ALERTED);
        g.set_crippled(T);
        g.set_effect(Held { carrier: HASTE, potion: false, charges: 0, deadline, rank: 12 }, 0);
        VectorFixture::plain(
            ref digest,
            ref id,
            @t,
            VectorFixture::words(array![VectorFixture::hero()], array![g]),
            1,
        );
    }
    BodyFixture::finish(digest, TICK_DIGEST_10);
}

// The flood: a dead goblin's tile, a frozen goblin on the walker's path, its cap of 15 layers
// toward and away; a goblin killed by the trap it enters.
#[test]
#[available_gas(l2_gas: 215905871)] // ceil(1.05 × 205624639 measured)
fn test_tick_vectors_11() {
    let t = VectorFixture::rv03d_table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_11;
    // Goblin 8 Alerted on `AT + 2`, its one neighbour in layer 1 `AT + 1`, where dead goblin 9
    // lies (not frozen: its tile is free): it steps there (161).
    let mut dead = VectorFixture::hob(9, AT + 1, ai::DEAD);
    dead.health = 0;
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(
            array![VectorFixture::hero()], array![VectorFixture::hob(8, AT + 2, ai::ALERTED), dead],
        ),
        1,
    );
    // Goblin 8 asleep on (8, 4), 3 tiles away (frozen: the flood's obstacle), goblin 9 Fleeing on
    // (7, 4): its step away is (7, 3), (6, 3) on a flood through goblin 8's tile (162).
    let goblins = array![
        VectorFixture::gob_at(8, 8, 4, ai::ASLEEP), VectorFixture::gob_at(9, 7, 4, ai::FLEEING),
    ];
    VectorFixture::plain(
        ref digest, ref id, @t, VectorFixture::words(array![VectorFixture::hero()], goblins), 1,
    );
    // The adventurer on (1, 1): the flood stops at its cap, 15 layers. Goblin 8 Alerted on
    // (13, 8), in layer 15, steps (163); Fleeing on (13, 9), beyond it (16), its free neighbours
    // in layer 15: not reached, no step, cornered (164).
    let m = VectorFixture::placed(VectorFixture::hero(), 1, 1);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m], array![VectorFixture::gob_at(8, 13, 8, ai::ALERTED)]),
        1,
    );
    let m = VectorFixture::placed(VectorFixture::hero(), 1, 1);
    VectorFixture::plain(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m], array![VectorFixture::gob_at(8, 13, 9, ai::FLEEING)]),
        1,
    );
    // Goblin 8 Alerted at 3 (50 health) steps onto the member's Snare (as row 113): killed by it
    // (165).
    let mut m = VectorFixture::hero();
    VectorFixture::equip(ref m, 0, SNARE, 12);
    let placer: u16 = Placer::Member((0, 0)).param();
    let trap = Object {
        tile: AT + 2, kind: crate::models::chunk::object::PLACED_TRAP, state: 0, param: placer,
    };
    let ground = array![
        (
            0,
            Features {
                objects: [trap, Default::default(), Default::default()], ..FeaturesTrait::empty(),
            },
        ),
    ];
    let mut g = VectorFixture::hob(8, AT + 3, ai::ALERTED);
    g.health = 50;
    VectorFixture::row(
        ref digest,
        ref id,
        @t,
        VectorFixture::words(array![m], array![g]),
        ExecutorFixture::board(),
        ground,
        1,
    );
    BodyFixture::finish(digest, TICK_DIGEST_11);
}

// The roster (D-238), as rows 129 and 130: the adventurer on (7, 12), the window's last row
// (y 15) chunk 15, the rows above chunk 0. An awake goblin away from home counted (166); two
// walkers stepping out, the second at a full roster (167).
#[test]
#[available_gas(l2_gas: 651009213)] // ceil(1.05 × 620008774 measured)
fn test_tick_vectors_12() {
    let t = VectorFixture::rv03d_table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_12;
    let m = VectorFixture::moved(VectorFixture::hero(), 187);
    // 59 away frozen, goblin 120 (spawn chunk 7) Alerted on (2, 3), away: the roster is full,
    // goblin 248 holds (166).
    let goblins = VectorFixture::roster(
        59,
        array![],
        array![
            VectorFixture::gob_at(120, 2, 3, ai::ALERTED),
            VectorFixture::gob_at(248, 7, 15, ai::ALERTED),
        ],
    );
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    // 59 away frozen; goblins 248 on (5, 15) and 249 on (9, 15), both of chunk 15: 248 steps out
    // (60), 249 holds (167).
    let goblins = VectorFixture::roster(
        59,
        array![],
        array![
            VectorFixture::gob_at(248, 5, 15, ai::ALERTED),
            VectorFixture::gob_at(249, 9, 15, ai::ALERTED),
        ],
    );
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    BodyFixture::finish(digest, TICK_DIGEST_12);
}

// The roster: a step between two chunks away from home at a full roster (168); a step back home
// before another goblin's step out (169); a Fleeing goblin held by a full roster (170).
#[test]
#[available_gas(l2_gas: 958873776)] // ceil(1.05 × 913213120 measured)
fn test_tick_vectors_13() {
    let t = VectorFixture::rv03d_table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TICK_PART_13;
    let m = VectorFixture::moved(VectorFixture::hero(), 187);
    // 59 away frozen; goblin 120 (spawn chunk 7) on (7, 15) (chunk 15): 60 listed, it steps
    // into chunk 0, neither home (168).
    let goblins = VectorFixture::roster(
        59, array![], array![VectorFixture::gob_at(120, 7, 15, ai::ALERTED)],
    );
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    // 59 away frozen; goblin 8 (chunk 0) on (5, 15), away (60 listed), steps home (59); goblin
    // 248 on (9, 15) steps out (60) (169).
    let goblins = VectorFixture::roster(
        59,
        array![VectorFixture::gob_at(8, 5, 15, ai::ALERTED)],
        array![VectorFixture::gob_at(248, 9, 15, ai::ALERTED)],
    );
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    // 60 away frozen; goblin 248 Fleeing on (7, 15): its step away leaves chunk 15, the roster is
    // full: it holds, still Fleeing (170).
    let goblins = VectorFixture::roster(
        60, array![], array![VectorFixture::gob_at(248, 7, 15, ai::FLEEING)],
    );
    VectorFixture::plain(ref digest, ref id, @t, VectorFixture::words(array![m], goblins), 1);
    BodyFixture::finish(digest, TICK_DIGEST_13);
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
const TICK_PART_9: u32 = 131;
const TICK_PART_10: u32 = 148;
const TICK_PART_11: u32 = 161;
const TICK_PART_12: u32 = 166;
const TICK_PART_13: u32 = 168;
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
const TICK_DIGEST_9: felt252 =
    1582936084682011356724934723224209689162162094389447800301723069686502032179;
const TICK_DIGEST_10: felt252 =
    2914130800114593077479069006017798304399579241925116561820285687276277351682;
const TICK_DIGEST_11: felt252 =
    1693114807347113218296078483094324171208976754097543185292791108078556916425;
const TICK_DIGEST_12: felt252 =
    598054295845168536442622539257093553383864494982541506295327794208873639112;
const TICK_DIGEST_13: felt252 =
    2317030673723877786572998069192345230257708680292480223034773720851100888327;
