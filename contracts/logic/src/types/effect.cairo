//! The effect entry and its enumerations (design/19 §2, §3; frozen by CBT-01, X-1, X-2). Every
//! carrier that acts (a skill, a potion, a trap) writes its effects as entries of 97 bits, one per
//! limb of a registry record: `SKILL` holds three, `ITEM` one.
//!
//! Layout of an entry, in the order of design/19 §2.1's table (bits of its limb):
//! kind 0–7 · param 8–15 · `v0` 16–31 · `v12` 32–47 (signed, two's complement) · `d0`
//! 48–63 ·
//! `d12` 64–79 · charges 80–85 · target 86–87 · shape 88–90 · filter 91 · guard
//! 92–94 ·
//! scope 95–96. 97 bits: an entry fits a high limb (122 bits) as well as a low one (128).

use crate::helpers::duration::MAX_BASE_DURATION;
use crate::helpers::packing::{P16, P32, P48, P64, P8, P80};
use crate::helpers::signed::SignedTrait;
use super::combat::{condition, damage};

/// Effect kinds that act, ids 1–23 (design/19 §3). 0 is the empty entry. 19–23 have no MVP
/// source and no rule yet (§3.6): catalogued for closure.
pub mod kind {
    pub const EMPTY: u8 = 0;
    pub const DAMAGE: u8 = 1;
    pub const ATTACK_BONUS: u8 = 2;
    pub const HEAL: u8 = 3;
    pub const LIFE_STEAL: u8 = 4;
    pub const REGENERATION: u8 = 5;
    pub const CONDITION: u8 = 6;
    pub const CURE: u8 = 7;
    pub const ENERGY: u8 = 8;
    pub const NEXT_SPELL_COST: u8 = 9;
    pub const ARMOR: u8 = 10;
    pub const PENETRATION: u8 = 11;
    pub const HIT_PENETRATION: u8 = 12;
    pub const BLOCK: u8 = 13;
    pub const EVADE: u8 = 14;
    pub const ON_ATTACK_CONDITION: u8 = 15;
    pub const MOVEMENT: u8 = 16;
    pub const INTERRUPT: u8 = 17;
    pub const TRAP: u8 = 18;
    pub const REVIVE: u8 = 19;
    pub const REVEAL_FLOOR: u8 = 20;
    pub const ON_SKILL_USE: u8 = 21;
    pub const SUMMON: u8 = 22;
    pub const CAPTURE: u8 = 23;
    /// The last kind of the MVP: kinds above have no rule (§3.6).
    pub const LAST_MVP: u8 = 18;
    pub const LAST: u8 = 23;
}

/// A kind's role for the executor (design/19 §3, §5.14).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum KindClass {
    /// A damaging entry (`DAMAGE`).
    Hit,
    /// Modifies the carrier's hit (`ATTACK_BONUS`, `HIT_PENETRATION`).
    HitModifier,
    /// Stays in an effect slot (5, 9–11, 13–16).
    Holding,
    /// Applies now (3, 4, 6–8, 17).
    Instant,
    /// Places a trap (`TRAP`).
    Placement,
}

/// The addressing: where the shape is centred (§2.3). An ally is an entity id (M-5).
pub mod target {
    pub const SELF: u8 = 0;
    pub const FOE: u8 = 1;
    pub const ALLY: u8 = 2;
    pub const TILE: u8 = 3;
}

/// Shapes, ids 1–5 (§2.3); 0 is refused but in an empty entry.
pub mod shape {
    pub const SINGLE: u8 = 1;
    /// The 6 tiles around the centre.
    pub const RING_1: u8 = 2;
    /// The centre and its 6 neighbours: potions only (FX-35).
    pub const DISC_1: u8 = 3;
    /// Within 2 (19 tiles), within 3 (37): no MVP content until measured (FX-21).
    pub const DISC_2: u8 = 4;
    pub const DISC_3: u8 = 5;
    pub const LAST: u8 = 5;
}

/// Which actors of the shape's tiles the entry takes (§2.3).
pub mod filter {
    pub const FOES: u8 = 0;
    pub const ALLIES: u8 = 1;
}

/// Guards, ids 0–4 (§2.4): the entry applies only when its guard holds, read once per carrier's
/// execution (FX-40).
pub mod guard {
    pub const ALWAYS: u8 = 0;
    /// The subject's health × 2 > its max health.
    pub const ABOVE_HALF: u8 = 1;
    /// The subject's health × 2 < its max health.
    pub const BELOW_HALF: u8 = 2;
    pub const IN_STANCE: u8 = 3;
    pub const ENCHANTED: u8 = 4;
    pub const LAST: u8 = 4;
}

/// Scopes of a kind that modifies hits (§2.1, §5.4); `WEAPON` by default (FX-27).
pub mod scope {
    pub const WEAPON: u8 = 0;
    pub const ATTACK_SKILL: u8 = 1;
    pub const SPELL: u8 = 2;
    pub const ALL: u8 = 3;
}

/// `EVADE`'s `param` (§3.4): the hits it evades.
pub const EVADE_MELEE: u8 = 1;
/// The highest rank a value scales to (FX-0b: the line is extrapolated from 12 to 15).
pub const MAX_RANK: u8 = 15;
/// A duration carried as a value is 1…32,767 ticks (§2.1).
pub const MAX_VALUE_DURATION: i32 = 32767;

pub mod errors {
    pub const CHARGES: felt252 = 'entry: charges';
    pub const TARGET: felt252 = 'entry: target';
    pub const SHAPE: felt252 = 'entry: shape';
    pub const FILTER: felt252 = 'entry: filter';
    pub const GUARD: felt252 = 'entry: guard';
    pub const SCOPE: felt252 = 'entry: scope';
    pub const DURATION: felt252 = 'entry: duration';
    pub const RANK: felt252 = 'entry: rank';
    // The content pipeline's checks (`assert_legal`, §2.1, §3's "reads").
    pub const KIND: felt252 = 'entry: kind';
    pub const NOT_MVP: felt252 = 'entry: kind after the MVP';
    pub const EMPTY: felt252 = 'entry: empty with a field';
    pub const READS: felt252 = 'entry: field not read';
    pub const PARAM: felt252 = 'entry: param';
    pub const CONDITION_NOT_MVP: felt252 = 'entry: condition after the MVP';
    pub const KIND_DEFERRED: felt252 = 'entry: kind deferred';
    pub const GUARD_DEFERRED: felt252 = 'entry: guard deferred';
    pub const VALUE: felt252 = 'entry: value out of bounds';
    pub const NO_TIME: felt252 = 'entry: neither d nor charges';
    pub const NOT_SCALED: felt252 = 'entry: scales';
    // The legal carriers (§5.14).
    pub const GAP: felt252 = 'carrier: gap';
    pub const TWO_HITS: felt252 = 'carrier: two hits';
    pub const HIT_NOT_FIRST: felt252 = 'carrier: damage not first';
    pub const TWO_HOLDING: felt252 = 'carrier: two holding entries';
    pub const TWO_ATTACK_BONUSES: felt252 = 'carrier: two attack bonuses';
    pub const MODIFIER_NO_HIT: felt252 = 'carrier: modifier without hit';
    pub const MODIFIER_SET: felt252 = 'carrier: modifier set';
    pub const ATTACK_BONUS: felt252 = 'carrier: attack bonus';
    pub const ATTACK_ENTRY: felt252 = 'carrier: attack entry';
    pub const TRAP_ENTRY: felt252 = 'carrier: trap entry';
    pub const PAYLOAD: felt252 = 'carrier: trap payload';
    pub const MIXED_TARGETS: felt252 = 'carrier: mixed targets';
    pub const TAKES_NOBODY: felt252 = 'carrier: takes nobody';
    pub const DISC_1: felt252 = 'carrier: disc 1 not a potion';
    pub const AREA: felt252 = 'carrier: area after the MVP';
}

/// What a carrier is, for its legal combinations (§5.14).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Carrier {
    /// An attack skill: an implicit weapon hit, entries all `FOE`, `SINGLE`.
    Attack,
    /// Any other skill.
    Skill,
    /// A potion: one entry, `DISC_1` allowed (FX-35), no scaling.
    Potion,
}

/// One effect of a carrier (design/19 §2.1).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Entry {
    /// `kind::EMPTY`, or an id of §3.
    pub kind: u8,
    /// By kind: the condition, damage type… (§3's "reads").
    pub param: u8,
    /// The value at rank 0 and at rank 12 (§2.2), signed.
    pub v0: i16,
    pub v12: i16,
    /// The holding duration at rank 0 and 12, 0…`MAX_BASE_DURATION`; 0: it does not stay.
    pub d0: u16,
    pub d12: u16,
    /// Uses before the effect ends (an oil), 0…63; 0: none.
    pub charges: u8,
    /// `target::SELF` … `TILE`.
    pub target: u8,
    /// `shape::SINGLE` … `DISC_3`.
    pub shape: u8,
    /// `filter::FOES` or `ALLIES`.
    pub filter: u8,
    /// `guard::ALWAYS` … `ENCHANTED`.
    pub guard: u8,
    /// `scope::WEAPON` … `ALL`.
    pub scope: u8,
}

// Offsets of the entry's fields above 80 bits (a table, docs/CAIRO.md §3).
const P86: u128 = 0x4000000000000000000000;
const P88: u128 = 0x10000000000000000000000;
const P91: u128 = 0x80000000000000000000000;
const P92: u128 = 0x100000000000000000000000;
const P95: u128 = 0x800000000000000000000000;
/// An entry is below 2^97.
pub const ENTRY_BOUND: u128 = 0x2000000000000000000000000;

// The fields of §3's "reads" column, one bit each.
const READS_PARAM: u8 = 1;
const READS_V: u8 = 2;
const READS_D: u8 = 4;
const READS_CHARGES: u8 = 8;
const READS_SCOPE: u8 = 16;

#[generate_trait]
pub impl EntryImpl of EntryTrait {
    fn new(
        kind: u8,
        param: u8,
        v0: i16,
        v12: i16,
        d0: u16,
        d12: u16,
        charges: u8,
        target: u8,
        shape: u8,
        filter: u8,
        guard: u8,
        scope: u8,
    ) -> Entry {
        Entry { kind, param, v0, v12, d0, d12, charges, target, shape, filter, guard, scope }
    }

    /// Whether it is the empty entry (kind 0).
    #[inline(always)]
    fn is_empty(self: @Entry) -> bool {
        *self.kind == kind::EMPTY
    }

    /// The entry's 97 bits; refuses a field wider than its layout, and a duration above
    /// `MAX_BASE_DURATION` (the registry's writer refuses more, ENG-01 §3.1).
    fn pack(self: @Entry) -> u128 {
        self.assert_valid();
        (*self.kind).into()
            + (*self.param).into() * P8
            + SignedTrait::bits16(*self.v0) * P16
            + SignedTrait::bits16(*self.v12) * P32
            + (*self.d0).into() * P48
            + (*self.d12).into() * P64
            + (*self.charges).into() * P80
            + (*self.target).into() * P86
            + (*self.shape).into() * P88
            + (*self.filter).into() * P91
            + (*self.guard).into() * P92
            + (*self.scope).into() * P95
    }

    /// The entry of 97 bits (`bits` below 2^97, as a limb of a record holds it).
    fn unpack(bits: u128) -> Entry {
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (bits, kind) = DivRem::div_rem(bits, s8);
        let (bits, param) = DivRem::div_rem(bits, s8);
        let (bits, v0) = DivRem::div_rem(bits, s16);
        let (bits, v12) = DivRem::div_rem(bits, s16);
        let (bits, d0) = DivRem::div_rem(bits, s16);
        let (bits, d12) = DivRem::div_rem(bits, s16);
        let (bits, charges) = DivRem::div_rem(bits, 0x40);
        let (bits, target) = DivRem::div_rem(bits, 4);
        let (bits, shape) = DivRem::div_rem(bits, 8);
        let (bits, filter) = DivRem::div_rem(bits, 2);
        let (scope, guard) = DivRem::div_rem(bits, 8);
        Entry {
            kind: kind.try_into().unwrap(),
            param: param.try_into().unwrap(),
            v0: SignedTrait::from16(v0),
            v12: SignedTrait::from16(v12),
            d0: d0.try_into().unwrap(),
            d12: d12.try_into().unwrap(),
            charges: charges.try_into().unwrap(),
            target: target.try_into().unwrap(),
            shape: shape.try_into().unwrap(),
            filter: filter.try_into().unwrap(),
            guard: guard.try_into().unwrap(),
            scope: scope.try_into().unwrap(),
        }
    }

    /// `v0 + (v12 − v0) × rank / 12` in `i32`, truncated toward zero (§2.2); `rank` 0–15
    /// (FX-0b). `|v12 − v0| ≤ 65,535` and `rank ≤ 15`: the product fits `i32`.
    fn value(self: @Entry, rank: u8) -> i32 {
        Self::line(*self.v0, *self.v12, rank)
    }

    /// The line of §2.2 through `(0, v0)` and `(12, v12)` at `rank`, for a value kept apart from
    /// its entry (the tick's content, `types::tick::SkillSheet`).
    fn line(v0: i16, v12: i16, rank: u8) -> i32 {
        EntryAssert::assert_rank(rank);
        let v0: i32 = v0.into();
        let v12: i32 = v12.into();
        v0 + (v12 - v0) * rank.into() / 12
    }

    /// The holding duration at `rank`, the same line (§2.2); signed, since `d12` may be below
    /// `d0`: the content pipeline keeps it in 0…`MAX_BASE_DURATION` at ranks 0 and 15.
    fn duration(self: @Entry, rank: u8) -> i32 {
        EntryAssert::assert_rank(rank);
        let d0: i32 = (*self.d0).into();
        let d12: i32 = (*self.d12).into();
        d0 + (d12 - d0) * rank.into() / 12
    }

    /// The kind's class (§3); `None` for the empty entry and the kinds after the MVP.
    fn class(self: @Entry) -> Option<KindClass> {
        let k = *self.kind;
        if k == kind::DAMAGE {
            Option::Some(KindClass::Hit)
        } else if k == kind::ATTACK_BONUS || k == kind::HIT_PENETRATION {
            Option::Some(KindClass::HitModifier)
        } else if k == kind::REGENERATION
            || (k >= kind::NEXT_SPELL_COST && k <= kind::PENETRATION)
            || (k >= kind::BLOCK && k <= kind::MOVEMENT) {
            Option::Some(KindClass::Holding)
        } else if k == kind::TRAP {
            Option::Some(KindClass::Placement)
        } else if k == kind::EMPTY || k > kind::LAST_MVP {
            Option::None
        } else {
            Option::Some(KindClass::Instant)
        }
    }

    /// Whether it is a holding entry (§5.14: at most one per carrier).
    #[inline(always)]
    fn is_holding(self: @Entry) -> bool {
        self.class() == Option::Some(KindClass::Holding)
    }

    /// Whether it is a hit modifier.
    #[inline(always)]
    fn is_hit_modifier(self: @Entry) -> bool {
        *self.kind == kind::ATTACK_BONUS || *self.kind == kind::HIT_PENETRATION
    }
}

/// The fields a kind reads besides kind, target, shape, filter, guard (§3's "reads"), and its
/// value's bounds `(low, high)` (checked at ranks 0 and 15, FX-0b); a kind that does not read `v`
/// has bounds (0, 0). The empty entry and the kinds after the MVP are not in it. A free function:
/// a constant table by kind id, which a trait would not make clearer (docs/CAIRO.md §7).
fn reads(kind: u8) -> (u8, i32, i32) {
    match kind {
        // Unreachable: `assert_legal` returns on the empty entry (kind 0) before it reads.
        0 => core::panic_with_felt252(errors::KIND),
        1 => (READS_PARAM + READS_V, 0, 32767), // DAMAGE: damage type, base damage
        2 => (READS_V, 0, 32767), // ATTACK_BONUS
        3 => (READS_V, 0, 32767), // HEAL
        4 => (READS_V, 0, 32767), // LIFE_STEAL
        5 => (READS_V + READS_D, -10, 10), // REGENERATION: pips
        6 => (READS_PARAM + READS_V, 1, MAX_VALUE_DURATION), // CONDITION: its duration
        7 => (READS_PARAM, 0, 0), // CURE
        8 => (READS_V, -255, 255), // ENERGY
        9 => (READS_V + READS_D, 0, 255), // NEXT_SPELL_COST
        10 => (READS_V + READS_D, 0, 255), // ARMOR
        11 => (READS_V + READS_D + READS_SCOPE, 0, 100), // PENETRATION: percent
        12 => (READS_V, 0, 100), // HIT_PENETRATION: percent
        13 => (READS_V + READS_D, 1, 63), // BLOCK: charges
        14 => (READS_PARAM + READS_D, 0, 0), // EVADE: melee
        15 => (READS_PARAM + READS_V + READS_D + READS_CHARGES, 1, MAX_VALUE_DURATION),
        16 => (READS_D, 0, 0), // MOVEMENT
        17 => (0, 0, 0), // INTERRUPT
        18 => (0, 0, 0), // TRAP
        // Reachable: a kind from 19 to `kind::LAST` reaches it through `assert_legal`. It is the
        // table's own refusal of a kind after the MVP's, kept in the `match` (ENG-R1c-2, ruling 9:
        // moving it would duplicate the table's case analysis).
        _ => core::panic_with_felt252(errors::NOT_MVP),
    }
}

#[generate_trait]
pub impl EntryAssert of EntryAssertTrait {
    /// A rank of 0 to `MAX_RANK` (FX-0b), the line's domain (§2.2).
    #[inline(always)]
    fn assert_rank(rank: u8) {
        assert(rank <= MAX_RANK, errors::RANK);
    }

    /// Every field fits its layout: charges 6 bits, target 2, shape 3, filter 1, guard 3, scope
    /// 2; durations at most `MAX_BASE_DURATION`.
    #[inline(always)]
    fn assert_valid(self: @Entry) {
        assert(*self.charges < 0x40, errors::CHARGES);
        assert(*self.target < 4, errors::TARGET);
        assert(*self.shape < 8, errors::SHAPE);
        assert(*self.filter < 2, errors::FILTER);
        assert(*self.guard < 8, errors::GUARD);
        assert(*self.scope < 4, errors::SCOPE);
        let max: u32 = MAX_BASE_DURATION;
        assert((*self.d0).into() <= max && (*self.d12).into() <= max, errors::DURATION);
    }

    /// The content pipeline's checks of one entry (§2.1, §3; X-1): an empty entry has every field
    /// 0; otherwise its kind is one of the MVP's, its shape 1–5 and its guard 0–4, the fields
    /// its kind does not read are 0, its `param` is one its kind names (a condition one of the
    /// MVP's five, FX-22), its value at ranks 0 and 15
    /// lies within its kind's bounds, its duration at ranks 0 and 15 within 0…43,688, and an
    /// `ON_ATTACK_CONDITION` has a duration or charges.
    fn assert_legal(self: @Entry) {
        self.assert_valid();
        if self.is_empty() {
            assert(*self == Default::default(), errors::EMPTY);
            return;
        }
        assert(*self.kind <= kind::LAST, errors::KIND);
        // CBT-05a's scope (the project manager, 2026-10-02, option (ii)): the executor runs what
        // the MVP's content uses (design/19 §8, design/20 §3). `LIFE_STEAL` and `INTERRUPT` have
        // no MVP source, and no MVP entry is guarded but by `BELOW_HALF` (Second Wind): they stay
        // in design/19 and are refused here until content needs them (PLAN: executor kinds beyond
        // the MVP's content).
        assert(
            *self.kind != kind::LIFE_STEAL && *self.kind != kind::INTERRUPT, errors::KIND_DEFERRED,
        );
        assert(
            *self.guard == guard::ALWAYS || *self.guard == guard::BELOW_HALF,
            errors::GUARD_DEFERRED,
        );
        let (fields, low, high) = reads(*self.kind);
        assert(*self.shape >= shape::SINGLE && *self.shape <= shape::LAST, errors::SHAPE);
        assert(*self.guard <= guard::LAST, errors::GUARD);
        let (_, param_read) = DivRem::div_rem(fields, 2);
        let (_, v_read) = DivRem::div_rem(fields / READS_V, 2);
        let (_, d_read) = DivRem::div_rem(fields / READS_D, 2);
        let (_, charges_read) = DivRem::div_rem(fields / READS_CHARGES, 2);
        let (_, scope_read) = DivRem::div_rem(fields / READS_SCOPE, 2);
        if param_read == 0 {
            assert(*self.param == 0, errors::READS);
        } else {
            let param = *self.param;
            let named = match *self.kind {
                1 => param >= damage::SLASHING && param <= damage::LAST,
                14 => param == EVADE_MELEE,
                _ => param >= condition::BLEEDING && param <= condition::LAST,
            };
            assert(named, errors::PARAM);
            // Conditions 6–9 have no MVP source and no stored deadline until FX-22 (CBT-04): a
            // `CONDITION`, `CURE` or `ON_ATTACK_CONDITION` naming one is refused here, so that the
            // executor never meets one (CBT-05a).
            let k = *self.kind;
            if k == kind::CONDITION || k == kind::CURE || k == kind::ON_ATTACK_CONDITION {
                assert(param <= condition::LAST_MVP, errors::CONDITION_NOT_MVP);
            }
        }
        if v_read == 0 {
            assert(*self.v0 == 0 && *self.v12 == 0, errors::READS);
        } else {
            let at0 = self.value(0);
            let at15 = self.value(MAX_RANK);
            assert(at0 >= low && at0 <= high && at15 >= low && at15 <= high, errors::VALUE);
        }
        if d_read == 0 {
            assert(*self.d0 == 0 && *self.d12 == 0, errors::READS);
        } else {
            let max: i32 = MAX_BASE_DURATION.try_into().unwrap();
            let at15 = self.duration(MAX_RANK);
            assert(at15 >= 0 && at15 <= max, errors::DURATION);
        }
        if charges_read == 0 {
            assert(*self.charges == 0, errors::READS);
        } else {
            // §3.4: a duration or charges. Without charges, the duration is positive at every
            // rank: at ranks 0 and 15, the line's ends (§2.2; FX-0b).
            let timed = self.duration(0) > 0 && self.duration(MAX_RANK) > 0;
            assert(*self.charges != 0 || timed, errors::NO_TIME);
        }
        if scope_read == 0 {
            assert(*self.scope == 0, errors::READS);
        }
    }

    /// The legal carriers (§5.14, FX-45, FX-21, FX-35), with every entry legal: entries packed
    /// without a gap; at most one hit (the implicit weapon hit of an attack, or one `DAMAGE`
    /// entry); a `DAMAGE` entry before every other entry but `TRAP`; at most one holding entry;
    /// hit modifiers only with a hit and on its addressing, shape and filter, `ATTACK_BONUS` only
    /// in an attack; an attack's entries all `FOE`, `SINGLE`; a `TRAP` entry first, `TILE`,
    /// `SINGLE`, its payload `FOE`, `SINGLE`; no `TILE` entry
    /// beside a `FOE` or `ALLY` one, no `SELF` entry before an addressed one, `TRAP` aside (D-271,
    /// D-276); no `SELF`, `SINGLE` entry on `FOES`, which takes nobody (R-45, D-289), nor a
    /// `DAMAGE` one on either filter (D-303); `DISC_1`
    /// only in a potion; no `DISC_2`, `DISC_3` in the MVP's content; a potion's entry does not
    /// scale.
    fn assert_carrier(entries: Span<Entry>, carrier: Carrier) {
        let mut ended = false;
        let mut hit: Option<Entry> = Option::None;
        let mut holding = false;
        let mut modifier = false;
        let mut bonus = false;
        let mut trap = false;
        let mut tiles = false;
        let mut entities = false;
        let mut selfed = false;
        let mut index: u32 = 0;
        for entry in entries {
            entry.assert_legal();
            if entry.is_empty() {
                ended = true;
            } else {
                assert(!ended, errors::GAP);
                let k = *entry.kind;
                let s = *entry.shape;
                assert(s != shape::DISC_2 && s != shape::DISC_3, errors::AREA);
                assert(s != shape::DISC_1 || carrier == Carrier::Potion, errors::DISC_1);
                if carrier == Carrier::Potion {
                    assert(*entry.v0 == *entry.v12 && *entry.d0 == *entry.d12, errors::NOT_SCALED);
                }
                if carrier == Carrier::Attack {
                    assert(
                        *entry.target == target::FOE && s == shape::SINGLE, errors::ATTACK_ENTRY,
                    );
                }
                if k == kind::TRAP {
                    assert(
                        index == 0 && *entry.target == target::TILE && s == shape::SINGLE,
                        errors::TRAP_ENTRY,
                    );
                    trap = true;
                } else if trap {
                    assert(*entry.target == target::FOE && s == shape::SINGLE, errors::PAYLOAD);
                }
                // D-271: the cast address is a tile or an entity id, never both. `TRAP` (a tile
                // by design) does not read it, and `SELF` (the caster) does not either.
                // D-276 (D-272 before it): a `SELF` entry before an addressed one (`TILE`, `FOE`,
                // `ALLY`) makes the carrier's addressing `SELF`, so the reach is never checked
                // yet the addressed entry reads the address; `SELF` entries after it are legal.
                if k != kind::TRAP {
                    let t = *entry.target;
                    let addressed = t == target::TILE || t == target::FOE || t == target::ALLY;
                    tiles = tiles || t == target::TILE;
                    entities = entities || t == target::FOE || t == target::ALLY;
                    assert(!(tiles && entities) && !(addressed && selfed), errors::MIXED_TARGETS);
                    selfed = selfed || t == target::SELF;
                    // R-45 (D-289): a set of `SELF`, `SINGLE` holds the caster alone, and the
                    // caster is never its own foe: under `FOES` it takes nobody. A hit modifier
                    // is not a set (it rides the hit's). D-303: nor does a `DAMAGE` entry of
                    // `SELF`, `SINGLE` under `ALLIES`, the caster being the source of its own
                    // hit, which `own_hit` cuts from the hit's set.
                    assert(
                        !(t == target::SELF
                            && s == shape::SINGLE
                            && ((*entry.filter == filter::FOES && !entry.is_hit_modifier())
                                || k == kind::DAMAGE)),
                        errors::TAKES_NOBODY,
                    );
                }
                if k == kind::DAMAGE {
                    assert(carrier != Carrier::Attack && hit.is_none(), errors::TWO_HITS);
                    let first = if trap {
                        1
                    } else {
                        0
                    };
                    assert(index == first, errors::HIT_NOT_FIRST);
                    hit = Option::Some(*entry);
                }
                if entry.is_holding() {
                    assert(!holding, errors::TWO_HOLDING);
                    holding = true;
                }
                if k == kind::ATTACK_BONUS {
                    assert(carrier == Carrier::Attack, errors::ATTACK_BONUS);
                    // DS-20 (design/20 §1.6, D-160): at most one a carrier.
                    assert(!bonus, errors::TWO_ATTACK_BONUSES);
                    bonus = true;
                }
                if entry.is_hit_modifier() {
                    // An attack's implicit hit is on the attacked foe: its modifiers take it
                    // (`FOE`, `SINGLE`, checked above, and `FOES`).
                    assert(
                        carrier != Carrier::Attack || *entry.filter == filter::FOES,
                        errors::MODIFIER_SET,
                    );
                    modifier = true;
                }
            }
            index += 1;
        }
        if !modifier || carrier == Carrier::Attack {
            return;
        }
        // Hit modifiers, of a carrier other than an attack: on the `DAMAGE` entry's set.
        let damage = match hit {
            Option::Some(damage) => damage,
            Option::None => core::panic_with_felt252(errors::MODIFIER_NO_HIT),
        };
        for entry in entries {
            if entry.is_hit_modifier() {
                assert(
                    *entry.target == damage.target
                        && *entry.shape == damage.shape
                        && *entry.filter == damage.filter,
                    errors::MODIFIER_SET,
                );
            }
        }
    }
}

/// The entry's unit tests (CBT-01, design/19 §2, §3 and §7.1): 97 bits round-trip and a value
/// too wide is refused, the line through ranks 0 and 12, the kinds' classes, and the content
/// pipeline's checks (reads, bounds, deferred kinds and guards, CBT-4's preparations, DS-20's
/// second attack bonus).
#[cfg(test)]
mod tests {
    use crate::models::item::class;
    use crate::models::skill::{Skill, SkillAssert, SkillRecord, SkillTrait};
    use crate::types::combat::{HitClass, condition, damage, skill_kind, weapon};
    use crate::types::passive::id;
    use super::{
        Carrier, ENTRY_BOUND, Entry, EntryAssert, EntryTrait, KindClass, filter, guard, kind, scope,
        shape, target,
    };

    /// The entries and records these tests start from: design/03's starter skills as design/19 §8
    /// writes them (values illustrative).
    #[generate_trait]
    impl FixtureImpl of Fixture {
        /// An entry of `kind` on the attacked foe, every other field 0.
        fn on_foe(kind: u8) -> Entry {
            Entry { kind, target: target::FOE, shape: shape::SINGLE, ..Default::default() }
        }

        fn damage(kind: u8, v0: i16, v12: i16) -> Entry {
            Entry { param: kind, v0, v12, ..Self::on_foe(kind::DAMAGE) }
        }

        fn inflict(condition: u8, v0: i16, v12: i16) -> Entry {
            Entry { param: condition, v0, v12, ..Self::on_foe(kind::CONDITION) }
        }

        /// Under `ALLIES`: the caster is its own ally, and under `FOES` a `SELF` entry takes nobody
        /// (R-45).
        fn on_self(kind: u8) -> Entry {
            Entry {
                kind,
                target: target::SELF,
                shape: shape::SINGLE,
                filter: filter::ALLIES,
                ..Default::default(),
            }
        }

        fn skill(kind: u8, entries: [Entry; 3]) -> Skill {
            SkillTrait::new(1, 2, kind, 5, 0, 1, 10, 6, target::FOE, false, entries)
        }

        /// Venom Coat: `ON_ATTACK_CONDITION` Poison 24 for 12 ticks.
        fn venom_coat() -> Skill {
            let coat = Entry {
                param: condition::POISON,
                v0: 24,
                v12: 24,
                d0: 12,
                d12: 12,
                ..Self::on_self(kind::ON_ATTACK_CONDITION),
            };
            Self::skill(skill_kind::PREPARATION, [coat, Default::default(), Default::default()])
        }

        /// Every field of an entry at its widest.
        fn entry_max() -> Entry {
            EntryTrait::new(0xFF, 0xFF, -32768, 32767, 43688, 43688, 63, 3, 7, 1, 7, 3)
        }

        fn preparation(d0: u16, d12: u16, charges: u8) -> Entry {
            Entry {
                kind: kind::ON_ATTACK_CONDITION,
                param: condition::POISON,
                v0: 1,
                v12: 1,
                d0,
                d12,
                charges,
                target: target::SELF,
                shape: shape::SINGLE,
                ..Default::default(),
            }
        }
    }

    // §2.1: 97 bits, every field at its widest round-trips; each sits at its bit; the empty entry
    // is 0.
    #[test]
    #[available_gas(l2_gas: 795281)] // ceil(1.05 × 757410 measured)
    fn test_entry_round_trip() {
        let top = Fixture::entry_max();
        let bits = top.pack();
        assert(bits < ENTRY_BOUND, '97 bits');
        assert(EntryTrait::unpack(bits) == top, 'top round trip');
        let low = Entry { v0: 32767, v12: -32768, d0: 0, d12: 0, ..top };
        assert(EntryTrait::unpack(low.pack()) == low, 'signed ends');
        let empty: Entry = Default::default();
        assert(empty.pack() == 0 && EntryTrait::unpack(0) == empty, 'empty is 0');
        let at = |entry: Entry| -> u128 {
            entry.pack()
        };
        let e: Entry = Default::default();
        assert(at(Entry { kind: 1, ..e }) == 1, 'kind at 0');
        assert(at(Entry { param: 1, ..e }) == 0x100, 'param at 8');
        assert(at(Entry { v0: 1, ..e }) == 0x10000, 'v0 at 16');
        assert(at(Entry { v0: -1, ..e }) == 0xFFFF0000, 'v0 signed');
        assert(at(Entry { v12: 1, ..e }) == 0x100000000, 'v12 at 32');
        assert(at(Entry { d0: 1, ..e }) == 0x1000000000000, 'd0 at 48');
        assert(at(Entry { d12: 1, ..e }) == 0x10000000000000000, 'd12 at 64');
        assert(at(Entry { charges: 1, ..e }) == 0x100000000000000000000, 'charges at 80');
        assert(at(Entry { target: 1, ..e }) == 0x4000000000000000000000, 'target at 86');
        assert(at(Entry { shape: 1, ..e }) == 0x10000000000000000000000, 'shape at 88');
        assert(at(Entry { filter: 1, ..e }) == 0x80000000000000000000000, 'filter at 91');
        assert(at(Entry { guard: 1, ..e }) == 0x100000000000000000000000, 'guard at 92');
        assert(at(Entry { scope: 1, ..e }) == 0x800000000000000000000000, 'scope at 95');
    }

    #[test]
    #[should_panic(expected: 'entry: charges')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_charges_refused() {
        Entry { charges: 64, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'entry: target')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_target_refused() {
        Entry { target: 4, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'entry: shape')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_shape_refused() {
        Entry { shape: 8, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'entry: filter')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_filter_refused() {
        Entry { filter: 2, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'entry: guard')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_guard_refused() {
        Entry { guard: 8, ..Default::default() }.pack();
    }

    #[test]
    #[should_panic(expected: 'entry: scope')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_scope_refused() {
        Entry { scope: 4, ..Default::default() }.pack();
    }

    // `MAX_BASE_DURATION` (ENG-01 §3.1): the registry's writer refuses a longer duration.
    #[test]
    #[should_panic(expected: 'entry: duration')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_duration_refused() {
        Entry { d12: 43689, ..Default::default() }.pack();
    }

    // §2.2: the line through ranks 0 and 12, truncated toward zero, extrapolated to 15 (FX-0b).
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_entry_scaling() {
        let rending = Fixture::inflict(condition::BLEEDING, 5, 20);
        assert(rending.value(0) == 5 && rending.value(12) == 20, 'ends');
        assert(rending.value(6) == 12, 'rank 6: 5 + 15 x 6 / 12');
        assert(rending.value(15) == 23, 'rank 15: 5 + 225 / 12');
        let falling = Entry { v0: 0, v12: -13, ..Default::default() };
        assert(falling.value(1) == -1, 'toward zero: -13 / 12');
        assert(falling.value(15) == -16, '-195 / 12');
        let widest = Entry { v0: -32768, v12: 32767, ..Default::default() };
        assert(widest.value(15) == -32768 + 65535 * 15 / 12, 'fits i32');
        let shrinking = Entry { d0: 10, d12: 0, ..Default::default() };
        assert(shrinking.duration(12) == 0 && shrinking.duration(15) == -2, 'duration line');
    }

    #[test]
    #[should_panic(expected: 'entry: rank')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_rank_refused() {
        Fixture::damage(damage::FIRE, 1, 2).value(16);
    }

    // §3's "class" column, and §7.1's enumerations as frozen ids.
    #[test]
    #[available_gas(l2_gas: 155159)] // ceil(1.05 × 147770 measured)
    fn test_kind_classes_and_ids() {
        let class = |k: u8| -> Option<KindClass> {
            Entry { kind: k, ..Default::default() }.class()
        };
        assert(class(0) == Option::None, 'empty');
        assert(class(kind::DAMAGE) == Option::Some(KindClass::Hit), 'damage');
        assert(class(kind::ATTACK_BONUS) == Option::Some(KindClass::HitModifier), 'bonus');
        assert(class(kind::HIT_PENETRATION) == Option::Some(KindClass::HitModifier), 'hit pen');
        let holding = array![5_u8, 9, 10, 11, 13, 14, 15, 16];
        for k in holding {
            assert(class(k) == Option::Some(KindClass::Holding), 'holding');
        }
        let instant = array![3_u8, 4, 6, 7, 8, 17];
        for k in instant {
            assert(class(k) == Option::Some(KindClass::Instant), 'instant');
        }
        assert(class(kind::TRAP) == Option::Some(KindClass::Placement), 'trap');
        for k in 19..24_u8 {
            assert(class(k) == Option::None, 'after the MVP');
        }
        assert(kind::LAST == 23 && id::FIRST == 40 && id::LAST == 65, 'kinds');
        assert(condition::LAST == 9 && damage::LAST == 9 && skill_kind::LAST == 12, 'enums');
        assert(
            shape::LAST == 5 && guard::LAST == 4 && scope::ALL == 3 && target::TILE == 3, 'fields',
        );
        assert(weapon::SWORD == 1 && weapon::WAND == 6, 'weapon classes');
        assert(HitClass::Weapon != HitClass::Trap, 'hit classes');
    }

    // §3's "reads" and bounds: the design's own entries are legal.
    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_entry_legal() {
        Fixture::inflict(condition::BLEEDING, 5, 20).assert_legal();
        Fixture::damage(damage::HOLY, 0, 26213).assert_legal();
        let [coat, _, _] = Fixture::venom_coat().entries;
        coat.assert_legal();
        let oil = Entry { d0: 0, d12: 0, charges: 3, ..coat };
        oil.assert_legal();
        let brace = Entry { v0: 1, v12: 3, d0: 10, d12: 10, ..Fixture::on_self(kind::BLOCK) };
        brace.assert_legal();
        let sidestep = Entry { param: 1, d0: 2, d12: 6, ..Fixture::on_self(kind::EVADE) };
        sidestep.assert_legal();
        let warcry = Entry {
            v0: 10,
            v12: 20,
            d0: 5,
            d12: 11,
            scope: scope::ALL,
            ..Fixture::on_self(kind::PENETRATION),
        };
        warcry.assert_legal();
        let drain = Entry { v0: -255, v12: -255, ..Fixture::on_foe(kind::ENERGY) };
        drain.assert_legal();
        let regen = Entry { v0: -10, v12: 6, d0: 5, d12: 5, ..Fixture::on_self(5) };
        regen.assert_legal();
        let empty: Entry = Default::default();
        empty.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_value_at_rank_15_refused() {
        // 10 at rank 12 extrapolates to 12 at rank 15: above `REGENERATION`'s +10.
        Entry { v0: 2, v12: 10, d0: 5, d12: 5, ..Fixture::on_self(kind::REGENERATION) }
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: value out of bounds')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_condition_of_zero_ticks_refused() {
        Fixture::inflict(condition::POISON, 0, 5).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: field not read')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_unread_field_refused() {
        // `HEAL` reads no duration.
        Entry { v0: 1, v12: 1, d0: 3, ..Fixture::on_self(kind::HEAL) }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_unknown_condition_refused() {
        Fixture::inflict(10, 1, 1).assert_legal();
    }

    // CBT-05a: conditions 6–9 are refused in every kind that names a condition (FX-22).
    // CBT-05a, option (ii): the kinds and entry guards the MVP's content does not use are refused.
    #[test]
    #[should_panic(expected: 'entry: kind deferred')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_interrupt_deferred() {
        Fixture::on_foe(kind::INTERRUPT).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: kind deferred')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_life_steal_deferred() {
        Entry { v0: 20, v12: 20, ..Fixture::on_foe(kind::LIFE_STEAL) }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: guard deferred')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_guard_above_half_deferred() {
        Entry { v0: 20, v12: 20, guard: guard::ABOVE_HALF, ..Fixture::on_foe(kind::HEAL) }
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: guard deferred')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_guard_in_stance_deferred() {
        Entry { v0: 20, v12: 20, guard: guard::IN_STANCE, ..Fixture::on_foe(kind::HEAL) }
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: guard deferred')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_guard_enchanted_deferred() {
        Entry { v0: 20, v12: 20, guard: guard::ENCHANTED, ..Fixture::on_foe(kind::HEAL) }
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: condition after the MVP')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_condition_after_the_mvp_refused() {
        Fixture::inflict(condition::DAZED, 1, 1).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: condition after the MVP')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_cure_after_the_mvp_refused() {
        Entry { param: condition::DEEP_WOUND, ..Fixture::on_self(kind::CURE) }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: neither d nor charges')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_oil_without_time_refused() {
        let [coat, _, _] = Fixture::venom_coat().entries;
        Entry { d0: 0, d12: 0, charges: 0, ..coat }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: kind after the MVP')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_post_mvp_kind_refused() {
        Fixture::on_self(kind::SUMMON).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: empty with a field')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_empty_with_field_refused() {
        Entry { guard: 1, ..Default::default() }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: shape')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_shape_zero_refused() {
        Entry { shape: 0, ..Fixture::on_foe(kind::HEAL) }.assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: duration')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_entry_negative_duration_at_15_refused() {
        Entry { v0: 1, v12: 1, d0: 10, d12: 0, ..Fixture::on_self(kind::ARMOR) }.assert_legal();
    }

    // CBT-4: without charges, a preparation's duration is positive at every rank (ranks 0 and 15).
    #[test]
    #[should_panic(expected: 'entry: neither d nor charges')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_preparation_falling_to_0_at_15_refused() {
        // The audit's case: 5 + trunc(−4 × 15 / 12) = 0.
        Fixture::preparation(5, 1, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: neither d nor charges')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_preparation_falling_by_one_refused() {
        // 1 + trunc(−15 / 12) = 0.
        Fixture::preparation(1, 0, 0).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'entry: neither d nor charges')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_preparation_rising_from_0_refused() {
        Fixture::preparation(0, 5, 0).assert_legal();
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_preparation_boundaries_accepted() {
        // 4 + trunc(−3 × 15 / 12) = 1; 1 at both ends; rising from 1 to exactly 43,688 at rank
        // 15 (1 + trunc(34,950 × 15 / 12)); charges without a duration.
        Fixture::preparation(4, 1, 0).assert_legal();
        Fixture::preparation(1, 1, 0).assert_legal();
        Fixture::preparation(1, 34951, 0).assert_legal();
        Fixture::preparation(0, 0, 1).assert_legal();
        Fixture::preparation(5, 1, 1).assert_legal();
    }

    // §6 test 7, DS-20: a second `ATTACK_BONUS` on one carrier is refused.
    #[test]
    #[should_panic(expected: 'carrier: two attack bonuses')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 168945)] // ceil(1.05 × 160900 measured)
    fn test_second_attack_bonus_refused() {
        let bonus = EntryTrait::new(
            kind::ATTACK_BONUS, 0, 5, 5, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
        );
        EntryAssert::assert_carrier(
            array![bonus, bonus, Default::default()].span(), Carrier::Attack,
        );
    }
}
