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
use crate::types::executor::{Board, BoardTrait, Body, Cache, ExecutorTrait, Levers};
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
        let x: u16 = (*board.x).into() + dx.into();
        let y: u16 = (*board.y).into() + dy.into();
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
