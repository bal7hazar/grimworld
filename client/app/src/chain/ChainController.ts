import { Illegal, NotMirrored, segmentBoard } from "@grimworld/sim";
import { CombatController, type CombatTarget, type CombatView } from "../combat/controller";
import { stateOf } from "../combat/fromWords";
import {
  type LogLine,
  CombatLog,
  MAX_LINES,
  Prefixes,
  batchLines,
  consoleLogReport,
  refusal,
} from "../combat/log";
import { NAMES } from "../combat/names";
import { runRecorded } from "../combat/record";
import { NOT_AVAILABLE_YET, UNREACHABLE, refusalLine } from "../combat/refusal";
import type { Armed } from "../combat/state";
import { type CombatWorld, aiming, tileValue } from "../combat/targeting";
import type { PlayAction } from "../preview/actions";
import type { Intent } from "../input/intent";
import { type MirrorState, mirrorOf, nativeClasses, segmentOf } from "../preview/mirror";
import type { Predict } from "../preview/reconcile";
import type { Facing, Tile } from "../render/view";
import { directionBetween, planPath, tileToward } from "../sandbox/wiring";
import { tileKey } from "../render/fog";
import { kindAt } from "../sandbox/world";
import { actionsOf } from "./batch";
import type { ChainState } from "./send";
import type { Stages, StagesState } from "./stages";
import { chainWorld, combatWorldOf, memberPlace, objectAt } from "./world";
import type { SandboxWorld } from "../sandbox/world";

/**
 * The chain mode's inputs (CLI-11 §4.1): what a tap, a step key, `Space`, `R` then a step key,
 * `B` and `N` do to the batch. It holds no drawing and no timer: every input becomes `PlayAction`s
 * put into `Stages` (which counts the batch's room and its ends as the contract does), or one of
 * its two other effects, `send` and `enter`. The path of a tap is the sandbox wiring's, planned on
 * the world the chain state draws; the planner follows the batch's own moves geometrically, tile
 * after tile, and never decides legality: the preview says how far the batch plays.
 *
 * A tap on a goblin selects it (the sandbox's own first tap, which the screen lets through to the
 * map); a second tap on the selected goblin attacks it. A floor tile far away plans a path (its
 * steps are marked, dropped after a send); an adjacent one, and a step key, is one move.
 *
 * The combat screen (CLI-11d, CLI-05 brief §4.4, §7.2): the bar, the belt and the targeting read the
 * mirror's state after the batch planned so far (`combatWorldOf`, `fromWords`), through a
 * `CombatController` made again at each change of the batch. Playing a slot is one `skill` or `item`
 * action, put into the batch only when the mirror, run on the planned actions plus the new one,
 * does not stop at it: a refusal is one line, the slot stays armed and the batch is unchanged. A
 * tap on a gate, a chest or a lever says it is not available yet and adds nothing. The log's lines
 * are the client's (§7.2), predicted until the sent batch confirms or strikes them.
 */

export interface ControllerDeps {
  readonly stages: Stages;
  /** The combat world of a stages state; `combatWorldOf` on the mirror's prediction by default. */
  readonly combatWorld?: (state: StagesState) => CombatWorld | undefined;
  /** The mirror's run of a chain state, for §4.4's check; `mirrorOf` by default. */
  readonly run?: (chain: ChainState) => Predict;
  /** The log's predicted lines of each action of a batch (§7.2); computed from the mirror by default. */
  readonly lines?: (base: MirrorState, actions: readonly PlayAction[]) => LogLine[][];
  /**
   * `N` (§3.4): enters again with the same adventurer once the instance closed, and reads the new
   * state. Rejections are shown in the panel's line.
   */
  readonly enter: () => Promise<ChainState>;
}

export interface ControllerState {
  /** `R` was pressed: the next step key turns. */
  readonly turning: boolean;
  /** The goblin the first tap selected, by entity. */
  readonly selected: number | null;
  /** `N` is running. */
  readonly entering: boolean;
  /** One line for the panel: an input that did nothing, a failed `N`. */
  readonly note: string | undefined;
}

export type Tap =
  /** A goblin selected: the map shows its arcs (the screen lets the tap through). */
  | { readonly kind: "select"; readonly entity: number }
  | { readonly kind: "attack"; readonly entity: number }
  | { readonly kind: "moves"; readonly count: number }
  /** Nothing: the tile is the adventurer's own, not floor, not reachable, or no input is taken. */
  | { readonly kind: "none" };

export const notes = {
  /** `L` and the Fate actions: not in part 1 (§4.1). */
  UNBOUND: "not in the chain mode yet",
  NOT_CLOSED: "the instance is open: nothing to enter",
  NO_PATH: "no path",
  NOT_TAKEN: "no input now",
  /** A tap on a gate, a chest or a lever (CLI-05 brief §4.4). */
  NOT_AVAILABLE_YET,
  /** A refusal no line of §4.4 covers (an `Illegal` a skill or item tap should not reach). */
  NOT_AVAILABLE: "Not available.",
} as const;

/** What the combat screen draws: the controller's view (none without a state to read) and the log. */
export interface CombatSnapshot {
  readonly view: CombatView | null;
  readonly log: readonly LogLine[];
}

/** The combat screen's inputs. Each one that plays a refused action leaves the slot armed. */
export interface CombatInputs {
  /** A stable snapshot: it changes only when the view or the log does. */
  snapshot(): CombatSnapshot;
  subscribe(listener: () => void): () => void;
  /** A tap on a bar or belt slot, or its key. */
  slot(armed: Armed): void;
  inspect(armed: Armed): void;
  /** A tap on an actor while a slot is armed. */
  actor(entity: number): boolean;
  /** A tap on a tile while a slot is armed. */
  tile(tile: Tile): boolean;
  cycle(by: 1 | -1): boolean;
  go(): boolean;
  escape(): boolean;
}

/** The action a played slot is: a `skill` on an entity or a tile, an `item` on an entity. */
export function slotAction(armed: Armed, target: CombatTarget): PlayAction | undefined {
  if (armed.kind === "skill") {
    const value = target.tile ? tileValue(target.at) : target.entity;
    return { kind: "skill", slot: armed.slot, target: { tile: target.tile, value } };
  }
  // A potion's action carries an entity only (`actions::Action::Item`)
  return target.tile ? undefined : { kind: "item", slot: armed.slot, entity: target.entity };
}

export interface ChainController {
  get(): ControllerState;
  subscribe(listener: (state: ControllerState) => void): () => void;
  /** The world the chain's state draws (the planner's, and the map's). */
  world(): SandboxWorld;
  /** Where the adventurer stands on the chain's state, and where the batch's moves end. */
  tiles(): { readonly chain: Tile; readonly planned: Tile };
  tap(tile: Tile): Tap;
  /**
   * A tap as the map sees it: the intent the sandbox's session gets, or null. The sandbox draws a
   * selected goblin's arcs and toggles it at each tap on it; this keeps its selection in step with
   * the controller's (a select, then an attack that deselects), and never lets it turn the drawn
   * adventurer toward a goblin: the map draws the chain's facing.
   */
  mapTap(tile: Tile): Intent | null;
  /** The facing the batch leaves the adventurer in: the last planned move or turn, else the chain's. */
  facing(): Facing;
  /** The facing the chain holds, which the map draws. */
  facingOfChain(): Facing;
  /** A step key or a tap on a neighbour: one `move`, or a `turn` after `R`. */
  step(direction: Facing): boolean;
  wait(): boolean;
  /** `R`: the next step key turns. Pressed again, or `Esc`: cancelled. */
  armTurn(): void;
  disarm(): boolean;
  /** `B` */
  send(): boolean;
  /** `N` */
  enterAgain(): Promise<boolean>;
  /** A key the mode does not bind in part 1: one line in the panel. */
  unbound(): void;
  /** A new chain state was drawn: the selection goes with the map it was on. */
  reset(): void;
  /** Stage 1 on the map (§5): the batch's moves as markers, the predicted last tile and facing. */
  ghosts(): Ghosts;
  /** The combat screen's model (CLI-11d). */
  readonly combat: CombatInputs;
}

export interface Ghosts {
  /** The tile of each move of the batch, in order (geometric: the planner decides no legality). */
  readonly steps: readonly Tile[];
  /** Where the mirror predicts the adventurer ends, none while it predicts nothing. */
  readonly end: { readonly tile: Tile; readonly facing: Facing } | undefined;
}

export function createChainController(deps: ControllerDeps): ChainController {
  const { stages } = deps;
  const listeners = new Set<(state: ControllerState) => void>();
  let state: ControllerState = {
    turning: false,
    selected: null,
    entering: false,
    note: undefined,
  };
  let drawn: { chain: ChainState; world: SandboxWorld } | undefined;
  /** The goblin the map's session has selected (its arcs), which `mapTap` keeps in step. */
  let onMap: number | null = null;
  /** The stages' line as last seen: a new one replaces the controller's own note. */
  let line = stages.get().line;
  let seen = stages.get();
  stages.subscribe((now) => {
    const before = seen;
    seen = now;
    if (now.sent !== before.sent && now.sent !== undefined) settle(now.sent);
    if (
      now.chain !== before.chain ||
      now.planned !== before.planned ||
      now.mirror !== before.mirror
    ) {
      rebuild();
    }
    if (now.line === line) return;
    line = now.line;
    if (state.note !== undefined) set({ note: undefined });
  });

  const set = (next: Partial<ControllerState>) => {
    state = { ...state, ...next };
    for (const listener of listeners) listener(state);
  };

  // ---- The combat screen (CLI-11d).

  /** The lines the sent batches settled (confirmed, or struck), and the refusals before the batch. */
  const history = new CombatLog();
  /** The predicted lines of each action of the batch planned (§7.2), recomputed with the batch. */
  let pending: LogLine[][] = [];
  /**
   * The refusals since the last settled batch, each after the lines of the `at` actions planned
   * when it came: the log stays in input order, and they go to `history` with the batch's lines.
   */
  let refusals: { readonly at: number; readonly line: LogLine }[] = [];
  const prefixes = new Prefixes<MirrorState>((base, actions) =>
    runRecorded({ ...segmentOf(base), actions }, nativeClasses),
  );
  let lineCache:
    { base: MirrorState; actions: readonly PlayAction[]; lines: LogLine[][] } | undefined;
  const combatListeners = new Set<() => void>();
  let combat:
    | { readonly world: CombatWorld; readonly view: CombatController; readonly stop: () => void }
    | undefined;
  let snapshot: CombatSnapshot = { view: null, log: [] };
  /** The slot a refused action left armed, for the input that played it to arm again. */
  let refused: Armed | undefined;

  const sameAction = (a: PlayAction, b: PlayAction) => JSON.stringify(a) === JSON.stringify(b);

  /** `batchLines` on the planned actions, only the new ones when the earlier ones are unchanged. */
  function computeLines(base: MirrorState, actions: readonly PlayAction[]): LogLine[][] {
    if (base.content === undefined || actions.length === 0) return [];
    try {
      const segment = segmentOf(base);
      const first = segment.words.members[0];
      if (first === undefined) return [];
      const { x, y } = memberPlace(first.state);
      const batch = {
        words: segment.words,
        ground: segment.ground,
        content: base.content,
        board: segmentBoard(segment.area, x, y),
        actions,
      };
      const kept =
        lineCache !== undefined &&
        lineCache.base === base &&
        lineCache.actions.length <= actions.length &&
        lineCache.actions.every((a, k) => sameAction(a, actions[k]!));
      const before = kept ? lineCache!.lines : [];
      const fresh = batchLines(batch, prefixes.at(base, actions), {
        names: NAMES,
        report: consoleLogReport,
        from: before.length + 1,
      });
      const lines = [...before, ...fresh];
      lineCache = { base, actions: [...actions], lines };
      return lines;
    } catch (error) {
      // No prediction (`NotMirrored`): no predicted lines; a mirror failure is `stages`' to log
      if (!(error instanceof NotMirrored)) {
        console.warn(
          "grimworld.log-failure",
          error instanceof Error ? error.message : String(error),
        );
      }
      return [];
    }
  }

  /** The batch's predicted lines with the refusals between them, in input order. */
  function unsettled(): LogLine[] {
    const after = (k: number) => refusals.filter((r) => r.at === k).map((r) => r.line);
    return [
      ...pending.flatMap((lines, k) => [...after(k), ...lines]),
      ...refusals.filter((r) => r.at >= pending.length).map((r) => r.line),
    ];
  }

  function refresh() {
    const log = [...history.lines, ...unsettled()].slice(-MAX_LINES);
    snapshot = { view: combat?.view.view() ?? null, log };
    for (const listener of combatListeners) listener();
  }

  /** §4.4's check: the line of the `Illegal` the mirror stops on at the new action, or none. */
  function verdict(action: PlayAction, armed: Armed): string | undefined {
    const { chain, planned } = stages.get();
    const actions = [...actionsOf(planned), action];
    let illegal: number | undefined;
    try {
      const ran = (deps.run?.(chain) ?? mirrorOf(chain.mirror))(actions);
      if (ran.done.illegal !== undefined && ran.done.played === planned.length) {
        illegal = ran.done.illegal;
      }
    } catch {
      // The mirror cannot say (`NotMirrored`, a reveal): the simulation decides
      return undefined;
    }
    if (illegal === undefined) return undefined;
    if (UNREACHABLE.includes(illegal)) {
      console.warn("grimworld.parity", { actions, illegal });
    }
    const slot = combat?.view.view().state.adventurer.bar[armed.slot];
    const ticks = armed.kind === "skill" ? (slot?.ticks ?? undefined) : undefined;
    return refusalLine(illegal, ticks) ?? notes.NOT_AVAILABLE;
  }

  /** Plays an armed slot on a target: one action put into the batch, or one refusal line. */
  function play(armed: Armed, target: CombatTarget) {
    const action = slotAction(armed, target);
    const line = action === undefined ? refusalLine(Illegal.Target)! : verdict(action, armed);
    if (line !== undefined) {
      refusals = [...refusals, { at: stages.get().planned.length, line: refusal(line) }];
      set({ note: line, turning: false });
      refused = armed;
      refresh();
      return;
    }
    set({ turning: false });
    if (!put([action!])) refused = armed;
  }

  /** A combat input: a play the check refused leaves the slot armed, as it was. */
  function guarded<T>(call: () => T): T {
    refused = undefined;
    const result = call();
    if (refused !== undefined && combat !== undefined) {
      const armed = refused;
      refused = undefined;
      combat.view.slot(armed);
    }
    return result;
  }

  /** The combat view made again on the state after the batch planned so far. */
  function rebuild() {
    const now = stages.get();
    const predicted = now.mirror?.kind === "predicted" ? now.mirror : undefined;
    const after =
      predicted?.ground === undefined
        ? undefined
        : { words: predicted.words, ground: predicted.ground };
    const world = deps.combatWorld ? deps.combatWorld(now) : combatWorldOf(now.chain.mirror, after);
    combat?.stop();
    combat = undefined;
    if (world !== undefined) {
      const view = new CombatController(stateOf(world, NAMES));
      view.setRules({
        aim: (_, armed) => {
          // `aiming` asks client/sim's `aim` of every tile of the window, those beyond the
          // location's edge included, and the loader panics on a negative tile (`u8_add`): a TILE
          // slot near the edge has no aim, never a thrown input (a defect of `targeting.ts`)
          try {
            return aiming(world, armed);
          } catch (error) {
            console.warn("grimworld.aim-failure", error instanceof Error ? error.message : error);
            return null;
          }
        },
        play: (at, armed, target) => {
          play(armed, target);
          return at;
        },
      });
      combat = { world, view, stop: view.subscribe(refresh) };
    }
    pending = (deps.lines ?? computeLines)(
      now.chain.mirror,
      now.planned.map((p) => p.action),
    );
    // A batch dropped or cut: its refusals stay, after what is left of it
    const at = now.planned.length;
    refusals = refusals.map((r) => (r.at > at ? { ...r, at } : r));
    refresh();
  }

  /** The sent batch settled (§7.2 item 4): its predicted lines confirmed, or struck if it differs. */
  function settle(sent: NonNullable<StagesState["sent"]>) {
    const { result } = sent;
    if (result.kind !== "sent" || result.chain.kind !== "played") return;
    if (result.mirror.kind !== "predicted") return;
    history.add(unsettled());
    if (result.mismatches.length === 0 && result.differs.length === 0) history.confirm();
    else history.correct();
    // What is pending is the sent batch's: it is settled, and the batch is dropped or read again
    pending = [];
    refusals = [];
    refresh();
  }

  function world(): SandboxWorld {
    const { chain } = stages.get();
    if (drawn?.chain !== chain) {
      const { view, region, member } = chain.mirror;
      drawn = { chain, world: chainWorld({ view, region, member }) };
    }
    return drawn.world;
  }

  function tiles() {
    const { chain, planned } = stages.get();
    const { view, member } = chain.mirror;
    const word = view.members[member]?.state ?? 0n;
    const here = memberPlace(word);
    let end: Tile = { x: here.x, y: here.y };
    for (const { action } of planned) {
      if (action.kind === "move") end = tileToward(end, action.direction as Facing);
    }
    return { chain: { x: here.x, y: here.y }, planned: end };
  }

  /** Puts actions into the batch; a refusal is a note, a taken input clears the last one. */
  function put(actions: readonly PlayAction[], path = false): boolean {
    const taken = stages.input(actions, { path });
    set({
      note: taken ? undefined : stages.get().line === undefined ? notes.NOT_TAKEN : undefined,
    });
    return taken;
  }

  const controller: ChainController = {
    get: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    world,
    tiles,

    facing() {
      const { chain, planned } = stages.get();
      for (let i = planned.length - 1; i >= 0; i--) {
        const action = planned[i]!.action;
        if (action.kind === "move" || action.kind === "turn") return action.direction as Facing;
      }
      const { view, member } = chain.mirror;
      return memberPlace(view.members[member]?.state ?? 0n).facing;
    },

    mapTap(tile) {
      const result = controller.tap(tile);
      const goblinTile = (entity: number) =>
        world().actors.find((a) => a.side === "goblin" && a.id === entity)?.tile;
      const toggle = (entity: number): Intent | null => {
        const at = goblinTile(entity);
        return at === undefined ? null : { kind: "tile", tile: at };
      };
      // The sandbox deselects a goblin tapped again, and turns nobody. The controller has no
      // selection after an attack, taken or refused: the map's follows, whatever the result says
      if (state.selected === null && onMap !== null) {
        const tapped = world().actors.find(
          (a) => a.side === "goblin" && tileKey(a.tile) === tileKey(tile),
        );
        if (tapped?.id === onMap) {
          onMap = null;
          return toggle(tapped.id);
        }
      }
      if (result.kind === "attack") return null;
      if (result.kind !== "select") return null;
      const { chain } = tiles();
      const at = goblinTile(result.entity);
      const toward = at === undefined ? null : directionBetween(chain, at);
      // The sandbox turns the adventurer toward an adjacent goblin it selects: that is not played
      if (toward !== null && toward !== controller.facingOfChain()) {
        const stale = onMap;
        onMap = null;
        return stale === null ? null : toggle(stale);
      }
      onMap = result.entity;
      return toggle(result.entity);
    },

    facingOfChain() {
      const { view, member } = stages.get().chain.mirror;
      return memberPlace(view.members[member]?.state ?? 0n).facing;
    },

    tap(tile) {
      if (stages.get().phase !== "ready") return { kind: "none" };
      const map = world();
      const goblin = map.actors.find(
        (a) => a.side === "goblin" && tileKey(a.tile) === tileKey(tile),
      );
      if (goblin !== undefined) {
        if (state.selected === goblin.id) {
          set({ selected: null, turning: false });
          return put([{ kind: "attack", entity: goblin.id }])
            ? { kind: "attack", entity: goblin.id }
            : { kind: "none" };
        }
        set({ selected: goblin.id, turning: false, note: undefined });
        return { kind: "select", entity: goblin.id };
      }
      // Interactions are not available (CLI-05 brief §4.4): a gate, a chest or a lever adds nothing
      if (objectAt(stages.get().chain.mirror.region, tile)) {
        set({ note: notes.NOT_AVAILABLE_YET, turning: false });
        return { kind: "none" };
      }
      if (kindAt(map.terrain, tile) !== "floor") return { kind: "none" };
      const { planned } = tiles();
      if (tileKey(planned) === tileKey(tile)) return { kind: "none" };
      const next = directionBetween(planned, tile);
      if (next !== null) {
        set({ turning: false });
        return put([{ kind: "move", direction: next }])
          ? { kind: "moves", count: 1 }
          : { kind: "none" };
      }
      const path = planPath(map, planned, tile);
      if (path === null) {
        set({ note: notes.NO_PATH });
        return { kind: "none" };
      }
      const moves: PlayAction[] = [];
      let from = planned;
      for (const to of path) {
        const direction = directionBetween(from, to);
        if (direction === null) break;
        moves.push({ kind: "move", direction });
        from = to;
      }
      set({ turning: false });
      return put(moves, true) ? { kind: "moves", count: moves.length } : { kind: "none" };
    },

    step(direction) {
      const kind = state.turning ? "turn" : "move";
      set({ turning: false });
      return put([{ kind, direction }]);
    },

    wait() {
      set({ turning: false });
      return put([{ kind: "wait" }]);
    },

    armTurn() {
      if (stages.get().phase === "ready") set({ turning: !state.turning });
    },

    disarm() {
      if (!state.turning) return false;
      set({ turning: false });
      return true;
    },

    send() {
      set({ turning: false, note: undefined });
      return stages.send();
    },

    async enterAgain() {
      if (stages.get().phase !== "closed") {
        set({ note: notes.NOT_CLOSED });
        return false;
      }
      if (state.entering) return false;
      set({ entering: true, note: undefined });
      try {
        const chain = await deps.enter();
        stages.install(chain);
        history.clear();
        rebuild();
        set({ entering: false, selected: null });
        return true;
      } catch (error) {
        // A refusal of the guard arrives inside the account's error: it shows the guard's own line
        const cause = (error as { cause?: unknown } | undefined)?.cause;
        const refused = [cause, error].find((e) => e instanceof Error && e.name === "ChainRefused");
        set({
          entering: false,
          note:
            refused instanceof Error
              ? refused.message
              : `enter failed: ${error instanceof Error ? error.message : String(error)}`,
        });
        return false;
      }
    },

    unbound() {
      set({ note: notes.UNBOUND });
    },

    reset() {
      onMap = null;
      set({ selected: null, turning: false });
    },

    ghosts() {
      const { chain, planned, mirror } = stages.get();
      const { view, member } = chain.mirror;
      const here = memberPlace(view.members[member]?.state ?? 0n);
      const steps: Tile[] = [];
      let at: Tile = { x: here.x, y: here.y };
      for (const { action } of planned) {
        if (action.kind !== "move") continue;
        at = tileToward(at, action.direction as Facing);
        steps.push(at);
      }
      const word = mirror?.kind === "predicted" ? mirror.words.members[member]?.state : undefined;
      if (word === undefined) return { steps, end: undefined };
      const place = memberPlace(word);
      return { steps, end: { tile: { x: place.x, y: place.y }, facing: place.facing } };
    },

    combat: {
      snapshot: () => snapshot,
      subscribe(listener) {
        combatListeners.add(listener);
        return () => combatListeners.delete(listener);
      },
      slot: (armed) => guarded(() => combat?.view.slot(armed)),
      inspect: (armed) => void combat?.view.inspect(armed),
      actor: (entity) => guarded(() => combat?.view.actor(entity) ?? false),
      tile: (tile) => guarded(() => combat?.view.tile(tile) ?? false),
      cycle: (by) => combat?.view.cycle(by) ?? false,
      go: () => guarded(() => combat?.view.go() ?? false),
      escape: () => combat?.view.escape() ?? false,
    },
  };
  rebuild();
  return controller;
}
