import type { Tile } from "../render/view";
import { fitChunks, nudge } from "./fit";
import { History } from "./history";
import type { EditorTool } from "./keys";
import {
  BRUSH_MAX,
  type Cell,
  type Change,
  FLOOR,
  type MapDocument,
  type MapMeta,
  type Swatch,
  type TerrainValue,
  brushAt,
  erase,
  fill,
  isZone,
  keyOf,
  nextObjectId,
  objectsAt,
  outlineFromFloor,
  paint,
  pick,
  tileOfKey,
} from "./model";
import {
  type MapObject,
  type PlaceChoice,
  SINGLE,
  mirrorable,
  movedBy,
  newObject,
} from "./objects";
import { DEFAULT_LAYERS, LAYER_NAMES, type Layers } from "./view";

/** Which palette group Paint uses (§2.3). */
export type PaletteGroup = "terrain" | "ground";

/** What Select holds (§2.4): hexes and objects, by key and id. */
export interface Selection {
  readonly hexes: ReadonlySet<number>;
  readonly objects: ReadonlySet<number>;
}

export const NOTHING: Selection = { hexes: new Set(), objects: new Set() };

/** What Copy keeps: hexes and objects, from an anchor on an even row (§4.1, the rows' parity). */
export interface Clip {
  readonly cells: readonly { readonly dx: number; readonly dy: number; readonly cell: Cell }[];
  readonly objects: readonly { readonly dx: number; readonly dy: number; readonly object: MapObject }[];
}

const mod2 = (n: number) => ((n % 2) + 2) % 2;

/** A row of the same parity as an even anchor's: the nearest even row at or below (§4.1). */
export const evenRowOf = (y: number) => y - mod2(y);

/** A box of hexes between two corners, in tile coordinates. */
export function inBox(a: Tile, b: Tile, t: Tile): boolean {
  return (
    t.x >= Math.min(a.x, b.x) &&
    t.x <= Math.max(a.x, b.x) &&
    t.y >= Math.min(a.y, b.y) &&
    t.y <= Math.max(a.y, b.y)
  );
}

/**
 * One map open in the editor: the document, its history, the armed tool, the palette, the brush
 * and the layers. The pointer's strokes come in as hexes; no DOM here, so that the tools are tested
 * without a browser.
 */
export class EditorSession {
  readonly history = new History();
  tool: EditorTool = "paint";
  /** The tool Pick returns to. */
  private previous: EditorTool = "paint";
  group: PaletteGroup = "terrain";
  terrain: TerrainValue = FLOOR;
  ground = 0;
  /** Fill armed from the outline tool fills the outline (§2.5). */
  fillOutline = false;
  /** The brush's radius, 0 to `BRUSH_MAX`. */
  brush = 0;
  layers: Layers = DEFAULT_LAYERS;
  /** The layer `K` has focused in the layers bar. */
  layerFocus = 0;
  /** Bumped on every change of the document. */
  revision = 0;
  /** The revision of the last fit or nudge: a later one means the map was painted since. */
  originRevision = 0;
  /** What the status bar says after a refused action, until the next one. */
  said = "";
  /** What Place puts down (§2.3, the palette's objects). */
  placing: PlaceChoice;
  selection: Selection = NOTHING;
  /** The hex the inspector shows: a right click with Select or Place, or a click of Select. */
  inspected: Tile | null = null;
  /** Select's box being dragged, and Move's drag of the selected objects. */
  box: { readonly from: Tile; readonly to: Tile; readonly add: boolean } | null = null;
  moving: { readonly from: Tile; readonly to: Tile } | null = null;
  /** What Copy or Cut kept; a paste follows the pointer while `pasting`. */
  clip: Clip | null = null;
  pasting = false;
  /** The stroke's mode: what a drag does, fixed at its start. */
  private stroke: "brush" | "erase" | "outlineIn" | "outlineOut" | "box" | "move" | null = null;

  constructor(
    readonly doc: MapDocument,
    private readonly onChange: () => void = () => {},
  ) {
    this.placing = { kind: isZone(doc) ? "entry" : "arrival" };
  }

  get zone(): boolean {
    return isZone(this.doc);
  }

  get stroking(): boolean {
    return this.stroke !== null;
  }

  /** What Paint puts down. */
  swatch(): Swatch {
    return this.group === "terrain"
      ? { layer: "terrain", value: this.terrain }
      : { layer: "ground", value: this.ground };
  }

  armTool(tool: EditorTool): void {
    this.said = "";
    if (tool === "outline" && !this.zone) {
      this.said = "A town has no outline: paint its island as ground.";
      this.onChange();
      return;
    }
    if (tool === "fill") this.fillOutline = this.tool === "outline";
    if (tool === "pick" && this.tool !== "pick") this.previous = this.tool;
    this.tool = tool;
    this.onChange();
  }

  /** A swatch chosen in the palette arms Paint (§2.3). */
  choose(group: PaletteGroup, value: number): void {
    this.group = group;
    if (group === "terrain") this.terrain = value as TerrainValue;
    else this.ground = value;
    this.tool = "paint";
    this.fillOutline = false;
    this.said = "";
    this.onChange();
  }

  setBrush(radius: number): void {
    this.brush = Math.max(0, Math.min(BRUSH_MAX, radius));
    this.onChange();
  }

  setLayers(layers: Layers): void {
    this.layers = layers;
    this.onChange();
  }

  toggleLayer(name: keyof Layers): void {
    this.setLayers({ ...this.layers, [name]: !this.layers[name] });
  }

  /** `K`: the next layer of the bar; `Shift+K` toggles it. */
  focusNextLayer(): void {
    this.layerFocus = (this.layerFocus + 1) % LAYER_NAMES.length;
    this.onChange();
  }

  /** The hexes under the brush at a hex, for the tool armed (Fill, Pick, Select, Place take one). */
  footprint(tile: Tile): Tile[] {
    const one = ["fill", "pick", "select", "place"].includes(this.tool) || this.pasting;
    return brushAt(tile, one ? 0 : this.brush);
  }

  private record(changes: readonly Change[]): void {
    if (changes.length === 0) return;
    this.history.record(this.doc, changes);
    this.revision += 1;
    this.onChange();
  }

  /** One step of the history: a command's changes (§3, undo). */
  private step(changes: readonly Change[]): void {
    this.history.begin();
    this.record(changes);
    this.history.end();
  }

  /** The palette's object chosen: Place is armed (§2.3). */
  choosePlace(choice: PlaceChoice): void {
    this.placing = choice;
    this.tool = "place";
    this.said = "";
    this.onChange();
  }

  /** A press on the canvas (§3): left, or right (`erase`), with Alt for Pick, Shift to add. */
  strokeStart(
    tile: Tile,
    how: { readonly erase: boolean; readonly alt: boolean; readonly shift?: boolean },
  ): void {
    this.said = "";
    this.stroke = null;
    if (this.pasting) {
      if (how.erase) this.endPaste();
      else this.pasteAt(tile);
      return;
    }
    if (how.alt && !how.erase) {
      this.pickAt(tile);
      return;
    }
    switch (this.tool) {
      case "select":
      case "place":
        // Right click inspects (design/11 l.170).
        if (how.erase) {
          this.inspect(tile);
          return;
        }
        if (this.tool === "place") {
          this.placeAt(tile);
          return;
        }
        if (!how.shift && objectsAt(this.doc, tile).some((id) => this.selection.objects.has(id))) {
          this.moving = { from: tile, to: tile };
          this.stroke = "move";
        } else {
          this.box = { from: tile, to: tile, add: how.shift ?? false };
          this.stroke = "box";
        }
        this.onChange();
        return;
      case "pick":
        if (!how.erase) this.pickAt(tile);
        return;
      case "fill": {
        // Right click fills the outline's outside; on terrain it does nothing.
        if (how.erase && !this.fillOutline) return;
        const swatch: Swatch = this.fillOutline
          ? { layer: "outline", value: how.erase ? 0 : 1 }
          : this.swatch();
        const changes = fill(this.doc, tile, swatch);
        if (typeof changes === "string") {
          this.said = changes;
          this.onChange();
          return;
        }
        this.history.begin();
        this.record(changes);
        this.history.end();
        return;
      }
      case "outline":
        this.stroke = how.erase ? "outlineOut" : "outlineIn";
        break;
      case "erase":
        this.stroke = "erase";
        break;
      case "paint":
        this.stroke = how.erase ? "erase" : "brush";
        break;
    }
    this.history.begin();
    this.strokeMove([tile]);
  }

  strokeMove(tiles: readonly Tile[]): void {
    if (!this.stroke) return;
    const last = tiles.at(-1);
    if (this.stroke === "box" || this.stroke === "move") {
      if (!last) return;
      if (this.box) this.box = { ...this.box, to: last };
      if (this.moving) this.moving = { ...this.moving, to: last };
      this.onChange();
      return;
    }
    for (const tile of tiles) {
      const under = brushAt(tile, this.brush);
      let step: Change[];
      switch (this.stroke) {
        case "brush":
          step = paint(this.doc, under, this.swatch());
          break;
        case "erase":
          step = erase(this.doc, under);
          break;
        case "outlineIn":
          step = paint(this.doc, under, { layer: "outline", value: 1 });
          break;
        case "outlineOut":
          step = erase(this.doc, under, true);
          break;
        default:
          step = [];
      }
      // Applied hex by hex, so that a later hex of the same move sees the earlier ones.
      this.record(step);
    }
  }

  strokeEnd(): void {
    const stroke = this.stroke;
    this.stroke = null;
    this.history.end();
    if (stroke === "box" && this.box) this.endBox(this.box);
    if (stroke === "move" && this.moving) this.endMove(this.moving);
    this.box = null;
    this.moving = null;
  }

  // --- Select, Move, Place (§3) ------------------------------------------------------------------

  /** Escape (§3): ends a paste, a box or a drag; clears the selection. */
  escape(): void {
    if (this.pasting) {
      this.endPaste();
      return;
    }
    if (this.stroke) {
      // A box or a move dropped; a brush stroke ends as one step.
      this.box = null;
      this.moving = null;
      this.strokeEnd();
      this.onChange();
      return;
    }
    this.select(NOTHING);
  }

  select(selection: Selection, inspected: Tile | null = null): void {
    this.selection = selection;
    this.inspected = inspected;
    this.onChange();
  }

  /** The hex the inspector shows, its objects selected (right click with Select or Place). */
  inspect(tile: Tile): void {
    this.select({ hexes: new Set(), objects: new Set(objectsAt(this.doc, tile)) }, tile);
  }

  /**
   * A box from `from` to `to`: its painted hexes and its objects. A click (a box of one hex)
   * selects the hex's last placed object, or the hex. Shift adds to the selection.
   */
  private endBox(box: { from: Tile; to: Tile; add: boolean }): void {
    const hexes = new Set<number>(box.add ? this.selection.hexes : []);
    const objects = new Set<number>(box.add ? this.selection.objects : []);
    const click = box.from.x === box.to.x && box.from.y === box.to.y;
    if (click) {
      const here = objectsAt(this.doc, box.from);
      if (here.length > 0) objects.add(here.at(-1)!);
      else hexes.add(keyOf(box.from));
    } else {
      for (const key of this.doc.hexes.keys()) {
        if (inBox(box.from, box.to, tileOfKey(key))) hexes.add(key);
      }
      for (const [id, object] of this.doc.objects) {
        if (inBox(box.from, box.to, object.at)) objects.add(id);
      }
    }
    this.select({ hexes, objects }, click ? box.from : null);
  }

  /**
   * The drag of selected objects ends: they move as one step. More than one keeps the rows'
   * parity (§4.1): the move's rows snap to an even count, so the group keeps its shape.
   */
  private endMove(move: { from: Tile; to: Tile }): void {
    const dx = move.to.x - move.from.x;
    let dy = move.to.y - move.from.y;
    if (this.selection.objects.size > 1) dy = 2 * Math.round(dy / 2);
    if (dx === 0 && dy === 0) return;
    const changes: Change[] = [];
    for (const id of this.selection.objects) {
      const before = this.doc.objects.get(id);
      if (before) changes.push({ object: id, before, after: movedBy(before, dx, dy) });
    }
    this.step(changes);
    this.onChange();
  }

  /** The offset a move in progress shows, the rows' parity kept as `endMove` keeps it. */
  moveOffset(): Tile | null {
    if (!this.moving) return null;
    const dx = this.moving.to.x - this.moving.from.x;
    let dy = this.moving.to.y - this.moving.from.y;
    if (this.selection.objects.size > 1) dy = 2 * Math.round(dy / 2);
    return { x: dx, y: dy };
  }

  /**
   * Place (§3): the palette's object on the hex, selected. One entry (and one arrival) a map:
   * placing it again moves it. An object of the same kind already on the hex is selected instead.
   */
  placeAt(tile: Tile): void {
    const kind = this.placing.kind;
    const zoneKinds = ["entry", "gate", "candidate", "feature", "spawn"];
    if (zoneKinds.includes(kind) !== this.zone) return;
    const here = objectsAt(this.doc, tile).find((id) => this.doc.objects.get(id)!.kind === kind);
    if (here !== undefined) {
      this.select({ hexes: new Set(), objects: new Set([here]) }, tile);
      return;
    }
    const single = SINGLE.includes(kind)
      ? [...this.doc.objects].find(([, o]) => o.kind === kind)
      : undefined;
    let id: number;
    if (single) {
      id = single[0];
      this.step([{ object: id, before: single[1], after: { ...single[1], at: tile } }]);
    } else {
      id = nextObjectId(this.doc);
      this.step([{ object: id, before: null, after: newObject(this.placing, tile) }]);
    }
    this.select({ hexes: new Set(), objects: new Set([id]) }, tile);
  }

  /** The inspector's edit of one object's fields (§2.4): one step. */
  editObject(id: number, after: MapObject): void {
    const before = this.doc.objects.get(id);
    if (!before || JSON.stringify(before) === JSON.stringify(after)) return;
    this.step([{ object: id, before, after }]);
  }

  /** The inspector's edit of the map's properties (§2.4): one step. */
  editMeta(meta: MapMeta): void {
    if (JSON.stringify(meta) === JSON.stringify(this.doc.meta)) return;
    this.step([{ meta, before: this.doc.meta }]);
  }

  /**
   * A quota removed from the list, with its candidates; the later quotas' candidates follow their
   * quota's new index. One step.
   */
  removeQuota(index: number): void {
    const quotas = this.doc.meta.quotas.filter((_, i) => i !== index);
    const changes: Change[] = [{ meta: { ...this.doc.meta, quotas }, before: this.doc.meta }];
    for (const [id, o] of this.doc.objects) {
      if (o.kind !== "candidate" || o.quota < index) continue;
      changes.push({
        object: id,
        before: o,
        after: o.quota === index ? null : { ...o, quota: o.quota - 1 },
      });
    }
    this.step(changes);
    this.select({
      hexes: this.selection.hexes,
      objects: new Set([...this.selection.objects].filter((id) => this.doc.objects.has(id))),
    });
  }

  /** "Set terrain to …" / "Set ground to …" on the selected hexes (§2.4, a group): one step. */
  paintSelection(swatch: Swatch): void {
    this.step(paint(this.doc, [...this.selection.hexes].map(tileOfKey), swatch));
  }

  /** Delete (§3): the selected objects removed and the selected hexes unpainted, one step. */
  deleteSelection(): void {
    const changes: Change[] = [];
    for (const id of this.selection.objects) {
      const before = this.doc.objects.get(id);
      if (before) changes.push({ object: id, before, after: null });
    }
    changes.push(...erase(this.doc, [...this.selection.hexes].map(tileOfKey)));
    this.step(changes);
    this.select(NOTHING);
  }

  /** Copy (§3): the selection, from an anchor on an even row so that a paste keeps the parity. */
  copy(): boolean {
    const tiles = [
      ...[...this.selection.hexes].map(tileOfKey),
      ...[...this.selection.objects].flatMap((id) => {
        const o = this.doc.objects.get(id);
        return o ? [o.at] : [];
      }),
    ];
    if (tiles.length === 0) {
      this.said = "Nothing selected to copy.";
      this.onChange();
      return false;
    }
    const ax = Math.min(...tiles.map((t) => t.x));
    const ay = evenRowOf(Math.min(...tiles.map((t) => t.y)));
    const cells: { dx: number; dy: number; cell: Cell }[] = [];
    for (const key of this.selection.hexes) {
      const cell = this.doc.hexes.get(key);
      if (cell === undefined) continue;
      const t = tileOfKey(key);
      cells.push({ dx: t.x - ax, dy: t.y - ay, cell });
    }
    const objects = [...this.selection.objects]
      .sort((a, b) => a - b)
      .flatMap((id) => {
        const object = this.doc.objects.get(id);
        return object ? [{ dx: object.at.x - ax, dy: object.at.y - ay, object }] : [];
      });
    this.clip = { cells, objects };
    this.onChange();
    return true;
  }

  /** Cut (§3): copy, then delete. */
  cut(): void {
    if (this.copy()) this.deleteSelection();
  }

  /** Paste (§3): the clip follows the pointer until a click. */
  paste(): void {
    if (!this.clip) {
      this.said = "Nothing to paste: copy first.";
      this.onChange();
      return;
    }
    this.pasting = true;
    this.onChange();
  }

  endPaste(): void {
    this.pasting = false;
    this.onChange();
  }

  /** Where the clip lands for a pointer on `tile`: its anchor on an even row (§4.1). */
  pasteOrigin(tile: Tile): Tile {
    return { x: tile.x, y: evenRowOf(tile.y) };
  }

  /**
   * The paste lands (one step): its hexes painted as copied, its objects added; an entry or an
   * arrival moves the map's own. The pasted things are selected.
   */
  pasteAt(tile: Tile): void {
    const clip = this.clip;
    if (!clip) return;
    const at = this.pasteOrigin(tile);
    const changes: Change[] = [];
    const hexes = new Set<number>();
    for (const { dx, dy, cell } of clip.cells) {
      const key = keyOf({ x: at.x + dx, y: at.y + dy });
      hexes.add(key);
      const before = this.doc.hexes.get(key) ?? null;
      if (before !== cell) changes.push({ key, before, after: cell });
    }
    const objects = new Set<number>();
    let id = nextObjectId(this.doc);
    for (const { dx, dy, object } of clip.objects) {
      const placed = { ...object, at: { x: at.x + dx, y: at.y + dy } };
      const single = SINGLE.includes(object.kind)
        ? [...this.doc.objects].find(([, o]) => o.kind === object.kind)
        : undefined;
      if (single) {
        changes.push({ object: single[0], before: single[1], after: placed });
        objects.add(single[0]);
      } else {
        changes.push({ object: id, before: null, after: placed });
        objects.add(id++);
      }
    }
    this.pasting = false;
    this.step(changes);
    this.select({ hexes, objects });
  }

  /** Mirror (§3, H): the selected buildings, decor and props, `mirror` on or off. One step. */
  mirror(): void {
    const changes: Change[] = [];
    for (const id of this.selection.objects) {
      const before = this.doc.objects.get(id);
      if (!before || !mirrorable(before) || !("mirror" in before)) continue;
      changes.push({ object: id, before, after: { ...before, mirror: !before.mirror } });
    }
    if (changes.length === 0) {
      this.said = "Mirror: select a building, a decor or a prop.";
      this.onChange();
      return;
    }
    this.step(changes);
  }

  private pickAt(tile: Tile): void {
    const found = pick(this.doc, tile);
    if (!found) return;
    this.terrain = found.terrain;
    this.ground = found.ground;
    if (this.tool === "pick") this.tool = this.previous;
    this.onChange();
  }

  /** "Outline from floor" (§2.5). */
  outlineFromFloor(from: Tile | null): void {
    if (!this.zone) return;
    const changes = outlineFromFloor(this.doc, from);
    if (changes.length === 0) {
      this.said = "No floor to outline.";
      this.onChange();
      return;
    }
    this.history.begin();
    this.record(changes);
    this.history.end();
  }

  /**
   * "Fit chunks" (D-216): the origin with the fewest chunks; the fitted grid's layer is shown. The
   * origin is the document's, saved with it, and not a step of the history.
   */
  fitChunks(): void {
    this.said = "";
    const best = fitChunks(this.doc);
    if (best === "empty") this.said = "Nothing to fit: paint the map first.";
    else if (best === "wide")
      this.said = "The painted hexes span more than 1000 hexes: not fitted.";
    else {
      this.doc.origin = { ...best.origin, how: "fitted" };
      this.originMoved();
      this.layers = { ...this.layers, seams: true };
    }
    this.onChange();
  }

  /** The origin moved by hand, one hex (`dx` West, `dy` North): the counts follow. */
  nudgeOrigin(dx: number, dy: number): void {
    this.said = "";
    this.doc.origin = nudge(this.doc.origin ?? { x: 0, y: 0 }, dx, dy);
    this.originMoved();
    this.layers = { ...this.layers, seams: true };
    this.onChange();
  }

  private originMoved(): void {
    // The draft keeps the origin: the document changed.
    this.revision += 1;
    this.originRevision = this.revision;
  }

  /** Painted since the last fit or nudge of this session. */
  get paintedSinceOrigin(): boolean {
    return this.doc.origin !== null && this.revision !== this.originRevision;
  }

  // A stroke in progress ends first: its changes become one step before the undo, and the moves
  // that follow draw nothing until the next press (CLI-09a's review, minor c).
  undo(): void {
    if (this.stroke) this.strokeEnd();
    if (this.history.undo(this.doc)) this.afterHistory();
  }

  redo(): void {
    if (this.stroke) this.strokeEnd();
    if (this.history.redo(this.doc)) this.afterHistory();
  }

  /** An undo or a redo: the selection keeps only objects that still exist. */
  private afterHistory(): void {
    this.revision += 1;
    const objects = [...this.selection.objects].filter((id) => this.doc.objects.has(id));
    if (objects.length !== this.selection.objects.size) {
      this.selection = { hexes: this.selection.hexes, objects: new Set(objects) };
    }
    this.onChange();
  }
}
