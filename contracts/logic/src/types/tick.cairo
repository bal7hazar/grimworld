//! The value types and constants of a world tick (CBT-02; design/19 §5, §7.2): a held effect as
//! its word stores it, the content's sheets, the encodings ENG-01 froze. The actors' words and
//! their in-call view are models (`models::member`, `models::goblin`); the world and the pipeline
//! are `types::world`.
//!
//! **Words in, words out.** The library call takes and returns the stored words (`Words`): a
//! member's four words that change in play (`MemberState`, `MemberTimers`, `MemberEffects`,
//! `Recharges`, ENG-01 §3.2) with the three snapshot words it reads, a goblin's two
//! (`GoblinState`, `GoblinTimers`), as `Instances` reads and writes them. Inside the call, each
//! actor's **hot fields** (what the ticks read and write) are unpacked once (`load`) into a small
//! struct, the ticks work on them, and they are written back into the words as deltas (`store`).
//! Measured (CBT-02's report): the words alone cost a limb split per read, a struct of every field
//! cost its copies; this is the cheapest of the three.
//!
//! The words' layouts are the ephemeral package's (it owns the storage); the offsets below are
//! ENG-01's frozen ones, and the ephemeral package's tests pin `load` and `store` against its
//! packers (`test_tick_words`).
//!
//! Beside the hot fields, each actor carries what the tick derives **once per call** from the
//! snapshot and the content (D-145: content read once per batch, kept in memory): its maxima, its
//! regeneration, and each held effect's `REGENERATION` pips at its rank. The executor (CBT-05)
//! sets an effect's pips and deadline when it holds one.

use core::dict::{Felt252Dict, Felt252DictTrait};
use crate::helpers::signed::SignedTrait;
use crate::models::caste::Caste;
use crate::models::index::{Item, Skill};
use crate::packing::{N16, N4, N8, limbs, peel};
use crate::types::combat::damage;
use crate::types::effect::{ENTRY_BOUND, Entry, EntryTrait, kind};

/// Adrenaline lost a tick out of combat, in quarter strikes (design/19 §5.8, FX-12): a code
/// constant until BAL-01, **1** by D-157 E.
pub const ADRENALINE_DECAY: u16 = 1;
/// Health pips are clamped to ±10 (design/03, *Pips*); one pip is 2 health a tick.
pub const MAX_PIPS: i32 = 10;
pub const HEALTH_PER_PIP: i32 = 2;
/// A crippled actor's move of one tile, in ticks (design/19 §3.2, FX-15).
pub const CRIPPLED_MOVE_TICKS: u8 = 2;
/// Energy is in thirds (design/03: one pip is one energy every 3 ticks).
pub const ENERGY_THIRDS: u16 = 3;
/// Stored health regeneration is its pips + 10 (`MemberStats.health_regen`, `Caste.health_regen`).
pub const REGEN_OFFSET: i32 = 10;
/// A goblin's adrenaline field holds at most 63 strikes, in quarters (design/19 §5.12).
pub const MAX_GOBLIN_ADRENALINE: u8 = 252;
/// No member activation (`MemberTimers.act_slot`, ENG-01).
pub const NO_SLOT: u8 = 255;

/// `MemberState.status` (ENG-01 §3.2).
pub mod status {
    pub const INSIDE: u8 = 0;
    pub const DOWN: u8 = 1;
    pub const GONE: u8 = 2;
}

/// `GoblinState.ai` (ENG-01 §3.2, design/04).
pub mod ai {
    pub const ASLEEP: u8 = 0;
    pub const WATCH: u8 = 1;
    pub const ALERTED: u8 = 2;
    pub const ENGAGED: u8 = 3;
    pub const FLEEING: u8 = 4;
    pub const RETURNING: u8 = 5;
    pub const DEAD: u8 = 6;
    pub const LOOTED: u8 = 7;
}

/// `MemberState.flags`: what happened "since the last tick" (ENG-01 §3.2) and "hit this tick"
/// (design/19 §7.2, §5.10), which a tick's step 0 clears; `HALVED` is spent once an instance.
pub mod flag {
    pub const TURNED: u8 = 1;
    pub const INSTANT: u8 = 2;
    pub const HIT: u8 = 8;
    pub const HALVED: u8 = 16;
    /// The flags step 0 keeps.
    pub const KEPT: u8 = 0xFF - TURNED - INSTANT - HIT;
}


/// A held effect as its word stores it (design/19 §5.7, §7.2): its carrier (a skill id, or with
/// `potion` a belt slot 0–3), its charges (0–63), its deadline (`MAX_CLOCK` for a charge-only
/// effect) and the source's rank at application (0–15).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Held {
    pub carrier: u16,
    pub potion: bool,
    pub charges: u8,
    pub deadline: u32,
    pub rank: u8,
}


/// The fields of a `SKILL` a tick reads: kind, activation, recharge, and its `REGENERATION`
/// entry's line (0, 0 without one); for the executor (CBT-05a), its range and its three entries as
/// the record packs them (97 bits each, 0 an empty entry), decoded once a call into
/// `Sheets.entries` (SPK-15's L3, D-172).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct SkillSheet {
    pub id: u16,
    pub kind: u8,
    /// Its adrenaline cost, in strikes (the caps of §5.12).
    pub adrenaline: u8,
    pub activation: u16,
    pub recharge: u16,
    pub regen0: i16,
    pub regen12: i16,
    /// In tiles: the reach its target must be in at resolution (§5.9).
    pub range: u8,
    pub entry1: u128,
    pub entry2: u128,
    pub entry3: u128,
}

/// The fields of a potion (`ITEM`) a tick reads: its `REGENERATION` pips (potions do not scale);
/// for the executor, its entry packed, its range and a bomb's strength (FX-18, FX-28).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct PotionSheet {
    pub id: u32,
    pub regen: i16,
    pub entry: u128,
    pub range: u8,
    pub strength: u8,
}

/// The fields of a `CASTE` a tick reads (design/19 §7.3).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct CasteSheet {
    pub id: u16,
    /// Health multiplier, percent.
    pub health: u16,
    /// Pips + 10.
    pub health_regen: u8,
    pub energy: u8,
    pub energy_regen: u8,
    /// Its weapon's tick cost `k` (FX-15).
    pub weapon_ticks: u8,
    pub skills: [u16; 4],
    /// For the executor's hits (CBT-05a, §5.5): its armor, its armor per damage type (9 × 6 bits,
    /// type `t` at `6 (t − 1)`, FX-23), its weapon inline (class, damage ≤ 255 by DS-18, damage
    /// type, range) and the rank of its skills and weapon (§7.3).
    pub armor: u8,
    pub armor_vs: u64,
    pub weapon: u8,
    pub weapon_damage: u8,
    pub damage_type: u8,
    pub weapon_range: u8,
    pub rank: u8,
}

/// The content of a batch, read once (D-145): the skills of the bars, of the goblins' castes and
/// of held effects; the belt's potions; the goblins' castes. What crosses the library call.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Content {
    pub skills: Span<SkillSheet>,
    pub potions: Span<PotionSheet>,
    pub castes: Span<CasteSheet>,
}

/// `CasteSheet.armor_vs`'s lanes: damage type `t` at `6 (t − 1)`, and the 54 bits' bound.
const VS_LANES: [u64; 9] = [
    1, 0x40, 0x1000, 0x40000, 0x1000000, 0x40000000, 0x1000000000, 0x40000000000, 0x1000000000000,
];
const VS_BOUND: u128 = 0x40000000000000;

/// A position in a list of `Sheets` that holds nothing: an empty skill slot.
pub const ABSENT: u32 = 0xFFFFFFFF;
/// The same in a 16-bit lane (`Member.bar_at`). A skill's position fits one: the content holds at
/// most `MAX_SKILLS` skills (`IndexTrait::new`).
pub const ABSENT_LANE: u128 = 0xFFFF;
/// Skill ids are `u16`: a content of more skills than that holds the same id twice, and only the
/// first is ever read.
pub const MAX_SKILLS: u32 = 0xFFFF;

/// What a caste's goblins read in the ticks, derived once per call (CBT-02d): each skill's position
/// in `Sheets.skills` (`ABSENT` for an empty slot), their highest adrenaline cost in quarters, at
/// most the field's 252 (design/19 §5.12), and the weapon's tick cost `k` (FX-15), so that a
/// conclusion reads the kit alone.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Kit {
    pub skills: [u32; 4],
    pub cap: u8,
    pub weapon_ticks: u8,
}

/// The content as the ticks read it (CBT-02d): its sheets, and each caste's `Kit` in the order of
/// `castes`. An actor holds the positions of its records (`Goblin.caste_at`, `Member.bar_at`),
/// found once, at its load, through the `Index`; the ticks read a record at its position.
/// The carriers' entries decoded once a call (CBT-05a, SPK-15's L3): skill `p`'s three at `3 p`,
/// `3 p + 1`, `3 p + 2`; potion `p`'s one at `p`. An in-call type: nothing crosses the call.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Sheets {
    pub skills: Span<SkillSheet>,
    pub potions: Span<PotionSheet>,
    pub castes: Span<CasteSheet>,
    pub kits: Span<Kit>,
    pub entries: Span<Entry>,
    pub potion_entries: Span<Entry>,
}

/// The content's positions by id, built once per call (CBT-02d): one dictionary, read once for
/// each id an actor's words hold at its load, then dropped. A read costs the same wherever the
/// record lies, where a lookup scanned its list (up to 38 comparisons for a skill).
#[derive(Destruct)]
pub struct Index {
    /// A record's position + 1 by its key (0: not in the content). Keys: a skill's id; a caste's,
    /// + `CASTE_KEY`; a potion's, + `POTION_KEY`.
    positions: Felt252Dict<u32>,
}

pub const CASTE_KEY: felt252 = 0x10000;
pub const POTION_KEY: felt252 = 0x100000000;

pub mod errors {
    pub const NO_SKILL: felt252 = 'tick: skill not in content';
    pub const NO_CASTE: felt252 = 'tick: caste not in content';
    pub const NO_POTION: felt252 = 'tick: potion not in content';
    pub const SKILLS: felt252 = 'tick: more skills than ids';
}


#[generate_trait]
pub impl SkillSheetImpl of SkillSheetTrait {
    /// The sheet of skill `id`: its holding entry is its one `REGENERATION` if any (§5.14: at most
    /// one holding entry per carrier).
    fn new(id: u16, skill: @Skill) -> SkillSheet {
        let mut regen0 = 0;
        let mut regen12 = 0;
        for entry in skill.entries.span() {
            if *entry.kind == kind::REGENERATION {
                regen0 = *entry.v0;
                regen12 = *entry.v12;
            }
        }
        let [first, second, third] = *skill.entries;
        SkillSheet {
            id,
            kind: *skill.kind,
            adrenaline: *skill.adrenaline,
            activation: *skill.activation,
            recharge: *skill.recharge,
            regen0,
            regen12,
            range: *skill.range,
            entry1: first.pack(),
            entry2: second.pack(),
            entry3: third.pack(),
        }
    }

    /// The sheet of skill `id` read from its record's 2 parts (`models::skill` layout): only the
    /// header's kind, activation and recharge, and the entries' kinds until the `REGENERATION`
    /// one or an empty entry. `new` on the unpacked record is its oracle.
    fn read(id: u16, parts: Span<felt252>) -> SkillSheet {
        let (header, first) = limbs(*parts[0]);
        let (second, third) = limbs(*parts[1]);
        let mut regen0 = 0;
        let mut regen12 = 0;
        for entry in array![first, second, third].span() {
            let mut rest = *entry;
            let entry_kind = peel(ref rest, N8);
            if entry_kind == kind::EMPTY.into() {
                break;
            }
            if entry_kind == kind::REGENERATION.into() {
                // Bits 8–15, then `v0` and `v12`.
                let _ = peel(ref rest, N8);
                regen0 = SignedTrait::from16(peel(ref rest, N16));
                regen12 = SignedTrait::from16(peel(ref rest, N16));
                break;
            }
        }
        // The header: profession and attribute 0–15, kind, energy, adrenaline, activation,
        // recharge.
        let (mut rest, _) = DivRem::div_rem(header, N16);
        let kind = peel(ref rest, N8);
        let _energy = peel(ref rest, N8);
        let adrenaline = peel(ref rest, N8);
        let activation = peel(ref rest, N16);
        let recharge = peel(ref rest, N16);
        let range = peel(ref rest, N8);
        SkillSheet {
            id,
            kind: kind.try_into().unwrap(),
            adrenaline: adrenaline.try_into().unwrap(),
            activation: activation.try_into().unwrap(),
            recharge: recharge.try_into().unwrap(),
            regen0,
            regen12,
            range: range.try_into().unwrap(),
            entry1: first,
            entry2: second,
            entry3: third,
        }
    }

    /// Its `REGENERATION` pips at `rank` (§2.2).
    #[inline(always)]
    fn regen(self: @SkillSheet, rank: u8) -> i32 {
        EntryTrait::line(*self.regen0, *self.regen12, rank)
    }

    /// Its entry 0–2 decoded from the packed field: the naive executor's read at each use, the
    /// measured pair of `Sheets.entries` (SPK-15's L3).
    fn entry(self: @SkillSheet, k: u32) -> Entry {
        let bits = if k == 0 {
            *self.entry1
        } else if k == 1 {
            *self.entry2
        } else {
            *self.entry3
        };
        EntryTrait::unpack(bits)
    }
}

#[generate_trait]
pub impl PotionSheetImpl of PotionSheetTrait {
    fn new(id: u32, item: @Item) -> PotionSheet {
        let regen = if *item.entry.kind == kind::REGENERATION {
            *item.entry.v0
        } else {
            0
        };
        PotionSheet {
            id, regen, entry: item.entry.pack(), range: *item.range, strength: *item.strength,
        }
    }

    /// The sheet of potion `id` read from its record's part (`models::item` layout: the entry in
    /// the high limb's 97 low bits, then the range and the strength); `new` on the unpacked record
    /// is its oracle.
    fn read(id: u32, parts: Span<felt252>) -> PotionSheet {
        let (_, high) = limbs(*parts[0]);
        let (above, entry) = DivRem::div_rem(high, ENTRY_BOUND.try_into().unwrap());
        let (strength, range) = DivRem::div_rem(above, N8);
        let mut rest = entry;
        let regen = if peel(ref rest, N8) == kind::REGENERATION.into() {
            let _ = peel(ref rest, N8);
            SignedTrait::from16(peel(ref rest, N16))
        } else {
            0
        };
        PotionSheet {
            id,
            regen,
            entry,
            range: range.try_into().unwrap(),
            strength: strength.try_into().unwrap(),
        }
    }
}

#[generate_trait]
pub impl CasteSheetImpl of CasteSheetTrait {
    fn new(id: u16, caste: @Caste) -> CasteSheet {
        CasteSheet {
            id,
            health: *caste.health,
            health_regen: *caste.health_regen,
            energy: *caste.energy,
            energy_regen: *caste.energy_regen,
            weapon_ticks: *caste.weapon.ticks,
            skills: *caste.skills,
            armor: *caste.armor,
            armor_vs: Self::pack_vs(*caste.armor_vs),
            weapon: *caste.weapon.class,
            weapon_damage: (*caste.weapon.damage).try_into().unwrap(),
            damage_type: *caste.weapon.damage_type,
            weapon_range: *caste.weapon.range,
            rank: *caste.rank,
        }
    }

    /// The nine armors by damage type in 6-bit lanes, type `t` at `6 (t − 1)` (the record's).
    fn pack_vs(armor_vs: [u8; 9]) -> u64 {
        let mut packed: u64 = 0;
        let mut shift: u64 = 1;
        for vs in armor_vs.span() {
            packed += (*vs).into() * shift;
            shift *= 0x40;
        }
        packed
    }

    /// Its armor against damage type 1–9 (FX-23); 0 for none.
    #[inline(always)]
    fn armor_vs(self: @CasteSheet, damage_type: u8) -> u8 {
        if damage_type == 0 || damage_type > damage::LAST {
            return 0;
        }
        let shift = *VS_LANES.span()[(damage_type - 1).into()];
        let (above, _) = DivRem::div_rem(*self.armor_vs, shift.try_into().unwrap());
        let (_, vs) = DivRem::div_rem(above, 0x40);
        vs.try_into().unwrap()
    }

    /// The sheet of caste `id` read from its record's 2 parts (`models::caste` layout: the
    /// weapon's ticks at bit 72); `new` on the unpacked record is its oracle.
    fn read(id: u16, parts: Span<felt252>) -> CasteSheet {
        let (low, high) = limbs(*parts[0]);
        let (skills, _) = limbs(*parts[1]);
        // Tier and AI profile 0–15, the health multiplier, its regeneration, the armor; the
        // weapon's class, damage, type, ticks and range 48–79; energy and its regeneration, the
        // flee threshold, the rank 104–107. The high limb: the armor by type, 54 bits.
        let (mut rest, _) = DivRem::div_rem(low, N16);
        let health = peel(ref rest, N16);
        let health_regen = peel(ref rest, N8);
        let armor = peel(ref rest, N8);
        let weapon = peel(ref rest, N4);
        let weapon_damage = peel(ref rest, N16);
        let damage_type = peel(ref rest, N4);
        let weapon_ticks = peel(ref rest, N4);
        let weapon_range = peel(ref rest, N4);
        let energy = peel(ref rest, N8);
        let energy_regen = peel(ref rest, N8);
        let _flee = peel(ref rest, N8);
        let rank = peel(ref rest, N4);
        let (_, armor_vs) = DivRem::div_rem(high, VS_BOUND.try_into().unwrap());
        let mut rest = skills;
        let first = peel(ref rest, N16);
        let second = peel(ref rest, N16);
        let third = peel(ref rest, N16);
        let fourth = peel(ref rest, N16);
        CasteSheet {
            id,
            health: health.try_into().unwrap(),
            health_regen: health_regen.try_into().unwrap(),
            energy: energy.try_into().unwrap(),
            energy_regen: energy_regen.try_into().unwrap(),
            weapon_ticks: weapon_ticks.try_into().unwrap(),
            skills: [
                first.try_into().unwrap(), second.try_into().unwrap(), third.try_into().unwrap(),
                fourth.try_into().unwrap(),
            ],
            armor: armor.try_into().unwrap(),
            armor_vs: armor_vs.try_into().unwrap(),
            weapon: weapon.try_into().unwrap(),
            weapon_damage: weapon_damage.try_into().unwrap(),
            damage_type: damage_type.try_into().unwrap(),
            weapon_range: weapon_range.try_into().unwrap(),
            rank: rank.try_into().unwrap(),
        }
    }

    /// A goblin's max health at `level`: the adventurer's formula (design/03, `100 + 20 × (level
    /// − 1)`) times the caste's multiplier in percent (design/05, design/19 §7.3), truncated.
    #[inline(always)]
    fn max_health(self: @CasteSheet, level: u8) -> u32 {
        let base: u32 = 80 + 20 * level.into();
        base * (*self.health).into() / 100
    }
}

#[generate_trait]
pub impl ContentImpl of ContentTrait {
    /// The call's sheets and the index its loads read (CBT-02d): the index built once, each
    /// caste's kit derived once from it.
    fn index(self: @Content) -> (Sheets, Index) {
        let mut index = IndexTrait::new(self);
        let mut kits = array![];
        for caste in *self.castes {
            kits.append(index.kit(caste, *self.skills));
        }
        let sheets = Sheets {
            skills: *self.skills,
            potions: *self.potions,
            castes: *self.castes,
            kits: kits.span(),
            entries: Self::entries(*self.skills),
            potion_entries: Self::potion_entries(*self.potions),
        };
        (sheets, index)
    }

    /// Every skill's three entries, decoded once a call (SPK-15's L3): an entry after an empty one
    /// is empty (§2.1, the pipeline refuses a gap), so it is not decoded.
    fn entries(skills: Span<SkillSheet>) -> Span<Entry> {
        let mut entries = array![];
        let none: Entry = Default::default();
        for sheet in skills {
            if *sheet.entry1 == 0 {
                entries.append(none);
                entries.append(none);
                entries.append(none);
                continue;
            }
            entries.append(EntryTrait::unpack(*sheet.entry1));
            if *sheet.entry2 == 0 {
                entries.append(none);
                entries.append(none);
                continue;
            }
            entries.append(EntryTrait::unpack(*sheet.entry2));
            if *sheet.entry3 == 0 {
                entries.append(none);
            } else {
                entries.append(EntryTrait::unpack(*sheet.entry3));
            }
        }
        entries.span()
    }

    /// Every potion's entry, decoded once a call.
    fn potion_entries(potions: Span<PotionSheet>) -> Span<Entry> {
        let mut entries = array![];
        for sheet in potions {
            entries.append(EntryTrait::unpack(*sheet.entry));
        }
        entries.span()
    }

    /// The call's sheets alone, the index dropped.
    fn sheets(self: @Content) -> Sheets {
        let (sheets, _) = self.index();
        sheets
    }
}

#[generate_trait]
pub impl IndexImpl of IndexTrait {
    /// Every record's position, keyed by its id. The lists are read from their ends, so that of two
    /// records with one id the first is kept, as a scan finds it.
    fn new(content: @Content) -> Index {
        assert(content.skills.len() <= MAX_SKILLS, errors::SKILLS);
        let mut positions: Felt252Dict<u32> = Default::default();
        let mut skills = *content.skills;
        let mut at = skills.len();
        while let Some(sheet) = skills.pop_back() {
            positions.insert((*sheet.id).into(), at);
            at -= 1;
        }
        let mut castes = *content.castes;
        let mut at = castes.len();
        while let Some(sheet) = castes.pop_back() {
            positions.insert((*sheet.id).into() + CASTE_KEY, at);
            at -= 1;
        }
        let mut potions = *content.potions;
        let mut at = potions.len();
        while let Some(sheet) = potions.pop_back() {
            positions.insert((*sheet.id).into() + POTION_KEY, at);
            at -= 1;
        }
        Index { positions }
    }

    /// The position of skill `id`. The content holds every skill the batch can need (design/19
    /// §7.2, the registry reads), so a missing one is the caller's error.
    fn skill(ref self: Index, id: u16) -> u32 {
        let key: felt252 = id.into();
        let at = Felt252DictTrait::get(ref self.positions, key);
        assert(at != 0, errors::NO_SKILL);
        at - 1
    }

    fn caste(ref self: Index, id: u16) -> u32 {
        let key: felt252 = id.into();
        let at = Felt252DictTrait::get(ref self.positions, key + CASTE_KEY);
        assert(at != 0, errors::NO_CASTE);
        at - 1
    }

    fn potion(ref self: Index, id: u32) -> u32 {
        let key: felt252 = id.into();
        let at = Felt252DictTrait::get(ref self.positions, key + POTION_KEY);
        assert(at != 0, errors::NO_POTION);
        at - 1
    }

    /// A caste's kit: its skills' positions and its goblins' adrenaline cap, their skills' highest
    /// cost in quarters, at most 252 (§5.12; DS-18 bounds a caste skill at 63 strikes). A skill
    /// missing from the content is refused when a goblin of the caste loads (`GoblinTrait::load`),
    /// not here: a caste no goblin of the call holds reads nothing.
    fn kit(ref self: Index, caste: @CasteSheet, skills: Span<SkillSheet>) -> Kit {
        let mut at: Array<u32> = array![];
        let mut cap: u16 = 0;
        for id in caste.skills.span() {
            if *id == 0 {
                at.append(ABSENT);
                continue;
            }
            let key: felt252 = (*id).into();
            let position = Felt252DictTrait::get(ref self.positions, key);
            if position == 0 {
                at.append(MISSING);
                continue;
            }
            at.append(position - 1);
            let cost: u16 = (*skills[position - 1].adrenaline).into() * 4;
            if cost > cap {
                cap = cost;
            }
        }
        if cap > MAX_GOBLIN_ADRENALINE.into() {
            cap = MAX_GOBLIN_ADRENALINE.into();
        }
        Kit {
            skills: [*at[0], *at[1], *at[2], *at[3]],
            cap: cap.try_into().unwrap(),
            weapon_ticks: *caste.weapon_ticks,
        }
    }
}

/// A caste skill the content does not hold (`IndexTrait::kit`).
pub const MISSING: u32 = 0xFFFFFFFE;

#[generate_trait]
pub impl SheetsImpl of SheetsTrait {
    /// The sheet of skill `slot` of the caste at `caste_at`, through its kit.
    #[inline(always)]
    fn caste_skill(self: @Sheets, caste_at: u32, slot: u8) -> @SkillSheet {
        let kit = self.kits[caste_at];
        self.skills[*kit.skills.span()[slot.into()]]
    }
}

/// The content's unit tests (CBT-02, CBT-02d; D-167): the sheets read from their records, the
/// index and the kits.
#[cfg(test)]
mod tests {
    use crate::content::Record;
    use crate::models::caste::{CasteRecord, CasteTrait, WeaponTrait};
    use crate::models::index::{Caste, Item, Skill};
    use crate::models::item::{ItemRecord, ItemTrait, class as item_class};
    use crate::models::skill::{SkillRecord, SkillTrait};
    use crate::types::combat::{skill_kind, weapon};
    use crate::types::effect::{Entry, EntryTrait, filter, kind, shape, target};
    use crate::types::world::fixtures::{Fixture, SMASH};
    use super::{
        ABSENT, CasteSheetTrait, Content, ContentTrait, IndexTrait, Kit, MISSING, PotionSheet,
        PotionSheetTrait, SkillSheetTrait,
    };

    // The sheets read from a record's parts (only the fields the tick reads) agree with the sheets
    // of the fully unpacked record, their oracle: a regeneration in entry 1 or 2, falling with rank
    // or negative, none; a potion with and without one; a caste.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 1859025)] // ceil(1.05 × 1770500 measured)
    fn test_sheets_read_oracle() {
        let regen = EntryTrait::new(
            kind::REGENERATION, 0, 2, 6, 5, 5, 0, target::SELF, shape::SINGLE, filter::ALLIES, 0, 0,
        );
        let skill = SkillTrait::new(
            1,
            1,
            skill_kind::SPELL,
            10,
            0,
            1,
            12,
            0,
            target::SELF,
            false,
            [regen, Default::default(), Default::default()],
        );
        let caste = CasteTrait::new(
            4,
            1,
            150,
            10,
            40,
            [0; 9],
            WeaponTrait::new(weapon::MAUL, 30, 3, 2, 1),
            10,
            1,
            [SMASH, 25, 26, 27],
            12,
            30,
            0,
            false,
        );
        let parts = Record::<Skill>::pack(@skill);
        assert(SkillSheetTrait::read(5, parts) == SkillSheetTrait::new(5, @skill), 'skill');
        let parts = Record::<Caste>::pack(@caste);
        assert(CasteSheetTrait::read(1, parts) == CasteSheetTrait::new(1, @caste), 'caste');
        let damage = EntryTrait::new(
            kind::DAMAGE, 4, 10, 40, 0, 0, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
        );
        let decay = EntryTrait::new(
            kind::REGENERATION, 0, 4, -10, 5, 5, 0, target::FOE, shape::SINGLE, filter::FOES, 0, 0,
        );
        let none: Entry = Default::default();
        for entries in array![[damage, decay, none], [damage, none, none]] {
            let skill = SkillTrait::new(
                1, 1, skill_kind::HEX, 10, 0, 2, 20, 5, target::FOE, false, entries,
            );
            let parts = Record::<Skill>::pack(@skill);
            let read = SkillSheetTrait::read(9, parts);
            assert(read == SkillSheetTrait::new(9, @skill), 'skill entries');
        }
        let tonic = EntryTrait::new(
            kind::REGENERATION,
            0,
            -3,
            -3,
            8,
            8,
            0,
            target::SELF,
            shape::SINGLE,
            filter::ALLIES,
            0,
            0,
        );
        let bomb = EntryTrait::new(
            kind::DAMAGE, 4, 30, 30, 0, 0, 0, target::TILE, shape::DISC_1, filter::FOES, 0, 0,
        );
        for entry in array![tonic, bomb] {
            let item = ItemTrait::new(item_class::POTION, 1, 1, 10, 0, entry, 3, 20);
            let parts = Record::<Item>::pack(@item);
            assert(PotionSheetTrait::read(7, parts) == PotionSheetTrait::new(7, @item), 'potion');
        }
    }

    // CBT-02d: the index finds every record's position, of each kind apart (a skill, a caste and a
    // potion may share an id); of two records with one id, the first, as a scan finds it.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 769776)] // ceil(1.05 × 733120 measured)
    fn test_index_positions() {
        let mut twin = Fixture::skill(3, skill_kind::SHOUT, 0, 1);
        twin.recharge = 99;
        let mut skills = array![];
        for id in 1..9_u16 {
            skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
        }
        skills.append(twin);
        let content = Content {
            skills: skills.span(),
            potions: array![
                PotionSheet { id: 2, regen: 1, ..Default::default() },
                PotionSheet { id: 70000, regen: 2, ..Default::default() },
            ]
                .span(),
            castes: array![].span(),
        };
        let (sheets, mut index) = content.index();
        assert(index.skill(1) == 0 && index.skill(8) == 7, 'skills');
        assert(index.skill(3) == 2 && *sheets.skills[index.skill(3)].recharge == 10, 'the first');
        assert(index.potion(2) == 0 && index.potion(70000) == 1, 'potions');
        let content = Fixture::content();
        let (_, mut index) = content.index();
        assert(index.caste(1) == 0 && index.caste(2) == 1, 'castes');
        assert(index.skill(24) == 8 && index.skill(31) == 15, 'caste skills');
    }

    #[test]
    #[should_panic(expected: 'tick: skill not in content')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 481877)] // ceil(1.05 × 458930 measured)
    fn test_index_no_skill() {
        let (_, mut index) = Fixture::content().index();
        index.skill(9);
    }

    #[test]
    #[should_panic(expected: 'tick: caste not in content')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 481877)] // ceil(1.05 × 458930 measured)
    fn test_index_no_caste() {
        let (_, mut index) = Fixture::content().index();
        index.caste(3);
    }

    #[test]
    #[should_panic(expected: 'tick: potion not in content')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 481877)] // ceil(1.05 × 458930 measured)
    fn test_index_no_potion() {
        let (_, mut index) = Fixture::content().index();
        index.potion(100);
    }

    // CBT-02d: each caste's kit, derived once: its skills' positions (`ABSENT` for an empty slot,
    // `MISSING` for one the content lacks) and its goblins' adrenaline cap, their highest cost in
    // quarters, at most 252.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 209496)] // ceil(1.05 × 199520 measured)
    fn test_kits() {
        let mut costly = Fixture::skill(24, skill_kind::ATTACK, 3, 10);
        costly.adrenaline = 5;
        let mut heavy = Fixture::skill(30, skill_kind::ATTACK, 0, 0);
        heavy.adrenaline = 63;
        let mut hob = Fixture::caste(1, 1);
        hob.skills = [25, 24, 0, 26];
        let mut runt = Fixture::caste(2, 1);
        runt.skills = [30, 99, 0, 0];
        let content = Content {
            skills: array![
                Fixture::skill(26, skill_kind::SHOUT, 0, 20), costly,
                Fixture::skill(25, skill_kind::SPELL, 2, 8), heavy,
            ]
                .span(),
            potions: array![].span(),
            castes: array![hob, runt].span(),
        };
        let sheets = content.sheets();
        let hob = Kit { skills: [2, 1, ABSENT, 0], cap: 20, weapon_ticks: 1 };
        let runt = Kit { skills: [3, MISSING, ABSENT, ABSENT], cap: 252, weapon_ticks: 1 };
        assert(*sheets.kits[0] == hob && *sheets.kits[1] == runt, 'kits');
    }
}
