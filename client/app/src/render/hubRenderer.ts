import { Container, Graphics, Rectangle, Sprite, Texture } from "pixi.js";
import { HEX_RADIUS, type Point, TILE_WIDTH } from "../input/coords";
import { type HubFit, type Size, hubFit } from "../input/hubTaps";
import { HUB_STEP_MS } from "../input/hubWalk";
import { isMirrored } from "./facing";
import {
  type HubPlace,
  type HubView,
  type HubWalkerView,
  type Standing,
  feetPoint,
  groundCell,
  groundCells,
  hubPoint,
  standingOrder,
} from "./hubView";
import type { Surface } from "./renderer";
import { type ScaleMode, sharpFactor } from "./scaling";
import { type FrameClient, type FrameHost, FrameScheduler, type FrameStats } from "./scheduler";
import { drawBody } from "./shapes";
import type { SpriteArt, SpriteLibrary } from "./sprites";

/** The animation name of a still in the atlas (`tools/art`, `STILL_ANIM`): buildings, props, tiles. */
export const STILL = "still";

/**
 * The path's hexes are drawn as a trodden earth over the grass (CLI-03e, proposed, the owner's
 * eye): the tileset has no path cell. 0 leaves the path out; it stays clear of props either way.
 */
export const PATH_ALPHA = 0.5;
/** A faint outline of the hex grid over the ground, for the owner's eye; off by default. */
export const SHOW_GRID = false;
/** The tapped hex's marker while a walk lasts (CLI-03f, the owner's eye): a faint light hex. */
export const HUB_TARGET_ALPHA = 0.28;

const COLOURS = {
  water: 0x3f8f8d,
  grass: 0x5d7a3e,
  grassEdge: 0x2a3a1c,
  path: 0xb89b6a,
  wall: 0xd8cfb8,
  wallShade: 0x9c947f,
  roof: 0x3b6fb6,
  roofShade: 0x2a4f84,
  decorRoof: 0x8a6a46,
  door: 0x4a3420,
  gate: 0x8a8577,
  gateShade: 0x5c574d,
};

/**
 * Draws a `HubView` on demand (CLI-03c, CLI-03e): the water around the hub, the ground baked once
 * into one texture, then one standing layer (buildings, decor, props, figures) sorted by the y of
 * each base. Every piece is at its native size: the scene is drawn with **one** factor, the fit of
 * `input/hubTaps.ts` in the room's scale modes. Only the player's adventurer moves (CLI-03f): a
 * step tweens it from hex to hex with its `move` frames, and asks for frames until the step ends.
 * Otherwise a frame is drawn when the view, the atlas or the size changes, and none else: no
 * ticker, no idle frame, no timer. A walk never bakes the ground again. The labels are the page's.
 */
export class HubRenderer implements FrameClient {
  readonly scheduler: FrameScheduler;
  /** The water behind the hub, over the whole zone, in CSS pixels. */
  private readonly backdrop = new Container();
  /** The hub in art pixels: the ground's sprite, then the standing layer. */
  private readonly scene = new Container();
  private readonly groundSprite = new Sprite(Texture.EMPTY);
  private readonly standing = new Container();
  /** What the ground is drawn from, baked into `groundSprite`; null when it needs drawing again. */
  private groundSource: Container | null = null;
  private groundResolution = 0;
  /** `sharp`: the scene baked at an integer scale, drawn down linearly. */
  private readonly sharpSprite = new Sprite(Texture.EMPTY);
  private view: HubView | null = null;
  private zone: Size = { width: 1, height: 1 };
  private library: SpriteLibrary | null;
  private readonly mode: ScaleMode;
  /** Ground bakes since the start: one per hub, atlas and size (AC-4). */
  bakes = 0;
  /** The player's adventurer in the standing layer, and the tapped hex's marker under it. */
  private walkerNode: WalkerNode | null = null;
  private readonly marker = new Graphics();
  private readonly stepMs: number;

  constructor(
    private readonly surface: Pick<Surface, "stage" | "render" | "bake" | "resolution"> &
      Partial<Pick<Surface, "maxTextureSize">>,
    private readonly host: FrameHost,
    options: {
      library?: SpriteLibrary | null;
      mode?: ScaleMode;
      /** A step's tween, in ms: the walk's pace (`HUB_STEP_MS`). */
      stepMs?: number;
      onDraw?: (stats: FrameStats) => void;
    } = {},
  ) {
    this.library = options.library ?? null;
    this.mode = options.mode ?? "continuous";
    this.stepMs = options.stepMs ?? HUB_STEP_MS;
    this.standing.sortableChildren = true;
    this.scheduler = new FrameScheduler(host, this, options.onDraw);
    this.scene.addChild(this.groundSprite, this.standing);
    surface.stage.addChild(this.backdrop);
    surface.stage.addChild(this.mode === "sharp" ? this.sharpSprite : this.scene);
  }

  /**
   * A new view rebuilds the scene; a view that differs only by its walker moves the walker, and
   * the rest (the ground's bake above all) stays as it is.
   */
  setView(view: HubView): void {
    const previous = this.view;
    this.view = view;
    if (previous && sameScene(previous, view)) {
      this.syncWalker(view.walker ?? null);
      this.scheduler.invalidate();
      return;
    }
    this.rebuild();
  }

  setLibrary(library: SpriteLibrary | null): void {
    this.library = library;
    this.rebuild();
  }

  resize(zone: Size): void {
    this.zone = zone;
    this.place();
    this.scheduler.invalidate();
  }

  /** The fit the scene is drawn with: the tap targets use the same (`input/hubTaps.ts`). */
  fit(): HubFit | null {
    return this.view
      ? hubFit(this.view, this.zone, { mode: this.mode, resolution: this.surface.resolution })
      : null;
  }

  /** Whether a building is drawn from the atlas (else a labelled shape: the label is the page's). */
  drawnFromAtlas(place: HubPlace): boolean {
    return this.still(place.building) !== null;
  }

  /** The scene, in art pixels: for tests (its children are the ground and the standing layer). */
  sceneRoot(): Container {
    return this.scene;
  }

  /** While a step tweens: the walker's position and `move` frame at `now`, and the next frame. */
  advance(now: number): { changed: boolean; next: number | null } {
    const node = this.walkerNode;
    if (!node?.step) return { changed: false, next: null };
    const { from, to, start } = node.step;
    const t = Math.min(1, Math.max(0, (now - start) / this.stepMs));
    const k = 1 - (1 - t) ** 3;
    node.container.position.set(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k);
    node.container.zIndex = node.container.y;
    if (t >= 1) node.step = null;
    this.showWalkerFrame(node, now);
    return { changed: true, next: node.step ? now : null };
  }

  /** Whether the walker's step is being drawn: for tests. */
  stepping(): boolean {
    return this.walkerNode?.step != null;
  }

  draw(): void {
    this.bakeGround();
    if (this.mode === "sharp") this.bakeSharp();
    this.surface.render();
  }

  destroy(): void {
    this.scheduler.destroy();
    this.dropGround();
    if (this.sharpSprite.texture !== Texture.EMPTY) this.sharpSprite.texture.destroy(true);
    this.backdrop.destroy({ children: true });
    if (!this.marker.parent) this.marker.destroy();
    this.sharpSprite.destroy();
    this.scene.destroy({ children: true });
  }

  private rebuild(): void {
    this.standing.removeChild(this.marker);
    for (const child of this.standing.removeChildren()) child.destroy({ children: true });
    this.walkerNode = null;
    this.dropGround();
    const view = this.view;
    if (view) {
      this.groundSource = this.drawGround(view);
      for (const item of standingOrder(view)) {
        if (item.kind === "walker") continue; // drawn by `syncWalker`
        const node = this.standingNode(item);
        if (!node) continue;
        // Sorted by the base's y; the standing order's insertion keeps the key's tie-break.
        node.zIndex = item.base.y;
        this.standing.addChild(node);
      }
      this.syncWalker(view.walker ?? null);
    }
    this.place();
    this.scheduler.invalidate();
  }

  /**
   * The walker drawn where the view puts it: a step to an adjacent hex tweens from where it is
   * drawn; anything else (the first drawing, a jump) puts it there at once. The marker follows the
   * walk's target.
   */
  private syncWalker(walker: HubWalkerView | null): void {
    const view = this.view!;
    this.marker.clear();
    if (walker?.target) {
      hexagon(this.marker, hubPoint(view, walker.target)).fill({
        color: 0xffffff,
        alpha: HUB_TARGET_ALPHA,
      });
      if (!this.marker.parent) this.standing.addChild(this.marker);
    } else if (this.marker.parent) {
      this.standing.removeChild(this.marker);
    }
    // Under everything that stands: it is on the ground.
    this.marker.zIndex = -Infinity;
    let node = this.walkerNode;
    if (!walker) {
      node?.container.destroy({ children: true });
      this.walkerNode = null;
      return;
    }
    const feet = feetPoint(view, walker.at);
    if (!node || node.profession !== walker.profession) {
      node?.container.destroy({ children: true });
      node = this.createWalker(walker);
      node.container.position.set(feet.x, feet.y);
      this.walkerNode = node;
      this.standing.addChild(node.container);
    } else if (node.at.x !== walker.at.x || node.at.y !== walker.at.y) {
      const from = { x: node.container.x, y: node.container.y };
      const adjacent = Math.hypot(feet.x - from.x, feet.y - from.y) < TILE_WIDTH * 1.01;
      node.step = adjacent ? { from, to: feet, start: this.host.now() } : null;
      if (!adjacent) node.container.position.set(feet.x, feet.y);
    }
    node.at = walker.at;
    node.container.zIndex = node.container.y;
    node.body.scale.x = (isMirrored(walker.facing) ? -1 : 1) * Math.abs(node.body.scale.x);
    this.showWalkerFrame(node, this.host.now());
    this.standing.sortChildren();
  }

  private createWalker(walker: HubWalkerView): WalkerNode {
    const container = new Container();
    const art = this.library?.get(walker.profession) ?? null;
    const texture = art?.animations.idle?.textures[0];
    let body: Container;
    let sprite: Sprite | null = null;
    if (art && texture) {
      sprite = this.sprite(texture, 0, 0);
      // As in a room: the sprite's own scale from sprites.json (1 by default).
      sprite.scale.set(art.scale, art.scale);
      body = sprite;
    } else {
      body = drawBody(walker.profession);
    }
    container.addChild(body);
    return {
      profession: walker.profession,
      at: walker.at,
      container,
      body,
      sprite,
      art: sprite ? art : null,
      step: null,
      frame: "",
    };
  }

  /** Its `move` frames while it steps, its idle frame 0 when it stands, as the present figures. */
  private showWalkerFrame(node: WalkerNode, now: number): void {
    if (!node.sprite || !node.art) return;
    const move = node.step ? node.art.animations.move : undefined;
    const animation = move ?? node.art.animations.idle;
    const count = animation?.textures.length ?? 1;
    const index = move ? Math.floor((now * move.fps) / 1000 + 1e-6) % count : 0;
    const key = `${move ? "move" : "idle"}/${index}`;
    if (key === node.frame) return;
    node.frame = key;
    const texture = animation?.textures[index];
    if (texture) node.sprite.texture = texture;
  }

  private place(): void {
    const fit = this.fit();
    if (!fit) return;
    // `sharp` bakes the scene as a root free of any transform (as the room's offscreen pass); only
    // the sprite that shows the bake is fitted.
    const fitted = this.mode === "sharp" ? this.sharpSprite : this.scene;
    fitted.scale.set(fit.scale);
    fitted.position.set(fit.x, fit.y);
    for (const child of this.backdrop.removeChildren()) child.destroy();
    const water = this.still(this.view!.ground.water);
    const fill = water ? new Sprite(water) : new Graphics().rect(0, 0, 1, 1).fill(COLOURS.water);
    // A flat colour stretched over the zone: no art pixel to keep (the tile is one colour).
    fill.width = this.zone.width;
    fill.height = this.zone.height;
    this.backdrop.addChild(fill);
  }

  private still(name: string): Texture | null {
    return this.library?.get(name)?.animations[STILL]?.textures[0] ?? null;
  }

  /** A standing piece at native size: a sprite with its base on its point, or a shape. */
  private standingNode(item: Exclude<Standing, { kind: "walker" }>): Container | null {
    if (item.kind === "figure") {
      const { figure } = item;
      const art = this.library?.get(figure.profession);
      const texture = art?.animations.idle?.textures[0];
      const mirror = figure.facing === "left" ? -1 : 1;
      if (art && texture) {
        // As in a room: the sprite's own scale from sprites.json (1 by default), mirrored.
        const sprite = this.sprite(texture, item.base.x, item.base.y);
        sprite.scale.set(mirror * art.scale, art.scale);
        return sprite;
      }
      const body = drawBody(figure.profession);
      body.position.set(item.base.x, item.base.y);
      body.scale.set(mirror, 1);
      return body;
    }
    const name =
      item.kind === "place"
        ? item.place.building
        : item.kind === "decor"
          ? item.decor.building
          : item.prop.sprite;
    const texture = this.still(name);
    if (texture) {
      const sprite = this.sprite(texture, item.base.x, item.base.y);
      if (item.kind === "prop" && item.prop.mirror) sprite.scale.x = -1;
      return sprite;
    }
    if (item.kind === "place") return drawBuilding(item.place, item.base.x, item.base.y);
    if (item.kind === "decor") {
      const { width, height } = item.decor;
      return drawHouse(item.base.x, item.base.y, width, height, COLOURS.decorRoof);
    }
    return null; // a prop needs the atlas
  }

  private sprite(texture: Texture, x: number, y: number): Sprite {
    const sprite = new Sprite(texture);
    const anchor = texture.defaultAnchor;
    sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
    sprite.position.set(x, y);
    return sprite;
  }

  /** The ground's source: tileset cells over the illustration, the path, and the grid if shown. */
  private drawGround(view: HubView): Container {
    const root = new Container();
    const { columns, rows } = groundCells(view);
    const centre = this.still(`${view.ground.tileset}_c`);
    if (centre) {
      for (let row = 0; row < rows; row++) {
        for (let column = 0; column < columns; column++) {
          const cell = groundCell(column, row, columns, rows);
          const texture = this.still(`${view.ground.tileset}_${cell}`) ?? centre;
          const sprite = new Sprite(texture);
          sprite.anchor.set(0, 0);
          sprite.position.set(column * TILE_WIDTH, row * TILE_WIDTH);
          root.addChild(sprite);
        }
      }
    } else {
      const g = new Graphics();
      g.rect(0, 0, view.width, view.height).fill(COLOURS.grass);
      g.rect(0.5, 0.5, view.width - 1, view.height - 1).stroke({
        width: 1,
        color: COLOURS.grassEdge,
      });
      root.addChild(g);
    }
    const marks = new Graphics();
    if (PATH_ALPHA > 0) {
      for (const tile of view.ground.path) {
        hexagon(marks, hubPoint(view, tile));
        marks.fill({ color: COLOURS.path, alpha: PATH_ALPHA });
      }
    }
    if (SHOW_GRID) {
      for (let row = -1; row <= rows + 1; row++) {
        for (let column = -1; column <= columns + 1; column++) {
          hexagon(marks, hubPoint(view, { x: column, y: row }));
          marks.stroke({ width: 1, color: 0x000000, alpha: 0.12 });
        }
      }
    }
    root.addChild(marks);
    return root;
  }

  /** The ground into one texture, once per hub, atlas and size: a frame draws one sprite of it. */
  private bakeGround(): void {
    const view = this.view;
    const fit = this.fit();
    if (!view || !fit || !this.groundSource) return;
    const frame = new Rectangle(0, 0, view.width, view.height);
    const resolution = this.bakeResolution(fit, frame);
    if (resolution === this.groundResolution && this.groundSprite.texture !== Texture.EMPTY) return;
    const old = this.groundSprite.texture;
    this.groundSprite.texture = this.surface.bake(this.groundSource, frame, resolution);
    if (old !== Texture.EMPTY) old.destroy(true);
    this.groundResolution = resolution;
    this.bakes += 1;
  }

  /**
   * Texels per art pixel: what the scene is drawn at (the canvas, or `sharp`'s integer), capped by
   * the GPU's texture size.
   */
  private bakeResolution(fit: HubFit, frame: Rectangle): number {
    const wanted =
      this.mode === "sharp"
        ? sharpFactor(fit.scale, this.surface.resolution).n
        : fit.scale * this.surface.resolution;
    const max = (this.surface.maxTextureSize ?? 4096) / Math.max(frame.width, frame.height, 1);
    return Math.min(wanted, max);
  }

  /**
   * `sharp` ("sharp bilinear", `render/scaling.ts`): the scene drawn nearest-neighbour at the
   * integer `n` canvas pixels per art pixel into a texture, which is drawn down to the fit with
   * linear filtering.
   */
  private bakeSharp(): void {
    const view = this.view;
    const fit = this.fit();
    if (!view || !fit) return;
    const frame = new Rectangle(0, 0, view.width, view.height);
    const old = this.sharpSprite.texture;
    // The scene is never on the stage in this mode and keeps an identity transform: the frame is
    // in its own art pixels.
    const texture = this.surface.bake(this.scene, frame, this.bakeResolution(fit, frame));
    texture.source.scaleMode = "linear";
    this.sharpSprite.texture = texture;
    if (old !== Texture.EMPTY) old.destroy(true);
  }

  private dropGround(): void {
    this.groundSource?.destroy({ children: true });
    this.groundSource = null;
    if (this.groundSprite.texture !== Texture.EMPTY) this.groundSprite.texture.destroy(true);
    this.groundSprite.texture = Texture.EMPTY;
    this.groundResolution = 0;
  }
}

interface WalkerNode {
  readonly profession: HubWalkerView["profession"];
  /** The hex it was last put on. */
  at: HubWalkerView["at"];
  readonly container: Container;
  /** The sprite or the shape, mirrored for the West facings. */
  readonly body: Container;
  readonly sprite: Sprite | null;
  readonly art: SpriteArt | null;
  /** The step being drawn, from where it was drawn to its new hex's feet, in art pixels. */
  step: { from: Point; to: Point; start: number } | null;
  frame: string;
}

/** Whether two views draw the same scene: everything but the walker is the same data. */
function sameScene(a: HubView, b: HubView): boolean {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  keys.delete("walker");
  for (const k of keys) {
    if (a[k as keyof HubView] !== b[k as keyof HubView]) return false;
  }
  return true;
}

/** A pointy-top hexagon around a point, as the room draws its tiles. */
function hexagon(g: Graphics, c: { x: number; y: number }): Graphics {
  const points: number[] = [];
  for (let i = 0; i < 6; i++) {
    const angle = (Math.PI / 180) * (60 * i - 90);
    points.push(c.x + HEX_RADIUS * Math.cos(angle), c.y + HEX_RADIUS * Math.sin(angle));
  }
  return g.poly(points);
}

/** A building as a shape at its native size: walls, a roof, a door; the Gate as an arch. */
function drawBuilding(place: HubPlace, x: number, y: number): Graphics {
  const { width: w, height: h } = place;
  if (place.target.kind !== "gate") return drawHouse(x, y, w, h, COLOURS.roof);
  const g = new Graphics();
  g.ellipse(x, y, w * 0.55, 6).fill({ color: 0x000000, alpha: 0.25 });
  const pillar = Math.max(6, w * 0.22);
  g.rect(x - w / 2, y - h, pillar, h).fill(COLOURS.gate);
  g.rect(x + w / 2 - pillar, y - h, pillar, h).fill(COLOURS.gate);
  g.rect(x - w / 2, y - h, w, h * 0.22).fill(COLOURS.gateShade);
  g.rect(x - w / 2 + pillar, y - h * 0.78, w - 2 * pillar, h * 0.78).fill({
    color: 0x000000,
    alpha: 0.35,
  });
  return g;
}

function drawHouse(x: number, y: number, w: number, h: number, roof: number): Graphics {
  const g = new Graphics();
  g.ellipse(x, y, w * 0.55, 6).fill({ color: 0x000000, alpha: 0.25 });
  const wall = h * 0.58;
  g.rect(x - w / 2, y - wall, w, wall).fill(COLOURS.wall);
  g.rect(x - w / 2, y - wall * 0.25, w, wall * 0.25).fill(COLOURS.wallShade);
  g.poly([x - w / 2 - 4, y - wall, x + w / 2 + 4, y - wall, x, y - h]).fill(roof);
  g.poly([x, y - h, x + w / 2 + 4, y - wall, x, y - wall]).fill(COLOURS.roofShade);
  const door = Math.max(6, w * 0.16);
  g.rect(x - door / 2, y - wall * 0.5, door, wall * 0.5).fill(COLOURS.door);
  return g;
}
