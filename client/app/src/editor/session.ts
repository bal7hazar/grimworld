import type { Tile } from "../render/view";
import { fitChunks, nudge } from "./fit";
import { History } from "./history";
import type { EditorTool } from "./keys";
import {
  BRUSH_MAX,
  type Change,
  FLOOR,
  type MapDocument,
  type Swatch,
  type TerrainValue,
  brushAt,
  erase,
  fill,
  isZone,
  outlineFromFloor,
  paint,
  pick,
} from "./model";
import { DEFAULT_LAYERS, LAYER_NAMES, type Layers } from "./view";

/** Which palette group Paint uses (§2.3). */
export type PaletteGroup = "terrain" | "ground";

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
  /** The stroke's mode: what a drag does, fixed at its start. */
  private stroke: "brush" | "erase" | "outlineIn" | "outlineOut" | null = null;

  constructor(
    readonly doc: MapDocument,
    private readonly onChange: () => void = () => {},
  ) {}

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

  /** The hexes under the brush at a hex, for the tool armed (Fill and Pick take one). */
  footprint(tile: Tile): Tile[] {
    const radius = this.tool === "fill" || this.tool === "pick" ? 0 : this.brush;
    return brushAt(tile, radius);
  }

  private record(changes: readonly Change[]): void {
    if (changes.length === 0) return;
    this.history.record(this.doc, changes);
    this.revision += 1;
    this.onChange();
  }

  /** A press on the canvas (§3): left, or right (`erase`), with Alt for Pick. */
  strokeStart(tile: Tile, how: { readonly erase: boolean; readonly alt: boolean }): void {
    this.said = "";
    this.stroke = null;
    if (how.alt && !how.erase) {
      this.pickAt(tile);
      return;
    }
    switch (this.tool) {
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
      }
      // Applied hex by hex, so that a later hex of the same move sees the earlier ones.
      this.record(step);
    }
  }

  strokeEnd(): void {
    this.stroke = null;
    this.history.end();
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
    if (this.history.undo(this.doc)) {
      this.revision += 1;
      this.onChange();
    }
  }

  redo(): void {
    if (this.stroke) this.strokeEnd();
    if (this.history.redo(this.doc)) {
      this.revision += 1;
      this.onChange();
    }
  }
}
