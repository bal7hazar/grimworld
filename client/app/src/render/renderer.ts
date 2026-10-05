import { Container, Graphics, Rectangle, RenderTexture, Sprite, Texture } from "pixi.js";
import {
  type Camera,
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
} from "./ground";
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
  resolution: number;
  dirty: boolean;
  /** How long drawing its `graphics` took, in ms: part of its bake's time. */
  drawMs: number;
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

/** The whole art pixels around some foam pieces: the frame their group is baked in. */
function piecesFrame(pieces: readonly FoamPiece[]): Rectangle {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const { points } of pieces) {
    for (let i = 0; i < points.length; i += 2) {
      minX = Math.min(minX, points[i]!);
      maxX = Math.max(maxX, points[i]!);
      minY = Math.min(minY, points[i + 1]!);
      maxY = Math.max(maxY, points[i + 1]!);
    }
  }
  const x = Math.floor(minX);
  const y = Math.floor(minY);
  return new Rectangle(x, y, Math.ceil(maxX) - x, Math.ceil(maxY) - y);
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
   * The foam over the void (CLI-03g2, `voidFoam`): its pieces over the void's hexes, grouped by the
   * chunk of the hex they lie in, each group baked as a chunk is; after the void's bands, under the
   * chunks. Drawn again when its pieces change, never per frame.
   */
  private readonly voidFoamLayer = new Container();
  private readonly voidFoamBakes = new Map<string, ChunkBake>();
  private voidFoamKey: string | null = null;
  private readonly ground = new Container();
  /**
   * Exploration by sight (CLI-03n, `ViewState.fog`): the ground's grayscale twin under it, the void's
   * bands, its foam and each chunk baked grey (`Surface.bake`), never filtered in a frame; the
   * ground in colour above it is masked to the hexes in sight (`sightMask`, drawn again on a step).
   * Without fog the twin is hidden and the ground unmasked, as before.
   */
  private readonly greyGround = new Container();
  private readonly greyBands = new Container();
  private readonly greyFoam = new Container();
  private readonly greyChunks = new Container();
  private readonly sightMask = new Graphics();
  private sightKey = "";
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
  private readonly structureNodes = new Map<string, Container>();
  private structuresKey = "";
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
    this.voidLayer.addChild(this.voidFoamLayer);
    // Under the chunks, in the ground's layer: the world's children keep their order.
    this.ground.addChild(this.voidLayer);
    this.greyBands.visible = false;
    for (let i = 0; i < 4; i++) this.greyBands.addChild(new Sprite(Texture.WHITE));
    this.greyGround.addChild(this.greyBands, this.greyFoam, this.greyChunks);
    this.greyGround.visible = false;
    this.sightMask.visible = false;
    this.world.addChild(
      this.greyGround,
      this.sightMask,
      this.ground,
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
    this.syncFog(view);
    this.syncStructures(view.structures ?? []);
    this.syncObstacles(view);
    const terrainChanged = this.syncChunks(view);
    if (terrainChanged || holeKey !== previousVoid) this.syncVoidFoam(view);
    drawOverlay(this.overlay, view);
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
    this.placeVoid();
    // The ground switches between flat colours and the atlas's cells: every chunk, once.
    for (const chunk of this.chunks.values()) chunk.key = "";
    this.voidFoamKey = null;
    if (this.view) this.syncChunks(this.view);
    if (this.view) this.syncVoidFoam(this.view);
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
    for (const bake of this.voidFoamBakes.values()) this.dropChunk(bake);
    this.chunks.clear();
    for (const node of this.obstacleNodes.values()) node.sprite.destroy();
    this.obstacleNodes.clear();
    this.dropGreyTextures();
    this.dropOffscreen();
    this.screen.destroy();
    this.world.destroy({ children: true });
    this.passRoot.destroy({ children: true });
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
    if (idleChanged) this.lastIdle = now;
    if (moving) return { changed, next: now };
    return { changed, next: this.nextIdle(now) };
  }

  draw(): void {
    this.bakeTerrain();
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
    if (ground === undefined) return;
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
   * Exploration by sight (CLI-03n): with the view's `fog`, the grayscale twin shows and the ground
   * in colour is masked to the hexes in sight, and to the void's hexes within the sight's radius of
   * the adventurer (the void has no tile in sight; without them a coast in sight would meet a grey
   * sea). The mask is drawn again only when those hexes change: once a step.
   */
  private syncFog(view: ViewState): void {
    const fog = view.fog ?? null;
    if ((fog !== null) !== this.fogOn) {
      this.fogOn = fog !== null;
      this.greyGround.visible = this.fogOn;
      // A mask that is not visible masks everything out; without fog it would draw as hexes.
      this.sightMask.visible = this.fogOn;
      this.ground.mask = this.fogOn ? this.sightMask : null;
      this.sightKey = "";
    }
    if (!fog) return;
    const adventurer = view.actors.find((a) => a.id === view.adventurerId);
    const key = `${adventurer ? tileKey(adventurer.tile) : ""} ${fog.sightRadius} ${view.sight.map(tileKey).join(" ")}`;
    if (key === this.sightKey) return;
    this.sightKey = key;
    const hexes: Tile[] = [...view.sight];
    if (adventurer && view.void !== undefined) {
      const tiles = new Set(view.tiles.map(tileKey));
      for (const hex of hexesWithin(adventurer.tile, fog.sightRadius)) {
        if (!tiles.has(tileKey(hex))) hexes.push(hex);
      }
    }
    // The hexes' own corners, not grown: they tile the plane, so the mask's edge is the hexes'.
    this.sightMask.clear();
    for (const hex of hexes) this.sightMask.poly(hexCorners(tileToPixel(hex))).fill(0xffffff);
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

  /** Draws and rebakes the foam over the void, group by group, when its pieces change. */
  private syncVoidFoam(view: ViewState): void {
    const foam = this.groundTextures()?.foam ?? null;
    const pieces = foam ? voidFoam(view.tiles, view.void) : [];
    const keyOf = (p: FoamPiece) => `${p.source.x},${p.source.y}:${p.points.join(",")}`;
    const key = pieces.map(keyOf).join(" ");
    if (key === this.voidFoamKey) return;
    this.voidFoamKey = key;
    const groups = new Map<string, FoamPiece[]>();
    for (const piece of pieces) {
      const id = `${Math.floor(piece.over.x / BAKE_CHUNK)},${Math.floor(piece.over.y / BAKE_CHUNK)}`;
      let group = groups.get(id);
      if (!group) groups.set(id, (group = []));
      group.push(piece);
    }
    for (const [id, group] of groups) {
      const groupKey = group.map(keyOf).join(" ");
      const bake = this.voidFoamBakes.get(id);
      if (bake?.key === groupKey) continue;
      const start = this.host.now();
      const graphics = new Graphics();
      drawFoam(graphics, group, foam);
      const drawMs = this.host.now() - start;
      const frame = piecesFrame(group);
      if (bake) {
        bake.graphics.destroy();
        Object.assign(bake, { key: groupKey, graphics, frame, dirty: true, drawMs });
      } else {
        const sprite = new Sprite(Texture.EMPTY);
        const grey = new Sprite(Texture.EMPTY);
        grey.tint = DIM_TINT;
        this.voidFoamLayer.addChild(sprite);
        this.greyFoam.addChild(grey);
        this.voidFoamBakes.set(id, {
          key: groupKey,
          graphics,
          frame,
          sprite,
          grey,
          greyStale: true,
          resolution: 0,
          dirty: true,
          drawMs,
        });
      }
    }
    for (const [id, bake] of this.voidFoamBakes) {
      if (!groups.has(id)) {
        this.dropChunk(bake);
        this.voidFoamBakes.delete(id);
      }
    }
  }

  /** The atlas's ground cells, or null when the atlas has none (flat colours). */
  private groundTextures(): GroundTextures | null {
    const still = (name: string) => this.library?.get(name)?.animations[STILL]?.textures[0] ?? null;
    const grass = still(GROUND_TILES.grass);
    const water = still(GROUND_TILES.water);
    const foam = still(GROUND_TILES.foam);
    return grass || water || foam ? { grass, water, foam } : null;
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
  private syncChunks(view: ViewState): boolean {
    const { tiles } = view;
    const groups = new Map<string, ViewTile[]>();
    const grounds = new Map<string, GroundKind | null>();
    for (const tile of tiles) {
      const id = `${Math.floor(tile.x / BAKE_CHUNK)},${Math.floor(tile.y / BAKE_CHUNK)}`;
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
    let changed = false;
    for (const [id, group] of groups) {
      const covered = (t: ViewTile) => (this.covered.has(`${t.x},${t.y}`) ? "c" : "");
      const ground = (t: ViewTile) => groundOf(t)[0];
      const own = group.map((t) => `${t.x},${t.y}${t.kind[0]}${ground(t)}${covered(t)}`).join("");
      // The lip and the foam look across the chunk's edge: the grounds around it join the key.
      const ring = this.ringOf(id, group)
        .map((t) => around(t)?.[0] ?? "-")
        .join("");
      const key = `${own}|${ring}`;
      const chunk = this.chunks.get(id);
      if (chunk?.key === key) continue;
      changed = true;
      const start = this.host.now();
      const graphics = drawTerrain(group, this.covered, { around, textures, rocks });
      const drawMs = this.host.now() - start;
      const frame = chunkFrame(group);
      if (chunk) {
        chunk.graphics.destroy();
        Object.assign(chunk, { key, graphics, frame, dirty: true, drawMs });
      } else {
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
          resolution: 0,
          dirty: true,
          drawMs,
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
    for (const sprite of [chunk.sprite, chunk.grey]) {
      if (sprite.texture !== Texture.EMPTY) sprite.texture.destroy(true);
      sprite.destroy();
    }
  }

  private bakeTerrain(): void {
    // The void's foam first: the last bake reported (`bakeMs`) is a chunk's when both bake.
    for (const chunk of [...this.voidFoamBakes.values(), ...this.chunks.values()]) {
      const resolution = this.bakeResolution(chunk.frame);
      const colour = chunk.dirty || resolution !== chunk.resolution;
      // The grayscale twin only while the view has fog (CLI-03n); a hub never bakes it.
      const grey = this.fogOn && (colour || chunk.greyStale);
      if (!colour && !grey) continue;
      const start = this.host.now();
      if (colour) {
        const old = chunk.sprite.texture;
        chunk.sprite.texture = this.surface.bake(chunk.graphics, chunk.frame, resolution);
        chunk.sprite.position.set(chunk.frame.x, chunk.frame.y);
        if (old !== Texture.EMPTY) old.destroy(true);
        chunk.dirty = false;
        chunk.resolution = resolution;
        chunk.greyStale = true;
      }
      if (grey) {
        // Through the filter once, into a texture: no filter runs in a frame.
        const old = chunk.grey.texture;
        chunk.grey.texture = this.surface.bake(chunk.graphics, chunk.frame, resolution, true);
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
    const key = sorted.map((s) => `${s.key}@${s.at.x},${s.at.y}`).join(" ");
    if (key === this.structuresKey) return;
    this.structuresKey = key;
    for (const node of this.structureNodes.values()) node.destroy({ children: true });
    this.structureNodes.clear();
    this.covered = new Set(sorted.flatMap((s) => s.covers.map((t) => `${t.x},${t.y}`)));
    for (const structure of sorted) {
      const node = this.createStructure(structure);
      this.actorsLayer.addChild(node);
      this.structureNodes.set(structure.key, node);
    }
  }

  private createStructure(structure: ViewStructure): Container {
    const base = tileToPixel(structure.at);
    const container = new Container();
    container.position.set(base.x, base.y);
    container.zIndex = base.y - 0.001;
    const texture = this.library?.get(structure.sprite)?.animations[STILL]?.textures[0];
    if (texture) {
      const sprite = new Sprite(texture);
      const anchor = texture.defaultAnchor;
      sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
      if (structure.mirror) sprite.scale.x = -1;
      container.addChild(sprite);
    } else {
      container.addChild(drawStructure(structure));
    }
    return container;
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
    return node.children[0] instanceof Sprite;
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
    if (!this.idleOn || this.nodes.size === 0) return null;
    let next = Infinity;
    for (const node of this.nodes.values()) {
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
