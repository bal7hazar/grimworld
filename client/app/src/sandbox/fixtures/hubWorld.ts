import { TILE_WIDTH } from "../../input/coords";
import {
  type HubDecor,
  type HubFigure,
  type HubPlace,
  type HubView,
  hubPoint,
} from "../../render/hubView";
import type { Tile, TileKind, ViewActor, ViewStructure } from "../../render/view";
import { CHUNK, type SandboxWorld } from "../world";
import { ADVENTURER } from "./hubs";

/**
 * A hub lived like an exploration zone (CLI-03f, D-202): its fixtures turned into a `SandboxWorld`
 * the zone's controller, session and renderer walk and draw. Presentation, not a rule: the chain
 * knows only which hub an adventurer is in (D-03), and the hex inside it is never sent, checked or
 * stored. Pure: no clock, no randomness.
 */

/** The player's adventurer's entity id in a hub's world (the figures' ids are the fixtures'). */
export const HUB_ADVENTURER_ID = 1;

/**
 * How far inside the illustration's rectangle a hex's centre stands to be on the island, in art
 * pixels: half a hex (#319's measure: whole border cells would close the town's road on row 0).
 */
export const EDGE_MARGIN = TILE_WIDTH / 2;

/** A building's rows behind its base row, when the fixture gives none. */
export const DEFAULT_DEPTH = 1;

const key = (tile: Tile) => `${tile.x},${tile.y}`;

interface Footed {
  readonly at: Tile;
  readonly width: number;
  readonly depth?: number;
}

/**
 * The hexes a building stands on: on its base row and on `depth` rows behind it, every hex whose
 * centre lies under the building's width, measured from its door's centre. The door is included.
 */
export function footprint(view: Pick<HubView, "origin">, building: Footed): Tile[] {
  const door = hubPoint(view, building.at).x;
  const half = building.width / 2;
  const reach = Math.ceil(building.width / TILE_WIDTH) + 1;
  const tiles: Tile[] = [];
  for (let d = 0; d <= (building.depth ?? DEFAULT_DEPTH); d++) {
    const y = building.at.y + d;
    for (let x = building.at.x - reach; x <= building.at.x + reach; x++) {
      if (Math.abs(hubPoint(view, { x, y }).x - door) <= half + 1e-9) tiles.push({ x, y });
    }
  }
  return tiles;
}

/** Whether a hex is on the island: its centre `EDGE_MARGIN` inside the illustration's rectangle. */
export function onIsland(view: HubView, tile: Tile): boolean {
  const p = hubPoint(view, tile);
  return (
    p.x >= EDGE_MARGIN &&
    p.x <= view.width - EDGE_MARGIN &&
    p.y >= EDGE_MARGIN &&
    p.y <= view.height - EDGE_MARGIN
  );
}

/** The hex a figure faces: West (3) for "left", East (0) for "right", as the sprite reads. */
const facingOf = (figure: HubFigure) => (figure.facing === "left" ? 3 : 0);

function structures(view: HubView): ViewStructure[] {
  const place = (p: HubPlace): ViewStructure => ({
    key: `place:${p.id}`,
    kind: "building",
    sprite: p.building,
    at: p.at,
    width: p.width,
    height: p.height,
    shape: p.target.kind === "gate" ? "gate" : "house",
    // A place's door stays floor: the adventurer walks onto it.
    covers: footprint(view, p).filter((t) => key(t) !== key(p.at)),
  });
  const decor = (d: HubDecor): ViewStructure => ({
    key: `decor:${d.id}`,
    kind: "building",
    sprite: d.building,
    at: d.at,
    width: d.width,
    height: d.height,
    shape: "decor",
    covers: footprint(view, d),
  });
  return [
    ...view.places.map(place),
    ...view.decor.map(decor),
    ...view.props.map((p): ViewStructure => ({
      key: `prop:${p.id}`,
      kind: "prop",
      sprite: p.sprite,
      at: p.at,
      width: TILE_WIDTH,
      height: TILE_WIDTH,
      ...(p.mirror ? { mirror: true } : {}),
      covers: [p.at],
    })),
  ];
}

/**
 * The hub as a zone's world, the player's adventurer on `at`:
 *
 * - terrain: whole 15 × 15 chunks over the island, all revealed; `floor` on the island, `wall`
 *   outside it (D-134) and under every building's footprint and every prop, a place's door apart;
 * - actors: the player's adventurer, and each present figure standing on its hex;
 * - structures: the buildings and props, drawn by the zone's renderer on the hexes they cover.
 */
export function hubWorld(view: HubView, at: Tile): SandboxWorld {
  const placed = structures(view);
  const blocked = new Set(placed.flatMap((s) => s.covers.map(key)));
  let columns = 0;
  let rows = 0;
  for (let y = 0; hubPoint(view, { x: 0, y }).y >= EDGE_MARGIN; y++) rows = y + 1;
  for (let x = 0; hubPoint(view, { x, y: 0 }).x >= EDGE_MARGIN; x++) columns = x + 1;
  const width = CHUNK * Math.max(1, Math.ceil(columns / CHUNK));
  const height = CHUNK * Math.max(1, Math.ceil(rows / CHUNK));
  const kinds: TileKind[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const tile = { x, y };
      kinds.push(onIsland(view, tile) && !blocked.has(key(tile)) ? "floor" : "wall");
    }
  }
  const actors: ViewActor[] = [
    {
      id: HUB_ADVENTURER_ID,
      side: "adventurer",
      profession: ADVENTURER.profession,
      tile: at,
      facing: 0,
      mark: null,
    },
    ...view.figures.map((f): ViewActor => ({
      id: f.id,
      side: "adventurer",
      profession: f.profession,
      tile: f.at,
      facing: facingOf(f),
      mark: null,
    })),
  ];
  return {
    name: view.name,
    description: `${view.name}: a hub lived like a zone (CLI-03f, D-202)`,
    terrain: { width, height, kinds, hidden: kinds },
    actors,
    adventurerId: HUB_ADVENTURER_ID,
    path: [],
    kind: "hub",
    structures: placed,
  };
}

/** What a hex of a hub is to a tap: a place (its door included), a figure, a decor, a prop, ground. */
export type HubTap =
  | { readonly kind: "place"; readonly place: HubPlace }
  | { readonly kind: "figure"; readonly figure: HubFigure }
  | { readonly kind: "decor"; readonly id: string }
  | { readonly kind: "prop"; readonly id: string }
  | { readonly kind: "ground" };

/** Which piece of the hub a tapped hex belongs to: pure, the hub screen routes the tap by it. */
export function hubTap(view: HubView, tile: Tile): HubTap {
  const here = key(tile);
  const figure = view.figures.find((f) => key(f.at) === here);
  if (figure) return { kind: "figure", figure };
  const place = view.places.find((p) => footprint(view, p).some((t) => key(t) === here));
  if (place) return { kind: "place", place };
  const decor = view.decor.find((d) => footprint(view, d).some((t) => key(t) === here));
  if (decor) return { kind: "decor", id: decor.id };
  const prop = view.props.find((p) => key(p.at) === here);
  if (prop) return { kind: "prop", id: prop.id };
  return { kind: "ground" };
}

/** Whether the adventurer stands on a place's door. */
export function onDoor(place: HubPlace, tile: Tile | null): boolean {
  return tile !== null && key(place.at) === key(tile);
}
