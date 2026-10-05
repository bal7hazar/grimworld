import { Container, Graphics, Matrix, Rectangle, RenderTexture, Sprite, Texture } from "pixi.js";
import {
  type Camera,
  HEX_RADIUS,
  type Point,
  TILE_WIDTH,
  type Viewport,
  fitScale,
  screenToWorld,
  tileToPixel,
} from "../input/coords";
import { facingRotation, isMirrored } from "./facing";
import { type ScaleMode, isWhole, sharpFactor, snapScale } from "./scaling";
import {
  type FrameClient,
  type FrameHost,
  FrameScheduler,
  type FrameStats,
  type Advance,
} from "./scheduler";
import {
  SHAPE_HEIGHT,
  SHAPE_IDLE,
  drawBody,
  drawFoam,
  drawGhosts,
  drawMark,
  drawOverlay,
  drawStructure,
  drawTerrain,
  drawUnrevealed,
  drawWedge,
  DIM_ALPHA,
  type GroundTextures,
} from "./shapes";
import {
  type Box,
  FOAM_REACH,
  type FoamPiece,
  chunkFrame,
  groundOf,
  hexCorners,
  hexesWithin,
  isRock,
  voidFoam,
  voidHole,
  waterFoam,
} from "./ground";
import { FOAM_FPS, FoamMesh, type WaterMode, overlaps, pageWater } from "./foam";
import { type FigureNode, figureFrame, figurePhase, nextFrameAt, spriteBounds } from "./figures";
import { OBSTACLES, type Obstacle, obstacleOf } from "./obstacles";
import type { SpriteArt, SpriteLibrary } from "./sprites";
import { type FogCounts, fogCounts, tileKey } from "./fog";
import type { GroundKind, Tile, ViewActor, ViewState, ViewStructure, ViewTile } from "./view";

/** What the renderer draws on: a PixiJS application in the browser, a fake in tests. */
export interface Surface {
  readonly stage: Container;
  /** The canvas resolution: render pixels per CSS pixel (it follows the scale mode). */
  readonly resolution: number;
  /** The screen's pixels per CSS pixel. */
  readonly devicePixelRatio: number;
  /** The GPU's largest texture side, read from the renderer. */
  readonly maxTextureSize: number;
  render(): void;
  /**
   * Renders `frame` of `target` into a texture of `resolution` pixels per world pixel; `grey`
   * renders it through a grayscale filter (CLI-03n, `greyOf`'s weights), in the bake only.
   */
  bake(target: Container, frame: Rectangle, resolution: number, grey?: boolean): Texture;
  /**
   * Renders `container` (a root: no parent) into `target`'s frame only: the pass's viewport is
   * the frame, and nothing is cleared (the container paints its own backdrop over the frame).
   */
  renderTo(container: Container, target: Texture): void;
}

/**
 * Zoom levels, as the number of tiles across the sight hexagon's widest row that fit the viewport
 * (by its width in portrait, by its height on a desktop). **Not decided here**: the owner and
 * SPK-6 set them (ADR-0006 §5); the debug panel changes them.
 */
export interface ZoomSettings {
  /** The default: 13, the whole sight of radius 6. */
  readonly defaultAcross: number;
  /** The closer level, one pinch away (ADR-0006 §5 names 9). */
  readonly closeAcross: number;
  /** Furthest out a pinch or the wheel goes. */
  readonly minAcross: number;
  /** Closest in. */
  readonly maxAcross: number;
}

export const DEFAULT_ZOOM: ZoomSettings = {
  defaultAcross: 13,
  closeAcross: 9,
  minAcross: 25,
  maxAcross: 4,
};

/** The animation name of a still in the atlas (`tools/art`, `STILL_ANIM`): buildings, props. */
export const STILL = "still";

/** The terrain is baked chunk by chunk (ADR-0006: chunks of 15 × 15). */
export const BAKE_CHUNK = 15;

interface ChunkBake {
  key: string;
  graphics: Graphics;
  frame: Rectangle;
  readonly sprite: Sprite;
  /** Its grayscale twin (CLI-03n), under the colour, baked only while the view has `fog`. */
  readonly grey: Sprite;
  /** Whether `grey` is older than `sprite`'s bake. */
  greyStale: boolean;
  /** What `grey` is baked from: one quad of `sprite`'s texture. */
  readonly greySource: Graphics;
  resolution: number;
  dirty: boolean;
  /** How long drawing its `graphics` took, in ms: part of its bake's time. */
  drawMs: number;
  /** The foam over its water hexes (CLI-03o): drawn over the bakes, never in them. */
  foam: readonly FoamPiece[];
  /** What its foam was planned from: the grounds as seen, in and around it. */
  foamKey: string;
}

/** The atlas's cells the ground is filled with (CLI-03e's `[[tileset]]`, CLI-03g1). */
export const GROUND_TILES = { grass: "grass_c", water: "water_c", foam: "foam_c" } as const;

/** How far the void's bands reach past the terrain, in art px: beyond the furthest zoom's view. */
export const VOID_REACH = 100_000;

/** Flat colours of the void beyond the tiles, without the atlas (as `shapes.ts`'s layers). */
const VOID_COLOURS: Readonly<Record<GroundKind, number>> = {
  grass: 0x5d7a3e,
  water: 0x3f8f8d,
  earth: 0x5d7a3e,
};

/** What the zoom gives on screen, for the panel (see `scaling.ts` for the three numbers). */
export interface ZoomInfo {
  readonly mode: ScaleMode;
  readonly devicePixelRatio: number;
  /** Canvas resolution: render pixels per CSS pixel. */
  readonly resolution: number;
  /** World scale: CSS pixels per art pixel. */
  readonly scale: number;
  /** Render (canvas) pixels per art pixel. */
  readonly canvasScale: number;
  /** Device (screen) pixels per art pixel: what the eye sees. */
  readonly deviceScale: number;
  /** Whether an art pixel covers a whole number of screen pixels. */
  readonly integer: boolean;
  /**
   * `sharp` only: the offscreen pass: `n` canvas pixels per art pixel, the texels it needs, the
   * texels allocated (buckets, reused during a pinch), and its cost against the canvas's own
   * pixels. Null in the other modes, and when `sharp` falls back (see `sharpFallback`).
   */
  readonly offscreen: {
    readonly n: number;
    readonly width: number;
    readonly height: number;
    readonly allocatedWidth: number;
    readonly allocatedHeight: number;
    /** Texels drawn per frame over the canvas's pixels: the oversampling squared. */
    readonly cost: number;
    /** Texels allocated over the canvas's pixels. */
    readonly allocatedCost: number;
  } | null;
  /** `sharp` asked for, but its offscreen does not fit the GPU's texture limit: drawn directly. */
  readonly sharpFallback: boolean;
  /** Tile width, CSS px. */
  readonly tileWidth: number;
  /** Tiles across the viewport's width. */
  readonly across: number;
}

/** Durations of what animates on an input, in ms. */
export const STEP_MS = 180;
export const TURN_MS = 120;
export const CAMERA_MS = 260;
/** How long the steps a stop or a cancel dropped take to fade out (design/11 *The queue*). */
export const FADE_MS = 400;

/**
 * Where an actor's feet stand in its tile: below the tile's centre, by a fraction of the hex's inner
 * radius (half a tile's width), the same for every sprite and shape, so that a body taller than
 * its tile reads as standing **in** it. The wedge, the arcs, the marks' tile and the selection stay
 * on the tile's centre. Not decided here: the owner sets it by eye (debug panel, `?feet=`).
 */
export const DEFAULT_FEET = 0.5;
export const FEET_RANGE = { min: 0, max: 1 } as const;

/** The feet's distance below the tile's centre, in art pixels, for a fraction of the inner radius. */
export function feetOffset(fraction: number): number {
  return (fraction * TILE_WIDTH) / 2;
}
/** Idle animations never draw more often than this (ADR-0003: 12–15 fps). */
export const IDLE_MAX_FPS = 15;

interface Tween {
  readonly from: readonly number[];
  readonly to: readonly number[];
  readonly start: number;
  readonly duration: number;
}

function progress(tween: Tween, now: number): number {
  const t = Math.min(1, Math.max(0, (now - tween.start) / tween.duration));
  return 1 - (1 - t) ** 3;
}

function at(tween: Tween, k: number): number[] {
  return tween.from.map((from, i) => from + ((tween.to[i] ?? from) - from) * k);
}

interface ActorNode {
  actor: ViewActor;
  readonly container: Container;
  readonly wedge: Graphics;
  readonly body: Container;
  readonly sprite: Sprite | null;
  readonly shape: Graphics | null;
  readonly art: SpriteArt | null;
  mark: Graphics | null;
  move: Tween | null;
  turn: Tween | null;
  /** Displayed frame: animation and index. */
  frame: string;
}

/**
 * The frame count of an animation at `fps` since time 0. Every sprite shares these boundaries, so
 * that ten idle sprites change together, in one frame; each starts at a frame of its own (its id).
 */
function tick(now: number, fps: number): number {
  return Math.floor((now * fps) / 1000 + 1e-6);
}

/** A structure as drawn: its container, and its sprite and still when the atlas has it. */
interface StructureNode {
  readonly container: Container;
  readonly structure: ViewStructure;
  readonly sprite: Sprite | null;
  readonly still: Texture | null;
}

const spriteName = (actor: ViewActor) =>
  actor.side === "adventurer" ? actor.profession : actor.caste;

export interface RendererOptions {
  readonly library?: SpriteLibrary | null;
  readonly zoom?: ZoomSettings;
  readonly idle?: boolean;
  /** How the world's scale meets the screen's pixels (`continuous` by default). */
  readonly mode?: ScaleMode;
  /** The feet below the tile's centre, as a fraction of the inner radius (`DEFAULT_FEET`). */
  readonly feet?: number;
  /** A step's animation, in ms (`STEP_MS`); the sandbox walks a path at the same pace. */
  readonly stepMs?: number;
  /**
   * The foam (CLI-03o): `loop` animates it, `still` shows frame 0 as before, to compare. By default
   * the page's `?water=` (`pageWater`).
   */
  readonly water?: WaterMode;
  /**
   * How many chunks a frame may bake that can wait (CLI-09g): a chunk off the screen, or one on it
   * whose texture is only at another zoom's resolution. The rest are baked in the next frames, on
   * the screen first, nearest the centre first. A chunk on the screen whose tiles changed, or that
   * has no texture yet, is baked at once. By default no limit: every chunk in the frame, as before.
   */
  readonly bakesPerFrame?: number;
  /**
   * How many times sharper than the zoom wants a chunk's texture may stay before it is baked again
   * at the zoom's resolution (CLI-09g): a zoom out within it rebakes nothing. By default 1: a chunk
   * is baked again at every step of the zoom's resolution, as before.
   */
  readonly keepSharper?: number;
  /**
   * How long the zoom must be still before a chunk whose texture is only at another zoom's
   * resolution is baked again (CLI-09g): while a zoom goes on, the textures it has are drawn
   * scaled. By default 0: at once, as before.
   */
  readonly rescaleAfterMs?: number;
  readonly onDraw?: (stats: FrameStats) => void;
}

/**
 * The `sharp` mode's offscreen texture: the world at an integer scale, drawn down linearly. It is
 * allocated in buckets larger than what a frame needs, and a frame draws into its top-left part.
 */
interface Offscreen {
  readonly texture: RenderTexture;
  /** Allocated size, CSS px at `resolution`. */
  readonly width: number;
  readonly height: number;
  readonly resolution: number;
  /** The part of it the last frame used, as a texture the screen sprite draws. */
  view: Texture;
  viewWidth: number;
  viewHeight: number;
}

/** What a `sharp` frame needs: the integer, the oversampling, the size in CSS px. */
interface OffscreenPlan {
  readonly n: number;
  readonly oversample: number;
  readonly width: number;
  readonly height: number;
}

/**
 * Offscreen buckets: the allocated oversampling is the needed one rounded up to a quarter of the
 * viewport, so a pinch reallocates when it crosses a quarter, not at every frame; a texture more
 * than two quarters too large is given back.
 */
export const OFFSCREEN_BUCKET = 0.25;

/** The canvas's background, and `sharp`'s backdrop over the part of the offscreen a frame uses. */
export const BACKGROUND = 0x0b0b0e;

/**
 * The tint of an obstacle beyond sight: the overlay's dimming (black at `DIM_ALPHA`) as a multiply,
 * since an obstacle stands over the overlay, with the actors (CLI-03h).
 */
const DIM_TINT = 0x010101 * Math.round(255 * (1 - DIM_ALPHA));

/**
 * The grayscale of what was explored beyond sight (CLI-03n): PixiJS's `desaturate`, luma weights
 * 0.3, 0.6, 0.1, so that a red, a green and a blue all end with R = G = B.
 */
export const LUMA = [0.3, 0.6, 0.1] as const;

/** A flat colour in grayscale, as the bakes' filter gives it. */
export function greyOf(colour: number): number {
  const [r, g, b] = [(colour >> 16) & 0xff, (colour >> 8) & 0xff, colour & 0xff];
  const y = Math.min(255, Math.round(LUMA[0] * r + LUMA[1] * g + LUMA[2] * b));
  return y * 0x010101;
}

/** A grey dimmed as the overlay dims what was seen before (black at `DIM_ALPHA`). */
export function dimmed(grey: number): number {
  return Math.round((grey & 0xff) * (1 - DIM_ALPHA)) * 0x010101;
}

/** Whether two plans of foam pieces are the same: same sources, water hexes and polygons, in order. */
function samePieces(a: readonly FoamPiece[], b: readonly FoamPiece[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const [p, q] = [a[i]!, b[i]!];
    if (p.source.x !== q.source.x || p.source.y !== q.source.y) return false;
    if (p.over.x !== q.over.x || p.over.y !== q.over.y) return false;
    if (p.points.length !== q.points.length) return false;
    for (let k = 0; k < p.points.length; k++) if (p.points[k] !== q.points[k]) return false;
  }
  return true;
}

/** The bake chunk a tile is in, as `syncChunks` keys them. */
function chunkId(tile: Tile): string {
  return `${Math.floor(tile.x / BAKE_CHUNK)},${Math.floor(tile.y / BAKE_CHUNK)}`;
}

/** A convex polygon (flat x, y pairs) clipped to a rectangle (Sutherland–Hodgman); [] when none. */
function clipToBox(points: readonly number[], box: Rectangle): number[] {
  const edges: ((x: number, y: number) => number)[] = [
    (x) => x - box.x,
    (x) => box.x + box.width - x,
    (_, y) => y - box.y,
    (_, y) => box.y + box.height - y,
  ];
  let poly = [...points];
  for (const inside of edges) {
    const out: number[] = [];
    const n = poly.length / 2;
    for (let i = 0; i < n; i++) {
      const [ax, ay] = [poly[2 * i]!, poly[2 * i + 1]!];
      const [bx, by] = [poly[(2 * i + 2) % poly.length]!, poly[(2 * i + 3) % poly.length]!];
      const [da, db] = [inside(ax, ay), inside(bx, by)];
      if (da >= 0) out.push(ax, ay);
      if (da >= 0 !== db >= 0) {
        const t = da / (da - db);
        out.push(ax + t * (bx - ax), ay + t * (by - ay));
      }
    }
    poly = out;
    if (poly.length === 0) break;
  }
  return poly;
}

/**
 * The tiles a view hides (CLI-03n): unrevealed in `tiles`, revealed in `revealed`; as the chain
 * holds them, by `tileKey`.
 */
function hiddenTiles(view: ViewState): ReadonlyMap<string, ViewTile> {
  const hidden = new Map<string, ViewTile>();
  if (!view.revealed) return hidden;
  const unrevealed = new Set<string>();
  for (const tile of view.tiles) if (tile.kind === "unrevealed") unrevealed.add(tileKey(tile));
  for (const tile of view.revealed) {
    const key = tileKey(tile);
    if (tile.kind !== "unrevealed" && unrevealed.has(key)) hidden.set(key, tile);
  }
  return hidden;
}

/**
 * Draws a `ViewState` on demand. Every change (a view, the camera, the size) asks for one frame;
 * a step, a turn and the camera's pan ask for frames until they end; idle animations ask for one
 * frame per change of a sprite's frame, at most 15 per second, and none when they are off.
 */
export class Renderer implements FrameClient {
  readonly scheduler: FrameScheduler;
  private readonly world = new Container();
  /**
   * The view's void beyond the tiles (CLI-03g1): four bands around `voidHole`, reaching
   * `VOID_REACH` past it, placed when the view's void or its tiles' box changes, never per frame. Inside the hole the background stays as before, so a seam between two chunks' bakes
   * looks as it did; the bands reach two hexes into the terrain, under its outer hexes.
   */
  private readonly voidLayer = new Container();
  private voidHole: Box | null = null;
  private voidKey = "";
  /**
   * The foam (CLI-03g2, animated by CLI-03o): over the chunks' water and the void's, out of the
   * bakes, as meshes of its pieces whose texture coordinates change with the frame (`FoamMesh`):
   * a frame of the foam rebakes nothing. Without fog, every piece but those over a hidden tile, by
   * group (a chunk's; the void's by the chunk of the hex they lie over), last in the ground's layer:
   * under the cover and the overlay, which dims it beyond sight as it dims the ground. Under fog,
   * only the pieces over the hexes in sight, in one group, first in the actors' layer: over the
   * overlay's hexes in sight, which are filled from bakes without foam. Its grayscale twin is still,
   * under the cover: baked into each chunk's twin, and over the void a mesh per group (`greyFoam`).
   */
  private readonly foamLayer = new Container();
  private readonly foamMeshes = new Map<string, FoamMesh>();
  private readonly greyFoamMeshes = new Map<string, FoamMesh>();
  /** The foam over the void (`voidFoam`), by group, each group's pieces joined as its key. */
  private voidPieces = new Map<string, { key: string; pieces: readonly FoamPiece[] }>();
  /** Bumped whenever a chunk's or the void's pieces change: the sight's group is built again. */
  private foamVersion = 0;
  private sightFoamKey = "";
  private readonly water: WaterMode;
  /** The foam's frames and rate, kept by `setLibrary` (the loop, or the still alone). */
  private foamFrames: readonly Texture[] = [];
  private foamFps = FOAM_FPS;
  /** The foam's frame count (its clock's), as `advance` last read it; null: shown still. */
  private foamTick: number | null = null;
  private readonly ground = new Container();
  /**
   * Exploration by sight (CLI-03n, `ViewState.fog`): the ground's grayscale twin, the void's
   * bands, its foam and each chunk baked grey (`Surface.bake`), never filtered in a frame; over it
   * the hexes in sight, each filled from the colour bake under it (the chunk's, or the void's
   * bands and foam), first in the overlay's Graphics (`drawSight`). A twin is baked from its colour
   * bake, in the same frame. No mask: a stencil cost two
   * draw calls and their state in every frame, and a Graphics of its own one more. The ground in
   * colour is not drawn under fog; without fog the twin is hidden.
   */
  private readonly greyGround = new Container();
  private readonly greyBands = new Container();
  private readonly greyChunks = new Container();
  private readonly greyFoam = new Container();
  private sightKey = "";
  /** The tiles in sight, and the void's hexes within the sight's radius, that the overlay fills. */
  private sightTiles: readonly Tile[] = [];
  private sightVoid: readonly Tile[] = [];
  /** Whether the overlay is older than the bakes its hexes in sight are filled from. */
  private overlayDirty = false;
  /**
   * Colour bakes replaced or dropped, destroyed once the overlay no longer fills from them
   * (`flushRetired`): a texture destroyed under a Graphics that still holds it broke PixiJS's
   * batch pool.
   */
  private retired: Texture[] = [];
  /** The void's bands, as `placeVoid` placed them: what a void hex in sight is filled with. */
  private voidBands: readonly Rectangle[] = [];
  /**
   * The tiles revealed on chain but never in sight (`ViewState.revealed`), drawn as unrevealed over
   * the ground, both twins, never baked, so that the chunks keep the chain's tiles and a step
   * rebakes nothing (CLI-03n). Drawn again only when it must (`syncCover`), not on every step that
   * explores: building it again is most of such a step's frame.
   */
  private readonly cover = new Graphics();
  /** The tiles `cover` covers, by `tileKey`, and whether in grayscale. */
  private coverTiles: ReadonlySet<string> = new Set();
  private coverGrey = false;
  /** The tiles the view hides, joined: the void's foam is planned again when they change. */
  private hiddenKey = "";
  private fogOn = false;
  /** The atlas's stills in grayscale (the obstacles, the water's cell), baked once each. */
  private readonly greyTextures = new Map<Texture, Texture>();
  private readonly overlay = new Graphics();
  /** The dropped steps of a planned path, fading out. */
  private readonly fading = new Graphics();
  private fade: Tween | null = null;
  private droppedKey = "";
  private readonly actorsLayer = new Container({ sortableChildren: true });
  private readonly nodes = new Map<number, ActorNode>();
  /** The structures drawn (CLI-03f), by key; they never move, so they are built once per view's set. */
  private readonly structureNodes = new Map<string, StructureNode>();
  private structuresKey = "";
  /** The structures that loop an animation (CLI-09e part 3: the characters), by key. */
  private readonly figures = new Map<string, FigureNode & { readonly sprite: Sprite }>();
  /** The wall hexes a structure stands on (`"x,y"`): no rock there. */
  private covered: ReadonlySet<string> = new Set();
  /**
   * The obstacles the atlas has (CLI-03h, `OBSTACLES`), kept by `setLibrary`; none: the bakes draw
   * the shaped rocks.
   */
  private obstacleArt: readonly Obstacle[] = [];
  /** The wall hexes' obstacles drawn from the atlas, by hex (`"x,y"`), in the actors' layer. */
  private readonly obstacleNodes = new Map<
    string,
    { readonly sprite: Sprite; readonly name: string; readonly texture: Texture }
  >();
  private readonly chunks = new Map<string, ChunkBake>();
  private readonly rings = new Map<string, { count: number; ring: readonly Tile[] }>();
  private view: ViewState | null = null;
  private viewport: Viewport = { width: 1, height: 1 };
  private camera: Camera = { centre: { x: 0, y: 0 }, scale: 1 };
  /** The scale asked for (fit, pinch, wheel); `camera.scale` is it, snapped in `snap` mode. */
  private wanted = 1;
  private mode: ScaleMode;
  /** `sharp`: the sprite that draws the offscreen texture down to the screen, linearly. */
  private readonly screen = new Sprite(Texture.EMPTY);
  private offscreen: Offscreen | null = null;
  /**
   * `sharp`: the root of the offscreen pass, a backdrop over exactly the part of the texture the
   * frame needs, then the world. The pass draws into that part only (its viewport), so the GPU
   * fills what the panel's cost counts, whatever the size of the reused texture.
   */
  private readonly passRoot = new Container();
  private readonly backdrop = new Graphics();
  private cameraTween: Tween | null = null;
  private zoomed = false;
  private zoom: ZoomSettings;
  private idleOn: boolean;
  private lastIdle = -Infinity;
  private library: SpriteLibrary | null;
  private readonly scales = new Map<string, number>();
  private feet: number;
  private readonly stepMs: number;
  /** The last chunk's bake, in ms (its drawing and its render into a texture), for `FrameStats`. */
  private lastBakeMs: number | null = null;
  /** `RendererOptions.bakesPerFrame`. */
  private readonly bakesPerFrame: number;
  /** `RendererOptions.keepSharper`. */
  private readonly keepSharper: number;
  /** `RendererOptions.rescaleAfterMs`, and when the scale last changed (host time). */
  private readonly rescaleAfterMs: number;
  private scaledAt = -Infinity;
  /** Whether the last frame left chunks to bake (`bakesPerFrame`): the next frame bakes more. */
  private bakesLeft = false;
  /** Where the ground's cells come from, kept by `setLibrary`: no lookup in a frame. */
  private groundSource: "atlas" | "colours" = "colours";

  constructor(
    private readonly surface: Surface,
    private readonly host: FrameHost,
    options: RendererOptions = {},
  ) {
    this.library = options.library ?? null;
    this.groundSource = this.groundTextures() ? "atlas" : "colours";
    this.obstacleArt = this.obstaclesInAtlas();
    this.zoom = options.zoom ?? DEFAULT_ZOOM;
    this.idleOn = options.idle ?? true;
    this.mode = options.mode ?? "continuous";
    this.feet = options.feet ?? DEFAULT_FEET;
    this.stepMs = options.stepMs ?? STEP_MS;
    this.bakesPerFrame = options.bakesPerFrame ?? Infinity;
    this.keepSharper = options.keepSharper ?? 1;
    this.rescaleAfterMs = options.rescaleAfterMs ?? 0;
    this.water = options.water ?? pageWater();
    this.foamFrames = this.foamTextures();
    const onDraw = options.onDraw;
    this.scheduler = new FrameScheduler(
      host,
      this,
      onDraw &&
        ((stats) =>
          onDraw({
            ...stats,
            bakeMs: this.lastBakeMs,
            ground: this.groundSource,
            obstacles: this.obstacleArt.length > 0 ? "atlas" : "shapes",
          })),
    );
    this.voidLayer.visible = false;
    for (let i = 0; i < 4; i++) this.voidLayer.addChild(new Sprite(Texture.WHITE));
    // Under the chunks, in the ground's layer: the world's children keep their order.
    this.ground.addChild(this.voidLayer);
    this.greyBands.visible = false;
    for (let i = 0; i < 4; i++) this.greyBands.addChild(new Sprite(Texture.WHITE));
    this.greyGround.addChild(this.greyBands, this.greyChunks, this.greyFoam);
    this.greyGround.visible = false;
    this.world.addChild(
      this.greyGround,
      this.ground,
      this.cover,
      this.overlay,
      this.fading,
      this.actorsLayer,
    );
    this.passRoot.addChild(this.backdrop);
    this.mountStage();
  }

  // --- inputs -------------------------------------------------------------------------------

  setView(view: ViewState): void {
    const previous = this.view;
    this.view = view;
    const hole = voidHole(view.tiles);
    const holeKey = `${view.void ?? ""} ${hole ? Object.values(hole).join(",") : ""}`;
    const previousVoid = this.voidKey;
    this.voidHole = hole;
    if (holeKey !== this.voidKey) {
      this.voidKey = holeKey;
      this.placeVoid();
    }
    const now = this.host.now();
    const sightKey = this.sightKey;
    this.syncFog(view);
    this.syncStructures(view.structures ?? []);
    this.syncObstacles(view);
    const hidden = hiddenTiles(view);
    this.syncStructureLooks(view, hidden);
    const terrainChanged = this.syncChunks(view, hidden);
    if (terrainChanged) this.overlayDirty = true;
    this.syncCover(view, hidden);
    const hiddenKey = [...hidden.keys()].join(" ");
    const hiddenChanged = hiddenKey !== this.hiddenKey;
    this.hiddenKey = hiddenKey;
    if (terrainChanged || hiddenChanged || holeKey !== previousVoid) this.syncVoidFoam(view);
    if (terrainChanged || hiddenChanged || holeKey !== previousVoid || sightKey !== this.sightKey)
      this.syncFoam(hidden);
    this.drawOverlay();
    this.flushRetired();
    this.syncDropped(view, now);
    this.syncActors(view, now);
    const adventurer = view.actors.find((a) => a.id === view.adventurerId);
    const before = previous?.actors.find((a) => a.id === previous.adventurerId);
    if (adventurer) {
      const target = tileToPixel(adventurer.tile);
      if (!before) {
        this.camera = { ...this.camera, centre: target };
      } else if (before.tile.x !== adventurer.tile.x || before.tile.y !== adventurer.tile.y) {
        this.panCameraTo(target, now);
      }
    }
    this.scheduler.invalidate();
  }

  resize(viewport: Viewport): void {
    this.viewport = viewport;
    this.setScale(this.zoomed ? this.clampScale(this.wanted) : this.defaultScale());
    this.scheduler.invalidate();
  }

  /**
   * The scale mode (`scaling.ts`). The caller sets the surface's canvas resolution for the mode
   * first (`canvasResolution`): the snapped scale is counted in its pixels.
   */
  setMode(mode: ScaleMode): void {
    this.mode = mode;
    // Leaving sharp gives the texture back now, not at the next frame (none while hidden).
    if (mode !== "sharp") this.dropOffscreen();
    this.mountStage();
    this.setScale(this.zoomed ? this.wanted : this.defaultScale());
    this.scheduler.invalidate();
  }

  scaleMode(): ScaleMode {
    return this.mode;
  }

  /** Drag: moves the camera by a distance in screen pixels. */
  pan(dx: number, dy: number): void {
    this.cameraTween = null;
    const { centre, scale } = this.camera;
    this.camera = { scale, centre: { x: centre.x - dx / scale, y: centre.y - dy / scale } };
    this.scheduler.invalidate();
  }

  /** Pinch or wheel: scales by `factor`, keeping the world point under `point` in place. */
  zoomAt(factor: number, point: Point): void {
    this.cameraTween = null;
    const anchor = screenToWorld(this.camera, this.viewport, point);
    this.zoomed = true;
    this.setScale(this.clampScale(this.wanted * factor));
    const scale = this.camera.scale;
    this.camera = {
      scale,
      centre: {
        x: anchor.x - (point.x - this.viewport.width / 2) / scale,
        y: anchor.y - (point.y - this.viewport.height / 2) / scale,
      },
    };
    this.scheduler.invalidate();
  }

  /** Sets the zoom to `across` tiles (a preset of the panel). */
  zoomTo(across: number): void {
    this.zoomed = across !== this.zoom.defaultAcross;
    this.setScale(fitScale(this.viewport, across));
    this.scheduler.invalidate();
  }

  setZoomSettings(zoom: ZoomSettings): void {
    this.zoom = zoom;
    this.zoomed = false;
    this.setScale(this.defaultScale());
    this.scheduler.invalidate();
  }

  /** Back to the adventurer, eased. */
  recentre(): void {
    const adventurer = this.view?.actors.find((a) => a.id === this.view?.adventurerId);
    if (!adventurer) return;
    this.panCameraTo(tileToPixel(adventurer.tile), this.host.now());
    this.scheduler.invalidate();
  }

  setIdle(on: boolean): void {
    this.idleOn = on;
    this.scheduler.invalidate();
  }

  setLibrary(library: SpriteLibrary | null): void {
    this.library = library;
    for (const node of this.nodes.values()) this.removeNode(node);
    this.nodes.clear();
    this.structuresKey = "";
    if (this.view) this.syncStructures(this.view.structures ?? []);
    if (this.view) this.syncActors(this.view, this.host.now());
    this.groundSource = this.groundTextures() ? "atlas" : "colours";
    // The obstacles switch between the atlas's stills and the bakes' rocks: every one again.
    this.obstacleArt = this.obstaclesInAtlas();
    for (const node of this.obstacleNodes.values()) node.sprite.destroy();
    this.obstacleNodes.clear();
    this.dropGreyTextures();
    if (this.view) this.syncObstacles(this.view);
    // After the grey textures are dropped: a structure's grey still is made again from the new atlas.
    if (this.view) this.syncStructureLooks(this.view, hiddenTiles(this.view));
    this.placeVoid();
    // The ground switches between flat colours and the atlas's cells: every chunk, once.
    for (const chunk of this.chunks.values()) {
      chunk.key = "";
      chunk.foamKey = "-";
    }
    this.foamFrames = this.foamTextures();
    this.dropFoam();
    if (this.view) {
      const hidden = hiddenTiles(this.view);
      this.syncChunks(this.view, hidden);
      this.syncVoidFoam(this.view);
      this.syncFoam(hidden);
    }
    this.scheduler.invalidate();
  }

  /** The display scale of a sprite (a caste or a profession); starts at `sprites.json`'s. */
  setSpriteScale(name: string, scale: number): void {
    this.scales.set(name, scale);
    for (const node of this.nodes.values()) {
      if (spriteName(node.actor) === name) this.placeBody(node);
    }
    this.scheduler.invalidate();
  }

  spriteScale(name: string): number {
    return this.scales.get(name) ?? this.library?.get(name)?.scale ?? 1;
  }

  /** Where the feet stand below the tile's centre, as a fraction of the inner radius. */
  setFeet(fraction: number): void {
    this.feet = fraction;
    for (const node of this.nodes.values()) this.placeBody(node);
    this.scheduler.invalidate();
  }

  feetFraction(): number {
    return this.feet;
  }

  cameraState(): { camera: Camera; viewport: Viewport } {
    return { camera: this.camera, viewport: this.viewport };
  }

  /** What the current zoom gives on screen. */
  zoomInfo(): ZoomInfo {
    const { scale } = this.camera;
    const { resolution, devicePixelRatio } = this.surface;
    const deviceScale = scale * devicePixelRatio;
    const plan = this.mode === "sharp" ? this.offscreenPlan() : null;
    // The texture actually held (a reused bucket may be larger than the plan's), else the bucket
    // the next frame will allocate.
    const held = this.offscreen?.resolution === resolution ? this.offscreen : null;
    const allocated = plan && (held ?? this.allocation(plan));
    const canvas = this.viewport.width * this.viewport.height * resolution * resolution;
    const texels = (w: number, h: number) =>
      Math.round(w * resolution) * Math.round(h * resolution);
    return {
      mode: this.mode,
      devicePixelRatio,
      resolution,
      scale,
      canvasScale: scale * resolution,
      deviceScale,
      // Whole on the screen only when the canvas is the screen (see scaling.ts).
      integer: resolution === devicePixelRatio && isWhole(deviceScale),
      offscreen: plan &&
        allocated && {
          n: plan.n,
          width: Math.round(plan.width * resolution),
          height: Math.round(plan.height * resolution),
          allocatedWidth: Math.round(allocated.width * resolution),
          allocatedHeight: Math.round(allocated.height * resolution),
          cost: texels(plan.width, plan.height) / canvas,
          allocatedCost: texels(allocated.width, allocated.height) / canvas,
        },
      sharpFallback: this.mode === "sharp" && plan === null,
      tileWidth: TILE_WIDTH * scale,
      across: this.viewport.width / (TILE_WIDTH * scale),
    };
  }

  /** `sharp`'s offscreen texture, as last drawn (null in the other modes); for tests. */
  offscreenTexture(): RenderTexture | null {
    return this.offscreen?.texture ?? null;
  }

  destroy(): void {
    this.scheduler.destroy();
    for (const chunk of this.chunks.values()) this.dropChunk(chunk);
    this.chunks.clear();
    this.dropFoam();
    for (const node of this.obstacleNodes.values()) node.sprite.destroy();
    this.obstacleNodes.clear();
    this.dropGreyTextures();
    this.dropOffscreen();
    this.screen.destroy();
    this.world.destroy({ children: true });
    this.passRoot.destroy({ children: true });
    this.foamLayer.destroy();
    this.flushRetired();
  }

  // --- frames -------------------------------------------------------------------------------

  advance(now: number): Advance {
    let changed = false;
    let moving = false;
    for (const node of this.nodes.values()) {
      if (node.move) {
        const [x = 0, y = 0] = at(node.move, progress(node.move, now));
        node.container.position.set(x, y);
        node.container.zIndex = y;
        if (now >= node.move.start + node.move.duration) node.move = null;
        else moving = true;
        changed = true;
      }
      if (node.turn) {
        node.wedge.rotation = at(node.turn, progress(node.turn, now))[0] ?? 0;
        if (now >= node.turn.start + node.turn.duration) node.turn = null;
        else moving = true;
        changed = true;
      }
    }
    if (this.fade) {
      this.fading.alpha = at(this.fade, progress(this.fade, now))[0] ?? 0;
      if (now >= this.fade.start + this.fade.duration) {
        this.fade = null;
        this.fading.clear();
      } else moving = true;
      changed = true;
    }
    if (this.cameraTween) {
      const [x = 0, y = 0] = at(this.cameraTween, progress(this.cameraTween, now));
      this.camera = { ...this.camera, centre: { x, y } };
      if (now >= this.cameraTween.start + this.cameraTween.duration) this.cameraTween = null;
      else moving = true;
      changed = true;
    }
    const idleDue = now >= this.lastIdle + 1000 / IDLE_MAX_FPS - 0.5;
    let idleChanged = false;
    for (const node of this.nodes.values()) {
      if (!node.move && !idleDue) continue;
      if (this.showFrame(node, now)) {
        changed = true;
        if (!node.move) idleChanged = true;
      }
    }
    // The foam, an idle animation under the same cap: its next frame, if a piece of it is in view.
    const foamTick = this.foamAnimates() ? tick(now, this.foamFps) : null;
    if (foamTick !== this.foamTick && (idleDue || foamTick === null)) {
      this.foamTick = foamTick;
      if (this.foamInView()) {
        changed = true;
        if (foamTick !== null) idleChanged = true;
      }
    }
    // The figures (CLI-09e part 3), under the same cap; off, each goes back to frame 0 at once.
    if (this.figures.size > 0 && (idleDue || !this.idleOn)) {
      const inView = new Set(this.figuresInView());
      for (const figure of this.figures.values()) {
        if (this.showFigure(figure, now) && (inView.has(figure) || !this.idleOn)) {
          changed = true;
          if (this.idleOn) idleChanged = true;
        }
      }
    }
    if (idleChanged) this.lastIdle = now;
    if (moving) return { changed, next: now };
    return { changed, next: this.nextIdle(now) };
  }

  draw(): void {
    this.bakeTerrain();
    // Chunks left to bake (`bakesPerFrame`): a frame more for them.
    if (this.bakesLeft) this.scheduler.invalidate();
    if (this.overlayDirty) this.drawOverlay();
    this.flushRetired();
    this.cullFoam();
    const { centre, scale } = this.camera;
    const plan = this.mode === "sharp" ? this.offscreenPlan() : null;
    if (!plan) {
      // Continuous, snap, or sharp falling back: the world drawn directly.
      this.dropOffscreen();
      this.mountStage(false);
      this.placeWorld(scale, this.viewport.width, this.viewport.height, centre);
      this.surface.render();
      return;
    }
    // Sharp bilinear: the world nearest-neighbour at `n` texels per art pixel into the offscreen
    // texture (one extra pass, only in a frame being drawn), then that texture drawn down to the
    // target scale, linearly, by `screen`.
    this.mountStage(true);
    const offscreen = this.ensureOffscreen(plan);
    this.placeWorld(scale * plan.oversample, plan.width, plan.height, centre);
    this.backdrop.clear().rect(0, 0, plan.width, plan.height).fill(BACKGROUND);
    // Into the view (the frame's part of the reused texture), not the whole allocation.
    this.surface.renderTo(this.passRoot, offscreen.view);
    this.screen.scale.set(1 / plan.oversample);
    this.surface.render();
  }

  // --- internals ----------------------------------------------------------------------------

  private defaultScale(): number {
    return fitScale(this.viewport, this.zoom.defaultAcross);
  }

  private setScale(wanted: number): void {
    this.wanted = wanted;
    const scale = this.mode === "snap" ? snapScale(wanted, this.surface.resolution) : wanted;
    if (scale !== this.camera.scale) this.scaledAt = this.host.now();
    this.camera = { ...this.camera, scale };
  }

  private placeWorld(scale: number, width: number, height: number, centre: Point): void {
    this.world.scale.set(scale);
    this.world.position.set(width / 2 - centre.x * scale, height / 2 - centre.y * scale);
  }

  /**
   * The void (CLI-03g1): the world's rectangle the frame shows, a whole art pixel larger on each
   * side, filled with the void's look; the water's atlas cell is one flat colour, so one sprite
   * stretched over it is the same water as the baked cells.
   */
  private placeVoid(): void {
    const ground = this.view?.void;
    this.voidLayer.visible = ground !== undefined;
    this.greyBands.visible = ground !== undefined;
    if (ground === undefined) {
      this.voidBands = [];
      return;
    }
    // The water's cell is one flat colour: stretched, it is the same water as the baked cells.
    const water = ground === "water" ? this.groundTextures()?.water : null;
    const hole = this.voidHole ?? { x0: 0, y0: 0, x1: 0, y1: 0 };
    // Placed once per view, never per frame: far past what the furthest zoom shows.
    const far = VOID_REACH;
    const bands = [
      [hole.x0 - far, hole.y0 - far, hole.x1 + far, hole.y0],
      [hole.x0 - far, hole.y1, hole.x1 + far, hole.y1 + far],
      [hole.x0 - far, hole.y0, hole.x0, hole.y1],
      [hole.x1, hole.y0, hole.x1 + far, hole.y1],
    ] as const;
    const greyWater = water ? this.greyTexture(water) : null;
    this.voidBands = bands.map(([x0, y0, x1, y1]) => new Rectangle(x0, y0, x1 - x0, y1 - y0));
    this.overlayDirty = true;
    bands.forEach(([x0, y0, x1, y1], i) => {
      const band = this.voidLayer.children[i] as Sprite;
      band.texture = water ?? Texture.WHITE;
      band.tint = water ? 0xffffff : VOID_COLOURS[ground];
      // Its grayscale twin (CLI-03n): the water's cell baked grey, or the flat colour's grey; dimmed
      // as the overlay dims the explored tiles beside it.
      const grey = this.greyBands.children[i] as Sprite;
      grey.texture = greyWater ?? Texture.WHITE;
      grey.tint = greyWater ? DIM_TINT : dimmed(greyOf(VOID_COLOURS[ground]));
      for (const sprite of [band, grey]) {
        sprite.position.set(x0, y0);
        sprite.width = x1 - x0;
        sprite.height = y1 - y0;
      }
    });
  }

  /**
   * Exploration by sight (CLI-03n): with the view's `fog`, the grayscale twin shows, and over it
   * the hexes in sight, and the void's hexes within the sight's radius of the adventurer (the void
   * has no tile in sight; without them a coast in sight would meet a grey sea). They change once a
   * step; the overlay is drawn with the view, from them (`drawSight`).
   */
  private syncFog(view: ViewState): void {
    const fog = view.fog ?? null;
    if ((fog !== null) !== this.fogOn) {
      this.fogOn = fog !== null;
      this.greyGround.visible = this.fogOn;
      this.ground.visible = !this.fogOn;
      this.sightKey = "";
    }
    if (!fog) return;
    const adventurer = view.actors.find((a) => a.id === view.adventurerId);
    const key = `${adventurer ? tileKey(adventurer.tile) : ""} ${fog.sightRadius} ${view.sight.map(tileKey).join(" ")}`;
    if (key === this.sightKey) return;
    this.sightKey = key;
    const voidHexes: Tile[] = [];
    if (adventurer && view.void !== undefined) {
      const tiles = new Set(view.tiles.map(tileKey));
      for (const hex of hexesWithin(adventurer.tile, fog.sightRadius)) {
        if (!tiles.has(tileKey(hex))) voidHexes.push(hex);
      }
    }
    this.sightTiles = view.sight;
    this.sightVoid = voidHexes;
  }

  /**
   * The overlay, and under fog the hexes in sight first: drawn with the view, as before CLI-03n,
   * and again in a frame whose bakes replaced a texture its hexes in sight are filled from.
   */
  private drawOverlay(): void {
    this.overlayDirty = false;
    if (!this.view) return;
    drawOverlay(this.overlay, this.view, this.fogOn ? (g) => this.drawSight(g) : undefined);
  }

  /**
   * Fills the hexes in sight from the colour bakes, under the overlay, in a frame after the bakes: a
   * tile from its chunk's texture, a void hex from the bands, each clipped to what it covers (the
   * foam over them is `foamLayer`'s, CLI-03o). The hexes' own corners, not grown: they tile the
   * plane, so the edge of what is in colour is theirs. Not snapped to whole pixels as the bakes' sprites are (`roundPixels`):
   * up to half a pixel apart from them, as two chunks' sprites can be.
   */
  private drawSight(g: Graphics): void {
    const at = (frame: Rectangle) => new Matrix().translate(frame.x, frame.y);
    for (const tile of this.sightTiles) {
      const chunk = this.chunks.get(chunkId(tile));
      if (!chunk || chunk.sprite.texture === Texture.EMPTY) continue;
      g.poly(hexCorners(tileToPixel(tile))).fill({
        texture: chunk.sprite.texture,
        textureSpace: "global",
        matrix: at(chunk.frame),
      });
    }
    const ground = this.view?.void;
    if (ground === undefined) return;
    // The water's cell is one flat colour: stretched over the hex's box, as the bands stretch it.
    const water = ground === "water" ? (this.groundTextures()?.water ?? null) : null;
    for (const hex of this.sightVoid) {
      const centre = tileToPixel(hex);
      const corners = hexCorners(centre);
      for (const band of this.voidBands) {
        const piece = clipToBox(corners, band);
        if (piece.length < 6) continue;
        if (!water) {
          g.poly(piece).fill(VOID_COLOURS[ground]);
          continue;
        }
        const matrix = new Matrix()
          .scale(TILE_WIDTH / water.width, (2 * HEX_RADIUS) / water.height)
          .translate(centre.x - TILE_WIDTH / 2, centre.y - HEX_RADIUS);
        g.poly(piece).fill({ texture: water, textureSpace: "global", matrix });
      }
    }
  }

  /**
   * Covers the tiles `ViewState.revealed` holds but `tiles` hides, as unrevealed (in its grayscale
   * under fog, as the grey twin drew them). Under fog a tile just explored is in sight, and the
   * hexes in sight are drawn over the cover (the overlay's `drawSight`): the cover is drawn again
   * only when a tile it covers was explored and has left sight, or when a tile is hidden that it
   * does not cover (a reveal). Without fog nothing is drawn over it: again at every change.
   */
  private syncCover(view: ViewState, hidden: ReadonlyMap<string, ViewTile>): void {
    const grey = view.fog !== undefined;
    let stale = grey !== this.coverGrey || (!grey && hidden.size !== this.coverTiles.size);
    for (const key of hidden.keys()) {
      if (stale) break;
      if (!this.coverTiles.has(key)) stale = true;
    }
    if (!stale && this.coverTiles.size !== hidden.size) {
      const inSight = new Set(view.sight.map(tileKey));
      for (const key of this.coverTiles) {
        if (!hidden.has(key) && !inSight.has(key)) {
          stale = true;
          break;
        }
      }
    }
    if (!stale) return;
    this.coverTiles = new Set(hidden.keys());
    this.coverGrey = grey;
    this.cover.clear();
    drawUnrevealed(this.cover, [...hidden.values()], grey ? greyOf : undefined);
  }

  /** A still of the atlas in grayscale (CLI-03n), baked once at its native size. */
  private greyTexture(texture: Texture): Texture {
    const known = this.greyTextures.get(texture);
    if (known) return known;
    const sprite = new Sprite(texture);
    const frame = new Rectangle(0, 0, texture.width, texture.height);
    const grey = this.surface.bake(sprite, frame, 1, true);
    sprite.destroy();
    this.greyTextures.set(texture, grey);
    return grey;
  }

  private dropGreyTextures(): void {
    for (const grey of this.greyTextures.values()) grey.destroy(true);
    this.greyTextures.clear();
  }

  /**
   * Plans the foam over the void again (`voidFoam`), grouped by the chunk of the hex each piece lies
   * over; a group whose pieces are the same keeps its array, so its meshes are not built again.
   */
  private syncVoidFoam(view: ViewState): void {
    const pieces = this.foamFrames.length > 0 ? voidFoam(view.tiles, view.void, true) : [];
    const groups = new Map<string, FoamPiece[]>();
    for (const piece of pieces) {
      const id = `v${chunkId(piece.over)}`;
      let group = groups.get(id);
      if (!group) groups.set(id, (group = []));
      group.push(piece);
    }
    const keyOf = (p: FoamPiece) => `${p.source.x},${p.source.y}:${p.points.join(",")}`;
    const next = new Map<string, { key: string; pieces: readonly FoamPiece[] }>();
    for (const [id, group] of groups) {
      const key = group.map(keyOf).join(" ");
      const before = this.voidPieces.get(id);
      next.set(id, before?.key === key ? before : { key, pieces: group });
      if (before?.key !== key) this.foamVersion += 1;
    }
    if (next.size !== this.voidPieces.size) this.foamVersion += 1;
    this.voidPieces = next;
  }

  /** The foam's frames: the atlas's loop, or its still alone (no loop, or not on one page). */
  private foamTextures(): readonly Texture[] {
    const art = this.library?.get(GROUND_TILES.foam);
    const loop = art?.animations.loop;
    if (loop && loop.textures.length > 1) {
      const source = loop.textures[0]!.source;
      if (loop.textures.every((t) => t.source === source)) {
        this.foamFps = loop.fps;
        return loop.textures;
      }
    }
    this.foamFps = FOAM_FPS;
    const still = art?.animations[STILL]?.textures[0];
    return still ? [still] : [];
  }

  /**
   * The foam's meshes for the view (see `foamLayer`): a group whose pieces did not change keeps its
   * mesh; under fog, the group in sight is built again when sight or the pieces change.
   */
  private syncFoam(hidden: ReadonlyMap<string, ViewTile>): void {
    const groups = new Map<string, readonly FoamPiece[]>();
    for (const [id, chunk] of this.chunks) if (chunk.foam.length > 0) groups.set(id, chunk.foam);
    for (const [id, { pieces }] of this.voidPieces) groups.set(id, pieces);
    const frames = this.foamFrames;
    const colour = new Map<string, readonly FoamPiece[]>();
    if (frames.length > 0 && this.fogOn) {
      const key = `${this.sightKey}|${this.foamVersion}`;
      const current = this.foamMeshes.get("sight");
      if (key === this.sightFoamKey && current) colour.set("sight", current.pieces);
      else {
        const shown = new Set([...this.sightTiles, ...this.sightVoid].map(tileKey));
        const inSight: FoamPiece[] = [];
        for (const pieces of groups.values()) {
          for (const piece of pieces) if (shown.has(tileKey(piece.over))) inSight.push(piece);
        }
        colour.set("sight", inSight);
      }
      this.sightFoamKey = key;
    } else if (frames.length > 0) {
      for (const [id, pieces] of groups) {
        // A tile hidden without fog: none over it (built again at each change, rare).
        colour.set(
          id,
          hidden.size === 0 ? pieces : pieces.filter((p) => !hidden.has(tileKey(p.over))),
        );
      }
    }
    this.syncMeshes(this.foamMeshes, colour, frames, this.foamLayer, () => 0xffffff);
    // Last in the ground's layer (after chunks added since), or first among the actors under fog:
    // a zIndex makes PixiJS sort its parent, so it is set only there, and while detached.
    const parent = this.fogOn ? this.actorsLayer : this.ground;
    if (this.foamMeshes.size === 0) this.foamLayer.removeFromParent();
    else if (
      this.fogOn ? this.foamLayer.parent !== parent : parent.children.at(-1) !== this.foamLayer
    ) {
      this.foamLayer.removeFromParent();
      this.foamLayer.zIndex = this.fogOn ? -Infinity : 0;
      parent.addChild(this.foamLayer);
    }
    // The grayscale twin over the void, still: the frame 0 in grayscale, dimmed as the bands are
    // (a chunk's twin bakes its own foam, `bakeTerrain`).
    const fogged = frames[0] !== undefined && this.fogOn;
    const grey = new Map<string, readonly FoamPiece[]>();
    if (fogged) for (const [id, { pieces }] of this.voidPieces) grey.set(id, pieces);
    const still = fogged ? [this.greyTexture(frames[0]!)] : [];
    this.syncMeshes(this.greyFoamMeshes, grey, still, this.greyFoam, () => DIM_TINT);
  }

  /**
   * The groups' meshes: a group whose pieces changed draws its new pieces with the same mesh (under
   * fog, the group in sight at every step), so the scene only changes when a group comes or goes.
   */
  private syncMeshes(
    meshes: Map<string, FoamMesh>,
    groups: ReadonlyMap<string, readonly FoamPiece[]>,
    frames: readonly Texture[],
    layer: Container,
    tint: (id: string) => number,
  ): void {
    for (const [id, mesh] of meshes) {
      const pieces = groups.get(id);
      if (pieces && pieces.length > 0) continue;
      mesh.destroy();
      meshes.delete(id);
    }
    for (const [id, pieces] of groups) {
      if (pieces.length === 0) continue;
      const known = meshes.get(id);
      if (known) {
        if (known.pieces !== pieces) known.setPieces(pieces);
        continue;
      }
      const mesh = new FoamMesh(pieces, frames);
      mesh.mesh.tint = tint(id);
      layer.addChild(mesh.mesh);
      meshes.set(id, mesh);
    }
  }

  private dropFoam(): void {
    for (const mesh of [...this.foamMeshes.values(), ...this.greyFoamMeshes.values()]) {
      mesh.destroy();
    }
    this.foamLayer.removeFromParent();
    this.foamMeshes.clear();
    this.greyFoamMeshes.clear();
    this.sightFoamKey = "";
    this.foamTick = null;
  }

  /** The world's rectangle the frame shows. */
  private viewRect(): Rectangle {
    const { centre, scale } = this.camera;
    const w = this.viewport.width / scale;
    const h = this.viewport.height / scale;
    return new Rectangle(centre.x - w / 2, centre.y - h / 2, w, h);
  }

  /** Whether the foam loops (`?water=`, the atlas's loop): whether it asks for frames at all. */
  private foamAnimates(): boolean {
    return this.water === "loop" && this.foamFrames.length > 1 && this.foamMeshes.size > 0;
  }

  /** Whether a piece of the foam in colour is on the screen: only then does it ask for frames. */
  private foamInView(): boolean {
    const rect = this.viewRect();
    for (const mesh of this.foamMeshes.values()) if (overlaps(mesh.bounds, rect)) return true;
    return false;
  }

  /**
   * Before a frame is drawn: the foam's meshes off the screen, colour and grey, are not drawn; those
   * in colour on it show the clock's frame (`foamTick`), or frame 0 when the foam is still.
   */
  private cullFoam(): void {
    const rect = this.viewRect();
    for (const mesh of this.foamMeshes.values()) {
      mesh.mesh.visible = overlaps(mesh.bounds, rect);
      if (mesh.mesh.visible) mesh.show(this.foamTick);
    }
    // The grayscale twin is still: only off the screen or on it, one draw call each on it.
    for (const mesh of this.greyFoamMeshes.values())
      mesh.mesh.visible = overlaps(mesh.bounds, rect);
  }

  /** The atlas's ground cells, or null when the atlas has none (flat colours). */
  private groundTextures(): GroundTextures | null {
    const still = (name: string) => this.library?.get(name)?.animations[STILL]?.textures[0] ?? null;
    const grass = still(GROUND_TILES.grass);
    const water = still(GROUND_TILES.water);
    const foam = still(GROUND_TILES.foam);
    // The foam is not baked (CLI-03o: `foamLayer`); it still makes the atlas's ground.
    return grass || water || foam ? { grass, water } : null;
  }

  /**
   * The world on the stage, or the offscreen texture's sprite with the world as a root (`sharp`,
   * when its offscreen fits; `draw` decides, the mode gives the first guess).
   */
  private mountStage(offscreen = this.mode === "sharp"): void {
    const child = offscreen ? this.screen : this.world;
    const stage = this.surface.stage;
    if (stage.children.length === 1 && stage.children[0] === child) return;
    stage.removeChildren();
    if (offscreen) this.passRoot.addChild(this.world);
    stage.addChild(child);
  }

  /**
   * `sharp`: what a frame needs, or null when an offscreen at the integer `n` does not fit the
   * GPU's texture limit (a large window at resolution 2): `sharp` then falls back to drawing
   * directly, and never asks for a texture larger than the GPU takes.
   */
  private offscreenPlan(): OffscreenPlan | null {
    const { resolution, maxTextureSize } = this.surface;
    const { n, oversample } = sharpFactor(this.camera.scale, resolution);
    const width = Math.ceil(this.viewport.width * oversample);
    const height = Math.ceil(this.viewport.height * oversample);
    if (Math.max(width, height) * resolution > maxTextureSize) return null;
    return { n, oversample, width, height };
  }

  /** The bucket a plan is allocated in, never above the GPU's limit (the plan itself fits). */
  private allocation(plan: OffscreenPlan): { width: number; height: number } {
    const { resolution, maxTextureSize } = this.surface;
    const k = Math.ceil(plan.oversample / OFFSCREEN_BUCKET - 1e-9) * OFFSCREEN_BUCKET;
    const limit = Math.floor(maxTextureSize / resolution);
    return {
      width: Math.max(plan.width, Math.min(Math.ceil(this.viewport.width * k), limit)),
      height: Math.max(plan.height, Math.min(Math.ceil(this.viewport.height * k), limit)),
    };
  }

  /**
   * Reuses the offscreen texture while the frame's size fits in it and it is not more than two
   * buckets too large; otherwise gives it back and allocates the plan's bucket. The screen sprite
   * draws the part the frame used.
   */
  private ensureOffscreen(plan: OffscreenPlan): Offscreen {
    const resolution = this.surface.resolution;
    const bucket = this.allocation(plan);
    const slack = 2 * OFFSCREEN_BUCKET;
    const current = this.offscreen;
    const reuse =
      current !== null &&
      current.resolution === resolution &&
      current.width >= plan.width &&
      current.height >= plan.height &&
      current.width <= bucket.width + this.viewport.width * slack &&
      current.height <= bucket.height + this.viewport.height * slack;
    let offscreen: Offscreen;
    if (reuse && current) {
      offscreen = current;
    } else {
      this.dropOffscreen();
      const texture = RenderTexture.create({
        width: bucket.width,
        height: bucket.height,
        resolution,
        scaleMode: "linear",
        antialias: false,
      });
      offscreen = {
        texture,
        width: bucket.width,
        height: bucket.height,
        resolution,
        view: Texture.EMPTY,
        viewWidth: 0,
        viewHeight: 0,
      };
      this.offscreen = offscreen;
    }
    if (offscreen.viewWidth !== plan.width || offscreen.viewHeight !== plan.height) {
      if (offscreen.view !== Texture.EMPTY) offscreen.view.destroy(false);
      offscreen.view = new Texture({
        source: offscreen.texture.source,
        frame: new Rectangle(0, 0, plan.width, plan.height),
      });
      offscreen.viewWidth = plan.width;
      offscreen.viewHeight = plan.height;
      this.screen.texture = offscreen.view;
    }
    return offscreen;
  }

  private dropOffscreen(): void {
    if (!this.offscreen) return;
    this.screen.texture = Texture.EMPTY;
    if (this.offscreen.view !== Texture.EMPTY) this.offscreen.view.destroy(false);
    this.offscreen.texture.destroy(true);
    this.offscreen = null;
  }

  private clampScale(scale: number): number {
    const low = fitScale(this.viewport, this.zoom.minAcross);
    const high = fitScale(this.viewport, this.zoom.maxAcross);
    return Math.min(high, Math.max(low, scale));
  }

  private panCameraTo(target: Point, now: number): void {
    const { centre } = this.camera;
    this.cameraTween = {
      from: [centre.x, centre.y],
      to: [target.x, target.y],
      start: now,
      duration: CAMERA_MS,
    };
  }

  /**
   * A chunk texture's resolution: the screen's pixels per world pixel, in steps of √2 so that a
   * pinch rebakes a few times, not at every frame; capped by the GPU's texture size.
   */
  private bakeResolution(frame: Rectangle): number {
    // What the world is drawn at: the canvas, or `sharp`'s offscreen texture.
    const oversample = this.mode === "sharp" ? (this.offscreenPlan()?.oversample ?? 1) : 1;
    const wanted = this.camera.scale * this.surface.resolution * oversample;
    const stepped = 2 ** (Math.round(2 * Math.log2(wanted)) / 2);
    const side = Math.max(frame.width, frame.height, 1);
    return Math.min(stepped, this.surface.maxTextureSize / side);
  }

  /**
   * Groups the tiles by chunk; a chunk whose tiles' kinds or grounds changed, or whose lip or foam toward a
   * neighbouring chunk or the void did, is drawn again, and rebaked. Its frame comes from its
   * tiles' positions only (`chunkFrame`): the ground never changes the textures' size or count.
   * Whether any chunk was drawn again, added or dropped: the terrain changed.
   */
  private syncChunks(view: ViewState, hidden: ReadonlyMap<string, ViewTile>): boolean {
    // The chain's tiles (CLI-03n): what the adventurer has not seen is covered, not baked hidden.
    const tiles =
      hidden.size === 0 ? view.tiles : view.tiles.map((t) => hidden.get(tileKey(t)) ?? t);
    const groups = new Map<string, ViewTile[]>();
    const grounds = new Map<string, GroundKind | null>();
    for (const tile of tiles) {
      const id = chunkId(tile);
      let group = groups.get(id);
      if (!group) groups.set(id, (group = []));
      group.push(tile);
      grounds.set(`${tile.x},${tile.y}`, tile.kind === "unrevealed" ? null : groundOf(tile));
    }
    const around = (t: Tile): GroundKind | null => {
      const ground = grounds.get(`${t.x},${t.y}`);
      return ground === undefined ? (view.void ?? null) : ground;
    };
    const textures = this.groundTextures();
    // The atlas's obstacles stand in the actors' layer (`syncObstacles`): no rock in the bakes.
    const rocks = this.obstacleArt.length === 0;
    // CLI-03n follow-up: the lip and the foam are planned from what was seen; a tile never seen is
    // unknown to them (`PlanOptions.hidden`), though baked with its ground under the cover.
    const unseen: ReadonlySet<string> = new Set(hidden.keys());
    // A lip looks only for water: a tile never seen changes the bake only if it is water.
    const lipMark = (t: Tile, ground: GroundKind | null) =>
      ground === "water" && unseen.has(tileKey(t)) ? "?" : (ground?.[0] ?? "-");
    // The foam looks for land too (its sources): every tile never seen marks it.
    const foamMark = (t: Tile, ground: GroundKind | null) =>
      unseen.has(tileKey(t)) ? "?" : (ground?.[0] ?? "-");
    let changed = false;
    for (const [id, group] of groups) {
      const covered = (t: ViewTile) => (this.covered.has(`${t.x},${t.y}`) ? "c" : "");
      const ground = (t: ViewTile) => (t.kind === "unrevealed" ? null : groundOf(t));
      const ownKey = (mark: typeof lipMark) =>
        group.map((t) => `${t.x},${t.y}${t.kind[0]}${mark(t, ground(t))}${covered(t)}`).join("");
      // The lip and the foam look across the chunk's edge: the grounds around it join the key.
      const ringKey = (mark: typeof lipMark) =>
        this.ringOf(id, group)
          .map((t) => mark(t, around(t)))
          .join("");
      const key = `${ownKey(lipMark)}|${ringKey(lipMark)}`;
      const foamKey = this.foamFrames.length > 0 ? `${ownKey(foamMark)}|${ringKey(foamMark)}` : "";
      const chunk = this.chunks.get(id);
      if (chunk && chunk.foamKey !== foamKey) {
        chunk.foamKey = foamKey;
        const foam = foamKey ? waterFoam(group, { around, hidden: unseen }) : [];
        // A tile seen that changes none of its pieces (most exploring steps) changes nothing.
        if (!samePieces(foam, chunk.foam)) {
          chunk.foam = foam;
          this.foamVersion += 1;
          // Its grayscale twin holds its foam, still (`bakeTerrain`).
          chunk.greyStale = true;
        }
      }
      if (chunk?.key === key) continue;
      changed = true;
      const start = this.host.now();
      const graphics = drawTerrain(group, this.covered, {
        around,
        textures,
        rocks,
        hidden: unseen,
      });
      const drawMs = this.host.now() - start;
      const frame = chunkFrame(group);
      if (chunk) {
        chunk.graphics.destroy();
        Object.assign(chunk, { key, graphics, frame, dirty: true, drawMs });
      } else {
        const foam = foamKey ? waterFoam(group, { around, hidden: unseen }) : [];
        this.foamVersion += 1;
        const sprite = new Sprite(Texture.EMPTY);
        const grey = new Sprite(Texture.EMPTY);
        this.ground.addChild(sprite);
        this.greyChunks.addChild(grey);
        this.chunks.set(id, {
          key,
          graphics,
          frame,
          sprite,
          grey,
          greyStale: true,
          greySource: new Graphics(),
          resolution: 0,
          dirty: true,
          drawMs,
          foam,
          foamKey,
        });
      }
    }
    for (const [id, chunk] of this.chunks) {
      if (!groups.has(id)) {
        this.dropChunk(chunk);
        this.chunks.delete(id);
        changed = true;
      }
    }
    return changed;
  }

  /**
   * The hexes around a chunk's tiles but not in it, as far as its drawing looks: the lip one step,
   * the foam `FOAM_REACH` steps to a land hex and one more to that hex's water (CLI-03g2). Kept per
   * chunk while its tiles stay.
   */
  private ringOf(id: string, group: readonly ViewTile[]): readonly Tile[] {
    const cached = this.rings.get(id);
    if (cached && cached.count === group.length) return cached.ring;
    const inside = new Set(group.map((t) => `${t.x},${t.y}`));
    const ring = new Map<string, Tile>();
    for (const tile of group) {
      for (const next of hexesWithin(tile, FOAM_REACH + 1)) {
        const key = `${next.x},${next.y}`;
        if (!inside.has(key)) ring.set(key, next);
      }
    }
    const entry = { count: group.length, ring: [...ring.values()] };
    this.rings.set(id, entry);
    return entry.ring;
  }

  private dropChunk(chunk: ChunkBake): void {
    chunk.graphics.destroy();
    chunk.greySource.destroy();
    if (chunk.sprite.texture !== Texture.EMPTY) this.retired.push(chunk.sprite.texture);
    if (chunk.grey.texture !== Texture.EMPTY) chunk.grey.texture.destroy(true);
    chunk.sprite.destroy();
    chunk.grey.destroy();
  }

  private flushRetired(): void {
    for (const texture of this.retired) texture.destroy(true);
    this.retired = [];
  }

  /** Whether a chunk's texture is to be baked again at `resolution` (`keepSharper`). */
  private rescaleDue(chunk: ChunkBake, resolution: number): boolean {
    return chunk.resolution < resolution || chunk.resolution > resolution * this.keepSharper;
  }

  /**
   * The chunks to bake in this frame, in order: all of them without `bakesPerFrame` or
   * `rescaleAfterMs`; else those on the screen whose tiles changed or that have no texture, then at
   * most `bakesPerFrame` of the others (on the screen first, nearest the centre first), of which
   * those only at another zoom's resolution once the zoom has been still `rescaleAfterMs`.
   * `bakesLeft` says whether any waits.
   */
  private chunksToBake(): Iterable<ChunkBake> {
    this.bakesLeft = false;
    if (this.bakesPerFrame === Infinity && this.rescaleAfterMs === 0) return this.chunks.values();
    const zooming = this.host.now() < this.scaledAt + this.rescaleAfterMs;
    const rect = this.viewRect();
    const { centre } = this.camera;
    const now: ChunkBake[] = [];
    const later: { chunk: ChunkBake; onScreen: boolean; distance: number }[] = [];
    for (const chunk of this.chunks.values()) {
      const stale =
        chunk.dirty ||
        this.rescaleDue(chunk, this.bakeResolution(chunk.frame)) ||
        (this.fogOn && chunk.greyStale);
      if (!stale) continue;
      const { frame } = chunk;
      const onScreen = overlaps(frame, rect);
      const unbaked = chunk.dirty || chunk.sprite.texture === Texture.EMPTY;
      if (onScreen && unbaked) {
        now.push(chunk);
        continue;
      }
      if (zooming && !unbaked) {
        this.bakesLeft = true;
        continue;
      }
      const dx = frame.x + frame.width / 2 - centre.x;
      const dy = frame.y + frame.height / 2 - centre.y;
      later.push({ chunk, onScreen, distance: dx * dx + dy * dy });
    }
    later.sort((a, b) => Number(b.onScreen) - Number(a.onScreen) || a.distance - b.distance);
    if (later.length > this.bakesPerFrame) this.bakesLeft = true;
    return [...now, ...later.slice(0, this.bakesPerFrame).map((l) => l.chunk)];
  }

  private bakeTerrain(): void {
    for (const chunk of this.chunksToBake()) {
      const resolution = this.bakeResolution(chunk.frame);
      const colour = chunk.dirty || this.rescaleDue(chunk, resolution);
      // The grayscale twin only while the view has fog (CLI-03n); a hub never bakes it.
      const grey = this.fogOn && (colour || chunk.greyStale);
      if (!colour && !grey) continue;
      const start = this.host.now();
      if (colour) {
        const old = chunk.sprite.texture;
        chunk.sprite.texture = this.surface.bake(chunk.graphics, chunk.frame, resolution);
        chunk.sprite.position.set(chunk.frame.x, chunk.frame.y);
        if (old !== Texture.EMPTY) this.retired.push(old);
        chunk.dirty = false;
        chunk.resolution = resolution;
        chunk.greyStale = true;
        // The overlay's hexes in sight are filled from the texture just replaced.
        this.overlayDirty = true;
      }
      if (grey) {
        // The colour bake through the filter, texel for texel: one quad, not the chunk's drawing
        // again; into a texture, so that no filter runs in a frame. The quad is the chunk's, kept
        // with it: a root destroyed right after its filtered bake broke PixiJS's batch pool.
        const { frame } = chunk;
        chunk.greySource
          .clear()
          .rect(frame.x, frame.y, frame.width, frame.height)
          .fill({
            texture: chunk.sprite.texture,
            textureSpace: "global",
            matrix: new Matrix().translate(frame.x, frame.y),
          });
        // Its foam, still (CLI-03o): what was explored is remembered, not live; baked, it costs no
        // frame. Over the colour bake's grass, cut back as `trimFoam` cuts it.
        drawFoam(chunk.greySource, chunk.foam, this.foamFrames[0] ?? null);
        const old = chunk.grey.texture;
        chunk.grey.texture = this.surface.bake(chunk.greySource, frame, resolution, true);
        chunk.grey.position.set(chunk.frame.x, chunk.frame.y);
        if (old !== Texture.EMPTY) old.destroy(true);
        chunk.greyStale = false;
      }
      this.lastBakeMs = chunk.drawMs + (this.host.now() - start);
      chunk.drawMs = 0;
    }
  }

  private syncActors(view: ViewState, now: number): void {
    const seen = new Set<number>();
    for (const actor of view.actors) {
      seen.add(actor.id);
      const node = this.nodes.get(actor.id);
      if (!node) {
        this.nodes.set(actor.id, this.createNode(actor));
        continue;
      }
      const before = node.actor;
      node.actor = actor;
      const target = tileToPixel(actor.tile);
      if (before.tile.x !== actor.tile.x || before.tile.y !== actor.tile.y) {
        const from = node.container.position;
        const adjacent = Math.hypot(target.x - from.x, target.y - from.y) < TILE_WIDTH * 1.01;
        node.move = adjacent
          ? { from: [from.x, from.y], to: [target.x, target.y], start: now, duration: this.stepMs }
          : null;
        if (!adjacent) node.container.position.set(target.x, target.y);
      }
      if (before.facing !== actor.facing) {
        const from = node.wedge.rotation;
        let to = facingRotation(actor.facing);
        while (to - from > Math.PI) to -= 2 * Math.PI;
        while (from - to > Math.PI) to += 2 * Math.PI;
        node.turn = { from: [from], to: [to], start: now, duration: TURN_MS };
      }
      if (before.mark !== actor.mark) this.setMark(node);
      node.container.zIndex = target.y;
      this.placeBody(node);
    }
    for (const [id, node] of this.nodes) {
      if (!seen.has(id)) {
        this.removeNode(node);
        this.nodes.delete(id);
      }
    }
  }

  /**
   * The structures (CLI-03f): built again only when the view's set changes (or the atlas), each in
   * the actors' layer, its base on its hex's centre, sorted with the actors by the y of its base.
   * An actor on the same row stands in front of it (its feet are below the centre); two structures
   * on one row keep the order of their keys.
   */
  private syncStructures(structures: readonly ViewStructure[]): void {
    const sorted = [...structures].sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    // What a node is built from: an edit that changes a sprite, a mirror or a covered hex builds it again.
    const key = sorted
      .map(
        (s) =>
          `${s.key}@${s.at.x},${s.at.y}:${s.sprite}/${s.animation ?? ""}${s.mirror ? "~" : ""}` +
          `[${s.covers.map((t) => `${t.x},${t.y}`).join(";")}]`,
      )
      .join(" ");
    if (key === this.structuresKey) return;
    this.structuresKey = key;
    for (const node of this.structureNodes.values()) node.container.destroy({ children: true });
    this.structureNodes.clear();
    this.figures.clear();
    this.covered = new Set(sorted.flatMap((s) => s.covers.map((t) => `${t.x},${t.y}`)));
    for (const structure of sorted) {
      const node = this.createStructure(structure);
      this.actorsLayer.addChild(node.container);
      this.structureNodes.set(structure.key, node);
    }
  }

  private createStructure(structure: ViewStructure): StructureNode {
    const base = tileToPixel(structure.at);
    const container = new Container();
    container.position.set(base.x, base.y);
    container.zIndex = base.y - 0.001;
    const art = this.library?.get(structure.sprite);
    const loop = structure.animation ? art?.animations[structure.animation] : undefined;
    const texture = loop?.textures[0] ?? art?.animations[STILL]?.textures[0];
    if (!texture) {
      container.addChild(drawStructure(structure));
      return { container, structure, sprite: null, still: null };
    }
    const sprite = new Sprite(texture);
    const anchor = texture.defaultAnchor;
    const ax = anchor?.x ?? 0.5;
    const ay = anchor?.y ?? 1;
    sprite.anchor.set(ax, ay);
    if (structure.mirror) sprite.scale.x = -1;
    container.addChild(sprite);
    if (loop && loop.textures.length > 1) {
      this.figures.set(structure.key, {
        sprite,
        textures: loop.textures,
        fps: loop.fps ?? 12,
        phase: figurePhase(structure.at),
        bounds: spriteBounds(base, texture.frame.width, texture.frame.height, ax, ay),
        animates: true,
        grey: false,
      });
    }
    return { container, structure, sprite, still: texture };
  }

  /**
   * Each structure as the view shows its hex (CLI-09e part 3, as the walls' obstacles): not drawn
   * on a hex the view hides, dimmed beyond sight, and in grayscale under the view's fog (a figure
   * then stands still at frame 0). Every view, over the structures alone: no rebuild.
   */
  private syncStructureLooks(view: ViewState, hidden: ReadonlyMap<string, ViewTile>): void {
    if (this.structureNodes.size === 0) return;
    const inSight = new Set(view.sight.map((t) => `${t.x},${t.y}`));
    // An instance (`revealed` given) also hides what stands on a chunk not revealed yet.
    const unrevealed = new Set<string>();
    if (view.revealed) {
      for (const t of view.tiles) if (t.kind === "unrevealed") unrevealed.add(tileKey(t));
    }
    const now = this.host.now();
    for (const [key, node] of this.structureNodes) {
      const at = node.structure.at;
      const drawn = !hidden.has(tileKey(at)) && !unrevealed.has(tileKey(at));
      const seen = inSight.has(`${at.x},${at.y}`);
      node.container.visible = drawn;
      const tint = seen ? 0xffffff : DIM_TINT;
      for (const child of node.container.children) {
        if ("tint" in child && child.tint !== tint) child.tint = tint;
      }
      const grey = !seen && this.fogOn;
      const figure = this.figures.get(key);
      if (figure) {
        figure.animates = drawn && !grey;
        figure.grey = grey;
        this.showFigure(figure, now);
      } else if (node.sprite && node.still) {
        const texture = grey ? this.greyTexture(node.still) : node.still;
        if (node.sprite.texture !== texture) node.sprite.texture = texture;
      }
    }
  }

  /** Shows a figure's frame at `now`: whether its texture changed. */
  private showFigure(figure: FigureNode & { readonly sprite: Sprite }, now: number): boolean {
    const index =
      this.idleOn && figure.animates
        ? figureFrame(now, figure.fps, figure.phase, figure.textures.length)
        : 0;
    const first = figure.textures[0]!;
    const texture = figure.grey ? this.greyTexture(first) : (figure.textures[index] ?? first);
    if (figure.sprite.texture === texture) return false;
    figure.sprite.texture = texture;
    return true;
  }

  /** The figures that ask for frames: animated, drawn in colour, and on the screen. */
  private figuresInView(): (FigureNode & { readonly sprite: Sprite })[] {
    if (!this.idleOn || this.figures.size === 0) return [];
    const rect = this.viewRect();
    return [...this.figures.values()].filter((f) => f.animates && overlaps(f.bounds, rect));
  }

  /** The obstacles of `OBSTACLES` whose still the atlas has, in their order. */
  private obstaclesInAtlas(): readonly Obstacle[] {
    return OBSTACLES.filter((o) => this.library?.get(o.sprite)?.animations[STILL]?.textures[0]);
  }

  /**
   * The wall hexes' obstacles (CLI-03h): with the atlas, each wall hex that would draw a rock
   * (`isRock`) shows the still `obstacleOf` gives it, placed as a prop (its base on the hex's
   * centre, at native size), sorted with the actors by that y; added and dropped as the revealed
   * walls change, never per frame. Beyond sight it is dimmed as the overlay dims the ground under
   * it, and drawn from its still in grayscale under the view's fog (CLI-03n). Without the atlas,
   * none: the bakes draw the rocks.
   */
  private syncObstacles(view: ViewState): void {
    if (this.obstacleArt.length === 0) return;
    const inSight = new Set(view.sight.map((t) => `${t.x},${t.y}`));
    const seen = new Set<string>();
    for (const tile of view.tiles) {
      if (!isRock(tile, this.covered)) continue;
      const key = `${tile.x},${tile.y}`;
      seen.add(key);
      let node = this.obstacleNodes.get(key);
      if (!node) {
        const choice = obstacleOf(tile, this.obstacleArt);
        const texture = choice && this.library?.get(choice.sprite)?.animations[STILL]?.textures[0];
        if (!choice || !texture) continue;
        const sprite = new Sprite(texture);
        const anchor = texture.defaultAnchor;
        sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
        if (choice.mirror) sprite.scale.x = -1;
        const base = tileToPixel(tile);
        sprite.position.set(base.x, base.y);
        sprite.zIndex = base.y - 0.001;
        this.actorsLayer.addChild(sprite);
        node = { sprite, name: choice.sprite, texture };
        this.obstacleNodes.set(key, node);
      }
      const now = inSight.has(key);
      const tint = now ? 0xffffff : DIM_TINT;
      if (node.sprite.tint !== tint) node.sprite.tint = tint;
      const texture = now || !this.fogOn ? node.texture : this.greyTexture(node.texture);
      if (node.sprite.texture !== texture) node.sprite.texture = texture;
    }
    for (const [key, node] of this.obstacleNodes) {
      if (!seen.has(key)) {
        node.sprite.destroy();
        this.obstacleNodes.delete(key);
      }
    }
  }

  /** The obstacles drawn from the atlas, by hex (`"x,y"`): their sprite and still; for tests. */
  obstacles(): ReadonlyMap<
    string,
    { readonly sprite: Sprite; readonly name: string; readonly texture: Texture }
  > {
    return this.obstacleNodes;
  }

  /** Whether a structure is drawn from the atlas (a still), else as a shape: for the page and tests. */
  structureFromAtlas(key: string): boolean | null {
    const node = this.structureNodes.get(key);
    if (!node) return null;
    return node.sprite !== null;
  }

  /** A structure's sprite, and whether it loops (a figure): for the page and tests. */
  structureSprite(key: string): { readonly sprite: Sprite; readonly loops: boolean } | null {
    const node = this.structureNodes.get(key);
    if (!node?.sprite) return null;
    return { sprite: node.sprite, loops: this.figures.has(key) };
  }

  /** Whether a structure is drawn (not on a hidden hex): for tests. */
  structureVisible(key: string): boolean | null {
    return this.structureNodes.get(key)?.container.visible ?? null;
  }

  /** A new set of dropped steps fades out from the ghosts' alpha to nothing. */
  private syncDropped(view: ViewState, now: number): void {
    const key = view.dropped.map((t) => `${t.x},${t.y}`).join(" ");
    if (key === this.droppedKey) return;
    this.droppedKey = key;
    this.fading.clear();
    this.fading.alpha = 1;
    this.fade = null;
    if (view.dropped.length === 0) return;
    drawGhosts(this.fading, view.dropped);
    this.fade = { from: [1], to: [0], start: now, duration: FADE_MS };
  }

  private createNode(actor: ViewActor): ActorNode {
    const art = this.library?.get(spriteName(actor)) ?? null;
    const container = new Container();
    const position = tileToPixel(actor.tile);
    container.position.set(position.x, position.y);
    container.zIndex = position.y;
    const wedge = drawWedge(actor.side === "adventurer");
    wedge.rotation = facingRotation(actor.facing);
    const body = new Container();
    let sprite: Sprite | null = null;
    let shape: Graphics | null = null;
    const first = art ? (art.animations.idle ?? Object.values(art.animations)[0]) : undefined;
    const texture = first?.textures[0];
    if (texture) {
      sprite = new Sprite(texture);
      const anchor = texture.defaultAnchor;
      sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
      body.addChild(sprite);
    } else {
      shape = drawBody(spriteName(actor));
      body.addChild(shape);
    }
    container.addChild(wedge, body);
    this.actorsLayer.addChild(container);
    const node: ActorNode = {
      actor,
      container,
      wedge,
      body,
      sprite,
      shape,
      art: texture ? art : null,
      mark: null,
      move: null,
      turn: null,
      frame: "",
    };
    this.placeBody(node);
    this.setMark(node);
    this.showFrame(node, this.host.now());
    return node;
  }

  private removeNode(node: ActorNode): void {
    node.container.destroy({ children: true });
  }

  /** Feet, scale and mirror of the body, and the mark's height over it. */
  private placeBody(node: ActorNode): void {
    const name = spriteName(node.actor);
    const scale = this.spriteScale(name);
    const feet = feetOffset(this.feet);
    node.body.position.set(0, feet);
    node.body.scale.set(isMirrored(node.actor.facing) ? -scale : scale, scale);
    const height = node.art ? node.art.baseline : SHAPE_HEIGHT[name];
    if (node.mark) node.mark.position.set(0, feet - height * scale - 14);
  }

  private setMark(node: ActorNode): void {
    node.mark?.destroy();
    node.mark = node.actor.mark ? drawMark(node.actor.mark) : null;
    if (node.mark) node.container.addChild(node.mark);
    this.placeBody(node);
  }

  /** The frame a node shows at `now`: its step's frames while it steps, idle ones otherwise. */
  private frameAt(node: ActorNode, now: number): { anim: string; index: number } {
    const anim = node.move ? "move" : "idle";
    if (anim === "idle" && !this.idleOn) return { anim, index: 0 };
    if (node.art) {
      const animation = node.art.animations[anim] ?? node.art.animations.idle;
      const count = animation?.textures.length ?? 1;
      const fps = animation?.fps ?? 12;
      return { anim, index: (tick(now, fps) + node.actor.id) % count };
    }
    const count = SHAPE_IDLE.offsets.length;
    return { anim: "idle", index: (tick(now, SHAPE_IDLE.fps) + node.actor.id) % count };
  }

  private showFrame(node: ActorNode, now: number): boolean {
    const { anim, index } = this.frameAt(node, now);
    const key = `${anim}/${index}`;
    if (key === node.frame) return false;
    node.frame = key;
    if (node.sprite && node.art) {
      const animation = node.art.animations[anim] ?? node.art.animations.idle;
      const texture = animation?.textures[index];
      if (texture) node.sprite.texture = texture;
    } else if (node.shape) {
      node.shape.y = SHAPE_IDLE.offsets[index] ?? 0;
    }
    return true;
  }

  /** When the next idle frame is due, or null when nothing idles. */
  private nextIdle(now: number): number | null {
    let next = Infinity;
    // The foam's next frame (CLI-03o), only while a piece of it is on the screen.
    if (this.foamAnimates() && this.foamInView()) {
      next = ((tick(now, this.foamFps) + 1) * 1000) / this.foamFps;
    }
    // The figures' next frame, only while one of them is on the screen (CLI-09e part 3).
    for (const figure of this.figuresInView()) next = Math.min(next, nextFrameAt(now, figure.fps));
    for (const node of this.idleOn ? this.nodes.values() : []) {
      const animation = node.art ? node.art.animations.idle : null;
      const count = node.art ? (animation?.textures.length ?? 0) : SHAPE_IDLE.offsets.length;
      if (count < 2) continue;
      const fps = animation?.fps ?? SHAPE_IDLE.fps;
      const boundary = ((tick(now, fps) + 1) * 1000) / fps;
      next = Math.min(next, boundary);
    }
    if (next === Infinity) return null;
    return Math.max(next, this.lastIdle + 1000 / IDLE_MAX_FPS);
  }

  /** What the view draws in each state of exploration (CLI-03n), or null before a view. */
  fogCounts(): FogCounts | null {
    return this.view && fogCounts(this.view);
  }

  /** Eases the camera to a tile (CLI-03k: a place selected by key, off the screen). */
  lookAt(tile: Tile): void {
    this.panCameraTo(tileToPixel(tile), this.host.now());
    this.scheduler.invalidate();
  }
}
