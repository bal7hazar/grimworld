//! `vectors/act.jsonl` (RV-03b, D-257): the adventurer's action, `ActionTrait::act` as
//! `ActionLibrary` runs it (the words loaded through the content, the carrier run through the real
//! `ExecutorLibrary`, the words stored back, or the words as they came on a refusal), with its full
//! inputs and outputs, for the client's mirror of the class; and the carrier's side of a hit,
//! `Body::defence` and `Body::offence`, on a member and a goblin. Row 0 is the table's content. The
//! families, their order and the bounds each row sits on are in `vectors/README.md`.

use snforge_std::{DeclareResultTrait, declare};
use starknet::ClassHash;
use crate::constants::LAST_TICK;
use crate::interface::{IActionLibraryDispatcherTrait, IActionLibraryLibraryDispatcher};
use crate::models::chunk::{Features, FeaturesTrait, Object, object};
use crate::models::goblin::{Goblin, GoblinTrait, GoblinWordsTrait};
use crate::models::member::{Member, MemberSnapshotTrait, MemberTrait, MemberWordsTrait};
use crate::types::Target;
use crate::types::batch::Action;
use crate::types::combat::{HitClass, condition, damage, skill_kind, weapon};
use crate::types::effect::{Entry, EntryTrait, filter, guard, kind, scope, shape, target};
use crate::types::executor::tests::body::{emit, finish};
use crate::types::executor::tests::{
    AT, BRACE, SHIELD, SIDESTEP, SNARE, board, entry, goblin, skill,
};
use crate::types::executor::{Board, BoardTrait, Cache, Context, Levered, Unit, UnitBody};
use crate::types::infliction::Infliction;
use crate::types::tick::{
    ABSENT, Content, ContentTrait, Held, PotionSheet, Sheets, ai, flag, status,
};
use crate::types::trap::Ground;
use crate::types::window::WindowTrait;
use crate::types::world::fixtures::{Fixture, two};
use crate::types::world::{Actor, Words, WorldStoreTrait};
use super::{FIELD, FIRE, GLYPH, MEND, RAGE, STANCE, adventurer, bench, equip, tile};

const CLOCK: u32 = 200;
/// The table's own skills, after `bench`'s (ids 66 on): an instant trap; an instant trap whose
/// `TRAP` entry is guarded `BELOW_HALF`; a hex of activation 1; an enchantment on `SELF` of
/// activation 2; an attack skill of activation 2; an instant spell; a glyph whose line rises with
/// the rank; two `PENETRATION` holders (`WEAPON` 20, `SPELL` 150); two `ARMOR` holders (a hex of
/// −20, an enchantment of 300).
const PIT: u16 = 66;
const GUARDED: u16 = 67;
const HEX: u16 = 68;
const WARD: u16 = 69;
const SLAM: u16 = 70;
const BOLT: u16 = 71;
const RUNE: u16 = 72;
const EDGE: u16 = 73;
const FOCUS: u16 = 74;
const RUST: u16 = 75;
const BULWARK: u16 = 76;
/// The belt: slot 0 the bomb (100), slot 1 a draught (101, a heal on `SELF`), slot 2 a dart (102,
/// 20 piercing on a foe, range 4), slot 3 item 103, which the content does not hold.
const DART_RANGE: u8 = 4;

// ---- The table's content, its classes and its world.

/// `bench`'s content (skill 1 made a glyph of 2 and skill 2 an enchantment; the executor tests'
/// castes of armor 40 and a sword of 30; Snare 10 / 2 / 20;
/// the glyph, the fire spell, the Warden skill, the stance, the attack skill of 2 adrenaline, the
/// ally heal; the bomb), the table's skills 66–74 and the potions 101, 102 and 0 (a sheet of id
/// 0, which no belt slot names: an empty slot never takes it).
fn act_content() -> Content {
    let base = bench();
    let none: Entry = Default::default();
    // Skills 1 and 2 at positions 0 and 1, where the held potions' positions fall: a glyph of 2,
    // an enchantment (a potion is never read as the skill at its position).
    let glyph = EntryTrait::new(
        kind::NEXT_SPELL_COST,
        0,
        2,
        2,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        0,
    );
    let mut skills = array![];
    for sheet in base.skills {
        let mut sheet = *sheet;
        if sheet.id == 1 {
            sheet = skill(1, skill_kind::GLYPH, 0, [glyph, none, none]);
            sheet.activation = 0;
        } else if sheet.id == 2 {
            sheet.kind = skill_kind::ENCHANTMENT;
        }
        skills.append(sheet);
    }
    let trap = entry(kind::TRAP, 0, 0, 0, target::TILE, shape::SINGLE, 0);
    let earth = entry(
        kind::DAMAGE, damage::EARTH, 10, 40, target::FOE, shape::SINGLE, filter::FOES,
    );
    let mut sheet = skill(PIT, skill_kind::TRAP, 3, [trap, earth, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let below = EntryTrait::new(
        kind::TRAP, 0, 0, 0, 0, 0, 0, target::TILE, shape::SINGLE, 0, guard::BELOW_HALF, 0,
    );
    let mut sheet = skill(GUARDED, skill_kind::TRAP, 3, [below, earth, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let fire = entry(kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES);
    skills.append(skill(HEX, skill_kind::HEX, 6, [fire, none, none]));
    let heal = entry(kind::HEAL, 0, 10, 10, target::SELF, shape::SINGLE, filter::ALLIES);
    let mut sheet = skill(WARD, skill_kind::ENCHANTMENT, 0, [heal, none, none]);
    sheet.activation = 2;
    skills.append(sheet);
    let mut sheet = skill(SLAM, skill_kind::ATTACK, 1, [none, none, none]);
    sheet.activation = 2;
    sheet.energy = 5;
    sheet.adrenaline = 1;
    skills.append(sheet);
    let mut sheet = skill(BOLT, skill_kind::SPELL, 6, [fire, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let rune = EntryTrait::new(
        kind::NEXT_SPELL_COST,
        0,
        1,
        13,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        0,
    );
    let mut sheet = skill(RUNE, skill_kind::GLYPH, 0, [rune, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let edge = EntryTrait::new(
        kind::PENETRATION,
        0,
        20,
        20,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        scope::WEAPON,
    );
    skills.append(skill(EDGE, skill_kind::ENCHANTMENT, 0, [edge, none, none]));
    let focus = EntryTrait::new(
        kind::PENETRATION,
        0,
        150,
        150,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        scope::SPELL,
    );
    skills.append(skill(FOCUS, skill_kind::STANCE, 0, [focus, none, none]));
    let rust = EntryTrait::new(
        kind::ARMOR, 0, -20, -20, 5, 5, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
    );
    skills.append(skill(RUST, skill_kind::HEX, 6, [rust, none, none]));
    let bulwark = EntryTrait::new(
        kind::ARMOR, 0, 300, 300, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
    );
    skills.append(skill(BULWARK, skill_kind::ENCHANTMENT, 0, [bulwark, none, none]));
    let mut potions = array![];
    for potion in base.potions {
        potions.append(PotionSheet { strength: 30, ..*potion });
    }
    let draught = entry(kind::HEAL, 0, 25, 25, target::SELF, shape::SINGLE, filter::ALLIES);
    potions.append(PotionSheet { id: 101, entry: draught.pack(), range: 0, ..Default::default() });
    let dart = entry(
        kind::DAMAGE, damage::PIERCING, 20, 20, target::FOE, shape::SINGLE, filter::FOES,
    );
    potions
        .append(
            PotionSheet {
                id: 102, entry: dart.pack(), range: DART_RANGE, strength: 45, ..Default::default(),
            },
        );
    potions.append(PotionSheet { id: 0, entry: dart.pack(), range: 6, ..Default::default() });
    Content { skills: skills.span(), potions: potions.span(), castes: base.castes }
}

#[derive(Drop)]
struct Table {
    action: ClassHash,
    executor: ClassHash,
    content: Content,
    sheets: Sheets,
}

fn class(name: ByteArray) -> ClassHash {
    *declare(name).unwrap().contract_class().class_hash
}

fn table() -> Table {
    let content = act_content();
    Table {
        action: class("ActionLibrary"),
        executor: class("ExecutorLibrary"),
        content,
        sheets: content.sheets(),
    }
}

/// The adventurer of `ids` (bar slots 0 on, rank 12; a sword of `k` 1, range 1; 30 energy thirds
/// of 60; health 400 of 480), facing 0 on `AT`.
fn hero(t: @Table, ids: Array<u16>) -> Member {
    adventurer(t.sheets, ids.span())
}

fn words(clock: u32, members: Array<Member>, goblins: Array<Goblin>) -> Words {
    Fixture::world(clock, members, goblins).store()
}

/// The ground: chunk 0, empty.
fn empty() -> Ground {
    array![(0, FeaturesTrait::empty())]
}

/// One `act` row: `case` the call's arguments but the content (row 0's) and the executor's class:
/// `Words`, `Board`, the ground, the `Action`; `ok` what it returns: `Words`, the ground, the
/// `Result<u8, Illegal>`.
fn row(
    ref digest: Array<felt252>,
    ref id: u32,
    t: @Table,
    words: Words,
    board: Board,
    ground: Ground,
    action: Action,
) {
    let mut case = array![];
    Serde::serialize(@words, ref case);
    Serde::serialize(@board, ref case);
    Serde::serialize(@ground, ref case);
    Serde::serialize(@action, ref case);
    let library = IActionLibraryLibraryDispatcher { class_hash: *t.action };
    let (after, ground, result) = library
        .act(words, *t.content, board, *t.executor, ground, action);
    let mut ok = array![];
    Serde::serialize(@after, ref ok);
    Serde::serialize(@ground, ref ok);
    Serde::serialize(@result, ref ok);
    emit(ref digest, ref id, "act", case.span(), ok.span());
}

/// A row on the open board and the empty ground.
fn plain(ref digest: Array<felt252>, ref id: u32, t: @Table, words: Words, action: Action) {
    row(ref digest, ref id, t, words, board(), empty(), action);
}

/// The adventurer alone at the clock `c`, and `goblins`.
fn alone(c: u32, member: Member, goblins: Array<Goblin>) -> Words {
    words(c, array![member], goblins)
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

fn skill_on(slot: u8, entity: u16) -> Action {
    Action::Skill((slot, Target::Entity(entity)))
}

fn skill_at(slot: u8, position: u8) -> Action {
    Action::Skill((slot, Target::Tile(tile(position))))
}

/// The held effect of skill `id` in effect slot `slot` to `deadline` at `rank`.
fn holding(
    ref member: Member, slot: u8, id: u16, potion: bool, charges: u8, deadline: u32, rank: u8,
) {
    member.set_effect(slot, Held { carrier: id, potion, charges, deadline, rank }, 0);
}

fn chunk(objects: [Object; 3]) -> Ground {
    array![(0, Features { objects, ..FeaturesTrait::empty() })]
}

fn thing(position: u8, kind: u8, state: u8) -> Object {
    Object { tile: position, kind, state, param: 0 }
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

// Row 0, the content; the clock, absent, knocked down; Wait, Turn, Move, Interact.
#[test]
#[available_gas(l2_gas: 956264082)] // ceil(1.05 × 910727697 measured)
fn test_act_vectors_0() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok = array![];
    Serde::serialize(@t.content, ref ok);
    emit(ref digest, ref id, "content", array![].span(), ok.span());
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // Wait: 1 tick, nothing written; at `LAST_TICK` legal, past it `Clock` (before `Absent`).
    plain(ref digest, ref id, @t, alone(CLOCK, hero(@t, array![]), goblins.clone()), Action::Wait);
    plain(
        ref digest, ref id, @t, alone(LAST_TICK, hero(@t, array![]), goblins.clone()), Action::Wait,
    );
    plain(
        ref digest,
        ref id,
        @t,
        alone(LAST_TICK + 1, hero(@t, array![]), goblins.clone()),
        Action::Wait,
    );
    let mut dead = hero(@t, array![]);
    dead.health = 0;
    plain(ref digest, ref id, @t, alone(LAST_TICK + 1, dead, goblins.clone()), Action::Attack(8));
    // Absent: at 0 health; at 1, legal; down (status 1) and gone (2) above 0; at 0 and knocked
    // down (`Absent` first).
    for (health, state) in array![
        (0_u16, status::INSIDE), (1, status::INSIDE), (400, status::DOWN), (400, status::GONE),
    ] {
        let mut m = hero(@t, array![]);
        m.health = health;
        m.status = state;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Wait);
    }
    let mut m = hero(@t, array![]);
    m.health = 0;
    m.knocked = CLOCK + 1;
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    // Knocked down to `c` (lapsed at `t₀ = c + 1`: an attack lands), to `c + 1` and `c + 2`
    // (refused); knocked down, each kind: only Wait.
    for knocked in array![CLOCK, CLOCK + 1, CLOCK + 2] {
        let mut m = hero(@t, array![]);
        m.knocked = knocked;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    }
    let actions = array![
        Action::Wait, Action::Turn(2), skill_on(0, 8), Action::Item((0, tile(AT + 1))),
        Action::Move(0), Action::Interact(tile(AT + 1)),
    ];
    for action in actions {
        let mut m = hero(@t, array![STANCE]);
        m.set_belt_count(0, 1);
        m.knocked = CLOCK + 1;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), action);
    }
    // Turn: 0 ticks, the facing set and `TURNED`; to 5 (the last direction), to the facing it
    // has; with `TURNED`, refused; with `INSTANT` only, legal. Wait with `TURNED`: legal.
    for (direction, flags) in array![
        (0_u8, 0_u8), (5, 0), (3, 0), (1, flag::TURNED), (1, flag::INSTANT),
    ] {
        let mut m = hero(@t, array![]);
        m.set_facing(3);
        m.flags = flags;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Turn(direction));
    }
    let mut m = hero(@t, array![]);
    m.flags = flag::TURNED | flag::INSTANT;
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Wait);
    // Move and Interact: the segment's, refused here (`Kind`).
    plain(
        ref digest, ref id, @t, alone(CLOCK, hero(@t, array![]), goblins.clone()), Action::Move(0),
    );
    plain(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, hero(@t, array![]), goblins.clone()),
        Action::Interact(tile(AT + 1)),
    );
    finish(digest, ACT_DIGEST_0);
}

// Attack: the target, the weapon's reach and `k`, the sight, the facing.
#[test]
#[available_gas(l2_gas: 787163494)] // ceil(1.05 × 749679518 measured)
fn test_act_vectors_1() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_1;
    let near = AT + 1;
    let goblins = array![
        goblin(8, near, 0, 100), goblin(9, AT + 2, 0, 100), corpse(10, AT - 1),
        goblin(11, AT + 15, 0, 100),
    ];
    // The sword (range 1, `k` 0: 1 tick): goblin 8 adjacent, hit now, the member turned toward
    // it; goblin 11 adjacent to the North-West; goblin 9 at 2, `Reach`; goblin 10 dead, an
    // entity no actor holds (77), the member itself (0), entity 1 of a world of one, entity 7:
    // `Target`.
    for entity in array![8_u16, 11, 9, 10, 77, 0, 1, 7] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, hero(@t, array![]), goblins.clone()),
            Action::Attack(entity),
        );
    }
    // Entity 1, a living member adjacent: an ally, `Target`.
    let ally = crate::types::executor::tests::member(AT - 15, 0, weapon::SWORD);
    plain(
        ref digest,
        ref id,
        @t,
        words(CLOCK, array![hero(@t, array![]), ally], goblins.clone()),
        Action::Attack(1),
    );
    // The weapon's `k` (`MemberStats` 104–111): 2, 255.
    for k in array![2_felt252, 255] {
        let mut m = hero(@t, array![]);
        m.words.stats += k * two(104);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    }
    // A range of 3 (`MemberStats` 112): goblin 12 at 3, legal; goblin 13 at 4, `Reach`; goblin
    // 12 behind a wall at 2, `Reach`; goblin 14 at 3 but outside the window (the board's origin
    // at (5, 0): its tile (4, 7) is `FAR`), `Reach`.
    let far = array![
        goblin(12, AT + 3, 0, 100), goblin(13, AT + 4, 0, 100), goblin(14, AT - 3, 0, 100),
    ];
    for entity in array![12_u16, 13] {
        let mut m = hero(@t, array![]);
        m.words.stats += 2 * two(112);
        plain(ref digest, ref id, @t, alone(CLOCK, m, far.clone()), Action::Attack(entity));
    }
    let mut m = hero(@t, array![]);
    m.words.stats += 2 * two(112);
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, m, far.clone()),
        walled(AT + 2),
        empty(),
        Action::Attack(12),
    );
    let mut m = hero(@t, array![]);
    m.words.stats += 2 * two(112);
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, m, far.clone()),
        BoardTrait::new(crate::types::executor::tests::open(), 5, 0),
        empty(),
        Action::Attack(14),
    );
    // The facing from 4: toward goblin 8 (East), legal at the clock's last tick.
    let mut m = hero(@t, array![]);
    m.set_facing(4);
    plain(ref digest, ref id, @t, alone(LAST_TICK, m, goblins.clone()), Action::Attack(8));
    finish(digest, ACT_DIGEST_1);
}

/// The adventurer with `id` on bar slot `slot` (the others the fixtures' 1–8, rank 12).
fn with_skill(t: @Table, slot: u8, id: u16) -> Member {
    let mut m = hero(t, array![]);
    equip(ref m, t.sheets, slot, id, 12);
    m
}

/// Bar slot `slot` emptied (skill id 0).
fn emptied(ref member: Member, slot: u8) {
    let old: felt252 = member.skill(slot).into();
    member.words.bar -= old * two(16 * slot.into());
}

/// Goblin `entity` dead on `position` (health 0, AI state `DEAD`).
fn corpse(entity: u16, position: u8) -> Goblin {
    let mut g = goblin(entity, position, 0, 0);
    g.ai = ai::DEAD;
    g
}

/// A second member, on `position`.
fn ally(position: u8) -> Member {
    crate::types::executor::tests::member(position, 0, weapon::SWORD)
}

// Skill: each refusal in `act`'s order, at its bound, and the one before it winning.
#[test]
#[available_gas(l2_gas: 963034352)] // ceil(1.05 × 917175573 measured)
fn test_act_vectors_2() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_2;
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // `Empty`: bar slot 0 with skill id 0; slot 7 holding the stance (legal), emptied (refused);
    // emptied with the weapon-required bit set (`Empty` first).
    let mut m = hero(@t, array![STANCE]);
    emptied(ref m, 0);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 0));
    let m = with_skill(@t, 7, STANCE);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(7, 0));
    let mut m = with_skill(@t, 7, STANCE);
    emptied(ref m, 7);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(7, 0));
    m.words.stats += two(47);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(7, 0));
    // `Kind`: the attack skill with its slot's weapon-required bit (`MemberStats` 40 + slot):
    // refused; with slot 1's bit only, legal; the stance with its bit, legal (not an attack);
    // with the bit and recharging (`Kind` first).
    for (bit, recharge) in array![(40_u32, 0_u32), (41, 0), (40, CLOCK + 1)] {
        let mut m = hero(@t, array![RAGE]);
        m.adrenaline = 8;
        m.words.stats += two(bit);
        if recharge != 0 {
            m.set_recharge(0, recharge);
        }
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    let mut m = hero(@t, array![STANCE]);
    m.words.stats += two(40);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 0));
    // `Instant`: an instant skill with `INSTANT` set: the stance, the instant spell (refused);
    // the spell of activation 3 and the attack skill of activation 0 (legal: neither is
    // instant); the stance with `TURNED` only (legal); with `INSTANT` and recharging (`Instant`
    // first).
    let cases: Array<(u16, u16, u8)> = array![
        (STANCE, 0, flag::INSTANT), (BOLT, 8, flag::INSTANT), (FIRE, 8, flag::INSTANT),
        (RAGE, 8, flag::INSTANT), (STANCE, 0, flag::TURNED),
    ];
    for (skill, target, flags) in cases {
        let mut m = hero(@t, array![skill]);
        m.adrenaline = 8;
        m.flags = flags;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, target));
    }
    let mut m = hero(@t, array![STANCE]);
    m.flags = flag::INSTANT;
    m.set_recharge(0, CLOCK + 1);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 0));
    // `Recharging` (`c < R`): R = c + 1 refused, R = c legal; the attack skill recharging and
    // short of adrenaline (`Recharging` first).
    for recharge in array![CLOCK + 1, CLOCK] {
        let mut m = hero(@t, array![STANCE]);
        m.set_recharge(0, recharge);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 0));
    }
    let mut m = hero(@t, array![RAGE]);
    m.set_recharge(0, CLOCK + 1);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    // `Adrenaline` (2 strikes, 8 quarters): 7 refused, 8 legal (to 0), 9 (to 1); the attack skill
    // of activation 2 (5 energy, 1 strike) short of both (`Adrenaline` first), of energy only
    // (`Energy`), of neither.
    for adrenaline in array![7_u16, 8, 9] {
        let mut m = hero(@t, array![RAGE]);
        m.adrenaline = adrenaline;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    for (adrenaline, energy) in array![(3_u16, 14_u16), (4, 14), (4, 15)] {
        let mut m = hero(@t, array![SLAM]);
        m.adrenaline = adrenaline;
        m.energy = energy;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    // `Energy` (the fire spell's 5: 15 thirds): 14 refused, 15 legal (to 0); short and aimed at no
    // actor (`Energy` first); aimed at no actor (`Target`).
    let foe = array![goblin(8, AT + 4, 0, 100)];
    for (energy, target) in array![(14_u16, 8_u16), (15, 8), (14, 77), (15, 77)] {
        let mut m = hero(@t, array![FIRE]);
        m.energy = energy;
        plain(ref digest, ref id, @t, alone(CLOCK, m, foe.clone()), skill_on(0, target));
    }
    finish(digest, ACT_DIGEST_2);
}

// Skill: the aim (§2.3): a foe, an ally, `SELF`, a tile; range and sight; a trap's tile.
#[test]
#[available_gas(l2_gas: 939832288)] // ceil(1.05 × 895078369 measured)
fn test_act_vectors_3() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_3;
    // The fire spell (`FOE`, range 6): goblin 8 at 6 (legal), goblin 9 at 7 (`Reach`), goblin
    // 10 dead at 2, the member (0), a tile: `Target`; goblin 8 behind a wall at 3: `Reach`.
    let foes = array![goblin(8, AT + 6, 0, 100), goblin(9, AT - 7, 0, 100), corpse(10, AT + 2)];
    let mut m = hero(@t, array![FIRE]);
    m.energy = 15;
    for action in array![
        skill_on(0, 8), skill_on(0, 9), skill_on(0, 10), skill_on(0, 0), skill_at(0, AT + 6),
    ] {
        plain(ref digest, ref id, @t, alone(CLOCK, m, foes.clone()), action);
    }
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, m, foes.clone()),
        walled(AT + 3),
        empty(),
        skill_on(0, 8),
    );
    // The ally heal (`ALLY`, range 6, instant): the member itself; member 1 at 6 (legal), at 7
    // (`Reach`), at 6 at 0 health, a goblin, a tile, member 1 of a world of one: `Target`.
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    let healer = hero(@t, array![MEND]);
    plain(ref digest, ref id, @t, alone(CLOCK, healer, goblins.clone()), skill_on(0, 0));
    let mut down = ally(AT + 6);
    down.health = 0;
    let pairs = array![
        (ally(AT + 6), skill_on(0, 1)), (ally(AT - 7), skill_on(0, 1)), (down, skill_on(0, 1)),
        (ally(AT + 6), skill_on(0, 8)), (ally(AT + 6), skill_at(0, AT + 6)),
    ];
    for (other, action) in pairs {
        let mut hurt = other;
        if hurt.health > 0 {
            hurt.health = 300;
        }
        plain(ref digest, ref id, @t, words(CLOCK, array![healer, hurt], goblins.clone()), action);
    }
    plain(ref digest, ref id, @t, alone(CLOCK, healer, goblins.clone()), skill_on(0, 1));
    // `SELF` (the stance): any address, the facing kept: a goblin, no actor, a tile. The
    // enchantment on `SELF` of activation 2 on a tile: started, `act_tile` 1, its target the
    // member.
    let stance = hero(@t, array![STANCE]);
    for action in array![skill_on(0, 8), skill_on(0, 77), skill_at(0, AT + 3)] {
        plain(ref digest, ref id, @t, alone(CLOCK, stance, goblins.clone()), action);
    }
    let ward = hero(@t, array![WARD]);
    plain(ref digest, ref id, @t, alone(CLOCK, ward, goblins.clone()), skill_at(0, AT + 3));
    plain(ref digest, ref id, @t, alone(CLOCK, ward, goblins.clone()), skill_on(0, 8));
    // Snare (`TILE`, range 3, activation 2, 10 energy): an empty tile at 3 (started, `act_tile`
    // 1, its target the tile), at 4 (`Reach`); an entity (`Target`); goblin 8's tile, the
    // member's own (`Trap`); a dead goblin's (legal); a wall at 2 (`Reach`: its sight).
    let mut snarer = hero(@t, array![SNARE]);
    snarer.energy = 30;
    let lying = array![goblin(8, AT + 1, 0, 100), corpse(9, AT - 1)];
    for action in array![
        skill_at(0, AT + 3), skill_at(0, AT + 4), skill_on(0, 8), skill_at(0, AT + 1),
        skill_at(0, AT), skill_at(0, AT - 1),
    ] {
        plain(ref digest, ref id, @t, alone(CLOCK, snarer, lying.clone()), action);
    }
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, snarer, lying.clone()),
        walled(AT + 2),
        empty(),
        skill_at(0, AT + 2),
    );
    finish(digest, ACT_DIGEST_3);
}

// The trap's tile (§5.11, FX-14): the ground the instant trap writes; the guarded trap.
#[test]
#[available_gas(l2_gas: 362483549)] // ceil(1.05 × 345222427 measured)
fn test_act_vectors_4() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_4;
    let goblins = array![goblin(8, AT + 15, 0, 100)];
    let spot = AT + 2;
    let pit = hero(@t, array![PIT, GUARDED]);
    let none: Object = Default::default();
    // The instant trap on `spot` (position 114, chunk 0's tile 114): the ground's chunk 0 empty
    // (index 0 written); a chest elsewhere at 0 (index 1); a used trap on the tile at 0 (index
    // 0); a chest on the tile, an unused trap on it, three objects elsewhere (`Trap`); chunk 0
    // the ground's second entry; no chunk 0 (`Trap`).
    let grounds: Array<Ground> = array![
        empty(), chunk([thing(3, object::CHEST, 0), none, none]),
        chunk([thing(spot, object::PLACED_TRAP, 1), none, none]),
        chunk([thing(spot, object::CHEST, 0), none, none]),
        chunk([thing(spot, object::PLACED_TRAP, 0), none, none]),
        chunk([thing(3, object::CHEST, 0), thing(4, object::CHEST, 0), thing(5, object::CHEST, 0)]),
        array![(1, FeaturesTrait::empty()), (0, FeaturesTrait::empty())],
        array![(1, FeaturesTrait::empty())],
    ];
    for ground in grounds {
        row(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, pit, goblins.clone()),
            board(),
            ground,
            skill_at(0, spot),
        );
    }
    // A tile of chunk 1: the board's origin at (5, 0), the member on (14, 7), the trap on the
    // location's tile (16, 7) (position 116), chunk 1's tile 106, the ground holding chunk 1.
    let mut east = hero(@t, array![PIT]);
    east.words.state += 7 * two(32);
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, east, array![]),
        BoardTrait::new(crate::types::executor::tests::open(), 5, 0),
        array![(1, FeaturesTrait::empty())],
        Action::Skill((0, Target::Tile(16 + 256 * 7))),
    );
    // The guarded trap (`BELOW_HALF` on the placer, health × 2 < 480): at 400 and 240 not held
    // (nothing placed, its costs and recharge spent: legal, 0 ticks), at 239 placed.
    for health in array![400_u16, 240, 239] {
        let mut m = pit;
        m.health = health;
        row(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, m, goblins.clone()),
            board(),
            empty(),
            skill_at(1, spot),
        );
    }
    finish(digest, ACT_DIGEST_4);
}

// Costs: *Fieldcraft*, the glyphs, the floor at 0.
#[test]
#[available_gas(l2_gas: 744075330)] // ceil(1.05 × 708643171 measured)
fn test_act_vectors_5() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_5;
    let goblins = array![goblin(8, AT + 4, 0, 100)];
    // The Warden skill (8 energy, profession 2, instant, a heal on `SELF`): a Warden primary
    // (`MemberStats` 72) of rank 12 at 0 energy (floored: free); rank 8 (8 − 8: free); rank 7
    // at 2 thirds (1 energy short), at 3; a primary 1 of rank 12 at 23 and 24 thirds; a Warden
    // of rank 12 casting the fire spell (no *Fieldcraft*: 15).
    let cases: Array<(felt252, felt252, u16, u16, u16)> = array![
        (2, 12, 0, 0, 0), (2, 8, 0, 0, 0), (2, 7, 2, 0, 0), (2, 7, 3, 0, 0), (1, 12, 23, 0, 0),
        (1, 12, 24, 0, 0), (2, 12, 14, 1, 8), (2, 12, 15, 1, 8),
    ];
    for (primary, rank, energy, slot, target) in cases {
        let mut m = hero(@t, array![FIELD, FIRE]);
        m.words.stats += primary * two(72) + rank * two(80);
        m.energy = energy;
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, m, goblins.clone()),
            skill_on(slot.try_into().unwrap(), target),
        );
    }
    // The glyph (`NEXT_SPELL_COST` 4) held in effect slot 0: to `c + 1` (held: the fire spell's
    // 5 − 4 = 1, 3 thirds, the glyph consumed, `D = c`); to `c` (lapsed: 3 thirds short); on
    // the Warden skill (not a spell: kept), the hex and the enchantment (spells: consumed), the
    // instant spell.
    for deadline in array![CLOCK + 1, CLOCK] {
        let mut m = hero(@t, array![FIRE]);
        m.energy = 3;
        holding(ref m, 0, GLYPH, false, 0, deadline, 12);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    let mut m = hero(@t, array![FIELD, HEX, WARD, BOLT]);
    m.energy = 30;
    holding(ref m, 0, GLYPH, false, 0, CLOCK + 1, 12);
    for (slot, target) in array![(0_u8, 0_u16), (1, 8), (2, 0), (3, 8)] {
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(slot, target));
    }
    // The rune (1 to 13 with the rank) on the fire spell: rank 0 (5 − 1: 12 thirds), 3 (5 − 4:
    // 3), 4 (5 − 5: free), 12 (5 − 13: free); each at 3 thirds short of 12 for rank 0.
    for (rank, energy) in array![(0_u8, 11_u16), (0, 12), (3, 3), (4, 0), (12, 0)] {
        let mut m = hero(@t, array![FIRE]);
        m.energy = energy;
        holding(ref m, 1, RUNE, false, 0, CLOCK + 1, rank);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    // A potion held (belt slot 0, the bomb: its position 0 is skill 1's, a glyph of 2 here):
    // not a glyph, kept, the fire spell's full 15 thirds.
    let mut m = hero(@t, array![FIRE]);
    m.energy = 15;
    holding(ref m, 0, 0, true, 0, CLOCK + 1, 0);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    // Two glyphs (slots 0 and 2: 4 + 1, both consumed), the stance held in slot 1 and a potion
    // in slot 3 (neither a glyph: kept).
    let mut m = hero(@t, array![FIRE]);
    m.energy = 0;
    holding(ref m, 0, GLYPH, false, 0, CLOCK + 1, 12);
    holding(ref m, 1, STANCE, false, 0, CLOCK + 1, 12);
    holding(ref m, 2, RUNE, false, 0, CLOCK + 1, 0);
    holding(ref m, 3, 0, true, 0, CLOCK + 1, 0);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    finish(digest, ACT_DIGEST_5);
}

// Quick cast (§5.12, FX-39, FX-43); the activation and the instant path; the tick cost.
#[test]
#[available_gas(l2_gas: 582545404)] // ceil(1.05 × 554805146 measured)
fn test_act_vectors_6() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_6;
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // Pair 0 (`MemberBar` 208–219) of N 5, pair 1 (220–231) of N 2; bar slot 0's pairs
    // (`MemberStats` 168, 169); the counters (`casts` 0 and 1). The fire spell (activation 3):
    // pair 0 at 4 (its bonus: activation 2, the counter 0); at 3 (to 4, activation 3); N 0 (the
    // counter kept); the slot not counting for it (kept); pair 1 at 1 (its bonus); both (bonuses
    // 2: activation 1). The hex (activation 1) with one bonus and with two: kept at 1 (`quick ≥
    // n`); the enchantment (activation 2) with two: 1; Snare (a trap, not a spell) and the
    // instant spell (activation 0): no count.
    let cases: Array<(u16, felt252, felt252, felt252, u8, u8)> = array![
        (FIRE, 5, 0, 1, 4, 0), (FIRE, 5, 0, 1, 3, 0), (FIRE, 0, 0, 1, 4, 0), (FIRE, 5, 0, 0, 4, 0),
        (FIRE, 0, 2, 2, 0, 1), (FIRE, 5, 2, 3, 4, 1), (HEX, 5, 0, 1, 4, 0), (HEX, 5, 2, 3, 4, 1),
        (WARD, 5, 2, 3, 4, 1), (SNARE, 5, 0, 1, 4, 0), (BOLT, 5, 0, 1, 4, 0),
    ];
    for (skill, n0, n1, matches, c0, c1) in cases {
        let mut m = hero(@t, array![skill]);
        m.energy = 30;
        m.words.bar += n0 * two(212) + n1 * two(224);
        m.words.stats += matches * two(168);
        m.set_casts(0, c0);
        m.set_casts(1, c1);
        let action = if skill == SNARE {
            skill_at(0, AT + 3)
        } else if skill == WARD {
            skill_on(0, 0)
        } else {
            skill_on(0, 8)
        };
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), action);
    }
    // The attack skill of activation 2 (`max(k, n)`, FX-5): `k` 1, 2, 3. The attack skill of
    // activation 0: lands now, `k` 2, its recharge from `c + 1`, `INSTANT` not set. The instant
    // spell: lands now, 0 ticks, `INSTANT`, its recharge.
    for k in array![0_felt252, 2, 3] {
        let mut m = hero(@t, array![SLAM]);
        m.adrenaline = 4;
        m.energy = 15;
        m.words.stats += k * two(104);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    }
    let mut m = hero(@t, array![RAGE, BOLT]);
    m.adrenaline = 8;
    m.words.stats += 2 * two(104);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(1, 8));
    finish(digest, ACT_DIGEST_6);
}

// Item: the belt slot, its count, the potion's addressing and reach.
#[test]
#[available_gas(l2_gas: 652450070)] // ceil(1.05 × 621381019 measured)
fn test_act_vectors_7() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_7;
    let centre = AT + 2;
    let goblins = array![
        goblin(8, centre, 0, 100), goblin(9, centre + 1, 0, 100),
        goblin(10, AT - DART_RANGE, 0, 100), goblin(11, AT - DART_RANGE - 1, 0, 100),
    ];
    // The bomb (belt slot 0, `TILE`, range 6, `DISC_1`): count 1 (to 0, both goblins hit, the
    // member turned toward the tile), 2 (to 1), 0 (`Belt`); a tile at 6 (legal), at 7 and
    // behind a wall (`Reach`).
    for count in array![1_u8, 2, 0] {
        let mut m = hero(@t, array![]);
        m.set_belt_count(0, count);
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, m, goblins.clone()),
            Action::Item((0, tile(centre))),
        );
    }
    let mut m = hero(@t, array![]);
    m.set_belt_count(0, 1);
    for position in array![AT + 6, AT - 7] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, m, goblins.clone()),
            Action::Item((0, tile(position))),
        );
    }
    row(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, m, goblins.clone()),
        walled(AT + 1),
        empty(),
        Action::Item((0, tile(centre))),
    );
    // Belt slot 3, item 103, which the content lacks: count 1 and 0 (`Empty` first); slot 0's
    // item 0 (the content's potion of id 0 is not taken): `Empty`.
    for count in array![1_u8, 0] {
        let mut m = hero(@t, array![]);
        m.set_belt_count(3, count);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Item((3, 8)));
    }
    let mut m = hero(@t, array![]);
    m.set_belt_count(0, 1);
    m.words.kit -= 100;
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Item((0, 8)));
    // The draught (slot 1, `SELF`): healed 25, the facing kept, any address.
    let mut m = hero(@t, array![]);
    m.set_belt_count(1, 1);
    m.set_facing(2);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Item((1, 77)));
    // The dart (slot 2, `FOE`, range 4): goblin 10 at 4 (legal), goblin 11 at 5 (`Reach`), the
    // member (`Target`), a tile's value read as an entity (`Target`).
    let mut m = hero(@t, array![]);
    m.set_belt_count(2, 1);
    for address in array![10_u16, 11, 0, tile(centre)] {
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Item((2, address)));
    }
    finish(digest, ACT_DIGEST_7);
}

// ---- The carrier's side of a hit: `Body::defence` and `Body::offence` (deferred from RV-03a).

/// An actor's words as a row records them: `0` then the `MemberWords`, or `1` then the
/// `GoblinWords`; the actor is loaded from them through the table's content.
fn actor_case(unit: @Unit, ref case: Array<felt252>) {
    match unit {
        Unit::M(m) => {
            case.append(0);
            Serde::serialize(@m.store(), ref case);
        },
        Unit::G(g) => {
            case.append(1);
            Serde::serialize(@g.store(), ref case);
        },
    }
}

fn loaded(unit: Unit, content: @Content) -> Unit {
    match unit {
        Unit::M(m) => Unit::M(Fixture::load_member(m.store(), content)),
        Unit::G(g) => Unit::G(Fixture::load_goblin(g.store(), content)),
    }
}

/// One `defence` row: `case` the actor and `t`; `ok` its `Defence` (a member's as member 0, a
/// fresh cache).
fn defence_row(ref digest: Array<felt252>, ref id: u32, t: @Table, unit: Unit, at: u32) {
    let mut case = array![];
    actor_case(@unit, ref case);
    case.append(at.into());
    let unit = loaded(unit, t.content);
    let actor = match unit {
        Unit::M(_) => Actor::Member(0),
        Unit::G(_) => Actor::Goblin(0),
    };
    let mut cache: Cache = Default::default();
    let defence = UnitBody::defence(@unit, @Levered {}, ref cache, actor, at, t.sheets);
    let mut ok = array![];
    Serde::serialize(@defence, ref ok);
    emit(ref digest, ref id, "defence", case.span(), ok.span());
}

fn context(rank: u8, skill_kind: u8, carrier: u16, at: u32, scope: u8, t: u32) -> Context {
    Context {
        rank,
        infliction: Infliction { condition: 2, percent: 10, knockdown: 1 },
        enchant: 5,
        skill_kind,
        carrier,
        potion: false,
        at,
        scope,
        t,
    }
}

/// One `offence` row: `case` the actor, the `HitClass`, the `Entry`, `bonus`, `penetration`,
/// then the `Context`'s fields in order (`Infliction` its three); `ok` the `Offence`'s fields in
/// order.
fn offence_row(
    ref digest: Array<felt252>,
    ref id: u32,
    t: @Table,
    unit: Unit,
    class: HitClass,
    entry: Entry,
    bonus: u32,
    penetration: u16,
    context: Context,
) {
    let mut case = array![];
    actor_case(@unit, ref case);
    Serde::serialize(@class, ref case);
    Serde::serialize(@entry, ref case);
    Serde::serialize(@bonus, ref case);
    Serde::serialize(@penetration, ref case);
    Serde::serialize(@context.rank, ref case);
    Serde::serialize(@context.infliction, ref case);
    Serde::serialize(@context.enchant, ref case);
    Serde::serialize(@context.skill_kind, ref case);
    Serde::serialize(@context.carrier, ref case);
    Serde::serialize(@context.potion, ref case);
    Serde::serialize(@context.at, ref case);
    Serde::serialize(@context.scope, ref case);
    Serde::serialize(@context.t, ref case);
    let unit = loaded(unit, t.content);
    let o = UnitBody::offence(
        @unit, @Levered {}, class, @entry, bonus, penetration, @context, t.sheets,
    );
    let mut ok = array![];
    Serde::serialize(@o.class, ref ok);
    Serde::serialize(@o.weapon, ref ok);
    Serde::serialize(@o.melee, ref ok);
    Serde::serialize(@o.strength, ref ok);
    Serde::serialize(@o.base, ref ok);
    Serde::serialize(@o.percent, ref ok);
    Serde::serialize(@o.above, ref ok);
    Serde::serialize(@o.penetration, ref ok);
    Serde::serialize(@o.damage_type, ref ok);
    Serde::serialize(@o.steal, ref ok);
    Serde::serialize(@o.energy, ref ok);
    emit(ref digest, ref id, "offence", case.span(), ok.span());
}

/// Goblin 8 holding skill `id` to `deadline` at `rank` with `charges`.
fn goblin_holding(id: u16, charges: u8, deadline: u32, rank: u8) -> Goblin {
    let mut g = goblin(8, AT + 1, 0, 100);
    GoblinWordsTrait::set_effect(
        ref g, Held { carrier: id, potion: false, charges, deadline, rank }, 0,
    );
    g
}

// `defence`: the armor terms, each held effect's `ARMOR`, `BLOCK`, `EVADE`, its deadline.
#[test]
#[available_gas(l2_gas: 256495076)] // ceil(1.05 × 244281024 measured)
fn test_act_vectors_8() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_8;
    let at = CLOCK;
    // A member: none held; its armor (`MemberBar` 232–247, −7) and guarded sums (`MemberKit`
    // 184–191 in a stance 4, 192–199 enchanted −3).
    defence_row(ref digest, ref id, @t, Unit::M(hero(@t, array![])), at);
    let mut m = hero(@t, array![]);
    m.words.bar += (65536 - 7) * two(232);
    m.words.kit += 4 * two(184) + (256 - 3) * two(192);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    // The shield (`ARMOR` 30, an enchantment) to `t` (held), to `t − 1` (lapsed); in two slots
    // (summed 60); a potion's `ARMOR`-less entry held (neither stance nor enchanted).
    for deadline in array![at, at - 1] {
        let mut m = hero(@t, array![]);
        holding(ref m, 1, SHIELD, false, 0, deadline, 12);
        defence_row(ref digest, ref id, @t, Unit::M(m), at);
    }
    let mut m = hero(@t, array![]);
    holding(ref m, 0, SHIELD, false, 0, at, 12);
    holding(ref m, 3, SHIELD, false, 0, at + 5, 0);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    let mut m = hero(@t, array![]);
    holding(ref m, 2, 1, true, 0, at, 0);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    // Each `ARMOR` clamped to 0…255: the rust (−20: 0), the bulwark (300: 255), both with the
    // shield (0 + 255 + 30).
    for skill in array![RUST, BULWARK] {
        let mut m = hero(@t, array![]);
        holding(ref m, 0, skill, false, 0, at, 12);
        defence_row(ref digest, ref id, @t, Unit::M(m), at);
    }
    let mut m = hero(@t, array![]);
    holding(ref m, 0, RUST, false, 0, at, 12);
    holding(ref m, 1, BULWARK, false, 0, at, 12);
    holding(ref m, 2, SHIELD, false, 0, at, 12);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    // Brace (`BLOCK`, a stance): 2 charges in slot 2 (block 2, slot 2, in a stance); 0 charges in
    // slot 1 and 3 in slot 3 (the first with charges: slot 3); 1 in slot 0 and 3 in slot 2 (the
    // lowest: slot 0). Sidestep (`EVADE`, a stance).
    let mut m = hero(@t, array![]);
    holding(ref m, 2, BRACE, false, 2, at, 12);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    let mut m = hero(@t, array![]);
    holding(ref m, 1, BRACE, false, 0, at, 12);
    holding(ref m, 3, BRACE, false, 3, at, 12);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    let mut m = hero(@t, array![]);
    holding(ref m, 0, BRACE, false, 1, at, 12);
    holding(ref m, 2, BRACE, false, 3, at, 12);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    let mut m = hero(@t, array![]);
    holding(ref m, 0, SIDESTEP, false, 0, at, 12);
    defence_row(ref digest, ref id, @t, Unit::M(m), at);
    // A goblin (its caste's armor 40): none held; the shield to `t`, to `t − 1`; the rust (0);
    // Brace with 2 charges; Sidestep.
    defence_row(ref digest, ref id, @t, Unit::G(goblin(8, AT + 1, 0, 100)), at);
    for deadline in array![at, at - 1] {
        defence_row(ref digest, ref id, @t, Unit::G(goblin_holding(SHIELD, 0, deadline, 12)), at);
    }
    defence_row(ref digest, ref id, @t, Unit::G(goblin_holding(RUST, 0, at, 12)), at);
    defence_row(ref digest, ref id, @t, Unit::G(goblin_holding(BRACE, 2, at, 12)), at);
    defence_row(ref digest, ref id, @t, Unit::G(goblin_holding(SIDESTEP, 0, at, 12)), at);
    finish(digest, ACT_DIGEST_8);
}

// `offence`: a weapon hit's terms, a spell's, a bomb's and a trap's; the passives and the held
// `PENETRATION`.
#[test]
#[available_gas(l2_gas: 387983861)] // ceil(1.05 × 369508439 measured)
fn test_act_vectors_9() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_9;
    let at = CLOCK;
    let none: Entry = Default::default();
    let fire = entry(kind::DAMAGE, damage::FIRE, 40, 70, target::FOE, shape::SINGLE, filter::FOES);
    let bomb = entry(kind::DAMAGE, damage::FIRE, 30, 30, target::TILE, shape::DISC_1, filter::FOES);
    let sapped = entry(
        kind::DAMAGE, damage::COLD, -20, -20, target::FOE, shape::SINGLE, filter::FOES,
    );
    // The member's sword (damage 27, range 1: melee, strength 60, slashing, its requirement met):
    // a plain weapon hit (scope 0), bonus 0, 5 and 255; its requirement not met (`MemberStats`
    // 176); a range of 3 (not melee); `LIFE_STEAL_ON_HIT` 3 and `ENERGY_ON_HIT` 2 (`MemberKit`
    // 128, 136).
    for bonus in array![0_u32, 5, 255] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::M(hero(@t, array![])),
            HitClass::Weapon,
            none,
            bonus,
            0,
            context(12, 0, 0, ABSENT, 0, at),
        );
    }
    let mut unmet = hero(@t, array![]);
    unmet.words.stats -= two(176);
    let mut ranged = hero(@t, array![]);
    ranged.words.stats += 2 * two(112);
    let mut thief = hero(@t, array![]);
    thief.words.kit += 3 * two(128) + 2 * two(136);
    for m in array![unmet, ranged, thief] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::M(m),
            HitClass::Weapon,
            none,
            0,
            0,
            context(12, 0, 0, ABSENT, 0, at),
        );
    }
    // The passives (`MemberBar` 136–143, 160–167, 184–191 of scope 0; 144, 168, 192 of 1;
    // 152, 176, 200 of 2: always +10, −5, 3; 20, 6, 4; −30, 7, 5) and the call's penetration 7:
    // a plain weapon hit (scope 0), an attack skill (`Weapon`, scope 1), a spell (scope 2, the fire
    // entry at ranks 0, 6 and 12, level 20: strength 60), a bomb (`Item`, scope 3: none, the
    // potion's strength 30), a trap (`Trap`, scope 3).
    let mut p = hero(@t, array![]);
    p.words.bar += 10 * two(136) + (256 - 5) * two(160) + 3 * two(184);
    p.words.bar += 20 * two(144) + 6 * two(168) + 4 * two(192);
    p.words.bar += (256 - 30) * two(152) + 7 * two(176) + 5 * two(200);
    let fire_at = crate::types::executor::tests::at(@t.sheets, FIRE);
    let rows: Array<(HitClass, Entry, u8, u8, u32)> = array![
        (HitClass::Weapon, none, 0, 12, ABSENT), (HitClass::Weapon, none, 1, 12, ABSENT),
        (HitClass::Spell, fire, 2, 0, fire_at), (HitClass::Spell, fire, 2, 6, fire_at),
        (HitClass::Spell, fire, 2, 12, fire_at), (HitClass::Item, bomb, 3, 12, 0),
        (HitClass::Trap, fire, 3, 12, fire_at), (HitClass::Spell, sapped, 2, 12, fire_at),
    ];
    for (class, e, scope, rank, carrier_at) in rows {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::M(p),
            class,
            e,
            0,
            7,
            context(rank, 2, FIRE, carrier_at, scope, at),
        );
    }
    // The held `PENETRATION`: the edge (`WEAPON` 20) in slot 1 and the focus (`SPELL` 150,
    // clamped to 100) in slot 2, to `t`: scopes 0, 1, 2 and 3; to `t − 1`: none.
    for deadline in array![at, at - 1] {
        let mut m = hero(@t, array![]);
        holding(ref m, 1, EDGE, false, 0, deadline, 12);
        holding(ref m, 2, FOCUS, false, 0, deadline, 12);
        for (class, scope) in array![
            (HitClass::Weapon, 0_u8), (HitClass::Weapon, 1), (HitClass::Spell, 2),
            (HitClass::Trap, 3),
        ] {
            offence_row(
                ref digest,
                ref id,
                @t,
                Unit::M(m),
                class,
                fire,
                0,
                0,
                context(12, 2, FIRE, fire_at, scope, at),
            );
        }
    }
    // A goblin (a Hob of caste rank 12, a sword of 30, range 1, slashing; level 10): its weapon
    // hit, bonus 0 and 5; a spell; a trap; holding the edge: its weapon hit, a spell.
    let hob = goblin(8, AT + 1, 0, 100);
    for bonus in array![0_u32, 5] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::G(hob),
            HitClass::Weapon,
            none,
            bonus,
            0,
            context(12, 0, 0, ABSENT, 0, at),
        );
    }
    for (class, scope) in array![(HitClass::Spell, 2_u8), (HitClass::Trap, 3)] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::G(hob),
            class,
            fire,
            0,
            7,
            context(12, 2, FIRE, fire_at, scope, at),
        );
    }
    let edged = goblin_holding(EDGE, 0, at, 12);
    for (class, scope) in array![(HitClass::Weapon, 0_u8), (HitClass::Spell, 2)] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::G(edged),
            class,
            fire,
            0,
            0,
            context(12, 2, FIRE, fire_at, scope, at),
        );
    }
    finish(digest, ACT_DIGEST_9);
}

/// Goblin 8 East of the member, facing `facing` (0: the member in its front arc; 3: behind it),
/// holding Brace (`BLOCK`) with `charges` to 300.
fn bracing(facing: u8, charges: u8) -> Goblin {
    let mut g = goblin(8, AT + 1, facing, 100);
    GoblinWordsTrait::set_effect(
        ref g, Held { carrier: BRACE, potion: false, charges, deadline: 300, rank: 12 }, 0,
    );
    g
}

// The struck target (track CV's trap port, #444): a blocked weapon hit spends a charge; a target
// knocked down or asleep does not block; the block's cap at 63.
#[test]
#[available_gas(l2_gas: 395141493)] // ceil(1.05 × 376325231 measured)
fn test_act_vectors_10() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_10;
    // The sword on goblin 8 holding Brace, the member in its front arc: blocked, 2 charges to 1, 1
    // to 0 (the effect ends, `D = t₀ − 1`); the member behind it: landed, the charges kept; the
    // attack skill, blocked the same.
    for (facing, charges) in array![(0_u8, 2_u8), (0, 1), (3, 2)] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, hero(@t, array![]), array![bracing(facing, charges)]),
            Action::Attack(8),
        );
    }
    let mut m = hero(@t, array![RAGE]);
    m.adrenaline = 8;
    plain(ref digest, ref id, @t, alone(CLOCK, m, array![bracing(0, 2)]), skill_on(0, 8));
    // Knocked down to `t₀ = c + 1` (held: not blocked, critical), to `c` (lapsed: blocked).
    for knocked in array![CLOCK + 1, CLOCK] {
        let mut g = bracing(0, 2);
        g.knocked = knocked;
        plain(
            ref digest, ref id, @t, alone(CLOCK, hero(@t, array![]), array![g]), Action::Attack(8),
        );
    }
    // Asleep (not blocked: its first hit, D-179); on watch (blocked).
    for (mind, awake) in array![(ai::ASLEEP, false), (ai::WATCH, false)] {
        let mut g = bracing(0, 2);
        g.ai = mind;
        g.awake = awake;
        plain(
            ref digest, ref id, @t, alone(CLOCK, hero(@t, array![]), array![g]), Action::Attack(8),
        );
    }
    // The cap (`MAX_BLOCK`, 63): 63 charges (on it: blocked, to 62), 62 (below: to 61). A goblin
    // holds at most 63 (`GoblinWords` 240–245) and `act` strikes only goblins: no row above it.
    for charges in array![63_u8, 62] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, hero(@t, array![]), array![bracing(0, charges)]),
            Action::Attack(8),
        );
    }
    finish(digest, ACT_DIGEST_10);
}

/// The adventurer with `id` on bar slot `slot` at `rank` (the others the fixtures' 1–8, rank 12).
fn ranked(t: @Table, slot: u8, id: u16, rank: u8) -> Member {
    let mut m = hero(t, array![]);
    let old: felt252 = m.rank(slot).into();
    m.words.stats -= old * two(128 + 4 * slot.into());
    equip(ref m, t.sheets, slot, id, rank);
    m
}

// The bar rank handed to the carrier (`Carrier::Skill((at, member.rank(slot)))`, the review of
// #447): the rune on bar slot 2 at ranks 3 and 9, slot 0 at 12; and a goblin dead by one field
// only, which play never makes: these rows pin the port, which must read liveness from both.
#[test]
#[available_gas(l2_gas: 288675232)] // ceil(1.05 × 274928792 measured)
fn test_act_vectors_11() {
    let t = table();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_11;
    // The rune (instant, `SELF`) held at the slot's rank: 3, 9.
    for rank in array![3_u8, 9] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, ranked(@t, 2, RUNE, rank), array![]),
            skill_on(2, 0),
        );
    }
    // Goblin 8 at health 0 and Engaged; at health 100 and `DEAD`: the sword (`locate`: dead,
    // `Target`), the instant trap on its tile (`TrapTrait::occupied` reads the AI state), the bomb
    // on its tile (count 1).
    let mut engaged = goblin(8, AT + 1, 0, 0);
    engaged.ai = ai::ENGAGED;
    let mut dead = goblin(8, AT + 1, 0, 100);
    dead.ai = ai::DEAD;
    for g in array![engaged, dead] {
        plain(
            ref digest, ref id, @t, alone(CLOCK, hero(@t, array![]), array![g]), Action::Attack(8),
        );
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, hero(@t, array![PIT]), array![g]),
            skill_at(0, AT + 1),
        );
        let mut m = hero(@t, array![]);
        m.set_belt_count(0, 1);
        plain(ref digest, ref id, @t, alone(CLOCK, m, array![g]), Action::Item((0, tile(AT + 1))));
    }
    finish(digest, ACT_DIGEST_11);
}

// ---- Appended by RV-03a2 (D-257): track CV's surviving mutants of the act port (#450). Every
// row from id 223 on reads the content of row 223, the last `content` row before it.

/// Row 223's own skills: a glyph of `NEXT_SPELL_COST` −2; an attack skill holding `ATTACK_BONUS`
/// 10; an enchantment holding `PENETRATION` 30 of scope `ALL`; two preparations holding an
/// `ON_ATTACK_CONDITION` (Poison 4; Bleeding 6, 2 charges); an instant spell of fire 40 on
/// `DISC_1` around its source, filter `ALLIES`; one of fire 40 on a `SINGLE` `TILE`; one of fire 40
/// on a foe and Burning 3 on a `DISC_1` around it; an attack skill holding `HIT_PENETRATION` 50.
const SAPPED: u16 = 77;
const BONUS: u16 = 78;
const EVERY: u16 = 79;
const VENOM: u16 = 80;
const COAT: u16 = 81;
const BLAST: u16 = 82;
const SPOT: u16 = 83;
const SPREAD: u16 = 84;
const PIERCER: u16 = 85;

/// Row 223's content: row 0's (`act_content`), its skills 77–85 appended (none mixing `TILE`
/// with `FOE` or `ALLY`, D-271), every instant (activation 0), no cost.
fn act_content_2() -> Content {
    let base = act_content();
    let none: Entry = Default::default();
    let mut skills = array![];
    skills.append_span(base.skills);
    let sapped = EntryTrait::new(
        kind::NEXT_SPELL_COST,
        0,
        -2,
        -2,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        0,
    );
    let mut sheet = skill(SAPPED, skill_kind::GLYPH, 0, [sapped, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let bonus = entry(kind::ATTACK_BONUS, 0, 10, 10, target::FOE, shape::SINGLE, filter::FOES);
    let mut sheet = skill(BONUS, skill_kind::ATTACK, 1, [bonus, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let every = EntryTrait::new(
        kind::PENETRATION,
        0,
        30,
        30,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        scope::ALL,
    );
    let mut sheet = skill(EVERY, skill_kind::ENCHANTMENT, 0, [every, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let venom = EntryTrait::new(
        kind::ON_ATTACK_CONDITION,
        condition::POISON,
        4,
        4,
        10,
        10,
        0,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        0,
    );
    let mut sheet = skill(VENOM, skill_kind::PREPARATION, 0, [venom, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let coat = EntryTrait::new(
        kind::ON_ATTACK_CONDITION,
        condition::BLEEDING,
        6,
        6,
        10,
        10,
        2,
        target::SELF,
        shape::SINGLE,
        filter::ALLIES,
        0,
        0,
    );
    let mut sheet = skill(COAT, skill_kind::PREPARATION, 0, [coat, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let blast = entry(
        kind::DAMAGE, damage::FIRE, 40, 40, target::SELF, shape::DISC_1, filter::ALLIES,
    );
    let mut sheet = skill(BLAST, skill_kind::SPELL, 0, [blast, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let spot = entry(kind::DAMAGE, damage::FIRE, 40, 40, target::TILE, shape::SINGLE, filter::FOES);
    let mut sheet = skill(SPOT, skill_kind::SPELL, 6, [spot, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let fire = entry(kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES);
    let burn = entry(
        kind::CONDITION, condition::BURNING, 3, 3, target::FOE, shape::DISC_1, filter::FOES,
    );
    let mut sheet = skill(SPREAD, skill_kind::SPELL, 6, [fire, burn, none]);
    sheet.activation = 0;
    skills.append(sheet);
    let pierce = entry(kind::HIT_PENETRATION, 0, 50, 50, target::FOE, shape::SINGLE, filter::FOES);
    let mut sheet = skill(PIERCER, skill_kind::ATTACK, 1, [pierce, none, none]);
    sheet.activation = 0;
    skills.append(sheet);
    Content { skills: skills.span(), ..base }
}

fn table_2() -> Table {
    let content = act_content_2();
    Table {
        action: class("ActionLibrary"),
        executor: class("ExecutorLibrary"),
        content,
        sheets: content.sheets(),
    }
}

// Row 223, the content; the skill's checks by slot (the weapon-required bit, the quick-cast pairs),
// a negative glyph; the attack skill's scope, its hit modifiers.
#[test]
#[available_gas(l2_gas: 389657184)] // ceil(1.05 × 371102080 measured)
fn test_act_vectors_12() {
    let t = table_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_12;
    let mut ok = array![];
    Serde::serialize(@t.content, ref ok);
    emit(ref digest, ref id, "content", array![].span(), ok.span());
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // The attack skill (2 strikes, 8 quarters held) on bar slot 1: with slot 0's weapon-required
    // bit only (`MemberStats` 40), legal; with slot 1's (41), `Kind`.
    for bit in array![40_u32, 41] {
        let mut m = with_skill(@t, 1, RAGE);
        m.adrenaline = 8;
        m.words.stats += two(bit);
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(1, 8));
    }
    // A glyph of −2 held in effect slot 0 to `c + 5`: it takes nothing off the fire spell (5,
    // 15 thirds: legal), consumed all the same.
    let mut m = hero(@t, array![FIRE]);
    m.energy = 15;
    holding(ref m, 0, SAPPED, false, 0, CLOCK + 5, 12);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    // The fire spell on bar slot 1, which counts for pair 0 (`MemberStats` 170; pair 0 of N 5,
    // its counter at 4): the bonus, activation 2.
    let mut m = with_skill(@t, 1, FIRE);
    m.energy = 30;
    m.words.bar += 5 * two(212);
    m.words.stats += two(170);
    m.set_casts(0, 4);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(1, 8));
    // The attack skill (scope 1) landing on goblin 8 with the passives of every scope (`MemberBar`
    // 136–200, as rows 183–190: scope 1's +20, 6, 4 taken); holding the edge (`PENETRATION` 20
    // of scope `WEAPON`, which an attack skill takes).
    let mut m = hero(@t, array![RAGE]);
    m.adrenaline = 8;
    m.words.bar += 10 * two(136) + (256 - 5) * two(160) + 3 * two(184);
    m.words.bar += 20 * two(144) + 6 * two(168) + 4 * two(192);
    m.words.bar += (256 - 30) * two(152) + 7 * two(176) + 5 * two(200);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    let mut m = hero(@t, array![RAGE]);
    m.adrenaline = 8;
    holding(ref m, 1, EDGE, false, 0, CLOCK + 5, 12);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    // The attack skills holding `ATTACK_BONUS` 10 and `HIT_PENETRATION` 50 on goblin 8 (armor
    // 40).
    for skill in array![BONUS, PIERCER] {
        plain(
            ref digest,
            ref id,
            @t,
            alone(CLOCK, hero(@t, array![skill]), goblins.clone()),
            skill_on(0, 8),
        );
    }
    finish(digest, ACT_DIGEST_12);
}

// The source's side of a weapon hit: the held `PENETRATION` of scope `ALL`, the
// `ON_ATTACK_CONDITION`s, `LIFE_STEAL_ON_HIT` and `ENERGY_ON_HIT`.
#[test]
#[available_gas(l2_gas: 266557446)] // ceil(1.05 × 253864234 measured)
fn test_act_vectors_13() {
    let t = table_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_13;
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // Holding `PENETRATION` 30 of scope `ALL` (effect slot 2, to `c + 5`): the bomb (belt slot 0,
    // count 1, on goblin 8's tile: scope 3, none taken); the sword (taken); the instant spell
    // (taken).
    let mut m = hero(@t, array![BOLT]);
    holding(ref m, 2, EVERY, false, 0, CLOCK + 5, 12);
    m.set_belt_count(0, 1);
    plain(
        ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Item((0, tile(AT + 1))),
    );
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), skill_on(0, 8));
    // The sword holding an `ON_ATTACK_CONDITION` (Poison 4, slot 0): goblin 8 poisoned; and one
    // with 2 charges (Bleeding 6, slot 1) beside it: both applied, the charge spent (2 to 1).
    let mut m = hero(@t, array![]);
    holding(ref m, 0, VENOM, false, 0, CLOCK + 5, 12);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    holding(ref m, 1, COAT, false, 2, CLOCK + 5, 12);
    plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    // The sword with `LIFE_STEAL_ON_HIT` 3 (`MemberKit` 128), the member at 400 of 480: 3
    // stolen; with `ENERGY_ON_HIT` 2 (136), at 30 thirds of 60: 6 thirds gained.
    for kit in array![3 * two(128), 2 * two(136)] {
        let mut m = hero(@t, array![]);
        m.words.kit += kit;
        plain(ref digest, ref id, @t, alone(CLOCK, m, goblins.clone()), Action::Attack(8));
    }
    finish(digest, ACT_DIGEST_13);
}

// The target sets (`actors`): a hit of filter `ALLIES` around its source, a dead member in a wide
// set, a `SINGLE` `TILE` entry, the actors' order, a set the hit's does not hold.
#[test]
#[available_gas(l2_gas: 259516751)] // ceil(1.05 × 247158810 measured)
fn test_act_vectors_14() {
    let t = table_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_14;
    let goblins = array![goblin(8, AT + 1, 0, 100)];
    // Fire 40 on `DISC_1` around the member, filter `ALLIES`: member 1 West of it (position 111)
    // hit, the member not (never in its own hit's set; not separated: mutant 509 is equivalent,
    // see README); member 1 there at 0 health: not a candidate, nothing (no `HIT` flag).
    for health in array![400_u16, 0] {
        let mut friend = ally(AT - 1);
        friend.health = health;
        plain(
            ref digest,
            ref id,
            @t,
            words(CLOCK, array![hero(@t, array![BLAST]), friend], goblins.clone()),
            skill_on(0, 0),
        );
    }
    // Fire 40 on a `SINGLE` `TILE`, goblin 8's: hit.
    plain(
        ref digest,
        ref id,
        @t,
        alone(CLOCK, hero(@t, array![SPOT]), goblins.clone()),
        skill_at(0, AT + 1),
    );
    // The bomb (count 1) on position 113: goblin 8 on 114 and goblin 9 on 113, both at 1 health,
    // killed in ascending position, 9 then 8 (`killed`), not in index order.
    let mut m = hero(@t, array![]);
    m.set_belt_count(0, 1);
    let pair = array![goblin(8, AT + 2, 0, 1), goblin(9, AT + 1, 0, 1)];
    plain(ref digest, ref id, @t, alone(CLOCK, m, pair), Action::Item((0, tile(AT + 1))));
    // Fire 40 on goblin 8 (113) and Burning 3 on `DISC_1` around it: goblin 9 (114) burns, not
    // hit.
    let pair = array![goblin(8, AT + 1, 0, 100), goblin(9, AT + 2, 0, 100)];
    plain(ref digest, ref id, @t, alone(CLOCK, hero(@t, array![SPREAD]), pair), skill_on(0, 8));
    finish(digest, ACT_DIGEST_14);
}

// RV-03a3 (D-257): `offence` holding `PENETRATION` 30 of scope `ALL`, which a bomb's or a trap's
// hit (scope 3) never takes; no `act` row can show it, `resolve` reading penetration of a weapon
// hit or a spell only.
#[test]
#[available_gas(l2_gas: 95144671)] // ceil(1.05 × 90613972 measured)
fn test_act_vectors_15() {
    let t = table_2();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = ACT_PART_15;
    let at = CLOCK;
    let fire = entry(kind::DAMAGE, damage::FIRE, 40, 70, target::FOE, shape::SINGLE, filter::FOES);
    let bomb = entry(kind::DAMAGE, damage::FIRE, 30, 30, target::TILE, shape::DISC_1, filter::FOES);
    let fire_at = crate::types::executor::tests::at(@t.sheets, FIRE);
    // The member holding skill 79 in effect slot 2 to `t`: a plain weapon hit (scope 0), an
    // attack skill (1), a spell (2) take its 30; a bomb (`Item`, scope 3) and a trap (`Trap`,
    // scope 3) none.
    let mut m = hero(@t, array![]);
    holding(ref m, 2, EVERY, false, 0, at, 12);
    let rows: Array<(HitClass, Entry, u8, u32)> = array![
        (HitClass::Weapon, fire, 0, fire_at), (HitClass::Weapon, fire, 1, fire_at),
        (HitClass::Spell, fire, 2, fire_at), (HitClass::Item, bomb, 3, 0),
        (HitClass::Trap, fire, 3, fire_at),
    ];
    for (class, e, scope, carrier_at) in rows {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::M(m),
            class,
            e,
            0,
            0,
            context(12, 2, FIRE, carrier_at, scope, at),
        );
    }
    // Goblin 8 holding it: a spell (scope 2) takes it, a trap (scope 3) does not.
    let held = goblin_holding(EVERY, 0, at, 12);
    for (class, scope) in array![(HitClass::Spell, 2_u8), (HitClass::Trap, 3)] {
        offence_row(
            ref digest,
            ref id,
            @t,
            Unit::G(held),
            class,
            fire,
            0,
            0,
            context(12, 2, FIRE, fire_at, scope, at),
        );
    }
    finish(digest, ACT_DIGEST_15);
}

/// The first id of each part, and each part's digest.
const ACT_PART_1: u32 = 27;
const ACT_PART_2: u32 = 43;
const ACT_PART_3: u32 = 70;
const ACT_PART_4: u32 = 95;
const ACT_PART_5: u32 = 107;
const ACT_PART_6: u32 = 128;
const ACT_PART_7: u32 = 144;
const ACT_PART_8: u32 = 158;
const ACT_PART_9: u32 = 177;
const ACT_PART_10: u32 = 205;
const ACT_PART_11: u32 = 215;
const ACT_PART_12: u32 = 223;
const ACT_PART_13: u32 = 232;
const ACT_PART_14: u32 = 239;
const ACT_PART_15: u32 = 244;
const ACT_DIGEST_0: felt252 =
    1030940271732062604804669110503688872228708044099169595645925593071242230283;
const ACT_DIGEST_1: felt252 =
    1877557721926457155813392980629918693731735479670870480906151700622873362804;
const ACT_DIGEST_2: felt252 =
    2155260657038495315163185118748703662879353180211412156835508204161953960819;
const ACT_DIGEST_3: felt252 =
    3138600085200800918734995720959513392942643883035079236558859120978533027964;
const ACT_DIGEST_4: felt252 =
    2869183508149844581645506755790026186828086578831961600605060318144159783553;
const ACT_DIGEST_5: felt252 =
    1824939615617333653090107050616329125677940737453819248504895830803274355943;
const ACT_DIGEST_6: felt252 =
    1203805621806876648476583917929853616124543079888817121158120546887060930534;
const ACT_DIGEST_7: felt252 =
    2942793287167649455997698397685145632568504538091578805479456198635937661385;
const ACT_DIGEST_8: felt252 =
    125427638892877233255178533104061449391953775311725324253266212463024105458;
const ACT_DIGEST_9: felt252 =
    2720915314688875214492673004805861766276897858278301462922432372461233942929;
const ACT_DIGEST_10: felt252 =
    2161744668382002736604283308408713117091980477643056135990864466526928679814;
const ACT_DIGEST_11: felt252 =
    2143361324673287838917145131743092043867945749555276112912585183627383427359;
const ACT_DIGEST_12: felt252 =
    3563418450462612459837549235224416494549560583332690645257836198876947044365;
const ACT_DIGEST_13: felt252 =
    3176533727201977987469364170763399164895871530069662833270276512284174446524;
const ACT_DIGEST_14: felt252 =
    965705507953071005487549611047696454075520364973681577494560792299333371081;
const ACT_DIGEST_15: felt252 =
    3369404342547317277746575153716820682249534639394267514847011043546253937437;
