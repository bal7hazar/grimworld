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
  drawMark,
  drawOverlay,
  drawTerrain,
  drawWedge,
} from "./shapes";
import type { SpriteArt, SpriteLibrary } from "./sprites";
import type { ViewActor, ViewState, ViewTile } from "./view";

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
  /** Renders `frame` of `target` into a texture of `resolution` pixels per world pixel. */
  bake(target: Container, frame: Rectangle, resolution: number): Texture;
  /** Renders `container` (a root: no parent) into `target`, cleared first. */
  renderTo(container: Container, target: RenderTexture): void;
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

/** The terrain is baked chunk by chunk (ADR-0006: chunks of 15 × 15). */
export const BAKE_CHUNK = 15;

interface ChunkBake {
  key: string;
  graphics: Graphics;
  frame: Rectangle;
  readonly sprite: Sprite;
  resolution: number;
  dirty: boolean;
}

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
  /** `sharp` only: the offscreen pass, `n` canvas pixels per art pixel, its size in texels. */
  readonly offscreen: {
    readonly n: number;
    readonly width: number;
    readonly height: number;
  } | null;
  /** Tile width, CSS px. */
  readonly tileWidth: number;
  /** Tiles across the viewport's width. */
  readonly across: number;
}

/** Durations of what animates on an input, in ms. */
export const STEP_MS = 180;
export const TURN_MS = 120;
export const CAMERA_MS = 260;
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
  readonly onDraw?: (stats: FrameStats) => void;
}

/** The `sharp` mode's offscreen texture: the world at an integer scale, drawn down linearly. */
interface Offscreen {
  readonly texture: RenderTexture;
  readonly width: number;
  readonly height: number;
  readonly resolution: number;
  readonly n: number;
}

/**
 * Draws a `ViewState` on demand. Every change (a view, the camera, the size) asks for one frame;
 * a step, a turn and the camera's pan ask for frames until they end; idle animations ask for one
 * frame per change of a sprite's frame, at most 15 per second, and none when they are off.
 */
export class Renderer implements FrameClient {
  readonly scheduler: FrameScheduler;
  private readonly world = new Container();
  private readonly ground = new Container();
  private readonly overlay = new Graphics();
  private readonly actorsLayer = new Container({ sortableChildren: true });
  private readonly nodes = new Map<number, ActorNode>();
  private readonly chunks = new Map<string, ChunkBake>();
  private view: ViewState | null = null;
  private viewport: Viewport = { width: 1, height: 1 };
  private camera: Camera = { centre: { x: 0, y: 0 }, scale: 1 };
  /** The scale asked for (fit, pinch, wheel); `camera.scale` is it, snapped in `snap` mode. */
  private wanted = 1;
  private mode: ScaleMode;
  /** `sharp`: the sprite that draws the offscreen texture down to the screen, linearly. */
  private readonly screen = new Sprite(Texture.EMPTY);
  private offscreen: Offscreen | null = null;
  private cameraTween: Tween | null = null;
  private zoomed = false;
  private zoom: ZoomSettings;
  private idleOn: boolean;
  private lastIdle = -Infinity;
  private library: SpriteLibrary | null;
  private readonly scales = new Map<string, number>();

  constructor(
    private readonly surface: Surface,
    private readonly host: FrameHost,
    options: RendererOptions = {},
  ) {
    this.library = options.library ?? null;
    this.zoom = options.zoom ?? DEFAULT_ZOOM;
    this.idleOn = options.idle ?? true;
    this.mode = options.mode ?? "continuous";
    this.scheduler = new FrameScheduler(host, this, options.onDraw);
    this.world.addChild(this.ground, this.overlay, this.actorsLayer);
    this.mountStage();
  }

  // --- inputs -------------------------------------------------------------------------------

  setView(view: ViewState): void {
    const previous = this.view;
    this.view = view;
    const now = this.host.now();
    this.syncChunks(view.tiles);
    drawOverlay(this.overlay, view);
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
    if (this.view) this.syncActors(this.view, this.host.now());
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

  cameraState(): { camera: Camera; viewport: Viewport } {
    return { camera: this.camera, viewport: this.viewport };
  }

  /** What the current zoom gives on screen. */
  zoomInfo(): ZoomInfo {
    const { scale } = this.camera;
    const { resolution, devicePixelRatio } = this.surface;
    const deviceScale = scale * devicePixelRatio;
    const plan = this.mode === "sharp" ? this.offscreenPlan() : null;
    return {
      mode: this.mode,
      devicePixelRatio,
      resolution,
      scale,
      canvasScale: scale * resolution,
      deviceScale,
      // Whole on the screen only when the canvas is the screen (see scaling.ts).
      integer: resolution === devicePixelRatio && isWhole(deviceScale),
      offscreen: plan && {
        n: plan.n,
        width: Math.round(plan.width * resolution),
        height: Math.round(plan.height * resolution),
      },
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
    this.dropOffscreen();
    this.screen.destroy();
    this.world.destroy({ children: true });
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
    if (this.mode !== "sharp") {
      this.dropOffscreen();
      this.placeWorld(scale, this.viewport.width, this.viewport.height, centre);
      this.surface.render();
      return;
    }
    // Sharp bilinear: the world nearest-neighbour at `n` texels per art pixel into the offscreen
    // texture (one extra pass, only in a frame being drawn), then that texture drawn down to the
    // target scale, linearly, by `screen`.
    const plan = this.offscreenPlan();
    const offscreen = this.ensureOffscreen(plan);
    this.placeWorld(scale * plan.oversample, plan.width, plan.height, centre);
    this.surface.renderTo(this.world, offscreen.texture);
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

  /** The world on the stage, or (`sharp`) the offscreen texture's sprite with the world as a root. */
  private mountStage(): void {
    this.surface.stage.removeChildren();
    if (this.mode === "sharp") this.surface.stage.addChild(this.screen);
    else this.surface.stage.addChild(this.world);
  }

  /**
   * `sharp`: the offscreen texture's size (CSS px, at the canvas resolution) and oversampling,
   * the integer `n` lowered only if the GPU's texture limit requires it.
   */
  private offscreenPlan(): { n: number; oversample: number; width: number; height: number } {
    const { resolution, maxTextureSize } = this.surface;
    const { width, height } = this.viewport;
    const { n, oversample } = sharpFactor(this.camera.scale, resolution);
    const limit = maxTextureSize / (Math.max(width, height) * resolution);
    const k = Math.max(1, Math.min(oversample, limit));
    return {
      n: k === oversample ? n : this.camera.scale * resolution * k,
      oversample: k,
      width: Math.ceil(width * k),
      height: Math.ceil(height * k),
    };
  }

  /** Keeps the offscreen texture while its size holds; destroys and remakes it on zoom or resize. */
  private ensureOffscreen(plan: { n: number; width: number; height: number }): Offscreen {
    const resolution = this.surface.resolution;
    const current = this.offscreen;
    if (
      current &&
      current.width === plan.width &&
      current.height === plan.height &&
      current.resolution === resolution
    ) {
      return current;
    }
    this.dropOffscreen();
    const texture = RenderTexture.create({
      width: plan.width,
      height: plan.height,
      resolution,
      scaleMode: "linear",
      antialias: false,
    });
    this.offscreen = { texture, width: plan.width, height: plan.height, resolution, n: plan.n };
    this.screen.texture = texture;
    return this.offscreen;
  }

  private dropOffscreen(): void {
    if (!this.offscreen) return;
    this.screen.texture = Texture.EMPTY;
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
    const oversample = this.mode === "sharp" ? this.offscreenPlan().oversample : 1;
    const wanted = this.camera.scale * this.surface.resolution * oversample;
    const stepped = 2 ** (Math.round(2 * Math.log2(wanted)) / 2);
    const side = Math.max(frame.width, frame.height, 1);
    return Math.min(stepped, this.surface.maxTextureSize / side);
  }

  /** Groups the tiles by chunk; a chunk whose tiles' kinds changed is drawn again, and rebaked. */
  private syncChunks(tiles: readonly ViewTile[]): void {
    const groups = new Map<string, ViewTile[]>();
    for (const tile of tiles) {
      const id = `${Math.floor(tile.x / BAKE_CHUNK)},${Math.floor(tile.y / BAKE_CHUNK)}`;
      let group = groups.get(id);
      if (!group) groups.set(id, (group = []));
      group.push(tile);
    }
    for (const [id, group] of groups) {
      const key = group.map((t) => `${t.x},${t.y}${t.kind[0]}`).join("");
      const chunk = this.chunks.get(id);
      if (chunk?.key === key) continue;
      const graphics = drawTerrain(group);
      const b = graphics.getLocalBounds();
      const frame = new Rectangle(
        Math.floor(b.minX),
        Math.floor(b.minY),
        Math.ceil(b.maxX) - Math.floor(b.minX),
        Math.ceil(b.maxY) - Math.floor(b.minY),
      );
      if (chunk) {
        chunk.graphics.destroy();
        Object.assign(chunk, { key, graphics, frame, dirty: true });
      } else {
        const sprite = new Sprite(Texture.EMPTY);
        this.ground.addChild(sprite);
        this.chunks.set(id, { key, graphics, frame, sprite, resolution: 0, dirty: true });
      }
    }
    for (const [id, chunk] of this.chunks) {
      if (!groups.has(id)) {
        this.dropChunk(chunk);
        this.chunks.delete(id);
      }
    }
  }

  private dropChunk(chunk: ChunkBake): void {
    chunk.graphics.destroy();
    if (chunk.sprite.texture !== Texture.EMPTY) chunk.sprite.texture.destroy(true);
    chunk.sprite.destroy();
  }

  private bakeTerrain(): void {
    for (const chunk of this.chunks.values()) {
      const resolution = this.bakeResolution(chunk.frame);
      if (!chunk.dirty && resolution === chunk.resolution) continue;
      const old = chunk.sprite.texture;
      chunk.sprite.texture = this.surface.bake(chunk.graphics, chunk.frame, resolution);
      chunk.sprite.position.set(chunk.frame.x, chunk.frame.y);
      if (old !== Texture.EMPTY) old.destroy(true);
      chunk.dirty = false;
      chunk.resolution = resolution;
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
          ? { from: [from.x, from.y], to: [target.x, target.y], start: now, duration: STEP_MS }
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

  /** Scale and mirror of the body, and the mark's height over it. */
  private placeBody(node: ActorNode): void {
    const name = spriteName(node.actor);
    const scale = this.spriteScale(name);
    node.body.scale.set(isMirrored(node.actor.facing) ? -scale : scale, scale);
    const height = node.art ? node.art.baseline : SHAPE_HEIGHT[name];
    if (node.mark) node.mark.position.set(0, -height * scale - 14);
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
}
