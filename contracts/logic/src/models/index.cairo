//! The world's registry records, together (D-143, docs/CAIRO.md §7): `REGION`, `LOCATION`,
//! `GATE` and both forms of `OUTLINE` (design/01 *World structure*, ADR-0006 *Outlines*;
//! docs/architecture/ENG-01-interfaces.md §3.5, where every width is justified). Each model's file
//! holds its constructor, its checks, its errors and its packing into the record's parts
//! (`content::Record`), which follows the packing rules: no field straddles bit 128, `LIVE` at bit
//! 250 in part 0, a value wider than its field refused.
//!
//! Widths:
//! - a content id is a `u16`, as every registry id the frozen layouts hold (`Header.location`,
//!   the bar's skills, a pack's template);
//! - a quest is quiver's id, a `u32` (the registry's id space);
//! - a level, a rank, a count of floors or chunks is a `u8`;
//! - a location is at most 15 × 15 chunks (ENG-01 §3.2): its width and height are 1 to 15, a
//! chunk
//!   index `15 cy + cx` and a tile index in a chunk `15 row + column` are below 225.

use crate::packing::Lanes16;
use crate::types::effect::Entry;
use crate::types::passive::Passive;

/// `REGION`, 1 part (design/01 *Horizontal scaling*).
/// town 0–15 · book 16–31 · first location 32–47 · name 128–247 (a short string of at
/// most 15 characters) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Region {
    /// The region's town, a `LOCATION` of kind `TOWN`.
    pub town: u16,
    /// Its alchemy book (`BOOK`; design/07); 0 for none.
    pub book: u16,
    /// The first of its locations (design/01: "list of locations").
    pub first_location: u16,
    /// A short string of at most 15 characters.
    pub name: felt252,
}

/// `LOCATION`, 2 parts (design/01, design/17, design/18, ADR-0006).
/// Part 0: type 0–7 · region 8–23 · biome 24–31 · level min 32–39 · level max 40–47
/// · rank required 48–55 · width 56–63 · height 64–71 (chunks, 1–15) · `N` 72–79 ·
/// floors 80–87 · next floor 88–103 · spawn table 104–119 · sealed 120–127 · entry
/// chunk 128–135 · entry tile 136–143 · `LIVE`.
/// Part 1: the set pieces, up to 15 `SET_PIECE` ids (`Lanes16`, 0 for none) · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Location {
    /// `location::kind::TOWN` … `TRIAL`.
    pub kind: u8,
    pub region: u16,
    /// `location::biome::MEADOW` … `RUIN`.
    pub biome: u8,
    /// The level band of its goblins (design/01: "levels within the zone's band").
    pub level_min: u8,
    pub level_max: u8,
    /// The rank required to enter (0 none; design/06, design/17).
    pub rank: u8,
    /// Its extent in chunks, 1 to 15 each (ENG-01 §3.2).
    pub width: u8,
    pub height: u8,
    /// A dungeon floor's target number of chunks, 6 to 12 (ADR-0006); 0 for a zone.
    pub target: u8,
    /// The floors of its dungeon (design/01: D1 has 3; design/17: up to 5).
    pub floors: u8,
    /// The location of the next floor; 0 on the last floor and outside dungeons.
    pub next_floor: u16,
    pub spawn_table: u16,
    /// A sealed Red Rift: no travel back (design/17).
    pub sealed: bool,
    /// Where an adventurer enters: chunk `15 cy + cx`, tile `15 row + column`.
    pub entry_chunk: u8,
    pub entry_tile: u8,
    /// The authored chunks its quotas may place (ADR-0006, *Set pieces*).
    pub set_pieces: Lanes16,
}

/// `GATE`, 1 part (design/01 *Connectivity*, ADR-0006: a gate is an anchor on the outline).
/// source 0–15 · destination 16–31 · source anchor chunk 32–39, tile 40–47 · destination
/// entry chunk 48–55, tile 56–63 · kind 64–71 · rank required 72–79 · quest required
/// 80–111 · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Gate {
    pub source: u16,
    pub destination: u16,
    /// Where the gate stands in the source location (0 and 0 in a hub, which has no map).
    pub anchor_chunk: u8,
    pub anchor_tile: u8,
    /// Where it leads in the destination (0 and 0 into a hub).
    pub entry_chunk: u8,
    pub entry_tile: u8,
    /// `gate::kind::HUB` … `RIFT`.
    pub kind: u8,
    /// The rank required (0 none).
    pub rank: u8,
    /// The quest required (quiver's id; 0 none).
    pub quest: u32,
}

/// `OUTLINE`, 1 part, both forms (ADR-0006, *Outlines*): at id `Outline::id(location,
/// CHUNK_SET)` the zone's chunk set, bit `15 cy + cx`; at id `Outline::id(location, chunk)` the
/// tile mask of a border chunk, bit `15 row + column` (1: the tile belongs to the zone). Bits
/// 0–127 in `low`, 128–224 in `high` · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Outline {
    pub low: u128,
    pub high: u128,
}

// The combat's records (CBT-01; design/19 §7.2, §7.3; ENG-01 §3.5). Their entries and passives
// are `types::effect::Entry` (97 bits) and `types::passive::Passive` (53 bits).

/// `SKILL`, 2 parts (design/03 *Skill definition*, design/19 §7.2).
/// Part 0 low, the header: profession 0–7 · attribute 8–15 · kind 16–23 · energy 24–31
/// ·
/// adrenaline 32–39 · activation 40–55 · recharge 56–71 · range 72–79 · target 80–81
/// · elite 82 (83 bits) · part 0 high: entry 1 · part 1 low: entry 2 · part 1 high: entry 3 ·
/// `LIVE` in both.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Skill {
    pub profession: u8,
    /// The attribute whose rank scales it (design/03).
    pub attribute: u8,
    /// `combat::skill_kind::ATTACK` … `SEAL_OF_CAPTURE`.
    pub kind: u8,
    /// Energy cost.
    pub energy: u8,
    /// Adrenaline cost, in strikes.
    pub adrenaline: u8,
    /// Ticks spent activating (0: instant), and before reuse; at most `MAX_BASE_DURATION`.
    pub activation: u16,
    pub recharge: u16,
    /// In tiles.
    pub range: u8,
    /// `effect::target::SELF` … `TILE`: what the action names.
    pub target: u8,
    pub elite: bool,
    /// Up to 3 entries, packed from the first without a gap (design/19 §2.1).
    pub entries: [Entry; 3],
}

/// `ITEM`, 1 part (ENG-01 §3.5, design/07, design/19 §7.2, FX-18, FX-28).
/// low: class 0–7 · region 8–23 · rarity 24–31 · value 32–63 · book index 64–71 (72
/// bits) ·
/// high: the potion's entry 128–224 · range 225–232 · bomb strength 233–240 (113 bits) ·
/// `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Item {
    /// `item::class::INGREDIENT` … `FAILED_BREW`.
    pub class: u8,
    pub region: u16,
    pub rarity: u8,
    /// In gold.
    pub value: u32,
    /// Its index in its region's alchemy book (an ingredient).
    pub book_index: u8,
    /// A potion's one entry; empty for any other class.
    pub entry: Entry,
    /// In tiles (a thrown bomb).
    pub range: u8,
    /// A bomb's strength (FX-28: from its recipe).
    pub strength: u8,
}

/// `MODIFIER`, 1 part (design/15 Q-4, design/19 §4).
/// low: slot type 0–7 · piece 8–15 · high: benefit 128–180 · cost 181–233 (53 bits each)
/// ·
/// `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Modifier {
    /// `modifier::slot::PREFIX` … `RUNE`.
    pub slot: u8,
    /// An insignia's armor piece, `base::slot::CHEST` … `FEET` (DS-23, D-160: its health bound is
    /// the piece's); 0 for every other slot type.
    pub piece: u8,
    /// Its rolled value is the item's `ItemMods` byte.
    pub benefit: Passive,
    /// Fixed (`min = max`); id 0 for a modifier without a cost.
    pub cost: Passive,
}

/// `BASE`, 2 parts (design/15; ENG-01 §3.5). CBT-08a lays out only its prefix, from bit 0 of
/// part 0: what the creator of an item copies into `ItemBase` (D-158), so that `set_build` reads
/// no `BASE`. The lot that lays out the rest (class, profession, damage by requirement, rating,
/// look) appends to it; until then this model covers the prefix only, and its packer writes every
/// other bit 0: part 0 low: slot 0–7 · hands 8–15 · `LIVE` in both parts.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Base {
    /// `base::slot::WEAPON` … `FEET`: `equipped`'s lane plus one.
    pub slot: u8,
    /// A weapon's hands (design/15, *Weapons*): 1, or 2 for a maul, a bow or a staff; 0 for
    /// anything else.
    pub hands: u8,
}

/// `ARMOR_SET`, 1 part (design/15 D-45, design/19 §7.2).
/// low: 5 piece bases, `u16` each, at 0, 16, 32, 48, 64 (chest, legs, head, hands, feet) · high:
/// the 3-piece bonus 128–180 · the 5-piece bonus 181–233 · `LIVE`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct ArmorSet {
    /// `BASE` ids.
    pub pieces: [u16; 5],
    pub bonuses: [Passive; 2],
}

/// A caste's weapon, inline (design/19 §7.3: no `BASE` read), 32 bits: class 0–3 · damage
/// 4–19 ·
/// damage type 20–23 · ticks 24–27 · range 28–31.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Weapon {
    /// `combat::weapon::SWORD` … `WAND`.
    pub class: u8,
    pub damage: u16,
    /// `combat::damage::SLASHING` … `HOLY`.
    pub damage_type: u8,
    pub ticks: u8,
    pub range: u8,
}

/// `CASTE`, 2 parts: the caste sheet's shape (design/19 §7.3; DES-06 fills the values), 243 bits.
/// Part 0 low: tier 0–7 · AI profile 8–15 · health multiplier 16–31 · health regeneration
/// + 10 32–39 · armor 40–47 · weapon 48–79 · energy 80–87 · energy regeneration 88–95
/// · flee threshold 96–103 · rank 104–107 · boss 108 (109 bits) · part 0 high: armor per
/// damage type 128–181 (9 ×
/// 6, type `t` at `128 + 6 (t − 1)`) · loot table 182–197 (70 bits) · part 1 low: 4 skills
/// 0–63 (`u16` each, in priority order) · part 1 high: empty · `LIVE` in both.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Caste {
    /// 1–6.
    pub tier: u8,
    /// design/05's profiles.
    pub ai: u8,
    /// Percent.
    pub health: u16,
    /// Signed pips −10…+10, stored + 10 (0–20; design/19 §5.8).
    pub health_regen: u8,
    pub armor: u8,
    /// Saturated at 63 (FX-23); index `damage type − 1`.
    pub armor_vs: [u8; 9],
    pub weapon: Weapon,
    /// At most 85 (stored in thirds in `GoblinState`: 85 × 3 = 255); its regeneration in pips.
    pub energy: u8,
    pub energy_regen: u8,
    /// Its skills, in priority order (`SKILL` ids, 0 none).
    pub skills: [u16; 4],
    /// The rank of its skills, 0–15 (design/19 §2.2).
    pub rank: u8,
    /// Percent of its max health below which it flees.
    pub flee: u8,
    pub loot_table: u16,
    pub boss: bool,
}

// The actors of a world tick (CBT-02, ENG-01 §3.2): their stored words, as `Instances` passes
// them to the tick's library call, and their view inside the call.

/// A member's stored words, in and out of the call: the four that change in play, and the
/// snapshot's `MemberStats`, `MemberBar`, `MemberKit`, read only.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct MemberWords {
    pub state: felt252,
    pub timers: felt252,
    pub effects: felt252,
    pub recharges: felt252,
    pub stats: felt252,
    pub bar: felt252,
    pub kit: felt252,
}

/// A member inside the call: its hot fields, what it derives once, and its words (the recharges
/// are read and written in `words.recharges` directly: only at an activation's end).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Member {
    pub status: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u16,
    /// In quarter strikes.
    pub adrenaline: u16,
    pub flags: u8,
    /// The bar slot activated (`NO_SLOT` for none), its target, whether it is a tile, `A`.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_tile: u8,
    pub act_deadline: u32,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub knocked: u32,
    /// Each effect slot's deadline (read only in the ticks) and `REGENERATION` pips.
    pub effect_deadlines: [u32; 4],
    pub effect_regen: [i8; 4],
    pub max_health: u16,
    /// In thirds.
    pub max_energy: u16,
    /// Pips, signed.
    pub health_regen: i8,
    /// Pips: thirds a tick.
    pub energy_regen: u8,
    /// Its adrenaline gains' cap in quarters: the highest adrenaline cost on its bar (design/19
    /// §5.12, FX-12), derived once.
    pub adrenaline_cap: u16,
    /// Its bar's skills' positions in the content (`types::tick::Sheets.skills`), found once at its
    /// load (CBT-02d): slot `s` in bits `16 s`, `ABSENT_LANE` for an empty slot.
    pub bar_at: u128,
    /// Each held effect's carrier's position in the content, found once at its load and set when
    /// the executor holds one (CBT-05a): a skill's in `Sheets.skills`, a potion's in
    /// `Sheets.potions`; slot `s` in bits `16 s`, `ABSENT_LANE` for an empty slot.
    pub effect_at: u128,
    pub words: MemberWords,
}

/// A goblin's stored words, in and out of the call, with its entity id and whether it is in the
/// tick's awake set (design/19 §5.2; not stored).
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct GoblinWords {
    pub entity: u16,
    pub awake: bool,
    pub state: felt252,
    pub timers: felt252,
}

/// A goblin inside the call: its hot fields, what it derives once, and its words (the recharges
/// are read and written in `state` directly).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Goblin {
    pub entity: u16,
    pub awake: bool,
    pub ai: u8,
    pub health: u16,
    /// In thirds.
    pub energy: u8,
    /// In quarter strikes.
    pub adrenaline: u8,
    pub caste: u16,
    /// The activation field (§5.2): a caste skill 0–3 with `A`, `activation::RECOVERING` with
    /// `B`, or `activation::NONE`; its target.
    pub act_slot: u8,
    pub act_target: u16,
    pub act_deadline: u32,
    pub bleeding: u32,
    pub poison: u32,
    pub burning: u32,
    pub knocked: u32,
    pub effect_deadline: u32,
    pub effect_regen: i8,
    pub max_health: u16,
    /// Pips, signed.
    pub health_regen: i8,
    /// In thirds.
    pub max_energy: u8,
    pub energy_regen: u8,
    /// Its adrenaline gains' cap in quarters: its caste skills' highest cost, at most the field's
    /// 252 (design/19 §5.12), derived once.
    pub adrenaline_cap: u8,
    /// Its caste's position in the content (`types::tick::Sheets.castes` and `.kits`), found once
    /// at its load (CBT-02d).
    pub caste_at: u32,
    /// Its held effect's skill's position in `Sheets.skills` (CBT-05a), `ABSENT` for none.
    pub effect_at: u32,
    pub state: felt252,
    pub timers: felt252,
}
