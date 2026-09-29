import { Graphics } from "pixi.js";
import { HEX_RADIUS, type Point, tileToPixel } from "../input/coords";
import { WEDGE } from "./facing";
import type { Caste, Mark, Profession, Tile, ViewArcs, ViewState, ViewTile } from "./view";

/**
 * Plain shapes: the terrain (the pack has no hex terrain, design/10), and the actors when the atlas
 * is not built. Colour is never the only carrier of a meaning (design/11 *Accessibility*): arcs and
 * marks also differ by shape.
 */

const COLOURS = {
  ground: 0x5d7a3e,
  groundEdge: 0x2a3a1c,
  rock: 0x8a8577,
  rockShade: 0x5c574d,
  rockLight: 0xb3ad9c,
  unrevealed: 0x131318,
  unrevealedEdge: 0x24242c,
  dim: 0x000000,
  rearSide: 0xf59e0b,
  back: 0xef4444,
  path: 0xffffff,
  selected: 0xffffff,
  wedgeAdventurer: 0xffffff,
  wedgeGoblin: 0xffd166,
};

/** The six corners of a pointy-top hex around a centre, `grow` pixels out. */
export function hexCorners(centre: Point, grow = 0): number[] {
  const points: number[] = [];
  for (let k = 0; k < 6; k++) {
    const angle = Math.PI / 6 + (k * Math.PI) / 3;
    points.push(
      centre.x + (HEX_RADIUS + grow) * Math.cos(angle),
      centre.y + (HEX_RADIUS + grow) * Math.sin(angle),
    );
  }
  return points;
}

/** A rock, the obstacle object of a wall tile (design/10); two outlines, chosen by the tile. */
function drawRock(g: Graphics, tile: Tile): void {
  const c = tileToPixel(tile);
  const variant = (tile.x + 2 * tile.y) % 2;
  const outline =
    variant === 0
      ? [-22, 8, -18, -10, -6, -20, 10, -18, 22, -6, 24, 10, 8, 18, -12, 18]
      : [-24, 10, -20, -4, -10, -16, 6, -22, 20, -12, 22, 6, 12, 18, -10, 20];
  const at = (points: number[]) => points.map((v, i) => v + (i % 2 === 0 ? c.x : c.y));
  g.poly(at(outline)).fill(COLOURS.rockShade);
  g.poly(at(outline.map((v, i) => (i % 2 === 1 ? v - 4 : v * 0.86)))).fill(COLOURS.rock);
  g.poly(at([-8, -14, 6, -16, 12, -8, -2, -6])).fill(COLOURS.rockLight);
}

/**
 * The static layers, to be baked into one texture: a continuous ground (each hex grown by half a
 * pixel so that no seam shows), rocks on walls, the hex grid, and the unrevealed.
 */
export function drawTerrain(tiles: readonly ViewTile[]): Graphics {
  const g = new Graphics();
  for (const tile of tiles) {
    const centre = tileToPixel(tile);
    const colour = tile.kind === "unrevealed" ? COLOURS.unrevealed : COLOURS.ground;
    g.poly(hexCorners(centre, 0.5)).fill(colour);
  }
  for (const tile of tiles) {
    const centre = tileToPixel(tile);
    if (tile.kind === "unrevealed") {
      g.poly(hexCorners(centre, -1)).stroke({ width: 1, color: COLOURS.unrevealedEdge });
    } else {
      g.poly(hexCorners(centre)).stroke({ width: 1, color: COLOURS.groundEdge, alpha: 0.35 });
    }
  }
  for (const tile of tiles) if (tile.kind === "wall") drawRock(g, tile);
  return g;
}

/**
 * What changes with the view but does not move: beyond sight dimmed, the planned path, the
 * selected tile, the selected actor's rear-side (a tint and a ring) and back (a tint and a cross).
 */
export function drawOverlay(g: Graphics, view: ViewState): void {
  g.clear();
  for (const tile of view.tiles) {
    if (tile.seen === "before" && tile.kind !== "unrevealed") {
      g.poly(hexCorners(tileToPixel(tile), 0.5)).fill({ color: COLOURS.dim, alpha: 0.45 });
    }
  }
  if (view.arcs) drawArcs(g, view.arcs);
  for (const tile of view.path) {
    const c = tileToPixel(tile);
    g.circle(c.x, c.y, 5).fill({ color: COLOURS.path, alpha: 0.75 });
  }
  if (view.selectedTile) {
    g.poly(hexCorners(tileToPixel(view.selectedTile), -2)).stroke({
      width: 3,
      color: COLOURS.selected,
    });
  }
}

function drawArcs(g: Graphics, arcs: ViewArcs): void {
  for (const tile of arcs.rearSide) {
    const c = tileToPixel(tile);
    g.poly(hexCorners(c, -1)).fill({ color: COLOURS.rearSide, alpha: 0.35 });
    g.circle(c.x, c.y, 11).stroke({ width: 4, color: COLOURS.rearSide });
  }
  for (const tile of arcs.back) {
    const c = tileToPixel(tile);
    g.poly(hexCorners(c, -1)).fill({ color: COLOURS.back, alpha: 0.4 });
    g.moveTo(c.x - 11, c.y - 11)
      .lineTo(c.x + 11, c.y + 11)
      .moveTo(c.x + 11, c.y - 11)
      .lineTo(c.x - 11, c.y + 11)
      .stroke({ width: 5, color: COLOURS.back });
  }
}

/** The facing wedge, pointing right; the actor's container rotates it. */
export function drawWedge(adventurer: boolean): Graphics {
  const colour = adventurer ? COLOURS.wedgeAdventurer : COLOURS.wedgeGoblin;
  return new Graphics()
    .poly([...WEDGE])
    .fill({ color: colour, alpha: 0.9 })
    .stroke({ width: 1, color: 0x000000, alpha: 0.6 });
}

/** A shape's height in art pixels, feet at 0: hobgoblin tallest, runt smallest. */
export const SHAPE_HEIGHT: Readonly<Record<Caste | Profession, number>> = {
  runt: 34,
  skirmisher: 42,
  slinger: 38,
  shaman: 44,
  hobgoblin: 60,
  vanguard: 50,
  warden: 50,
  cleric: 50,
  arcanist: 50,
};

const SHAPE_COLOUR: Readonly<Record<Caste | Profession, number>> = {
  runt: 0x7fa650,
  skirmisher: 0x9c7a3c,
  slinger: 0xb08d57,
  shaman: 0x8e5ea2,
  hobgoblin: 0x4f6b35,
  vanguard: 0x3b82f6,
  warden: 0x2fa37a,
  cleric: 0xe2c044,
  arcanist: 0xa66cf0,
};

/**
 * A body drawn as a shape, facing right (a nose on its right side, so that the mirror shows),
 * feet at (0, 0). Castes differ by outline, not only by colour.
 */
export function drawBody(who: Caste | Profession): Graphics {
  const h = SHAPE_HEIGHT[who];
  const w = Math.round(h * 0.6);
  const colour = SHAPE_COLOUR[who];
  const g = new Graphics();
  g.ellipse(0, 0, w * 0.55, 5).fill({ color: 0x000000, alpha: 0.3 });
  switch (who) {
    case "skirmisher":
      g.poly([-w / 2, 0, w / 2, 0, 0, -h]).fill(colour);
      break;
    case "slinger":
      g.poly([0, 0, w / 2, -h / 2, 0, -h, -w / 2, -h / 2]).fill(colour);
      break;
    case "shaman":
      g.poly([-w / 2, 0, w / 2, 0, w / 2, -h * 0.6, 0, -h, -w / 2, -h * 0.6]).fill(colour);
      break;
    case "hobgoblin":
      g.roundRect(-w / 2, -h, w, h, 6).fill(colour);
      break;
    case "runt":
      g.circle(0, -h / 2, h / 2).fill(colour);
      break;
    default:
      g.roundRect(-w / 2, -h, w, h, w / 2).fill(colour);
      g.rect(-w / 2 + 3, -h * 0.55, w - 6, 4).fill(0xffffff);
  }
  g.poly([w / 2 - 2, -h * 0.72, w / 2 + 7, -h * 0.64, w / 2 - 2, -h * 0.56]).fill(0xffffff);
  g.circle(w * 0.18, -h * 0.72, 2.5).fill(0x111111);
  return g;
}

/** The mark over a goblin (design/11): Z asleep, ! alerted, crossed blades engaged, ⇇ fleeing. */
export function drawMark(mark: Mark): Graphics {
  const g = new Graphics();
  g.circle(0, 0, 10).fill({ color: 0x000000, alpha: 0.55 });
  switch (mark) {
    case "asleep":
      g.moveTo(-5, -5)
        .lineTo(5, -5)
        .lineTo(-5, 5)
        .lineTo(5, 5)
        .stroke({ width: 2.5, color: 0x9fd3ff });
      break;
    case "alerted":
      g.rect(-1.5, -7, 3, 9).fill(0xffd23f);
      g.circle(0, 5, 1.8).fill(0xffd23f);
      break;
    case "engaged":
      g.moveTo(-6, -6)
        .lineTo(6, 6)
        .moveTo(6, -6)
        .lineTo(-6, 6)
        .stroke({ width: 3, color: 0xff4d4d });
      break;
    case "fleeing":
      g.moveTo(1, -6).lineTo(-5, 0).lineTo(1, 6).moveTo(7, -6).lineTo(1, 0).lineTo(7, 6);
      g.stroke({ width: 2.5, color: 0xe5e5e5 });
      break;
  }
  return g;
}

/** The idle "animation" of a shape: a bob of a few pixels, as a pixel-art idle at 12 fps. */
export const SHAPE_IDLE = { fps: 12, offsets: [0, 0, -1, -2, -2, -1] } as const;
