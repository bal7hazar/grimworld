//! Lever 3: what CBT-05's executor will add around CBT-03a's hit and CBT-04's applications, as it
//! will add it: reading the actors from the world, gathering a hit's inputs from them, applying the
//! outcome (health, adrenaline, a kill), writing the actors back. An **estimate**, not CBT-05's
//! code: the reads are main's decoders on the fields the hit names (design/19 §5.5; ENG-01 §3.2),
//! and the terms the content does not yet carry (a caste's armor and weapon damage, which
//! `CasteSheet`
//! lacks; a member's `ARMOR` and `DAMAGE_PERCENT` sums, which the snapshot's words hold) are read
//! at the cost of a field of the same words. ENG-02's arc and front tile are inputs.
//!
//! Two ways to write the actors back are priced: one write per hit or application (`world.set_*`
//! after each), and one write per actor for the whole carrier (`hits_on_goblins` with `Pending`:
//! the awake set rebuilt once for all the goblins a bomb reaches).

use grimworld_logic::models::goblin::{Goblin, GoblinLifecycleTrait, GoblinWordsTrait};
use grimworld_logic::models::member::{Member, MemberLifecycleTrait, MemberWordsTrait};
use grimworld_logic::packing::{P16, P32, P8, field, limbs};
use grimworld_logic::types::combat::{HitClass, weapon};
use grimworld_logic::types::tick::{Sheets, ai, flag};
use grimworld_logic::types::world::{World, WorldTrait};
use crate::cbt03a::{Arc, Hit, HitOutcome, HitTarget, HitTrait};
use crate::cbt04::{Cbt04GoblinTrait, Cbt04MemberTrait, Infliction};

/// The member's defence terms a hit on it reads (§5.5 step 3, §5.6), gathered once.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Guard {
    pub armor: i16,
    pub effects: u16,
    pub stance: i8,
    pub enchanted: i8,
    pub vs: u8,
    pub block: u8,
    pub evade: bool,
}

#[generate_trait]
pub impl GatherImpl of GatherTrait {
    /// A goblin's weapon hit on the member (§5.5): its source terms from its caste's sheet and its
    /// own fields, the member's armor terms from its words and its four effect slots (`ARMOR`,
    /// `BLOCK`, `EVADE` are held effects), its state from its hot fields.
    fn goblin_on_member(
        goblin: @Goblin, member: @Member, arc: Arc, in_front: bool, t: u32, sheets: @Sheets,
    ) -> (Hit, HitTarget) {
        let caste = (*sheets.castes)[*goblin.caste_at];
        let hit = Hit {
            class: HitClass::Weapon,
            weapon: *caste.weapon_ticks,
            melee: *caste.energy_regen == 1,
            arc,
            in_front,
            strength: (*caste.health).into(),
            base: (*caste.energy).into(),
            percent: 0,
            percent_above_half: 0,
            penetration: 0,
            health: *goblin.health,
            max_health: *goblin.max_health,
            weakened: false,
            blind: false,
        };
        let guard = Self::guard(member, t);
        let target = Self::member_target(member, @guard, t);
        (hit, target)
    }

    /// The same, the member's defence terms given (`guard`, read once a tick).
    fn goblin_on_member_guarded(
        goblin: @Goblin,
        member: @Member,
        guard: @Guard,
        arc: Arc,
        in_front: bool,
        t: u32,
        sheets: @Sheets,
    ) -> (Hit, HitTarget) {
        let caste = (*sheets.castes)[*goblin.caste_at];
        let hit = Hit {
            class: HitClass::Weapon,
            weapon: *caste.weapon_ticks,
            melee: *caste.energy_regen == 1,
            arc,
            in_front,
            strength: (*caste.health).into(),
            base: (*caste.energy).into(),
            percent: 0,
            percent_above_half: 0,
            penetration: 0,
            health: *goblin.health,
            max_health: *goblin.max_health,
            weakened: false,
            blind: false,
        };
        (hit, Self::member_target(member, guard, t))
    }

    /// The member's defence terms a hit reads from its words and its four effect slots: they
    /// change only when the executor holds, spends or ends an effect, so a tick may read them once.
    fn guard(member: @Member, t: u32) -> Guard {
        let (armor, stance, enchanted, vs) = Self::member_armor(member);
        let mut effects: u16 = 0;
        let mut block: u8 = 0;
        let mut evade = false;
        for slot in 0..4_u8 {
            let held = member.effect_of(slot);
            if held.deadline >= t {
                effects += held.rank.into();
                if held.charges > block {
                    block = held.charges;
                }
                evade = evade || held.potion;
            }
        }
        Guard { armor, effects, stance, enchanted, vs, block, evade }
    }

    /// The member as a hit's target: its guard and its state.
    #[inline(always)]
    fn member_target(member: @Member, guard: @Guard, t: u32) -> HitTarget {
        HitTarget {
            armor: *guard.armor,
            armor_effects: *guard.effects,
            armor_stance: *guard.stance,
            armor_enchanted: *guard.enchanted,
            in_stance: *member.flags & flag::HALVED != 0,
            enchanted: false,
            armor_vs: *guard.vs,
            block: *guard.block,
            evade: *guard.evade,
            knocked_down: member.takes_critical(t),
            asleep: false,
            halve: *member.flags & flag::HALVED == 0,
            health: *member.health,
            max_health: *member.max_health,
        }
    }

    /// The member's hit on a goblin: its source terms from its words (its weapon, strength,
    /// `DAMAGE_PERCENT` and penetration sums the snapshot flattened), the goblin's armor from its
    /// caste's sheet, its one effect, its state.
    fn member_on_goblin(
        member: @Member, goblin: @Goblin, class: HitClass, arc: Arc, t: u32, sheets: @Sheets,
    ) -> (Hit, HitTarget) {
        let (low, high) = limbs(*member.words.stats);
        let hit = Hit {
            class,
            weapon: weapon::AXE,
            melee: field(low, P8, 0x100) == 1,
            arc,
            in_front: true,
            strength: field(low, P16, 0x100).try_into().unwrap(),
            base: field(low, P32, 0x10000).try_into().unwrap(),
            percent: field(high, 1, 0x100).try_into().unwrap(),
            percent_above_half: field(high, P8, 0x100).try_into().unwrap(),
            penetration: field(high, P16, 0x100).try_into().unwrap(),
            health: *member.health,
            max_health: *member.max_health,
            weakened: false,
            blind: false,
        };
        let caste = (*sheets.castes)[*goblin.caste_at];
        let held = goblin.effect_of();
        let target = HitTarget {
            armor: (*caste.health_regen).into(),
            armor_effects: if held.deadline >= t {
                held.rank.into()
            } else {
                0
            },
            armor_stance: 0,
            armor_enchanted: 0,
            in_stance: false,
            enchanted: false,
            armor_vs: *caste.energy,
            block: held.charges,
            evade: false,
            knocked_down: goblin.takes_critical(t),
            asleep: *goblin.ai == ai::ASLEEP,
            halve: false,
            health: *goblin.health,
            max_health: *goblin.max_health,
        };
        (hit, target)
    }

    /// The member's armor terms in its `MemberStats` (armor, stance and enchanted sums, the damage
    /// type's `ARMOR_VS`): four fields of one word.
    #[inline(always)]
    fn member_armor(member: @Member) -> (i16, i8, i8, u8) {
        let (_, high) = limbs(*member.words.stats);
        let armor: u16 = field(high, 1, 0x10000).try_into().unwrap();
        let stance: u8 = field(high, P16, 0x80).try_into().unwrap();
        let enchanted: u8 = field(high, P16 * P8, 0x80).try_into().unwrap();
        let vs: u8 = field(high, P32, 0x40).try_into().unwrap();
        (
            (armor % 0x8000).try_into().unwrap(),
            stance.try_into().unwrap(),
            enchanted.try_into().unwrap(),
            vs,
        )
    }
}

#[generate_trait]
pub impl OutcomeImpl of OutcomeTrait {
    /// A landed hit on the member (§5.5 steps 5–8): its health, its adrenaline for the hit
    /// taken, the source's for the hit landed; a blocked hit spends a charge (left to the effect's
    /// writer, not priced).
    fn on_member(ref member: Member, ref source: Goblin, outcome: HitOutcome) {
        if let HitOutcome::Landed(landed) = outcome {
            member
                .health =
                    if landed.damage >= member.health {
                        0
                    } else {
                        member.health - landed.damage
                    };
            member.take_hit();
            source.land_weapon_hit();
        }
    }

    /// A landed hit on a goblin: its health, its adrenaline, the member's for the hit landed.
    /// Whether it died is returned (the executor's `kill`).
    fn on_goblin(ref goblin: Goblin, ref source: Member, outcome: HitOutcome) -> bool {
        if let HitOutcome::Landed(landed) = outcome {
            goblin
                .health =
                    if landed.damage >= goblin.health {
                        0
                    } else {
                        goblin.health - landed.damage
                    };
            goblin.take_hit();
            source.land_weapon_hit();
            return goblin.health == 0;
        }
        false
    }
}

#[generate_trait]
pub impl ExecutorImpl of ExecutorTrait {
    /// Goblin `index`'s weapon hit on member 0 at `t`, as CBT-05 will run it: both actors read from
    /// the world, the hit's inputs gathered, resolved, the outcome applied, both written back.
    fn goblin_hit(ref world: World, index: u32, t: u32, sheets: @Sheets) -> HitOutcome {
        let mut goblin = world.goblin(index);
        let mut member = world.member(0);
        let (hit, target) = GatherTrait::goblin_on_member(
            @goblin, @member, Arc::FrontSide, true, t, sheets,
        );
        let outcome = hit.resolve(@target);
        OutcomeTrait::on_member(ref member, ref goblin, outcome);
        world.set_member(0, member);
        world.set_goblin(index, goblin);
        outcome
    }

    /// The same hit, the member's guard read before (once a tick, `GatherTrait::guard`).
    fn goblin_hit_guarded(
        ref world: World, index: u32, guard: @Guard, t: u32, sheets: @Sheets,
    ) -> HitOutcome {
        let mut goblin = world.goblin(index);
        let mut member = world.member(0);
        let (hit, target) = GatherTrait::goblin_on_member_guarded(
            @goblin, @member, guard, Arc::FrontSide, true, t, sheets,
        );
        let outcome = hit.resolve(@target);
        OutcomeTrait::on_member(ref member, ref goblin, outcome);
        world.set_member(0, member);
        world.set_goblin(index, goblin);
        outcome
    }

    /// The member's carrier on the goblins at `targets` (a bomb's `DISC_1`, FX-35): for each, the
    /// hit, then its condition `CONDITION` (`apply`); each goblin written back after its own hit.
    fn bomb_each(
        ref world: World, targets: Span<u32>, condition: u8, v: i32, t: u32, sheets: @Sheets,
    ) -> u32 {
        let mut member = world.member(0);
        let source: Infliction = member.infliction();
        let mut kills = 0;
        for index in targets {
            let mut goblin = world.goblin(*index);
            let (hit, target) = GatherTrait::member_on_goblin(
                @member, @goblin, HitClass::Item, Arc::Back, t, sheets,
            );
            let outcome = hit.resolve(@target);
            let died = OutcomeTrait::on_goblin(ref goblin, ref member, outcome);
            goblin.apply(condition, v, @source, t, sheets);
            world.set_goblin(*index, goblin);
            if died {
                world.kill(*index);
                kills += 1;
            }
        }
        world.set_member(0, member);
        kills
    }

    /// The same carrier, the awake goblins it reaches written back together: one rebuild of the
    /// awake set (`WorldTrait::flush`) for all of them. `targets` are positions in the awake set,
    /// ascending (a carrier's targets are awake: §9.2's frozen ones are `set_goblin`'s).
    fn bomb_flushed(
        ref world: World, targets: Span<u32>, condition: u8, v: i32, t: u32, sheets: @Sheets,
    ) -> u32 {
        let mut member = world.member(0);
        let source: Infliction = member.infliction();
        let woken = world.woken();
        let mut pending = array![];
        let mut kills = 0;
        for k in targets {
            let index = *woken[*k];
            let mut goblin = world.goblin(index);
            let (hit, target) = GatherTrait::member_on_goblin(
                @member, @goblin, HitClass::Item, Arc::Back, t, sheets,
            );
            let outcome = hit.resolve(@target);
            let died = OutcomeTrait::on_goblin(ref goblin, ref member, outcome);
            goblin.apply(condition, v, @source, t, sheets);
            if died {
                goblin.ai = ai::DEAD;
                world.killed.append(goblin.entity);
                kills += 1;
            }
            pending.append((*k, goblin));
        }
        world.flush(pending);
        world.set_member(0, member);
        kills
    }

    /// One `CONDITION` entry on member 0, read from and written back to the world.
    fn condition_on_member(
        ref world: World, condition: u8, v: i32, source: @Infliction, t: u32, sheets: @Sheets,
    ) {
        let mut member = world.member(0);
        member.apply(condition, v, source, t, sheets);
        world.set_member(0, member);
    }

    /// One `CONDITION` entry on goblin `index`, read from and written back to the world.
    fn condition_on_goblin(
        ref world: World,
        index: u32,
        condition: u8,
        v: i32,
        source: @Infliction,
        t: u32,
        sheets: @Sheets,
    ) {
        let mut goblin = world.goblin(index);
        goblin.apply(condition, v, source, t, sheets);
        world.set_goblin(index, goblin);
    }
}
