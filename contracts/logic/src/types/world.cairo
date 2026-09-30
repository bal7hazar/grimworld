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
//!
//! **The awake set apart (CBT-02d, D-166).** The goblins are 23-felt structs: writing one in an
//! array of them rebuilds it whole (about 590,000 L2 gas at `MAX_GOBLINS`). The steps write only
//! the awake set (§5.2, at most `MAX_AWAKE`), fixed for the tick once perception has run, so its
//! goblins live apart, in `World.awake`, beside their indexes (`World.woken`); `World.goblins`
//! keeps the frozen ones. The pipeline
//! - reads and writes the awake set alone: a write rebuilds at most 8 goblins, and CBT-02b's
//! pending
//!   writes (`Pending`) still share one rebuild between two executor hooks;
//! - forms the set when the world is made (`WorldTrait::new`, `WordsTrait::load`), and again only
//!   when an awake flag changes (`TickTrait::awake` in step 0, `WorldTrait::set_goblin`); it
//!   refuses a set above `MAX_AWAKE` there (design/02), so no tick runs over one;
//! - puts the set back in its places once, when the call stores the words (`WorldStoreTrait`).
//! A goblin is read through `WorldTrait::goblin` and written through `set_goblin` and `kill`. A
//! hook after step 0 does not wake a goblin or put one to sleep (§5.2: the set is fixed for the
//! tick).
//!
//! **The content through an index (CBT-02d).** The call's content arrives as its sheets
//! (`types::tick::Content`); `ContentTrait::index` builds a dictionary of their positions once and
//! derives each caste's `Kit` once, and each actor's load reads its ids through it
//! (`types::tick::Index`). The ticks then read a record at the position its actor holds.

use crate::models::goblin::{GoblinTickTrait, GoblinTrait};
use crate::models::index::{Goblin, GoblinWords, Member, MemberWords};
use crate::models::member::{MemberTickTrait, MemberTrait};
use crate::types::combat::activation;
use crate::types::tick::{Content, ContentTrait, NO_SLOT, Sheets, ai, flag, status};

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

/// What the ticks run over, inside the call. Its goblins are read through `WorldTrait::goblin` and
/// written through `WorldTrait::set_goblin` and `kill`.
#[derive(Drop, Debug, PartialEq)]
pub struct World {
    pub clock: u32,
    pub members: Array<Member>,
    /// Every goblin the ticks may touch, ascending entity id. An awake goblin's entry is its value
    /// when the awake set was last formed; its current value is in `awake`.
    goblins: Array<Goblin>,
    /// The awake set (design/19 §5.2): its goblins' indexes in `goblins`, ascending,
    woken: Span<u32>,
    /// and their current values, in the same order: the goblins the steps write.
    awake: Array<Goblin>,
    pub killed: Array<u16>,
    pub defeated: bool,
}

/// The awake goblins step 1 changed and has not yet put in `World.awake`: `(position in the awake
/// set, new value)`, by ascending position, each once.
pub type Pending = Array<(u32, Goblin)>;

/// An actor of the world, by its index in `World.members` or among the goblins.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Actor {
    Member: u32,
    Goblin: u32,
}

#[generate_trait]
pub impl WordsImpl of WordsTrait {
    /// The world of the call and its content's sheets: the index built once, every actor loaded
    /// once through it (D-145), the awake set formed in the same pass.
    fn load(self: Words, content: @Content) -> (World, Sheets) {
        let (sheets, mut index) = content.index();
        let mut members = array![];
        for words in self.members {
            members.append(MemberTrait::load(words, ref index, @sheets));
        }
        let mut goblins = array![];
        let mut woken = array![];
        let mut awake = array![];
        let mut i = 0;
        for words in self.goblins {
            let goblin = GoblinTrait::load(words, ref index, @sheets);
            if goblin.awake {
                woken.append(i);
                awake.append(goblin);
            }
            goblins.append(goblin);
            i += 1;
        }
        WorldAssert::assert_awake(@woken);
        let world = World {
            clock: self.clock,
            members,
            goblins,
            woken: woken.span(),
            awake,
            killed: self.killed,
            defeated: self.defeated,
        };
        (world, sheets)
    }
}

#[generate_trait]
pub impl WorldStoreImpl of WorldStoreTrait {
    /// The words of the world, every actor's hot fields written back, the awake set's goblins in
    /// their places.
    fn store(self: World) -> Words {
        let mut members = array![];
        for member in self.members.span() {
            members.append(member.store());
        }
        let all = self.goblins.span();
        let mut goblins = array![];
        let mut from = 0;
        let mut k = 0;
        for index in self.woken {
            while from < *index {
                goblins.append(all[from].store());
                from += 1;
            }
            goblins.append(self.awake[k].store());
            from += 1;
            k += 1;
        }
        while from < all.len() {
            goblins.append(all[from].store());
            from += 1;
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
    pub const AWAKE: felt252 = 'tick: more than 8 awake';
}

/// What the pipeline leaves to the lots after it: each hook is called at its point of the order.
pub trait Rules<R> {
    /// Step 0: perception (design/18) and the awake set (`TickTrait::awake`), ENG-07.
    fn perceive(ref self: R, ref world: World);
    /// Step 1: the executor (design/19 §5.14, CBT-05) for the activation of `actor`'s `slot` on
    /// `target`, which the pipeline has concluded (field cleared, recharge set).
    fn resolve(ref self: R, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16);
    /// Step 2: the goblin at `index` acts (the AI, ENG-07); it is awake, alive, not busy, not
    /// knocked down, and did not resolve an activation in step 1.
    fn act(ref self: R, ref world: World, sheets: @Sheets, index: u32);
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
        ref self: Idle, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    ) {}
    fn act(ref self: Idle, ref world: World, sheets: @Sheets, index: u32) {}
    fn objectives(ref self: Idle, ref world: World) {}
}

#[generate_trait]
pub impl TickImpl of TickTrait {
    /// Runs up to `ticks` world ticks (an action's tick cost, design/02), stopping after a tick
    /// that defeated the adventurer.
    fn run<R, +Rules<R>, +Drop<R>>(ref world: World, sheets: @Sheets, ticks: u8, ref rules: R) {
        let mut k: u8 = 0;
        while k < ticks && !world.defeated {
            Self::tick(ref world, sheets, ref rules);
            k += 1;
        }
    }

    /// One world tick, steps 0 to 5 (design/19 §5.1).
    fn tick<R, +Rules<R>, +Drop<R>>(ref world: World, sheets: @Sheets, ref rules: R) {
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
        let (stopped, resolved) = Self::conclude(ref world, sheets, ref rules);
        if !stopped && !Self::act(ref world, sheets, resolved, ref rules) {
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

    /// Step 1: members' activations due, then the awake set's, ascending id (the set is fixed for
    /// the tick once perception has run, §5.2). Returns whether the adventurer reached 0 and the
    /// mask of the awake goblins that resolved (bit `2^k` for the `k`-th of the set).
    /// The goblins step 1 changes are pending writes, put in the set in one rebuild before the
    /// executor runs (it sees the world as it is) and when the step ends.
    fn conclude<R, +Rules<R>, +Drop<R>>(
        ref world: World, sheets: @Sheets, ref rules: R,
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
                let (slot, target) = member.conclude(sheets);
                world.set_member(i, member);
                rules.resolve(ref world, sheets, Actor::Member(i), slot, target);
                if world.is_down() {
                    return (true, 0);
                }
            }
            i += 1;
        }
        let mut pending: Pending = array![];
        let mut resolved: u128 = 0;
        let mut bit: u128 = 1;
        let count = world.awake.len();
        let mut k = 0;
        while k < count {
            let goblin = world.awake.at(k);
            let slot = *goblin.act_slot;
            let deadline = *goblin.act_deadline;
            if slot <= activation::LAST_SLOT {
                if deadline <= t && goblin.is_alive() {
                    let mut goblin = *goblin;
                    if deadline == t {
                        let (slot, target) = goblin.conclude(sheets);
                        pending.append((k, goblin));
                        world.flush(pending);
                        pending = array![];
                        resolved += bit;
                        let index = *world.woken[k];
                        rules.resolve(ref world, sheets, Actor::Goblin(index), slot, target);
                        if world.is_down() {
                            return (true, resolved);
                        }
                    } else {
                        goblin.lapse(sheets);
                        pending.append((k, goblin));
                    }
                }
            } else if slot == activation::RECOVERING && deadline < t {
                let mut goblin = *goblin;
                goblin.clear();
                pending.append((k, goblin));
            }
            bit *= 2;
            k += 1;
        }
        world.flush(pending);
        (false, resolved)
    }

    /// Step 2: every goblin of the awake set, ascending id, that is alive, not busy (activating
    /// or recovering), not knocked down, and did not resolve in step 1 (§5.2). Returns whether
    /// the adventurer reached 0.
    fn act<R, +Rules<R>, +Drop<R>>(
        ref world: World, sheets: @Sheets, resolved: u128, ref rules: R,
    ) -> bool {
        let t = world.clock;
        let woken = world.woken;
        let mut bit: u128 = 1;
        let mut k = 0;
        while k < woken.len() {
            let goblin = world.awake.at(k);
            if *goblin.act_slot == activation::NONE
                && *goblin.knocked < t
                && goblin.is_alive()
                && resolved & bit == 0 {
                rules.act(ref world, sheets, *woken[k]);
                if world.is_down() {
                    return true;
                }
            }
            bit *= 2;
            k += 1;
        }
        false
    }

    /// Step 3 (§5.8): members, then the awake set, ascending id. Out of combat is, for a member,
    /// no goblin of the tick's awake set Engaged; for a goblin, not Engaged. A goblin at 0 dies
    /// after every actor of the step, in id order. The awake set is written in one rebuild, none
    /// without an awake goblin; the frozen goblins are not read.
    fn regenerate(ref world: World) {
        let t = world.clock;
        let mut engaged = false;
        for goblin in world.awake.span() {
            if *goblin.ai == ai::ENGAGED {
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
        if world.awake.len() == 0 {
            return;
        }
        let mut awake = array![];
        for goblin in world.awake.span() {
            let mut goblin = *goblin;
            if goblin.is_alive() {
                goblin.regenerate(t);
                if goblin.health == 0 {
                    goblin.ai = ai::DEAD;
                    world.killed.append(goblin.entity);
                }
            }
            awake.append(goblin);
        }
        world.awake = awake;
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
    /// computed on the window by the caller), ties by lowest entity id. Fixed for the tick, and
    /// formed apart again in the pass that writes the flags.
    fn awake(ref world: World, distances: Span<u16>) {
        let count = world.goblins.len();
        world.assert_distances(distances);
        let all = world.goblins.span();
        let woken = world.woken;
        let values = world.awake.span();
        // Each candidate's key, `distance × 2^16 + entity`, is unique: select the 8 smallest. The
        // goblins of the set being replaced are read at their current values.
        let mut keys: Array<u32> = array![];
        let mut next = 0;
        let mut i = 0;
        while i < count {
            let goblin = if next < woken.len() && *woken[next] == i {
                next += 1;
                values[next - 1]
            } else {
                all[i]
            };
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
            let mut least: u32 = 0xFFFFFFFF;
            for key in keys {
                if (found == 0 || *key > last) && *key < least {
                    least = *key;
                }
            }
            if least == 0xFFFFFFFF {
                break;
            }
            last = least;
            found += 1;
        }
        let mut goblins = array![];
        let mut now: Array<u32> = array![];
        let mut awake = array![];
        let mut next = 0;
        let mut i = 0;
        while i < count {
            let mut goblin = if next < woken.len() && *woken[next] == i {
                next += 1;
                *values[next - 1]
            } else {
                *all[i]
            };
            goblin.awake = found > 0 && *keys[i] <= last;
            if goblin.awake {
                now.append(i);
                awake.append(goblin);
            }
            goblins.append(goblin);
            i += 1;
        }
        world.goblins = goblins;
        world.woken = now.span();
        world.awake = awake;
    }
}

#[generate_trait]
pub impl WorldImpl of WorldTrait {
    /// A world of `goblins` (ascending entity id), its awake set formed from their flags.
    fn new(
        clock: u32,
        members: Array<Member>,
        goblins: Array<Goblin>,
        killed: Array<u16>,
        defeated: bool,
    ) -> World {
        let (woken, awake) = Self::split(goblins.span());
        World { clock, members, goblins, woken, awake, killed, defeated }
    }

    /// The awake set of `goblins`: the indexes and values of those flagged awake, ascending, at
    /// most `MAX_AWAKE` (design/02).
    fn split(goblins: Span<Goblin>) -> (Span<u32>, Array<Goblin>) {
        let mut woken = array![];
        let mut awake = array![];
        let mut i = 0;
        for goblin in goblins {
            if *goblin.awake {
                woken.append(i);
                awake.append(*goblin);
            }
            i += 1;
        }
        WorldAssert::assert_awake(@woken);
        (woken.span(), awake)
    }

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
        let members = self.members.span();
        let mut rebuilt = array![];
        rebuilt.append_span(members.slice(0, index));
        rebuilt.append(member);
        rebuilt.append_span(members.slice(index + 1, members.len() - index - 1));
        self.members = rebuilt;
    }

    /// How many goblins the world holds.
    #[inline(always)]
    fn goblin_count(self: @World) -> u32 {
        self.goblins.len()
    }

    /// The indexes of the awake set, ascending.
    #[inline(always)]
    fn woken(self: @World) -> Span<u32> {
        *self.woken
    }

    /// The position of goblin `index` in the awake set, if it is awake.
    fn position(self: @World, index: u32) -> Option<u32> {
        let mut k = 0;
        for i in *self.woken {
            if *i == index {
                return Some(k);
            }
            k += 1;
        }
        None
    }

    /// Goblin `index` as it is now.
    fn goblin(self: @World, index: u32) -> Goblin {
        match self.position(index) {
            Some(k) => *self.awake[k],
            None => *self.goblins[index],
        }
    }

    /// Writes goblin `index`: in the awake set (at most `MAX_AWAKE` goblins rebuilt) if it is
    /// awake and stays so; in the array if it is frozen and stays so; the set is formed again if
    /// the flag changes (step 0).
    fn set_goblin(ref self: World, index: u32, goblin: Goblin) {
        match self.position(index) {
            Some(k) => if goblin.awake {
                self.flush(array![(k, goblin)]);
                return;
            },
            None => if !goblin.awake {
                self.goblins = Self::rebuilt(self.goblins.span(), index, goblin);
                return;
            },
        }
        let all = Self::rebuilt(self.current().span(), index, goblin);
        let (woken, awake) = Self::split(all.span());
        self.goblins = all;
        self.woken = woken;
        self.awake = awake;
    }

    /// Every goblin as it is now, the awake set's in their places: one pass.
    fn current(self: @World) -> Array<Goblin> {
        let all = self.goblins.span();
        let mut goblins = array![];
        let mut from = 0;
        let mut k = 0;
        for index in *self.woken {
            goblins.append_span(all.slice(from, *index - from));
            goblins.append(*self.awake[k]);
            from = *index + 1;
            k += 1;
        }
        goblins.append_span(all.slice(from, all.len() - from));
        goblins
    }

    /// `goblins` with `goblin` at `index`, the unchanged runs copied whole.
    fn rebuilt(goblins: Span<Goblin>, index: u32, goblin: Goblin) -> Array<Goblin> {
        let mut rebuilt = array![];
        rebuilt.append_span(goblins.slice(0, index));
        rebuilt.append(goblin);
        rebuilt.append_span(goblins.slice(index + 1, goblins.len() - index - 1));
        rebuilt
    }

    /// Puts the pending writes in the awake set, in one rebuild of it: its unchanged runs are
    /// copied whole between the writes. Nothing without a write.
    fn flush(ref self: World, pending: Pending) {
        if pending.len() == 0 {
            return;
        }
        let awake = self.awake.span();
        let mut rebuilt: Array<Goblin> = array![];
        let mut from = 0;
        for (k, goblin) in pending {
            rebuilt.append_span(awake.slice(from, k - from));
            rebuilt.append(goblin);
            from = k + 1;
        }
        rebuilt.append_span(awake.slice(from, awake.len() - from));
        self.awake = rebuilt;
    }

    /// A goblin at 0 dies at once (§5.13): health 0, dead (its remains), out of the awake set's
    /// work, recorded in resolution order (`GoblinKilled`). For the executor.
    fn kill(ref self: World, index: u32) {
        let mut goblin = self.goblin(index);
        if !goblin.is_alive() {
            return;
        }
        goblin.health = 0;
        goblin.ai = ai::DEAD;
        self.killed.append(goblin.entity);
        self.set_goblin(index, goblin);
    }
}

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

    /// The awake set holds at most `MAX_AWAKE` goblins (design/02; CBT-02b: the tick's upper
    /// bound counts 8 awake goblins, and a larger set is refused, not priced). Checked where the
    /// set is formed (CBT-02d), so that no tick runs over a larger one.
    #[inline(always)]
    fn assert_awake(woken: @Array<u32>) {
        assert(woken.len() <= MAX_AWAKE, errors::AWAKE);
    }
}

#[cfg(test)]
pub mod fixtures;

/// The pipeline's unit tests (CBT-02, CBT-02d; D-167): the worked examples of design/19 §10 whose
/// steps are the pipeline's (10.1's step 3, 10.2, 10.3, 10.5, 10.6, 10.9), every rule of the steps
/// one by one, the awake set apart, the checks. Determinism and the cost of a tick are
/// `tests/test_tick.cairo`'s, with the benchmarks' states.
#[cfg(test)]
mod tests {
    use crate::models::goblin::{GoblinTickTrait, GoblinTrait};
    use crate::models::index::{GoblinWords, MemberWords};
    use crate::models::member::{MemberTickTrait, MemberTrait};
    use crate::types::MAX_CLOCK;
    use crate::types::combat::{activation, skill_kind};
    use crate::types::tick::{
        Content, ContentTrait, NO_SLOT, PotionSheet, SkillSheet, ai, flag, status,
    };
    use super::fixtures::{Fixture, HOB, RUNT, Script, activation_of, run};
    use super::{
        Actor, Idle, TickTrait, Words, WordsTrait, WorldAssert, WorldStoreTrait, WorldTrait,
    };

    // design/19 §10.3, the degeneration: Poisoned to 72, Bleeding to 77 from step 2 of tick 70,
    // regeneration 0. Ticks 70–72 lose 14 each (−7 pips), ticks 73–75 lose 6 (−3): 60 in
    // all.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_condition_degeneration() {
        let mut spec = Fixture::spec();
        spec.conditions = [77, 72, 0, 0];
        let member = Fixture::member(spec);
        let mut world = Fixture::world(69, array![member], array![Fixture::goblin(17, HOB)]);
        run(ref world, 3);
        assert(*world.members.at(0).health == 400 - 42, 'ticks 70-72: -14 each');
        run(ref world, 3);
        assert(*world.members.at(0).health == 400 - 60, 'ticks 73-75: -6 each');
        assert(world.clock == 75, 'clock');
    }

    // design/19 §10.1, step 3 of ticks 42–44: goblin 24 Burning to 44, health regeneration 0,
    // goes 87 → 73 → 59 → 45; tick 45 changes nothing.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_burning_goblin() {
        let mut goblin = Fixture::goblin(24, HOB);
        goblin.health = 87;
        goblin.burning = 44;
        let mut world = Fixture::only(41, goblin);
        run(ref world, 1);
        assert(world.goblin(0).health == 73, 'tick 42');
        run(ref world, 2);
        assert(world.goblin(0).health == 45, 'tick 44');
        run(ref world, 1);
        assert(world.goblin(0).health == 45, 'tick 45: burning over');
    }

    // design/19 §10.2: the smash started in step 2 of tick 50 (activation 3: A = 53); Skullring in
    // the action phase at clock 51 knocks the Hobgoblin down to 53 and interrupts it at t0 = 52:
    // the field goes to none, R = 61. It skips ticks 52 and 53, acts at 54; the smash is usable in
    // step 2 of tick 62 (T > R).
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_interrupt() {
        let sheets = Fixture::sheets();
        let mut goblin = Fixture::goblin(40, HOB);
        goblin.start(0, 0, 3, 50);
        assert(activation_of(@goblin) == (0, 0, 53), 'A = 53');
        // Clock 51: the knock-down (t0 = 52, D = 53) interrupts.
        goblin.knocked = 53;
        goblin.interrupt(52, @sheets);
        assert(activation_of(@goblin) == (activation::NONE, 0, 0), 'field none');
        assert(goblin.recharge(0) == 61, 'R = 61');
        let mut world = Fixture::only(51, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @sheets, 3, ref rules);
        assert(rules.acts.span() == array![(54, 40)].span(), 'acts again at 54 only');
        assert(rules.resolved.len() == 0, 'no resolution');
        // A recovery is not an activation: an interrupt changes nothing.
        let mut goblin = Fixture::goblin(40, HOB);
        goblin.recover(3, 60);
        let before = goblin;
        goblin.interrupt(61, @sheets);
        assert(goblin == before, 'recovery kept');
    }

    // design/19 §10.5: goblin 30 starts a 3-tick activation in step 2 of tick 100 (A = 103,
    // recharge 10); it is frozen from tick 103 to 106 and nothing of it changes; awake at 107, its
    // activation has lapsed at 103: none, R = 112, and it acts in step 2 of 107.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_lapse() {
        let mut goblin = Fixture::goblin(30, HOB);
        goblin.start(0, 0, 3, 100);
        goblin.awake = false;
        goblin.health = 50;
        goblin.bleeding = 105;
        let frozen = goblin;
        let mut world = Fixture::only(102, goblin);
        run(ref world, 4);
        assert(world.goblin(0) == frozen, 'frozen: nothing read or written');
        let mut goblin = world.goblin(0);
        goblin.awake = true;
        world.set_goblin(0, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @Fixture::sheets(), 1, ref rules);
        let goblin = @world.goblin(0);
        assert(activation_of(goblin) == (activation::NONE, 0, 0), 'lapsed');
        assert(goblin.recharge(0) == 112, 'R = 103 + 10 - 1');
        assert(*goblin.health == 50, 'bleeding lost while frozen');
        assert(rules.resolved.len() == 0, 'a lapse does not resolve');
        assert(rules.acts.span() == array![(107, 30)].span(), 'acts at 107');
        // A later recharge already stored is kept.
        let mut goblin = Fixture::goblin(30, HOB);
        goblin.start(0, 0, 3, 100);
        goblin.set_recharge(0, 200);
        let mut world = Fixture::only(106, goblin);
        run(ref world, 1);
        assert(world.goblin(0).recharge(0) == 200, 'later recharge kept');
    }

    // design/19 §10.9: a weapon of cost k = 2 in step 2 of tick 50. A plain attack recovers to
    // B = 51 and acts again at 52; an attack skill with activation 1 resolves at 51, does not act
    // in 51, has no recovery (k < n + 2) and acts at 52; with k = 3 it recovers to B = 52 and acts
    // at 53.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_activated_attack_cost() {
        let sheets = Fixture::sheets();
        // Plain attack, k = 2.
        let mut goblin = Fixture::goblin(9, RUNT);
        goblin.recover(2, 50);
        assert(activation_of(@goblin) == (activation::RECOVERING, 0, 51), 'B = 51');
        let mut world = Fixture::only(50, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @sheets, 2, ref rules);
        assert(rules.acts.span() == array![(52, 9)].span(), 'plain: acts at 52');
        assert(activation_of(@world.goblin(0)) == (activation::NONE, 0, 0), 'recovery cleared');
        // Attack skill with activation 1 (caste 2's slot 1), k = 2.
        let mut goblin = Fixture::goblin(9, RUNT);
        goblin.start(1, 0, 1, 50);
        let mut world = Fixture::only(50, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @sheets, 2, ref rules);
        assert(rules.resolved.span() == array![(51, Actor::Goblin(0), 1)].span(), 'resolves at 51');
        assert(rules.acts.span() == array![(52, 9)].span(), 'n = 1, k = 2: acts at 52');
        assert(world.goblin(0).recharge(1) == 56, 'R = 51 + 6 - 1');
        // The same with k = 3: recovering to B = 52, acts at 53 = 50 + max(3, 2).
        let sheets = Content {
            castes: array![Fixture::caste(HOB, 1), Fixture::caste(RUNT, 3)].span(),
            ..Fixture::content(),
        }
            .sheets();
        let mut goblin = Fixture::goblin(9, RUNT);
        goblin.start(1, 0, 1, 50);
        let mut world = Fixture::only(50, goblin);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @sheets, 1, ref rules);
        assert(activation_of(@world.goblin(0)) == (activation::RECOVERING, 0, 52), 'B = 52');
        TickTrait::run(ref world, @sheets, 2, ref rules);
        assert(rules.acts.span() == array![(53, 9)].span(), 'n = 1, k = 3: acts at 53');
    }

    // design/19 §10.1 and §10.6, a member's activation: Cinder Ring (activation 2, recharge 12)
    // started at clock 40 resolves in step 1 of 42 with R = 53; the spell of §10.6 started at
    // clock 200 with activation 2 (after the quick-cast bonus) and interrupted in step 2 of 201
    // recharges from 201.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_example_member_activation() {
        let sheets = Fixture::sheets();
        let mut member = Fixture::member(Fixture::spec());
        member.start(1, 57, 2, 40);
        assert(
            member.act_slot == 1 && member.act_target == 57 && member.act_deadline == 42, 'A = 42',
        );
        let mut world = Fixture::world(40, array![member], array![]);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @sheets, 1, ref rules);
        assert(rules.resolved.len() == 0, 'not at 41');
        TickTrait::run(ref world, @sheets, 1, ref rules);
        assert(rules.resolved.span() == array![(42, Actor::Member(0), 1)].span(), 'resolves at 42');
        let member = world.members.at(0);
        assert(*member.act_slot == NO_SLOT && *member.act_deadline == 0, 'cleared');
        assert(member.recharge(1) == 53, 'R = 53');
        // §10.6: interrupted at 201.
        let mut member = Fixture::member(Fixture::spec());
        member.start(3, 0, 2, 200);
        assert(member.act_deadline == 202, 'A = 202');
        member.interrupt(201, @sheets);
        assert(member.act_slot == NO_SLOT, 'interrupted');
        assert(member.recharge(3) == 210, 'R = 201 + 10 - 1');
        // An instant skill used at clock 60 recharges from 61; an activation below 1 is 1 (§6).
        let mut member = Fixture::member(Fixture::spec());
        member.use_instant(0, 60, @sheets);
        assert(member.recharge(0) == 65, 'R = 61 + 5 - 1');
        member.start(2, 0, 0, 60);
        assert(member.act_deadline == 61, 'activation at least 1');
        // Every recharge slot is its own lane.
        for slot in 0..8_u8 {
            member.set_recharge(slot, 1000 + slot.into());
        }
        for slot in 0..8_u8 {
            assert(member.recharge(slot) == 1000 + slot.into(), 'recharge lanes');
        }
    }

    // §5.8: regeneration from the snapshot and held effects while they last, pips clamped to +10;
    // energy in thirds up to its max. `MemberTrait::load` derives an effect's pips once: a skill's
    // at its rank, a potion's through its belt slot.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_regeneration() {
        // Skill 1 regenerates 2…6 pips; the bar's other skills (2–8) are read for its
        // adrenaline cap.
        let mut skills = array![
            SkillSheet {
                id: 1,
                kind: skill_kind::SPELL,
                adrenaline: 0,
                activation: 0,
                recharge: 0,
                regen0: 2,
                regen12: 6,
            },
        ];
        for id in 2..9_u16 {
            skills.append(Fixture::skill(id, skill_kind::SPELL, 1, 10));
        }
        let content = Content {
            skills: skills.span(),
            potions: array![PotionSheet { id: 101, regen: 3 }].span(),
            castes: array![].span(),
        };
        let mut spec = Fixture::spec();
        spec
            .effects =
                [(1, false, 10, 12), (1, true, MAX_CLOCK, 0), (1, false, 4, 12), (0, false, 0, 0)];
        spec.energy = 55;
        spec.health_regen = 1;
        spec.energy_regen = 4;
        let member = Fixture::load_member(Fixture::member_words(spec), @content);
        assert(member.effect_regen == [6, 3, 6, 0], 'effect pips');
        assert(member.effect_deadlines == [10, MAX_CLOCK, 4, 0], 'effect deadlines');
        assert(member.max_health == 480 && member.max_energy == 60, 'maxima');
        assert(member.health_regen == 1 && member.energy_regen == 4, 'regeneration');
        let mut world = Fixture::world(4, array![member], array![]);
        let mut rules = Idle {};
        let sheets = content.sheets();
        TickTrait::run(ref world, @sheets, 1, ref rules);
        let after = world.members.at(0);
        assert(*after.health == 400 + 2 * 10, '1 + 6 + 3 pips');
        assert(*after.energy == 59, 'energy +4 thirds');
        TickTrait::run(ref world, @sheets, 1, ref rules);
        assert(*world.members.at(0).energy == 60, 'energy at its max');
        // Near max health: clamped.
        let mut spec = Fixture::spec();
        spec.health = 479;
        spec.health_regen = 10;
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
        run(ref world, 1);
        assert(*world.members.at(0).health == 480, 'max health');
    }

    // design/20 §6 test 9 (DES06-7, DS-29): step 3's pip sum at its extremes computes without
    // overflow and clamps to ±10: −10 (the field at 0), four −10 effects and the three
    // conditions give −64, 20 health lost; +10 and four +10 effects give +50, 20 health gained.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_regeneration_extremes() {
        let mut spec = Fixture::spec();
        spec.health_regen = -10;
        spec.effect_regen = [-10; 4];
        spec.effects = [(1, false, 99, 0); 4];
        spec.conditions = [99, 99, 99, 0];
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
        run(ref world, 1);
        assert(*world.members.at(0).health == 380, '-64 pips: -20');
        let mut spec = Fixture::spec();
        spec.health = 300;
        spec.health_regen = 10;
        spec.effect_regen = [10; 4];
        spec.effects = [(1, false, 99, 0); 4];
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
        run(ref world, 1);
        assert(*world.members.at(0).health == 320, '+50 pips: +20');
    }

    // §5.8 step 3, FX-12, D-157 E: out of combat (no goblin of the awake set Engaged) a member
    // loses 1 quarter strike a tick, floored at 0; a goblin not Engaged too; an Engaged one keeps
    // it.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_adrenaline_decay() {
        let mut spec = Fixture::spec();
        spec.adrenaline = 5;
        let mut alerted = Fixture::goblin(8, HOB);
        alerted.ai = ai::ALERTED;
        alerted.adrenaline = 1;
        let mut frozen_engaged = Fixture::goblin(9, HOB);
        frozen_engaged.awake = false;
        let mut world = Fixture::world(
            0, array![Fixture::member(spec)], array![alerted, frozen_engaged],
        );
        run(ref world, 2);
        assert(*world.members.at(0).adrenaline == 3, 'member: -1 a tick');
        assert(world.goblin(0).adrenaline == 0, 'goblin: floored at 0');
        // In combat: an awake goblin is Engaged.
        let mut engaged = Fixture::goblin(8, HOB);
        engaged.adrenaline = 4;
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![engaged]);
        run(ref world, 1);
        assert(*world.members.at(0).adrenaline == 5, 'member in combat keeps');
        assert(world.goblin(0).adrenaline == 4, 'engaged goblin keeps');
    }

    // §5.13: goblins at 0 in step 3 die after every actor of the step, in id order; a dead goblin
    // is no longer touched. Goblin energy regenerates in thirds up to the caste's.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_deaths_in_step_3() {
        let mut a = Fixture::goblin(8, HOB);
        a.health = 10;
        a.burning = 5;
        let mut b = Fixture::goblin(12, HOB);
        b.health = 14;
        b.burning = 5;
        b.bleeding = 5;
        let mut c = Fixture::goblin(20, HOB);
        c.energy = 29;
        let mut world = Fixture::world(
            0, array![Fixture::member(Fixture::spec())], array![a, b, c],
        );
        run(ref world, 1);
        assert(world.killed.span() == array![8, 12].span(), 'killed in id order');
        assert(world.goblin(0).ai == ai::DEAD && world.goblin(1).ai == ai::DEAD, 'dead');
        assert(world.goblin(0).health == 0, 'at 0');
        assert(world.goblin(2).energy == 30, 'energy at 10 x 3');
        let dead = world.goblin(0);
        run(ref world, 1);
        assert(world.killed.len() == 2 && world.goblin(0) == dead, 'dead untouched');
        // The executor's kill: at once, once.
        world.kill(2);
        world.kill(2);
        assert(world.killed.span() == array![8, 12, 20].span(), 'kill once');
        assert(world.goblin(2).health == 0 && !world.goblin(2).is_alive(), 'killed');
    }

    // §5.13, FX-8: the adventurer at 0 in step 3 is down at step 5 and the run stops; at 0 in step
    // 2 the tick stops at once (no later act, no step 3) and step 5 still runs.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_defeat() {
        let mut spec = Fixture::spec();
        spec.health = 6;
        spec.conditions = [9, 9, 9, 0];
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
        run(ref world, 3);
        let member = world.members.at(0);
        assert(*member.health == 0 && *member.status == status::DOWN, 'down');
        assert(world.defeated && world.clock == 1, 'stopped after the tick');
        // At 0 in step 2 (goblin 8's act): goblin 9 does not act, nobody regenerates.
        let mut a = Fixture::goblin(8, HOB);
        a.health = 50;
        a.bleeding = 9;
        let b = Fixture::goblin(9, HOB);
        let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], array![a, b]);
        let mut rules: Script = Default::default();
        rules.kill_member_at = 1;
        TickTrait::run(ref world, @Fixture::sheets(), 2, ref rules);
        assert(rules.acts.span() == array![(1, 8)].span(), 'stopped at once');
        assert(world.goblin(0).health == 50, 'no step 3');
        assert(world.defeated && *world.members.at(0).status == status::DOWN, 'step 5 ran');
    }

    // Step 2 (§5.2): a knocked-down goblin, a busy one (activating, recovering), a frozen one and
    // a dead one do not act; the others act in ascending id order.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_who_acts() {
        let mut knocked = Fixture::goblin(8, HOB);
        knocked.knocked = 1;
        let mut activating = Fixture::goblin(9, HOB);
        activating.start(0, 0, 3, 0);
        let mut recovering = Fixture::goblin(10, HOB);
        recovering.recover(3, 0);
        let mut frozen = Fixture::goblin(11, HOB);
        frozen.awake = false;
        let mut dead = Fixture::goblin(12, HOB);
        dead.ai = ai::DEAD;
        let goblins = array![
            knocked, activating, recovering, frozen, dead, Fixture::goblin(13, HOB),
            Fixture::goblin(14, RUNT),
        ];
        let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @Fixture::sheets(), 1, ref rules);
        assert(rules.acts.span() == array![(1, 13), (1, 14)].span(), 'acts');
    }

    // Step 0: the flags "since the last tick" and "hit this tick" clear; `HALVED` stays.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_flags_cleared() {
        let mut spec = Fixture::spec();
        spec.flags = flag::TURNED + flag::INSTANT + flag::HIT + flag::HALVED;
        let mut world = Fixture::world(0, array![Fixture::member(spec)], array![]);
        run(ref world, 1);
        assert(*world.members.at(0).flags == flag::HALVED, 'flags');
    }

    // Step 0's awake set (§5.2, design/02): the 8 nearest goblins alive and not asleep, ties by
    // lowest id; an asleep or dead goblin never. The set is formed apart, and a goblin of the set
    // it replaces is read at its current value.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_awake_set() {
        let mut goblins = array![];
        for entity in 8..19_u16 {
            let mut goblin = Fixture::goblin(entity, HOB);
            goblin.awake = entity == 18;
            if entity == 8 {
                goblin.ai = ai::ASLEEP;
            } else if entity == 9 {
                goblin.ai = ai::DEAD;
            }
            goblins.append(goblin);
        }
        let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
        // Goblin 18, awake before, has changed in the set: its current value is the one read.
        let mut changed = world.goblin(10);
        changed.health = 77;
        world.set_goblin(10, changed);
        // Entities 8–18 at distances 1, 1, 5, 3, 3, 9, 2, 3, 4, 3, 6.
        TickTrait::awake(ref world, array![1, 1, 5, 3, 3, 9, 2, 3, 4, 3, 6].span());
        let mut awake = array![];
        for i in 0..world.goblin_count() {
            if world.goblin(i).awake {
                awake.append(world.goblin(i).entity);
            }
        }
        // Candidates by (distance, id): 14 (2), 11, 12, 15, 17 (3), 16 (4), 10 (5), 18 (6), 13 (9).
        assert(awake.span() == array![10, 11, 12, 14, 15, 16, 17, 18].span(), 'nearest 8');
        assert(world.woken() == array![2, 3, 4, 6, 7, 8, 9, 10].span(), 'the set apart');
        assert(world.goblin(10).health == 77, 'current value kept');
    }

    // AUD-182-5 (design/19 §5.11, §5.13, FX-8): a member already at 0 when the tick begins (a
    // trap on its move, in the action phase) stops it at once: the clock does not advance, no
    // goblin acts, nothing regenerates, and step 5's defeat and objectives run.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_member_down_before_the_tick() {
        let mut spec = Fixture::spec();
        spec.health = 0;
        let mut goblin = Fixture::goblin(8, HOB);
        goblin.bleeding = 99;
        let mut world = Fixture::world(49, array![Fixture::member(spec)], array![goblin]);
        let mut rules: Script = Default::default();
        TickTrait::run(ref world, @Fixture::sheets(), 3, ref rules);
        assert(rules.acts.len() == 0, 'no goblin acts');
        assert(world.clock == 49, 'the clock stays');
        assert(world.goblin(0).health == 100, 'no step 3');
        assert(world.defeated && *world.members.at(0).status == status::DOWN, 'defeat ran');
    }

    // CBT-02d: the awake set lives apart. A goblin is read at its current value; a write to an
    // awake goblin stays in the set, a write to a frozen one in the array; a changed flag forms the
    // set again; the words put every goblin back in its place.
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_awake_set_apart() {
        let mut frozen = Fixture::goblin(8, HOB);
        frozen.awake = false;
        let awake = Fixture::goblin(9, HOB);
        let mut last = Fixture::goblin(10, RUNT);
        last.awake = false;
        let mut world = Fixture::world(
            7, array![Fixture::member(Fixture::spec())], array![frozen, awake, last],
        );
        assert(world.woken() == array![1].span() && world.goblin_count() == 3, 'formed');
        let mut changed = world.goblin(1);
        changed.health = 11;
        world.set_goblin(1, changed);
        let mut still = world.goblin(2);
        still.health = 22;
        world.set_goblin(2, still);
        assert(world.goblin(1).health == 11 && world.goblin(2).health == 22, 'written');
        assert(world.woken() == array![1].span(), 'the same set');
        // Goblin 0 wakes and goblin 1 falls asleep: the set is formed again, the values kept.
        let mut woken = world.goblin(0);
        woken.awake = true;
        world.set_goblin(0, woken);
        assert(world.woken() == array![0, 1].span(), 'woken');
        let mut asleep = world.goblin(1);
        asleep.awake = false;
        world.set_goblin(1, asleep);
        assert(world.woken() == array![0].span(), 'asleep');
        assert(world.goblin(1).health == 11 && !world.goblin(1).awake, 'its value kept');
        // The words, and the world loaded from them, hold every goblin as it is.
        let (one, two) = (world.goblin(1).store(), world.goblin(2).store());
        let words = world.store();
        assert(*words.goblins.at(1) == one && *words.goblins.at(2) == two, 'stored in place');
        let (again, _) = words.load(@Fixture::content());
        assert(again.woken() == array![0].span(), 'loaded apart');
        assert(again.goblin(1).health == 11 && again.goblin(2).health == 22, 'loaded');
    }

    // The checks are the Assert impls', with their errors.
    #[test]
    #[should_panic(expected: 'tick: too many goblins')]
    #[available_gas(l2_gas: 999999999)]
    fn test_world_assert_goblins() {
        let mut goblins = array![];
        let mut i: u16 = 0;
        while i < 101 {
            let mut goblin = Fixture::goblin(8 + i, HOB);
            goblin.awake = false;
            goblins.append(goblin);
            i += 1;
        }
        let world = Fixture::world(0, array![], goblins);
        world.assert_goblins();
    }

    #[test]
    #[should_panic(expected: 'tick: one distance a goblin')]
    #[available_gas(l2_gas: 999999999)]
    fn test_world_assert_distances() {
        let world = Fixture::world(0, array![], array![Fixture::goblin(8, HOB)]);
        world.assert_distances(array![].span());
    }

    /// Nine goblins flagged awake, the member concluding bar slot 1 at 1.
    fn nine_awake() -> (Array<MemberWords>, Array<GoblinWords>) {
        let mut member = Fixture::member(Fixture::spec());
        member.start(1, 0, 1, 0);
        let mut goblins = array![];
        let mut i: u16 = 0;
        while i < 9 {
            goblins.append(Fixture::goblin(8 + i, HOB).store());
            i += 1;
        }
        (array![member.store()], goblins)
    }

    // More than 8 awake goblins is not a state of the game (design/02): the set is refused where it
    // is formed, so no tick runs over it, even one the member's defeat would stop in step 1 before
    // the goblins' turn (CBT-02d, #196's review). The world made of them.
    #[test]
    #[should_panic(expected: 'tick: more than 8 awake')]
    #[available_gas(l2_gas: 999999999)]
    fn test_world_assert_awake() {
        let mut goblins = array![];
        let mut i: u16 = 0;
        while i < 9 {
            goblins.append(Fixture::goblin(8 + i, HOB));
            i += 1;
        }
        let mut world = Fixture::world(0, array![Fixture::member(Fixture::spec())], goblins);
        run(ref world, 1);
    }

    // The same through the library call's load.
    #[test]
    #[should_panic(expected: 'tick: more than 8 awake')]
    #[available_gas(l2_gas: 999999999)]
    fn test_world_assert_awake_loaded() {
        let (members, goblins) = nine_awake();
        let words = Words { clock: 0, members, goblins, killed: array![], defeated: false };
        let (mut world, sheets) = words.load(@Fixture::content());
        let mut rules: Script = Default::default();
        rules.kill_on_resolve = true;
        TickTrait::run(ref world, @sheets, 1, ref rules);
    }

    // The same when perception wakes a ninth in step 0, the member dying at its resolution in
    // step 1: refused in step 0, before step 1 can return on the defeat.
    #[test]
    #[should_panic(expected: 'tick: more than 8 awake')]
    #[available_gas(l2_gas: 999999999)]
    fn test_world_assert_awake_perceived() {
        let (members, goblins) = nine_awake();
        let mut goblins = goblins;
        let mut frozen = goblins.pop_front().unwrap();
        frozen.awake = false;
        let mut all = array![frozen];
        all.append_span(goblins.span());
        let words = Words { clock: 0, members, goblins: all, killed: array![], defeated: false };
        let (mut world, sheets) = words.load(@Fixture::content());
        assert(world.woken().len() == 8, 'eight awake');
        let mut rules: Script = Default::default();
        rules.kill_on_resolve = true;
        rules.wake = 1;
        TickTrait::run(ref world, @sheets, 1, ref rules);
    }

    // Without the ninth, the same tick stops on the defeat in step 1: the member's resolution
    // takes it to 0 (the state the two tests above refuse).
    #[test]
    #[available_gas(l2_gas: 999999999)]
    fn test_defeat_in_step_1_with_eight_awake() {
        let (members, mut goblins) = nine_awake();
        let _ = goblins.pop_front();
        let words = Words { clock: 0, members, goblins, killed: array![], defeated: false };
        let (mut world, sheets) = words.load(@Fixture::content());
        let mut rules: Script = Default::default();
        rules.kill_on_resolve = true;
        TickTrait::run(ref world, @sheets, 1, ref rules);
        assert(rules.resolved.span() == array![(1, Actor::Member(0), 1)].span(), 'resolved');
        assert(world.defeated && rules.acts.len() == 0, 'stopped in step 1');
    }
}
