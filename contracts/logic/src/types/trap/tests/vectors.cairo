//! `vectors/trap.jsonl` (RV-03a, D-257): a trap's trigger, `TrapTrait::trigger` as `TrapLibrary`
//! runs it (the words loaded through the content, the entrant found by its entity, the words
//! stored back), with its full inputs and outputs, for the client's mirror of the class; and
//! `TrapTrait::free`, the object index a placement takes. Row 0 is the table's content. The
//! families, their order and the bounds each row sits on are in `vectors/README.md`.

use snforge_std::{DeclareResultTrait, declare};
use starknet::ClassHash;
use crate::interface::{ITrapLibraryDispatcherTrait, ITrapLibraryLibraryDispatcher};
use crate::models::chunk::{Features, FeaturesTrait, Object, object};
use crate::models::goblin::{Goblin, GoblinTrait};
use crate::models::member::{Member, MemberTrait};
use crate::types::combat::{Placer, PlacerTrait, condition, damage, skill_kind, weapon};
use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, shape, target};
use crate::types::executor::tests::body::{emit, finish};
use crate::types::executor::tests::{AT, SNARE, board, content, entry, goblin, member, open, skill};
use crate::types::executor::{Board, ORIGIN};
use crate::types::tick::{Content, ai};
use crate::types::world::Words;
use crate::types::world::fixtures::two;
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

/// The executor tests' content (castes of armor 40, a sword of 30, rank 12; Snare 45: earth 10 to
/// 40, Crippled 3), with Hob's caste skill 26 a trap skill of the same payload; a terrain trap's
/// skill 70 (earth 10 to 40, Poison 4); 71, a pit (earth 30 to 60 guarded `BELOW_HALF`, Knocked
/// down 2); 72, caltrops (Bleeding 10 to 22, no hit).
fn trap_content() -> Content {
    let base = content(40, array![].span());
    let none: Entry = Default::default();
    let trap = entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
    let earth = entry(
        kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
    );
    let cripple = entry(
        kind::CONDITION, condition::CRIPPLED, 3, 3, target::FOE, shape::SINGLE, filter::FOES,
    );
    let mut skills = array![];
    for sheet in base.skills {
        if *sheet.id == HOB_TRAP {
            skills.append(skill(HOB_TRAP, skill_kind::TRAP, 3, [trap, earth, cripple]));
        } else {
            skills.append(*sheet);
        }
    }
    let poison = entry(
        kind::CONDITION, condition::POISON, 4, 4, target::FOE, shape::SINGLE, filter::FOES,
    );
    skills.append(skill(TERRAIN, skill_kind::TRAP, 0, [trap, earth, poison]));
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
    let knock = entry(
        kind::CONDITION, condition::KNOCKED_DOWN, 2, 2, target::FOE, shape::SINGLE, filter::FOES,
    );
    skills.append(skill(PIT, skill_kind::TRAP, 3, [trap, pit, knock]));
    let bleed = entry(
        kind::CONDITION, condition::BLEEDING, 10, 22, target::FOE, shape::SINGLE, filter::FOES,
    );
    skills.append(skill(CALTROPS, skill_kind::TRAP, 3, [trap, bleed, none]));
    Content { skills: skills.span(), ..base }
}

/// The trapper: the executor tests' member on `AT` (level 20, health 400 of 480), its bar Snare
/// (slot 0, rank 12), the pit (slot 1, rank 0), caltrops (slot 2, rank 15), slots 3–6 the
/// fixtures' 4–7, slot 7 empty.
fn trapper() -> Member {
    let mut m = member(AT, 0, weapon::BOW);
    m.words.bar += (SNARE.into() - 1)
        + (PIT.into() - 2) * two(16)
        + (CALTROPS.into() - 3) * two(32)
        - 8 * two(112);
    m.words.stats += 12 * two(128) + 15 * two(136);
    m
}

/// A Hob of the executor tests at `position`, its health `health`, its AI state `mind`.
fn hob(entity: u16, position: u8, health: u16, mind: u8) -> Goblin {
    let mut g = goblin(entity, position, 0, health);
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
    words(
        array![trapper()],
        array![hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED)],
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
    array![chunk(0, [first, Default::default(), Default::default()])]
}

fn member_trap(m: u8, slot: u8) -> Object {
    trap(SPOT, object::PLACED_TRAP, 0, Placer::Member((m, slot)).param())
}

fn goblin_trap(entity: u16) -> Object {
    trap(SPOT, object::PLACED_TRAP, 0, Placer::Goblin((entity, 2)).param())
}

fn terrain(skill: u16) -> Object {
    trap(SPOT, object::TRAP, 0, skill)
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
    emit(ref digest, ref id, "trigger", case.span(), ok.span());
}

fn class() -> ClassHash {
    *declare("TrapLibrary").unwrap().contract_class().class_hash
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

// Row 0, the content; a terrain trap; a member's placed trap and its source.
#[test]
#[available_gas(l2_gas: 574648349)] // ceil(1.05 × 547284141 measured)
fn test_trap_vectors_0() {
    let class = class();
    let content = trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok = array![];
    Serde::serialize(@content, ref ok);
    emit(ref digest, ref id, "content", array![].span(), ok.span());
    let b = board();
    // A terrain trap (kind 4, `param` skill 70): on the member at the band's level 20, 1 and 40;
    // on a goblin, nothing; a skill the content lacks, nothing (the trap stays unused); used
    // (state 1), nothing; on the member at 1 health: killed, Poison not applied.
    for level in array![20_u8, 1, 40] {
        row(
            ref digest,
            ref id,
            class,
            @content,
            world(),
            b,
            alone(terrain(TERRAIN)),
            0,
            SPOT,
            level,
        );
    }
    row(
        ref digest, ref id, class, @content, world(), b, alone(terrain(TERRAIN)), ENTRANT, SPOT, 20,
    );
    row(ref digest, ref id, class, @content, world(), b, alone(terrain(99)), 0, SPOT, 20);
    row(
        ref digest,
        ref id,
        class,
        @content,
        world(),
        b,
        alone(trap(SPOT, object::TRAP, 1, TERRAIN)),
        0,
        SPOT,
        20,
    );
    let mut weak = trapper();
    weak.health = 1;
    let goblins = array![
        hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED),
    ];
    row(
        ref digest,
        ref id,
        class,
        @content,
        words(array![weak], goblins),
        b,
        alone(terrain(TERRAIN)),
        0,
        SPOT,
        20,
    );
    // A member's trap (Snare, bar slot 0, rank 12, level 20) on goblin 44 (§10.10: 100 → 44,
    // Crippled); on the member itself, its own side, nothing; on a second member, nothing.
    row(
        ref digest, ref id, class, @content, world(), b, alone(member_trap(0, 0)), ENTRANT, SPOT, 0,
    );
    row(ref digest, ref id, class, @content, world(), b, alone(member_trap(0, 0)), 0, SPOT, 0);
    let pair = words(
        array![trapper(), member(AT + 1, 0, weapon::SWORD)],
        array![hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED)],
    );
    row(ref digest, ref id, class, @content, pair.clone(), b, alone(member_trap(0, 0)), 1, SPOT, 0);
    // The placer: member 1 of a world of one (`m ≥ count`: nothing); member 1 of two (it
    // triggers, member 1's source: no Snare on its bar slot 0, skill 1); bar slot 7 empty
    // (`ABSENT_LANE`: nothing).
    row(
        ref digest, ref id, class, @content, world(), b, alone(member_trap(1, 0)), ENTRANT, SPOT, 0,
    );
    row(ref digest, ref id, class, @content, pair, b, alone(member_trap(1, 0)), ENTRANT, SPOT, 0);
    row(
        ref digest, ref id, class, @content, world(), b, alone(member_trap(0, 7)), ENTRANT, SPOT, 0,
    );
    finish(digest, TRAP_DIGEST_0);
}

// The source's guards, rank and `Infliction`.
#[test]
#[available_gas(l2_gas: 388584934)] // ceil(1.05 × 370080889 measured)
fn test_trap_vectors_1() {
    let class = class();
    let content = trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_1;
    let b = board();
    let goblins = array![
        hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED),
    ];
    // The pit (bar slot 1, rank 0): its hit guarded `BELOW_HALF` on the placer (health × 2 <
    // 480): at 400 and at 240 not held (no hit, the knock-down applies), at 239 held.
    for health in array![400_u16, 240, 239] {
        let mut placer = trapper();
        placer.health = health;
        let w = words(array![placer], goblins.clone());
        row(ref digest, ref id, class, @content, w, b, alone(member_trap(0, 1)), ENTRANT, SPOT, 0);
    }
    // Caltrops (bar slot 2, rank 15: Bleeding 10 + 12 × 15 / 12 = 25), no hit; then the
    // placer's `CONDITION_DURATION` (`MemberKit` 144, 148): Bleeding at 33 % (33), at 63 %
    // (capped at 50: 37), Poison at 33 % (another condition: 25).
    let kits = array![0_felt252, 1 + 33 * two(4), 1 + 63 * two(4), 2 + 33 * two(4)];
    for kit in kits {
        let mut placer = trapper();
        placer.words.kit += kit * two(144);
        let w = words(array![placer], goblins.clone());
        row(ref digest, ref id, class, @content, w, b, alone(member_trap(0, 2)), ENTRANT, SPOT, 0);
    }
    // `KNOCKDOWN_FLAT` 3 (`MemberKit` 200) with the pit's hit held (239): Knocked down 2 + 3.
    let mut placer = trapper();
    placer.health = 239;
    placer.words.kit += 3 * two(200);
    let w = words(array![placer], goblins.clone());
    row(ref digest, ref id, class, @content, w, b, alone(member_trap(0, 1)), ENTRANT, SPOT, 0);
    // Snare at rank 0 and at rank 15 (its earth 10 and 47).
    for rank in array![0_felt252, 15] {
        let mut placer = trapper();
        placer.words.stats += (rank - 12) * two(128);
        let w = words(array![placer], goblins.clone());
        row(ref digest, ref id, class, @content, w, b, alone(member_trap(0, 0)), ENTRANT, SPOT, 0);
    }
    finish(digest, TRAP_DIGEST_1);
}

// A goblin's placed trap; the entrant's state.
#[test]
#[available_gas(l2_gas: 471357511)] // ceil(1.05 × 448911915 measured)
fn test_trap_vectors_2() {
    let class = class();
    let content = trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_2;
    let b = board();
    // Goblin 45's trap (caste slot 2, skill 26, rank 12, its level 10): on the member; on goblin
    // 44, its side, nothing; its placer dead (its record still holds it); its placer not in the
    // call (entity 46), nothing.
    row(ref digest, ref id, class, @content, world(), b, alone(goblin_trap(PLACER)), 0, SPOT, 0);
    row(
        ref digest,
        ref id,
        class,
        @content,
        world(),
        b,
        alone(goblin_trap(PLACER)),
        ENTRANT,
        SPOT,
        0,
    );
    let dead = words(
        array![trapper()],
        array![hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 0, ai::DEAD)],
    );
    row(ref digest, ref id, class, @content, dead, b, alone(goblin_trap(PLACER)), 0, SPOT, 0);
    row(ref digest, ref id, class, @content, world(), b, alone(goblin_trap(46)), 0, SPOT, 0);
    // The entrant, under Snare: asleep (critical, wakes), on watch (wakes), at 1 health (killed,
    // in `killed`; Crippled not applied).
    for (health, mind) in array![(100_u16, ai::ASLEEP), (100, ai::WATCH), (1, ai::ENGAGED)] {
        let w = words(
            array![trapper()],
            array![hob(ENTRANT, SPOT, health, mind), hob(PLACER, AT + 2, 100, ai::ENGAGED)],
        );
        row(ref digest, ref id, class, @content, w, b, alone(member_trap(0, 0)), ENTRANT, SPOT, 0);
    }
    // The member under goblin 45's trap: holding Brace (43, a `BLOCK` charge, to 400; a trap's
    // hit is never blocked: the charge stays), Sidestep (42, `EVADE`: never evaded), Knocked
    // down to 400.
    let effects = array![43 + two(16) + 400 * two(24), 42 + 400 * two(24)];
    for effect in effects {
        let mut m = trapper();
        m.words.effects += effect;
        let w = words(
            array![m],
            array![hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED)],
        );
        row(ref digest, ref id, class, @content, w, b, alone(goblin_trap(PLACER)), 0, SPOT, 0);
    }
    let mut knocked = trapper();
    knocked.knocked = 400;
    let w = words(
        array![knocked],
        array![hob(ENTRANT, SPOT, 100, ai::ENGAGED), hob(PLACER, AT + 2, 100, ai::ENGAGED)],
    );
    row(ref digest, ref id, class, @content, w, b, alone(goblin_trap(PLACER)), 0, SPOT, 0);
    // An entrant the call does not hold: entity 99, member 1 of one: nothing.
    row(ref digest, ref id, class, @content, world(), b, alone(terrain(TERRAIN)), 99, SPOT, 20);
    row(ref digest, ref id, class, @content, world(), b, alone(terrain(TERRAIN)), 1, SPOT, 20);
    finish(digest, TRAP_DIGEST_2);
}

// The lookup: the object index and the ground's entry written, the window's position.
#[test]
#[available_gas(l2_gas: 538998801)] // ceil(1.05 × 513332191 measured)
fn test_trap_vectors_3() {
    let class = class();
    let content = trap_content();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = TRAP_PART_3;
    let b = board();
    let chest = trap(SPOT, object::CHEST, 0, 0);
    let used = trap(SPOT, object::PLACED_TRAP, 1, Placer::Member((0, 0)).param());
    let t = terrain(TERRAIN);
    let grounds: Array<Ground> = array![
        // A chest on the tile at 0, the trap at 1: index 1 written.
        array![chunk(0, [chest, t, Default::default()])],
        // A chunk of 3 objects, used traps on the tile at 0 and 1: index 2.
        array![chunk(0, [used, trap(SPOT, object::TRAP, 1, TERRAIN), t])],
        // The trap on another tile: nothing.
        alone(trap(SPOT + 1, object::TRAP, 0, TERRAIN)),
        // Chunk 0 the ground's second entry: entry 1 written, entry 0 kept.
        array![
            chunk(
                1, [trap(SPOT, object::TRAP, 0, TERRAIN), Default::default(), Default::default()],
            ),
            chunk(0, [t, Default::default(), Default::default()]),
        ],
        // No chunk 0: nothing.
        array![chunk(1, [t, Default::default(), Default::default()])],
        // Chunk 0 twice, the trap in the second: only the first is read, nothing.
        array![
            chunk(0, [Default::default(); 3]),
            chunk(0, [t, Default::default(), Default::default()]),
        ],
    ];
    for ground in grounds {
        row(ref digest, ref id, class, @content, world(), b, ground, 0, SPOT, 20);
    }
    // The window's position: 240 (outside), nothing; 239, the window's last: chunk 15, tile 14.
    let last = array![
        chunk(15, [trap(14, object::TRAP, 0, TERRAIN), Default::default(), Default::default()]),
    ];
    row(ref digest, ref id, class, @content, world(), b, last.clone(), 0, 240, 20);
    row(ref digest, ref id, class, @content, world(), b, last, 0, 239, 20);
    // A board whose origin is negative, `(−5, 0)` (`x` held as 10): position 0 lies before the
    // location (nothing); position 5 is its tile (0, 0), chunk 0's tile 0.
    let west = Board { window: open(), x: ORIGIN - 5, y: ORIGIN };
    let corner = alone(trap(0, object::TRAP, 0, TERRAIN));
    row(ref digest, ref id, class, @content, world(), west, corner.clone(), 0, 0, 20);
    row(ref digest, ref id, class, @content, world(), west, corner, 0, 5, 20);
    // The location's East edge: origin x 210, position 14 is tile (224, 0), chunk 14's tile 14;
    // origin 240, position 14 is column 254, chunk column 16: none. Its North edge: origin y
    // 240, row 240, chunk row 16: none.
    let east = array![
        chunk(14, [trap(14, object::TRAP, 0, TERRAIN), Default::default(), Default::default()]),
    ];
    let edge = Board { window: open(), x: ORIGIN + 210, y: ORIGIN };
    row(ref digest, ref id, class, @content, world(), edge, east.clone(), 0, 14, 20);
    let beyond = Board { window: open(), x: ORIGIN + 240, y: ORIGIN };
    row(ref digest, ref id, class, @content, world(), beyond, east, 0, 14, 20);
    let north = Board { window: open(), x: ORIGIN, y: ORIGIN + 240 };
    row(
        ref digest,
        ref id,
        class,
        @content,
        world(),
        north,
        alone(trap(0, object::TRAP, 0, TERRAIN)),
        0,
        0,
        20,
    );
    // `free` (placing, §5.11): the lowest index that is empty or a used trap; `None` when the
    // tile holds another object, or no index is free. `case` the chunk's `Features` and the
    // tile, `ok` the `Option<u32>`.
    let at = 9_u8;
    let other = trap(7, object::CHEST, 0, 0);
    let frees: Array<([Object; 3], u8)> = array![
        ([Default::default(); 3], at), ([other, Default::default(), Default::default()], at),
        ([trap(7, object::PLACED_TRAP, 1, 0), Default::default(), Default::default()], at),
        ([trap(7, object::TRAP, 1, 0), Default::default(), Default::default()], at),
        ([trap(at, object::CHEST, 0, 0), Default::default(), Default::default()], at),
        ([trap(at, object::PLACED_TRAP, 0, 0), Default::default(), Default::default()], at),
        ([other, trap(at, object::PLACED_TRAP, 1, 0), Default::default()], at),
        ([other, trap(8, object::VEIN, 1, 0), trap(6, object::TRAP, 0, 3)], at),
        ([other, trap(8, object::VEIN, 1, 0), trap(6, object::TRAP, 1, 3)], at),
        ([trap(at, object::NONE, 0, 0), other, Default::default()], at),
    ];
    for (objects, tile) in frees {
        let features = Features { objects, ..FeaturesTrait::empty() };
        let mut case = array![];
        Serde::serialize(@features, ref case);
        case.append(tile.into());
        let mut ok = array![];
        Serde::serialize(@TrapTrait::free(@features, tile), ref ok);
        emit(ref digest, ref id, "free", case.span(), ok.span());
    }
    finish(digest, TRAP_DIGEST_3);
}

/// The first id of each part, and each part's digest.
const TRAP_PART_1: u32 = 14;
const TRAP_PART_2: u32 = 24;
const TRAP_PART_3: u32 = 36;
const TRAP_DIGEST_0: felt252 =
    2787498107184120386038607310383447558271195683507077469272024736095572910618;
const TRAP_DIGEST_1: felt252 =
    28586507383434623868094572723670594695203416324847342307105816419457224450;
const TRAP_DIGEST_2: felt252 =
    3438638085967200555492296647354720432742156539403220268880570701724845901951;
const TRAP_DIGEST_3: felt252 =
    3075499101549686030732729308817093250590815560376692689788891479222492881474;
