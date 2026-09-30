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
//! array of them rebuilds it whole (about 590,000 L2 gas at `MAX_GOBLINS`). The steps write only the
//! awake set (§5.2, at most `MAX_AWAKE`), fixed for the tick once perception has run, so its goblins
//! live apart, in `World.awake`, beside their indexes (`World.woken`); `World.goblins` keeps the
//! frozen ones. The pipeline
//! - reads and writes the awake set alone: a write rebuilds at most 8 goblins, and CBT-02b's pending
//!   writes (`Pending`) still share one rebuild between two executor hooks;
//! - forms the set when the world is made (`WorldTrait::new`, `WordsTrait::load`), and again only
//!   when an awake flag changes (`TickTrait::awake` in step 0, `WorldTrait::set_goblin`); it refuses
//!   a set above `MAX_AWAKE` there (design/02), so no tick runs over one;
//! - puts the set back in its places once, when the call stores the words (`WorldStoreTrait`).
//! A goblin is read through `WorldTrait::goblin` and written through `set_goblin` and `kill`. A hook
//! after step 0 does not wake a goblin or put one to sleep (§5.2: the set is fixed for the tick).
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
    fn resolve(
        ref self: R, ref world: World, sheets: @Sheets, actor: Actor, slot: u8, target: u16,
    );
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
