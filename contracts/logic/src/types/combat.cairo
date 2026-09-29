//! The enumerations of combat that are not an effect entry's own fields (design/19, frozen by
//! CBT-01, X-2): conditions, damage types, skill kinds, weapon classes, hit classes, the chunk
//! objects a trap is, the goblin's activation field, and who placed a trap. Content refers to them
//! by id; an id never changes meaning once frozen.

/// Conditions, ids 1–9 (design/19 §3.2, design/04's order). 1–5 are the MVP's, stored as
/// deadlines in `MemberTimers` and `GoblinTimers`; 6–9 have no MVP source (FX-22: one more word
/// per member and per goblin when they ship).
pub mod condition {
    pub const BLEEDING: u8 = 1;
    pub const POISON: u8 = 2;
    pub const BURNING: u8 = 3;
    pub const CRIPPLED: u8 = 4;
    pub const KNOCKED_DOWN: u8 = 5;
    pub const DAZED: u8 = 6;
    pub const BLIND: u8 = 7;
    pub const WEAKNESS: u8 = 8;
    pub const DEEP_WOUND: u8 = 9;
    /// The last condition id.
    pub const LAST: u8 = 9;
    /// The last condition of the MVP (the five a timer word stores).
    pub const LAST_MVP: u8 = 5;
    /// Health pips of the conditions that degenerate (§5.8 step 1), subtracted.
    pub const BLEEDING_PIPS: i32 = 3;
    pub const POISON_PIPS: i32 = 4;
    pub const BURNING_PIPS: i32 = 7;
}

/// Damage types, ids 1–9 (design/19 §3.1, design/04's order): 1–3 physical, 4–7 elemental, 8–9
/// neither (FX-23).
pub mod damage {
    pub const SLASHING: u8 = 1;
    pub const PIERCING: u8 = 2;
    pub const BLUNT: u8 = 3;
    pub const FIRE: u8 = 4;
    pub const COLD: u8 = 5;
    pub const LIGHTNING: u8 = 6;
    pub const EARTH: u8 = 7;
    pub const SHADOW: u8 = 8;
    pub const HOLY: u8 = 9;
    /// The last damage type; there are `LAST` per-type armors (`ARMOR_VS`, 9 × 6 bits).
    pub const LAST: u8 = 9;
}

/// Skill kinds, ids 1–12 (design/19 §3.4, design/03's order; 11 is design/03's generic `Skill`,
/// FX-25; 12 is post-MVP, FX-26).
pub mod skill_kind {
    pub const ATTACK: u8 = 1;
    pub const SPELL: u8 = 2;
    pub const HEX: u8 = 3;
    pub const ENCHANTMENT: u8 = 4;
    pub const STANCE: u8 = 5;
    pub const SHOUT: u8 = 6;
    pub const SIGNET: u8 = 7;
    pub const PREPARATION: u8 = 8;
    pub const TRAP: u8 = 9;
    pub const GLYPH: u8 = 10;
    pub const SKILL: u8 = 11;
    pub const SEAL_OF_CAPTURE: u8 = 12;
    pub const LAST: u8 = 12;
    /// Packs within this many tiles a shout alerts (design/18).
    pub const SHOUT_ALERT_RANGE: u8 = 8;
}

/// Weapon classes (design/15's table; design/19 §7.2: `MemberStats.weapon` is the class, a
/// caste's weapon holds it inline). 0 is none.
pub mod weapon {
    pub const SWORD: u8 = 1;
    pub const AXE: u8 = 2;
    pub const MAUL: u8 = 3;
    pub const BOW: u8 = 4;
    pub const STAFF: u8 = 5;
    pub const WAND: u8 = 6;
    pub const LAST: u8 = 6;
}

/// Chunk object kinds that are traps (design/19 §5.11, §7.2): the generated terrain trap, whose
/// `param` is its `SKILL` id (FX-14), and the placed trap, whose `param` is its `Placer`.
pub mod object {
    pub const TERRAIN_TRAP: u8 = 4;
    pub const PLACED_TRAP: u8 = 9;
}

/// The goblin's activation field, `GoblinTimers.act_slot` (design/19 §5.2): a caste skill 0–3
/// being activated (deadline `A`), recovering (deadline `B`, FX-15), or none.
pub mod activation {
    /// The last caste skill slot: activating is `0..=LAST_SLOT`.
    pub const LAST_SLOT: u8 = 3;
    pub const RECOVERING: u8 = 254;
    pub const NONE: u8 = 255;
}

/// A hit's class (design/19 §5.4): what applies to it. Not stored; the executor's.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum HitClass {
    /// A weapon attack, or an attack skill (then also `ATTACK_SKILL` for scopes).
    Weapon,
    /// A `DAMAGE` entry of any other skill kind.
    Spell,
    /// A potion's `DAMAGE` entry (a bomb).
    Item,
    /// A trap's `DAMAGE` entry, placed or terrain.
    Trap,
}

/// Who placed a trap (design/19 §7.2, a placed trap's chunk-object `param`, 16 bits): bit 15 is
/// 0 for a member (member 0–7 at bits 0–2, bar slot 0–7 at bits 3–5) and 1 for a goblin (entity
/// − 8 at bits 0–11, at most 3,593 − 8 < 4,096; caste skill 0–3 at bits 12–13).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Placer {
    /// `(member, bar slot)`.
    Member: (u8, u8),
    /// `(entity, caste skill slot)`.
    Goblin: (u16, u8),
}

pub mod errors {
    pub const PLACER_MEMBER: felt252 = 'placer: member';
    pub const PLACER_SLOT: felt252 = 'placer: slot';
    pub const PLACER_ENTITY: felt252 = 'placer: entity';
}

const GOBLIN_BIT: u16 = 0x8000;
const FIRST_GOBLIN: u16 = 8;
const ENTITY_SIZE: u16 = 0x1000;

#[generate_trait]
pub impl PlacerImpl of PlacerTrait {
    /// The object's `param`; refuses a member above 7, a bar slot above 7, a goblin entity outside
    /// 8…4,103 or a caste skill above 3.
    fn param(self: @Placer) -> u16 {
        match *self {
            Placer::Member((
                member, slot,
            )) => {
                assert(member < 8, errors::PLACER_MEMBER);
                assert(slot < 8, errors::PLACER_SLOT);
                member.into() + slot.into() * 8
            },
            Placer::Goblin((
                entity, skill,
            )) => {
                assert(
                    entity >= FIRST_GOBLIN && entity - FIRST_GOBLIN < ENTITY_SIZE,
                    errors::PLACER_ENTITY,
                );
                assert(skill <= activation::LAST_SLOT, errors::PLACER_SLOT);
                GOBLIN_BIT + (entity - FIRST_GOBLIN) + skill.into() * ENTITY_SIZE
            },
        }
    }

    /// The placer of a placed trap's `param`.
    fn from_param(param: u16) -> Placer {
        if param >= GOBLIN_BIT {
            let (skill, entity) = DivRem::div_rem(param - GOBLIN_BIT, ENTITY_SIZE.try_into().unwrap());
            Placer::Goblin((entity + FIRST_GOBLIN, skill.try_into().unwrap()))
        } else {
            let (slot, member) = DivRem::div_rem(param, 8);
            Placer::Member((member.try_into().unwrap(), slot.try_into().unwrap()))
        }
    }
}
