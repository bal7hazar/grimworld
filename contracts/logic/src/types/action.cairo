//! The adventurer's action (CBT-05b; design/19 §5.3): between two ticks the clock reads `c`, and
//! one action of the batch runs there, before its ticks. A value type's behaviour over the `World`,
//! as the pipeline's: it sits in `types/` (docs/CAIRO.md §7, D-147). ENG-07's `play` calls it for
//! each action (`TickLibrary::act`), then runs the action's ticks.
//!
//! For the combat kinds (Attack, Skill, Item, Turn, Wait; Move and Interact are ENG-07's, CBT-05b's
//! open question 2), in §5.3's order:
//! 1. **Legality** against the state as it is (design/02 *Executing a batch*): the clock past
//!    `LAST_TICK` (E-4); the adventurer knocked down acts only by Wait (FX-7); a second Turn or a
//!    second instant skill between two ticks (`MemberState.flags` bits 0–1); an empty bar or belt
//!    slot, a belt count at 0; the skill recharging; energy short after reductions; adrenaline
//!    short; a target its carrier does not address (§2.3: a dead goblin is neither foe nor ally; a
//!    tile for an entity), out of range or of sight (ENG-02's `reach`); a trap tile that cannot
//!    take one (§5.11, FX-14). Illegal is a refusal (`Illegal`): nothing is written, the batch
//!    stops (`Stop::Invalid`). Never a panic on a legal action (D-140).
//! 2. **Costs** at once (FX-0): energy after *Fieldcraft* (`ENERGY_COST` of a Warden's skills,
//!    design/20 §1.3) and the glyphs held (`NEXT_SPELL_COST`, at a spell's start, consumed),
//!    floored at 0 (§6); adrenaline; an instant skill's recharge from its use (§5.1); the
//!    potion's belt count; the `casts` counters (§5.12, FX-39, FX-43) at a spell's start.
//!    Interrupted later, every cost stays spent (§5.9).
//! 3. **Facing** through ENG-02's `WindowTrait::facing` toward the target (an entity's tile or the
//!    tile), Turn's direction set directly; the same tile or a position outside the window leaves
//!    it unchanged (D-174).
//! 4. **Resolution now** through CBT-05a's executor (`Carry`: a weapon attack, an attack skill
//!    without activation, FX-5; a potion; an instant skill), **or** an activation starts
//!    (`MemberTickTrait::start`, `n` after the quick-cast bonus), resolving in step 1 of its `n`-th
//!    tick.
//! 5. The action's **tick cost** is returned for the pipeline (FX-3): Wait 1, Turn 0, a weapon
//!    attack its weapon's `k`, an attack skill `max(k, n)` (FX-5), any other skill its activation
//!    (an instant one 0), a potion 1 (design/04).
//!
//! **Not built** (CBT-05b's escalations): an attack skill's weapon of its attribute (§3.4: no
//! attribute id names a weapon class; the attribute id space is open, ENG-01 §7.2), and which
//! quick-cast pair a spell counts for (its attribute is a global id, the pair's a build-local
//! index, D-157 A: no word of the member maps one to the other). `QuickCastTrait::count` is the
//! rule, held to §10.6; the action phase passes it no matching pair until the mapping exists.

use crate::actions::Action;
use crate::models::member::{
    Member, MemberConditionTrait, MemberSnapshotTrait, MemberTickTrait, MemberTrait,
    MemberWordsTrait,
};
use crate::professions::Profession;
use crate::types::combat::skill_kind;
use crate::types::effect::{EntryTrait, kind, target};
use crate::types::executor::{Board, BoardTrait, Carrier, Executed, ExecutorTrait, Levered, Levers};
use crate::types::tick::{ABSENT_LANE, ENERGY_THIRDS, Sheets, flag};
use crate::types::trap::{Ground, TrapTrait};
use crate::types::window::WindowTrait;
use crate::types::world::{Actor, World, WorldTrait};
use crate::types::{LAST_TICK, Target};

/// *Fieldcraft*'s energy a primary rank takes off a Warden skill's cost (design/20 §1.3, DS-7: at
/// most 1 a rank): a code constant until BAL-01.
pub const FIELDCRAFT_PER_RANK: u8 = 1;

/// Why an action is illegal in the state it meets (design/02, design/19 §5.3 step 1): the batch
/// stops. The order of the variants is not stored.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub enum Illegal {
    /// The clock is past `LAST_TICK` (ENG-01 §4.1, E-4).
    Clock,
    /// The adventurer is not inside or is at 0 health.
    Absent,
    /// Knocked down: only Wait (FX-7).
    Knocked,
    /// A second Turn between two ticks.
    Turned,
    /// A second instant skill between two ticks.
    Instant,
    /// An empty bar or belt slot (or a potion the content does not hold).
    Empty,
    /// The belt slot's count is 0.
    Belt,
    /// The skill is recharging (`c < R`, §5.1).
    Recharging,
    /// Energy short after reductions.
    Energy,
    /// Adrenaline short.
    Adrenaline,
    /// A target the carrier does not address: no such entity, a dead or wrong-side one (§2.3), a
    /// tile for an entity or an entity for a tile.
    Target,
    /// Out of range or of sight (ENG-02's `reach`).
    Reach,
    /// A trap tile that cannot take one (§5.11, FX-14).
    Trap,
    /// Move and Interact: ENG-07's.
    Kind,
}

/// The executor as the action phase calls it for an immediate carrier (§5.3 step 4) and as step 1
/// does at an activation's conclusion: `TickLibrary`'s rules call `ExecutorLibrary`
/// (`executor::Delegate`), the in-class ones run it in process (`executor::Executor`).
pub trait Carry<R> {
    /// Runs `carrier` of `source` (from its bar or caste `slot`) on `address` at `t` (§5.14). A
    /// `TRAP` carrier whose guard held places its trap on the address's tile if the tile can take
    /// one (§5.11): `Executed::Place`, else `Executed::Illegal`.
    fn carry(
        ref self: R,
        ref world: World,
        sheets: @Sheets,
        source: Actor,
        slot: u8,
        carrier: Carrier,
        address: u16,
        t: u32,
    ) -> Executed;
    /// The tick's board.
    fn board(self: @R) -> Board;
    /// The chunk objects the call carries.
    fn ground(self: @R) -> @Ground;
}

/// What an action addresses, read before any write: the carrier, its address and the window's
/// position of its target (the source's own for `SELF`).
#[derive(Copy, Drop, Debug, PartialEq)]
struct Aim {
    carrier: Carrier,
    address: u16,
    to: u8,
}

#[generate_trait]
pub impl ActionImpl of ActionTrait {
    /// §5.3 steps 1–4 for member `m`'s `action` at the clock `c = world.clock`: the action's
    /// tick cost, or why it is illegal (then nothing is written).
    fn act<R, +Carry<R>, +Destruct<R>>(
        ref world: World, sheets: @Sheets, ref rules: R, m: u32, action: Action,
    ) -> Result<u8, Illegal> {
        let c = world.clock;
        if c > LAST_TICK {
            return Err(Illegal::Clock);
        }
        let mut member = world.member(m);
        if !member.is_alive() {
            return Err(Illegal::Absent);
        }
        let t0 = c + 1;
        if !member.can_act(t0) && action != Action::Wait {
            return Err(Illegal::Knocked);
        }
        let board = rules.board();
        let (x, y, facing) = member.place();
        let from = board.position(x, y);
        let source = Actor::Member(m);
        match action {
            Action::Wait => Ok(1),
            Action::Turn(direction) => {
                if member.flags & flag::TURNED != 0 {
                    return Err(Illegal::Turned);
                }
                member.flags = member.flags | flag::TURNED;
                member.set_facing(direction);
                world.set_member(m, member);
                Ok(0)
            },
            Action::Attack(entity) => {
                let aim = Self::aim(
                    @world, sheets, @board, source, from, Carrier::Weapon, Target::Entity(entity),
                )?;
                member.set_facing(WindowTrait::facing(from, aim.to, facing));
                world.set_member(m, member);
                let _ = rules.carry(ref world, sheets, source, 0, Carrier::Weapon, entity, t0);
                Ok(member.weapon_ticks())
            },
            Action::Skill((
                slot, address,
            )) => {
                let at = member.position(slot);
                if at == ABSENT_LANE {
                    return Err(Illegal::Empty);
                }
                let at: u32 = at.try_into().unwrap();
                let sheet = *sheets.skills[at];
                let attack = sheet.kind == skill_kind::ATTACK;
                let instant = sheet.activation == 0 && !attack;
                if instant && member.flags & flag::INSTANT != 0 {
                    return Err(Illegal::Instant);
                }
                if c < member.recharge(slot) {
                    return Err(Illegal::Recharging);
                }
                let adrenaline: u16 = sheet.adrenaline.into() * 4;
                if member.adrenaline < adrenaline {
                    return Err(Illegal::Adrenaline);
                }
                let spell = Self::is_spell(sheet.kind);
                let (glyph, glyphs) = if spell {
                    Self::glyphs(@member, sheets, c)
                } else {
                    (0, 0)
                };
                let energy = Self::energy(@member, sheet.energy, sheet.profession, glyph);
                if member.energy < energy {
                    return Err(Illegal::Energy);
                }
                let carrier = Carrier::Skill((at, member.rank(slot)));
                let aim = Self::aim(@world, sheets, @board, source, from, carrier, address)?;
                let lever = Levered {};
                if lever.entry(sheets, at, 0).kind == kind::TRAP
                    && TrapTrait::spot(@world, @board, rules.ground(), aim.to).is_none() {
                    return Err(Illegal::Trap);
                }
                // 2. Costs, at once.
                member.energy -= energy;
                member.adrenaline -= adrenaline;
                Self::consume(ref member, glyphs, c);
                let mut n = sheet.activation;
                if spell && n >= 1 {
                    let (casts, quick) = QuickCastTrait::count(
                        [member.casts(0), member.casts(1)], member.quick_casts(), 0,
                    );
                    let [c0, c1] = casts;
                    member.set_casts(0, c0);
                    member.set_casts(1, c1);
                    n = if quick >= n {
                        1
                    } else {
                        n - quick
                    };
                }
                // 3. Facing.
                member.set_facing(WindowTrait::facing(from, aim.to, facing));
                // 4. Now, or an activation.
                if n == 0 {
                    // Its recharge from its use (§5.1); an instant skill's flag (an attack skill
                    // without activation costs its weapon's ticks, FX-5).
                    member.use_instant(slot, c, sheets);
                    if instant {
                        member.flags = member.flags | flag::INSTANT;
                    }
                    world.set_member(m, member);
                    let _ = rules.carry(ref world, sheets, source, slot, carrier, aim.address, t0);
                    return Ok(if attack {
                        member.weapon_ticks()
                    } else {
                        0
                    });
                }
                member.start(slot, aim.address, n, c);
                if let Target::Tile(_) = address {
                    member.act_tile = 1;
                }
                world.set_member(m, member);
                let ticks: u8 = n.try_into().unwrap();
                Ok(
                    if attack && member.weapon_ticks() > ticks {
                        member.weapon_ticks()
                    } else {
                        ticks
                    },
                )
            },
            Action::Item((
                slot, address,
            )) => {
                let item = member.belt_item(slot.into());
                let mut at: Option<u32> = None;
                let mut k: u32 = 0;
                for sheet in *sheets.potions {
                    if item != 0 && *sheet.id == item {
                        at = Some(k);
                        break;
                    }
                    k += 1;
                }
                let at = match at {
                    Some(at) => at,
                    None => { return Err(Illegal::Empty); },
                };
                let count = member.belt_count(slot);
                if count == 0 {
                    return Err(Illegal::Belt);
                }
                let carrier = Carrier::Potion((at, slot));
                // The item's target is an entity or a tile by its entry (ENG-01 *play*).
                let addressing = Levered {}.potion_entry(sheets, at).target;
                let address = if addressing == target::TILE {
                    Target::Tile(address)
                } else {
                    Target::Entity(address)
                };
                let aim = Self::aim(@world, sheets, @board, source, from, carrier, address)?;
                member.set_belt_count(slot, count - 1);
                member.set_facing(WindowTrait::facing(from, aim.to, facing));
                world.set_member(m, member);
                let _ = rules.carry(ref world, sheets, source, slot, carrier, aim.address, t0);
                Ok(1)
            },
            Action::Move(_) => Err(Illegal::Kind),
            Action::Interact(_) => Err(Illegal::Kind),
        }
    }

    /// The carrier's address and its target's position, if the carrier addresses `address`
    /// (§2.3) and it is in reach (ENG-02's `reach`): a `FOE` a living goblin, an `ALLY` a living
    /// member, a `TILE` a tile, `SELF` the source.
    fn aim(
        world: @World,
        sheets: @Sheets,
        board: @Board,
        source: Actor,
        from: u8,
        carrier: Carrier,
        address: Target,
    ) -> Result<Aim, Illegal> {
        let lever = Levered {};
        let (addressing, reach) = ExecutorTrait::addressing(@lever, world, sheets, source, carrier);
        if addressing == target::SELF {
            let entity: u16 = match source {
                Actor::Member(i) => i.try_into().unwrap(),
                Actor::Goblin(_) => 0,
            };
            return Ok(Aim { carrier, address: entity, to: from });
        }
        let (address, to) = match address {
            Target::Tile(tile) => {
                if addressing != target::TILE {
                    return Err(Illegal::Target);
                }
                (tile, board.tile(tile))
            },
            Target::Entity(entity) => {
                if addressing == target::TILE {
                    return Err(Illegal::Target);
                }
                let actor = match ExecutorTrait::actor(world, entity) {
                    Some(actor) => actor,
                    None => { return Err(Illegal::Target); },
                };
                let member = match actor {
                    Actor::Member(_) => true,
                    Actor::Goblin(_) => false,
                };
                if member != (addressing == target::ALLY) {
                    return Err(Illegal::Target);
                }
                let (alive, at) = ExecutorTrait::locate(world, board, actor);
                if !alive {
                    return Err(Illegal::Target);
                }
                (entity, at)
            },
        };
        if !board.window.reach(from, to, reach) {
            return Err(Illegal::Reach);
        }
        Ok(Aim { carrier, address, to })
    }

    /// A spell for glyphs and quick cast: skill kinds 2, 3, 4 (§3.4; FX-25: not kind 11).
    #[inline(always)]
    fn is_spell(kind: u8) -> bool {
        kind == skill_kind::SPELL || kind == skill_kind::HEX || kind == skill_kind::ENCHANTMENT
    }

    /// The energy, in thirds, a skill of `energy` and `profession` costs `member` (§5.3 step 2):
    /// less *Fieldcraft* on a Warden's Warden skill and the glyphs' `glyph`, floored at 0 (§6).
    fn energy(member: @Member, energy: u8, profession: u8, glyph: u32) -> u16 {
        let (primary, rank) = member.primary();
        let warden: u8 = Profession::Warden.into();
        let fieldcraft: u32 = if primary == warden && profession == warden {
            rank.into() * FIELDCRAFT_PER_RANK.into()
        } else {
            0
        };
        let off = fieldcraft + glyph;
        let cost: u32 = energy.into();
        if off >= cost {
            0
        } else {
            ((cost - off) * ENERGY_THIRDS.into()).try_into().unwrap()
        }
    }

    /// The `NEXT_SPELL_COST` (kind 9) the member's held glyphs take off a spell at clock `c`,
    /// summed at each one's rank (§3.3), and the mask of their slots (bit `s`).
    fn glyphs(member: @Member, sheets: @Sheets, c: u32) -> (u32, u8) {
        let lever = Levered {};
        let mut off: u32 = 0;
        let mut mask: u8 = 0;
        let mut bit: u8 = 1;
        let mut slot: u8 = 0;
        while slot < 4 {
            let at = member.effect_position(slot);
            let held = member.effect_of(slot);
            if at != ABSENT_LANE && !held.potion && c < held.deadline {
                let at: u32 = at.try_into().unwrap();
                for k in 0..3_u32 {
                    let entry = lever.entry(sheets, at, k);
                    if entry.kind == kind::NEXT_SPELL_COST {
                        let v = EntryTrait::line(entry.v0, entry.v12, held.rank);
                        if v > 0 {
                            off += v.try_into().unwrap();
                        }
                        mask = mask | bit;
                    }
                }
            }
            bit *= 2;
            slot += 1;
        }
        (off, mask)
    }

    /// The glyphs of `mask` consumed at clock `c`: each ends now (`D = c`, §5.1: a duration of 0).
    fn consume(ref member: Member, mask: u8, c: u32) {
        let mut rest = mask;
        let mut slot: u8 = 0;
        while rest != 0 {
            if rest % 2 == 1 {
                let mut held = member.effect_of(slot);
                held.deadline = c;
                let [r0, r1, r2, r3] = member.effect_regen;
                member.set_effect(slot, held, *[r0, r1, r2, r3].span()[slot.into()]);
            }
            rest /= 2;
            slot += 1;
        }
    }
}

/// The quick-cast counters (design/19 §5.12, FX-39, FX-43).
#[generate_trait]
pub impl QuickCastImpl of QuickCastTrait {
    /// A spell with activation ≥ 1 starts: each pair `(attribute, N)` of `pairs` with `N > 0`
    /// whose bit is set in `matches` (the spell is of its attribute) moves its counter; one at `N`
    /// gives a bonus of 1 and resets. Returns the counters and the bonuses added (the caller keeps
    /// the activation at least 1).
    fn count(counters: [u8; 2], pairs: [(u8, u8); 2], matches: u8) -> ([u8; 2], u16) {
        let [c0, c1] = counters;
        let [(_, n0), (_, n1)] = pairs;
        let (c0, b0) = Self::step(c0, n0, matches & 1 != 0);
        let (c1, b1) = Self::step(c1, n1, matches & 2 != 0);
        ([c0, c1], b0 + b1)
    }

    #[inline(always)]
    fn step(casts: u8, n: u8, matches: bool) -> (u8, u16) {
        if n == 0 || !matches {
            return (casts, 0);
        }
        if casts + 1 >= n {
            (0, 1)
        } else {
            (casts + 1, 0)
        }
    }
}
