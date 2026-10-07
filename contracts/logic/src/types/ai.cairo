//! The goblins' acts (ENG-07; design/04 *Goblin AI*, design/05 *AI profiles*, design/19 §5.1 step
//! 2, §5.2, §5.11): step 2 as one hook for the step (`Rules::act`), which `AiLibrary` runs in one
//! call a tick (ENG-07 Open question 1, candidate C). Step 0's perception and the awake set are
//! one pass over the goblins (`TickTrait::perceive`, L4, D-172). A value type's behaviour over the
//! `World`, as the pipeline's: it sits in `types/` (docs/CAIRO.md §7, D-147).
//!
//! **The step** (`AiTrait::step`): every goblin of the awake set, ascending id, alive, not busy
//! (activating or recovering), not knocked down, and that did not resolve in step 1 (§5.2), acts
//! once, on the state the previous ones left. **The flood** (design/04, D-127): one breadth-first
//! flood from the adventurer on the window, on the occupancy frozen when the step starts (every
//! living goblin's tile and every other member's), stopped at 15 layers (`FLOOD_DEPTH`); computed
//! only when a goblin first needs a step, shared by every walker after it. A walker steps to its
//! free neighbour nearest the adventurer (`Flood::next_step`, the current occupancy blocked, ties
//! by the lowest tile index), away from it when fleeing (`next_step_away`); one beyond the 15
//! layers gets no step and holds its tile (D-127). The hook never wakes or puts to sleep a goblin
//! (§5.2: the set is fixed for the tick).
//!
//! **One goblin's act** (design/04's state machine, its *Engaged* row): its target is the nearest
//! living member, ties by the lowest index (M-3; one member in the MVP).
//! - **Engaged**: the first usable skill of its caste's priority list (not recharging, its energy
//!   and adrenaline there, its target legal and in reach: a `FOE` the target, an `ALLY` or `SELF`
//!   itself); with activation `n ≥ 1` it starts (`A = T + n`), else it lands now through the
//!   executor (`Carry`) and recharges from `T`, an attack skill recovering for its weapon's `k`;
//!   else its weapon if the target is in its reach (`k > 1` recovers, FX-15); else a step toward
//!   the target.
//! - **Alerted**: a step toward the adventurer (below).
//! - **Fleeing**: a step away; cornered (no step), it is Engaged again (design/04).
//! - **Asleep, on watch, returning**: nothing.
//! A step sets the facing toward the tile entered (design/04: a move sets facing); a crippled step
//! costs 2 and recovers until `B = T + 1` (§5.2, FX-15, unless a `MOVEMENT` effect is held, FX-18);
//! entering a tile that holds an unused trap triggers it (`Enter`, §5.11), which ends the act.
//!
//! **Readings this lot fixed where the design is silent** (each in the report, reversible):
//! - the caste sheets carry no AI profile (`CasteSheet` has none; design/05's seven are not
//!   encoded anywhere): every caste runs the *Engaged* row above, design/04's own (the profiles
//!   are a later lot's, with their encoding);
//! - an Alerted goblin "knows the last tile where the adventurer was seen" (design/18): the noise
//!   that alerts it is a fight, so that tile is the adventurer's, and it walks the tick's flood;
//! - a `TRAP` skill is skipped by the AI (design/20: the Trapper's placement profile is post-MVP,
//!   DS-16), as a skill it cannot use.

use hexx::finders::bfs::Bfs;
use hexx::finders::flood::{Flood, FloodTrait};
use crate::models::goblin::{
    Goblin, GoblinPlaceTrait, GoblinTickTrait, GoblinTrait, GoblinConditionTrait,
};
use crate::models::member::MemberSnapshotTrait;
use crate::types::action::Carry;
use crate::models::chunk::object;
use crate::types::combat::{Placer, PlacerTrait, activation, skill_kind};
use crate::types::effect::{kind, target};
use crate::interface::{ITrapLibraryDispatcherTrait, ITrapLibraryLibraryDispatcher};
use crate::models::member::MemberTrait;
use crate::types::executor::{
    Board, BoardTrait, Carrier, Delegate, ExecutorTrait, Levered, Levers, ORIGIN,
};
use crate::types::trap::{Ground, TrapTrait};
use crate::types::tick::{ABSENT, Sheets, ai};
use crate::types::window::{FAR, HEIGHT, WIDTH, WindowTrait};
use crate::types::world::{Actor, Words, World, WorldTrait};

/// The flood's depth (D-127): a goblin farther on foot holds its tile.
pub const FLOOD_DEPTH: u8 = 15;

/// What a goblin's act calls besides the executor (`Carry`): the trap of the tile it entered
/// (§5.11), through `TrapLibrary` in the class (`AiLibrary`), in process in the tests.
pub trait Enter<R> {
    /// `entrant` entered the window's `position`: its unused trap triggers if any; whether it did.
    fn enter(ref self: R, ref world: World, sheets: @Sheets, entrant: Actor, position: u8) -> bool;
    /// The window's tiles of the living goblins the world does not hold (a bitmap of the window).
    fn frozen(self: @R) -> felt252;
}

/// `AiLibrary`'s rules (`Delegate`): a trap through `TrapLibrary`, called only when the tile holds
/// an unused trap, with every member and the entrant (a placed trap's placer is a member or the
/// entrant's foe, a goblin: only a member's trap triggers on a goblin, §5.11).
pub impl DelegateEnter of Enter<Delegate> {
    fn enter(
        ref self: Delegate, ref world: World, sheets: @Sheets, entrant: Actor, position: u8,
    ) -> bool {
        if AiTrait::armed(@self.ground, @self.board, position).is_none() {
            return false;
        }
        let index = match entrant {
            Actor::Goblin(i) => i,
            Actor::Member(_) => { return false; },
        };
        let mut members = array![];
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            members.append(world.member(m).store());
            m += 1;
        }
        let goblin = world.goblin(index);
        let words = Words {
            clock: world.clock,
            members,
            goblins: array![goblin.store()],
            killed: array![],
            defeated: false,
        };
        let ground = self.ground;
        let (out, ground, triggered) = ITrapLibraryLibraryDispatcher { class_hash: self.trap }
            .trigger(words, self.content, self.board, ground, goblin.entity, position, self.level);
        self.ground = ground;
        let mut m = 0;
        for words in out.members {
            world.set_member(m, MemberTrait::load(words, ref self.index, sheets));
            m += 1;
        }
        for words in out.goblins {
            world.set_goblin(index, GoblinTrait::load(words, ref self.index, sheets));
        }
        for entity in out.killed {
            world.killed.append(entity);
        }
        triggered
    }

    fn frozen(self: @Delegate) -> felt252 {
        *self.frozen
    }
}

#[generate_trait]
pub impl AiImpl of AiTrait {
    /// Step 2 (§5.1): every goblin of the awake set free to act acts, ascending id; `resolved`
    /// holds the set's goblins that resolved in step 1 (bit `2^k` for the `k`-th). Returns
    /// whether the adventurer reached 0 (the step stops there, FX-8).
    fn step<R, +Carry<R>, +Enter<R>, +Destruct<R>>(
        ref world: World, sheets: @Sheets, ref rules: R, resolved: u128,
    ) -> bool {
        let t = world.clock;
        let woken = world.woken();
        let board = rules.board();
        let mut flood: Option<Flood> = None;
        let mut bit: u128 = 1;
        let mut k = 0;
        while k < woken.len() {
            let index = *woken[k];
            let goblin = world.goblin(index);
            if goblin.act_slot == activation::NONE
                && goblin.knocked < t
                && goblin.is_alive()
                && resolved & bit == 0 {
                Self::act(ref world, sheets, ref rules, @board, ref flood, index, goblin, t);
                if world.is_down() {
                    return true;
                }
            }
            bit *= 2;
            k += 1;
        }
        false
    }

    /// Goblin `index`'s act at `t` (design/04's state machine, the module's rules).
    fn act<R, +Carry<R>, +Enter<R>, +Destruct<R>>(
        ref world: World,
        sheets: @Sheets,
        ref rules: R,
        board: @Board,
        ref flood: Option<Flood>,
        index: u32,
        goblin: Goblin,
        t: u32,
    ) {
        let state = goblin.ai;
        if state != ai::ENGAGED && state != ai::ALERTED && state != ai::FLEEING {
            return;
        }
        let (target, target_at) = match Self::target(@world, board) {
            Some(found) => found,
            None => { return; },
        };
        let source = Actor::Goblin(index);
        if state == ai::ENGAGED {
            if Self::skill(ref world, sheets, ref rules, board, source, goblin, target, target_at, t) {
                return;
            }
            let carrier = Carrier::Weapon;
            if ExecutorTrait::legal(@Levered {}, @world, sheets, board, source, carrier, target) {
                let (x, y, facing) = goblin.place();
                let from = board.position(x, y);
                let mut goblin = goblin;
                goblin.set_place(x, y, WindowTrait::facing(from, target_at, facing));
                goblin.recover(*(*sheets.kits)[goblin.caste_at].weapon_ticks, t);
                world.set_goblin(index, goblin);
                let _ = rules.carry(ref world, sheets, source, 0, carrier, target, t);
                return;
            }
        }
        let away = state == ai::FLEEING;
        if !Self::walk(ref world, sheets, ref rules, board, ref flood, index, goblin, away, t)
            && away {
            let mut goblin = goblin;
            goblin.ai = ai::ENGAGED;
            world.set_goblin(index, goblin);
        }
    }

    /// The first usable skill of the goblin's priority list, used on `target` (the module's
    /// *Engaged* row); whether one was.
    fn skill<R, +Carry<R>, +Destruct<R>>(
        ref world: World,
        sheets: @Sheets,
        ref rules: R,
        board: @Board,
        source: Actor,
        goblin: Goblin,
        target: u16,
        target_at: u8,
        t: u32,
    ) -> bool {
        let lever = Levered {};
        let kit = (*sheets.kits)[goblin.caste_at];
        let positions = kit.skills.span();
        let mut slot: u8 = 0;
        while slot < 4 {
            let at = *positions[slot.into()];
            if at != ABSENT && t > goblin.recharge(slot) {
                let sheet = *sheets.skills[at];
                let energy: u16 = sheet.energy.into() * 3;
                let adrenaline: u16 = sheet.adrenaline.into() * 4;
                let first = lever.entry(sheets, at, 0);
                if first.kind != kind::TRAP
                    && goblin.energy.into() >= energy
                    && goblin.adrenaline.into() >= adrenaline {
                    let carrier = Carrier::Skill((at, *(*sheets.castes)[goblin.caste_at].rank));
                    let (address, to) = Self::address(
                        @world, goblin, first.target, sheet.kind, target, target_at,
                    );
                    if ExecutorTrait::legal(@lever, @world, sheets, board, source, carrier, address) {
                        Self::use_skill(
                            ref world,
                            sheets,
                            ref rules,
                            board,
                            source,
                            goblin,
                            slot,
                            carrier,
                            address,
                            to,
                            energy,
                            adrenaline,
                            t,
                        );
                        return true;
                    }
                }
            }
            slot += 1;
        }
        false
    }

    /// What the goblin's skill addresses (§2.3): an attack skill or a `FOE` entry the target, a
    /// `TILE` one the target's tile (`x + 256 y`), `SELF` and `ALLY` itself (a heal of the pack is a
    /// profile's choice, `support`: not encoded, the module's readings).
    /// Returns the address and its position in the window.
    fn address(
        world: @World, goblin: Goblin, addressing: u8, kind: u8, target: u16, target_at: u8,
    ) -> (u16, u8) {
        if kind == skill_kind::ATTACK || addressing == target::FOE {
            return (target, target_at);
        }
        if addressing == target::TILE {
            let (x, y, _) = MemberSnapshotTrait::place(@world.member(target.into()));
            return (x.into() + 256 * y.into(), target_at);
        }
        (goblin.entity, FAR)
    }

    /// The goblin's caste skill `slot` used on `address` at `t`: its costs, its facing, then an
    /// activation (`n ≥ 1`) or the carrier now.
    fn use_skill<R, +Carry<R>, +Destruct<R>>(
        ref world: World,
        sheets: @Sheets,
        ref rules: R,
        board: @Board,
        source: Actor,
        goblin: Goblin,
        slot: u8,
        carrier: Carrier,
        address: u16,
        to: u8,
        energy: u16,
        adrenaline: u16,
        t: u32,
    ) {
        let index = match source {
            Actor::Goblin(i) => i,
            Actor::Member(_) => { return; },
        };
        let Carrier::Skill((at, _)) = carrier else {
            return;
        };
        let sheet = *sheets.skills[at];
        let mut goblin = goblin;
        goblin.energy -= energy.try_into().unwrap();
        goblin.adrenaline -= adrenaline.try_into().unwrap();
        let (x, y, facing) = goblin.place();
        let from = board.position(x, y);
        goblin.set_place(x, y, WindowTrait::facing(from, to, facing));
        if sheet.activation >= 1 {
            goblin.start(slot, address, sheet.activation, t);
            world.set_goblin(index, goblin);
            return;
        }
        goblin.use_instant(slot, t, sheets);
        if sheet.kind == skill_kind::ATTACK {
            goblin.recover(*(*sheets.kits)[goblin.caste_at].weapon_ticks, t);
        }
        world.set_goblin(index, goblin);
        let _ = rules.carry(ref world, sheets, source, slot, carrier, address, t);
    }

    /// One step of the goblin toward the adventurer (away when `away`) on the tick's flood, the
    /// current occupancy blocked; its facing, a crippled step's recovery, then the trap of the tile
    /// entered (§5.11). Whether it stepped.
    fn walk<R, +Carry<R>, +Enter<R>, +Destruct<R>>(
        ref world: World,
        sheets: @Sheets,
        ref rules: R,
        board: @Board,
        ref flood: Option<Flood>,
        index: u32,
        goblin: Goblin,
        away: bool,
        t: u32,
    ) -> bool {
        let (x, y, facing) = goblin.place();
        let from = board.position(x, y);
        if from >= FAR {
            return false;
        }
        let blocked = Self::occupancy(@world, board, None) + rules.frozen();
        if flood.is_none() {
            flood = Self::flood(@world, board, rules.frozen());
        }
        let step = match @flood {
            Some(flood) => if away {
                flood.next_step_away(from, blocked)
            } else {
                flood.next_step(from, blocked)
            },
            None => None,
        };
        let to = match step {
            Some(to) => to,
            None => { return false; },
        };
        let dy = to / WIDTH;
        let dx = to % WIDTH;
        let mut goblin = goblin;
        // A step is a walkable tile, inside the location: its origin less `ORIGIN` is not negative.
        goblin
            .set_place(
                *board.x + dx - ORIGIN, *board.y + dy - ORIGIN, WindowTrait::facing(from, to, facing),
            );
        let cost = goblin.move_ticks(t, Self::movement(@goblin, sheets, t));
        goblin.recover(cost, t);
        world.set_goblin(index, goblin);
        let _ = rules.enter(ref world, sheets, Actor::Goblin(index), to);
        true
    }

    /// The tick's flood from the adventurer (member 0) on the window, every other living actor's
    /// tile an obstacle, stopped at `FLOOD_DEPTH`; `None` when the adventurer is not in the
    /// window or not on a walkable tile.
    fn flood(world: @World, board: @Board, frozen: felt252) -> Option<Flood> {
        let member = world.member(0);
        let (x, y, _) = member.place();
        let from = board.position(x, y);
        let grid = board.window.open();
        if from >= FAR || !Self::walkable(grid, from) {
            return None;
        }
        let obstacles = Self::occupancy(world, board, Some(from)) + frozen;
        Some(Bfs::flood(grid, WIDTH, HEIGHT, from, obstacles, FLOOD_DEPTH))
    }

    /// The window's tiles of every living actor, as a bitmap of the window, but `except`.
    fn occupancy(world: @World, board: @Board, except: Option<u8>) -> felt252 {
        let mut tiles: u256 = 0;
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            let member = world.member(m);
            let (x, y, _) = MemberSnapshotTrait::place(@member);
            Self::mark(ref tiles, board.position(x, y), except);
            m += 1;
        }
        for (_, state) in world.alive() {
            let (x, y, _) = GoblinPlaceTrait::at(state);
            Self::mark(ref tiles, board.position(x, y), except);
        }
        tiles.try_into().unwrap()
    }

    /// Sets bit `position` of `tiles` once, unless it is outside the window or `except`.
    #[inline(always)]
    fn mark(ref tiles: u256, position: u8, except: Option<u8>) {
        if position >= FAR || Some(position) == except {
            return;
        }
        let bit = Self::power(position);
        if tiles & bit == 0 {
            tiles += bit;
        }
    }

    /// `2^position` for a position of the window.
    #[inline(always)]
    fn power(position: u8) -> u256 {
        if position < 128 {
            u256 { low: Self::pow2(position), high: 0 }
        } else {
            u256 { low: 0, high: Self::pow2(position - 128) }
        }
    }

    fn pow2(n: u8) -> u128 {
        let mut value: u128 = 1;
        let mut k = 0;
        while k < n {
            value *= 2;
            k += 1;
        }
        value
    }

    /// Whether the window's tile `position` is walkable in `grid`.
    fn walkable(grid: felt252, position: u8) -> bool {
        let grid: u256 = grid.into();
        grid & Self::power(position) != 0
    }

    /// The goblins' target: the nearest living member inside, ties by the lowest index, and its
    /// position; `None` when none is in the window.
    fn target(world: @World, board: @Board) -> Option<(u16, u8)> {
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            let member = world.member(m);
            let (x, y, _) = MemberSnapshotTrait::place(@member);
            let at = board.position(x, y);
            if member.is_alive() && at < FAR {
                return Some((m.try_into().unwrap(), at));
            }
            m += 1;
        }
        None
    }

    /// The unused trap of the window's `position` in `ground` (§5.11), if any: its placer, `None`
    /// for a terrain trap.
    fn armed(ground: @Ground, board: @Board, position: u8) -> Option<Option<Placer>> {
        let (chunk, tile) = TrapTrait::locate(board, position)?;
        for (c, features) in ground.span() {
            if *c == chunk {
                for object in features.objects.span() {
                    if TrapTrait::is_trap(object) && *object.state == 0 && *object.tile == tile {
                        if *object.kind == object::PLACED_TRAP {
                            return Some(Some(PlacerTrait::from_param(*object.param)));
                        }
                        return Some(None);
                    }
                }
                return None;
            }
        }
        None
    }

    /// Whether the goblin holds a `MOVEMENT` effect at `t` (FX-18).
    fn movement(goblin: @Goblin, sheets: @Sheets, t: u32) -> bool {
        let at = *goblin.effect_at;
        if at == ABSENT || t > *goblin.effect_deadline {
            return false;
        }
        let lever = Levered {};
        let mut k = 0;
        while k < 3 {
            if lever.entry(sheets, at, k).kind == kind::MOVEMENT {
                return true;
            }
            k += 1;
        }
        false
    }
}
