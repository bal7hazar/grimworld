//! Traps (CBT-05b; design/19 §5.11, §5.14): the two object kinds of a chunk (ENG-01 §3.2
//! `Features`, objects at 128, 160, 192), placing one through the executor's step 2 and triggering
//! one when an actor enters its tile. A value type's behaviour over the chunk objects a call
//! carries (`Ground`), as `World`'s: it sits in `types/` (docs/CAIRO.md §7, D-147).
//!
//! **Placing** (a `TRAP` carrier whose guard held, §5.14 step 2): the tile is in the window and
//! walkable, holds no living actor (remains do not block, §5.13) and no object but a used trap;
//! the trap takes the chunk's lowest object index that is empty or a used trap; otherwise the tile
//! cannot take one (FX-14): the member's action is illegal (§5.3 step 1), and at a resolution
//! nothing is placed and the costs stay paid (§5.9). The object is kind 9, state 0, its `param`
//! the `Placer`.
//!
//! **Triggering** (`TrapTrait::trigger`), called by the move's owner (ENG-07) right after an actor
//! enters a tile: the tile's unused trap, if any, triggers once on a foe of its side (a placed
//! trap: its placer's foes; a terrain trap: members only, FX-34). Its source (§5.11 step 1): a
//! member placer's snapshot level and its bar slot's rank; a goblin placer's record level and its
//! caste's rank; a terrain trap's location band's lower level and rank 0 (the project manager,
//! 2026-10-02, CBT-05b's open question 6). Its payload, the skill's entries without the `TRAP`
//! one, runs through CBT-05a's executor with the entrant as its only actor, class `TRAP`
//! (`ExecutorTrait::trigger`); the object is marked used.
//!
//! **Where the trigger runs** (CBT-05b's escalation 1): the in-class payload (`ExecutorTrait::
//! trigger`, the hit and the entries) measured 37,462 CASM felts in `TickLibrary` (87,409, 106.70 %
//! of the limit, over D-200's 75 %), so no class calls it yet; the project manager decides its
//! class. The tests run it in process.

use crate::models::chunk::{Features, Object, object};
use crate::models::goblin::GoblinPlaceTrait;
use crate::models::member::{MemberSnapshotTrait, MemberTrait, MemberWordsTrait};
use crate::types::combat::{Placer, PlacerTrait};
use crate::types::effect::{Entry, kind, shape};
use crate::types::executor::{Board, BoardTrait, Body, Cache, ExecutorTrait, Levers, ORIGIN};
use crate::types::infliction::Infliction;
use crate::types::tick::{ABSENT_LANE, Sheets};
use crate::types::window::{FAR, WindowTrait};
use crate::types::world::{Actor, World, WorldTrait};
use crate::types::{CHUNK_SIDE, MAX_CHUNKS};

/// The chunk objects a call reads and writes: each chunk's `Features` by its index `15 cy + cx`,
/// as `Instances` stores them (ENG-01 §3.2). The caller passes the chunks the action or the move
/// can touch (ENG-07 assembles them with the window).
pub type Ground = Array<(u8, Features)>;

/// The used state of an object (ENG-01 §3.2: 0 untouched, 1 used).
const USED: u8 = 1;
/// Every guard of a terrain trap's payload holds: its entries carry none (FX-14).
const ALL_HELD: u8 = 7;

/// Where a placement goes: the chunk's entry in the ground, the object index, the chunk's tile.
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct Spot {
    pub entry: u32,
    pub index: u32,
    pub tile: u8,
}

#[generate_trait]
pub impl TrapImpl of TrapTrait {
    /// The chunk `15 cy + cx` and its tile `15 ly + lx` of the window's `position`; `None` outside
    /// the window or the location.
    fn locate(board: @Board, position: u8) -> Option<(u8, u8)> {
        if position >= FAR || position >= 240 {
            return None;
        }
        // The window's 15 columns, the chunk's 15 tiles a side (`WIDTH`, `CHUNK_SIDE`).
        let (dy, dx) = DivRem::div_rem(position, 15);
        // The location's tile: the board's origin is held plus `ORIGIN` (a negative origin near
        // the West or South edge, D-134): a tile before the location's first is in none.
        let x: u16 = (*board.x).into() + dx.into();
        let y: u16 = (*board.y).into() + dy.into();
        let origin: u16 = ORIGIN.into();
        if x < origin || y < origin {
            return None;
        }
        let x = x - origin;
        let y = y - origin;
        let side: u16 = CHUNK_SIDE.into();
        let (cy, ly) = DivRem::div_rem(y, 15);
        let (cx, lx) = DivRem::div_rem(x, 15);
        let chunk = cy * side + cx;
        if chunk >= MAX_CHUNKS.into() || cx >= side {
            return None;
        }
        Some((chunk.try_into().unwrap(), (ly * side + lx).try_into().unwrap()))
    }

    /// The object index a trap placed on `tile` takes: the lowest that is empty or a used trap;
    /// `None` when the tile holds another object, or no index is free (a full chunk, FX-14).
    fn free(features: @Features, tile: u8) -> Option<u32> {
        let mut found: Option<u32> = None;
        let mut k: u32 = 0;
        for object in features.objects.span() {
            let spent = Self::is_trap(object) && *object.state == USED;
            if *object.kind != object::NONE && !spent && *object.tile == tile {
                return None;
            }
            if found.is_none() && (*object.kind == object::NONE || spent) {
                found = Some(k);
            }
            k += 1;
        }
        found
    }

    /// Where a trap placed on the window's `position` goes (§5.11 placing): in the window and
    /// walkable, no living actor on it, its chunk in `ground` with an object index free; `None` if
    /// the tile cannot take one.
    fn spot(world: @World, board: @Board, ground: @Ground, position: u8) -> Option<Spot> {
        let (chunk, tile) = Self::locate(board, position)?;
        if !Self::open(board, position) || Self::occupied(world, board, position) {
            return None;
        }
        let mut entry: u32 = 0;
        for (c, features) in ground.span() {
            if *c == chunk {
                let index = Self::free(features, tile)?;
                return Some(Spot { entry, index, tile });
            }
            entry += 1;
        }
        None
    }

    /// Places `placer`'s trap on the window's `position` if the tile can take one (§5.11); returns
    /// whether it did.
    fn place(
        ref ground: Ground, world: @World, board: @Board, position: u8, placer: Placer,
    ) -> bool {
        match Self::spot(world, board, @ground, position) {
            Some(spot) => {
                let trap = Object {
                    tile: spot.tile, kind: object::PLACED_TRAP, state: 0, param: placer.param(),
                };
                Self::write(ref ground, spot.entry, spot.index, trap);
                true
            },
            None => false,
        }
    }

    /// The placer of `actor`'s carrier from bar or caste slot `slot` (design/19 §7.2).
    fn placer(world: @World, actor: Actor, slot: u8) -> Placer {
        match actor {
            Actor::Member(i) => Placer::Member((i.try_into().unwrap(), slot)),
            Actor::Goblin(i) => Placer::Goblin((world.goblin(i).entity, slot)),
        }
    }

    /// The tile's unused trap after `entrant` entered the window's `position`, triggered once if
    /// the entrant is a foe of its side (§5.11): its payload through the executor
    /// (`ExecutorTrait::trigger`), then the object marked used. `level` is the location band's
    /// lower level, a terrain trap's source. Returns whether a trap triggered; a death follows
    /// §5.13 (the executor records a goblin's, the pipeline stops on the adventurer's).
    fn trigger<L, +Levers<L>, +Drop<L>>(
        lever: @L,
        ref cache: Cache,
        ref world: World,
        sheets: @Sheets,
        ref ground: Ground,
        board: @Board,
        entrant: Actor,
        position: u8,
        level: u8,
    ) -> bool {
        let (chunk, tile) = match Self::locate(board, position) {
            Some(found) => found,
            None => { return false; },
        };
        let mut found: Option<(u32, u32, Object)> = None;
        let mut entry: u32 = 0;
        for (c, features) in ground.span() {
            if *c == chunk {
                let mut k: u32 = 0;
                for object in features.objects.span() {
                    if Self::is_trap(object) && *object.state != USED && *object.tile == tile {
                        found = Some((entry, k, *object));
                        break;
                    }
                    k += 1;
                }
                break;
            }
            entry += 1;
        }
        let (entry, index, trap) = match found {
            Some(found) => found,
            None => { return false; },
        };
        let on_member = match entrant {
            Actor::Member(_) => true,
            Actor::Goblin(_) => false,
        };
        // The source and the payload (§5.11 step 1): `(payload, rank, level, held, infliction)`.
        let source = if trap.kind == object::TRAP {
            if !on_member {
                return false;
            }
            Self::terrain(sheets, trap.param, level)
        } else {
            match PlacerTrait::from_param(trap.param) {
                Placer::Member((
                    m, slot,
                )) => {
                    if on_member {
                        return false;
                    }
                    Self::by_member(lever, @world, sheets, m.into(), slot)
                },
                Placer::Goblin((
                    entity, slot,
                )) => {
                    if !on_member {
                        return false;
                    }
                    Self::by_goblin(lever, @world, sheets, entity, slot)
                },
            }
        };
        let (payload, rank, level, held, infliction) = match source {
            Some(source) => source,
            None => { return false; },
        };
        let t = world.clock;
        ExecutorTrait::trigger(
            lever, ref cache, ref world, sheets, payload, rank, level, held, infliction, entrant, t,
        );
        Self::write(ref ground, entry, index, Object { state: USED, ..trap });
        true
    }

    /// A terrain trap's source: its `SKILL` (`param`) found in the sheets, the band's lower level,
    /// rank 0, every guard held; `None` if the content lacks the skill.
    fn terrain(sheets: @Sheets, skill: u16, level: u8) -> Option<(u32, u8, u8, u8, Infliction)> {
        let mut at: u32 = 0;
        for sheet in *sheets.skills {
            if *sheet.id == skill {
                return Some((at, 0, level, ALL_HELD, Default::default()));
            }
            at += 1;
        }
        None
    }

    /// A member placer's source: its bar slot's skill at the slot's rank, its snapshot's level, the
    /// guards evaluated on it now (§5.14: steps 1, 3, 5), what it adds to conditions.
    fn by_member<L, +Levers<L>>(
        lever: @L, world: @World, sheets: @Sheets, m: u32, slot: u8,
    ) -> Option<(u32, u8, u8, u8, Infliction)> {
        if m >= world.member_count() {
            return None;
        }
        let member = world.member(m);
        let at = member.position(slot);
        if at == ABSENT_LANE {
            return None;
        }
        let at: u32 = at.try_into().unwrap();
        let held = ExecutorTrait::guards(@member, Self::entries(lever, sheets, at));
        Some((at, member.rank(slot), member.level(), held, MemberWordsTrait::infliction(@member)))
    }

    /// A goblin placer's source: its caste skill `slot`, its record's level, its caste's rank (a
    /// dead placer's record still holds them, §5.11); `None` if the call does not carry it.
    fn by_goblin<L, +Levers<L>>(
        lever: @L, world: @World, sheets: @Sheets, entity: u16, slot: u8,
    ) -> Option<(u32, u8, u8, u8, Infliction)> {
        let i = world.find(entity)?;
        let goblin = world.goblin(i);
        let kit = (*sheets.kits)[goblin.caste_at];
        let at = *kit.skills.span()[slot.into()];
        let held = ExecutorTrait::guards(@goblin, Self::entries(lever, sheets, at));
        let rank = *(*sheets.castes)[goblin.caste_at].rank;
        Some((at, rank, GoblinPlaceTrait::level(@goblin), held, Body::infliction(@goblin)))
    }

    /// The skill at `at`'s entries, up to the first empty one.
    fn entries<L, +Levers<L>>(lever: @L, sheets: @Sheets, at: u32) -> Span<Entry> {
        let mut entries = array![];
        for k in 0..3_u32 {
            let entry = lever.entry(sheets, at, k);
            if entry.kind == kind::EMPTY {
                break;
            }
            entries.append(entry);
        }
        entries.span()
    }

    /// A terrain trap (kind 4) or a placed one (kind 9).
    #[inline(always)]
    fn is_trap(object: @Object) -> bool {
        *object.kind == object::TRAP || *object.kind == object::PLACED_TRAP
    }

    /// The window's `position` is walkable: its `SINGLE` shape holds it (the window's open bit).
    #[inline(always)]
    fn open(board: @Board, position: u8) -> bool {
        board.window.near(shape::SINGLE, position) != 0
    }

    /// A living actor stands on the window's `position` (remains do not block, §5.13).
    fn occupied(world: @World, board: @Board, position: u8) -> bool {
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            let member = world.member(m);
            let (x, y, _) = MemberSnapshotTrait::place(@member);
            if member.is_alive() && board.position(x, y) == position {
                return true;
            }
            m += 1;
        }
        for (_, state) in world.alive() {
            let (x, y, _) = GoblinPlaceTrait::at(state);
            if board.position(x, y) == position {
                return true;
            }
        }
        false
    }

    /// `ground`'s chunk at `entry` with object `index` replaced by `object`.
    fn write(ref ground: Ground, entry: u32, index: u32, object: Object) {
        let mut next: Ground = array![];
        let mut k: u32 = 0;
        for (chunk, features) in ground.span() {
            if k == entry {
                let [o0, o1, o2] = *features.objects;
                let objects = if index == 0 {
                    [object, o1, o2]
                } else if index == 1 {
                    [o0, object, o2]
                } else {
                    [o0, o1, object]
                };
                next.append((*chunk, Features { objects, ..*features }));
            } else {
                next.append((*chunk, *features));
            }
            k += 1;
        }
        ground = next;
    }
}

/// The traps' unit tests (CBT-05b; D-167): §10.10 to the unit, through the action phase, step 1's
/// placement and the trigger; a trap's side, its single trigger, the lowest index, a full chunk,
/// a terrain trap.
#[cfg(test)]
mod tests {
    use crate::actions::Action;
    use crate::models::chunk::{Features, FeaturesTrait, Object, object};
    use crate::models::goblin::GoblinWordsTrait;
    use crate::models::member::{Member, MemberTrait};
    use crate::types::Target;
    use crate::types::action::ActionTrait;
    use crate::types::combat::{Placer, PlacerTrait, skill_kind, weapon};
    use crate::types::executor::tests::{AT, SNARE, at, board, content, goblin, member};
    use crate::types::executor::{Cache, ExecutorTrait, Levered};
    use crate::types::tick::{ContentTrait, Sheets};
    use crate::types::world::fixtures::{Fixture, two};
    use crate::types::world::{Actor, TickTrait, World, WorldTrait};
    use super::{Ground, TrapTrait};

    /// The trap's tile, `(7, 9)`: window position 142, chunk 0's tile 142.
    const TILE: u16 = 7 + 256 * 9;
    const SPOT: u8 = 142;

    /// The executor's content with Snare as §10.10's (10 / 2 / 20), and a terrain trap's skill (id
    /// 70: its `TRAP` entry, then Snare's payload).
    fn sheets() -> Sheets {
        let base = content(40, array![].span());
        let mut skills = array![];
        for sheet in base.skills {
            let mut sheet = *sheet;
            if sheet.id == SNARE {
                sheet.energy = 10;
                sheet.activation = 2;
                sheet.recharge = 20;
                skills.append(sheet);
                skills
                    .append(
                        crate::types::tick::SkillSheet { id: 70, kind: skill_kind::TRAP, ..sheet },
                    );
            } else {
                skills.append(sheet);
            }
        }
        crate::types::tick::Content { skills: skills.span(), ..base }.sheets()
    }

    /// The Warden at `AT`, level 20, Snare on bar slot 0 at rank 12.
    fn warden(sheets: @Sheets) -> Member {
        let mut member = member(AT, 0, weapon::BOW);
        let position: u128 = at(sheets, SNARE).into();
        member.words.bar += (SNARE.into() - member.skill(0).into());
        member.bar_at = member.bar_at - member.position(0) + position;
        member.words.stats += 12 * two(128);
        member
    }

    fn trap(tile: u8, kind: u8, state: u8, param: u16) -> Object {
        Object { tile, kind, state, param }
    }

    fn chunk(objects: [Object; 3]) -> Ground {
        array![(0, Features { objects, ..FeaturesTrait::empty() })]
    }

    fn nth(ground: @Ground, k: u32) -> Object {
        let (_, features) = ground[0];
        *features.objects.span()[k]
    }

    fn enter(
        ref world: World, sheets: @Sheets, ref ground: Ground, entrant: Actor, level: u8,
    ) -> bool {
        let mut cache: Cache = Default::default();
        TrapTrait::trigger(
            @Levered {}, ref cache, ref world, sheets, ref ground, @board(), entrant, SPOT, level,
        )
    }

    // §10.10: the Warden casts Snare at clock 300 on the empty walkable tile `(7, 9)` in range
    // (`A = 302`); step 1 of tick 302 places it: chunk 0's object index 0, kind 9, `param` member
    // 0 and bar slot 0; no actor at placement. Step 2 of 305: goblin 44 (armor 40, 100 health)
    // moves onto it: strength 3 × 20 = 60, rank 12; the hit 100 → 44, Crippled `D = 307`; the
    // object used.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 13019107)] // ceil(1.05 × 12399149 measured)
    fn test_example_trap() {
        let sheets = sheets();
        let mut world = Fixture::world(
            300, array![warden(@sheets)], array![goblin(44, AT + 1, 0, 100)],
        );
        let mut rules = ExecutorTrait::new(board());
        rules.ground = chunk([Default::default(); 3]);
        let ticks = ActionTrait::act(
            ref world, @sheets, ref rules, 0, Action::Skill((0, Target::Tile(TILE))),
        );
        assert(ticks == Ok(2), 'two ticks');
        TickTrait::run(ref world, @sheets, 2, ref rules);
        assert(world.clock == 302 && world.goblin(0).health == 100, 'placed, no actor');
        let placed = nth(@rules.ground, 0);
        assert(
            placed == trap(SPOT, object::PLACED_TRAP, 0, Placer::Member((0, 0)).param()), 'kind 9',
        );
        // Step 2 of 305: goblin 44 enters.
        world.clock = 305;
        let mut goblin = world.goblin(0);
        // From (8, 7) to (7, 9).
        goblin.state = goblin.state - 1 + 2 * 256;
        world.set_goblin(0, goblin);
        let mut ground = rules.ground;
        assert(enter(ref world, @sheets, ref ground, Actor::Goblin(0), 0), 'triggered');
        let foe = world.goblin(0);
        assert(foe.health == 44 && foe.crippled() == 307, '100 -> 44, D = 307');
        assert(nth(@ground, 0).state == 1, 'used');
        // Once: a second entrant finds it used.
        assert(!enter(ref world, @sheets, ref ground, Actor::Goblin(0), 0), 'once');
    }

    // A placed trap never triggers on its own side: the member on its own trap.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 9315201)] // ceil(1.05 × 8871620 measured)
    fn test_own_side() {
        let sheets = sheets();
        let mut world = Fixture::world(305, array![warden(@sheets)], array![]);
        let param = Placer::Member((0, 0)).param();
        let mut ground = chunk(
            [trap(SPOT, object::PLACED_TRAP, 0, param), Default::default(), Default::default()],
        );
        let before = world.member(0);
        assert(!enter(ref world, @sheets, ref ground, Actor::Member(0), 0), 'own side');
        assert(world.member(0) == before && nth(@ground, 0).state == 0, 'nothing');
    }

    // A terrain trap (kind 4, its `param` a `SKILL`) hits members only (FX-34), at its band's
    // lower level and rank 0 (the project manager, 2026-10-02): a goblin entering is not hit.
    #[test]
    #[available_gas(l2_gas: 10625157)] // ceil(1.05 × 10119197 measured)
    fn test_terrain_trap() {
        let sheets = sheets();
        let mut world = Fixture::world(
            305, array![warden(@sheets)], array![goblin(44, SPOT, 0, 100)],
        );
        let mut ground = chunk(
            [trap(SPOT, object::TRAP, 0, 70), Default::default(), Default::default()],
        );
        assert(!enter(ref world, @sheets, ref ground, Actor::Goblin(0), 20), 'not on goblins');
        let health = world.member(0).health;
        assert(enter(ref world, @sheets, ref ground, Actor::Member(0), 20), 'on members');
        assert(world.member(0).health < health && nth(@ground, 0).state == 1, 'hit, used');
    }

    // Placing (§5.11): the lowest index that is empty or a used trap; a tile holding another
    // object, or a full chunk, takes none (FX-14); a used trap on the tile itself is replaced.
    #[test]
    #[available_gas(l2_gas: 64953)] // ceil(1.05 × 61860 measured)
    fn test_free_index() {
        let used = trap(5, object::PLACED_TRAP, 1, 0);
        let chest = trap(7, object::CHEST, 0, 0);
        let empty: Object = Default::default();
        let features = Features { objects: [chest, used, empty], ..FeaturesTrait::empty() };
        assert(TrapTrait::free(@features, 9) == Some(1), 'the used trap first');
        assert(TrapTrait::free(@features, 7) == None, 'a chest on it');
        assert(TrapTrait::free(@features, 5) == Some(1), 'a used trap on it');
        let full = Features {
            objects: [chest, trap(8, object::VEIN, 1, 0), trap(6, object::TRAP, 0, 3)],
            ..FeaturesTrait::empty(),
        };
        assert(TrapTrait::free(@full, 9) == None, 'full');
    }

    // `place` writes the object at the free index and leaves the others; an actor on the tile
    // refuses it (a dead goblin's remains do not).
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 16209541)] // ceil(1.05 × 15437658 measured)
    fn test_place() {
        let sheets = sheets();
        let _ = sheets;
        let mut world = Fixture::world(
            300, array![member(AT, 0, weapon::BOW)], array![goblin(8, SPOT, 0, 0)],
        );
        world.kill(0);
        let chest = trap(1, object::CHEST, 0, 0);
        let mut ground = chunk([chest, Default::default(), Default::default()]);
        let placer = Placer::Goblin((8, 2));
        assert(TrapTrait::place(ref ground, @world, @board(), SPOT, placer), 'over remains');
        assert(nth(@ground, 0) == chest, 'kept');
        assert(nth(@ground, 1) == trap(SPOT, object::PLACED_TRAP, 0, placer.param()), 'index 1');
        let world = Fixture::world(
            300, array![member(AT, 0, weapon::BOW)], array![goblin(8, SPOT, 0, 50)],
        );
        let mut ground = chunk([Default::default(); 3]);
        assert(!TrapTrait::place(ref ground, @world, @board(), SPOT, placer), 'occupied');
        assert(!TrapTrait::place(ref ground, @world, @board(), AT, placer), 'the member');
    }

    // ---- The trigger's cost (ENG-01 §9.2: "a trap's trigger replaces an application already
    // counted, never adds one"): Snare's payload on goblin 44 in process (the hit, Crippled, the
    // lookup, the used mark), less its fixture.

    fn trigger_state() -> (World, Sheets, Ground) {
        let sheets = sheets();
        let world = Fixture::world(305, array![warden(@sheets)], array![goblin(44, SPOT, 0, 100)]);
        let param = Placer::Member((0, 0)).param();
        let ground = chunk(
            [trap(SPOT, object::PLACED_TRAP, 0, param), Default::default(), Default::default()],
        );
        (world, sheets, ground)
    }

    #[test]
    #[available_gas(l2_gas: 9576525)] // ceil(1.05 × 9120500 measured)
    fn test_cost_trigger_fixture() {
        let (world, sheets, ground) = trigger_state();
        assert(
            world.goblin_count() == 1 && sheets.skills.len() > 0 && ground.len() == 1, 'fixture',
        );
    }

    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 10404668)] // ceil(1.05 × 9909207 measured)
    fn test_cost_trigger() {
        let (mut world, sheets, mut ground) = trigger_state();
        assert(enter(ref world, @sheets, ref ground, Actor::Goblin(0), 0), 'triggered');
        assert(world.goblin(0).health == 44, 'hit');
    }

    // A window position's chunk and tile, the board's origin added; outside the window, none.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 12380)] // ceil(1.05 × 11790 measured)
    fn test_locate() {
        let board = board();
        assert(TrapTrait::locate(@board, SPOT) == Some((0, 142)), 'chunk 0');
        let moved = crate::types::executor::BoardTrait::new(board.window, 10, 14);
        // (7, 9) + (10, 14) = (17, 23): chunk 15 + 1 = 16, tile 15 × 8 + 2 = 122.
        assert(TrapTrait::locate(@moved, SPOT) == Some((16, 122)), 'chunk 16');
        assert(TrapTrait::locate(@board, 240) == None, 'outside');
    }
}
