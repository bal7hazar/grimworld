//! A segment of a played batch (ENG-07; design/02 *Executing a batch*, ADR-0006 §4; D-233, D-234):
//! `TickLibrary::segment` runs the batch's actions in order, each against the state it meets, and
//! each action's ticks, until the actions end, one is illegal (`Done.illegal`: nothing of it is
//! written, the batch stops), the weight left would pass, the adventurer is defeated, or a Move
//! brings sight onto a chunk not yet revealed (`Done.reveal`: the caller reveals it, then calls the
//! next segment with the Move's ticks owed). A value type's behaviour over the `World`, as the
//! pipeline's: it sits in `types/` (docs/CAIRO.md §7, D-147).
//!
//! **In process** (D-233): Move (one tile, the six directions, walkable on the one walkable plane
//! (Open question 7) and free of a living actor; its facing the direction; 1 tick, 2 Crippled
//! unless a `MOVEMENT` effect is held, FX-18), then the trap of the tile entered through
//! `TrapLibrary` (§5.11), right after the move and before its ticks; Turn (once between two ticks,
//! 0 ticks) and Wait (1 tick); Interact refused (Open question 6). **Through `ActionLibrary`**: an
//! Attack, a Skill, an Item (CBT-05b's action phase), with the whole words.
//!
//! **The window** (ADR-0006 §4, `Board`): assembled from the area's chunks around the adventurer
//! after each of its moves, never stored, never clamped: hexx's assembly of the 2 to 4 chunks it
//! overlaps, the origin on an even global row, a chunk not revealed wall (D-136), a void one (out
//! of the location, a zone's set or a dungeon floor's outline) a constant, never read (D-134), the
//! outer ring wall. The origin, down to −8, is held plus `ORIGIN`: `15 (cx + 1) + ox`.

use hexx::board::assembly::AssemblyTrait;
use hexx::board::layout::LayoutTrait;
use starknet::ClassHash;
use crate::actions::Action;
use crate::interface::{
    IActionLibraryDispatcherTrait, IActionLibraryLibraryDispatcher, ITrapLibraryDispatcherTrait,
    ITrapLibraryLibraryDispatcher,
};
use crate::models::goblin::GoblinTrait;
use crate::models::member::{
    Member, MemberConditionTrait, MemberSnapshotTrait, MemberTrait, MemberWordsTrait,
};
use crate::types::LAST_TICK;
use crate::types::action::Illegal;
use crate::types::ai::AiTrait;
use crate::types::combat::{Placer, PlacerTrait};
use crate::types::effect::kind;
use crate::types::executor::{Board, BoardTrait, Delegate, Levered, Levers, ORIGIN};
use crate::types::reveal::SightTrait;
use crate::types::reveal::board::BoardTrait as Bitmap;
use crate::types::tick::{ABSENT_LANE, Sheets, flag};
use crate::types::trap::TrapTrait;
use crate::types::window::{HEIGHT, WIDTH, WindowAssert, WindowTrait};
use crate::types::world::{TickTrait, Words, World, WorldStoreTrait, WorldTrait};

/// The window's interior, its ring cleared (hexx's `LayoutTrait::interior(15, 16)`), as limbs.
const INTERIOR: u256 = u256 {
    low: 0xfe7ffcfff9fff3ffe7ffcfff9fff0000, high: 0xfff9fff3ffe7ffcfff9fff3f,
};

/// The chunks a segment's windows may overlap.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Area {
    /// The location's size in chunks.
    pub width: u8,
    pub height: u8,
    /// Bit `15 cy + cx` for each chunk of the location that is not void (inside its rectangle and a
    /// zone's chunk set or a dungeon floor's outline).
    pub known: felt252,
    /// Bit `15 cy + cx` for each chunk revealed.
    pub revealed: felt252,
    /// The walkable tiles of the revealed chunks the windows may overlap, `(chunk, bits)`: bit
    /// `15 ly + lx` is 1 for a walkable tile (the complement of `Terrain.walls`).
    pub chunks: Span<(u8, felt252)>,
}

/// The library classes a segment calls.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Classes {
    pub executor: ClassHash,
    pub ai: ClassHash,
    pub trap: ClassHash,
    pub action: ClassHash,
}

/// How a segment ended.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct Done {
    /// The actions that ran (an illegal one is not counted).
    pub played: u8,
    /// The weight left after them.
    pub weight: u8,
    /// The last Move's ticks, not run: it brought sight onto a chunk to reveal (`reveal`).
    pub owed: u8,
    pub reveal: bool,
    /// Why the batch stopped on an action, if it did.
    pub illegal: Option<Illegal>,
    /// The next action would pass the weight left.
    pub heavy: bool,
}

/// Why an action did not run.
#[derive(Copy, Drop, Debug, PartialEq)]
enum Halt {
    Illegal: Illegal,
    Heavy,
}

#[generate_trait]
pub impl SegmentImpl of SegmentTrait {
    /// The segment (module documentation): `owed` ticks first, then `actions` within `weight`
    /// (`max(1, ticks)` an action, design/02).
    fn run(
        ref world: World,
        sheets: @Sheets,
        ref rules: Delegate,
        area: @Area,
        action: ClassHash,
        actions: Span<Action>,
        owed: u8,
        weight: u8,
    ) -> Done {
        rules.board = Self::board(area, @world);
        TickTrait::run(ref world, sheets, owed, ref rules);
        let mut done = Done {
            played: 0, weight, owed: 0, reveal: false, illegal: None, heavy: false,
        };
        for next in actions {
            if world.defeated {
                break;
            }
            let ran = match *next {
                Action::Move(direction) => Self::step(ref world, sheets, ref rules, direction, weight),
                Action::Turn(direction) => Self::turn(ref world, direction),
                Action::Wait => Self::wait(@world),
                Action::Interact(_) => Err(Halt::Illegal(Illegal::Kind)),
                _ => Self::combat(ref world, sheets, ref rules, action, *next, done.weight),
            };
            let ticks = match ran {
                Ok(ticks) => ticks,
                Err(Halt::Illegal(illegal)) => {
                    done.illegal = Some(illegal);
                    break;
                },
                Err(Halt::Heavy) => {
                    done.heavy = true;
                    break;
                },
            };
            let cost = if ticks == 0 {
                1
            } else {
                ticks
            };
            if cost > done.weight {
                // Only an in-process action reaches here: nothing of it was kept but a Turn's facing,
                // which costs 0 ticks and so 1 of weight; a Move's ticks are checked before it moves.
                done.heavy = true;
                break;
            }
            done.weight -= cost;
            done.played += 1;
            if let Action::Move(_) = *next {
                if Self::to_reveal(area, @world) {
                    done.owed = ticks;
                    done.reveal = true;
                    break;
                }
                rules.board = Self::board(area, @world);
            }
            TickTrait::run(ref world, sheets, ticks, ref rules);
        }
        done
    }

    /// A Move of the adventurer (member 0) toward `direction`: legal against the state it meets,
    /// then its place and facing, then the trap of the tile entered. Its ticks.
    fn step(
        ref world: World, sheets: @Sheets, ref rules: Delegate, direction: u8, weight: u8,
    ) -> Result<u8, Halt> {
        let c = world.clock;
        if c > LAST_TICK {
            return Err(Halt::Illegal(Illegal::Clock));
        }
        let mut member = world.member(0);
        if !member.is_alive() {
            return Err(Halt::Illegal(Illegal::Absent));
        }
        let t0 = c + 1;
        if !member.can_act(t0) {
            return Err(Halt::Illegal(Illegal::Knocked));
        }
        let board = rules.board;
        let (x, y, _) = member.place();
        let from = board.position(x, y);
        let to = match LayoutTrait::neighbor(
            WIDTH, HEIGHT, from, WindowAssert::direction(direction),
        ) {
            Some(to) => to,
            None => { return Err(Halt::Illegal(Illegal::Blocked)); },
        };
        if !TrapTrait::open(@board, to) || TrapTrait::occupied(@world, @board, to) {
            return Err(Halt::Illegal(Illegal::Blocked));
        }
        let ticks = member.move_ticks(t0, Self::movement(@member, sheets, c));
        if ticks > weight {
            return Err(Halt::Heavy);
        }
        member
            .set_place(
                board.x + to % WIDTH - ORIGIN, board.y + to / WIDTH - ORIGIN, direction,
            );
        world.set_member(0, member);
        Self::trap(ref world, sheets, ref rules, to);
        Ok(ticks)
    }

    /// A Turn: once between two ticks, its facing set, 0 ticks.
    fn turn(ref world: World, direction: u8) -> Result<u8, Halt> {
        if world.clock > LAST_TICK {
            return Err(Halt::Illegal(Illegal::Clock));
        }
        let mut member = world.member(0);
        if !member.is_alive() {
            return Err(Halt::Illegal(Illegal::Absent));
        }
        if !member.can_act(world.clock + 1) {
            return Err(Halt::Illegal(Illegal::Knocked));
        }
        if member.flags & flag::TURNED != 0 {
            return Err(Halt::Illegal(Illegal::Turned));
        }
        member.flags = member.flags | flag::TURNED;
        member.set_facing(direction);
        world.set_member(0, member);
        Ok(0)
    }

    /// A Wait: 1 tick, legal while the adventurer stands and the clock allows.
    fn wait(world: @World) -> Result<u8, Halt> {
        if *world.clock > LAST_TICK {
            return Err(Halt::Illegal(Illegal::Clock));
        }
        if !world.member(0).is_alive() {
            return Err(Halt::Illegal(Illegal::Absent));
        }
        Ok(1)
    }

    /// An Attack, a Skill or an Item through `ActionLibrary` with the whole words (D-233): kept
    /// only if legal and within `weight`, else the words as they were.
    fn combat(
        ref world: World,
        sheets: @Sheets,
        ref rules: Delegate,
        class: ClassHash,
        action: Action,
        weight: u8,
    ) -> Result<u8, Halt> {
        let current = world;
        let words = current.store();
        let ground = rules.ground;
        let (out, ground, result) = IActionLibraryLibraryDispatcher { class_hash: class }
            .act(words.clone(), rules.content, rules.board, rules.executor, ground, action);
        rules.ground = ground;
        let (kept, ran) = match result {
            Ok(ticks) => if ticks > weight || (ticks == 0 && weight == 0) {
                (words, Err(Halt::Heavy))
            } else {
                (out, Ok(ticks))
            },
            Err(illegal) => (words, Err(Halt::Illegal(illegal))),
        };
        world = Self::reload(kept, sheets, ref rules);
        ran
    }

    /// The world of `words` loaded through the call's index.
    fn reload(words: Words, sheets: @Sheets, ref rules: Delegate) -> World {
        let mut members = array![];
        for member in words.members {
            members.append(MemberTrait::load(member, ref rules.index, sheets));
        }
        let mut goblins = array![];
        for goblin in words.goblins {
            goblins.append(GoblinTrait::load(goblin, ref rules.index, sheets));
        }
        WorldTrait::new(words.clock, members, goblins, words.killed, words.defeated)
    }

    /// The trap of the window's `position` the adventurer entered (§5.11): through `TrapLibrary`
    /// with the members and, for a goblin's placed trap, its placer; nothing without an unused
    /// trap there.
    fn trap(ref world: World, sheets: @Sheets, ref rules: Delegate, position: u8) {
        let placer = match AiTrait::armed(@rules.ground, @rules.board, position) {
            Some(param) => param,
            None => { return; },
        };
        let mut members = array![];
        let count = world.member_count();
        let mut m = 0;
        while m < count {
            members.append(world.member(m).store());
            m += 1;
        }
        let mut goblins = array![];
        let mut index: Option<u32> = None;
        if let Some(Placer::Goblin((entity, _))) = placer {
            index = world.find(entity);
            if let Some(i) = index {
                goblins.append(world.goblin(i).store());
            }
        }
        let words = Words {
            clock: world.clock, members, goblins, killed: array![], defeated: false,
        };
        let ground = rules.ground;
        let (out, ground, _) = ITrapLibraryLibraryDispatcher { class_hash: rules.trap }
            .trigger(words, rules.content, rules.board, ground, 0, position, rules.level);
        rules.ground = ground;
        let mut m = 0;
        for member in out.members {
            world.set_member(m, MemberTrait::load(member, ref rules.index, sheets));
            m += 1;
        }
        if let Some(i) = index {
            for goblin in out.goblins {
                world.set_goblin(i, GoblinTrait::load(goblin, ref rules.index, sheets));
            }
        }
    }

    /// The board of the adventurer's window (module documentation).
    fn board(area: @Area, world: @World) -> Board {
        let (x, y, _) = world.member(0).place();
        let origin = AssemblyTrait::origin(x, y);
        let (cx, cy) = (origin.cx, origin.cy);
        let chunks = [
            Self::piece(area, cx, cy), Self::piece(area, cx + 1, cy), Self::piece(area, cx, cy + 1),
            Self::piece(area, cx + 1, cy + 1),
        ];
        let row: i16 = cy.into() + 2;
        let odd = row % 2 == 1;
        let open: u256 = AssemblyTrait::assemble(chunks, origin.ox, origin.oy, odd).into();
        let open = open & INTERIOR;
        let x0: i16 = 15 * (cx.into() + 1) + origin.ox.into();
        let y0: i16 = 15 * (cy.into() + 1) + origin.oy.into();
        Board {
            window: WindowTrait::new(open.try_into().unwrap()),
            x: x0.try_into().unwrap(),
            y: y0.try_into().unwrap(),
        }
    }

    /// Chunk `(cx, cy)` in the assembly: `None` when void (D-134), its walkable tiles when
    /// revealed, all wall when not (D-136).
    fn piece(area: @Area, cx: i8, cy: i8) -> Option<felt252> {
        if cx < 0 || cy < 0 || cx >= 15 || cy >= 15 {
            return None;
        }
        let cx: u8 = cx.try_into().unwrap();
        let cy: u8 = cy.try_into().unwrap();
        let chunk = cy * 15 + cx;
        if !Bitmap::has(*area.known, chunk) {
            return None;
        }
        if !Bitmap::has(*area.revealed, chunk) {
            return Some(0);
        }
        for (c, bits) in *area.chunks {
            if *c == chunk {
                return Some(*bits);
            }
        }
        Some(0)
    }

    /// Whether sight (radius 6) from the adventurer touches a chunk not yet revealed.
    fn to_reveal(area: @Area, world: @World) -> bool {
        let (x, y, _) = world.member(0).place();
        for chunk in SightTrait::chunks(x, y, *area.width, *area.height) {
            if Bitmap::has(*area.known, chunk) && !Bitmap::has(*area.revealed, chunk) {
                return true;
            }
        }
        false
    }

    /// Whether the member holds a `MOVEMENT` effect at clock `c` (FX-18).
    fn movement(member: @Member, sheets: @Sheets, c: u32) -> bool {
        let lever = Levered {};
        let mut slot: u8 = 0;
        while slot < 4 {
            let at = member.effect_position(slot);
            let held = member.effect_of(slot);
            if at != ABSENT_LANE && !held.potion && c < held.deadline {
                let at: u32 = at.try_into().unwrap();
                let mut k = 0;
                while k < 3 {
                    if lever.entry(sheets, at, k).kind == kind::MOVEMENT {
                        return true;
                    }
                    k += 1;
                }
            }
            slot += 1;
        }
        false
    }
}
