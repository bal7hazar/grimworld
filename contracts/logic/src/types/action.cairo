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
//!    slot, a belt count at 0; an attack skill without the weapon of its attribute (§3.4); the
//!    skill recharging; energy short after reductions; adrenaline short; a target its carrier
//!    does not address (§2.3: a dead goblin is neither foe nor ally; a tile for an entity), out
//!    of range or of sight (ENG-02's `reach`); a trap tile that cannot take one (§5.11, FX-14).
//!    Illegal is a refusal (`Illegal`): nothing is written, the batch stops (`Stop::Invalid`).
//!    Never a panic on a legal action (D-140).
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
//! **The attribute mappings** (CBT-05f, CBT-05b's escalation 2): the skill's attribute is a global
//! id, a quick-cast pair's a build-local index (D-157 A), and no attribute id names a weapon class
//! (the id space is open, ENG-01 §7.2). `set_build`'s flattening maps them once, into
//! `MemberStats`' free bits: the pairs each bar slot counts for (`quick_cast_matches`, the
//! `matches` of `QuickCastTrait::count`) and whether its attack skill needs a weapon of another
//! attribute than the one held (`weapon_required`: refused, `Illegal::Kind`).

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
    /// An action the member cannot take: Move and Interact here (ENG-07's, the segment's own:
    /// Interact is refused until its entrypoints exist, ENG-07 Open question 6); an attack skill
    /// without the weapon of its attribute (design/19 §3.4's skill kinds; `MemberStats`'
    /// weapon-required bit, CBT-05f: a variant of its own would grow the classes that deserialize
    /// `Illegal`, D-240).
    Kind,
    /// A Move onto a tile that is not walkable or holds a living actor (ENG-07).
    Blocked,
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
                if attack && member.weapon_required(slot) {
                    return Err(Illegal::Kind);
                }
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
                        [member.casts(0), member.casts(1)],
                        member.quick_casts(),
                        member.quick_cast_matches(slot),
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

/// The action phase's unit tests (CBT-05b; D-167): each legality row refused, each legal kind with
/// its tick cost, the costs, facing, quick cast (§10.6). The executor's fixtures
/// (`executor::tests`), the in-class executor as the rules.
#[cfg(test)]
mod tests {
    use crate::actions::Action;
    use crate::models::chunk::FeaturesTrait;
    use crate::models::member::{
        Member, MemberConditionTrait, MemberSnapshotTrait, MemberTickTrait, MemberTrait,
        MemberWordsTrait,
    };
    use crate::types::combat::{damage, skill_kind, weapon};
    use crate::types::effect::{Entry, EntryTrait, filter, kind, shape, target};
    use crate::types::executor::tests::{AT, SNARE, at, content, entry, goblin, member, skill};
    use crate::types::executor::{BoardTrait, Executor, ExecutorTrait};
    use crate::types::infliction::Infliction;
    use crate::types::tick::{ABSENT_LANE, Content, ContentTrait, Held, PotionSheet, Sheets, flag};
    use crate::types::window::{FAR, WindowTrait};
    use crate::types::world::fixtures::{Fixture, two};
    use crate::types::world::{World, WorldTrait};
    use crate::types::{LAST_TICK, Target};
    use super::{ActionTrait, FIELDCRAFT_PER_RANK, Illegal, QuickCastTrait};

    /// The tests' own skills, after the executor's (ids 60 on).
    const GLYPH: u16 = 60;
    const FIRE: u16 = 61;
    const FIELD: u16 = 62;
    const STANCE: u16 = 63;
    const RAGE: u16 = 64;
    const MEND: u16 = 65;
    /// The bomb, belt slot 0's item (the fixtures' kit: 100–103).
    const BOMB: u32 = 100;
    const CLOCK: u32 = 200;

    /// The executor's content (armor 40), its Snare as design/19 §10.10's (10 / 2 / 20), and:
    /// a glyph (`NEXT_SPELL_COST` 4, 10 ticks); a fire spell (5 energy, activation 3, range 6, 40
    /// fire on a foe); a Warden skill (8 energy, instant, a heal); a stance (instant); an attack
    /// skill of 2 adrenaline; an instant heal on an ally of range 6. Belt slot 0's bomb: 30 fire on
    /// `DISC_1` around a tile, range 6.
    fn bench() -> Content {
        let none: Entry = Default::default();
        let bomb = entry(
            kind::DAMAGE, damage::FIRE, 30, 30, target::TILE, shape::DISC_1, filter::FOES,
        );
        let base = content(
            40,
            array![PotionSheet { id: BOMB, entry: bomb.pack(), range: 6, ..Default::default() }]
                .span(),
        );
        let mut skills = array![];
        for sheet in base.skills {
            let mut sheet = *sheet;
            if sheet.id == SNARE {
                sheet.energy = 10;
                sheet.activation = 2;
                sheet.recharge = 20;
            }
            skills.append(sheet);
        }
        let glyph = EntryTrait::new(
            kind::NEXT_SPELL_COST,
            0,
            4,
            4,
            10,
            10,
            0,
            target::SELF,
            shape::SINGLE,
            filter::ALLIES,
            0,
            0,
        );
        let mut sheet = skill(GLYPH, skill_kind::GLYPH, 0, [glyph, none, none]);
        sheet.activation = 0;
        skills.append(sheet);
        let fire = entry(
            kind::DAMAGE, damage::FIRE, 40, 40, target::FOE, shape::SINGLE, filter::FOES,
        );
        let mut sheet = skill(FIRE, skill_kind::SPELL, 6, [fire, none, none]);
        sheet.energy = 5;
        sheet.activation = 3;
        skills.append(sheet);
        let heal = entry(kind::HEAL, 0, 10, 10, target::SELF, shape::SINGLE, filter::ALLIES);
        let mut sheet = skill(FIELD, skill_kind::SKILL, 0, [heal, none, none]);
        sheet.energy = 8;
        sheet.profession = 2;
        sheet.activation = 0;
        skills.append(sheet);
        let mut sheet = skill(STANCE, skill_kind::STANCE, 0, [heal, none, none]);
        sheet.activation = 0;
        skills.append(sheet);
        let mut sheet = skill(RAGE, skill_kind::ATTACK, 1, [none, none, none]);
        sheet.adrenaline = 2;
        sheet.activation = 0;
        skills.append(sheet);
        let mend = entry(kind::HEAL, 0, 10, 10, target::ALLY, shape::SINGLE, filter::ALLIES);
        let mut sheet = skill(MEND, skill_kind::SKILL, 6, [mend, none, none]);
        sheet.activation = 0;
        skills.append(sheet);
        Content { skills: skills.span(), potions: base.potions, castes: base.castes }
    }

    /// `id` on bar `slot` at `rank`, at its position in `sheets`.
    fn equip(ref member: Member, sheets: @Sheets, slot: u8, id: u16, rank: u8) {
        let lane: u128 = two(16 * slot.into()).try_into().unwrap();
        let old = member.skill(slot);
        member.words.bar += (id.into() - old.into()) * two(16 * slot.into());
        let position: u128 = at(sheets, id).into();
        member.bar_at = member.bar_at - member.position(slot) * lane + position * lane;
        member.words.stats += rank.into() * two(128 + 4 * slot.into());
    }

    /// The member at `AT` (a sword), 10 energy, with `ids` on bar slots 0 on, rank 12.
    fn adventurer(sheets: @Sheets, ids: Span<u16>) -> Member {
        let mut member = member(AT, 0, weapon::SWORD);
        let mut slot: u8 = 0;
        for id in ids {
            equip(ref member, sheets, slot, *id, 12);
            slot += 1;
        }
        member
    }

    /// The location's tile `x + 256 y` of the window's `position` (the board at the origin).
    fn tile(position: u8) -> u16 {
        (position % 15).into() + 256 * (position / 15).into()
    }

    fn fresh() -> Executor {
        let mut rules = ExecutorTrait::new(crate::types::executor::tests::board());
        rules.ground = array![(0, FeaturesTrait::empty())];
        rules
    }

    fn act(ref world: World, sheets: @Sheets, action: Action) -> Result<u8, Illegal> {
        let mut rules = fresh();
        ActionTrait::act(ref world, sheets, ref rules, 0, action)
    }

    // ---- Legal actions and their tick costs ---------------------------------------------------

    // Wait costs 1 and writes nothing; Turn costs 0, sets the facing, and only once between two
    // ticks (design/04); a knocked-down adventurer may only Wait (FX-7).
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 10564147)] // ceil(1.05 × 10061092 measured)
    fn test_wait_turn_knocked() {
        let sheets = bench().sheets();
        let mut world = Fixture::world(
            CLOCK, array![adventurer(@sheets, array![].span())], array![],
        );
        let before = world.member(0);
        assert(act(ref world, @sheets, Action::Wait) == Ok(1), 'wait 1');
        assert(world.member(0) == before, 'wait writes nothing');
        assert(act(ref world, @sheets, Action::Turn(3)) == Ok(0), 'turn 0');
        let (_, _, facing) = world.member(0).place();
        assert(facing == 3 && world.member(0).flags & flag::TURNED != 0, 'turned');
        assert(act(ref world, @sheets, Action::Turn(4)) == Err(Illegal::Turned), 'second turn');
        let mut member = world.member(0);
        member.knocked = CLOCK + 1;
        world.set_member(0, member);
        assert(act(ref world, @sheets, Action::Attack(8)) == Err(Illegal::Knocked), 'knocked');
        assert(act(ref world, @sheets, Action::Wait) == Ok(1), 'knocked: wait');
        assert(act(ref world, @sheets, Action::Move(0)) == Err(Illegal::Knocked), 'knocked: move');
    }

    // The clock past `LAST_TICK` refuses any action (E-4); an adventurer at 0 acts no more; Move
    // and Interact are ENG-07's.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 10359930)] // ceil(1.05 × 9866600 measured)
    fn test_clock_absent_kind() {
        let sheets = bench().sheets();
        let mut world = Fixture::world(
            LAST_TICK + 1, array![adventurer(@sheets, array![].span())], array![],
        );
        assert(act(ref world, @sheets, Action::Wait) == Err(Illegal::Clock), 'clock');
        world.clock = LAST_TICK;
        assert(act(ref world, @sheets, Action::Wait) == Ok(1), 'at LAST_TICK');
        assert(act(ref world, @sheets, Action::Move(0)) == Err(Illegal::Kind), 'move: ENG-07');
        assert(act(ref world, @sheets, Action::Interact(0)) == Err(Illegal::Kind), 'interact');
        let mut member = world.member(0);
        member.health = 0;
        world.set_member(0, member);
        assert(act(ref world, @sheets, Action::Wait) == Err(Illegal::Absent), 'absent');
    }

    // A weapon attack lands now and costs the weapon's `k` (1 here): the goblin hit, the member
    // turned toward it. Refused: no such entity, a member, a dead goblin, one out of reach.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 13418201)] // ceil(1.05 × 12779239 measured)
    fn test_attack() {
        let sheets = bench().sheets();
        let near = AT + 1;
        let far = AT + 3;
        let mut world = Fixture::world(
            CLOCK,
            array![adventurer(@sheets, array![].span())],
            array![goblin(8, near, 0, 100), goblin(9, far, 0, 100), goblin(10, AT - 1, 0, 0)],
        );
        assert(act(ref world, @sheets, Action::Attack(77)) == Err(Illegal::Target), 'no such');
        assert(act(ref world, @sheets, Action::Attack(0)) == Err(Illegal::Target), 'a member');
        assert(act(ref world, @sheets, Action::Attack(10)) == Err(Illegal::Target), 'dead');
        assert(act(ref world, @sheets, Action::Attack(9)) == Err(Illegal::Reach), 'out of reach');
        assert(act(ref world, @sheets, Action::Attack(8)) == Ok(1), 'k = 1');
        assert(world.goblin(0).health < 100, 'hit now');
        let (_, _, facing) = world.member(0).place();
        assert(facing == WindowTrait::facing(AT, near, 0), 'faces it');
    }

    // A spell with activation: its energy paid at once, its activation started (`A = c + n`), its
    // tick cost `n`; the target an entity it addresses, in range and sight. Refused: an empty bar
    // slot, recharging, energy short, a tile for an entity.
    #[test]
    #[available_gas(l2_gas: 12336834)] // ceil(1.05 × 11749365 measured)
    fn test_spell_activation() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![FIRE].span());
        member.bar_at = member.bar_at | (ABSENT_LANE * 0x10000);
        let foe = AT + 4;
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, foe, 0, 100)]);
        assert(
            act(ref world, @sheets, Action::Skill((1, Target::Entity(8)))) == Err(Illegal::Empty),
            'empty slot',
        );
        assert(
            act(
                ref world, @sheets, Action::Skill((0, Target::Tile(foe.into()))),
            ) == Err(Illegal::Target),
            'a tile',
        );
        let mut member = world.member(0);
        member.set_recharge(0, CLOCK + 1);
        world.set_member(0, member);
        assert(
            act(
                ref world, @sheets, Action::Skill((0, Target::Entity(8))),
            ) == Err(Illegal::Recharging),
            'recharging',
        );
        let mut member = world.member(0);
        member.set_recharge(0, CLOCK);
        member.energy = 14;
        world.set_member(0, member);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Err(Illegal::Energy),
            'energy short',
        );
        let mut member = world.member(0);
        member.energy = 30;
        world.set_member(0, member);
        assert(act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Ok(3), 'n = 3');
        let member = world.member(0);
        assert(member.energy == 15 && member.act_slot == 0, 'paid, started');
        assert(member.act_deadline == CLOCK + 3 && member.act_target == 8, 'A = c + n');
        assert(world.goblin(0).health == 100, 'resolves later');
    }

    // An instant skill resolves now, costs 0 ticks, sets its recharge from its use (`t₀ = c + 1`)
    // and the flag: a second instant skill between two ticks is refused. An attack skill of 2
    // adrenaline: refused short, else lands now for its weapon's `k` (FX-5).
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 14293085)] // ceil(1.05 × 13612461 measured)
    fn test_instant_and_attack_skill() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![STANCE, FIELD, RAGE].span());
        member.health = 300;
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, AT + 1, 0, 100)]);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Entity(0)))) == Ok(0), 'instant: 0',
        );
        let member = world.member(0);
        assert(member.flags & flag::INSTANT != 0 && member.health == 310, 'now, flagged');
        assert(member.recharge(0) == CLOCK + 1 + 10 - 1, 'R = c + r');
        assert(
            act(ref world, @sheets, Action::Skill((1, Target::Entity(0)))) == Err(Illegal::Instant),
            'second instant',
        );
        assert(
            act(
                ref world, @sheets, Action::Skill((2, Target::Entity(8))),
            ) == Err(Illegal::Adrenaline),
            'adrenaline short',
        );
        let mut member = world.member(0);
        member.adrenaline = 9;
        world.set_member(0, member);
        assert(
            act(ref world, @sheets, Action::Skill((2, Target::Entity(8)))) == Ok(1),
            'attack skill: k',
        );
        assert(world.member(0).adrenaline == 1 && world.goblin(0).health < 100, 'paid, landed');
    }

    // Energy after reductions (§5.3 step 2, §6): *Fieldcraft* takes `FIELDCRAFT_PER_RANK` a
    // primary rank off a Warden's Warden skill, floored at 0; a held glyph takes its
    // `NEXT_SPELL_COST` off a spell and is consumed, not off a skill of kind 11 (FX-25).
    #[test]
    #[available_gas(l2_gas: 13453209)] // ceil(1.05 × 12812580 measured)
    fn test_energy_reductions() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![FIELD, FIRE, MEND].span());
        // A Warden, Fieldcraft 12: the Warden skill's 8 energy floored at 0.
        member.words.stats += 2 * two(72) + 12 * two(80);
        assert(FIELDCRAFT_PER_RANK == 1, 'one a rank');
        member.energy = 0;
        let glyph = at(@sheets, GLYPH);
        member
            .set_effect(
                0,
                Held { carrier: GLYPH, potion: false, charges: 0, deadline: CLOCK + 5, rank: 12 },
                0,
            );
        member.effect_at = (member.effect_at & ~0xFFFF_u128) | glyph.into();
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, AT + 4, 0, 100)]);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Entity(0)))) == Ok(0),
            'fieldcraft: free',
        );
        assert(world.member(0).effect_of(0).deadline == CLOCK + 5, 'not a spell: kept');
        assert(
            act(ref world, @sheets, Action::Skill((2, Target::Entity(0)))) == Err(Illegal::Instant),
            'instant',
        );
        let mut member = world.member(0);
        member.flags = 0;
        member.energy = 3;
        world.set_member(0, member);
        // The spell's 5 less the glyph's 4: 1 energy, 3 thirds.
        assert(act(ref world, @sheets, Action::Skill((1, Target::Entity(8)))) == Ok(3), 'glyph: 1');
        let member = world.member(0);
        assert(member.energy == 0 && member.effect_of(0).deadline == CLOCK, 'consumed');
    }

    // An ally skill reaches a living member, not a goblin; a `SELF` one leaves the facing alone
    // (the same tile, D-174).
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 12936453)] // ceil(1.05 × 12320431 measured)
    fn test_ally_and_self() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![MEND, STANCE].span());
        member.health = 300;
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, AT + 1, 0, 100)]);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Err(Illegal::Target),
            'a goblin',
        );
        assert(act(ref world, @sheets, Action::Skill((1, Target::Entity(8)))) == Ok(0), 'self');
        let (_, _, facing) = world.member(0).place();
        assert(facing == 0, 'facing unchanged');
        let mut member = world.member(0);
        member.flags = 0;
        world.set_member(0, member);
        assert(act(ref world, @sheets, Action::Skill((0, Target::Entity(0)))) == Ok(0), 'an ally');
        assert(world.member(0).health == 320, 'healed twice');
    }

    // A potion: a bomb on a tile in range (its entry addresses a tile), the belt's count 1 less,
    // 1 tick, the goblins of its `DISC_1` hit now. Refused: an empty count, an item the content
    // lacks, out of reach.
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 12812935)] // ceil(1.05 × 12202795 measured)
    fn test_item_bomb() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![].span());
        member.set_belt_count(0, 1);
        let centre = AT + 2;
        let mut world = Fixture::world(
            CLOCK, array![member], array![goblin(8, centre, 0, 100), goblin(9, centre + 1, 0, 100)],
        );
        assert(
            act(ref world, @sheets, Action::Item((1, 8))) == Err(Illegal::Empty), 'not in content',
        );
        assert(
            act(ref world, @sheets, Action::Item((0, tile(AT + 7 * 15)))) == Err(Illegal::Reach),
            'out of reach',
        );
        assert(act(ref world, @sheets, Action::Item((0, tile(centre)))) == Ok(1), 'one tick');
        assert(world.member(0).belt_count(0) == 0, 'count 0');
        assert(world.goblin(0).health < 100 && world.goblin(1).health < 100, 'both hit');
        let (_, _, facing) = world.member(0).place();
        assert(facing == WindowTrait::facing(AT, centre, 0), 'faces the tile');
        assert(
            act(ref world, @sheets, Action::Item((0, tile(centre)))) == Err(Illegal::Belt),
            'count 0',
        );
    }

    // A trap tile that cannot take one refuses the skill (§5.11, FX-14): a wall (by sight), an
    // actor on it, a full chunk; on an empty walkable tile in range, the activation starts
    // (§10.10: 10 / 2 /
    // 20 at clock 300, `A = 302`).
    #[test]
    // gas: raised, ENG-07: perception, the AI, Board's origin (D-233 to D-236)
    #[available_gas(l2_gas: 12440172)] // ceil(1.05 × 11847782 measured)
    fn test_trap_tile() {
        let sheets = bench().sheets();
        let member = adventurer(@sheets, array![SNARE].span());
        let spot: u16 = 7 + 256 * 9;
        let position = 7 + 15 * 9;
        let mut world = Fixture::world(300, array![member], array![goblin(8, position, 0, 100)]);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Tile(spot)))) == Err(Illegal::Trap),
            'occupied',
        );
        world.set_goblin(0, goblin(8, position + 1, 0, 0));
        let mut rules = fresh();
        rules
            .board =
                BoardTrait::new(
                    WindowTrait::new(
                        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
                            - two(position.into()),
                    ),
                    0,
                    0,
                );
        // A wall at the line's end blocks the sight first (D-174): refused all the same.
        assert(
            ActionTrait::act(
                ref world, @sheets, ref rules, 0, Action::Skill((0, Target::Tile(spot))),
            ) == Err(Illegal::Reach),
            'a wall',
        );
        let mut rules = fresh();
        let chest = crate::models::chunk::Object {
            tile: 1, kind: crate::models::chunk::object::CHEST, state: 0, param: 0,
        };
        rules
            .ground =
                array![
                    (
                        0,
                        crate::models::chunk::Features {
                            objects: [chest; 3], ..FeaturesTrait::empty(),
                        },
                    ),
                ];
        assert(
            ActionTrait::act(
                ref world, @sheets, ref rules, 0, Action::Skill((0, Target::Tile(spot))),
            ) == Err(Illegal::Trap),
            'full chunk',
        );
        assert(act(ref world, @sheets, Action::Skill((0, Target::Tile(spot)))) == Ok(2), 'n = 2');
        let member = world.member(0);
        assert(
            member.act_deadline == 302 && member.act_target == spot && member.act_tile == 1,
            'A = 302',
        );
        assert(member.energy == 0, '10 energy');
    }

    // Facing (§5.3 step 3, ENG-02): toward a target two tiles away, the first step of the line.
    #[test]
    #[available_gas(l2_gas: 11316399)] // ceil(1.05 × 10777522 measured)
    fn test_facing_first_step() {
        let sheets = bench().sheets();
        let member = adventurer(@sheets, array![FIRE].span());
        let foe = AT + 2 * 15 + 1;
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, foe, 0, 100)]);
        assert(act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Ok(3), 'started');
        let (_, _, facing) = world.member(0).place();
        assert(facing == WindowTrait::facing(AT, foe, 0) && facing != FAR, 'first step');
    }

    // §5.12, FX-39, FX-43: each pair whose spell matches moves its counter; at N it resets and
    // gives 1; two pairs add; a pair of N 0 or not matching stays.
    #[test]
    #[available_gas(l2_gas: 25079)] // ceil(1.05 × 23884 measured)
    fn test_quick_cast_counters() {
        let pairs = [(1, 5), (2, 3)];
        assert(QuickCastTrait::count([4, 2], pairs, 3) == ([0, 0], 2), 'both at N');
        assert(QuickCastTrait::count([1, 1], pairs, 1) == ([2, 1], 0), 'first moves');
        assert(QuickCastTrait::count([1, 1], pairs, 0) == ([1, 1], 0), 'none matches');
        assert(QuickCastTrait::count([1, 1], [(1, 0), (2, 0)], 3) == ([1, 1], 0), 'N 0');
    }

    // §10.6: `QUICK_CAST_EVERY_N` Fire 5, `casts = 4`; a Fire spell of activation 3 starts at
    // clock 200: `casts` 4 → 0, activation 2, `A = 202`. Knocked down in step 2 of 201:
    // interrupted, energy stays paid, the recharge from `t₀ = 201`. The bonus is spent: the next
    // Fire spell makes `casts` 1.
    #[test]
    #[available_gas(l2_gas: 10412275)] // ceil(1.05 × 9916452 measured)
    fn test_example_fifth_cast_interrupted() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![FIRE].span());
        member.set_casts(0, 4);
        let (casts, bonus) = QuickCastTrait::count([member.casts(0), 0], [(1, 5), (0, 0)], 1);
        assert(casts == [0, 0] && bonus == 1, 'fifth: bonus');
        let [c0, _] = casts;
        member.set_casts(0, c0);
        member.energy -= 15;
        member.start(0, 8, 3 - bonus, CLOCK);
        assert(member.act_deadline == 202 && member.casts(0) == 0, 'A = 202');
        member.knock(1, @Infliction { condition: 0, percent: 0, knockdown: 0 }, 201, @sheets);
        assert(member.act_slot == crate::types::tick::NO_SLOT, 'interrupted');
        assert(member.recharge(0) == 201 + 10 - 1 && member.energy == 15, 'R from 201, paid');
        let (casts, _) = QuickCastTrait::count([member.casts(0), 0], [(1, 5), (0, 0)], 1);
        assert(casts == [1, 0], 'next: casts 1');
    }

    // §10.6 through `act` (CBT-05f; review t-0092 note 3): the kit's `QUICK_CAST_EVERY_N` Fire 5
    // is pair 0 (`MemberBar` 208–219), the Fire spell's slot counts for it (`MemberStats` 168),
    // `casts = 4`. At clock 200 the spell starts: `casts` 4 → 0, activation 3 − 1 = 2, `A =
    // 202`.
    // Knocked down in step 2 of 201: interrupted, energy paid, the recharge from 201. The bonus is
    // spent: the next Fire spell makes `casts` 1 and keeps its activation 3. A spell whose slot
    // counts for no pair leaves the counter alone.
    #[test]
    #[available_gas(l2_gas: 13620659)] // ceil(1.05 × 12972056 measured)
    fn test_example_fifth_cast_through_act() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![FIRE, FIRE].span());
        member.words.bar += 5 * two(212);
        member.words.stats += two(168);
        member.set_casts(0, 4);
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, AT + 4, 0, 100)]);
        assert(act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Ok(2), 'n = 2');
        let mut member = world.member(0);
        assert(member.casts(0) == 0 && member.act_deadline == 202, 'casts 0, A = 202');
        assert(member.energy == 15, 'paid');
        member.knock(1, @Infliction { condition: 0, percent: 0, knockdown: 0 }, 201, @sheets);
        assert(member.act_slot == crate::types::tick::NO_SLOT, 'interrupted');
        assert(member.recharge(0) == 201 + 10 - 1 && member.energy == 15, 'R from 201, paid');
        world.set_member(0, member);
        world.clock = member.recharge(0);
        assert(act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Ok(3), 'n = 3');
        let mut member = world.member(0);
        assert(member.casts(0) == 1, 'next: casts 1');
        member.act_slot = crate::types::tick::NO_SLOT;
        member.energy = 15;
        world.set_member(0, member);
        assert(act(ref world, @sheets, Action::Skill((1, Target::Entity(8)))) == Ok(3), 'slot 1');
        assert(world.member(0).casts(0) == 1, 'slot 1 counts for none');
    }

    // CBT-05f: an attack skill whose attribute is not the weapon's (`MemberStats` bit 40 + slot,
    // design/19 §3.4) is refused and writes nothing; the same skill on a slot without the bit
    // lands for the weapon's `k`.
    #[test]
    #[available_gas(l2_gas: 13089415)] // ceil(1.05 × 12466109 measured)
    fn test_attack_skill_without_its_weapon() {
        let sheets = bench().sheets();
        let mut member = adventurer(@sheets, array![RAGE, RAGE].span());
        member.adrenaline = 9;
        member.words.stats += two(40);
        let mut world = Fixture::world(CLOCK, array![member], array![goblin(8, AT + 1, 0, 100)]);
        let before = world.member(0);
        assert(
            act(ref world, @sheets, Action::Skill((0, Target::Entity(8)))) == Err(Illegal::Kind),
            'not its weapon',
        );
        assert(world.member(0) == before && world.goblin(0).health == 100, 'nothing written');
        assert(
            act(ref world, @sheets, Action::Skill((1, Target::Entity(8)))) == Ok(1), 'its weapon',
        );
        assert(world.goblin(0).health < 100, 'landed');
    }
}
