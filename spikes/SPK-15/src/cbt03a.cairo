//! CBT-03a's hit, copied for measurement (SPK-15's brief: never by editing the branch).
//!
//! Sources, branch `feat/cbt-03a-hit` at commit `36bf2ba` (PR #229):
//! - `contracts/logic/src/types/hit.cairo`: everything above its `#[cfg(test)] mod tests`
//!   (`Hit`, `HitTarget`, `Landed`, `HitOutcome`, `HitTrait`, `HitTargetTrait`, `HitAssert`, the
//!   constants), its module documentation and tests left out;
//! - `contracts/logic/src/types/combat.cairo`: the `Arc` enum it adds.
//! The bodies are unchanged; only the `use` lines point at `grimworld_logic` and at `Arc` here.

/// The arc of the target a hit arrives from (design/04 *Facing and arcs*, D-41), for a target
/// facing `d`: front `d`, front-side `d ± 1`, rear-side `d ± 2` (the flank), back `d + 3`.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum Arc {
    Front,
    FrontSide,
    RearSide,
    Back,
}
use grimworld_logic::helpers::exp2::{Exp2, SHIFT};
use grimworld_logic::snapshot::STRENGTH_PER_RANK;
use grimworld_logic::types::combat::{HitClass, weapon};

/// A critical strike: +40 % (design/04).
pub const CRITICAL_PERCENT: i32 = 40;
/// The axe, from the rear-side and back arcs: +25 % (design/04).
pub const AXE_PERCENT: i32 = 25;
/// Weakness on the source: −33 % to its weapon hits (design/19 §3.2, **P**).
pub const WEAKNESS_PERCENT: i32 = -33;
/// The sum of the percents is never below −100 (D-140).
pub const MIN_PERCENT: i32 = -100;
/// Penetration is capped at 100 % (FX-9).
pub const PENETRATION_CAP: u32 = 100;
/// The damage of one hit is clamped to [0, 65,535] (D-140).
pub const MAX_DAMAGE: u64 = 65535;
/// Strength of a spell and a trap: 3 × level (design/04, FX-28).
pub const STRENGTH_PER_LEVEL: u16 = 3;
/// A weapon's damage below its requirement is divided by 3 (design/15).
pub const REQUIREMENT_DIVISOR: u32 = 3;
/// The largest base of a hit: a weapon's damage ≤ 255 and one `ATTACK_BONUS` ≤ 32,767
/// (design/20 §1.6, case B, DS-18, DS-20); a `DAMAGE` entry is ≤ 32,767. `base × table(80)` <
/// 2^34: a `u64`.
pub const MAX_BASE: u32 = 33022;
/// A `BLOCK`'s charges, 1…63 (design/19 §3.4); 0 is none held.
pub const MAX_BLOCK: u8 = 63;

pub mod errors {
    pub const BASE: felt252 = 'hit: base above its bound';
    pub const HEALTH: felt252 = 'hit: health above max';
    pub const BLOCK: felt252 = 'hit: block charges';
}

/// One hit and its source (design/19 §5.5): the class, the arc, the source's strength and base,
/// the percents and penetrations that apply, the source's state.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Hit {
    /// What applies to it (§5.4).
    pub class: HitClass,
    /// The source's weapon class (`combat::weapon`, 0 none): the axe's +25 %. `WEAPON` only.
    pub weapon: u8,
    /// The weapon's range is 1: evasion takes melee hits only (§3.4). `WEAPON` only.
    pub melee: bool,
    /// The arc of the target it arrives from (ENG-02). `WEAPON` only (FX-27).
    pub arc: Arc,
    /// The target is on the source's front tile (ENG-02): Blind's miss. `WEAPON` only.
    pub in_front: bool,
    /// The source's strength by class: `HitTrait::weapon_strength`, `level_strength`, or a bomb's
    /// recipe (§5.4, FX-28).
    pub strength: u16,
    /// The base damage: `HitTrait::weapon_base` for a weapon hit, the `DAMAGE` entry's value for
    /// another class; ≤ `MAX_BASE`.
    pub base: u32,
    /// The source's `DAMAGE_PERCENT` sums for this class (§7.2: plain weapon, attack skill or
    /// spell), unguarded and `ABOVE_HALF`. `WEAPON` and `SPELL` only (§5.4).
    pub percent: i16,
    pub percent_above_half: i16,
    /// The penetrations that apply to this class, summed: the `PENETRATION` passive of the class,
    /// the source's `PENETRATION` effects of its scope, the carrier's `HIT_PENETRATION`; capped at
    /// 100 here. `WEAPON` and `SPELL` only (§5.4).
    pub penetration: u16,
    /// The source's health and max health, for the `ABOVE_HALF` guard at the damage step (§2.4).
    pub health: u16,
    pub max_health: u16,
    /// The source holds Weakness (CBT-04; **P**). `WEAPON` only.
    pub weakened: bool,
    /// The source holds Blind (CBT-04; **P**). `WEAPON` only.
    pub blind: bool,
}

/// The target of a hit: its armor terms and its state (design/19 §5.5 step 3, §5.6).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct HitTarget {
    /// The unguarded armor, signed: the snapshot's `i16` (F-20), or the caste's.
    pub armor: i16,
    /// Its `ARMOR` effects, summed (each 0…255).
    pub armor_effects: u16,
    /// Its guarded `ARMOR` sums, signed (F-20), and whether their guards hold (subject the target).
    pub armor_stance: i8,
    pub armor_enchanted: i8,
    pub in_stance: bool,
    pub enchanted: bool,
    /// Its `ARMOR_VS` of the hit's damage type (≤ 63, FX-23).
    pub armor_vs: u8,
    /// The charges of the `BLOCK` it holds; 0 none.
    pub block: u8,
    /// It holds `EVADE` (melee).
    pub evade: bool,
    /// It is knocked down (CBT-04): critical from any arc, neither blocks nor evades (FX-7).
    pub knocked_down: bool,
    /// It is asleep: critical from any arc, and this first hit cannot be blocked (design/04).
    pub asleep: bool,
    /// It holds `HALVE_FIRST_HEAVY_HIT`, not yet spent (FX-19).
    pub halve: bool,
    /// Its health and max health before the hit (FX-19).
    pub health: u16,
    pub max_health: u16,
}

/// A landed hit (FX-10: whatever its damage, 0 included).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct Landed {
    /// The damage, in [0, 65,535], after FX-19's halving.
    pub damage: u16,
    /// It was a critical strike.
    pub critical: bool,
    /// FX-19's halving triggered: the executor marks it spent.
    pub halved: bool,
}

/// What a hit does (§5.5 step 2, §5.6). A stopped hit is not a hit: nothing of it or of its
/// carrier applies to the target.
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub enum HitOutcome {
    /// Blind's miss (**P**).
    Missed,
    /// Blocked: the executor spends one of the target's `BLOCK` charges.
    Blocked,
    /// Evaded.
    Evaded,
    Landed: Landed,
}

#[generate_trait]
pub impl HitImpl of HitTrait {
    /// §5.5 steps 1–4 and §5.6: the outcome of the hit on the target.
    fn resolve(self: @Hit, target: @HitTarget) -> HitOutcome {
        HitAssert::assert_valid(self, target);
        let weapon_hit = *self.class == HitClass::Weapon;
        if weapon_hit {
            let stop = self.stop(target);
            if stop.is_some() {
                return stop.unwrap();
            }
        }
        let critical = weapon_hit && self.is_critical(target);
        let damage = self.damage(self.armor(target), self.percent(target, critical));
        let (damage, halved) = if weapon_hit {
            target.halve(damage)
        } else {
            (damage, false)
        };
        HitOutcome::Landed(Landed { damage: damage.try_into().unwrap(), critical, halved })
    }

    /// Step 2 of a weapon hit (§5.6), in §5.5's order: a miss, a block, an evasion; `None` if it
    /// goes on.
    #[inline(always)]
    fn stop(self: @Hit, target: @HitTarget) -> Option<HitOutcome> {
        if *self.blind && !*self.in_front {
            return Option::Some(HitOutcome::Missed);
        }
        let open = !*target.knocked_down;
        let front = *self.arc == Arc::Front || *self.arc == Arc::FrontSide;
        if *target.block > 0 && front && open && !*target.asleep {
            return Option::Some(HitOutcome::Blocked);
        }
        if *target.evade && *self.melee && open {
            return Option::Some(HitOutcome::Evaded);
        }
        Option::None
    }

    /// A weapon hit is critical from the back, or on a knocked-down or sleeping target from any arc
    /// (design/04).
    #[inline(always)]
    fn is_critical(self: @Hit, target: @HitTarget) -> bool {
        *self.arc == Arc::Back || *target.knocked_down || *target.asleep
    }

    /// Step 3: the final armor, never below 0. `a` signed, floored at 0 (D-140, F-20), then
    /// `a⁺ − ⌊a⁺ × p / 100⌋` with `p` the penetration capped at 100 (FX-9), 0 for a bomb
    /// or a trap.
    #[inline(always)]
    fn armor(self: @Hit, target: @HitTarget) -> u32 {
        let mut a: i32 = (*target.armor).into()
            + (*target.armor_effects).into()
            + (*target.armor_vs).into();
        if *target.in_stance {
            a += (*target.armor_stance).into();
        }
        if *target.enchanted {
            a += (*target.armor_enchanted).into();
        }
        if a <= 0 {
            return 0;
        }
        let a: u32 = a.try_into().unwrap();
        let p: u32 = if self.reads_passives() {
            let p: u32 = (*self.penetration).into();
            if p > PENETRATION_CAP {
                PENETRATION_CAP
            } else {
                p
            }
        } else {
            0
        };
        a - a * p / 100
    }

    /// The sum of the percents that apply (§5.4), floored at −100 (D-140): the source's
    /// `DAMAGE_PERCENT` (the `ABOVE_HALF` sum if its guard holds) for a weapon hit or a spell; the
    /// critical, the axe's and Weakness's for a weapon hit.
    #[inline(always)]
    fn percent(self: @Hit, target: @HitTarget, critical: bool) -> i32 {
        let mut sum: i32 = 0;
        if self.reads_passives() {
            sum += (*self.percent).into();
            let health: u32 = (*self.health).into();
            if health * 2 > (*self.max_health).into() {
                sum += (*self.percent_above_half).into();
            }
        }
        if *self.class == HitClass::Weapon {
            if critical {
                sum += CRITICAL_PERCENT;
            }
            if *self.weapon == weapon::AXE
                && (*self.arc == Arc::RearSide || *self.arc == Arc::Back) {
                sum += AXE_PERCENT;
            }
            if *self.weakened {
                sum += WEAKNESS_PERCENT;
            }
        }
        if sum < MIN_PERCENT {
            MIN_PERCENT
        } else {
            sum
        }
    }

    /// Step 4 before FX-19: `x = strength − armor` clamped to [−160, +80] by the table,
    /// `⌊base × table(x) / 2^16⌋`, then `⌊· × (100 + percent) / 100⌋`, clamped to [0,
    /// 65,535].
    /// `percent` ≥ −100, so nothing is negative and 0 is the lower bound by itself.
    #[inline(always)]
    fn damage(self: @Hit, armor: u32, percent: i32) -> u64 {
        let x: i32 = (*self.strength).into() - armor.try_into().unwrap();
        let factor: u64 = Exp2::at(x).into();
        let base: u64 = (*self.base).into();
        let scaled = base * factor / SHIFT.into();
        let multiplier: u64 = (100 + percent).try_into().unwrap();
        let damage = scaled * multiplier / 100;
        if damage > MAX_DAMAGE {
            MAX_DAMAGE
        } else {
            damage
        }
    }

    /// The class reads the source's `DAMAGE_PERCENT` and the penetrations (§5.4: weapon and spell,
    /// by scope; not a bomb, not a trap).
    #[inline(always)]
    fn reads_passives(self: @Hit) -> bool {
        *self.class == HitClass::Weapon || *self.class == HitClass::Spell
    }

    /// A weapon hit's strength: `5 × rank` of the weapon's attribute, capped (design/04, DS-9; the
    /// cap is the level's, `Loadout.strength_cap`).
    fn weapon_strength(rank: u8, cap: u8) -> u16 {
        let strength = STRENGTH_PER_RANK * rank.into();
        let cap: u16 = cap.into();
        if strength > cap {
            cap
        } else {
            strength
        }
    }

    /// A spell's or a trap's strength: `3 × level` (design/04, FX-28).
    fn level_strength(level: u8) -> u16 {
        STRENGTH_PER_LEVEL * level.into()
    }

    /// A weapon hit's base: the weapon's damage, divided by 3 below its requirement (design/15),
    /// plus an attack skill's `ATTACK_BONUS` (§3.1; 0 for a plain attack).
    fn weapon_base(damage: u8, requirement_met: bool, bonus: u16) -> u32 {
        let damage: u32 = damage.into();
        let damage = if requirement_met {
            damage
        } else {
            damage / REQUIREMENT_DIVISOR
        };
        damage + bonus.into()
    }
}

#[generate_trait]
pub impl HitTargetImpl of HitTargetTrait {
    /// FX-19, on a weapon hit's final damage: if the target holds the halving unspent, and the hit
    /// would bring it from at least 50 % to below 50 % (`2h ≥ max ∧ 2(h ⊖ d) < max`), the
    /// damage is halved, truncated. Returns the damage and whether it triggered.
    #[inline(always)]
    fn halve(self: @HitTarget, damage: u64) -> (u64, bool) {
        if !*self.halve {
            return (damage, false);
        }
        let health: u64 = (*self.health).into();
        let max: u64 = (*self.max_health).into();
        let after = if damage > health {
            0
        } else {
            health - damage
        };
        if health * 2 >= max && after * 2 < max {
            (damage / 2, true)
        } else {
            (damage, false)
        }
    }
}

#[generate_trait]
pub impl HitAssert of HitAssertTrait {
    /// What an input may not be: a base above `MAX_BASE` (the content and the snapshot bound it), a
    /// health above its max, a `BLOCK` above 63 charges. A breach is a bug, not a play (D-140).
    #[inline(always)]
    fn assert_valid(hit: @Hit, target: @HitTarget) {
        assert(*hit.base <= MAX_BASE, errors::BASE);
        assert(*hit.health <= *hit.max_health, errors::HEALTH);
        assert(*target.health <= *target.max_health, errors::HEALTH);
        assert(*target.block <= MAX_BLOCK, errors::BLOCK);
    }
}
