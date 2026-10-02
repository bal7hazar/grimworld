import { type Point, TILE_WIDTH, tileToPixel } from "../input/coords";
import type { ServiceId } from "../input/intent";
import { DEFAULT_FEET, feetOffset } from "./renderer";
import type { Profession, Tile } from "./view";

/**
 * The hub renderer's input (CLI-03c, CLI-03e), as `view.ts` is the room's: what a hub shows, as
 * data. A hub is a screen of places to tap (design/11 *Hubs*, D-03): no movement, no rule. Since
 * CLI-03e it is laid out on the **instance's hex grid** at the instance's scale (D-196): every
 * building, prop and figure stands on a hex, given as a tile in the room's coordinates
 * (`input/coords.ts`), and the illustration is in art pixels at scale 1, `x` to the right and `y`
 * down. The grid places things; it is not drawn.
 */

/** Where a place leads: a service's screen, or the Gate screen. */
export type HubTarget =
  { readonly kind: "service"; readonly service: ServiceId } | { readonly kind: "gate" };

/** A building standing on the ground, a place to tap. */
export interface HubPlace {
  /** Unique in the hub; the tap target's name in the page. */
  readonly id: string;
  readonly label: string;
  readonly target: HubTarget;
  /** The building's still in the atlas (`tools/art`, role `building`); a shape without it. */
  readonly building: string;
  /** Its anchor tile, its door: the middle of its base stands on the hex's centre. */
  readonly at: Tile;
  /** Its native size in art pixels (the still's visible width, and height above its base). */
  readonly width: number;
  readonly height: number;
}

/** A building that is not a place: life around the services. No tap target, no label. */
export interface HubDecor {
  readonly id: string;
  readonly building: string;
  readonly at: Tile;
  /** Its native size, for the shape drawn without the atlas. */
  readonly width: number;
  readonly height: number;
}

/** A tree, a bush, a rock, a stump, a sheep (`tools/art`, role `prop`): drawn at one frame. */
export interface HubProp {
  readonly id: string;
  readonly sprite: string;
  readonly at: Tile;
  readonly mirror?: boolean;
}

/** A present adventurer (design/09: listed by the indexer later), drawn as decor. */
export interface HubFigure {
  readonly id: number;
  readonly name: string;
  readonly profession: Profession;
  readonly level: number;
  /** The hex it stands on, its feet where a room puts them; it stands still (D-178). */
  readonly at: Tile;
  readonly facing: "left" | "right";
}

/**
 * The ground, drawn once into a texture: square cells of `TILE_WIDTH` over the whole illustration,
 * from a tileset of the atlas (`<tileset>_<cell>`: the centre `c` inside, the edges and corners
 * on the border), the water around it, and the path's hexes.
 */
export interface HubGround {
  readonly tileset: string;
  readonly water: string;
  /** The path from the front of the scene to the Gate and the doors: kept clear of props. */
  readonly path: readonly Tile[];
}

export interface HubView {
  readonly name: string;
  readonly gold: number;
  /** The illustration's size, in art pixels: whole cells of the ground. */
  readonly width: number;
  readonly height: number;
  /** Where the centre of tile (0, 0) is in the illustration (x grows West, y North). */
  readonly origin: Point;
  readonly ground: HubGround;
  readonly places: readonly HubPlace[];
  readonly decor: readonly HubDecor[];
  readonly props: readonly HubProp[];
  readonly figures: readonly HubFigure[];
  /** The service entries under the illustration, in reading order; the Gate last. */
  readonly services: readonly HubTarget[];
}

/** One label per target: the building's tap and its service entry name the same screen. */
export function targetLabel(target: HubTarget): string {
  if (target.kind === "gate") return "Gate";
  return target.service[0]!.toUpperCase() + target.service.slice(1);
}

export function sameTarget(a: HubTarget, b: HubTarget): boolean {
  return a.kind === "gate" ? b.kind === "gate" : b.kind === "service" && a.service === b.service;
}

/** A tile's centre in the illustration: the room's conversion, from the hub's origin. */
export function hubPoint(view: Pick<HubView, "origin">, tile: Tile): Point {
  const p = tileToPixel(tile);
  return { x: view.origin.x + p.x, y: view.origin.y + p.y };
}

/** Where a figure's feet stand: below its hex's centre, as in a room (`renderer.ts`). */
export function feetPoint(view: Pick<HubView, "origin">, tile: Tile): Point {
  const c = hubPoint(view, tile);
  return { x: c.x, y: c.y + feetOffset(DEFAULT_FEET) };
}

/** Everything that stands, in one layer: buildings, decor, props, figures. */
export type Standing =
  | { readonly kind: "place"; readonly key: string; readonly base: Point; readonly place: HubPlace }
  | { readonly kind: "decor"; readonly key: string; readonly base: Point; readonly decor: HubDecor }
  | { readonly kind: "prop"; readonly key: string; readonly base: Point; readonly prop: HubProp }
  | {
      readonly kind: "figure";
      readonly key: string;
      readonly base: Point;
      readonly figure: HubFigure;
    };

/**
 * The standing layer back to front: by the y of each base, then by a stable key. A figure in front
 * of a house covers it; one behind is covered.
 */
export function standingOrder(view: HubView): Standing[] {
  const items: Standing[] = [
    ...view.places.map((place): Standing => ({
      kind: "place",
      key: `place:${place.id}`,
      base: hubPoint(view, place.at),
      place,
    })),
    ...view.decor.map((decor): Standing => ({
      kind: "decor",
      key: `decor:${decor.id}`,
      base: hubPoint(view, decor.at),
      decor,
    })),
    ...view.props.map((prop): Standing => ({
      kind: "prop",
      key: `prop:${prop.id}`,
      base: hubPoint(view, prop.at),
      prop,
    })),
    ...view.figures.map((figure): Standing => ({
      kind: "figure",
      key: `figure:${figure.id}`,
      base: feetPoint(view, figure.at),
      figure,
    })),
  ];
  return items.sort((a, b) => a.base.y - b.base.y || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
}

/** The ground's cells: columns and rows of `TILE_WIDTH` over the illustration. */
export function groundCells(view: Pick<HubView, "width" | "height">): {
  columns: number;
  rows: number;
} {
  return { columns: Math.ceil(view.width / TILE_WIDTH), rows: Math.ceil(view.height / TILE_WIDTH) };
}

/** Which cell of the tileset a ground cell takes: `c` inside, an edge or a corner on the border. */
export function groundCell(column: number, row: number, columns: number, rows: number): string {
  const v = row === 0 ? "n" : row === rows - 1 ? "s" : "";
  const h = column === 0 ? "w" : column === columns - 1 ? "e" : "";
  return v + h || "c";
}
