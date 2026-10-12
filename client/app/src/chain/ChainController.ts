import type { PlayAction } from "../preview/actions";
import type { Facing, Tile } from "../render/view";
import { directionBetween, planPath, tileToward } from "../sandbox/wiring";
import { tileKey } from "../render/fog";
import { kindAt } from "../sandbox/world";
import type { ChainState } from "./send";
import type { Stages } from "./stages";
import { chainWorld, memberPlace } from "./world";
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
 */

export interface ControllerDeps {
  readonly stages: Stages;
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
} as const;

export interface ChainController {
  get(): ControllerState;
  subscribe(listener: (state: ControllerState) => void): () => void;
  /** The world the chain's state draws (the planner's, and the map's). */
  world(): SandboxWorld;
  /** Where the adventurer stands on the chain's state, and where the batch's moves end. */
  tiles(): { readonly chain: Tile; readonly planned: Tile };
  tap(tile: Tile): Tap;
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

  const set = (next: Partial<ControllerState>) => {
    state = { ...state, ...next };
    for (const listener of listeners) listener(state);
  };

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

  return {
    get: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    world,
    tiles,

    tap(tile) {
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
      set({ turning: false });
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
        set({ entering: false, selected: null });
        return true;
      } catch (error) {
        set({
          entering: false,
          note: `enter failed: ${error instanceof Error ? error.message : String(error)}`,
        });
        return false;
      }
    },

    unbound() {
      set({ note: notes.UNBOUND });
    },

    reset() {
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
  };
}
