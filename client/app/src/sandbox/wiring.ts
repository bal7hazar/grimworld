import type { Intent } from "../input/intent";
import { type StepKey, verticalDirection } from "../input/keys";
import { type Explored, NOTHING_EXPLORED, drawnActors, explore, fogTiles } from "../render/fog";
import type { Tile, ViewActor, ViewState, ViewTile } from "../render/view";
import {
  SIGHT_RADIUS,
  type StepStops,
  TICKS_PER_STEP,
  arcsOf,
  facingToward,
  findPath,
  revealInSight,
  stepToward,
  stopsAfterStep,
  tilesInSight,
  visibleActors,
} from "./placeholders";
import { type SandboxWorld, inBounds, kindAt, sameTile } from "./world";

/**
 * The sandbox's wiring: applies an intent to the fixture's state through the placeholders, and
 * produces the view state. The only importer of `placeholders.ts`; CLI-03 replaces both with
 * `client/sim`.
 *
 * A world of kind `"hub"` (CLI-03f, D-202) walks with the same finder and step, and inherits none
 * of the instance's stand-ins: every tile is in sight and every actor seen, nothing is revealed,
 * no stop condition is evaluated, the path is not bounded by the D-120 window, and a tap on an
 * actor selects nothing (no arcs). The hub kind is read here only.
 */

export interface SandboxState {
  readonly world: SandboxWorld;
  readonly selectedActorId: number | null;
  readonly selectedTile: Tile | null;
  /** The planned queue (design/11 *The queue*): the steps not walked yet, first step first. */
  readonly path: readonly Tile[];
  /** Whether the planned queue is being walked; a planned queue not walked is a preview. */
  readonly walking: boolean;
  /** The steps the last stop or cancel dropped: they fade out. */
  readonly dropped: readonly Tile[];
  /** Why the last walk stopped, in one line (design/11), or "" when it did not stop. */
  readonly stopped: string;
  /** One line on what the last intent did, for the debug panel. */
  readonly said: string;
  /**
   * The tiles in sight at least once since the instance opened (CLI-03n, `render/fog.ts`): what
   * the map draws. Grown on a step, started again with the instance; lost on a reload. None in
   * a hub (it hides nothing).
   */
  readonly explored: Explored;
}

/**
 * How an instance's map shows what was seen (CLI-03n, D-213): `sight` (the default) draws the
 * explored tiles beyond sight in grayscale; `full` (`?fog=full`) keeps them in colour, dimmed.
 * Either way a tile never in sight is hidden.
 */
export type FogMode = "sight" | "full";

/** The one line of a walk ended by a tap: on the counter, or on the map. */
export const CANCELLED = "walk cancelled";

/** How a tap on a floor tile plays (design/11 *Confirmation*, I-5). */
export interface TapOptions {
  /** Move is played on the tap (the design's default); off, a first tap previews the path. */
  readonly playOnTap: boolean;
}

export const DEFAULT_TAP: TapOptions = { playOnTap: true };

const isHub = (world: SandboxWorld) => world.kind === "hub";

/** The actors the adventurer sees: in a hub, every one (nothing is hidden by sight). */
function seen(world: SandboxWorld): ViewActor[] {
  return isHub(world) ? [...world.actors] : visibleActors(world.terrain, world.actors);
}

export function initialState(world: SandboxWorld): SandboxState {
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  const terrain =
    adventurer && !isHub(world) ? revealInSight(world.terrain, adventurer.tile) : world.terrain;
  const explored =
    adventurer && !isHub(world)
      ? explore(NOTHING_EXPLORED, tilesInSight(terrain, adventurer.tile))
      : NOTHING_EXPLORED;
  return {
    world: { ...world, terrain },
    explored,
    selectedActorId: null,
    selectedTile: world.path.at(-1) ?? null,
    path: world.path,
    walking: false,
    dropped: [],
    stopped: "",
    said: "",
  };
}

const nameOf = (actor: ViewActor) => (actor.side === "adventurer" ? actor.profession : actor.caste);

function describe(actor: ViewActor): string {
  return `#${actor.id} ${nameOf(actor)}, facing ${actor.facing}${actor.mark ? `, ${actor.mark}` : ""}`;
}

function cleared(state: SandboxState, said: string): SandboxState {
  return { ...state, selectedActorId: null, selectedTile: null, said };
}

/** The planned queue's cost in ticks (a placeholder: one tick a step). */
export function pathCost(state: SandboxState): number {
  return state.path.length * TICKS_PER_STEP;
}

/**
 * Ends the planned queue, walked or previewed: its steps not walked are dropped and fade out.
 * `reason` is the one line of a stop ("" for none).
 */
function drop(state: SandboxState, reason: string, said: string): SandboxState {
  return {
    ...state,
    path: [],
    walking: false,
    dropped: state.path,
    selectedTile: null,
    stopped: reason,
    said,
  };
}

/** A tap on the counter: the steps not yet walked fade out (design/11 *The queue*). */
export function cancelWalk(state: SandboxState): SandboxState {
  if (state.path.length === 0) return state;
  return state.walking ? drop(state, CANCELLED, CANCELLED) : drop(state, "", "preview cancelled");
}

/**
 * A tap on the adventurer or a goblin in sight selects it (its arcs are shown), and the adventurer
 * turns toward an adjacent goblin; a tap on a floor tile plans the path to it and walks it, on the
 * tap (`playOnTap`) or on a second tap on the same tile; a tap on the selected actor again, or
 * outside the revealed map, clears the selection. Any other tap ends the planned queue first.
 */
export function applyIntent(
  state: SandboxState,
  intent: Intent,
  options: TapOptions = DEFAULT_TAP,
): SandboxState {
  const { world } = state;
  const { terrain } = world;
  const tile = intent.tile;
  const where = `(${tile.x}, ${tile.y})`;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) return state;
  const actor = seen(world).find((a) => sameTile(a.tile, tile));
  const kind = inBounds(terrain, tile) ? kindAt(terrain, tile) : null;

  if (intent.kind === "inspect") {
    const what = actor ? describe(actor) : (kind ?? "outside the location");
    return { ...state, said: `inspect ${where}: ${what}` };
  }
  const previewed = !state.walking && state.path.length > 0 && state.selectedTile !== null;
  if (previewed && state.selectedTile && sameTile(state.selectedTile, tile)) {
    return {
      ...state,
      walking: true,
      dropped: [],
      stopped: "",
      said: `tap ${where}: walk ${state.path.length} steps`,
    };
  }
  // A tap ends the planned queue first; a walk it ends says so in its one line (a new walk
  // started by the same tap replaces the line).
  const before: SandboxState =
    state.path.length > 0
      ? drop(state, state.walking ? CANCELLED : "", "")
      : { ...state, dropped: [], stopped: "" };
  if (kind === null || kind === "unrevealed") {
    return cleared(before, `tap ${where}: outside, clear`);
  }
  // In a hub an actor is never selected: the hub screen inspects a figure before the wiring.
  if (actor && isHub(world)) return { ...state, said: `tap ${where}: ${describe(actor)}` };
  if (actor) {
    if (state.selectedActorId === actor.id) return cleared(before, `tap ${where}: deselect`);
    const facing = actor.side === "goblin" ? facingToward(adventurer.tile, actor.tile) : null;
    const actors =
      facing === null
        ? world.actors
        : world.actors.map((a) => (a.id === adventurer.id ? { ...a, facing } : a));
    return {
      ...before,
      world: { ...world, actors },
      selectedActorId: actor.id,
      selectedTile: null,
      said: `tap ${where}: select ${describe(actor)}${facing === null ? "" : `; turn to ${facing}`}`,
    };
  }
  if (kind !== "floor") return cleared(before, `tap ${where}: ${kind}, clear`);
  const path = findPath(terrain, world.actors, adventurer.tile, tile, !isHub(world));
  if (!path) {
    return { ...before, selectedActorId: null, selectedTile: tile, said: `tap ${where}: no path` };
  }
  const how = options.playOnTap ? "walk" : "preview";
  return {
    ...before,
    selectedActorId: null,
    selectedTile: tile,
    path,
    walking: options.playOnTap,
    stopped: options.playOnTap ? "" : before.stopped,
    said: `tap ${where}: ${how} ${path.length} steps, ${path.length * TICKS_PER_STEP} ticks`,
  };
}

/**
 * The hex a step key stands for (CLI-03k): the adjacent tile in that direction from the
 * adventurer, ↑ / ↓ resolved on the side it faces; the controller taps it. The direction is the
 * placeholder's own (`facingToward`, the adjacent tile it names `d`): the grid's geometry stays in
 * `placeholders.ts`.
 */
export function stepTarget(state: SandboxState, step: StepKey): Tile | null {
  const { world } = state;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) return null;
  const d =
    "direction" in step ? step.direction : verticalDirection(adventurer.facing, step.vertical);
  const { x, y } = adventurer.tile;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      const tile = { x: x + dx, y: y + dy };
      if (facingToward(adventurer.tile, tile) === d) return tile;
    }
  }
  return null;
}

const at = (tile: Tile) => `(${tile.x}, ${tile.y})`;

const article = (name: string) => (/^[aeiou]/.test(name) ? `an ${name}` : `a ${name}`);

/** "a runt", "a runt and a shaman", "a runt, a shaman and a slinger". */
function listed(names: readonly string[]): string {
  const all = names.map(article);
  if (all.length < 2) return all[0] ?? "";
  return `${all.slice(0, -1).join(", ")} and ${all.at(-1)}`;
}

/**
 * Plays the next step of the walk through the same placeholder step as a tap (`stepToward`),
 * then evaluates the stop conditions of design/02 that the sandbox can: the next step is invalid
 * (a wall, an actor on it: the walk stops before it), a goblin enters sight, a chunk is revealed
 * (the step is played, the walk stops after it). Damage, conditions, a goblin becoming alerted or
 * activating a skill, and Fate actions have no placeholder: they never stop a sandbox walk.
 */
export function walkStep(state: SandboxState): SandboxState {
  const next = state.path[0];
  if (!state.walking || !next) return state;
  const { world } = state;
  const { terrain } = world;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) return state;
  // The log line: the walk's target, where the adventurer stands, the planned next tile, and the
  // tile actually stepped to, so that a step off the plan shows.
  const walk = `walk to ${at(state.path.at(-1) ?? next)} from ${at(adventurer.tile)}`;
  const step = stepToward(terrain, world.actors, adventurer.id, next);
  if (!step || !sameTile(step.tile, next)) {
    const holder = world.actors.find((a) => sameTile(a.tile, next));
    const why = holder ? `${article(nameOf(holder))} stands in the way` : "the way is blocked";
    return drop(state, why, `${walk}: planned ${at(next)} invalid, stop: ${why}`);
  }
  const actors = world.actors.map((a) =>
    a.id === adventurer.id ? { ...a, tile: step.tile, facing: step.facing } : a,
  );
  const revealed = isHub(world) ? terrain : revealInSight(terrain, step.tile);
  const walked: SandboxState = {
    ...state,
    world: { ...world, actors, terrain: revealed },
    explored: isHub(world)
      ? state.explored
      : explore(state.explored, tilesInSight(revealed, step.tile)),
    path: state.path.slice(1),
    said: `${walk}: planned ${at(next)}, stepped to ${at(step.tile)}, facing ${step.facing}`,
  };
  const stops: StepStops = isHub(world)
    ? { entered: [], revealed: false }
    : stopsAfterStep({ terrain, actors: world.actors }, { terrain: revealed, actors });
  const { entered } = stops;
  const reasons: string[] = [];
  if (entered.length > 0) reasons.push(`${listed(entered.map(nameOf))} came into sight`);
  if (stops.revealed) reasons.push("a chunk was revealed");
  if (reasons.length > 0) {
    const who = entered.map((a) => `#${a.id} ${nameOf(a)} at ${at(a.tile)}`).join(", ");
    const why = reasons.join("; ");
    return drop(walked, why, `${walked.said}; stop: ${why}${who ? ` (${who})` : ""}`);
  }
  if (walked.path.length === 0) {
    return { ...walked, walking: false, selectedTile: null, said: `${walked.said}; arrived` };
  }
  return walked;
}

export function toView(state: SandboxState, fog: FogMode = "sight"): ViewState {
  const { world } = state;
  const { terrain } = world;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) throw new Error(`${world.name}: no adventurer`);
  const tiles: ViewTile[] = [];
  for (let y = 0; y < terrain.height; y++) {
    for (let x = 0; x < terrain.width; x++) {
      const i = y * terrain.width + x;
      const ground = terrain.ground?.[i];
      tiles.push({ x, y, kind: terrain.kinds[i] ?? "wall", ...(ground ? { ground } : {}) });
    }
  }
  const hub = isHub(world);
  const sight = hub ? tiles.map(({ x, y }) => ({ x, y })) : tilesInSight(terrain, adventurer.tile);
  // Drawn: a hub hides nothing; an instance, what was never in sight (CLI-03n). Selected: only an
  // actor the adventurer sees (`seen`), as before.
  const actors = hub ? [...world.actors] : drawnActors(world.actors, adventurer.id, state.explored);
  const selected = seen(world).find((a) => a.id === state.selectedActorId);
  return {
    tiles: hub ? tiles : fogTiles(tiles, state.explored),
    ...(hub ? {} : { revealed: tiles }),
    actors,
    adventurerId: adventurer.id,
    sight,
    arcs: selected ? arcsOf(terrain, selected) : null,
    path: state.path,
    dropped: state.dropped,
    selectedTile: state.selectedTile,
    structures: world.structures ?? [],
    ...(world.void ? { void: world.void } : {}),
    ...(!hub && fog === "sight" ? { fog: { sightRadius: SIGHT_RADIUS } } : {}),
  };
}
