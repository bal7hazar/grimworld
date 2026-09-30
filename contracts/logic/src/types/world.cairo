//! The world a library call runs over, and the tick's pipeline as its behaviour (CBT-02; design/02
//! *The tick* in design/19 §5's order): state in, state out, no storage. docs/CAIRO.md §7 has no
//! layer for pure game rules (no `logic/` folder, D-147): the pipeline is the behaviour of the
//! `World` value type, which is not stored on its own, so it sits in `types/` with it; the rules of
//! one actor are its model's (`models::member`, `models::goblin`), the shared arithmetic a helper
//! (`helpers::tick`), and the library class's entrypoint a system (`systems::tick`).
//!
//! The caller (`play`, ENG-07) reads the words once and runs every tick of an action in one call of
//! the library class (ENG-01 §1.3), which loads them (`WordsTrait::load`), runs the ticks and
//! stores them back (`WorldStoreTrait::store`).
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
//! A member at 0 before the tick, or in steps 1–2, stops it there: step 5 still runs (FX-8,
//! §5.13).

use crate::models::goblin::{GoblinTickTrait, GoblinTrait};
use crate::models::index::{Goblin, GoblinWords, Member, MemberWords};
use crate::models::member::{MemberTickTrait, MemberTrait};
use crate::types::combat::activation;
use crate::types::tick::{Content, ContentTrait, NO_SLOT, ai, flag, status};

/// What crosses the library call: the clock, the members (ascending entity id), the goblins the
/// ticks may touch (ascending entity id), the goblins killed in resolution order (`GoblinKilled`)
/// and whether the adventurer was defeated.
#[derive(Drop, Serde, Debug, PartialEq)]
pub struct Words {
    pub clock: u32,
    pub members: Array<MemberWords>,
    pub goblins: Array<GoblinWords>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

/// What the ticks run over, inside the call.
#[derive(Drop, Debug, PartialEq)]
pub struct World {
    pub clock: u32,
    pub members: Array<Member>,
    pub goblins: Array<Goblin>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

/// An actor of the world, by its index in `World.members` or `World.goblins`.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Actor {
    Member: u32,
    Goblin: u32,
}

#[generate_trait]
pub impl WordsImpl of WordsTrait {
    /// The world of the call: every actor loaded once (D-145).
    fn load(self: Words, content: @Content) -> World {
        let mut members = array![];
        for words in self.members {
            members.append(MemberTrait::load(words, content));
        }
        let mut goblins = array![];
        for words in self.goblins {
            goblins.append(GoblinTrait::load(words, content));
        }
        World { clock: self.clock, members, goblins, killed: self.killed, defeated: self.defeated }
    }
}

#[generate_trait]
pub impl WorldStoreImpl of WorldStoreTrait {
    /// The words of the world, every actor's hot fields written back.
    fn store(self: World) -> Words {
        let mut members = array![];
        for member in self.members.span() {
            members.append(member.store());
        }
        let mut goblins = array![];
        for goblin in self.goblins.span() {
            goblins.append(goblin.store());
        }
        Words { clock: self.clock, members, goblins, killed: self.killed, defeated: self.defeated }
    }
}

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
        world.assert_goblins();
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
        world.assert_distances(distances);
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
// Free functions below: the arithmetic of one quantity, shared by members and goblins; no type
// owns it (docs/CAIRO.md §7).

#[generate_trait]
pub impl WorldAssert of WorldAssertTrait {
    /// The goblins a tick holds are at most `MAX_GOBLINS`, so their indexes fit step 1's mask.
    #[inline(always)]
    fn assert_goblins(self: @World) {
        assert(self.goblins.len() <= MAX_GOBLINS, errors::GOBLINS);
    }

    /// One distance a goblin, in the order of `World.goblins`.
    #[inline(always)]
    fn assert_distances(self: @World, distances: Span<u16>) {
        assert(distances.len() == self.goblins.len(), errors::DISTANCES);
    }
}
