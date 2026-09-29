import type { Intent } from "../input/intent";
import type { Tile, ViewActor, ViewState, ViewTile } from "../render/view";
import {
  arcsOf,
  facingToward,
  revealInSight,
  stepToward,
  tilesInSight,
  visibleActors,
} from "./placeholders";
import { type SandboxWorld, inBounds, kindAt, sameTile } from "./world";

/**
 * The sandbox's wiring: applies an intent to the fixture's state through the placeholders, and
 * produces the view state. The only importer of `placeholders.ts`; CLI-03 replaces both with
 * `client/sim`.
 */

export interface SandboxState {
  readonly world: SandboxWorld;
  readonly selectedActorId: number | null;
  readonly selectedTile: Tile | null;
  readonly path: readonly Tile[];
  /** One line on what the last intent did, for the debug panel. */
  readonly said: string;
}

export function initialState(world: SandboxWorld): SandboxState {
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  const terrain = adventurer ? revealInSight(world.terrain, adventurer.tile) : world.terrain;
  return {
    world: { ...world, terrain },
    selectedActorId: null,
    selectedTile: null,
    path: world.path,
    said: "",
  };
}

function describe(actor: ViewActor): string {
  const who = actor.side === "adventurer" ? actor.profession : actor.caste;
  return `#${actor.id} ${who}, facing ${actor.facing}${actor.mark ? `, ${actor.mark}` : ""}`;
}

function cleared(state: SandboxState, said: string): SandboxState {
  return { ...state, selectedActorId: null, selectedTile: null, said };
}

/**
 * A tap on the adventurer or a goblin in sight selects it (its arcs are shown), and the adventurer
 * turns toward an adjacent goblin; a tap on a floor tile takes one step toward it; a tap on the
 * selected actor again, or outside the revealed map, clears the selection.
 */
export function applyIntent(state: SandboxState, intent: Intent): SandboxState {
  const { world } = state;
  const { terrain } = world;
  const tile = intent.tile;
  const where = `(${tile.x}, ${tile.y})`;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) return state;
  const actor = visibleActors(terrain, world.actors).find((a) => sameTile(a.tile, tile));
  const kind = inBounds(terrain, tile) ? kindAt(terrain, tile) : null;

  if (intent.kind === "inspect") {
    const what = actor ? describe(actor) : (kind ?? "outside the location");
    return { ...state, said: `inspect ${where}: ${what}` };
  }
  if (kind === null || kind === "unrevealed") return cleared(state, `tap ${where}: outside, clear`);
  if (actor) {
    if (state.selectedActorId === actor.id) return cleared(state, `tap ${where}: deselect`);
    const facing = actor.side === "goblin" ? facingToward(adventurer.tile, actor.tile) : null;
    const actors =
      facing === null
        ? world.actors
        : world.actors.map((a) => (a.id === adventurer.id ? { ...a, facing } : a));
    return {
      ...state,
      world: { ...world, actors },
      selectedActorId: actor.id,
      selectedTile: null,
      said: `tap ${where}: select ${describe(actor)}${facing === null ? "" : `; turn to ${facing}`}`,
    };
  }
  if (kind !== "floor") return cleared(state, `tap ${where}: ${kind}, clear`);
  const step = stepToward(terrain, world.actors, adventurer.id, tile);
  if (!step) return { ...state, selectedTile: tile, said: `tap ${where}: no step` };
  const actors = world.actors.map((a) =>
    a.id === adventurer.id ? { ...a, tile: step.tile, facing: step.facing } : a,
  );
  const arrived = sameTile(step.tile, tile);
  return {
    ...state,
    world: { ...world, actors, terrain: revealInSight(terrain, step.tile) },
    selectedTile: arrived ? null : tile,
    path: [],
    said: `tap ${where}: step to (${step.tile.x}, ${step.tile.y}), facing ${step.facing}`,
  };
}

export function toView(state: SandboxState): ViewState {
  const { world } = state;
  const { terrain } = world;
  const adventurer = world.actors.find((a) => a.id === world.adventurerId);
  if (!adventurer) throw new Error(`${world.name}: no adventurer`);
  const tiles: ViewTile[] = [];
  for (let y = 0; y < terrain.height; y++) {
    for (let x = 0; x < terrain.width; x++) {
      tiles.push({ x, y, kind: terrain.kinds[y * terrain.width + x] ?? "wall" });
    }
  }
  const sight = tilesInSight(terrain, adventurer.tile);
  const actors = visibleActors(terrain, world.actors);
  const selected = actors.find((a) => a.id === state.selectedActorId);
  return {
    tiles,
    actors,
    adventurerId: adventurer.id,
    sight,
    arcs: selected ? arcsOf(terrain, selected) : null,
    path: state.path,
    selectedTile: state.selectedTile,
  };
}
