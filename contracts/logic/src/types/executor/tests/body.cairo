//! `vectors/body.jsonl` (RV-03a, D-257): the `Body` operations on an actor, member and goblin,
//! and the effect entry's operations (`types/effect.cairo`), with their full inputs and outputs,
//! for the client's mirror of the classes. Row 0 is the table's content; every actor is loaded
//! through it. The families, their order and the bounds each row sits on are in
//! `vectors/README.md`.
//!
//! An actor is recorded as `Unit`'s layout: `0` then the `Member`'s fields, or `1` then the
//! `Goblin`'s, each field in its struct's declaration order (`models/index.cairo`), an array's
//! elements in order with no length, a `MemberWords` its `Serde`: what `#[derive(Serde)]` would
//! write (the structs derive none). The operations run through `UnitBody`, the executor's
//! dispatch (CBT-05a, route (c)).

use crate::models::goblin::{Goblin, GoblinTrait, GoblinWords, GoblinWordsTrait};
use crate::models::member::{Member, MemberLifecycleTrait, MemberTrait, MemberWordsTrait};
use crate::types::MAX_CLOCK;
use crate::types::combat::{activation, condition, skill_kind};
use crate::types::effect::{Entry, EntryTrait, kind};
use crate::types::executor::{Unit, UnitBody};
use crate::types::infliction::Infliction;
use crate::types::tick::{
    CasteSheet, Content, ContentTrait, Held, PotionSheet, Sheets, SkillSheetTrait, ai, flag, status,
};
use crate::types::world::fixtures::{Fixture, HOB, RUNT, two};
use super::at;

/// The clock or tick the operations that take one run at.
const T: u32 = 50;

// ---- Printing (as `types::play::tests`): one JSON line a row, every felt in hex, a digest.

pub fn hex(felts: Span<felt252>) -> ByteArray {
    let mut out: ByteArray = "[";
    let mut first = true;
    for felt in felts {
        if !first {
            out.append(@",");
        }
        first = false;
        let wide: u256 = (*felt).into();
        out.append(@format!("\"0x{:x}\"", wide));
    }
    out.append(@"]");
    out
}

pub fn emit(
    ref digest: Array<felt252>,
    ref id: u32,
    name: ByteArray,
    case: Span<felt252>,
    ok: Span<felt252>,
) {
    println!("{{\"id\":{},\"fn\":\"{}\",\"case\":{},\"ok\":{}}}", id, name, hex(case), hex(ok));
    digest.append(core::poseidon::poseidon_hash_span(case));
    digest.append(core::poseidon::poseidon_hash_span(ok));
    id += 1;
}

/// A part's digest, against the one its constant holds.
pub fn finish(digest: Array<felt252>, expected: felt252) {
    let digest = core::poseidon::poseidon_hash_span(digest.span());
    println!("digest {}", digest);
    assert(digest == expected, 'vectors moved: regenerate');
}

// ---- The actor as felts.

fn member_felts(m: @Member, ref out: Array<felt252>) {
    out.append((*m.status).into());
    out.append((*m.health).into());
    out.append((*m.energy).into());
    out.append((*m.adrenaline).into());
    out.append((*m.flags).into());
    out.append((*m.act_slot).into());
    out.append((*m.act_target).into());
    out.append((*m.act_tile).into());
    out.append((*m.act_deadline).into());
    out.append((*m.bleeding).into());
    out.append((*m.poison).into());
    out.append((*m.burning).into());
    out.append((*m.knocked).into());
    for d in m.effect_deadlines.span() {
        out.append((*d).into());
    }
    for r in m.effect_regen.span() {
        out.append((*r).into());
    }
    out.append((*m.max_health).into());
    out.append((*m.max_energy).into());
    out.append((*m.health_regen).into());
    out.append((*m.energy_regen).into());
    out.append((*m.adrenaline_cap).into());
    out.append((*m.bar_at).into());
    out.append((*m.effect_at).into());
    Serde::serialize(m.words, ref out);
}

fn goblin_felts(g: @Goblin, ref out: Array<felt252>) {
    out.append((*g.entity).into());
    out.append(if *g.awake {
        1
    } else {
        0
    });
    out.append((*g.ai).into());
    out.append((*g.health).into());
    out.append((*g.energy).into());
    out.append((*g.adrenaline).into());
    out.append((*g.caste).into());
    out.append((*g.act_slot).into());
    out.append((*g.act_target).into());
    out.append((*g.act_deadline).into());
    out.append((*g.bleeding).into());
    out.append((*g.poison).into());
    out.append((*g.burning).into());
    out.append((*g.knocked).into());
    out.append((*g.effect_deadline).into());
    out.append((*g.effect_regen).into());
    out.append((*g.max_health).into());
    out.append((*g.caste_at).into());
    out.append((*g.effect_at).into());
    out.append(*g.state);
    out.append(*g.timers);
}

fn unit_felts(unit: @Unit, ref out: Array<felt252>) {
    match unit {
        Unit::M(m) => {
            out.append(0);
            member_felts(m, ref out);
        },
        Unit::G(g) => {
            out.append(1);
            goblin_felts(g, ref out);
        },
    }
}

fn flag_felt(b: bool) -> felt252 {
    if b {
        1
    } else {
        0
    }
}

// ---- The table's content and its actors.

/// The fixtures' content (`Fixture::content`: the bar's skills 1–8 at positions 0–7, the
/// castes'
/// 24–31 at 8–15), with: skill 1 an adrenaline cost of 5 strikes (a member's cap, 20 quarters),
/// skill 3 a stance whose `REGENERATION` line is 1 to 4, skill 4 a stance, skill 5 an enchantment
/// of −2 to −5 pips, skill 24 (Hob's slot 0) a cost of 5 (Hob's cap, 20); the belt's potions
/// 100 to 103 (pips 1, 3, −2, 0); the castes of armor 20, Hob's `ARMOR_VS` 5 against type 1 and
/// 63 against type 9, Runt's 11 to 19 against types 1 to 9.
pub fn body_content() -> Content {
    let base = Fixture::content();
    let mut skills = array![];
    for sheet in base.skills {
        let mut sheet = *sheet;
        if sheet.id == 1 || sheet.id == 24 {
            sheet.adrenaline = 5;
        } else if sheet.id == 3 {
            sheet.kind = skill_kind::STANCE;
            sheet.regen0 = 1;
            sheet.regen12 = 4;
        } else if sheet.id == 4 {
            sheet.kind = skill_kind::STANCE;
        } else if sheet.id == 5 {
            sheet.kind = skill_kind::ENCHANTMENT;
            sheet.regen0 = -2;
            sheet.regen12 = -5;
        }
        skills.append(sheet);
    }
    let potions = array![
        PotionSheet { id: 100, regen: 1, ..Default::default() },
        PotionSheet { id: 101, regen: 3, ..Default::default() },
        PotionSheet { id: 102, regen: -2, ..Default::default() },
        PotionSheet { id: 103, regen: 0, ..Default::default() },
    ];
    // RV-03a fix loop 1: Runt's `ARMOR_VS` 11 to 19 against types 1 to 9, one a lane.
    let mut lanes: u64 = 0;
    let mut shift: u64 = 1;
    for t in 1..10_u64 {
        lanes += (10 + t) * shift;
        shift *= 64;
    }
    let mut castes: Array<CasteSheet> = array![];
    for caste in base.castes {
        let armor_vs = if *caste.id == RUNT {
            lanes
        } else {
            5 + 63 * 0x1000000000000
        };
        castes.append(CasteSheet { armor: 20, armor_vs, ..*caste });
    }
    Content { skills: skills.span(), potions: potions.span(), castes: castes.span() }
}

/// The hot fields written back into the words, so that the recorded actor is one `load` gives.
fn synced(m: Member) -> Member {
    let mut m = m;
    m.words = m.store();
    m
}

fn gsynced(g: Goblin) -> Goblin {
    let mut g = g;
    let words = g.store();
    g.state = words.state;
    g.timers = words.timers;
    g
}

/// The fixtures' member (health 400 of 480, energy 30 of 60 thirds, adrenaline 0 of its cap 20,
/// no condition, no effect), loaded through the content.
fn member(content: @Content) -> Member {
    Fixture::load_member(Fixture::member_words(Fixture::spec()), content)
}

/// Goblin 264 of caste Hob (Engaged, health 100, energy 0 of 30 thirds, adrenaline 0 of 20),
/// loaded through the content.
fn goblin(content: @Content) -> Goblin {
    let g = Fixture::goblin(264, HOB);
    let words = GoblinWords { entity: 264, awake: true, state: g.state, timers: g.timers };
    Fixture::load_goblin(words, content)
}

fn m_with(content: @Content, health: u16, adrenaline: u16, flags: u8) -> Unit {
    let mut m = member(content);
    m.health = health;
    m.adrenaline = adrenaline;
    m.flags = flags;
    Unit::M(synced(m))
}

fn g_with(content: @Content, mind: u8, health: u16, adrenaline: u8) -> Unit {
    let mut g = goblin(content);
    g.ai = mind;
    g.health = health;
    g.adrenaline = adrenaline;
    Unit::G(gsynced(g))
}

/// The member with `held` put in `slot` (its pips and carrier's position, as the executor does).
fn m_holding(m: Member, slot: u8, held: Held, sheets: @Sheets) -> Member {
    let mut m = m;
    let at = if held.potion {
        held.carrier.into()
    } else {
        at(sheets, held.carrier)
    };
    MemberLifecycleTrait::put(ref m, slot, held, at, sheets);
    m
}

fn g_holding(g: Goblin, held: Held, sheets: @Sheets) -> Goblin {
    let mut g = g;
    let at = at(sheets, held.carrier);
    let pips: i32 = (*sheets.skills)[at].regen(held.rank);
    GoblinWordsTrait::set_effect(ref g, held, pips.try_into().unwrap());
    g.effect_at = at;
    g
}

fn held(carrier: u16, potion: bool, charges: u8, deadline: u32, rank: u8) -> Held {
    Held { carrier, potion, charges, deadline, rank }
}

// ---- One operation on one actor.

#[derive(Copy, Drop)]
enum Op {
    Health,
    MaxHealth,
    Alive,
    IsMember,
    Place,
    Knocked: u32,
    Asleep,
    Halves,
    ArmorVs: u8,
    Inflicts,
    EnchantPercent,
    Slots,
    Effect: u8,
    Wound: u16,
    Heal: u16,
    Energize: i32,
    Struck,
    Landed,
    Halved,
    Inflict: (u8, i32, Infliction, u32),
    Cure: (u8, u32),
    Hold: (Held, u32, bool, u32),
    Spend: (u8, u32),
}

/// One row: `case` the actor then the operation's arguments (the sheets are the content's); `ok`
/// a read's value, or a write's actor after.
fn row(ref digest: Array<felt252>, ref id: u32, sheets: @Sheets, unit: Unit, op: Op) {
    let mut case: Array<felt252> = array![];
    unit_felts(@unit, ref case);
    let mut ok: Array<felt252> = array![];
    let mut after = unit;
    let mut wrote = true;
    let name: ByteArray = match op {
        Op::Health => {
            wrote = false;
            ok.append(UnitBody::health(@unit).into());
            "health"
        },
        Op::MaxHealth => {
            wrote = false;
            ok.append(UnitBody::max_health(@unit).into());
            "max_health"
        },
        Op::Alive => {
            wrote = false;
            ok.append(flag_felt(UnitBody::alive(@unit)));
            "alive"
        },
        Op::IsMember => {
            wrote = false;
            ok.append(flag_felt(UnitBody::is_member(@unit)));
            "is_member"
        },
        Op::Place => {
            wrote = false;
            let (x, y, facing) = UnitBody::place(@unit);
            ok.append(x.into());
            ok.append(y.into());
            ok.append(facing.into());
            "place"
        },
        Op::Knocked(t) => {
            wrote = false;
            case.append(t.into());
            ok.append(flag_felt(UnitBody::knocked(@unit, t)));
            "knocked"
        },
        Op::Asleep => {
            wrote = false;
            ok.append(flag_felt(UnitBody::asleep(@unit)));
            "asleep"
        },
        Op::Halves => {
            wrote = false;
            ok.append(flag_felt(UnitBody::halves(@unit)));
            "halves"
        },
        Op::ArmorVs(damage_type) => {
            wrote = false;
            case.append(damage_type.into());
            ok.append(UnitBody::armor_vs(@unit, damage_type, sheets).into());
            "armor_vs"
        },
        Op::Inflicts => {
            wrote = false;
            Serde::serialize(@UnitBody::infliction(@unit), ref ok);
            "infliction"
        },
        Op::EnchantPercent => {
            wrote = false;
            ok.append(UnitBody::enchant_percent(@unit).into());
            "enchant_percent"
        },
        Op::Slots => {
            wrote = false;
            ok.append(UnitBody::slots(@unit).into());
            "slots"
        },
        Op::Effect(slot) => {
            wrote = false;
            case.append(slot.into());
            let (held, at) = UnitBody::effect(@unit, slot);
            Serde::serialize(@held, ref ok);
            ok.append(at.into());
            "effect"
        },
        Op::Wound(damage) => {
            case.append(damage.into());
            UnitBody::wound(ref after, damage);
            "wound"
        },
        Op::Heal(v) => {
            case.append(v.into());
            UnitBody::heal(ref after, v);
            "heal"
        },
        Op::Energize(v) => {
            case.append(v.into());
            UnitBody::energize(ref after, v, sheets);
            "energize"
        },
        Op::Struck => {
            UnitBody::struck(ref after, sheets);
            "struck"
        },
        Op::Landed => {
            UnitBody::landed(ref after, sheets);
            "landed"
        },
        Op::Halved => {
            UnitBody::halved(ref after);
            "halved"
        },
        Op::Inflict((
            c, v, source, t,
        )) => {
            case.append(c.into());
            case.append(v.into());
            Serde::serialize(@source, ref case);
            case.append(t.into());
            UnitBody::inflict(ref after, c, v, @source, t, sheets);
            "inflict"
        },
        Op::Cure((
            c, t,
        )) => {
            case.append(c.into());
            case.append(t.into());
            UnitBody::cure(ref after, c, t);
            "cure"
        },
        Op::Hold((
            held, at, stance, t,
        )) => {
            Serde::serialize(@held, ref case);
            case.append(at.into());
            case.append(flag_felt(stance));
            case.append(t.into());
            UnitBody::hold(ref after, held, at, stance, t, sheets);
            "hold"
        },
        Op::Spend((
            slot, t,
        )) => {
            case.append(slot.into());
            case.append(t.into());
            UnitBody::spend(ref after, slot, t);
            "spend"
        },
    };
    if wrote {
        unit_felts(@after, ref ok);
    }
    emit(ref digest, ref id, name, case.span(), ok.span());
}

// ---- The families.

/// The reads: one row a kind for the plain ones, each branch and bound for the others.
fn reads(content: @Content, sheets: @Sheets) -> Array<(Unit, Op)> {
    let m = Unit::M(member(content));
    let g = Unit::G(goblin(content));
    let mut rows = array![
        (m, Op::Health), (g, Op::Health), (m, Op::MaxHealth), (g, Op::MaxHealth), (m, Op::IsMember),
        (g, Op::IsMember),
    ];
    // `place`: a member on (7, 9) facing 4, the goblin on (11, 3) facing 2.
    let mut placed = member(content);
    placed.words.state += 7 * two(32) + 9 * two(40) + 4 * two(48);
    let mut there = goblin(content);
    there.state += 11 + 3 * two(8) + 2 * two(16);
    rows.append((Unit::M(placed), Op::Place));
    rows.append((Unit::G(there), Op::Place));
    // `alive`: a member inside above 0; at 0; down; gone. A goblin Engaged above 0; at 0;
    // Returning (the last state below `DEAD`); Dead with health left; Looted.
    rows.append((m_with(content, 1, 0, 0), Op::Alive));
    rows.append((m_with(content, 0, 0, 0), Op::Alive));
    let mut down = member(content);
    down.status = status::DOWN;
    down.health = 50;
    rows.append((Unit::M(synced(down)), Op::Alive));
    let mut gone = member(content);
    gone.status = status::GONE;
    rows.append((Unit::M(synced(gone)), Op::Alive));
    rows.append((g_with(content, ai::ENGAGED, 1, 0), Op::Alive));
    rows.append((g_with(content, ai::ENGAGED, 0, 0), Op::Alive));
    rows.append((g_with(content, ai::RETURNING, 100, 0), Op::Alive));
    rows.append((g_with(content, ai::DEAD, 50, 0), Op::Alive));
    rows.append((g_with(content, ai::LOOTED, 50, 0), Op::Alive));
    // `knocked`: Knocked down to 50, at 49, 50 (held: `t ≤ D`) and 51.
    let mut knocked = member(content);
    knocked.knocked = 50;
    let knocked = Unit::M(synced(knocked));
    let mut gknocked = goblin(content);
    gknocked.knocked = 50;
    let gknocked = Unit::G(gsynced(gknocked));
    for t in array![49_u32, 50, 51] {
        rows.append((knocked, Op::Knocked(t)));
        rows.append((gknocked, Op::Knocked(t)));
    }
    // `asleep`: a goblin asleep, on watch; a member never.
    rows.append((g_with(content, ai::ASLEEP, 100, 0), Op::Asleep));
    rows.append((g_with(content, ai::WATCH, 100, 0), Op::Asleep));
    rows.append((m, Op::Asleep));
    // `halves`: `HALVE_FIRST_HEAVY_HIT` held (`MemberKit` bit 202), not spent; spent (`HALVED`);
    // not held; a goblin never.
    let mut halving = member(content);
    halving.words.kit += two(202);
    rows.append((Unit::M(halving), Op::Halves));
    let mut spent = halving;
    spent.flags = flag::HALVED;
    rows.append((Unit::M(synced(spent)), Op::Halves));
    rows.append((m, Op::Halves));
    rows.append((g, Op::Halves));
    // `armor_vs`: the member's per-type armors 5, 6, 7 and 63 (types 1, 2, 3, 9; `MemberStats`
    // 48, 54, 200, 236), types 0 and 10 none; the goblin's caste (5 against 1, 63 against 9).
    let mut armored = member(content);
    armored.words.stats += 5 * two(48) + 6 * two(54) + 7 * two(200) + 63 * two(236);
    for damage_type in array![0_u8, 1, 2, 3, 9, 10] {
        rows.append((Unit::M(armored), Op::ArmorVs(damage_type)));
    }
    for damage_type in array![0_u8, 1, 9, 10] {
        rows.append((g, Op::ArmorVs(damage_type)));
    }
    // `infliction` and `enchant_percent`: a member's kit (`CONDITION_DURATION` Burning 33 % at
    // 144 and 148, `ENCHANT_DURATION` 15 % at 154, `KNOCKDOWN_FLAT` 1 at 200); a goblin's none.
    let mut kit = member(content);
    kit.words.kit += 3 * two(144) + 33 * two(148) + 15 * two(154) + two(200);
    rows.append((Unit::M(kit), Op::Inflicts));
    rows.append((g, Op::Inflicts));
    rows.append((Unit::M(kit), Op::EnchantPercent));
    rows.append((g, Op::EnchantPercent));
    // `slots` and `effect`: a member 4, a goblin 1; a member's slot holding skill 5 (2 charges,
    // rank 12), an empty one, one holding belt potion 2; the goblin holding skill 5, and empty.
    rows.append((m, Op::Slots));
    rows.append((g, Op::Slots));
    let mut effects = m_holding(member(content), 1, held(5, false, 2, 60, 12), sheets);
    effects = m_holding(effects, 3, held(2, true, 0, 58, 0), sheets);
    for slot in array![1_u8, 2, 3] {
        rows.append((Unit::M(effects), Op::Effect(slot)));
    }
    rows
        .append(
            (Unit::G(g_holding(goblin(content), held(5, false, 2, 60, 12), sheets)), Op::Effect(0)),
        );
    rows.append((g, Op::Effect(0)));
    rows
}

/// `wound`, `heal`, `energize`: each side of every comparison.
fn health(content: @Content) -> Array<(Unit, Op)> {
    let m = m_with(content, 400, 0, 0);
    let g = Unit::G(goblin(content));
    let mut rows = array![];
    // `wound`: `damage ≥ health` at 0, health − 1, health, health + 1, the maximum; at 0
    // health; a dead goblin with health left (no alive check).
    for damage in array![0_u16, 399, 400, 401, 65535] {
        rows.append((m, Op::Wound(damage)));
    }
    rows.append((m_with(content, 0, 0, 0), Op::Wound(0)));
    for damage in array![99_u16, 100, 101] {
        rows.append((g, Op::Wound(damage)));
    }
    rows.append((g_with(content, ai::DEAD, 50, 0), Op::Wound(10)));
    // `heal`: 400 of 480 by 0, 79, 80, 81 and the maximum; at the max by 1; nothing at 0
    // health or down. The goblin to its max − 1, its max, past it; nothing dead, or at 0.
    for v in array![0_u16, 79, 80, 81, 65535] {
        rows.append((m, Op::Heal(v)));
    }
    rows.append((m_with(content, 480, 0, 0), Op::Heal(1)));
    rows.append((m_with(content, 0, 0, 0), Op::Heal(10)));
    let mut down = member(content);
    down.status = status::DOWN;
    down.health = 50;
    rows.append((Unit::M(synced(down)), Op::Heal(10)));
    let room = match g {
        Unit::G(g) => g.max_health - g.health,
        Unit::M(_) => 0,
    };
    for v in array![room - 1, room, room + 1] {
        rows.append((g, Op::Heal(v)));
    }
    rows.append((g_with(content, ai::DEAD, 50, 0), Op::Heal(10)));
    rows.append((g_with(content, ai::ENGAGED, 0, 0), Op::Heal(10)));
    // `energize`, in energy (× 3 thirds), clamped to 0 and the max: the member's 30 of 60
    // thirds by 10 (exactly the max), 11, 9, 0, −10 (exactly 0), −11, −9; the goblin's 0 of
    // 30 by 10, 11, 9, −1, and from 30 by −10, −11, −9.
    for v in array![10_i32, 11, 9, 0, -10, -11, -9] {
        rows.append((m, Op::Energize(v)));
    }
    for v in array![10_i32, 11, 9, -1] {
        rows.append((g, Op::Energize(v)));
    }
    let mut full = goblin(content);
    full.energy = 30;
    let full = Unit::G(gsynced(full));
    for v in array![-10_i32, -11, -9] {
        rows.append((full, Op::Energize(v)));
    }
    rows
}

/// `struck`, `landed`, `halved`: the adrenaline and its cap, the `hits` counter, the waking.
fn hits(content: @Content) -> Array<(Unit, Op)> {
    let mut rows = array![];
    // `struck`, a member: the `HIT` flag and 1 quarter: from 0; at 0 health (the flag only);
    // 19 of the cap 20; at it; above it (kept); with `TURNED | HIT` already set.
    rows.append((m_with(content, 400, 0, 0), Op::Struck));
    rows.append((m_with(content, 0, 0, 0), Op::Struck));
    rows.append((m_with(content, 400, 19, 0), Op::Struck));
    rows.append((m_with(content, 400, 20, 0), Op::Struck));
    rows.append((m_with(content, 400, 25, 0), Op::Struck));
    rows.append((m_with(content, 400, 0, flag::TURNED | flag::HIT), Op::Struck));
    // A goblin: Engaged from 0, 19, 20 (the cap), 21; asleep and on watch it engages; Alerted
    // stays; asleep at 0 health stays asleep, gains nothing; dead, nothing; Returning gains.
    for adrenaline in array![0_u8, 19, 20, 21] {
        rows.append((g_with(content, ai::ENGAGED, 100, adrenaline), Op::Struck));
    }
    rows.append((g_with(content, ai::ASLEEP, 100, 0), Op::Struck));
    rows.append((g_with(content, ai::WATCH, 100, 0), Op::Struck));
    rows.append((g_with(content, ai::ALERTED, 100, 0), Op::Struck));
    rows.append((g_with(content, ai::ASLEEP, 0, 0), Op::Struck));
    rows.append((g_with(content, ai::DEAD, 50, 0), Op::Struck));
    rows.append((g_with(content, ai::RETURNING, 100, 0), Op::Struck));
    // `landed`, a member: 4 quarters, 8 on the N-th hit of `ADRENALINE_EVERY_N` (`MemberKit`
    // 160–167; the `hits` counter at `MemberState` 112–119): N 0 (the counter stays 0); N 3
    // from 0, 1, 2 (the third: 8, the counter back to 0); N 1; capped at 20 from 17 (+4) and from
    // 13 on the N-th (+8); at the cap; at 0 health (no alive check).
    rows.append((m_with(content, 400, 0, 0), Op::Landed));
    for hits in array![0_u8, 1, 2] {
        let mut m = member(content);
        m.words.kit += 3 * two(160);
        m.set_hits(hits);
        rows.append((Unit::M(m), Op::Landed));
    }
    let mut every = member(content);
    every.words.kit += two(160);
    rows.append((Unit::M(every), Op::Landed));
    rows.append((m_with(content, 400, 17, 0), Op::Landed));
    let mut third = member(content);
    third.words.kit += 3 * two(160);
    third.set_hits(2);
    third.adrenaline = 13;
    rows.append((Unit::M(synced(third)), Op::Landed));
    rows.append((m_with(content, 400, 20, 0), Op::Landed));
    rows.append((m_with(content, 0, 0, 0), Op::Landed));
    // A goblin: 4 quarters, capped at 20: from 0, 15, 16, 17, 20, 21 (above, kept).
    for adrenaline in array![0_u8, 15, 16, 17, 20, 21] {
        rows.append((g_with(content, ai::ENGAGED, 100, adrenaline), Op::Landed));
    }
    // `halved`: a member's `HALVED` flag, already set; a goblin, nothing.
    rows.append((m_with(content, 400, 0, flag::HIT), Op::Halved));
    rows.append((m_with(content, 400, 0, flag::HALVED), Op::Halved));
    rows.append((Unit::G(goblin(content)), Op::Halved));
    rows
}

/// Sets condition `c`'s deadline (Crippled's in the words).
fn m_condition(m: Member, c: u8, deadline: u32) -> Member {
    let mut m = m;
    MemberLifecycleTrait::set_condition(ref m, c, deadline);
    synced(m)
}

fn g_condition(g: Goblin, c: u8, deadline: u32) -> Goblin {
    let mut g = g;
    crate::models::goblin::GoblinLifecycleTrait::set_condition(ref g, c, deadline);
    gsynced(g)
}

/// `inflict` at `T`: `D = T + d − 1` refreshed by `max`, `d` the value clamped to 1…32,767 and
/// the source's bonuses (`InflictionTrait::duration`); Knocked down interrupts.
fn inflicts(content: @Content) -> Array<(Unit, Op)> {
    let none: Infliction = Default::default();
    let m = member(content);
    let g = goblin(content);
    let mut rows = array![];
    // Each condition on each kind, the value 3, none held: `D = 52`.
    for c in 1..6_u8 {
        rows.append((Unit::M(m), Op::Inflict((c, 3, none, T))));
        rows.append((Unit::G(g), Op::Inflict((c, 3, none, T))));
    }
    // The value's clamp on Bleeding: 0, −1, 1, 2, 32,767, 32,768; refreshed over a later deadline
    // (53, kept) and an earlier one (51, replaced by 52).
    for v in array![0_i32, -1, 1, 2, 32767, 32768] {
        rows.append((Unit::M(m), Op::Inflict((condition::BLEEDING, v, none, T))));
        rows.append((Unit::G(g), Op::Inflict((condition::BLEEDING, v, none, T))));
    }
    for old in array![53_u32, 51] {
        let c = condition::BLEEDING;
        rows.append((Unit::M(m_condition(m, c, old)), Op::Inflict((c, 3, none, T))));
        rows.append((Unit::G(g_condition(g, c, old)), Op::Inflict((c, 3, none, T))));
        // Crippled is written in the timers word.
        let c = condition::CRIPPLED;
        rows.append((Unit::M(m_condition(m, c, old)), Op::Inflict((c, 3, none, T))));
        rows.append((Unit::G(g_condition(g, c, old)), Op::Inflict((c, 3, none, T))));
    }
    // Knocked down (value 2: `D = 51`) interrupts an activation: the member's bar slot 1
    // (recharge 12, so `R = T + 11`), the goblin's caste slot 2 (recharge 8), with none held and
    // over a later one (60: kept, interrupted all the same); over an earlier one (50), no
    // activation; a goblin recovering keeps its recovery.
    let mut acting = member(content);
    acting.act_slot = 1;
    acting.act_target = 264;
    acting.act_deadline = 55;
    let acting = synced(acting);
    let mut gacting = goblin(content);
    gacting.act_slot = 2;
    gacting.act_target = 0;
    gacting.act_deadline = 55;
    let gacting = gsynced(gacting);
    let kd = condition::KNOCKED_DOWN;
    rows.append((Unit::M(acting), Op::Inflict((kd, 2, none, T))));
    rows.append((Unit::G(gacting), Op::Inflict((kd, 2, none, T))));
    rows.append((Unit::M(m_condition(acting, kd, 60)), Op::Inflict((kd, 2, none, T))));
    rows.append((Unit::G(g_condition(gacting, kd, 60)), Op::Inflict((kd, 2, none, T))));
    rows.append((Unit::M(m_condition(m, kd, 50)), Op::Inflict((kd, 2, none, T))));
    rows.append((Unit::G(g_condition(g, kd, 50)), Op::Inflict((kd, 2, none, T))));
    let mut recovering = goblin(content);
    recovering.act_slot = activation::RECOVERING;
    recovering.act_deadline = 55;
    rows.append((Unit::G(gsynced(recovering)), Op::Inflict((kd, 2, none, T))));
    // The source: `CONDITION_DURATION` Bleeding at 33 % (10 → 13), on Poison (10); at 49, 50
    // and 63 (capped at 50: 15); `KNOCKDOWN_FLAT` 3 on Knocked down (2 → 5), on Crippled (2), 4
    // (capped at 3); on a goblin, Bleeding at 33 %.
    let b = condition::BLEEDING;
    let sources = array![
        (b, Infliction { condition: b, percent: 33, knockdown: 0 }, 10_i32),
        (condition::POISON, Infliction { condition: b, percent: 33, knockdown: 0 }, 10),
        (b, Infliction { condition: b, percent: 49, knockdown: 0 }, 10),
        (b, Infliction { condition: b, percent: 50, knockdown: 0 }, 10),
        (b, Infliction { condition: b, percent: 63, knockdown: 0 }, 10),
        (kd, Infliction { condition: 0, percent: 0, knockdown: 3 }, 2),
        (condition::CRIPPLED, Infliction { condition: 0, percent: 0, knockdown: 3 }, 2),
        (kd, Infliction { condition: 0, percent: 0, knockdown: 4 }, 2),
    ];
    for (c, source, v) in sources {
        rows.append((Unit::M(m), Op::Inflict((c, v, source, T))));
    }
    let rending = Infliction { condition: b, percent: 33, knockdown: 0 };
    rows.append((Unit::G(g), Op::Inflict((b, 10, rending, T))));
    // Not alive: nothing, through `apply` and through `knock`.
    let mut dead = member(content);
    dead.health = 0;
    let dead = Unit::M(synced(dead));
    let mut gdead = goblin(content);
    gdead.ai = ai::DEAD;
    let gdead = Unit::G(gsynced(gdead));
    rows.append((dead, Op::Inflict((b, 3, none, T))));
    rows.append((dead, Op::Inflict((kd, 2, none, T))));
    rows.append((gdead, Op::Inflict((b, 3, none, T))));
    rows.append((gdead, Op::Inflict((kd, 2, none, T))));
    rows
}

/// `cure` at `T`: a condition held at `T` (`D ≥ T`) ends at `T − 1`.
fn cures(content: @Content) -> Array<(Unit, Op)> {
    let m = member(content);
    let g = goblin(content);
    let mut rows = array![];
    for c in 1..6_u8 {
        rows.append((Unit::M(m_condition(m, c, 60)), Op::Cure((c, T))));
        rows.append((Unit::G(g_condition(g, c, 60)), Op::Cure((c, T))));
    }
    // Bleeding to 50 (held at `T`: 49), 48 (not held: kept), 0.
    let b = condition::BLEEDING;
    for old in array![50_u32, 48, 0] {
        rows.append((Unit::M(m_condition(m, b, old)), Op::Cure((b, T))));
        rows.append((Unit::G(g_condition(g, b, old)), Op::Cure((b, T))));
    }
    // Not alive: a member at 0, one down, a dead goblin: nothing.
    let mut dead = m_condition(m, b, 60);
    dead.health = 0;
    rows.append((Unit::M(synced(dead)), Op::Cure((b, T))));
    let mut down = m_condition(m, b, 60);
    down.status = status::DOWN;
    rows.append((Unit::M(synced(down)), Op::Cure((b, T))));
    let mut gdead = g_condition(g, b, 60);
    gdead.ai = ai::DEAD;
    rows.append((Unit::G(gsynced(gdead)), Op::Cure((b, T))));
    rows
}

/// `hold` at `T` (§5.7: the same carrier, a stance's slot, the lowest free slot, the earliest
/// deadline), `spend`.
fn holds(content: @Content, sheets: @Sheets) -> Array<(Unit, Op)> {
    let m = member(content);
    let g = goblin(content);
    let five = at(sheets, 5);
    let six = at(sheets, 6);
    let three = at(sheets, 3);
    let mut rows = array![];
    // A member, skill 5 to 60 at rank 12: into slot 0 when none is held.
    rows.append((Unit::M(m), hold(held(5, false, 0, 60, 12), five, false)));
    // Skill 5 held in slot 0 to 60: again to 70 (replaced), 55 (kept), 60 at rank 0 (a tie:
    // replaced).
    let fived = m_holding(m, 0, held(5, false, 0, 60, 12), sheets);
    rows.append((Unit::M(fived), hold(held(5, false, 0, 70, 12), five, false)));
    rows.append((Unit::M(fived), hold(held(5, false, 0, 55, 12), five, false)));
    rows.append((Unit::M(fived), hold(held(5, false, 0, 60, 0), five, false)));
    // Held to 49, before `T`: not the same carrier held, slot 0 is free; to 50 (`T`): held,
    // skill 6 takes slot 1; to 49, skill 6 takes slot 0.
    let lapsed = m_holding(m, 0, held(5, false, 0, 49, 12), sheets);
    rows.append((Unit::M(lapsed), hold(held(5, false, 0, 55, 12), five, false)));
    let held_t = m_holding(m, 0, held(5, false, 0, T, 12), sheets);
    rows.append((Unit::M(held_t), hold(held(6, false, 0, 55, 0), six, false)));
    rows.append((Unit::M(lapsed), hold(held(6, false, 0, 55, 0), six, false)));
    // Spell 6 in slot 0, stance 4 in slot 1, both to 60: stance 3 takes slot 1; not as a
    // stance, slot 2. Both to 49: the stance lapsed, slot 0 (the lowest free).
    let mut stanced = m_holding(m, 0, held(6, false, 0, 60, 0), sheets);
    stanced = m_holding(stanced, 1, held(4, false, 0, 60, 0), sheets);
    rows.append((Unit::M(stanced), hold(held(3, false, 0, 58, 12), three, true)));
    rows.append((Unit::M(stanced), hold(held(3, false, 0, 58, 12), three, false)));
    let mut stale = m_holding(m, 0, held(6, false, 0, 49, 0), sheets);
    stale = m_holding(stale, 1, held(4, false, 0, 49, 0), sheets);
    rows.append((Unit::M(stale), hold(held(3, false, 0, 58, 15), three, true)));
    // Every slot held, to 70, 55, 60, 55: the earliest, the lowest of the tie, slot 1.
    let mut full = m_holding(m, 0, held(6, false, 0, 70, 0), sheets);
    full = m_holding(full, 1, held(4, false, 0, 55, 0), sheets);
    full = m_holding(full, 2, held(3, false, 0, 60, 0), sheets);
    full = m_holding(full, 3, held(7, false, 0, 55, 0), sheets);
    rows.append((Unit::M(full), hold(held(5, false, 0, 58, 12), five, false)));
    // A potion: belt slot 1 (item 101) held in slot 2 to 55, again to 60: the same item,
    // slot 2. Skill 1 held in slot 0 is not potion 1: slot 1.
    let mut potion = m_holding(m, 0, held(6, false, 0, 60, 0), sheets);
    potion = m_holding(potion, 1, held(4, false, 0, 60, 0), sheets);
    potion = m_holding(potion, 2, held(1, true, 0, 55, 0), sheets);
    rows.append((Unit::M(potion), hold(held(1, true, 0, 60, 0), 1, false)));
    let skill_one = m_holding(m, 0, held(1, false, 0, 60, 0), sheets);
    rows.append((Unit::M(skill_one), hold(held(1, true, 0, 60, 0), 1, false)));
    // Not alive: nothing.
    let mut dead = m;
    dead.health = 0;
    rows.append((Unit::M(synced(dead)), hold(held(5, false, 0, 60, 12), five, false)));
    // A goblin's one slot: empty, skill 5 to 60; held to 60, again to 55 (kept), 60 at rank
    // 0 (replaced); held to 50 (`T`), again to 49 (kept); to 49, again to 40 (lapsed:
    // replaced); skill 6 over it (replaced); a potion (never held); dead, nothing.
    rows.append((Unit::G(g), hold(held(5, false, 0, 60, 12), five, false)));
    let gfive = g_holding(g, held(5, false, 0, 60, 12), sheets);
    rows.append((Unit::G(gfive), hold(held(5, false, 0, 55, 12), five, false)));
    rows.append((Unit::G(gfive), hold(held(5, false, 0, 60, 0), five, false)));
    let gheld_t = g_holding(g, held(5, false, 0, T, 12), sheets);
    rows.append((Unit::G(gheld_t), hold(held(5, false, 0, 49, 12), five, false)));
    let glapsed = g_holding(g, held(5, false, 0, 49, 12), sheets);
    rows.append((Unit::G(glapsed), hold(held(5, false, 0, 40, 12), five, false)));
    rows.append((Unit::G(gfive), hold(held(6, false, 0, 40, 0), six, false)));
    rows.append((Unit::G(g), hold(held(1, true, 0, 60, 0), 1, false)));
    let mut gdead = g;
    gdead.ai = ai::DEAD;
    rows.append((Unit::G(gsynced(gdead)), hold(held(5, false, 0, 60, 12), five, false)));
    // `spend` at `T`: 2 charges to 1; 1 to 0, the effect ending at `T − 1`; 0, nothing. A
    // member's slot 0 and slot 3 (the other slots' pips kept), a goblin's.
    for charges in array![2_u8, 1, 0] {
        let spent = m_holding(m, 0, held(5, false, charges, MAX_CLOCK, 12), sheets);
        rows.append((Unit::M(spent), Op::Spend((0, T))));
        let gspent = g_holding(g, held(5, false, charges, MAX_CLOCK, 12), sheets);
        rows.append((Unit::G(gspent), Op::Spend((0, T))));
    }
    let mut last = m_holding(m, 0, held(3, false, 0, 60, 12), sheets);
    last = m_holding(last, 3, held(5, false, 1, MAX_CLOCK, 0), sheets);
    rows.append((Unit::M(last), Op::Spend((3, T))));
    rows
}

/// Appended by RV-03a's fix loop 1 (the review of #440), after every earlier id: `armor_vs` on
/// every type's lane, and `hold`'s potion paths.
fn appended(content: @Content, sheets: @Sheets) -> Array<(Unit, Op)> {
    let mut rows = array![];
    // `armor_vs`, a member: its per-type armors 5 to 12 and 63 (types 1 to 9: `MemberStats` 48,
    // 54, then 200 + 6 (t − 3)), at types 4 to 8.
    let mut armored = member(content);
    armored.words.stats += 5 * two(48)
        + 6 * two(54)
        + 7 * two(200)
        + 8 * two(206)
        + 9 * two(212)
        + 10 * two(218)
        + 11 * two(224)
        + 12 * two(230)
        + 63 * two(236);
    for damage_type in 4..9_u8 {
        rows.append((Unit::M(armored), Op::ArmorVs(damage_type)));
    }
    // A goblin of caste Runt (`ARMOR_VS` 11 to 19 against types 1 to 9), at types 2 to 8.
    let g = Fixture::goblin(265, RUNT);
    let words = GoblinWords { entity: 265, awake: true, state: g.state, timers: g.timers };
    let runt = Unit::G(Fixture::load_goblin(words, content));
    for damage_type in 2..9_u8 {
        rows.append((runt, Op::ArmorVs(damage_type)));
    }
    // `hold`, a potion beside another: belt potion 1 (item 101) held in slot 0, belt potion 2
    // (item 102) is not the same item, slot 1.
    let m = member(content);
    let potion = m_holding(m, 0, held(1, true, 0, 60, 0), sheets);
    rows.append((Unit::M(potion), hold(held(2, true, 0, 60, 0), 2, false)));
    // Step 2's `!old.potion`, both sides: belt potion 3 (its sheet at position 3, where skill 4,
    // a stance, sits) held in slot 0, stance 3 is not put there, slot 1; stance 4 held in slot
    // 0, stance 3 takes it.
    let three = at(sheets, 3);
    let potion = m_holding(m, 0, held(3, true, 0, 60, 0), sheets);
    rows.append((Unit::M(potion), hold(held(3, false, 0, 58, 12), three, true)));
    let stance = m_holding(m, 0, held(4, false, 0, 60, 0), sheets);
    rows.append((Unit::M(stance), hold(held(3, false, 0, 58, 12), three, true)));
    rows
}

/// RV-03a2 (D-257): track CV's surviving mutants of the body port (#443), after every earlier id.
fn surviving(content: @Content, sheets: @Sheets) -> Array<(Unit, Op)> {
    let mut rows = array![];
    let m = member(content);
    let five = at(sheets, 5);
    // `hold`'s step 1 at its bound: skill 5 held in slot 0 to `T` (held: `old.deadline ≥ t`),
    // held again to 60: the same carrier, slot 0 (`>` would put it in slot 1, the lowest free).
    let held_t = m_holding(m, 0, held(5, false, 0, T, 12), sheets);
    rows.append((Unit::M(held_t), hold(held(5, false, 0, 60, 12), five, false)));
    // Step 1's potion compared by its item, not its belt slot: belt slots 1 and 2 both hold item
    // 101 (`MemberKit` 64–95 made 101), belt potion 1 held in slot 0 to 60; belt potion 2 (the
    // sheet of item 101, position 1) is the same item: slot 0.
    let mut words = Fixture::member_words(Fixture::spec());
    words.kit -= two(64);
    let twice = Fixture::load_member(words, content);
    let potion = m_holding(twice, 0, held(1, true, 0, 60, 0), sheets);
    rows.append((Unit::M(potion), hold(held(2, true, 0, 60, 0), 1, false)));
    // Knocked down (value 2) interrupting the member's activation of bar slots 4 to 7 (spells of
    // recharge 10: `R = T + 9`), their lanes in the recharges word's high limb; every lane holding
    // a recharge `40 + slot` before, so that only the slot's lane moves.
    let none: Infliction = Default::default();
    let kd = condition::KNOCKED_DOWN;
    for slot in 4..8_u8 {
        let mut acting = member(content);
        for lane in 0..8_u8 {
            acting.set_recharge(lane, 40 + lane.into());
        }
        acting.act_slot = slot;
        acting.act_target = 264;
        acting.act_deadline = 55;
        rows.append((Unit::M(synced(acting)), Op::Inflict((kd, 2, none, T))));
    }
    // A goblin activating caste slot 3 (`LAST_SLOT`: activating; Hob's shout, recharge 20),
    // knocked down: interrupted, its slot 3 recharging to `T + 19`.
    let mut last = goblin(content);
    last.act_slot = activation::LAST_SLOT;
    last.act_target = 0;
    last.act_deadline = 55;
    rows.append((Unit::G(gsynced(last)), Op::Inflict((kd, 2, none, T))));
    rows
}

fn hold(h: Held, at: u32, stance: bool) -> Op {
    Op::Hold((h, at, stance, T))
}

fn run(ref digest: Array<felt252>, ref id: u32, sheets: @Sheets, rows: Array<(Unit, Op)>) {
    for (unit, op) in rows {
        row(ref digest, ref id, sheets, unit, op);
    }
}

// ---- The effect entry's operations (`types/effect.cairo`).

fn entry_felts(entry: @Entry) -> Array<felt252> {
    let mut out = array![];
    Serde::serialize(entry, ref out);
    out
}

/// `line` (and `value`, the same line on an entry's `v0`, `v12`), `duration`, `class` (with
/// `is_holding` and `is_hit_modifier`), `pack` and `unpack`.
fn entries(ref digest: Array<felt252>, ref id: u32) {
    // `line`: `v0 + (v12 − v0) × rank / 12`, truncated toward zero, at ranks 0, 1, 11, 12, 13
    // and 15 (`MAX_RANK`), rising, falling, around 0 both ways, and at the `i16` extremes.
    let lines = array![
        (10_i16, 40_i16), (40, 10), (0, 7), (0, -7), (-32768, 32767), (32767, -32768),
    ];
    for (v0, v12) in lines {
        for rank in array![0_u8, 1, 11, 12, 13, 15] {
            let case = array![v0.into(), v12.into(), rank.into()];
            let ok = array![EntryTrait::line(v0, v12, rank).into()];
            emit(ref digest, ref id, "line", case.span(), ok.span());
        }
    }
    // `value`: an entry's line at its rank.
    let snare = EntryTrait::new(kind::DAMAGE, 7, 10, 40, 0, 0, 0, 1, 1, 0, 0, 0);
    let falling = EntryTrait::new(kind::ENERGY, 0, -5, -17, 0, 0, 0, 0, 1, 1, 0, 0);
    for (entry, rank) in array![(snare, 7_u8), (falling, 7), (falling, 15)] {
        let mut case = entry_felts(@entry);
        case.append(rank.into());
        let ok = array![entry.value(rank).into()];
        emit(ref digest, ref id, "value", case.span(), ok.span());
    }
    // `duration`: the same line on `d0`, `d12` (unsigned, the result signed) at ranks 0, 1, 12
    // and 15.
    let durations = array![(5_u16, 17_u16), (17, 5), (0, 43688), (43688, 0)];
    for (d0, d12) in durations {
        let entry = EntryTrait::new(kind::ARMOR, 0, 10, 10, d0, d12, 0, 0, 1, 1, 0, 0);
        for rank in array![0_u8, 1, 12, 15] {
            let mut case = entry_felts(@entry);
            case.append(rank.into());
            let ok = array![entry.duration(rank).into()];
            emit(ref digest, ref id, "duration", case.span(), ok.span());
        }
    }
    // `class`: every kind 0–24 and 255; `ok` the `Option<KindClass>` (`[1]` none, `[0, c]`: 0
    // `Hit`, 1 `HitModifier`, 2 `Holding`, 3 `Instant`, 4 `Placement`), `is_holding`,
    // `is_hit_modifier`.
    let mut kinds: Array<u8> = array![];
    for k in 0..25_u8 {
        kinds.append(k);
    }
    kinds.append(255);
    for k in kinds {
        let entry = Entry { kind: k, ..Default::default() };
        let mut ok = array![];
        Serde::serialize(@entry.class(), ref ok);
        ok.append(flag_felt(entry.is_holding()));
        ok.append(flag_felt(entry.is_hit_modifier()));
        emit(ref digest, ref id, "class", array![k.into()].span(), ok.span());
    }
    // `pack` and `unpack`: the empty entry, the snare's damage, a negative value, every field at
    // its layout's maximum (the durations at `MAX_BASE_DURATION`), the top field alone.
    let widest = EntryTrait::new(255, 255, -32768, 32767, 43688, 43688, 63, 3, 7, 1, 7, 3);
    let top = Entry { scope: 3, ..Default::default() };
    let packed = array![Default::default(), snare, falling, widest, top];
    for entry in packed {
        let bits = entry.pack();
        emit(ref digest, ref id, "pack", entry_felts(@entry).span(), array![bits.into()].span());
        emit(
            ref digest,
            ref id,
            "unpack",
            array![bits.into()].span(),
            entry_felts(@EntryTrait::unpack(bits)).span(),
        );
    }
}

// ---- The parts (a table too long for snforge's step limit is printed in parts, `check.py`).

#[test]
#[available_gas(l2_gas: 468137187)] // ceil(1.05 × 445844940 measured)
fn test_body_vectors_0() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = 0;
    let mut ok: Array<felt252> = array![];
    Serde::serialize(@content, ref ok);
    emit(ref digest, ref id, "content", array![].span(), ok.span());
    run(ref digest, ref id, @sheets, reads(@content, @sheets));
    finish(digest, BODY_DIGEST_0);
}

#[test]
#[available_gas(l2_gas: 1134695389)] // ceil(1.05 × 1080662275 measured)
fn test_body_vectors_1() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_1;
    run(ref digest, ref id, @sheets, health(@content));
    run(ref digest, ref id, @sheets, hits(@content));
    finish(digest, BODY_DIGEST_1);
}

#[test]
#[available_gas(l2_gas: 756618118)] // ceil(1.05 × 720588683 measured)
fn test_body_vectors_2() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_2;
    run(ref digest, ref id, @sheets, inflicts(@content));
    finish(digest, BODY_DIGEST_2);
}

#[test]
#[available_gas(l2_gas: 765947697)] // ceil(1.05 × 729473997 measured)
fn test_body_vectors_3() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_3;
    run(ref digest, ref id, @sheets, cures(@content));
    run(ref digest, ref id, @sheets, holds(@content, @sheets));
    finish(digest, BODY_DIGEST_3);
}

#[test]
#[available_gas(l2_gas: 106473117)] // ceil(1.05 × 101402968 measured)
fn test_body_vectors_4() {
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_4;
    entries(ref digest, ref id);
    finish(digest, BODY_DIGEST_4);
}

// Appended by the fix loop: ids after every earlier part's.
#[test]
#[available_gas(l2_gas: 156243847)] // ceil(1.05 × 148803663 measured)
fn test_body_vectors_5() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_5;
    run(ref digest, ref id, @sheets, appended(@content, @sheets));
    finish(digest, BODY_DIGEST_5);
}

// Appended by RV-03a2 (D-257): track CV's surviving mutants (#443), after every earlier id.
#[test]
#[available_gas(l2_gas: 167799202)] // ceil(1.05 × 159808763 measured)
fn test_body_vectors_6() {
    let content = body_content();
    let sheets = content.sheets();
    let mut digest: Array<felt252> = array![];
    let mut id: u32 = BODY_PART_6;
    run(ref digest, ref id, @sheets, surviving(@content, @sheets));
    finish(digest, BODY_DIGEST_6);
}

/// The first id of each part, and each part's digest.
const BODY_PART_1: u32 = 52;
const BODY_PART_2: u32 = 123;
const BODY_PART_3: u32 = 173;
const BODY_PART_4: u32 = 221;
const BODY_PART_5: u32 = 312;
const BODY_PART_6: u32 = 327;
const BODY_DIGEST_0: felt252 =
    1598459221565441623804350022951177107043960060755901037354943566470590002612;
const BODY_DIGEST_1: felt252 =
    822755559781721334376966019348273462998371782871208343343980908972303218630;
const BODY_DIGEST_2: felt252 =
    450519756701183914306781957105965862106680085611770177740111989402173178090;
const BODY_DIGEST_3: felt252 =
    204783480972355102103941296066621439799057620292245381899642073046951479842;
const BODY_DIGEST_4: felt252 =
    3116694715749133080887387106960700414459042789108760740297312786033004326793;
const BODY_DIGEST_5: felt252 =
    180299553724079398759478913516279442118061555934969195638265543515182710644;
const BODY_DIGEST_6: felt252 =
    2429298052524284503116930073981651924323587693382478258366592473340700994381;
