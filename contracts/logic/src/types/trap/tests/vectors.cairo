//! `vectors/trap.jsonl` (RV-03a, D-257): a trap's trigger, `TrapTrait::trigger` as `TrapLibrary`
//! runs it (the words loaded through the content, the entrant found by its entity, the words
//! stored back), with its full inputs and outputs, for the client's mirror of the class; and
//! `TrapTrait::free`, the object index a placement takes. Row 0 is the table's content. The
//! families, their order and the bounds each row sits on are in `vectors/README.md`.

use snforge_std::{DeclareResultTrait, declare};
use starknet::ClassHash;
use crate::interface::{ITrapLibraryDispatcherTrait, ITrapLibraryLibraryDispatcher};
use crate::models::chunk::{Features, FeaturesTrait, Object, object};
use crate::models::goblin::{Goblin, GoblinTrait, GoblinWordsTrait};
use crate::models::member::{Member, MemberTrait, MemberWordsTrait};
use crate::types::combat::{Placer, PlacerTrait, condition, damage, skill_kind, weapon};
use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, shape, target};
use crate::types::executor::tests::body::BodyFixture;
use crate::types::executor::tests::{AT, BRACE, ExecutorFixture, KINDS, SHIELD, SNARE};
use crate::types::executor::{Board, ORIGIN};
use crate::types::tick::{CasteSheet, Content, Held, ai};
use crate::types::world::Words;
use crate::types::world::fixtures::Fixture;
use super::{Ground, TrapTrait};

/// The trap's tile, `(7, 9)`: window position 142, chunk 0's tile 142 (`board()`'s origin is 0).
const SPOT: u8 = 142;
const CLOCK: u32 = 305;
/// The entrant goblin and the placer goblin, both Hobs.
const ENTRANT: u16 = 44;
const PLACER: u16 = 45;
/// The tests' trap skills: a terrain trap's, a guarded pit, caltrops (no hit).
const TERRAIN: u16 = 70;
const PIT: u16 = 71;
const CALTROPS: u16 = 72;
/// Hob's caste skill slot 2, a trap skill here.
const HOB_TRAP: u16 = 26;

#[generate_trait]
impl VectorFixtureImpl of VectorFixture {
    /// The executor tests' content (castes of armor 40, a sword of 30, rank 12; Snare 45: earth 10
    /// to 40, Crippled 3), with Hob's caste skill 26 a trap skill of the same payload; a terrain
    /// trap's skill 70 (earth 10 to 40, Poison 4); 71, a pit (earth 30 to 60 guarded `BELOW_HALF`,
    /// Knocked down 2); 72, caltrops (Bleeding 10 to 22, no hit).
    fn trap_content() -> Content {
        let base = ExecutorFixture::content(40, array![].span());
        let none: Entry = Default::default();
        let trap = ExecutorFixture::entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
        let earth = ExecutorFixture::entry(
            kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let cripple = ExecutorFixture::entry(
            kind::CONDITION, condition::CRIPPLED, 3, 3, target::FOE, shape::SINGLE, filter::FOES,
        );
        let mut skills = array![];
        for sheet in base.skills {
            if *sheet.id == HOB_TRAP {
                skills
                    .append(
                        ExecutorFixture::skill(
                            HOB_TRAP, skill_kind::TRAP, 3, [trap, earth, cripple],
                        ),
                    );
            } else {
                skills.append(*sheet);
            }
        }
        let poison = ExecutorFixture::entry(
            kind::CONDITION, condition::POISON, 4, 4, target::FOE, shape::SINGLE, filter::FOES,
        );
        skills.append(ExecutorFixture::skill(TERRAIN, skill_kind::TRAP, 0, [trap, earth, poison]));
        let pit = EntryTrait::new(
            kind::DAMAGE,
            damage::EARTH,
            30,
            60,
            0,
            0,
            0,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
            guard::BELOW_HALF,
            0,
        );
        let knock = ExecutorFixture::entry(
            kind::CONDITION,
            condition::KNOCKED_DOWN,
            2,
            2,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
        );
        skills.append(ExecutorFixture::skill(PIT, skill_kind::TRAP, 3, [trap, pit, knock]));
        let bleed = ExecutorFixture::entry(
            kind::CONDITION, condition::BLEEDING, 10, 22, target::FOE, shape::SINGLE, filter::FOES,
        );
        skills.append(ExecutorFixture::skill(CALTROPS, skill_kind::TRAP, 3, [trap, bleed, none]));
        Content { skills: skills.span(), ..base }
    }

    /// The trapper: the executor tests' member on `AT` (level 20, health 400 of 480), its bar Snare
    /// (slot 0, rank 12), the pit (slot 1, rank 0), caltrops (slot 2, rank 15), slots 3–6 the
    /// fixtures' 4–7, slot 7 empty.
    fn trapper() -> Member {
        let mut m = ExecutorFixture::member(AT, 0, weapon::BOW);
        m.words.bar += (SNARE.into() - 1)
            + (PIT.into() - 2) * Fixture::two(16)
            + (CALTROPS.into() - 3) * Fixture::two(32)
            - 8 * Fixture::two(112);
        m.words.stats += 12 * Fixture::two(128) + 15 * Fixture::two(136);
        m
    }

    /// A Hob of the executor tests at `position`, its health `health`, its AI state `mind`.
    fn hob(entity: u16, position: u8, health: u16, mind: u8) -> Goblin {
        let mut g = ExecutorFixture::goblin(entity, position, 0, health);
        g.ai = mind;
        g
    }

    fn words(members: Array<Member>, goblins: Array<Goblin>) -> Words {
        let mut stored = array![];
        for m in members {
            stored.append(m.store());
        }
        let mut kept = array![];
        for g in goblins {
            kept.append(g.store());
        }
        Words { clock: CLOCK, members: stored, goblins: kept, killed: array![], defeated: false }
    }

    /// The trapper, the entrant on the trap's tile (health 100, Engaged) and the placer goblin.
    fn world() -> Words {
        Self::words(
            array![Self::trapper()],
            array![
                Self::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
                Self::hob(PLACER, AT + 2, 100, ai::ENGAGED),
            ],
        )
    }

    fn trap(tile: u8, kind: u8, state: u8, param: u16) -> Object {
        Object { tile, kind, state, param }
    }

    fn chunk(c: u8, objects: [Object; 3]) -> (u8, Features) {
        (c, Features { objects, ..FeaturesTrait::empty() })
    }

    /// Chunk 0 holding `first` at index 0, nothing else.
    fn alone(first: Object) -> Ground {
        array![Self::chunk(0, [first, Default::default(), Default::default()])]
    }

    fn member_trap(m: u8, slot: u8) -> Object {
        Self::trap(SPOT, object::PLACED_TRAP, 0, Placer::Member((m, slot)).param())
    }

    fn goblin_trap(entity: u16) -> Object {
        Self::trap(SPOT, object::PLACED_TRAP, 0, Placer::Goblin((entity, 2)).param())
    }

    fn terrain(skill: u16) -> Object {
        Self::trap(SPOT, object::TRAP, 0, skill)
    }

    /// One `trigger` row: `case` the call's arguments but the content (row 0's): `Words`, `Board`,
    /// the ground, the entrant's entity, the window's position, the level; `ok` what it returns:
    /// `Words`, the ground, triggered.
    fn row(
        ref digest: Array<felt252>,
        ref id: u32,
        class: ClassHash,
        content: @Content,
        words: Words,
        board: Board,
        ground: Ground,
        entrant: u16,
        position: u8,
        level: u8,
    ) {
        let mut case = array![];
        Serde::serialize(@words, ref case);
        Serde::serialize(@board, ref case);
        Serde::serialize(@ground, ref case);
        case.append(entrant.into());
        case.append(position.into());
        case.append(level.into());
        let library = ITrapLibraryLibraryDispatcher { class_hash: class };
        let (after, ground, triggered) = library
            .trigger(words, *content, board, ground, entrant, position, level);
        let mut ok = array![];
        Serde::serialize(@after, ref ok);
        Serde::serialize(@ground, ref ok);
        ok.append(if triggered {
            1
        } else {
            0
        });
        BodyFixture::emit(ref digest, ref id, "trigger", case.span(), ok.span());
    }

    fn class() -> ClassHash {
        *declare("TrapLibrary").unwrap().contract_class().class_hash
    }

    /// Row 63's content: row 0's, with Hob's caste skill 27 (slot 3) a trap skill of the pit's
    /// payload (earth 30 to 60 guarded `BELOW_HALF`, Knocked down 2); Runt's caste skill 30 (slot
    /// 2) a trap skill of earth 10 to 40 and Poison 4; Hob's `ARMOR_VS` 9 against earth (type 7,
    /// bits 36–41);
    /// Runt's rank 6; skill 73, the rust (a hex holding `ARMOR` −20 for 5 ticks); skill 74, a
    /// trap skill of earth 10 to 40 and Crippled 3 guarded `BELOW_HALF`.
    fn trap_content_2() -> Content {
        let base = Self::trap_content();
        let none: Entry = Default::default();
        let trap = ExecutorFixture::entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
        let earth = ExecutorFixture::entry(
            kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let pit = EntryTrait::new(
            kind::DAMAGE,
            damage::EARTH,
            30,
            60,
            0,
            0,
            0,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
            guard::BELOW_HALF,
            0,
        );
        let knock = ExecutorFixture::entry(
            kind::CONDITION,
            condition::KNOCKED_DOWN,
            2,
            2,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
        );
        let poison = ExecutorFixture::entry(
            kind::CONDITION, condition::POISON, 4, 4, target::FOE, shape::SINGLE, filter::FOES,
        );
        let mut skills = array![];
        for sheet in base.skills {
            if *sheet.id == HOB_PIT {
                skills
                    .append(
                        ExecutorFixture::skill(HOB_PIT, skill_kind::TRAP, 3, [trap, pit, knock]),
                    );
            } else if *sheet.id == RUNT_TRAP {
                skills
                    .append(
                        ExecutorFixture::skill(
                            RUNT_TRAP, skill_kind::TRAP, 3, [trap, earth, poison],
                        ),
                    );
            } else {
                skills.append(*sheet);
            }
        }
        let rust = EntryTrait::new(
            kind::ARMOR, 0, -20, -20, 5, 5, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
        );
        skills.append(ExecutorFixture::skill(RUST, skill_kind::HEX, 6, [rust, none, none]));
        let cripple = EntryTrait::new(
            kind::CONDITION,
            condition::CRIPPLED,
            3,
            3,
            0,
            0,
            0,
            target::FOE,
            shape::SINGLE,
            filter::FOES,
            guard::BELOW_HALF,
            0,
        );
        skills.append(ExecutorFixture::skill(LAME, skill_kind::TRAP, 3, [trap, earth, cripple]));
        let mut castes: Array<CasteSheet> = array![];
        for caste in base.castes {
            let mut caste = *caste;
            if caste.id == 1 {
                caste.armor_vs = 9 * 0x1000000000;
            } else {
                caste.rank = 6;
            }
            castes.append(caste);
        }
        Content { skills: skills.span(), castes: castes.span(), ..base }
    }

    /// The trapper with skill `id` on bar slot 3 (the fixtures' 4, rank 0).
    fn slot_3(id: u16) -> Member {
        let mut m = Self::trapper();
        m.words.bar += (id.into() - 4) * Fixture::two(48);
        m
    }

    /// The trapper holding skill `id` in effect slot `slot` to `deadline` at rank 12.
    fn guarded(ref m: Member, slot: u8, id: u16, charges: u8, deadline: u32) {
        m.set_effect(slot, Held { carrier: id, potion: false, charges, deadline, rank: 12 }, 0);
    }

    /// Goblin 44 (the entrant) holding skill `id` to `deadline` at rank 12.
    fn entrant_holding(id: u16, deadline: u32) -> Goblin {
        let mut g = Self::hob(ENTRANT, SPOT, 100, ai::ENGAGED);
        GoblinWordsTrait::set_effect(
            ref g, Held { carrier: id, potion: false, charges: 0, deadline, rank: 12 }, 0,
        );
        g
    }

    /// A trap of terrain skill 70 on `tile`, unused.
    fn on_tile(tile: u8) -> Object {
        Self::trap(tile, object::TRAP, 0, TERRAIN)
    }
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

// Row 0, the content; a terrain trap; a member's placed trap and its source.
#[test]
#[available_gas(l2_gas: 574648349)] // ceil(1.05 × 547284141 measured)
fn test_trap_vectors_0() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok = array![];
    Serde::serialize(@content, ref ok);
    BodyFixture::emit(ref digest, ref id, "content", array![].span(), ok.span());
    let b = ExecutorFixture::board();
    // A terrain trap (kind 4, `param` skill 70): on the member at the band's level 20, 1 and 40;
    // on a goblin, nothing; a skill the content lacks, nothing (the trap stays unused); used
    // (state 1), nothing; on the member at 1 health: killed, Poison not applied.
    for level in array![20_u8, 1, 40] {
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            VectorFixture::world(),
            b,
            VectorFixture::alone(VectorFixture::terrain(TERRAIN)),
            0,
            SPOT,
            level,
        );
    }
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::terrain(TERRAIN)),
        ENTRANT,
        SPOT,
        20,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::terrain(99)),
        0,
        SPOT,
        20,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::trap(SPOT, object::TRAP, 1, TERRAIN)),
        0,
        SPOT,
        20,
    );
    let mut weak = VectorFixture::trapper();
    weak.health = 1;
    let goblins = array![
        VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
        VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
    ];
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::words(array![weak], goblins),
        b,
        VectorFixture::alone(VectorFixture::terrain(TERRAIN)),
        0,
        SPOT,
        20,
    );
    // A member's trap (Snare, bar slot 0, rank 12, level 20) on goblin 44 (§10.10: 100 → 44,
    // Crippled); on the member itself, its own side, nothing; on a second member, nothing.
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 0)),
        ENTRANT,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 0)),
        0,
        SPOT,
        0,
    );
    let pair = VectorFixture::words(
        array![VectorFixture::trapper(), ExecutorFixture::member(AT + 1, 0, weapon::SWORD)],
        array![
            VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
            VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
        ],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        pair.clone(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 0)),
        1,
        SPOT,
        0,
    );
    // The placer: member 1 of a world of one (`m ≥ count`: nothing); member 1 of two (it
    // triggers, member 1's source: no Snare on its bar slot 0, skill 1); bar slot 7 empty
    // (`ABSENT_LANE`: nothing).
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(1, 0)),
        ENTRANT,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        pair,
        b,
        VectorFixture::alone(VectorFixture::member_trap(1, 0)),
        ENTRANT,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 7)),
        ENTRANT,
        SPOT,
        0,
    );
    BodyFixture::finish(digest, TRAP_DIGEST_0);
}

// The source's guards, rank and `Infliction`.
#[test]
#[available_gas(l2_gas: 388584934)] // ceil(1.05 × 370080889 measured)
fn test_trap_vectors_1() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_1;
    let b = ExecutorFixture::board();
    let goblins = array![
        VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
        VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
    ];
    // The pit (bar slot 1, rank 0): its hit guarded `BELOW_HALF` on the placer (health × 2 <
    // 480): at 400 and at 240 not held (no hit, the knock-down applies), at 239 held.
    for health in array![400_u16, 240, 239] {
        let mut placer = VectorFixture::trapper();
        placer.health = health;
        let w = VectorFixture::words(array![placer], goblins.clone());
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 1)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    // Caltrops (bar slot 2, rank 15: Bleeding 10 + 12 × 15 / 12 = 25), no hit; then the
    // placer's `CONDITION_DURATION` (`MemberKit` 144, 148): Bleeding at 33 % (33), at 63 %
    // (capped at 50: 37), Poison at 33 % (another condition: 25).
    let kits = array![
        0_felt252, 1 + 33 * Fixture::two(4), 1 + 63 * Fixture::two(4), 2 + 33 * Fixture::two(4),
    ];
    for kit in kits {
        let mut placer = VectorFixture::trapper();
        placer.words.kit += kit * Fixture::two(144);
        let w = VectorFixture::words(array![placer], goblins.clone());
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 2)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    // `KNOCKDOWN_FLAT` 3 (`MemberKit` 200) with the pit's hit held (239): Knocked down 2 + 3.
    let mut placer = VectorFixture::trapper();
    placer.health = 239;
    placer.words.kit += 3 * Fixture::two(200);
    let w = VectorFixture::words(array![placer], goblins.clone());
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 1)),
        ENTRANT,
        SPOT,
        0,
    );
    // Snare at rank 0 and at rank 15 (its earth 10 and 47).
    for rank in array![0_felt252, 15] {
        let mut placer = VectorFixture::trapper();
        placer.words.stats += (rank - 12) * Fixture::two(128);
        let w = VectorFixture::words(array![placer], goblins.clone());
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 0)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    BodyFixture::finish(digest, TRAP_DIGEST_1);
}

// A goblin's placed trap; the entrant's state.
#[test]
#[available_gas(l2_gas: 471357511)] // ceil(1.05 × 448911915 measured)
fn test_trap_vectors_2() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_2;
    let b = ExecutorFixture::board();
    // Goblin 45's trap (caste slot 2, skill 26, rank 12, its level 10): on the member; on goblin
    // 44, its side, nothing; its placer dead (its record still holds it); its placer not in the
    // call (entity 46), nothing.
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
        0,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
        ENTRANT,
        SPOT,
        0,
    );
    let dead = VectorFixture::words(
        array![VectorFixture::trapper()],
        array![
            VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
            VectorFixture::hob(PLACER, AT + 2, 0, ai::DEAD),
        ],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        dead,
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
        0,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(46)),
        0,
        SPOT,
        0,
    );
    // The entrant, under Snare: asleep (critical, wakes), on watch (wakes), at 1 health (killed,
    // in `killed`; Crippled not applied).
    for (health, mind) in array![(100_u16, ai::ASLEEP), (100, ai::WATCH), (1, ai::ENGAGED)] {
        let w = VectorFixture::words(
            array![VectorFixture::trapper()],
            array![
                VectorFixture::hob(ENTRANT, SPOT, health, mind),
                VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
            ],
        );
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 0)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    // The member under goblin 45's trap: holding Brace (43, a `BLOCK` charge, to 400; a trap's
    // hit is never blocked: the charge stays), Sidestep (42, `EVADE`: never evaded), Knocked
    // down to 400.
    let effects = array![
        43 + Fixture::two(16) + 400 * Fixture::two(24), 42 + 400 * Fixture::two(24),
    ];
    for effect in effects {
        let mut m = VectorFixture::trapper();
        m.words.effects += effect;
        let w = VectorFixture::words(
            array![m],
            array![
                VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
                VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
            ],
        );
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
            0,
            SPOT,
            0,
        );
    }
    let mut knocked = VectorFixture::trapper();
    knocked.knocked = 400;
    let w = VectorFixture::words(
        array![knocked],
        array![
            VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
            VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
        ],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
        0,
        SPOT,
        0,
    );
    // An entrant the call does not hold: entity 99, member 1 of one: nothing.
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::terrain(TERRAIN)),
        99,
        SPOT,
        20,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::terrain(TERRAIN)),
        1,
        SPOT,
        20,
    );
    BodyFixture::finish(digest, TRAP_DIGEST_2);
}

// The lookup: the object index and the ground's entry written, the window's position.
#[test]
#[available_gas(l2_gas: 538998801)] // ceil(1.05 × 513332191 measured)
fn test_trap_vectors_3() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_3;
    let b = ExecutorFixture::board();
    let chest = VectorFixture::trap(SPOT, object::CHEST, 0, 0);
    let used = VectorFixture::trap(SPOT, object::PLACED_TRAP, 1, Placer::Member((0, 0)).param());
    let t = VectorFixture::terrain(TERRAIN);
    let grounds: Array<Ground> = array![
        // A chest on the tile at 0, the trap at 1: index 1 written.
        array![VectorFixture::chunk(0, [chest, t, Default::default()])],
        // A chunk of 3 objects, used traps on the tile at 0 and 1: index 2.
        array![
            VectorFixture::chunk(0, [used, VectorFixture::trap(SPOT, object::TRAP, 1, TERRAIN), t]),
        ],
        // The trap on another tile: nothing.
        VectorFixture::alone(VectorFixture::trap(SPOT + 1, object::TRAP, 0, TERRAIN)),
        // Chunk 0 the ground's second entry: entry 1 written, entry 0 kept.
        array![
            VectorFixture::chunk(
                1,
                [
                    VectorFixture::trap(SPOT, object::TRAP, 0, TERRAIN), Default::default(),
                    Default::default(),
                ],
            ),
            VectorFixture::chunk(0, [t, Default::default(), Default::default()]),
        ],
        // No chunk 0: nothing.
        array![VectorFixture::chunk(1, [t, Default::default(), Default::default()])],
        // Chunk 0 twice, the trap in the second: only the first is read, nothing.
        array![
            VectorFixture::chunk(0, [Default::default(); 3]),
            VectorFixture::chunk(0, [t, Default::default(), Default::default()]),
        ],
    ];
    for ground in grounds {
        VectorFixture::row(
            ref digest, ref id, class, @content, VectorFixture::world(), b, ground, 0, SPOT, 20,
        );
    }
    // The window's position: 240 (outside), nothing; 239, the window's last: chunk 15, tile 14.
    let last = array![
        VectorFixture::chunk(
            15,
            [
                VectorFixture::trap(14, object::TRAP, 0, TERRAIN), Default::default(),
                Default::default(),
            ],
        ),
    ];
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), b, last.clone(), 0, 240, 20,
    );
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), b, last, 0, 239, 20,
    );
    // A board whose origin is negative, `(−5, 0)` (`x` held as 10): position 0 lies before the
    // location (nothing); position 5 is its tile (0, 0), chunk 0's tile 0.
    let west = Board { window: ExecutorFixture::open(), x: ORIGIN - 5, y: ORIGIN };
    let corner = VectorFixture::alone(VectorFixture::trap(0, object::TRAP, 0, TERRAIN));
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), west, corner.clone(), 0, 0, 20,
    );
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), west, corner, 0, 5, 20,
    );
    // The location's East edge: origin x 210, position 14 is tile (224, 0), chunk 14's tile 14;
    // origin 240, position 14 is column 254, chunk column 16: none. Its North edge: origin y
    // 240, row 240, chunk row 16: none.
    let east = array![
        VectorFixture::chunk(
            14,
            [
                VectorFixture::trap(14, object::TRAP, 0, TERRAIN), Default::default(),
                Default::default(),
            ],
        ),
    ];
    let edge = Board { window: ExecutorFixture::open(), x: ORIGIN + 210, y: ORIGIN };
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), edge, east.clone(), 0, 14, 20,
    );
    let beyond = Board { window: ExecutorFixture::open(), x: ORIGIN + 240, y: ORIGIN };
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), beyond, east, 0, 14, 20,
    );
    let north = Board { window: ExecutorFixture::open(), x: ORIGIN, y: ORIGIN + 240 };
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        north,
        VectorFixture::alone(VectorFixture::trap(0, object::TRAP, 0, TERRAIN)),
        0,
        0,
        20,
    );
    // `free` (placing, §5.11): the lowest index that is empty or a used trap; `None` when the
    // tile holds another object, or no index is free. `case` the chunk's `Features` and the
    // tile, `ok` the `Option<u32>`.
    let at = 9_u8;
    let other = VectorFixture::trap(7, object::CHEST, 0, 0);
    let frees: Array<([Object; 3], u8)> = array![
        ([Default::default(); 3], at), ([other, Default::default(), Default::default()], at),
        (
            [
                VectorFixture::trap(7, object::PLACED_TRAP, 1, 0), Default::default(),
                Default::default(),
            ],
            at,
        ),
        ([VectorFixture::trap(7, object::TRAP, 1, 0), Default::default(), Default::default()], at),
        (
            [VectorFixture::trap(at, object::CHEST, 0, 0), Default::default(), Default::default()],
            at,
        ),
        (
            [
                VectorFixture::trap(at, object::PLACED_TRAP, 0, 0), Default::default(),
                Default::default(),
            ],
            at,
        ),
        ([other, VectorFixture::trap(at, object::PLACED_TRAP, 1, 0), Default::default()], at),
        (
            [
                other, VectorFixture::trap(8, object::VEIN, 1, 0),
                VectorFixture::trap(6, object::TRAP, 0, 3),
            ],
            at,
        ),
        (
            [
                other, VectorFixture::trap(8, object::VEIN, 1, 0),
                VectorFixture::trap(6, object::TRAP, 1, 3),
            ],
            at,
        ),
        ([VectorFixture::trap(at, object::NONE, 0, 0), other, Default::default()], at),
    ];
    for (objects, tile) in frees {
        let features = Features { objects, ..FeaturesTrait::empty() };
        let mut case = array![];
        Serde::serialize(@features, ref case);
        case.append(tile.into());
        let mut ok = array![];
        Serde::serialize(@TrapTrait::free(@features, tile), ref ok);
        BodyFixture::emit(ref digest, ref id, "free", case.span(), ok.span());
    }
    BodyFixture::finish(digest, TRAP_DIGEST_3);
}

// Appended by RV-03a's fix loop 1 (the review of #440), after every earlier id: a negative origin
// on the y axis; a goblin placer on another caste slot.
#[test]
#[available_gas(l2_gas: 158320785)] // ceil(1.05 × 150781700 measured)
fn test_trap_vectors_4() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_4;
    // A board whose origin is negative, `(0, −5)` (`y` held as 10): position 0 lies before the
    // location (nothing); position 75 (row 5) is its tile (0, 0), chunk 0's tile 0.
    let south = Board { window: ExecutorFixture::open(), x: ORIGIN, y: ORIGIN - 5 };
    let corner = VectorFixture::alone(VectorFixture::trap(0, object::TRAP, 0, TERRAIN));
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        south,
        corner.clone(),
        0,
        0,
        20,
    );
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), south, corner, 0, 75, 20,
    );
    // Goblin 45's trap from caste slot 0 (skill 24) and slot 3 (skill 27), neither a trap skill
    // nor holding an entry: it triggers on the member, nothing applied, the trap used; slot 2's
    // Snare payload (row 24) is not read.
    let b = ExecutorFixture::board();
    for slot in array![0_u8, 3] {
        let placed = VectorFixture::trap(
            SPOT, object::PLACED_TRAP, 0, Placer::Goblin((PLACER, slot)).param(),
        );
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            VectorFixture::world(),
            b,
            VectorFixture::alone(placed),
            0,
            SPOT,
            0,
        );
    }
    BodyFixture::finish(digest, TRAP_DIGEST_4);
}

// ---- Appended by RV-03a2 (D-257): track CV's surviving mutants of the trap port (#444). Every
// row from id 63 on reads the content of row 63, the last `content` row before it.

/// Hob's caste skill slot 3, Runt's slot 2 (the fixtures' 27 and 30): trap skills in row 63's
/// content.
const HOB_PIT: u16 = 27;
const RUNT_TRAP: u16 = 30;
/// Row 63's own skills: the rust (a hex holding `ARMOR` −20); a trap skill whose Crippled is
/// guarded `BELOW_HALF`.
const RUST: u16 = 73;
const LAME: u16 = 74;

// Row 63, the content; the lookup's bounds (the window's last position, the location's East and
// North edges, West of its first tile), each ground holding a trap where a port without the
// bound would look.
#[test]
#[available_gas(l2_gas: 243853060)] // ceil(1.05 × 232241009 measured)
fn test_trap_vectors_5() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_5;
    let mut ok = array![];
    Serde::serialize(@content, ref ok);
    BodyFixture::emit(ref digest, ref id, "content", array![].span(), ok.span());
    let none: Object = Default::default();
    // Position 240 (row 16 of the window): outside, nothing; read as inside it is chunk 15's
    // tile 15, which the ground holds.
    let b = ExecutorFixture::board();
    let fifteen = array![VectorFixture::chunk(15, [VectorFixture::on_tile(15), none, none])];
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), b, fifteen, 0, 240, 20,
    );
    // Origin x 240, position 14: column 254, chunk column 16, nothing; without the column's bound
    // it is chunk 16 (`15 cy + cx`, the next row's), tile 14, which the ground holds.
    let beyond = Board { window: ExecutorFixture::open(), x: ORIGIN + 240, y: ORIGIN };
    let sixteen = array![VectorFixture::chunk(16, [VectorFixture::on_tile(14), none, none])];
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), beyond, sixteen, 0, 14, 20,
    );
    // Origin y 240, position 0: chunk row 16, chunk 240, nothing; origin y 225: chunk row 15,
    // chunk 225 (`MAX_CHUNKS`, on the bound), nothing; the ground holds each.
    let north = Board { window: ExecutorFixture::open(), x: ORIGIN, y: ORIGIN + 240 };
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        north,
        array![VectorFixture::chunk(240, [VectorFixture::on_tile(0), none, none])],
        0,
        0,
        20,
    );
    let last = Board { window: ExecutorFixture::open(), x: ORIGIN, y: ORIGIN + 225 };
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        last,
        array![VectorFixture::chunk(225, [VectorFixture::on_tile(0), none, none])],
        0,
        0,
        20,
    );
    // West of the location: origin `(−5, 15)` (`x` held as 10, `y` as 30), position 15 (row 1,
    // column 0): x before the location, nothing. Without the West guard, `x − ORIGIN` is −5:
    // chunk `15 · 1 − 1` = 14, its tile 10 (a remainder toward zero, 15 − 5) or 25 (a floored
    // one, 15 +
    // 10); the ground's chunk 14 holds a trap on each.
    let west = Board { window: ExecutorFixture::open(), x: ORIGIN - 5, y: ORIGIN + 15 };
    let fourteen = array![
        VectorFixture::chunk(14, [VectorFixture::on_tile(10), VectorFixture::on_tile(25), none]),
    ];
    VectorFixture::row(
        ref digest, ref id, class, @content, VectorFixture::world(), west, fourteen, 0, 15, 20,
    );
    BodyFixture::finish(digest, TRAP_DIGEST_5);
}

// The entrant's defence: its `ARMOR_VS` against the trap's earth, its armor terms, its held
// `ARMOR` effects on each side of their deadline, a negative one.
#[test]
#[available_gas(l2_gas: 392697618)] // ceil(1.05 × 373997731 measured)
fn test_trap_vectors_6() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_6;
    let b = ExecutorFixture::board();
    let goblins = array![
        VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
        VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
    ];
    let placed = VectorFixture::alone(VectorFixture::goblin_trap(PLACER));
    // The member under goblin 45's trap (Snare's earth at rank 12) with `ARMOR_VS` 9 against earth
    // (`MemberStats` 224–229); goblin 44 under the member's Snare, Hob's `ARMOR_VS` 9 against
    // earth.
    let mut m = VectorFixture::trapper();
    m.words.stats += 9 * Fixture::two(224);
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::words(array![m], goblins.clone()),
        b,
        placed.clone(),
        0,
        SPOT,
        0,
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        VectorFixture::world(),
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 0)),
        ENTRANT,
        SPOT,
        0,
    );
    // The member's armor 10 (`MemberBar` 232–247), its stance sum 4 and its enchanted sum 3
    // (`MemberKit` 184–191, 192–199): holding Brace (a stance, slot 0) and the shield (`ARMOR`
    // 30, an enchantment, slot 1) to 400, every term counts; holding neither, the armor alone.
    let mut sums = VectorFixture::trapper();
    sums.words.bar += 10 * Fixture::two(232);
    sums.words.kit += 4 * Fixture::two(184) + 3 * Fixture::two(192);
    let mut both = sums;
    VectorFixture::guarded(ref both, 0, BRACE, 1, 400);
    VectorFixture::guarded(ref both, 1, SHIELD, 0, 400);
    for m in array![both, sums] {
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            VectorFixture::words(array![m], goblins.clone()),
            b,
            placed.clone(),
            0,
            SPOT,
            0,
        );
    }
    // The member holding the shield to the clock 305 (held: `deadline ≥ t`) and to 304 (lapsed);
    // the rust (−20, clamped to 0) and the shield together (30, not 10).
    let mut held = VectorFixture::trapper();
    VectorFixture::guarded(ref held, 1, SHIELD, 0, CLOCK);
    let mut lapsed = VectorFixture::trapper();
    VectorFixture::guarded(ref lapsed, 1, SHIELD, 0, CLOCK - 1);
    let mut rusted = VectorFixture::trapper();
    VectorFixture::guarded(ref rusted, 0, RUST, 0, 400);
    VectorFixture::guarded(ref rusted, 1, SHIELD, 0, 400);
    for m in array![held, lapsed, rusted] {
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            VectorFixture::words(array![m], goblins.clone()),
            b,
            placed.clone(),
            0,
            SPOT,
            0,
        );
    }
    // Goblin 44 under the member's Snare holding the shield to 305 (held) and 304 (lapsed); the
    // rust alone (−20, clamped to 0).
    for (skill, deadline) in array![(SHIELD, CLOCK), (SHIELD, CLOCK - 1), (RUST, 400)] {
        let w = VectorFixture::words(
            array![VectorFixture::trapper()],
            array![
                VectorFixture::entrant_holding(skill, deadline),
                VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
            ],
        );
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 0)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    BodyFixture::finish(digest, TRAP_DIGEST_6);
}

// The payload: a goblin placer's guarded hit, a member placer's guarded condition, the `HEAL`,
// `CURE`, `ENERGY` and holding entries, a dead goblin entering, a placer of another caste.
#[test]
#[available_gas(l2_gas: 320514261)] // ceil(1.05 × 305251677 measured)
fn test_trap_vectors_7() {
    let class = VectorFixture::class();
    let content = VectorFixture::trap_content_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_7;
    let b = ExecutorFixture::board();
    // Goblin 45's trap from caste slot 3 (skill 27: earth 30 to 60 guarded `BELOW_HALF`, Knocked
    // down 2) on the member, the placer at 140 of 280 (not held: the knock-down alone) and 139
    // (held).
    let pit = VectorFixture::alone(
        VectorFixture::trap(SPOT, object::PLACED_TRAP, 0, Placer::Goblin((PLACER, 3)).param()),
    );
    for health in array![140_u16, 139] {
        let w = VectorFixture::words(
            array![VectorFixture::trapper()],
            array![
                VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
                VectorFixture::hob(PLACER, AT + 2, health, ai::ENGAGED),
            ],
        );
        VectorFixture::row(ref digest, ref id, class, @content, w, b, pit.clone(), 0, SPOT, 0);
    }
    // The member's trap from bar slot 3 holding skill 74 (earth, Crippled guarded `BELOW_HALF`)
    // on goblin 44, the placer at 400 of 480 (not held: the hit alone) and 239 (held).
    for health in array![400_u16, 239] {
        let mut m = VectorFixture::slot_3(LAME);
        m.health = health;
        let w = VectorFixture::words(
            array![m],
            array![
                VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
                VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
            ],
        );
        VectorFixture::row(
            ref digest,
            ref id,
            class,
            @content,
            w,
            b,
            VectorFixture::alone(VectorFixture::member_trap(0, 3)),
            ENTRANT,
            SPOT,
            0,
        );
    }
    // Bar slot 3 holding skill 47 (heal 30, cure Bleeding, 5 energy) on goblin 44, Bleeding to
    // 400: healed to 130, cured, energized; holding the shield (an enchantment's `ARMOR`): goblin
    // 44 holds it.
    let mut bleeding = VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED);
    bleeding.bleeding = 400;
    let w = VectorFixture::words(
        array![VectorFixture::slot_3(KINDS)],
        array![bleeding, VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED)],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 3)),
        ENTRANT,
        SPOT,
        0,
    );
    let w = VectorFixture::words(
        array![VectorFixture::slot_3(SHIELD)],
        array![
            VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED),
            VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
        ],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 3)),
        ENTRANT,
        SPOT,
        0,
    );
    // A dead goblin (health 0, `DEAD`) entering the member's Snare: it triggers, nothing applied,
    // and it is not killed again (`killed` stays empty).
    let w = VectorFixture::words(
        array![VectorFixture::trapper()],
        array![
            VectorFixture::hob(ENTRANT, SPOT, 0, ai::DEAD),
            VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED),
        ],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::member_trap(0, 0)),
        ENTRANT,
        SPOT,
        0,
    );
    // Goblin 45 a Runt of level 16 (its caste rank 6), goblin 44 a Hob of level 10: its trap from
    // caste slot 2 (Runt's skill 30: earth, Poison 4) on the member; the Hob's slot 2 (Snare), its
    // rank 12 and its level are not the source.
    let mut runt = VectorFixture::hob(PLACER, AT + 2, 100, ai::ENGAGED);
    runt.state += Fixture::two(64) + 6 * Fixture::two(80);
    let w = VectorFixture::words(
        array![VectorFixture::trapper()],
        array![VectorFixture::hob(ENTRANT, SPOT, 100, ai::ENGAGED), runt],
    );
    VectorFixture::row(
        ref digest,
        ref id,
        class,
        @content,
        w,
        b,
        VectorFixture::alone(VectorFixture::goblin_trap(PLACER)),
        0,
        SPOT,
        0,
    );
    BodyFixture::finish(digest, TRAP_DIGEST_7);
}

/// The first id of each part, and each part's digest.
const TRAP_PART_1: u32 = 14;
const TRAP_PART_2: u32 = 24;
const TRAP_PART_3: u32 = 36;
const TRAP_PART_4: u32 = 59;
const TRAP_PART_5: u32 = 63;
const TRAP_PART_6: u32 = 69;
const TRAP_PART_7: u32 = 79;
const TRAP_DIGEST_0: felt252 =
    2787498107184120386038607310383447558271195683507077469272024736095572910618;
const TRAP_DIGEST_1: felt252 =
    28586507383434623868094572723670594695203416324847342307105816419457224450;
const TRAP_DIGEST_2: felt252 =
    3438638085967200555492296647354720432742156539403220268880570701724845901951;
const TRAP_DIGEST_3: felt252 =
    3075499101549686030732729308817093250590815560376692689788891479222492881474;
const TRAP_DIGEST_4: felt252 =
    2230414804466176496992525929743744514951125034518003269410151585528301294780;
const TRAP_DIGEST_5: felt252 =
    1143514613547480855758157787459522051546000614263460163426820701149065072345;
const TRAP_DIGEST_6: felt252 =
    1951498054139824216706528105397110888718285796424453164430890230858788909660;
const TRAP_DIGEST_7: felt252 =
    2130154780865369211456725098921882948040016459795604852026055806414239975124;
