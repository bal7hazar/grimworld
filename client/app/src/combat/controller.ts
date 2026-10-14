/**
 * The combat screen's input (CLI-05 brief §2.4, §3, §4.1): arming a bar or belt slot by a tap or
 * its key, the second tap that plays a skill addressed to the adventurer, a target chosen on the
 * map or cycled by `F` and played by `Enter`, a `TILE` skill's first tap that previews and second
 * that plays, the inspection of a slot, and `Esc`. It decides no rule: what a slot reaches and
 * which actors it may take come from `CombatRules.aim` (the sandbox's placeholders; client/sim's
 * `targeting.ts` on chain), and what playing changes from `CombatRules.play`. Pure state and
 * listeners, so it is tested with fakes.
 */

import { type LogLine, MAX_LINES } from "./log";
import type { OverlayAim } from "./overlay";
import { beltLine, refusalLine, slotLine } from "./refusal";
import type { Addressing, Armed, BarSlot, BeltSlot, CombatState } from "./state";
import type { Tile } from "../render/view";
import { Illegal } from "@grimworld/sim";

/** What an armed slot shows and takes: the overlay's aim, its addressing, its targets nearest first. */
export interface CombatAim extends OverlayAim {
  readonly addressing: Addressing;
}

/** An action's target: an actor's entity, or a tile (`Target.tile`). */
export type CombatTarget =
  { readonly tile: false; readonly entity: number } | { readonly tile: true; readonly at: Tile };

export interface CombatRules {
  /** The armed slot's aim on `state`; null when it cannot say (the map is not mounted yet). */
  aim(state: CombatState, armed: Armed): CombatAim | null;
  /** The state once the armed slot is played on `target`. */
  play(state: CombatState, armed: Armed, target: CombatTarget): CombatState;
}

/** What the screen draws of the controller. */
export interface CombatView {
  readonly state: CombatState;
  readonly armed: Armed | null;
  /** The armed slot's aim, null when nothing is armed (or the rules cannot say yet). */
  readonly aim: CombatAim | null;
  /** The target `F` cycled to, its entity: `Enter` plays on it. */
  readonly focus: number | null;
  /** A `TILE` slot's previewed tile: a second tap on it plays. */
  readonly preview: Tile | null;
  /** The slot a long press inspects. */
  readonly inspected: Armed | null;
  /** The one line the last tap said ("Recharging: 3 ticks."), or "". */
  readonly said: string;
  /** The log's lines, newest last (§7.3: the last 100). */
  readonly log: readonly LogLine[];
}

/** No aim: the rules are not given yet. */
const NO_RULES: CombatRules = { aim: () => null, play: (state) => state };

const sameArmed = (a: Armed | null, b: Armed | null): boolean =>
  a !== null && b !== null && a.kind === b.kind && a.slot === b.slot;

const sameTile = (a: Tile | null, b: Tile): boolean => a !== null && a.x === b.x && a.y === b.y;

const plural = (n: number, word: string): string => `${n} ${word}${n === 1 ? "" : "s"}`;

/** Bar or belt slot `armed` of `state`. */
export function slotOf(state: CombatState, armed: Armed): BarSlot | BeltSlot | undefined {
  const { adventurer } = state;
  return armed.kind === "skill" ? adventurer.bar[armed.slot] : adventurer.belt[armed.slot];
}

/** Whether a slot can be armed: a ready skill, a potion with some left (§2.2, §3). */
export function armable(slot: BarSlot | BeltSlot | undefined): boolean {
  if (!slot) return false;
  return "skill" in slot ? slot.state === "ready" : slot.state === "some";
}

/** The one line a tap on slot `armed` says when it cannot be armed; "" for an empty slot. */
export function notReadyLine(state: CombatState, armed: Armed): string {
  const slot = slotOf(state, armed);
  if (!slot) return "";
  const knocked = state.adventurer.knocked;
  return ("skill" in slot ? slotLine(slot, knocked) : beltLine(slot, knocked)) ?? "";
}

/** The name of the actor `entity`: "you", "the hobgoblin" (its caste), or "#12". */
export function actorName(state: CombatState, entity: number): string {
  if (entity === state.adventurer.entity) return "you";
  const goblin = state.goblins.find((g) => g.entity === entity);
  return goblin ? `the ${goblin.casteName ?? "goblin"}` : `#${entity}`;
}

/** The log's line for playing `armed` on `target` (§7.1): "You used Cleave on the runt". */
export function playedLine(state: CombatState, armed: Armed, target: CombatTarget): string {
  const self = !target.tile && target.entity === state.adventurer.entity;
  const on = target.tile
    ? ` on (${target.at.x}, ${target.at.y})`
    : self
      ? ""
      : ` on ${actorName(state, target.entity)}`;
  if (armed.kind === "item") {
    const name = state.adventurer.belt[armed.slot]?.name ?? "a potion";
    return self ? `You drank a ${name}` : `You threw a ${name}${on}`;
  }
  const skill = state.adventurer.bar[armed.slot]?.skill;
  return `You used ${skill?.name ?? "a skill"}${on}`;
}

/**
 * The combat screen's controller: one per fight. The screen calls an input, then reads `view()`;
 * a listener hears every change.
 */
export class CombatController {
  private current: CombatView;
  private rules: CombatRules = NO_RULES;
  private readonly listeners = new Set<() => void>();

  constructor(state: CombatState, lines: readonly LogLine[] = []) {
    this.current = {
      state,
      armed: null,
      aim: null,
      focus: null,
      preview: null,
      inspected: null,
      said: "",
      log: lines.slice(-MAX_LINES),
    };
  }

  /** The rules, once the map can answer them (the sandbox's placeholders need its terrain). */
  setRules(rules: CombatRules): void {
    this.rules = rules;
    this.update({
      aim: this.current.armed ? rules.aim(this.current.state, this.current.armed) : null,
    });
  }

  view = (): CombatView => this.current;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  /** The adventurer stood elsewhere (a walk in the sandbox): the aim follows. */
  moved(tile: Tile): void {
    const { state } = this.current;
    const at = state.adventurer.tile;
    if (at.x === tile.x && at.y === tile.y) return;
    const next = { ...state, adventurer: { ...state.adventurer, tile } };
    const armed = this.current.armed;
    this.update({ state: next, aim: armed ? this.rules.aim(next, armed) : null, preview: null });
  }

  /**
   * A tap on a slot, or its key (§2.4, §3): an empty slot does nothing and says nothing; a slot
   * not ready says its line and arms nothing; a ready one is armed; the armed one again plays a
   * skill or potion addressed to the adventurer (or to an ally while alone), and disarms any other.
   */
  slot(armed: Armed): void {
    const { state } = this.current;
    const slot = slotOf(state, armed);
    const empty = !slot || ("skill" in slot ? slot.skill === null : slot.item === null);
    if (empty) return;
    if (!armable(slot)) {
      this.update({ said: notReadyLine(state, armed) });
      return;
    }
    if (sameArmed(this.current.armed, armed)) {
      if (this.selfPlayed()) this.play({ tile: false, entity: state.adventurer.entity });
      else this.disarm();
      return;
    }
    this.update({
      armed,
      aim: this.rules.aim(state, armed),
      focus: null,
      preview: null,
      inspected: null,
      said: "",
    });
  }

  /** A long press or a right click on a slot: its inspection (§2.4); the same slot again closes it. */
  inspect(armed: Armed): void {
    const slot = slotOf(this.current.state, armed);
    const empty = !slot || ("skill" in slot ? slot.skill === null : slot.item === null);
    if (empty) return;
    this.update({ inspected: sameArmed(this.current.inspected, armed) ? null : armed });
  }

  /**
   * A tap on an actor while a slot is armed (§4.1): a marked one is the target; any other says
   * why. True when the tap was the controller's (always, while armed).
   */
  actor(entity: number): boolean {
    const { armed, aim, state } = this.current;
    if (!armed) return false;
    if (aim?.marked.includes(entity)) {
      this.play({ tile: false, entity });
      return true;
    }
    const addressed = aim?.addressing;
    const foe = state.goblins.some((g) => g.entity === entity);
    const reach = (addressed === "foe" && foe) || (addressed === "ally" && !foe);
    this.update({ said: refusalLine(reach ? Illegal.Reach : Illegal.Target) ?? "" });
    return true;
  }

  /**
   * A tap on a tile (any tile, for a `TILE` aim) while a slot is armed: a `TILE` slot previews a tile in reach and
   * plays on a second tap on it; any other slot is disarmed, the tap going nowhere (§4.1).
   */
  tile(tile: Tile): boolean {
    const { armed, aim } = this.current;
    if (!armed) return false;
    if (aim?.addressing !== "tile") {
      this.disarm();
      return true;
    }
    if (!aim.reach.some((t) => sameTile(t, tile))) {
      this.update({ said: refusalLine(Illegal.Reach) ?? "", preview: null });
      return true;
    }
    if (sameTile(this.current.preview, tile)) this.play({ tile: true, at: tile });
    else this.update({ preview: tile, said: "" });
    return true;
  }

  /** `F` / `Shift+F` while armed: the marked targets in turn, nearest first (§4.1). */
  cycle(by: 1 | -1): boolean {
    const { armed, aim, focus } = this.current;
    if (!armed || !aim || aim.marked.length === 0) return false;
    const n = aim.marked.length;
    const at = focus === null ? -1 : aim.marked.indexOf(focus);
    const next = at < 0 ? (by > 0 ? 0 : n - 1) : (at + by + n) % n;
    this.update({ focus: aim.marked[next]!, said: "" });
    return true;
  }

  /** `Enter` while armed: plays on the cycled target. */
  go(): boolean {
    const { armed, focus, aim } = this.current;
    if (!armed || focus === null || !aim?.marked.includes(focus)) return false;
    this.play({ tile: false, entity: focus });
    return true;
  }

  /**
   * `Esc` (§4.1's order, after the key help and the confirmation, which hold their own key):
   * an inspection, then an armed slot. False when it had neither: the walk, then the selection.
   */
  escape(): boolean {
    if (this.current.inspected) {
      this.update({ inspected: null });
      return true;
    }
    if (this.current.armed) {
      this.disarm();
      return true;
    }
    return false;
  }

  /** A line in the log that plays nothing (the sandbox's Wait). */
  note(text: string): void {
    this.update({ log: this.lines(text) });
  }

  private selfPlayed(): boolean {
    const { aim, state } = this.current;
    const self = state.adventurer.entity;
    // Alone, an ally is the adventurer: the slot twice plays on them (§4.1, §3).
    return (
      aim !== null &&
      (aim.addressing === "self" ||
        (aim.addressing === "ally" && aim.marked.length === 1 && aim.marked[0] === self))
    );
  }

  private play(target: CombatTarget): void {
    const { state, armed } = this.current;
    if (!armed) return;
    const line = playedLine(state, armed, target);
    this.update({
      state: this.rules.play(state, armed, target),
      armed: null,
      aim: null,
      focus: null,
      preview: null,
      said: "",
      log: this.lines(line),
    });
  }

  private disarm(): void {
    this.update({ armed: null, aim: null, focus: null, preview: null, said: "" });
  }

  private lines(text: string): LogLine[] {
    return [
      ...this.current.log,
      { text, tone: "event" as const, status: "predicted" as const },
    ].slice(-MAX_LINES);
  }

  private update(patch: Partial<CombatView>): void {
    this.current = { ...this.current, ...patch };
    for (const listener of this.listeners) listener();
  }
}

/** A recharge's or an activation's ticks in words, for the inspection and the lines. */
export const ticksText = (n: number): string => plural(n, "tick");

const line = (text: string, status: LogLine["status"] = "confirmed"): LogLine => ({
  text,
  tone: "event",
  status,
});

/**
 * The sandbox fight's log (CLI-05 brief §9, `?combat=`): fixed lines in §7.1's words, written by
 * hand as the fixture is (nothing computed), the last ones predicted and one refusal, so that each
 * tone is seen. CLI-11d's log on chain computes its lines (§7.2).
 */
export const FIGHT_LINES: readonly LogLine[] = [
  line("You used Cleave on the runt, from the flank"),
  line("The runt lost 38 health"),
  line("The skirmisher struck you from behind: critical"),
  line("You lost 26 health"),
  line("You are bleeding (5 ticks)"),
  line("You drank a Regeneration potion"),
  line("Regeneration: +2 a tick (6 ticks)"),
  line("The skirmisher is poisoned (6 ticks)"),
  line("The hobgoblin struck you"),
  line("You lost 16 health"),
  line("You used Shield bash", "predicted"),
  line("Block: 2 blocks", "predicted"),
  line("The hobgoblin starts Overhead Smash on you (3 ticks)", "predicted"),
  line("The shaman starts Mend Kin on the runt (2 ticks)", "predicted"),
  { text: "Not enough energy.", tone: "refusal", status: "predicted" },
];
