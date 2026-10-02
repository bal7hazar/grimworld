import { type HubPlace, type HubView, hubPoint } from "../render/hubView";
import { STEP_MS } from "../render/renderer";
import type { FrameHost } from "../render/scheduler";
import type { Facing, Tile } from "../render/view";
import { TILE_WIDTH, neighbours } from "./coords";

/**
 * The player's adventurer walking a hub's hex grid (CLI-03f, D-196): presentation, not a rule. The
 * chain knows only which hub an adventurer is in (D-03); the hex inside it is never sent, checked
 * or stored, so this module decides nothing the chain or `client/sim` decides. It reuses the room's
 * geometry (`input/coords.ts`) and pace, and none of its rules (`sandbox/placeholders.ts`).
 */

/** The pace of a hub walk: one step every `HUB_STEP_MS`, the room's step (the owner's eye). */
export const HUB_STEP_MS = STEP_MS;

/**
 * How far inside the illustration a hex's centre stands to be walkable, in art pixels: half a hex.
 * The tileset's edge cells are grass but for their outer few pixels, where they meet the water.
 */
export const EDGE_MARGIN = TILE_WIDTH / 2;

/** A building's rows behind its base row, blocked for the walk, when the fixture gives none. */
export const DEFAULT_DEPTH = 1;

const key = (tile: Tile) => `${tile.x},${tile.y}`;
const same = (a: Tile, b: Tile) => a.x === b.x && a.y === b.y;
/** The lower tile index first: `y`, then `x` (the room's reading order). */
const lower = (a: Tile, b: Tile) => a.y - b.y || a.x - b.x;

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

/**
 * Which hexes the adventurer may stand on: the centre on the island's grass (`EDGE_MARGIN` inside
 * the illustration), and nothing standing there. A place blocks its footprint but its door; a
 * decor building blocks its whole footprint; a prop and a present adventurer block their hex. The
 * drawn path is no constraint.
 */
export function hubWalkable(view: HubView): (tile: Tile) => boolean {
  const blocked = new Set<string>();
  for (const place of view.places) {
    for (const t of footprint(view, place)) if (!same(t, place.at)) blocked.add(key(t));
  }
  for (const decor of view.decor) for (const t of footprint(view, decor)) blocked.add(key(t));
  for (const prop of view.props) blocked.add(key(prop.at));
  for (const figure of view.figures) blocked.add(key(figure.at));
  return (tile) => {
    const p = hubPoint(view, tile);
    const inside =
      p.x >= EDGE_MARGIN &&
      p.x <= view.width - EDGE_MARGIN &&
      p.y >= EDGE_MARGIN &&
      p.y <= view.height - EDGE_MARGIN;
    return inside && !blocked.has(key(tile));
  };
}

/**
 * The shortest walk from `from` to `to` over the walkable hexes, first step first, `from` left out:
 * `[]` when already there, null when `to` is blocked or out of reach. Breadth first, the
 * neighbours taken lowest `y`, then `x` first, so two equal walks always resolve the same way.
 */
export function hubPath(view: HubView, from: Tile, to: Tile): Tile[] | null {
  if (same(from, to)) return [];
  const walkable = hubWalkable(view);
  if (!walkable(to)) return null;
  const cameFrom = new Map<string, Tile | null>([[key(from), null]]);
  const reached: Tile[] = [from];
  for (let i = 0; i < reached.length && !cameFrom.has(key(to)); i++) {
    const tile = reached[i]!;
    for (const next of neighbours(tile).sort(lower)) {
      if (cameFrom.has(key(next)) || !walkable(next)) continue;
      cameFrom.set(key(next), tile);
      reached.push(next);
    }
  }
  if (!cameFrom.has(key(to))) return null;
  const path: Tile[] = [];
  for (let t: Tile | null = to; t && !same(t, from); t = cameFrom.get(key(t)) ?? null) {
    path.unshift(t);
  }
  return path;
}

/** The direction of one step, in the library's numbering; East when the hexes are not adjacent. */
export function stepFacing(from: Tile, to: Tile): Facing {
  const d = neighbours(from).findIndex((n) => same(n, to));
  return (d < 0 ? 0 : d) as Facing;
}

/** The place whose door is this hex, if any: a walk that ends there opens it. */
export function doorAt(view: HubView, tile: Tile): HubPlace | null {
  return view.places.find((p) => same(p.at, tile)) ?? null;
}

/** Timers and visibility of the host (the renderer's `FrameHost` is one). */
export type WalkTimers = Pick<FrameHost, "setTimer" | "clearTimer" | "hidden" | "onVisibilityChange">;

/** Where the walker is: its hex (the one it steps to during a step), its facing, its goal. */
export interface WalkerState {
  readonly at: Tile;
  readonly facing: Facing;
  readonly target: Tile | null;
}

/**
 * A hub walk on the host's timers, as the room's `SandboxSession` walks a queue: the first step on
 * the tap, each next one `stepMs` later, and the walk's end `stepMs` after its last step, once
 * that step is drawn; then the walk's `then` (a place opening). Nothing is scheduled once it ends.
 * While the page is hidden it pauses, and it resumes when the page shows again.
 */
export class HubWalker {
  private current: WalkerState;
  private path: Tile[] = [];
  private then: (() => void) | null = null;
  private timer: number | null = null;
  private readonly stepMs: number;
  private readonly unsubscribe: () => void;

  constructor(
    private readonly view: HubView,
    start: Tile,
    private readonly timers: WalkTimers,
    private readonly options: {
      readonly facing?: Facing;
      readonly stepMs?: number;
      readonly onChange?: (state: WalkerState) => void;
    } = {},
  ) {
    this.current = { at: start, facing: options.facing ?? 0, target: null };
    this.stepMs = options.stepMs ?? HUB_STEP_MS;
    this.unsubscribe = timers.onVisibilityChange(() => this.visibilityChanged());
  }

  get state(): WalkerState {
    return this.current;
  }

  walking(): boolean {
    return this.current.target !== null;
  }

  /**
   * Walks to `tile`, then calls `then`. During a step, the new walk starts from the hex being
   * stepped to, once that step ends. False when `tile` cannot be reached: nothing changes.
   */
  walkTo(tile: Tile, then?: () => void): boolean {
    const path = hubPath(this.view, this.current.at, tile);
    if (!path) return false;
    this.path = path;
    this.then = then ?? null;
    this.set({ ...this.current, target: tile });
    if (this.timer === null && !this.timers.hidden()) this.walkOn();
    return true;
  }

  /** Ends the walk where it stands: nothing more is stepped, nothing opens. */
  stop(): void {
    this.stopTimer();
    this.path = [];
    this.then = null;
    if (this.current.target) this.set({ ...this.current, target: null });
  }

  destroy(): void {
    this.stopTimer();
    this.path = [];
    this.then = null;
    this.unsubscribe();
  }

  private walkOn(): void {
    this.timer = null;
    // Hidden: paused; the walk goes on once the page shows again.
    if (this.timers.hidden()) return;
    const next = this.path.shift();
    if (!next) {
      const then = this.then;
      this.then = null;
      this.set({ ...this.current, target: null });
      then?.();
      return;
    }
    this.set({ at: next, facing: stepFacing(this.current.at, next), target: this.current.target });
    this.timer = this.timers.setTimer(() => this.walkOn(), this.stepMs);
  }

  private visibilityChanged(): void {
    if (this.timers.hidden()) {
      this.stopTimer();
    } else if (this.walking() && this.timer === null) {
      this.timer = this.timers.setTimer(() => this.walkOn(), this.stepMs);
    }
  }

  private stopTimer(): void {
    if (this.timer !== null) this.timers.clearTimer(this.timer);
    this.timer = null;
  }

  private set(state: WalkerState): void {
    this.current = state;
    this.options.onChange?.(state);
  }
}
