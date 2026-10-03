import { Graphics, Matrix, type Texture } from "pixi.js";
import { TILE_WIDTH, tileToPixel } from "../input/coords";
import { WEDGE } from "./facing";
import {
  GROW,
  type GroundPlan,
  type PlanOptions,
  acrossSide,
  groundPlan,
  hexCorners,
} from "./ground";
import type { Caste, Mark, Profession, Tile, ViewState, ViewStructure, ViewTile } from "./view";

/**
 * Plain shapes: the terrain (the pack has no hex terrain, design/10), and the actors when the atlas
 * is not built. Colour is never the only carrier of a meaning (design/11 *Accessibility*): arcs and
 * marks also differ by shape.
 */

const COLOURS = {
  ground: 0x5d7a3e,
  groundEdge: 0x2a3a1c,
  water: 0x3f8f8d,
  earth: 0xb89b6a,
  lip: 0x1f3a2a,
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
  wall: 0xd8cfb8,
  wallShade: 0x9c947f,
  roof: 0x3b6fb6,
  roofShade: 0x2a4f84,
  decorRoof: 0x8a6a46,
  door: 0x4a3420,
  gate: 0x8a8577,
  gateShade: 0x5c574d,
  bush: 0x3f6a2c,
  bushLight: 0x5f8f3f,
};

export { hexCorners };

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

/** The pack's ground cells the bake fills its layers with (CLI-03g1); none: flat colours. */
export interface GroundTextures {
  readonly grass?: Texture | null;
  readonly water?: Texture | null;
}

export interface TerrainOptions {
  /** The ground of the tiles around the chunk (`groundPlan`'s `around`): lips across chunks. */
  readonly around?: PlanOptions["around"];
  readonly textures?: GroundTextures | null;
}

/**
 * The static layers of one chunk, to be baked into one texture (CLI-03g1, `groundPlan`): the water,
 * the grass (each hex grown by half a pixel so that no seam shows), cut by cells of `TILE_WIDTH`
 * and filled from the atlas's cell at that cell's world position, or flat colours without the
 * atlas; the earth's soft fill; the lip along every land side that faces water; the hex grid on
 * land; rocks on walls not on water; the unrevealed. A wall hex in `covered` (`"x,y"`) draws no
 * rock: a structure stands there as its obstacle object (CLI-03f).
 */
export function drawTerrain(
  tiles: readonly ViewTile[],
  covered: ReadonlySet<string> = new Set(),
  options: TerrainOptions = {},
): Graphics {
  const plan = groundPlan(tiles, { covered, around: options.around });
  const g = new Graphics();
  for (const layer of plan.layers) {
    const texture = options.textures?.[layer.kind] ?? null;
    if (texture) {
      // Global texture space: a point samples the cell's frame at its offset in the cell, so the
      // cells meet on whole art pixels and repeat the cell without a seam.
      for (const piece of layer.pieces) {
        g.poly([...piece.points]).fill({
          texture,
          textureSpace: "global",
          matrix: new Matrix().translate(piece.cell.x, piece.cell.y),
        });
      }
    } else {
      const colour = layer.kind === "water" ? COLOURS.water : COLOURS.ground;
      for (const hex of layer.hexes) g.poly(hexCorners(tileToPixel(hex), GROW)).fill(colour);
    }
  }
  for (const tile of plan.earth) {
    g.poly(earthHex(tile, plan)).fill({ color: COLOURS.earth, alpha: EARTH_ALPHA });
  }
  drawLip(g, plan.lip);
  for (const tile of plan.unrevealed) {
    g.poly(hexCorners(tileToPixel(tile), GROW)).fill(COLOURS.unrevealed);
  }
  for (const tile of plan.unrevealed) {
    g.poly(hexCorners(tileToPixel(tile), -1)).stroke({ width: 1, color: COLOURS.unrevealedEdge });
  }
  for (const tile of plan.grid) {
    g.poly(hexCorners(tileToPixel(tile))).stroke({
      width: 1,
      color: COLOURS.groundEdge,
      alpha: 0.35,
    });
  }
  for (const tile of plan.rocks) drawRock(g, tile);
  return g;
}

/**
 * The earth's fill (CLI-03e's trodden path, proposed, the owner's eye): its alpha over the grass.
 * 0 leaves the path out.
 */
export const EARTH_ALPHA = 0.5;
/** How far an earth hex's side that faces another ground stands inside it, in art px. */
export const EARTH_INSET = 4;

/**
 * An earth hex: each side that faces earth stays on the hex's edge, so the path's hexes join
 * without a gap or an overlap (no double alpha); each other side is moved `EARTH_INSET` inward, so
 * the path reads as trodden ground inside the grass, not as tiles.
 */
function earthHex(tile: Tile, plan: GroundPlan): number[] {
  const earth = new Set(plan.earth.map((t) => `${t.x},${t.y}`));
  const c = tileToPixel(tile);
  const apothem = TILE_WIDTH / 2;
  // Side k's line: points p with p · n_k = apothem - inset, n_k at angle (k + 1)·60°.
  const offsets = [0, 1, 2, 3, 4, 5].map((side) => {
    const next = acrossSide(tile, side);
    return apothem - (earth.has(`${next.x},${next.y}`) ? 0 : EARTH_INSET);
  });
  const points: number[] = [];
  for (let k = 0; k < 6; k++) {
    // Corner k + 1 lies on sides k and k + 1.
    const a = ((k + 1) * Math.PI) / 3;
    const b = ((k + 2) * Math.PI) / 3;
    const da = offsets[k]!;
    const db = offsets[(k + 1) % 6]!;
    const det = Math.cos(a) * Math.sin(b) - Math.sin(a) * Math.cos(b);
    points.push(
      c.x + (da * Math.sin(b) - db * Math.sin(a)) / det,
      c.y + (db * Math.cos(a) - da * Math.cos(b)) / det,
    );
  }
  return points;
}

/** The lip: a darker line on the land's side of every land–water edge (lot 1; lot 2's foam). */
export const LIP = { width: 3, alpha: 0.55 } as const;

function drawLip(g: Graphics, lip: GroundPlan["lip"]): void {
  if (lip.length === 0) return;
  const sides = new Map<string, { tile: Tile; sides: Set<number> }>();
  for (const { tile, side } of lip) {
    const key = `${tile.x},${tile.y}`;
    let entry = sides.get(key);
    if (!entry) sides.set(key, (entry = { tile, sides: new Set() }));
    entry.sides.add(side);
  }
  for (const { tile, sides: facing } of sides.values()) {
    // The hex shrunk so that its sides stand half the lip's width inside the hex's sides: a
    // mitred join then reaches the hex's corner exactly, never past it.
    const inner = hexCorners(tileToPixel(tile), -LIP.width / 2 / Math.cos(Math.PI / 6));
    const corner = (k: number) => [inner[2 * (k % 6)]!, inner[2 * (k % 6) + 1]!] as const;
    if (facing.size === 6) {
      g.poly(inner);
      continue;
    }
    // Each run of consecutive sides facing water, as one line from its first corner to its last.
    for (const first of facing) {
      if (facing.has((first + 5) % 6)) continue;
      let last = first;
      while (facing.has((last + 1) % 6)) last += 1;
      g.moveTo(...corner(first));
      for (let k = first + 1; k <= last + 1; k++) g.lineTo(...corner(k));
    }
  }
  g.stroke({ width: LIP.width, color: COLOURS.lip, alpha: LIP.alpha, join: "miter" });
}

/**
 * A structure as a shape, when the atlas has no still for it (CLI-03e's shapes, CLI-03f): a
 * building at its native size, walls, a roof and a door, the Gate as an arch; a prop as a bush.
 * Base at (0, 0).
 */
export function drawStructure(structure: ViewStructure): Graphics {
  const { width: w, height: h } = structure;
  const g = new Graphics();
  if (structure.kind === "prop") {
    g.ellipse(0, 0, 20, 5).fill({ color: 0x000000, alpha: 0.25 });
    g.circle(0, -16, 16).fill(COLOURS.bush);
    g.circle(-5, -21, 7).fill(COLOURS.bushLight);
    return g;
  }
  g.ellipse(0, 0, w * 0.55, 6).fill({ color: 0x000000, alpha: 0.25 });
  if (structure.shape === "gate") {
    const pillar = Math.max(6, w * 0.22);
    g.rect(-w / 2, -h, pillar, h).fill(COLOURS.gate);
    g.rect(w / 2 - pillar, -h, pillar, h).fill(COLOURS.gate);
    g.rect(-w / 2, -h, w, h * 0.22).fill(COLOURS.gateShade);
    g.rect(-w / 2 + pillar, -h * 0.78, w - 2 * pillar, h * 0.78).fill({
      color: 0x000000,
      alpha: 0.35,
    });
    return g;
  }
  const roof = structure.shape === "decor" ? COLOURS.decorRoof : COLOURS.roof;
  const wall = h * 0.58;
  g.rect(-w / 2, -wall, w, wall).fill(COLOURS.wall);
  g.rect(-w / 2, -wall * 0.25, w, wall * 0.25).fill(COLOURS.wallShade);
  g.poly([-w / 2 - 4, -wall, w / 2 + 4, -wall, 0, -h]).fill(roof);
  g.poly([0, -h, w / 2 + 4, -wall, 0, -wall]).fill(COLOURS.roofShade);
  const door = Math.max(6, w * 0.16);
  g.rect(-door / 2, -wall * 0.5, door, wall * 0.5).fill(COLOURS.door);
  return g;
}

/** What the overlay draws, as tiles: kept apart from the drawing so that tests can read it. */
export interface OverlayPlan {
  /** Revealed tiles beyond sight: seen before, dimmed. */
  readonly dimmed: readonly Tile[];
  /** The selected actor's rear-side tiles: a tint and a ring. */
  readonly rings: readonly Tile[];
  /** The selected actor's back tile: a tint and a cross. */
  readonly crosses: readonly Tile[];
  readonly path: readonly Tile[];
  readonly selected: Tile | null;
}

export function overlayPlan(view: ViewState): OverlayPlan {
  const inSight = new Set(view.sight.map((t) => `${t.x},${t.y}`));
  return {
    dimmed: view.tiles.filter((t) => t.kind !== "unrevealed" && !inSight.has(`${t.x},${t.y}`)),
    rings: view.arcs?.rearSide ?? [],
    crosses: view.arcs?.back ?? [],
    path: view.path,
    selected: view.selectedTile,
  };
}

/**
 * What changes with the view but does not move: beyond sight dimmed, the planned path, the
 * selected tile, the selected actor's rear-side (a tint and a ring) and back (a tint and a cross).
 */
export function drawOverlay(g: Graphics, view: ViewState): void {
  const plan = overlayPlan(view);
  g.clear();
  for (const tile of plan.dimmed) {
    g.poly(hexCorners(tileToPixel(tile), 0.5)).fill({ color: COLOURS.dim, alpha: 0.45 });
  }
  drawArcs(g, plan);
  drawGhosts(g, plan.path);
  if (plan.selected) {
    g.poly(hexCorners(tileToPixel(plan.selected), -2)).stroke({
      width: 3,
      color: COLOURS.selected,
    });
  }
}

/** The ghost markers of a planned path (design/11 *The queue*); the renderer fades dropped ones. */
export function drawGhosts(g: Graphics, path: readonly Tile[]): Graphics {
  for (const tile of path) {
    const c = tileToPixel(tile);
    g.circle(c.x, c.y, 5).fill({ color: COLOURS.path, alpha: 0.75 });
  }
  return g;
}

function drawArcs(g: Graphics, plan: OverlayPlan): void {
  for (const tile of plan.rings) {
    const c = tileToPixel(tile);
    g.poly(hexCorners(c, -1)).fill({ color: COLOURS.rearSide, alpha: 0.35 });
    g.circle(c.x, c.y, 11).stroke({ width: 4, color: COLOURS.rearSide });
  }
  for (const tile of plan.crosses) {
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
