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

use crate::types::combat::{activation, skill_kind};
use crate::types::tick::{
    ADRENALINE_DECAY, Actor, CasteSheet, Content, ContentTrait, Goblin, GoblinTrait, HEALTH_PER_PIP,
    MAX_PIPS, Member, MemberTrait, NO_SLOT, World, ai, flag, status,
};

/// The goblins one tick may hold: the window's (at most 4 chunks × 2 packs × 5) and the roster's
/// 60 (ENG-01 §9.2). Their index fits the step's `u128` mask.
pub const MAX_GOBLINS: u32 = 100;
/// The awake set's size (design/02).
pub const MAX_AWAKE: u32 = 8;

pub mod errors {
    pub const GOBLINS: felt252 = 'tick: too many goblins';
    pub const DISTANCES: felt252 = 'tick: one distance a goblin';
}

/// What the pipeline leaves to the lots after it: each hook is called at its point of the order.
pub trait Rules<R> {
    /// Step 0: perception (design/18) and the awake set (`TickTrait::awake`), ENG-07.
    fn perceive(ref self: R, ref world: World);
    /// Step 1: the executor (design/19 §5.14, CBT-05) for the activation of `actor`'s `slot` on
    /// `target`, which the pipeline has concluded (field cleared, recharge set).
    fn resolve(ref self: R, ref world: World, content: @Content, actor: Actor, slot: u8, target: u16);
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

    /// Step 3 (§5.8): members, then awake goblins, ascending id. Out of combat is, for a member, no
    /// goblin of the tick's awake set Engaged; for a goblin, not Engaged. A goblin at 0 dies after
    /// every actor of the step, in id order.
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
    /// whose weapon costs `k ≥ n + 2` recovers until `B = A + k − n − 1` (FX-15, §10.9). Returns
    /// its slot and target for the executor.
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
        self.energy = if energy > self.max_energy.into() {
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

// Free functions below: the arithmetic of one quantity, shared by members and goblins; no type
// owns it (docs/CAIRO.md §7).

/// The pips of the degenerating conditions active at `t` (§5.8 step 1): −3 Bleeding, −4 Poison,
/// −7 Burning (`types::combat::condition`).
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
