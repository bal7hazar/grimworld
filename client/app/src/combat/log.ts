/**
 * The combat log (CLI-05 brief §7): one line per thing that happened, computed on the client from the
 * mirror, since neither client/sim nor the chain gives per-hit records (§7.2, Q-3).
 *
 * 1. **Per action, the difference of two states.** `SegmentTrait::run` plays each action and then its
 *    `n` ticks in the same loop turn (`client/sim/src/segment.ts`, `run`), so the state after action
 *    `k` is the end of a run on the batch's first `k` actions. `Prefixes` caches those runs, keyed by
 *    the base the batch runs on and its actions: appending an action adds one run; a new base, or an
 *    action removed or changed, empties the cache. Two prefixes' words compared give the action's
 *    lines: health, conditions, held effects, activations, kills, the defeat; their grounds, a trap
 *    placed or triggered.
 * 2. **Per tick, hits attributed by replay.** Each `TickLibrary::ticks` call an action made (recorded
 *    by `record.ts`) is replayed as `n` chained calls of client/sim's native `tickTicks` with `n = 1`.
 *    In each tick, an actor's health change less what step 3 gives it (its regeneration and its
 *    conditions, `degeneration` and `effect_pips`, through `heal`) is given to the goblin that acted
 *    in that tick (an activation resolved, an attack's recovery, a recharge set), with its arc
 *    (`arc`, from the positions before the tick). A change two goblins could have made, or none, is
 *    one joint line and a `grimworld.log-unattributed` record. A call whose one-tick replay does not
 *    give the recorded words and ground is a `grimworld.log-replay` record, and its ticks are not
 *    attributed (the replay is off for it until track game answers).
 * 3. A refusal before the batch (§4.4) is a line of its own, in a muted tone.
 *
 * `CombatLog` keeps the last 100 lines (§7.3), predicted until the chain confirms them.
 */

import {
  type Action,
  Arc,
  type Content,
  type Goblin,
  type Ground,
  type Member,
  type SegmentBoard,
  type Sheets,
  type TicksCall,
  type Words,
  NO_SLOT,
  activation,
  aiState,
  arc,
  beltItem,
  degeneration,
  effect_pips,
  goblinPlace,
  goblinRecharge,
  groundObject,
  heal,
  indexSheets,
  loadWorld,
  memberPlace,
  memberRecharge,
  position,
  reach,
  shapes,
  skillKind,
  tickTicks,
  writeGround,
  writeWords,
} from "@grimworld/sim";
import { activating } from "./bar";
import { areaOf } from "./targeting";
import { goblinChips, memberChips } from "./chips";
import type { RecordedRun, TicksRecord } from "./record";
import { refusalLine } from "./refusal";
import { type Chip, DEFAULT_NAMES, type Names } from "./state";

/** The lines the log keeps (§7.3). */
export const MAX_LINES = 100;

export interface LogLine {
  readonly text: string;
  /** A refusal before the batch is drawn muted. */
  readonly tone: "event" | "refusal";
  /** Predicted until the chain confirms it; struck when the chain differed. */
  readonly status: "predicted" | "confirmed" | "struck";
}

/** What the log reports to track game: an unattributed change, a replay that differs. */
export type LogRecord =
  | {
      readonly kind: "grimworld.log-unattributed";
      readonly call: TicksCall;
      /** The tick of the call, 1 to `n`. */
      readonly tick: number;
      readonly actor: number;
      readonly change: number;
      readonly goblins: readonly number[];
    }
  | {
      readonly kind: "grimworld.log-replay";
      readonly call: TicksCall;
      readonly replayed: { readonly words: Words; readonly ground: Ground };
      readonly recorded: { readonly words: Words; readonly ground: Ground };
    };

export type LogReport = (record: LogRecord) => void;

export const consoleLogReport: LogReport = (record) => console.warn(record.kind, record);

// ---- The prefix cache (§7.2 item 1).

const sameAction = (a: Action, b: Action): boolean => JSON.stringify(a) === JSON.stringify(b);

/**
 * The runs on a batch's prefixes: `runs[k]` the run on its first `k` actions (`runs[0]` the owed
 * ticks alone). Keyed by the base (by identity: a send, a reveal or a state read again is a new
 * base) and the actions: a new base, or an action removed or changed, empties it.
 */
export class Prefixes<Base> {
  private base: Base | undefined;
  private actions: Action[] = [];
  private runs: RecordedRun[] = [];
  /** The runs computed so far, for the cost of an input. */
  computed = 0;

  constructor(private readonly run: (base: Base, actions: readonly Action[]) => RecordedRun) {}

  /** The runs on every prefix of `actions` over `base`, the full run last. */
  at(base: Base, actions: readonly Action[]): readonly RecordedRun[] {
    const kept =
      this.base === base &&
      this.actions.length <= actions.length &&
      this.actions.every((a, k) => sameAction(a, actions[k]!));
    if (!kept) {
      this.base = base;
      this.actions = [];
      this.runs = [];
    }
    for (let k = this.runs.length; k <= actions.length; k++) {
      this.runs.push(this.run(base, actions.slice(0, k)));
      this.computed += 1;
    }
    this.actions = [...actions];
    return this.runs.slice(0, actions.length + 1);
  }

  /** How many prefixes are cached. */
  get size(): number {
    return this.runs.length;
  }
}

// ---- Naming.

const ORDINALS = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth"];

/** How the log names an actor: "you", or a goblin by its caste with a number among its kind. */
export function namer(
  members: readonly Member[],
  goblins: readonly Goblin[],
  sheets: Sheets,
  names: Names,
): (entity: number) => string {
  const living = goblins.filter((g) => g.ai < aiState.DEAD);
  return (entity) => {
    if (entity < members.length) return entity === 0 ? "you" : `member ${entity}`;
    const goblin = goblins.find((g) => g.entity === entity);
    if (goblin === undefined) return `goblin ${entity}`;
    const caste = sheets.castes[goblin.caste_at]!.id;
    const kin = living.filter((g) => g.caste_at === goblin.caste_at).map((g) => g.entity);
    const k = kin.indexOf(entity);
    const ordinal = kin.length > 1 && k >= 0 ? `${ORDINALS[k] ?? `#${k + 1}`} ` : "";
    return `the ${ordinal}${names.caste(caste)}`;
  };
}

const capital = (text: string): string => text.charAt(0).toUpperCase() + text.slice(1);
const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? "" : "s"}`;

/** The words of a hit's arc (§7.1): a critical from behind, a flank; nothing from the front. */
export function arcWords(a: Arc | undefined): string {
  if (a === Arc.Back) return ", from behind: critical";
  if (a === Arc.RearSide) return ", from the flank";
  return "";
}

const CONDITION_WORDS: Readonly<Record<string, string>> = {
  B: "bleeding",
  P: "poisoned",
  F: "burning",
  C: "crippled",
  K: "knocked down",
};

// ---- The per-action difference (§7.2 item 1).

/** A world decoded from words, the sheets beside it. */
interface Decoded {
  readonly words: Words;
  readonly members: Member[];
  readonly goblins: Goblin[];
}

const decode = (words: Words, sheets: Sheets): Decoded => {
  const world = loadWorld(words, sheets);
  return { words, members: world.members, goblins: world.goblins };
};

/** An actor's subject and verb forms: "You are" / "The runt is". */
const be = (who: string): string => (who === "you" ? "You are" : `${capital(who)} is`);
const has = (who: string): string => (who === "you" ? "You" : capital(who));

/** The lines of conditions and effects gained or ended between two chip lists of one actor. */
function chipLines(
  who: string,
  was: readonly Chip[],
  now: readonly Chip[],
  names: Names,
): string[] {
  const lines: string[] = [];
  const whose = who === "you" ? "" : `${capital(who)}: `;
  const key = (c: Chip) => `${c.kind}:${c.letter}:${c.source?.potion ?? ""}:${c.source?.id ?? ""}`;
  const before = new Map(was.map((c) => [key(c), c]));
  const after = new Map(now.map((c) => [key(c), c]));
  const carrier = (c: Chip) =>
    c.source === null
      ? c.name
      : c.source.potion
        ? names.potion(c.source.id)
        : names.skill(c.source.id);
  for (const [k, c] of after) {
    const old = before.get(k);
    if (old !== undefined) continue;
    if (c.kind === "condition") {
      lines.push(`${be(who)} ${CONDITION_WORDS[c.letter]} (${plural(c.ticks ?? 0, "tick")})`);
    } else {
      const parts = [
        ...(c.charges !== null ? [plural(c.charges, c.letter === "▣" ? "block" : "charge")] : []),
        ...(c.ticks !== null ? [plural(c.ticks, "tick")] : []),
      ];
      lines.push(`${whose}${carrier(c)}: ${parts.join(", ")}`);
    }
  }
  for (const [k, c] of before) {
    if (after.has(k)) continue;
    if (c.kind === "condition") lines.push(`${be(who)} no longer ${CONDITION_WORDS[c.letter]}`);
    else lines.push(`${whose}${carrier(c)} ended`);
  }
  return lines;
}

/** A health change in words: "The skirmisher lost 31 health", "You gained 12 health". */
const healthLine = (who: string, change: number): string =>
  `${has(who)} ${change < 0 ? "lost" : "gained"} ${Math.abs(change)} health`;

/** The adventurer's action in words, with a weapon hit's or an attack skill's arc (§7.1). */
function actionLine(
  action: Action,
  before: Decoded,
  sheets: Sheets,
  board: SegmentBoard,
  names: Names,
  name: (entity: number) => string,
): string | null {
  const member = before.members[0]!;
  const arcTo = (entity: number): string => {
    const goblin = before.goblins.find((g) => g.entity === entity);
    if (goblin === undefined) return "";
    const from = memberPlace(member);
    const to = goblinPlace(goblin);
    return arcWords(arc(position(board, from.x, from.y), position(board, to.x, to.y), to.facing));
  };
  switch (action.kind) {
    case "wait":
      return "You waited";
    case "attack":
      return `You attacked ${name(action.entity)}${arcTo(action.entity)}`;
    case "skill": {
      const at = member.bar_at[action.slot]!;
      const sheet = sheets.skills[at];
      if (sheet === undefined) return null;
      const skill = names.skill(sheet.id);
      if (action.target.tile) return `You used ${skill}`;
      if (action.target.value === 0) return `You used ${skill} on yourself`;
      const attack = sheet.kind === skillKind.ATTACK ? arcTo(action.target.value) : "";
      return `You used ${skill} on ${name(action.target.value)}${attack}`;
    }
    case "item": {
      const potion = names.potion(beltItem(member, action.slot));
      return action.entity === 0
        ? `You drank a ${potion}`
        : `You used a ${potion} on ${name(action.entity)}`;
    }
    default:
      return null;
  }
}

/** An activation's state at a clock: its skill id and deadline, or none. */
function goblinAct(
  g: Goblin,
  sheets: Sheets,
  clock: number,
): { skill: number; deadline: number } | null {
  if (g.act_slot > activation.LAST_SLOT || g.act_deadline <= clock) return null;
  const at = sheets.kits[g.caste_at]!.skills[g.act_slot]!;
  return { skill: sheets.skills[at]?.id ?? 0, deadline: g.act_deadline };
}

function memberAct(
  m: Member,
  sheets: Sheets,
  clock: number,
): { skill: number; deadline: number } | null {
  if (!activating(m, clock)) return null;
  return { skill: sheets.skills[m.bar_at[m.act_slot]!]?.id ?? 0, deadline: m.act_deadline };
}

/** The activation lines of one actor between two states (§7.1). */
function activationLines(
  who: string,
  was: { skill: number; deadline: number } | null,
  now: { skill: number; deadline: number } | null,
  clock: number,
  names: Names,
): string[] {
  const lines: string[] = [];
  const you = who === "you";
  if (was !== null && (now === null || now.deadline !== was.deadline)) {
    const skill = names.skill(was.skill);
    if (clock >= was.deadline)
      lines.push(you ? `You finish ${skill}` : `${capital(who)} finishes ${skill}`);
    else lines.push(you ? `Your ${skill} was interrupted` : `You interrupted ${who}`);
  }
  if (now !== null && (was === null || now.deadline !== was.deadline)) {
    const skill = names.skill(now.skill);
    const ticks = plural(now.deadline - clock, "tick");
    lines.push(
      you ? `You start ${skill} (${ticks})` : `${capital(who)} starts ${skill} (${ticks})`,
    );
  }
  return lines;
}

/** The unused traps of a ground, as `chunk:tile` keys, and the used ones. */
function trapKeys(ground: Ground): { unused: Set<string>; used: Set<string> } {
  const unused = new Set<string>();
  const used = new Set<string>();
  for (const [chunk, features] of ground) {
    for (const o of features.objects) {
      if (o.kind !== groundObject.TRAP && o.kind !== groundObject.PLACED_TRAP) continue;
      (o.state === 0 ? unused : used).add(`${chunk}:${o.tile}:${o.kind}`);
    }
  }
  return { unused, used };
}

/** The lines of the difference between the states before and after one action (§7.2 item 1). */
export function differenceLines(
  before: Decoded,
  after: Decoded,
  groundBefore: Ground,
  groundAfter: Ground,
  sheets: Sheets,
  names: Names,
): string[] {
  const lines: string[] = [];
  const name = namer(before.members, before.goblins, sheets, names);
  const [c0, c1] = [before.words.clock, after.words.clock];
  after.members.forEach((m, i) => {
    const was = before.members[i];
    if (was === undefined) return;
    const who = name(i);
    if (m.health !== was.health) lines.push(healthLine(who, m.health - was.health));
    lines.push(...chipLines(who, memberChips(was, sheets, c0), memberChips(m, sheets, c1), names));
    lines.push(
      ...activationLines(who, memberAct(was, sheets, c0), memberAct(m, sheets, c1), c1, names),
    );
  });
  for (const g of after.goblins) {
    const was = before.goblins.find((b) => b.entity === g.entity);
    if (was === undefined) continue;
    const who = name(g.entity);
    if (g.health !== was.health) lines.push(healthLine(who, g.health - was.health));
    lines.push(...chipLines(who, goblinChips(was, sheets, c0), goblinChips(g, sheets, c1), names));
    lines.push(
      ...activationLines(who, goblinAct(was, sheets, c0), goblinAct(g, sheets, c1), c1, names),
    );
  }
  const killed = after.words.killed.filter((e) => !before.words.killed.includes(e));
  for (const entity of killed) lines.push(`${capital(name(entity))} is killed`);
  const [t0, t1] = [trapKeys(groundBefore), trapKeys(groundAfter)];
  for (const k of t1.unused) if (!t0.unused.has(k)) lines.push("A trap was placed");
  for (const k of t1.used) if (t0.unused.has(k)) lines.push("A trap was triggered");
  if (after.words.defeated && !before.words.defeated) lines.push("You are defeated");
  return lines;
}

// ---- The one-tick replay and its attribution (§7.2 item 2).

const feltsEqual = (a: readonly bigint[], b: readonly bigint[]): boolean =>
  a.length === b.length && a.every((felt, i) => felt === b[i]);

/** `n` chained calls of `tickTicks` with `n = 1`: each tick's state, the call's input first. */
export function replayTicks(call: TicksCall): { words: Words; ground: Ground }[] {
  const states = [{ words: call.words, ground: call.ground }];
  for (let k = 0; k < call.n; k++) {
    const last = states[states.length - 1]!;
    states.push(tickTicks({ ...call, words: last.words, ground: last.ground, n: 1 }));
  }
  return states;
}

/** Whether a replay ends on the recorded output, felt for felt. */
export function replayAgrees(
  replayed: { words: Words; ground: Ground },
  recorded: { words: Words; ground: Ground },
): boolean {
  return (
    feltsEqual(writeWords(replayed.words), writeWords(recorded.words)) &&
    feltsEqual(writeGround(replayed.ground), writeGround(recorded.ground))
  );
}

/**
 * The health step 3 left on an actor whose health went from `before` to `after` in one tick with
 * `pips` of regeneration and conditions: `heal` read backwards. At a bound (`after` at max or at 0)
 * the change is taken as small as `before` allows: no hit is assumed there.
 */
export function beforeRegeneration(
  before: number,
  after: number,
  pips: number,
  max: number,
): number {
  const change = 2 * Math.min(10, Math.max(-10, pips));
  if (change >= 0) {
    if (after < max) return after - change;
    return before >= max - change ? Math.min(before, max) : max - change;
  }
  if (after > 0) return after - change;
  return before <= -change ? before : -change;
}

/**
 * The goblins that may have struck or healed `actor` in the tick that went from `before` to `after`
 * (§7.2): one whose activation resolved in the tick on that actor (or with an area); one that used
 * an instant caste skill (a recharge set); and one free in step 2 (awake, alive, no activation, not
 * knocked down) that neither moved nor started an activation and holds the actor, a member, in its
 * weapon's reach. The last is the brief's "attack (its recovery or recharge set)" widened: a weapon of tick
 * cost 1 sets no recovery (`GoblinTickTrait::recover` needs `k > 1`) and no recharge, so a goblin's
 * plain attack leaves no mark on its words.
 */
function strikers(
  before: Decoded,
  after: Decoded,
  sheets: Sheets,
  board: SegmentBoard,
  actor: { entity: number; at: { x: number; y: number } },
): number[] {
  const t = after.words.clock;
  const to = position(board, actor.at.x, actor.at.y);
  const out: number[] = [];
  for (const g of after.goblins) {
    const was = before.goblins.find((b) => b.entity === g.entity);
    if (was === undefined || !g.awake || was.ai >= aiState.DEAD) continue;
    if (was.act_slot <= activation.LAST_SLOT && was.act_deadline === t) {
      const at = sheets.kits[was.caste_at]!.skills[was.act_slot]!;
      const area = [0, 1, 2].some((k) => (sheets.entries[3 * at + k]?.shape ?? 0) > shapes.SINGLE);
      if (was.act_target === actor.entity || area) out.push(g.entity);
      continue;
    }
    if ([0, 1, 2, 3].some((s) => goblinRecharge(was, s) !== goblinRecharge(g, s))) {
      out.push(g.entity);
      continue;
    }
    // A goblin's weapon strikes a member only (no friendly fire, design/19 §2.3)
    if (actor.entity >= after.members.length) continue;
    const free = was.act_slot === activation.NONE && was.knocked < t;
    const [p0, p1] = [goblinPlace(was), goblinPlace(g)];
    const stayed = p0.x === p1.x && p0.y === p1.y;
    const started = g.act_slot <= activation.LAST_SLOT;
    const from = position(board, p0.x, p0.y);
    const range = sheets.castes[was.caste_at]!.weapon_range;
    if (
      free &&
      stayed &&
      !started &&
      from < 240 &&
      to < 240 &&
      reach(board.open, from, to, range)
    ) {
      out.push(g.entity);
    }
  }
  return out;
}

/** Whether a trap was triggered between two grounds (an unused trap now used). */
function triggered(before: Ground, after: Ground): boolean {
  const [t0, t1] = [trapKeys(before), trapKeys(after)];
  return [...t1.used].some((k) => t0.unused.has(k));
}

/**
 * The lines of one tick's hits, attributed (§7.2 item 2). An actor's health change less what step 3
 * gives it is a hit; one step 3 explains alone (its regeneration, its conditions) is none. The hit
 * goes to the one candidate: a goblin of `strikers`, the adventurer's activation resolved in the tick
 * when its area takes the actor, a trap triggered in the tick. Several candidates, or none, give one
 * joint line and a `grimworld.log-unattributed` record.
 */
export function tickLines(
  call: TicksCall,
  tick: number,
  before: Decoded,
  after: Decoded,
  groundBefore: Ground,
  groundAfter: Ground,
  sheets: Sheets,
  names: Names,
  report: LogReport,
): string[] {
  const lines: string[] = [];
  const t = after.words.clock;
  const board = call.board;
  const name = namer(before.members, before.goblins, sheets, names);
  const actors: {
    entity: number;
    was: number;
    now: number;
    pips: number;
    max: number;
    regen: boolean;
    at: { x: number; y: number; facing: number };
  }[] = [];
  after.members.forEach((m, i) => {
    const was = before.members[i];
    if (was === undefined) return;
    let pips = m.health_regen + degeneration(m.bleeding, m.poison, m.burning, t);
    m.effect_regen.forEach((regen, s) => (pips += effect_pips(regen, m.effect_deadlines[s]!, t)));
    const regen = was.status === 0 && was.health > 0;
    actors.push({
      entity: i,
      was: was.health,
      now: m.health,
      pips,
      max: m.max_health,
      regen,
      at: memberPlace(was),
    });
  });
  for (const g of after.goblins) {
    const was = before.goblins.find((b) => b.entity === g.entity);
    if (was === undefined) continue;
    const pips =
      sheets.castes[g.caste_at]!.health_regen -
      10 +
      degeneration(g.bleeding, g.poison, g.burning, t) +
      effect_pips(g.effect_regen, g.effect_deadline, t);
    const regen = g.awake && was.ai < aiState.DEAD;
    actors.push({
      entity: g.entity,
      was: was.health,
      now: g.health,
      pips,
      max: g.max_health,
      regen,
      at: goblinPlace(was),
    });
  }
  const self = before.members[0]!;
  const resolved = self.act_slot !== NO_SLOT && self.act_deadline === t;
  const trapped = triggered(groundBefore, groundAfter);
  const cw = {
    world: { ...before, clock: before.words.clock, killed: [], defeated: false },
    sheets,
    board,
    ground: groundBefore,
  };
  const yours = (entity: number): boolean => {
    if (!resolved) return false;
    const centre =
      self.act_tile === 1
        ? { x: self.act_target % 256, y: Math.floor(self.act_target / 256) }
        : entity === self.act_target
          ? actors.find((a) => a.entity === entity)!.at
          : (actors.find((a) => a.entity === self.act_target)?.at ?? memberPlace(self));
    return areaOf(cw, { kind: "skill", slot: self.act_slot }, centre).marked.includes(entity);
  };
  for (const a of actors) {
    if (a.was === a.now) continue;
    // Step 3 alone explains it: no hit
    if (a.regen && heal(a.was, a.pips, a.max) === a.now) continue;
    let mid = a.regen ? beforeRegeneration(a.was, a.now, a.pips, a.max) : a.now;
    // Step 3 did not run (the tick stopped at a member down): the change is the hit's
    if (a.regen && heal(mid, a.pips, a.max) !== a.now) mid = a.now;
    const hit = mid - a.was;
    if (hit === 0) continue;
    const who = name(a.entity);
    const goblins = strikers(before, after, sheets, board, a);
    const mine = yours(a.entity);
    const count =
      goblins.length + (mine ? 1 : 0) + (trapped && goblins.length === 0 && !mine ? 1 : 0);
    const amount = hit < 0 ? `${-hit} damage` : `${hit} health`;
    if (count === 1 && goblins.length === 1) {
      const g = before.goblins.find((b) => b.entity === goblins[0])!;
      const from = goblinPlace(g);
      const by = capital(name(g.entity));
      const side = arcWords(
        arc(position(board, from.x, from.y), position(board, a.at.x, a.at.y), a.at.facing),
      );
      lines.push(
        hit < 0 ? `${by} struck ${who}: ${amount}${side}` : `${by} healed ${who} for ${hit}`,
      );
      continue;
    }
    if (count === 1 && mine) {
      const skill = names.skill(sheets.skills[self.bar_at[self.act_slot]!]?.id ?? 0);
      lines.push(
        hit < 0 ? `Your ${skill} hit ${who}: ${amount}` : `Your ${skill} healed ${who} for ${hit}`,
      );
      continue;
    }
    if (count === 1 && trapped) {
      lines.push(
        hit < 0 ? `A trap struck ${who}: ${amount}` : `${capital(has(who))} gained ${hit} health`,
      );
      continue;
    }
    const together = [...goblins.map(name), ...(mine ? ["you"] : [])];
    const subject = together.length > 0 ? capital(together.join(" and ")) : "Something";
    lines.push(
      hit < 0 ? `${subject} struck ${who}: ${amount}` : `${subject} healed ${who} for ${hit}`,
    );
    report({
      kind: "grimworld.log-unattributed",
      call,
      tick,
      actor: a.entity,
      change: hit,
      goblins,
    });
  }
  return lines;
}

/** The hit lines of an action's tick calls, each replayed one tick at a time. */
export function replayLines(
  records: readonly TicksRecord[],
  sheets: Sheets,
  names: Names,
  report: LogReport,
): string[] {
  const lines: string[] = [];
  for (const { call, out } of records) {
    const states = replayTicks(call);
    const last = states[states.length - 1]!;
    if (!replayAgrees(last, out)) {
      report({ kind: "grimworld.log-replay", call, replayed: last, recorded: out });
      continue;
    }
    for (let k = 1; k < states.length; k++) {
      const before = decode(states[k - 1]!.words, sheets);
      const after = decode(states[k]!.words, sheets);
      lines.push(
        ...tickLines(
          call,
          k,
          before,
          after,
          states[k - 1]!.ground,
          states[k]!.ground,
          sheets,
          names,
          report,
        ),
      );
    }
  }
  return lines;
}

// ---- A batch's lines.

/** What a batch's lines are computed from: its base words and ground, content, board, actions. */
export interface Batch {
  readonly words: Words;
  readonly ground: Ground;
  readonly content: Content;
  readonly board: SegmentBoard;
  readonly actions: readonly Action[];
}

export interface LinesOptions {
  readonly names?: Names;
  readonly report?: LogReport;
  /** The one-tick replay's hit lines; off, an action has its difference lines only (§7.2). */
  readonly replay?: boolean;
  /** The first action (1-based) to give lines of: an input needs only the new action's. */
  readonly from?: number;
}

/**
 * The lines of each action of a batch, from the runs on its prefixes (`Prefixes.at`): the action in
 * words, its ticks' hits (the replay), then the difference of the two states; the action that
 * stopped the batch on a refusal, its refusal line. Actions the batch did not reach have none.
 * The list starts at action `from`.
 */
export function batchLines(
  batch: Batch,
  runs: readonly RecordedRun[],
  options: LinesOptions = {},
): LogLine[][] {
  const { names = DEFAULT_NAMES, report = consoleLogReport, replay = true, from = 1 } = options;
  const sheets = indexSheets(batch.content);
  const last = runs[runs.length - 1]!;
  const out: LogLine[][] = [];
  const event = (text: string): LogLine => ({ text, tone: "event", status: "predicted" });
  for (let k = from; k <= batch.actions.length; k++) {
    const action = batch.actions[k - 1]!;
    if (k > last.done.played) {
      const refused =
        k === last.done.played + 1 && last.done.illegal !== undefined
          ? refusalLine(last.done.illegal, rechargeLeft(runs[k - 1], action, sheets))
          : null;
      out.push(refused === null ? [] : [{ text: refused, tone: "refusal", status: "predicted" }]);
      continue;
    }
    const was = runs[k - 1]!;
    const now = runs[k]!;
    const before = decode(was.words, sheets);
    const after = decode(now.words, sheets);
    const name = namer(before.members, before.goblins, sheets, names);
    const lines: string[] = [];
    const said = actionLine(action, before, sheets, batch.board, names, name);
    if (said !== null) lines.push(said);
    if (replay)
      lines.push(...replayLines(now.ticks.slice(was.ticks.length), sheets, names, report));
    lines.push(...differenceLines(before, after, was.ground, now.ground, sheets, names));
    out.push(lines.map(event));
  }
  return out;
}

/** A skill action's recharge ticks left on the state it met, for its refusal line. */
function rechargeLeft(
  run: RecordedRun | undefined,
  action: Action,
  sheets: Sheets,
): number | undefined {
  if (run === undefined || action.kind !== "skill") return undefined;
  const member = loadWorld(run.words, sheets).members[0]!;
  const left = memberRecharge(member, action.slot) - run.words.clock;
  return left > 0 ? left : undefined;
}

// ---- The log (§7.3).

/** The instance's log: its last 100 lines, lost on a reload, cleared on a new instance. */
export class CombatLog {
  private kept: LogLine[] = [];

  get lines(): readonly LogLine[] {
    return this.kept;
  }

  /** Lines added, newest last; past 100 the oldest are dropped. */
  add(lines: readonly LogLine[]): void {
    this.kept = [...this.kept, ...lines].slice(-MAX_LINES);
  }

  /** A refusal before the batch (§4.4), muted. */
  refuse(text: string): void {
    this.add([{ text, tone: "refusal", status: "predicted" }]);
  }

  /** The chain played the predicted lines: confirmed. */
  confirm(): void {
    this.kept = this.kept.map((l) =>
      l.status === "predicted" ? { ...l, status: "confirmed" } : l,
    );
  }

  /** The chain differed: the predicted lines are struck and one line says so (design/11). */
  correct(): void {
    this.kept = this.kept.map((l) => (l.status === "predicted" ? { ...l, status: "struck" } : l));
    this.add([{ text: "The world corrected itself", tone: "event", status: "confirmed" }]);
  }

  /** A new instance. */
  clear(): void {
    this.kept = [];
  }
}
