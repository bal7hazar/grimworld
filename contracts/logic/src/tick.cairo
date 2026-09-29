//! The world tick's pipeline (CBT-02): design/02 *The tick* in design/19 §5's order, as pure rules
//! over `types::tick::World`: state in, state out, no storage. The caller (`play`, ENG-07) reads
//! the words once, runs every tick of an action in one call of the library class
//! (`systems::tick::TickLibrary`, ENG-01 §1.3), which loads them, runs the ticks and stores them
//! back, and writes what changed.
//!
//! One tick `T` (§5.1):
//! 0. the clock advances; the flags "since the last tick" clear; perception and the awake set
//!    (`Rules::perceive`, design/18: ENG-07; `TickTrait::awake` selects the set);
//! 1. activations due at `T` resolve, members then awake goblins by ascending id (the executor,
//!    `Rules::resolve`: CBT-05); a goblin's activation from before `T` lapses (FX-29); a recovery
//!    over clears;
//! 2. awake goblins free to act act, ascending id (`Rules::act`: ENG-07);
//! 3. regeneration, degeneration and adrenaline decay, members then awake goblins; a goblin at 0
//!    dies after every actor of the step;
//! 4. durations and recharges end: nothing is written, a deadline at or below the clock reads as
//!    ended;
//! 5. defeat, then the objectives (`Rules::objectives`: ENG-07).
//! The adventurer at 0 in steps 1–2 stops the tick there: step 5 still runs (FX-8, §5.13).
//!
//! The rules that act on one actor (starting, concluding, interrupting an activation, a goblin's
//! recovery) are methods of `MemberTickTrait` and `GoblinTickTrait`, for the executor and the AI.

use crate::types::combat::{activation, condition, skill_kind};
use crate::types::tick::{
    ADRENALINE_DECAY, Actor, CasteSheet, Content, ContentTrait, Goblin, GoblinTrait,
    GoblinWordsTrait, HEALTH_PER_PIP, Held, MAX_PIPS, Member, MemberTrait, MemberWordsTrait,
    NO_SLOT, SkillSheetTrait, World, ai, flag, status,
};

/// The goblins one tick may hold: the window's (at most 4 chunks × 2 packs × 5) and the roster's
/// 60 (ENG-01 §9.2). Their index fits the step's `u128` mask.
pub const MAX_GOBLINS: u32 = 100;
/// The awake set's size (design/02).
pub const MAX_AWAKE: u32 = 8;

pub mod errors {
    pub const GOBLINS: felt252 = 'tick: too many goblins';
    pub const DISTANCES: felt252 = 'tick: one distance a goblin';
    pub const CONDITION: felt252 = 'tick: condition not stored';
    pub const DURATION: felt252 = 'tick: duration below 1';
}

/// What the pipeline leaves to the lots after it: each hook is called at its point of the order.
pub trait Rules<R> {
    /// Step 0: perception (design/18) and the awake set (`TickTrait::awake`), ENG-07.
    fn perceive(ref self: R, ref world: World);
    /// Step 1: the executor (design/19 §5.14, CBT-05) for the activation of `actor`'s `slot` on
    /// `target`, which the pipeline has concluded (field cleared, recharge set).
    fn resolve(
        ref self: R, ref world: World, content: @Content, actor: Actor, slot: u8, target: u16,
    );
    /// Step 2: the goblin at `index` acts (the AI, ENG-07); it is awake, alive, not busy, not
    /// knocked down, and did not resolve an activation in step 1.
    fn act(ref self: R, ref world: World, content: @Content, index: u32);
    /// Step 5: the objectives (D-04), after the defeat check.
    fn objectives(ref self: R, ref world: World);
}

/// The rules of this lot alone: every hook does nothing. The library class runs it until CBT-05
/// and ENG-07 give the executor and the AI.
#[derive(Copy, Drop, Default)]
pub struct Idle {}

pub impl IdleRules of Rules<Idle> {
    fn perceive(ref self: Idle, ref world: World) {}
    fn resolve(
        ref self: Idle, ref world: World, content: @Content, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Idle, ref world: World, content: @Content, index: u32) {}
    fn objectives(ref self: Idle, ref world: World) {}
}

#[generate_trait]
pub impl TickImpl of TickTrait {
    /// Runs up to `ticks` world ticks (an action's tick cost, design/02), stopping after a tick
    /// that defeated the adventurer.
    fn run<R, +Rules<R>, +Drop<R>>(ref world: World, content: @Content, ticks: u8, ref rules: R) {
        let mut k: u8 = 0;
        while k < ticks && !world.defeated {
            Self::tick(ref world, content, ref rules);
            k += 1;
        }
    }

    /// One world tick, steps 0 to 5 (design/19 §5.1).
    fn tick<R, +Rules<R>, +Drop<R>>(ref world: World, content: @Content, ref rules: R) {
        assert(world.goblins.len() <= MAX_GOBLINS, errors::GOBLINS);
        // The adventurer at 0 before the tick (in the action phase: a trap on its move, §5.11):
        // the tick stops at once, before the clock advances or any actor runs; step 5's defeat
        // and objectives run (FX-8, §5.13; AUD-182-5). The caller applies the action and then
        // calls the pipeline, which owns this check.
        if world.is_down() {
            Self::check(ref world);
            rules.objectives(ref world);
            return;
        }
        // Step 0.
        world.clock += 1;
        Self::clear_flags(ref world);
        rules.perceive(ref world);
        // Steps 1 and 2; the adventurer at 0 stops the tick at once (FX-8).
        let (stopped, resolved) = Self::conclude(ref world, content, ref rules);
        if !stopped && !Self::act(ref world, content, resolved, ref rules) {
            // Step 3.
            Self::regenerate(ref world);
        }
        // Step 4 writes nothing. Step 5.
        Self::check(ref world);
        rules.objectives(ref world);
    }

    /// Step 0: the member flags "since the last tick" and "hit this tick" clear.
    fn clear_flags(ref world: World) {
        let mut members = array![];
        for member in world.members.span() {
            let mut member = *member;
            member.flags = member.flags & flag::KEPT;
            members.append(member);
        }
        world.members = members;
    }

    /// Step 1: members' activations due, then awake goblins', ascending id. Returns whether the
    /// adventurer reached 0 and the mask of the goblins that resolved (bit = 2^index).
    fn conclude<R, +Rules<R>, +Drop<R>>(
        ref world: World, content: @Content, ref rules: R,
    ) -> (bool, u128) {
        let t = world.clock;
        let count = world.members.len();
        let mut i = 0;
        while i < count {
            let member = world.members.at(i);
            if *member.act_slot != NO_SLOT
                && *member.act_deadline <= t
                && *member.status == status::INSIDE
                && *member.health > 0 {
                let mut member = *member;
                let (slot, target) = member.conclude(content);
                world.set_member(i, member);
                rules.resolve(ref world, content, Actor::Member(i), slot, target);
                if world.is_down() {
                    return (true, 0);
                }
            }
            i += 1;
        }
        let count = world.goblins.len();
        let mut resolved: u128 = 0;
        let mut bit: u128 = 1;
        let mut i = 0;
        while i < count {
            let goblin = world.goblins.at(i);
            if *goblin.awake {
                let slot = *goblin.act_slot;
                let deadline = *goblin.act_deadline;
                if slot <= activation::LAST_SLOT {
                    if deadline <= t && goblin.is_alive() {
                        let mut goblin = *goblin;
                        let caste = content.caste(goblin.caste);
                        if deadline == t {
                            let (slot, target) = goblin.conclude(caste, content);
                            world.set_goblin(i, goblin);
                            resolved += bit;
                            rules.resolve(ref world, content, Actor::Goblin(i), slot, target);
                            if world.is_down() {
                                return (true, resolved);
                            }
                        } else {
                            goblin.lapse(caste, content);
                            world.set_goblin(i, goblin);
                        }
                    }
                } else if slot == activation::RECOVERING && deadline < t {
                    let mut goblin = *goblin;
                    goblin.clear();
                    world.set_goblin(i, goblin);
                }
            }
            i += 1;
            bit *= 2;
        }
        (false, resolved)
    }

    /// Step 2: every awake goblin, ascending id, that is alive, not busy (activating or
    /// recovering), not knocked down, and did not resolve in step 1 (§5.2). Returns whether the
    /// adventurer reached 0.
    fn act<R, +Rules<R>, +Drop<R>>(
        ref world: World, content: @Content, resolved: u128, ref rules: R,
    ) -> bool {
        let t = world.clock;
        let count = world.goblins.len();
        let mut bit: u128 = 1;
        let mut i = 0;
        while i < count {
            let goblin = world.goblins.at(i);
            if *goblin.awake
                && *goblin.act_slot == activation::NONE
                && *goblin.knocked < t
                && goblin.is_alive()
                && resolved & bit == 0 {
                rules.act(ref world, content, i);
                if world.is_down() {
                    return true;
                }
            }
            i += 1;
            bit *= 2;
        }
        false
    }

    /// Step 3 (§5.8): members, then awake goblins, ascending id. Out of combat is, for a member,
    /// no goblin of the tick's awake set Engaged; for a goblin, not Engaged. A goblin at 0 dies
    /// after every actor of the step, in id order.
    fn regenerate(ref world: World) {
        let t = world.clock;
        let mut engaged = false;
        for goblin in world.goblins.span() {
            if *goblin.awake && *goblin.ai == ai::ENGAGED {
                engaged = true;
                break;
            }
        }
        let mut members = array![];
        for member in world.members.span() {
            let mut member = *member;
            if member.status == status::INSIDE && member.health > 0 {
                member.regenerate(t, engaged);
            }
            members.append(member);
        }
        world.members = members;
        let mut goblins = array![];
        for goblin in world.goblins.span() {
            let mut goblin = *goblin;
            if goblin.awake && goblin.is_alive() {
                goblin.regenerate(t);
                if goblin.health == 0 {
                    goblin.ai = ai::DEAD;
                    world.killed.append(goblin.entity);
                }
            }
            goblins.append(goblin);
        }
        world.goblins = goblins;
    }

    /// Step 5's defeat (§5.13): a member inside at 0 is down, and the adventurer defeated.
    fn check(ref world: World) {
        if !world.is_down() {
            return;
        }
        let mut members = array![];
        for member in world.members.span() {
            let mut member = *member;
            if member.status == status::INSIDE && member.health == 0 {
                member.status = status::DOWN;
            }
            members.append(member);
        }
        world.members = members;
        world.defeated = true;
    }

    /// Step 0's awake set (§5.2, design/02): among the goblins alive and not asleep, the
    /// `MAX_AWAKE` nearest to a member by hex distance (`distances`, one per goblin of the world,
    /// computed on the window by the caller), ties by lowest entity id. Fixed for the tick.
    fn awake(ref world: World, distances: Span<u16>) {
        let count = world.goblins.len();
        assert(distances.len() == count, errors::DISTANCES);
        // Each candidate's key, `distance × 2^16 + entity`, is unique: select the 8 smallest.
        let mut keys: Array<u32> = array![];
        let mut i = 0;
        while i < count {
            let goblin = world.goblins.at(i);
            let key: u32 = if goblin.is_alive() && *goblin.ai != ai::ASLEEP {
                (*distances[i]).into() * 0x10000 + (*goblin.entity).into()
            } else {
                0xFFFFFFFF
            };
            keys.append(key);
            i += 1;
        }
        let keys = keys.span();
        let mut last: u32 = 0;
        let mut found = 0;
        while found < MAX_AWAKE {
            let mut next: u32 = 0xFFFFFFFF;
            for key in keys {
                if (found == 0 || *key > last) && *key < next {
                    next = *key;
                }
            }
            if next == 0xFFFFFFFF {
                break;
            }
            last = next;
            found += 1;
        }
        let mut goblins = array![];
        let mut i = 0;
        while i < count {
            let mut goblin = *world.goblins.at(i);
            goblin.awake = found > 0 && *keys[i] <= last;
            goblins.append(goblin);
            i += 1;
        }
        world.goblins = goblins;
    }
}

#[generate_trait]
pub impl WorldImpl of WorldTrait {
    /// Whether a member inside is at 0 health (the adventurer at 0, FX-8).
    fn is_down(self: @World) -> bool {
        for member in self.members.span() {
            if *member.status == status::INSIDE && *member.health == 0 {
                return true;
            }
        }
        false
    }

    fn set_member(ref self: World, index: u32, member: Member) {
        let mut members = array![];
        let mut i = 0;
        for current in self.members.span() {
            members.append(if i == index {
                member
            } else {
                *current
            });
            i += 1;
        }
        self.members = members;
    }

    fn set_goblin(ref self: World, index: u32, goblin: Goblin) {
        let mut goblins = array![];
        let mut i = 0;
        for current in self.goblins.span() {
            goblins.append(if i == index {
                goblin
            } else {
                *current
            });
            i += 1;
        }
        self.goblins = goblins;
    }

    /// A goblin at 0 dies at once (§5.13): health 0, dead (its remains), out of the awake set's
    /// work, recorded in resolution order (`GoblinKilled`). For the executor.
    fn kill(ref self: World, index: u32) {
        let mut goblin = *self.goblins.at(index);
        if !goblin.is_alive() {
            return;
        }
        goblin.health = 0;
        goblin.ai = ai::DEAD;
        self.killed.append(goblin.entity);
        self.set_goblin(index, goblin);
    }
}

/// `R = t₀ + r − 1` (§5.1; FX-2): `t₀` is at least 1, the first tick.
#[inline(always)]
fn recharge(t0: u32, r: u16) -> u32 {
    t0 + r.into() - 1
}

#[generate_trait]
pub impl MemberTickImpl of MemberTickTrait {
    /// An activation of `n` ticks started in the action phase at clock `c` (§5.1, §5.3 step 4):
    /// `A = c + n`, `n` at least 1 (§6).
    fn start(ref self: Member, slot: u8, target: u16, n: u16, c: u32) {
        let n: u32 = if n == 0 {
            1
        } else {
            n.into()
        };
        self.act_slot = slot;
        self.act_target = target;
        self.act_tile = 0;
        self.act_deadline = c + n;
    }

    /// An instant skill of the bar's `slot` used in the action phase at clock `c`: its recharge
    /// counts from `t₀ = c + 1` (§5.1).
    fn use_instant(ref self: Member, slot: u8, c: u32, content: @Content) {
        let r = *content.skill(self.skill(slot)).recharge;
        self.set_recharge(slot, recharge(c + 1, r));
    }

    /// Step 1 at `A`: the activation ends; its recharge counts from `A` (FX-2); returns its slot
    /// and target for the executor.
    fn conclude(ref self: Member, content: @Content) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let r = *content.skill(self.skill(slot)).recharge;
        self.set_recharge(slot, recharge(self.act_deadline, r));
        self.clear();
        (slot, target)
    }

    /// Interrupted at `t₀` (§5.9: `c + 1` in the action phase, `T` in a tick): no effect, the
    /// recharge counts from `t₀` (FX-2). Nothing without an activation.
    fn interrupt(ref self: Member, t0: u32, content: @Content) {
        if self.act_slot == NO_SLOT {
            return;
        }
        let r = *content.skill(self.skill(self.act_slot)).recharge;
        self.set_recharge(self.act_slot, recharge(t0, r));
        self.clear();
    }

    /// Step 3 at tick `t` (§5.8) for a member inside and alive: health by its pips (the
    /// snapshot's, its `REGENERATION` effects', the conditions'; clamped to ±10, × 2), energy by
    /// its pips in thirds, adrenaline decay out of combat (D-157 E).
    fn regenerate(ref self: Member, t: u32, engaged: bool) {
        let mut pips: i32 = self.health_regen.into()
            + degeneration(self.bleeding, self.poison, self.burning, t);
        let [r0, r1, r2, r3] = self.effect_regen;
        if r0 != 0 || r1 != 0 || r2 != 0 || r3 != 0 {
            let [d0, d1, d2, d3] = self.effect_deadlines;
            pips += held(r0, d0, t) + held(r1, d1, t) + held(r2, d2, t) + held(r3, d3, t);
        }
        self.health = heal(self.health, pips, self.max_health);
        let energy = self.energy + self.energy_regen.into();
        self.energy = if energy > self.max_energy {
            self.max_energy
        } else {
            energy
        };
        if !engaged {
            self.adrenaline = decay(self.adrenaline);
        }
    }

    fn clear(ref self: Member) {
        self.act_slot = NO_SLOT;
        self.act_target = 0;
        self.act_tile = 0;
        self.act_deadline = 0;
    }
}

#[generate_trait]
pub impl GoblinTickImpl of GoblinTickTrait {
    /// Step 2 of `T`: a caste skill with activation `n ≥ 1` starts, `A = T + n` (§5.2).
    fn start(ref self: Goblin, slot: u8, target: u16, n: u16, t: u32) {
        let n: u32 = if n == 0 {
            1
        } else {
            n.into()
        };
        self.act_slot = slot;
        self.act_target = target;
        self.act_deadline = t + n;
    }

    /// Step 2 of `T`: an act of tick cost `k` that lands now (a weapon attack, an instant attack
    /// skill, a crippled move of cost 2): recovering until `B = T + k − 1` if `k > 1` (FX-15).
    fn recover(ref self: Goblin, k: u8, t: u32) {
        if k > 1 {
            self.act_slot = activation::RECOVERING;
            self.act_target = 0;
            self.act_deadline = t + k.into() - 1;
        }
    }

    /// An instant caste skill of `slot` used in step 2 of `T`: its recharge counts from `T`.
    fn use_instant(ref self: Goblin, slot: u8, t: u32, caste: @CasteSheet, content: @Content) {
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        self.set_recharge(slot, recharge(t, r));
    }

    /// Step 1 at `A`: the activation ends, its recharge counts from `A` (FX-2); an attack skill
    /// whose weapon costs `k ≥ n + 2` recovers until `B = A + k − n − 1` (FX-15, §10.9).
    /// Returns its slot and target for the executor.
    fn conclude(ref self: Goblin, caste: @CasteSheet, content: @Content) -> (u8, u16) {
        let slot = self.act_slot;
        let target = self.act_target;
        let a = self.act_deadline;
        let skill = content.skill(*caste.skills.span()[slot.into()]);
        self.set_recharge(slot, recharge(a, *skill.recharge));
        let k: u32 = (*caste.weapon_ticks).into();
        let n: u32 = (*skill.activation).into();
        if *skill.kind == skill_kind::ATTACK && k >= n + 2 {
            self.act_slot = activation::RECOVERING;
            self.act_target = 0;
            self.act_deadline = a + k - n - 1;
        } else {
            self.clear();
        }
        (slot, target)
    }

    /// Step 1 of `T > A` for a goblin frozen at `A` (FX-29): the activation lapsed at `A`, as an
    /// interrupt dated `A`; its recharge `A + r − 1` is kept if a later one is stored.
    fn lapse(ref self: Goblin, caste: @CasteSheet, content: @Content) {
        let slot = self.act_slot;
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        let deadline = recharge(self.act_deadline, r);
        if deadline > self.recharge(slot) {
            self.set_recharge(slot, deadline);
        }
        self.clear();
    }

    /// Interrupted at `t₀` (§5.9): the field goes to none, the recharge counts from `t₀`
    /// (FX-2). Nothing unless activating (a recovery is not an activation).
    fn interrupt(ref self: Goblin, t0: u32, caste: @CasteSheet, content: @Content) {
        let slot = self.act_slot;
        if slot > activation::LAST_SLOT {
            return;
        }
        let r = *content.skill(*caste.skills.span()[slot.into()]).recharge;
        self.set_recharge(slot, recharge(t0, r));
        self.clear();
    }

    /// Step 3 at tick `t` (§5.8) for an awake goblin alive: health by its caste's pips, its
    /// effect's and its conditions'; energy by the caste's pips in thirds; adrenaline decay when
    /// not Engaged (D-157 E).
    fn regenerate(ref self: Goblin, t: u32) {
        let mut pips: i32 = self.health_regen.into()
            + degeneration(self.bleeding, self.poison, self.burning, t)
            + held(self.effect_regen, self.effect_deadline, t);
        self.health = heal(self.health, pips, self.max_health);
        let energy: u16 = self.energy.into() + self.energy_regen.into();
        self
            .energy =
                if energy > self.max_energy.into() {
                    self.max_energy
                } else {
                    energy.try_into().unwrap()
                };
        if self.ai != ai::ENGAGED {
            let decayed = decay(self.adrenaline.into());
            self.adrenaline = decayed.try_into().unwrap();
        }
    }

    fn clear(ref self: Goblin) {
        self.act_slot = activation::NONE;
        self.act_target = 0;
        self.act_deadline = 0;
    }
}

/// The lifecycle rules of design/19 §5.7 and §5.12 on a member (AUD-182-6): conditions inflicted
/// and cured, held effects held, refreshed and replaced, adrenaline gained. The executor (CBT-05)
/// calls them; the durations it passes are after `durations::effective_duration`.
#[generate_trait]
pub impl MemberLifecycleImpl of MemberLifecycleTrait {
    /// Condition `condition` (1–5, the MVP's: FX-22) inflicted at `t0` for `d ≥ 1` ticks: `D =
    /// t0 + d − 1`; held already, it refreshes to `max(D_old, D)` (FX-6; Knocked down too,
    /// FX-31).
    fn inflict(ref self: Member, condition: u8, t0: u32, d: u32) {
        let old = self.condition(condition);
        self.set_condition(condition, refreshed(old, t0, d));
    }

    /// `CURE` at `t0` (§3.2): a duration of 0, `D = t0 − 1`; an absent condition, nothing.
    fn cure(ref self: Member, condition: u8, t0: u32) {
        let old = self.condition(condition);
        self.set_condition(condition, cured(old, t0));
    }

    /// The deadline of condition 1–5.
    fn condition(self: @Member, condition: u8) -> u32 {
        assert(
            condition >= condition::BLEEDING && condition <= condition::LAST_MVP, errors::CONDITION,
        );
        if condition == condition::BLEEDING {
            *self.bleeding
        } else if condition == condition::POISON {
            *self.poison
        } else if condition == condition::BURNING {
            *self.burning
        } else if condition == condition::CRIPPLED {
            self.crippled()
        } else {
            *self.knocked
        }
    }

    fn set_condition(ref self: Member, condition: u8, deadline: u32) {
        if condition == condition::BLEEDING {
            self.bleeding = deadline;
        } else if condition == condition::POISON {
            self.poison = deadline;
        } else if condition == condition::BURNING {
            self.burning = deadline;
        } else if condition == condition::CRIPPLED {
            self.set_crippled(deadline);
        } else {
            self.knocked = deadline;
        }
    }

    /// A holding effect applied at tick or clock `t` (§5.7), `stance` if its carrier is a stance;
    /// returns its slot. In order:
    /// 1. its carrier held (FX-42: the skill id, or a potion's item id through its belt slot):
    ///    the application with the later deadline is kept whole, the new one on a tie (FX-30);
    /// 2. else a stance while one is held: it takes that slot;
    /// 3. else the lowest free slot (never held, or its deadline passed);
    /// 4. else eviction: the earliest deadline, ties the lowest slot (FX-13).
    /// An effect ends by its deadline: one whose charges reach 0 is ended by the executor with a
    /// deadline of `t − 1`.
    fn hold(ref self: Member, held: Held, stance: bool, t: u32, content: @Content) -> u8 {
        let item = if held.potion {
            self.belt_item(held.carrier)
        } else {
            0
        };
        // 1. The same carrier.
        let mut slot: u8 = 0;
        while slot < 4 {
            let old = self.effect_of(slot);
            if old.deadline >= t && old.potion == held.potion {
                let same = if held.potion {
                    self.belt_item(old.carrier) == item
                } else {
                    old.carrier == held.carrier
                };
                if same {
                    if held.deadline >= old.deadline {
                        self.put(slot, held, item, content);
                    }
                    return slot;
                }
            }
            slot += 1;
        }
        // 2. A stance replaces the stance held.
        if stance {
            let mut slot: u8 = 0;
            while slot < 4 {
                let old = self.effect_of(slot);
                if old.deadline >= t
                    && !old.potion
                    && old.carrier != 0
                    && *content.skill(old.carrier).kind == skill_kind::STANCE {
                    self.put(slot, held, item, content);
                    return slot;
                }
                slot += 1;
            }
        }
        // 3. The lowest free slot; 4. else the earliest deadline, ties the lowest slot.
        let mut earliest: u8 = 0;
        let mut earliest_deadline: u32 = 0xFFFFFFFF;
        let mut slot: u8 = 0;
        while slot < 4 {
            let deadline = self.effect_of(slot).deadline;
            if deadline < t {
                self.put(slot, held, item, content);
                return slot;
            }
            if deadline < earliest_deadline {
                earliest = slot;
                earliest_deadline = deadline;
            }
            slot += 1;
        }
        self.put(earliest, held, item, content);
        earliest
    }

    /// Writes `held` in `slot` with its pips: a potion's through its item, a skill's at its rank.
    fn put(ref self: Member, slot: u8, held: Held, item: u32, content: @Content) {
        let pips: i32 = if held.potion {
            (*content.potion(item).regen).into()
        } else {
            content.skill(held.carrier).regen(held.rank)
        };
        self.set_effect(slot, held, pips.try_into().unwrap());
    }

    /// Adrenaline gained, in quarters (§5.12): capped at the member's cap (its bar's highest
    /// cost, FX-12); one already at or above it keeps what it has.
    fn gain_adrenaline(ref self: Member, quarters: u16) {
        if self.adrenaline < self.adrenaline_cap {
            let gained = self.adrenaline + quarters;
            self.adrenaline = min16(gained, self.adrenaline_cap);
        }
    }

    /// A weapon hit landed (§5.5 step 8, §5.12): 4 quarters, 8 on every `N`-th hit of
    /// `ADRENALINE_EVERY_N` (the `hits` counter resets at N; N = 0: it stays 0).
    fn land_weapon_hit(ref self: Member) {
        let every = self.double_every();
        let mut quarters: u16 = 4;
        if every > 0 {
            let hits = self.hits() + 1;
            if hits == every {
                quarters = 8;
                self.set_hits(0);
            } else {
                self.set_hits(hits);
            }
        }
        self.gain_adrenaline(quarters);
    }

    /// A hit taken while alive (§5.12): 1 quarter.
    fn take_hit(ref self: Member) {
        if self.health > 0 {
            self.gain_adrenaline(1);
        }
    }
}

/// The same lifecycle rules on a goblin (§5.7, §5.12): a dead goblin takes nothing; its one slot
/// is refreshed by its carrier or replaced (FX-13); its gains capped at its caste's cap.
#[generate_trait]
pub impl GoblinLifecycleImpl of GoblinLifecycleTrait {
    fn inflict(ref self: Goblin, condition: u8, t0: u32, d: u32) {
        if !self.is_alive() {
            return;
        }
        let old = self.condition(condition);
        self.set_condition(condition, refreshed(old, t0, d));
    }

    fn cure(ref self: Goblin, condition: u8, t0: u32) {
        let old = self.condition(condition);
        self.set_condition(condition, cured(old, t0));
    }

    fn condition(self: @Goblin, condition: u8) -> u32 {
        assert(
            condition >= condition::BLEEDING && condition <= condition::LAST_MVP, errors::CONDITION,
        );
        if condition == condition::BLEEDING {
            *self.bleeding
        } else if condition == condition::POISON {
            *self.poison
        } else if condition == condition::BURNING {
            *self.burning
        } else if condition == condition::CRIPPLED {
            self.crippled()
        } else {
            *self.knocked
        }
    }

    fn set_condition(ref self: Goblin, condition: u8, deadline: u32) {
        if condition == condition::BLEEDING {
            self.bleeding = deadline;
        } else if condition == condition::POISON {
            self.poison = deadline;
        } else if condition == condition::BURNING {
            self.burning = deadline;
        } else if condition == condition::CRIPPLED {
            self.set_crippled(deadline);
        } else {
            self.knocked = deadline;
        }
    }

    /// A holding effect on its one slot at `t` (§5.7): the same carrier held keeps the later
    /// deadline, the new one on a tie (FX-30); anything else replaces it (FX-13).
    fn hold(ref self: Goblin, held: Held, t: u32, content: @Content) {
        if !self.is_alive() {
            return;
        }
        let old = self.effect_of();
        if old.deadline >= t && old.carrier == held.carrier && held.deadline < old.deadline {
            return;
        }
        let pips: i32 = content.skill(held.carrier).regen(held.rank);
        self.set_effect(held, pips.try_into().unwrap());
    }

    /// Adrenaline gained, in quarters (§5.12), capped at its caste's cap (at most 252).
    fn gain_adrenaline(ref self: Goblin, quarters: u8) {
        if self.adrenaline < self.adrenaline_cap {
            let gained: u16 = self.adrenaline.into() + quarters.into();
            let cap: u16 = self.adrenaline_cap.into();
            self.adrenaline = min16(gained, cap).try_into().unwrap();
        }
    }

    /// A weapon hit landed: 4 quarters (no `hits` counter: a member's modifier).
    fn land_weapon_hit(ref self: Goblin) {
        self.gain_adrenaline(4);
    }

    /// A hit taken while alive: 1 quarter.
    fn take_hit(ref self: Goblin) {
        if self.is_alive() && self.health > 0 {
            self.gain_adrenaline(1);
        }
    }
}

// Free functions below: the arithmetic of one quantity, shared by members and goblins; no type
// owns it (docs/CAIRO.md §7).

/// A condition inflicted at `t0` for `d ≥ 1` ticks over `old`: `max(old, t0 + d − 1)` (FX-6).
#[inline(always)]
fn refreshed(old: u32, t0: u32, d: u32) -> u32 {
    assert(d >= 1, errors::DURATION);
    let deadline = t0 + d - 1;
    if deadline > old {
        deadline
    } else {
        old
    }
}

/// A cure at `t0` over `old`: `t0 − 1` if the condition is held at `t0`, else unchanged.
#[inline(always)]
fn cured(old: u32, t0: u32) -> u32 {
    if old >= t0 {
        t0 - 1
    } else {
        old
    }
}

#[inline(always)]
fn min16(a: u16, b: u16) -> u16 {
    if a < b {
        a
    } else {
        b
    }
}

/// The pips of the degenerating conditions active at `t` (§5.8 step 1): −3 Bleeding, −4
/// Poison, −7 Burning (`types::combat::condition`).
#[inline(always)]
fn degeneration(bleeding: u32, poison: u32, burning: u32, t: u32) -> i32 {
    let mut pips = 0;
    if t <= bleeding {
        pips -= 3;
    }
    if t <= poison {
        pips -= 4;
    }
    if t <= burning {
        pips -= 7;
    }
    pips
}

/// A held effect's pips while it lasts (`t ≤ deadline`).
#[inline(always)]
fn held(pips: i8, deadline: u32, t: u32) -> i32 {
    if pips != 0 && t <= deadline {
        pips.into()
    } else {
        0
    }
}

/// `health + 2 × clamp(pips, −10, 10)`, clamped to `[0, max]` (§5.8 step 1; X-3: the pip sum is
/// signed).
fn heal(health: u16, pips: i32, max: u16) -> u16 {
    let pips = if pips > MAX_PIPS {
        MAX_PIPS
    } else if pips < -MAX_PIPS {
        -MAX_PIPS
    } else {
        pips
    };
    let change = HEALTH_PER_PIP * pips;
    if change < 0 {
        let loss: u16 = (-change).try_into().unwrap();
        if loss >= health {
            0
        } else {
            health - loss
        }
    } else {
        let next: u32 = health.into() + change.try_into().unwrap();
        if next > max.into() {
            max
        } else {
            next.try_into().unwrap()
        }
    }
}

/// Adrenaline less `ADRENALINE_DECAY`, floored at 0 (FX-12, D-157 E).
#[inline(always)]
fn decay(adrenaline: u16) -> u16 {
    if adrenaline < ADRENALINE_DECAY {
        0
    } else {
        adrenaline - ADRENALINE_DECAY
    }
}
