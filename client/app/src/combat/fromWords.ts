/**
 * A `CombatState` from the mirror's words (CLI-05 brief §10, CLI-05a): the members' and goblins'
 * packed words (`MirrorWords`, `preview/reconcile.ts`), the batch's content and the ground, on the
 * window's board. The world is client/sim's own load (`loadWorld(words, indexSheets(content))`,
 * `WordsTrait::load`), which refuses what Cairo refuses; every figure is then read by client/sim's
 * function (`bar.ts`, `chips.ts`, `targeting.ts`), never computed here.
 */

import {
  ABSENT,
  ABSENT_LANE,
  type Content,
  type Goblin,
  type Ground,
  type Member,
  type SegmentBoard,
  type Words,
  activation,
  aiState,
  condition,
  goblinPlace,
  groundObject,
  held,
  indexSheets,
  kind,
  loadWorld,
  memberPlace,
  shape,
  shapes,
  target,
} from "@grimworld/sim";
import type { MirrorWords } from "../preview/reconcile";
import type { Mark, Tile } from "../render/view";
import { activating, barOf, beltOf, knockedAt, QUARTERS, THIRDS } from "./bar";
import { goblinChips, memberChips } from "./chips";
import type {
  ActivationView,
  Aimed,
  CombatAdventurer,
  CombatGoblin,
  CombatState,
  CombatTrap,
  GoblinActivationView,
  Names,
} from "./state";
import { type CombatWorld, aiming, positionOf, tileOf } from "./targeting";

/** client/sim's `Words` from the mirror's (its arrays copied: the loader keeps them). */
const asWords = (words: MirrorWords): Words => ({
  clock: words.clock,
  members: words.members.map((m) => ({ ...m })),
  goblins: words.goblins.map((g) => ({ ...g })),
  killed: [...words.killed],
  defeated: words.defeated,
});

/** The world client/sim loads from the words, with what targeting reads beside it. */
export function readWorld(
  words: MirrorWords,
  content: Content,
  ground: Ground,
  board: SegmentBoard,
): CombatWorld {
  const sheets = indexSheets(content);
  return { world: loadWorld(asWords(words), sheets), sheets, board, ground };
}

/** The mark drawn over a goblin of AI state `ai` (design/11): none on watch or returning. */
export function markOf(ai: number): Mark | null {
  if (ai === aiState.ASLEEP) return "asleep";
  if (ai === aiState.ALERTED) return "alerted";
  if (ai === aiState.ENGAGED) return "engaged";
  if (ai === aiState.FLEEING) return "fleeing";
  return null;
}

/** A location's tile written as `x + 256 y` (`BoardTrait::tile`'s argument). */
const tileFrom = (value: number): Tile => ({ x: value % 256, y: Math.floor(value / 256) });

/** The ring of tiles around `at` when skill `at`'s entries hold a `RING_1` centred on the caster. */
function shout(cw: CombatWorld, skill: number, at: Tile): Tile[] {
  const ring = [0, 1, 2].some((k) => {
    const e = cw.sheets.entries[3 * skill + k]!;
    return e.kind !== kind.EMPTY && e.target === target.SELF && e.shape === shapes.RING_1;
  });
  const p = positionOf(cw.board, at);
  if (!ring || p >= 240) return [];
  const bits = shape(cw.board.open, shapes.RING_1, p);
  const tiles: Tile[] = [];
  for (let q = 0; q < 240; q++)
    if (((bits >> BigInt(q)) & 1n) === 1n) tiles.push(tileOf(cw.board, q));
  return tiles;
}

/** Whether skill `at` can interrupt: an `INTERRUPT` entry, or one that knocks down (§5). */
function interrupts(cw: CombatWorld, at: number): boolean {
  return [0, 1, 2].some((k) => {
    const e = cw.sheets.entries[3 * at + k]!;
    return (
      e.kind === kind.INTERRUPT || (e.kind === kind.CONDITION && e.param === condition.KNOCKED_DOWN)
    );
  });
}

/** The adventurer's activation, if one is in progress (§5). */
function memberActivation(cw: CombatWorld, member: Member, names?: Names): ActivationView | null {
  const clock = cw.world.clock;
  if (!activating(member, clock)) return null;
  const at = member.bar_at[member.act_slot]!;
  if (at === ABSENT_LANE) return null;
  const sheet = cw.sheets.skills[at]!;
  const { x, y } = memberPlace(member);
  const aimed: Aimed =
    member.act_tile === 1
      ? { tile: true, at: tileFrom(member.act_target) }
      : { tile: false, entity: member.act_target };
  return {
    slot: member.act_slot,
    skill: sheet.id,
    ...(names ? { name: names.skill(sheet.id) } : {}),
    ticks: member.act_deadline - clock,
    total: sheet.activation,
    target: aimed,
    area: shout(cw, at, { x, y }),
  };
}

/**
 * A goblin's activation (`act_slot` 0–3, its deadline ahead); a deadline passed is read as none
 * (a lapsed activation, design/19 §5.2). Interruptible when a ready bar slot holds a skill that
 * interrupts and client/sim's `aim` accepts the goblin as that skill's target.
 */
function goblinActivation(
  cw: CombatWorld,
  goblin: Goblin,
  ready: readonly number[],
  names?: Names,
): GoblinActivationView | null {
  const clock = cw.world.clock;
  if (goblin.act_slot > activation.LAST_SLOT || goblin.act_deadline <= clock) return null;
  const at = cw.sheets.kits[goblin.caste_at]!.skills[goblin.act_slot]!;
  if (at === ABSENT || at >= cw.sheets.skills.length) return null;
  const sheet = cw.sheets.skills[at]!;
  const { x, y } = goblinPlace(goblin);
  const interruptible = ready.some(
    (slot) =>
      interrupts(cw, cw.world.members[0]!.bar_at[slot]!) &&
      (aiming(cw, { kind: "skill", slot })?.marked.includes(goblin.entity) ?? false),
  );
  return {
    slot: goblin.act_slot,
    skill: sheet.id,
    ...(names ? { name: names.skill(sheet.id) } : {}),
    ticks: goblin.act_deadline - clock,
    total: sheet.activation,
    target: { tile: false, entity: goblin.act_target },
    area: shout(cw, at, { x, y }),
    interruptible,
  };
}

/** The adventurer, member 0 (§2, §3, §6.1). */
export function adventurerOf(cw: CombatWorld, names?: Names): CombatAdventurer {
  const member = cw.world.members[0]!;
  const clock = cw.world.clock;
  const { x, y } = memberPlace(member);
  const bar = barOf(member, cw.sheets, clock).map((slot) =>
    slot.skill && names
      ? { ...slot, skill: { ...slot.skill, name: names.skill(slot.skill.id) } }
      : slot,
  );
  const belt = beltOf(member, cw.sheets, clock).map((slot) =>
    slot.item !== null && names ? { ...slot, name: names.potion(slot.item) } : slot,
  );
  return {
    entity: 0,
    tile: { x, y },
    health: member.health,
    maxHealth: member.max_health,
    energy: Math.floor(member.energy / THIRDS),
    maxEnergy: Math.floor(member.max_energy / THIRDS),
    adrenaline: Math.floor(member.adrenaline / QUARTERS),
    adrenalineCap: Math.floor(member.adrenaline_cap / QUARTERS),
    bar,
    belt,
    activation: memberActivation(cw, member, names),
    chips: memberChips(member, cw.sheets, clock),
    knocked: knockedAt(member, clock),
  };
}

/** The goblins the world holds, alive or not (§5, §6.2). */
export function goblinsOf(
  cw: CombatWorld,
  ready: readonly number[],
  names?: Names,
): CombatGoblin[] {
  const clock = cw.world.clock;
  return cw.world.goblins.map((goblin) => {
    const { x, y } = goblinPlace(goblin);
    const caste = cw.sheets.castes[goblin.caste_at]!.id;
    return {
      entity: goblin.entity,
      caste,
      ...(names ? { casteName: names.caste(caste) } : {}),
      tile: { x, y },
      health: goblin.health,
      maxHealth: goblin.max_health,
      alive: goblin.ai < aiState.DEAD,
      mark: markOf(goblin.ai),
      activation: goblinActivation(cw, goblin, ready, names),
      recovering: goblin.act_slot === activation.RECOVERING && goblin.act_deadline > clock,
      chips: goblinChips(goblin, cw.sheets, clock),
      knocked: held(goblin.knocked, clock + 1),
    };
  });
}

/** The unused traps of the ground, a terrain one (kind 4) or a placed one (kind 9). */
export function trapsOf(ground: Ground): CombatTrap[] {
  const traps: CombatTrap[] = [];
  for (const [chunk, features] of ground) {
    for (const o of features.objects) {
      const trap = o.kind === groundObject.TRAP || o.kind === groundObject.PLACED_TRAP;
      if (!trap || o.state !== 0) continue;
      traps.push({
        tile: {
          x: (chunk % 15) * 15 + (o.tile % 15),
          y: Math.floor(chunk / 15) * 15 + Math.floor(o.tile / 15),
        },
        placed: o.kind === groundObject.PLACED_TRAP,
      });
    }
  }
  return traps;
}

/** The `CombatState` of a world client/sim loaded. */
export function stateOf(cw: CombatWorld, names?: Names): CombatState {
  const adventurer = adventurerOf(cw, names);
  const ready = adventurer.bar.filter((s) => s.state === "ready").map((s) => s.slot);
  return {
    clock: cw.world.clock,
    adventurer,
    goblins: goblinsOf(cw, ready, names),
    traps: trapsOf(cw.ground),
  };
}

/** The `CombatState` of the mirror's words, the content and the ground on the window's board. */
export function fromWords(
  words: MirrorWords,
  content: Content,
  ground: Ground,
  board: SegmentBoard,
  names?: Names,
): CombatState {
  return stateOf(readWorld(words, content, ground, board), names);
}
