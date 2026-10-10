import type { Tile } from "../render/view";
import { FIT_SPAN_MAX, type Fitted, chunkAt, fitted } from "./fit";
import {
  CHUNK,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  SIZE_MAX,
  WALL,
  groundOfCell,
  isOutside,
  isZone,
  keyOf,
  paintedBox,
  SIDE_STEPS,
  sideOf,
  terrainOf,
  tileOfKey,
} from "./model";
import { type MapObject, OBJECT_NAMES, QUOTA_NAMES, kindOf, servicesOf } from "./objects";
import { bridgeHexes, doorOf, isPack } from "./pack";
import { doorSide } from "./palette";
import { deckKeys, footprintOf, townCovers } from "./walkWorld";
import checksText from "./export/checks.json?raw";
import { type Manifest, convert } from "./export/convert";
import { nameOf, toExport } from "./export/document";
import { Refused } from "./export/records";

/**
 * The validation (CLI-09b, brief §5): ENG-08's content checks for map records (**R**), the editor's
 * own (**E**), and the checks whose exact rule waited for ENG-08's spike (**○**). It runs on the
 * **fitted** map (D-216): chunk and tile indices in the fitted map's coordinates. A tool's checks,
 * not game rules (mandate §6): they live in the editor's folder.
 *
 * CLI-09c settles the ○ checks by ENG-08's converter: R-12's members are the zone's chunks, a
 * candidate counts against its chunk's caps (a Heart's against the 2 packs, the others' against the
 * 3 objects), E-17's seams hold by construction (P-2) and a seam with no crossing is not refused.
 * With a content manifest, the converter itself runs on the map's export (`export/convert.ts`): its
 * refusal is a finding under its check's id (`checks.json`), so that the editor refuses what the
 * converter refuses.
 *
 * Reachability is connectivity by hex neighbours over walkable hexes (`SIDE_STEPS`, the drawing's
 * neighbours), the reach `placeholders.ts`'s finder walks until CLI-02 gives `client/sim` its own.
 * A bridge's deck inside the outline is walkable there (D-227, ADR-0008 rule 1: the converter
 * writes it so), whatever is painted under it.
 */

export type Source = "R" | "E" | "○";
export type Severity = "error" | "warning" | "hint";

export interface Finding {
  /** The check's id in §5's table: `R-13`, `E-6`… */
  readonly check: string;
  readonly source: Source;
  readonly severity: Severity;
  readonly message: string;
  /** What Show selects: hexes of the editor's plane, and objects by id. */
  readonly hexes: readonly Tile[];
  readonly objects: readonly number[];
}

/** design/18 l.17-26: a biome's walkable share, in percent (E-13). */
export const WALKABLE_SHARE: Readonly<Record<string, readonly [number, number]>> = {
  meadow: [80, 90],
  forest: [60, 70],
  cave: [45, 55],
  ruin: [40, 50],
};

/** The chunk and tile index bound (`INDEX_BOUND`, `location.cairo:30`). */
const INDEX_BOUND = 225;
/** At most 6 quotas (ENG-08 l.55). */
export const QUOTAS_MAX = 6;
/** Per chunk (ENG-08 l.59, l.174; E-3 of ENG-05): spawn points and objects. */
export const SPAWNS_PER_CHUNK = 2;
export const OBJECTS_PER_CHUNK = 3;

const at = (o: MapObject) => o.at;
const where = (t: Tile) => `(${t.x}, ${t.y})`;

class Findings {
  readonly list: Finding[] = [];
  add(
    check: string,
    source: Source,
    severity: Severity,
    message: string,
    hexes: readonly Tile[] = [],
    objects: readonly number[] = [],
  ): void {
    this.list.push({ check, source, severity, message, hexes, objects });
  }
  error(check: string, message: string, hexes?: readonly Tile[], objects?: readonly number[]) {
    this.add(check, check.startsWith("R") ? "R" : "E", "error", message, hexes, objects);
  }
}

/** The objects of a kind, by id, in the order they were placed. */
function objectsOf<K extends MapObject["kind"]>(
  doc: MapDocument,
  kind: K,
): [number, Extract<MapObject, { kind: K }>][] {
  return [...doc.objects].filter(([, o]) => o.kind === kind).sort(([a], [b]) => a - b) as [
    number,
    Extract<MapObject, { kind: K }>,
  ][];
}

/**
 * The painted hexes as a dense grid over their box (one validation reads it many times): index
 * `(y - y0) w + (x - x0)`, each cell's value or -1 unpainted. Neighbours by `SIDE_STEPS`, the
 * drawing's (odd-r: a row's parity is its `y`'s).
 */
class Plane {
  readonly x0: number;
  readonly y0: number;
  readonly w: number;
  readonly h: number;
  readonly cells: Int32Array;

  constructor(doc: MapDocument) {
    const box = paintedBox(doc) ?? { x0: 0, y0: 0, x1: -1, y1: -1 };
    this.x0 = box.x0;
    this.y0 = box.y0;
    this.w = box.x1 - box.x0 + 1;
    this.h = box.y1 - box.y0 + 1;
    this.cells = new Int32Array(Math.max(0, this.w * this.h)).fill(-1);
    for (const [key, cell] of doc.hexes) {
      const { x, y } = tileOfKey(key);
      this.cells[(y - this.y0) * this.w + (x - this.x0)] = cell;
    }
  }

  /** A hex's index, or -1 outside the box. */
  index(tile: Tile): number {
    const x = tile.x - this.x0;
    const y = tile.y - this.y0;
    return x < 0 || y < 0 || x >= this.w || y >= this.h ? -1 : y * this.w + x;
  }

  tile(i: number): Tile {
    return { x: (i % this.w) + this.x0, y: Math.floor(i / this.w) + this.y0 };
  }

  /** The index across side `side` of index `i`, or -1 outside the box. */
  side(i: number, side: number): number {
    const x = i % this.w;
    const y = Math.floor(i / this.w);
    const step = SIDE_STEPS[(y + this.y0) & 1]![side]!;
    const nx = x + step.x;
    const ny = y + step.y;
    return nx < 0 || ny < 0 || nx >= this.w || ny >= this.h ? -1 : ny * this.w + nx;
  }

  /** The indices connected to `from` over cells `accept` takes (1 in the result); none if not. */
  reach(from: Tile, accept: (cell: number, i: number) => boolean): Uint8Array {
    const seen = new Uint8Array(this.cells.length);
    const first = this.index(from);
    if (first < 0 || !accept(this.cells[first]!, first)) return seen;
    seen[first] = 1;
    const pending = [first];
    while (pending.length > 0) {
      const i = pending.pop()!;
      for (let side = 0; side < 6; side++) {
        const next = this.side(i, side);
        if (next < 0 || seen[next] || !accept(this.cells[next]!, next)) continue;
        seen[next] = 1;
        pending.push(next);
      }
    }
    return seen;
  }
}

/**
 * Whether the painted box is small enough for a `Plane` (`FIT_SPAN_MAX` a side, the fit's own
 * bound): two far hexes of a legal file would otherwise ask for gigabytes (review of #366).
 */
export function planeFits(doc: MapDocument): boolean {
  const box = paintedBox(doc);
  return !box || (box.x1 - box.x0 < FIT_SPAN_MAX && box.y1 - box.y0 < FIT_SPAN_MAX);
}

/** The plane's indices of the bridges' decks (1), as the converter writes them walkable. */
function deckIndices(plane: Plane, doc: MapDocument): Uint8Array {
  const out = new Uint8Array(plane.cells.length);
  for (const key of deckKeys(doc)) {
    const i = plane.index(tileOfKey(key));
    if (i >= 0) out[i] = 1;
  }
  return out;
}

/** Cell predicates over the plane's values (-1 unpainted). */
const isIn = (cell: number) => cell >= 0 && !isOutside(cell);
const isWalkable = (cell: number) => isIn(cell) && terrainOf(cell) === FLOOR;

/** The fitted-map index checks of a hex: R-2 and R-3's bound. */
function indicesOk(tile: Tile, fit: Fitted): boolean {
  const a = chunkAt(tile, fit);
  return a.cx >= 0 && a.cy >= 0 && a.cx < CHUNK && a.cy < CHUNK && a.chunk < INDEX_BOUND;
}

/**
 * The checks of the fitted records that hold by construction (R-5, R-7, R-11, R-20): the editor
 * derives the ids and masks, so they fail only on a forged `Fitted` (the tests' failing cases).
 */
export function checkFitted(doc: MapDocument, fit: Fitted, out = new Findings()): Finding[] {
  for (const chunk of fit.chunkSet) {
    if (chunk < 0 || chunk >= INDEX_BOUND) {
      out.error("R-5", `An OUTLINE id's chunk ${chunk} is not below 225 (nor the set's 255).`);
    }
    const cx = chunk % CHUNK;
    const cy = Math.floor(chunk / CHUNK);
    if (cx >= fit.width || cy >= fit.height) {
      out.error(
        "R-11",
        `Chunk ${chunk} (${cx}, ${cy}) lies outside the ${fit.width} × ${fit.height} rectangle.`,
      );
    }
  }
  for (const [chunk, mask] of fit.masks) {
    if (mask.some((t) => t < 0 || t >= INDEX_BOUND)) {
      out.error("R-7", `Chunk ${chunk}'s tile mask has a bit above 224.`);
    }
  }
  // R-20: each border chunk's mask is the map's hexes of that chunk; a whole chunk has none.
  const tiles = new Map<number, number[]>();
  const zone = isZone(doc);
  for (const [key, cell] of doc.hexes) {
    if (zone && isOutside(cell)) continue;
    const a = chunkAt(tileOfKey(key), fit);
    let list = tiles.get(a.chunk);
    if (!list) tiles.set(a.chunk, (list = []));
    list.push(a.tile);
  }
  for (const [chunk, list] of tiles) {
    const mask = fit.masks.get(chunk);
    const whole = list.length === INDEX_BOUND;
    const agrees = whole
      ? mask === undefined
      : mask !== undefined &&
        mask.length === list.length &&
        [...list].sort((a, b) => a - b).every((t, i) => mask[i] === t);
    if (!agrees || !fit.chunkSet.includes(chunk)) {
      out.error("R-20", `Chunk ${chunk}'s tile mask disagrees with the map's hexes.`);
    }
  }
  return out.list;
}

/** Every finding of the map, errors first; the converter's too when a manifest is given. */
export function validate(doc: MapDocument, manifest: Manifest | null = null): Finding[] {
  const out = new Findings();
  const fit = fitted(doc);
  const zone = isZone(doc);
  const max = SIZE_MAX[doc.meta.kind];
  if (fit === "unfitted") {
    out.error("E-1", "The chunks are not fitted yet: Fit chunks (Shift+0).");
  } else if (fit === "empty") {
    out.error("E-1", zone ? "Nothing is painted inside the outline." : "Nothing is painted.");
  } else if (fit === "wide") {
    out.error("E-1", "The painted hexes span more than 1000 hexes: they cannot be fitted.");
  } else {
    const sized = `The fitted map is ${fit.width} × ${fit.height} chunks`;
    if (zone && (fit.width > max || fit.height > max)) {
      out.error("R-1", `${sized}: a zone is 1 to ${max} chunks on each side.`);
    } else if (!zone && (fit.width > max || fit.height > max)) {
      out.error("E-1", `${sized}: a ${doc.meta.kind} is at most ${max} × ${max}.`);
    }
    if (zone) checkFitted(doc, fit, out);
  }
  const frame = typeof fit === "string" ? null : fit;
  // Past the fit's span, the checks of reach (E-2, E-3, E-6, E-7, E-15's doors, E-17) are not run.
  const span = planeFits(doc);
  if (!span) {
    out.error(
      "E-1",
      `The painted hexes span more than ${FIT_SPAN_MAX} hexes: the checks of reach are not run.`,
    );
  }
  if (zone) zoneChecks(doc, frame, span, manifest, out);
  else townChecks(doc, span, out);
  // A town's footprints are checked with its places (E-16); a zone's are the pack's buildings.
  if (zone) footprintChecks(doc, out, true);
  packChecks(doc, out);
  bridgeChecks(doc, out);
  groundChecks(doc, out);
  if (zone && manifest && frame && frame.problems.length === 0) converterChecks(doc, manifest, out);
  const rank: Record<Severity, number> = { error: 0, warning: 1, hint: 2 };
  return out.list.sort((a, b) => rank[a.severity] - rank[b.severity]);
}

/**
 * Whether a gate is a dungeon's entrance, free of E-5 (D-215 Q9, ENG-09): its destination location
 * is a dungeon by the content manifest's `location_kinds`, as the converter reads it. No record
 * says it: GATE's `floor` kind is a floor-to-floor gate, and the sample's entrance is a `link`. With
 * no manifest, or a destination the manifest gives no kind, no gate is one.
 */
export function dungeonEntrance(to: number, manifest: Manifest | null): boolean {
  if (manifest === null) return false;
  const kinds = manifest.location_kinds ?? {};
  const name = nameOf(manifest, "locations", to);
  return Object.hasOwn(kinds, name) && kinds[name] === "dungeon";
}

/** `checks.json`'s ids by refusal code: the first case of a code names it. */
const CHECK_IDS: ReadonlyMap<string, string> = (() => {
  const table = JSON.parse(checksText) as Record<string, unknown>;
  const ids = new Map<string, string>();
  for (const group of ["registry", "pipeline", "export"]) {
    for (const c of table[group] as { id: string; code: string }[]) {
      if (!ids.has(c.code)) ids.set(c.code, c.id);
    }
  }
  return ids;
})();

/**
 * The converter's verdict on the map's export (CLI-09c): its refusal, under its check's id. What the
 * editor cannot export at all (a record the pack cannot write) is E-20's or E-23's, said there.
 */
function converterChecks(doc: MapDocument, manifest: Manifest, out: Findings): void {
  const file = toExport(doc, manifest);
  if ("problem" in file) return;
  const verdict = convert(file.file, manifest);
  if (!(verdict instanceof Refused)) return;
  const check = CHECK_IDS.get(verdict.code) ?? "E-40";
  const detail = verdict.detail ? ` (${verdict.detail})` : "";
  out.add(
    check,
    check.startsWith("R") ? "R" : "E",
    "error",
    `The converter refuses the export: ${verdict.code}${detail}.`,
  );
}

/** E-12: ground agrees with terrain (`world.ts:14-16`): water only on walls, earth only on floor. */
function groundChecks(doc: MapDocument, out: Findings): void {
  const water = GROUND_KINDS.indexOf("water");
  const earth = GROUND_KINDS.indexOf("earth");
  const wet: Tile[] = [];
  const dry: Tile[] = [];
  for (const [key, cell] of doc.hexes) {
    if (isZone(doc) && isOutside(cell)) continue;
    const g = groundOfCell(cell);
    if (g === water && terrainOf(cell) === FLOOR) wet.push(tileOfKey(key));
    if (g === earth && terrainOf(cell) === WALL) dry.push(tileOfKey(key));
  }
  if (wet.length > 0) {
    out.add("E-12", "E", "warning", `${wet.length} floor hexes have water ground.`, wet);
  }
  if (dry.length > 0) {
    out.add("E-12", "E", "warning", `${dry.length} wall hexes have earth ground.`, dry);
  }
}

function zoneChecks(
  doc: MapDocument,
  fit: Fitted | null,
  span: boolean,
  manifest: Manifest | null,
  out: Findings,
): void {
  const plane = span ? new Plane(doc) : null;
  const cellAtKey = (key: number) => doc.hexes.get(key) ?? -1;
  const inside = (key: number) => isIn(cellAtKey(key));
  const walkable = (key: number) => isWalkable(cellAtKey(key));
  const floor = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && terrainOf(cell) === FLOOR;
  };
  const entries = objectsOf(doc, "entry");
  const gates = objectsOf(doc, "gate");
  const candidates = objectsOf(doc, "candidate");
  const spawns = objectsOf(doc, "spawn");
  const quotas = doc.meta.quotas;
  let insideCount = 0;
  let walkableCount = 0;
  for (const cell of doc.hexes.values()) {
    if (!isIn(cell)) continue;
    insideCount += 1;
    if (terrainOf(cell) === FLOOR) walkableCount += 1;
  }
  let firstInside = -1;
  if (plane) {
    for (let i = 0; i < plane.cells.length && firstInside < 0; i++) {
      if (isIn(plane.cells[i]!)) firstInside = i;
    }
  }

  // E-2: the outline, not empty, one connected region.
  if (insideCount === 0) {
    out.error("E-2", "The outline is empty: no painted hex is inside.");
  } else if (plane) {
    const first = plane.reach(plane.tile(firstInside), isIn);
    const rest: Tile[] = [];
    for (let i = 0; i < plane.cells.length; i++) {
      if (isIn(plane.cells[i]!) && !first[i]) rest.push(plane.tile(i));
    }
    if (rest.length > 0) {
      out.error(
        "E-2",
        `The outline is not one region: ${rest.length} inside hexes are apart from the rest.`,
        rest,
      );
    }
  }

  // E-3: closed; an inside hex touches an unpainted one only as a wall or a gate anchor.
  const anchors = new Set(gates.map(([, g]) => plane?.index(g.at)));
  const open: Tile[] = [];
  for (let i = 0; plane && i < plane.cells.length; i++) {
    const cell = plane.cells[i]!;
    if (!isIn(cell) || terrainOf(cell) === WALL || anchors.has(i)) continue;
    for (let side = 0; side < 6; side++) {
      const next = plane.side(i, side);
      if (next < 0 || plane.cells[next]! < 0) {
        open.push(plane.tile(i));
        break;
      }
    }
  }
  if (open.length > 0) {
    out.error(
      "E-3",
      `The outline is open: ${open.length} inside floor hexes touch the unpainted void. Paint the outside around them, or make them walls.`,
      open,
    );
  }

  // E-4: exactly one entry, a floor hex inside the outline.
  if (entries.length !== 1) {
    out.error(
      "E-4",
      entries.length === 0 ? "The zone has no entry." : `The zone has ${entries.length} entries.`,
      entries.map(([, e]) => at(e)),
      entries.map(([id]) => id),
    );
  }
  for (const [id, entry] of entries) {
    if (!walkable(keyOf(entry.at))) {
      out.error(
        "E-4",
        `The entry ${where(entry.at)} is not a floor hex inside the outline.`,
        [entry.at],
        [id],
      );
    }
  }

  // E-5 and R-18: gate anchors on the outline's border, on walkable hexes.
  gates.forEach(([id, gate], i) => {
    const name = `Gate G${i + 1}`;
    if (!floor(keyOf(gate.at))) {
      out.error("R-18", `${name}'s anchor ${where(gate.at)} is not walkable.`, [gate.at], [id]);
    }
    let border = false;
    for (let side = 0; side < 6; side++) {
      if (!inside(keyOf(sideOf(gate.at, side)))) border = true;
    }
    // A gate to another location anchors on the outline; a dungeon's entrance (its destination a
    // dungeon) is free inside the chunk set (track game, D-215 Q9; ENG-09's converter).
    if ((!inside(keyOf(gate.at)) || !border) && !dungeonEntrance(gate.to, manifest)) {
      out.error(
        "E-5",
        `${name}'s anchor ${where(gate.at)} is not on the outline's border (export: gate not on the outline).`,
        [gate.at],
        [id],
      );
    }
    if (gate.entryChunk >= INDEX_BOUND || gate.entryTile >= INDEX_BOUND) {
      out.error(
        "R-3",
        `${name}'s entry in its destination (chunk ${gate.entryChunk}, tile ${gate.entryTile}) is not below 225.`,
        [gate.at],
        [id],
      );
    }
  });

  // R-14 and E-10: spawn points, features and candidates on walkable hexes inside the outline.
  // Every kind whose row says it stands on a walkable hex (CLI-09e's kinds join by their row).
  const onWalkable = [...doc.objects]
    .filter(([, o]) => kindOf(o).onWalkable)
    .sort(([a], [b]) => a - b);
  for (const [id, object] of onWalkable) {
    const name = OBJECT_NAMES[object.kind];
    const key = keyOf(object.at);
    if (!floor(key)) {
      out.error("R-14", `${name} ${where(object.at)} is not on a walkable hex.`, [object.at], [id]);
    }
    if (!inside(key)) {
      out.error("E-10", `${name} ${where(object.at)} is outside the outline.`, [object.at], [id]);
    }
  }

  // E-19: a spawn point's template is typed (R-17's existence is the pipeline's, ○).
  for (const [id, spawn] of spawns) {
    if (spawn.template === 0) {
      out.error(
        "E-19",
        `Spawn point ${where(spawn.at)} has no pack template (0).`,
        [spawn.at],
        [id],
      );
    }
  }

  // R-10, R-13, R-12: the quota list and its candidates.
  if (quotas.length > QUOTAS_MAX) {
    out.error("R-10", `The zone has ${quotas.length} quotas: at most ${QUOTAS_MAX}.`);
  }
  quotas.forEach((quota, q) => {
    const mine = candidates.filter(([, c]) => c.quota === q);
    const name = `Quota Q${q + 1} (${QUOTA_NAMES[quota.kind]})`;
    if (quota.count > mine.length) {
      out.error(
        "R-13",
        `${name} counts ${quota.count}, with ${mine.length} candidate places.`,
        mine.map(([, c]) => c.at),
        mine.map(([id]) => id),
      );
    }
    // Settled by ENG-08's converter: a zone's members are its chunks.
    if (fit && quota.count > fit.chunkSet.length) {
      out.error(
        "R-12",
        `${name} counts ${quota.count}, more than the zone's ${fit.chunkSet.length} chunks (its members).`,
      );
    }
  });
  for (const [id, c] of candidates) {
    if (!quotas[c.quota]) {
      out.error(
        "R-13",
        `Quota place ${where(c.at)} is a candidate for Q${c.quota + 1}, which the list does not hold.`,
        [c.at],
        [id],
      );
    }
  }

  // E-6 and E-7: reachable from the entry over walkable hexes inside the outline, bridges' decks
  // included.
  const entry = entries.length === 1 ? entries[0]![1] : null;
  if (plane && entry && walkable(keyOf(entry.at))) {
    const decks = deckIndices(plane, doc);
    const passable = (cell: number, i: number) =>
      isWalkable(cell) || (decks[i] === 1 && isIn(cell));
    const reached = plane.reach(entry.at, passable);
    const unreached = [...gates, ...candidates].filter(([, o]) => {
      const i = plane.index(o.at);
      return i < 0 || !reached[i];
    });
    if (unreached.length > 0) {
      out.error(
        "E-6",
        `${unreached.length} gate anchors or quota places are not reachable from the entry.`,
        unreached.map(([, o]) => o.at),
        unreached.map(([id]) => id),
      );
    }
    const sealed: Tile[] = [];
    for (let i = 0; i < plane.cells.length; i++) {
      if (passable(plane.cells[i]!, i) && !reached[i]) sealed.push(plane.tile(i));
    }
    if (sealed.length > 0) {
      out.error(
        "E-7",
        `${sealed.length} walkable hexes inside the outline are not reachable from the entry.`,
        sealed,
      );
    }
  }

  // E-13: a hint on the walkable share.
  const range = doc.meta.biome ? WALKABLE_SHARE[doc.meta.biome] : undefined;
  if (range && insideCount > 0) {
    const share = Math.round((100 * walkableCount) / insideCount);
    if (share < range[0] || share > range[1]) {
      out.add(
        "E-13",
        "E",
        "hint",
        `Walkable share ${share} % (${doc.meta.biome} ${range[0]}–${range[1]} %).`,
      );
    }
  }

  // R-39 (D-247): an authored zone's level band spans at most 255 levels: 0 to 255 is refused.
  if (doc.meta.levelMin === 0 && doc.meta.levelMax === 255) {
    out.error("R-39", "The level band 0 to 255 spans 256 levels: at most 255 (zone: level band).");
  }

  if (!fit) return;

  // R-14 (ENG-09): spawn points, features and quota places stand in their chunk's interior (rows
  // and columns 1 to 13), so that a pack's goblins stand within 2 of its tile.
  for (const [id, object] of [...doc.objects].sort(([a], [b]) => a - b)) {
    if (!kindOf(object).perChunk || !indicesOk(object.at, fit)) continue;
    const { tile } = chunkAt(object.at, fit);
    const row = Math.floor(tile / CHUNK);
    const col = tile % CHUNK;
    if (row === 0 || row === CHUNK - 1 || col === 0 || col === CHUNK - 1) {
      out.error(
        "R-14",
        `${OBJECT_NAMES[object.kind]} ${where(object.at)} stands on its chunk's ring: a placement needs the interior, rows and columns 1 to 13 (zone chunk: tile not floor).`,
        [object.at],
        [id],
      );
    }
  }

  // R-2 and R-3: the entry's and the anchors' indices in the fitted map.
  for (const [id, entry] of entries) {
    if (!indicesOk(entry.at, fit)) {
      const a = chunkAt(entry.at, fit);
      out.error(
        "R-2",
        `The entry's chunk ${a.chunk} or tile ${a.tile} is outside the fitted map (not below 225).`,
        [entry.at],
        [id],
      );
    }
  }
  gates.forEach(([id, gate], i) => {
    if (!indicesOk(gate.at, fit)) {
      out.error(
        "R-3",
        `Gate G${i + 1}'s anchor is outside the fitted map (its chunk or tile not below 225).`,
        [gate.at],
        [id],
      );
    }
  });

  // R-15 per chunk, settled by ENG-08's converter: every candidate counts, a Heart's against the
  // 2 packs, the others' against the 3 objects.
  const perChunk = new Map<
    number,
    { spawns: number[]; features: number[]; hearts: number[]; places: number[] }
  >();
  const chunkOf = (o: MapObject) => chunkAt(o.at, fit).chunk;
  const bucket = (chunk: number) => {
    let b = perChunk.get(chunk);
    if (!b) perChunk.set(chunk, (b = { spawns: [], features: [], hearts: [], places: [] }));
    return b;
  };
  for (const [id, o] of [...doc.objects].sort(([a], [b]) => a - b)) {
    const counted = kindOf(o).perChunk;
    if (!counted) continue;
    const b = bucket(chunkOf(o));
    if (counted === "spawn") b.spawns.push(id);
    else if (counted === "object") b.features.push(id);
    else if (o.kind === "candidate" && quotas[o.quota]?.kind === "heart") b.hearts.push(id);
    else b.places.push(id);
  }
  const tilesOf = (ids: number[]) => ids.map((id) => doc.objects.get(id)!.at);
  for (const [chunk, b] of [...perChunk].sort(([a], [z]) => a - z)) {
    if (b.spawns.length + b.hearts.length > SPAWNS_PER_CHUNK) {
      const ids = [...b.spawns, ...b.hearts];
      const places = b.hearts.length > 0 ? ` and ${b.hearts.length} Heart quota places` : "";
      out.error(
        "R-15",
        `Chunk ${chunk} holds ${b.spawns.length} spawn points${places}: at most ${SPAWNS_PER_CHUNK}.`,
        tilesOf(ids),
        ids,
      );
    }
    if (b.features.length + b.places.length > OBJECTS_PER_CHUNK) {
      const ids = [...b.features, ...b.places];
      const places = b.places.length > 0 ? ` and ${b.places.length} quota places` : "";
      out.error(
        "R-15",
        `Chunk ${chunk} holds ${b.features.length} features${places}: at most ${OBJECTS_PER_CHUNK}.`,
        tilesOf(ids),
        ids,
      );
    }
  }
}

function townChecks(doc: MapDocument, span: boolean, out: Findings): void {
  if (doc.meta.kind === "zone") return;
  const places = objectsOf(doc, "place");
  const arrivals = objectsOf(doc, "arrival");
  const services = servicesOf(doc.meta.kind);

  // E-14: one place per service of the hub's list, and one gate.
  for (const target of [...services, "gate" as const]) {
    const mine = places.filter(([, p]) => p.target === target);
    if (mine.length !== 1) {
      out.error(
        "E-14",
        mine.length === 0
          ? `No place for the ${target}.`
          : `${mine.length} places for the ${target}: one only.`,
        mine.map(([, p]) => p.at),
        mine.map(([id]) => id),
      );
    }
  }
  for (const [id, p] of places) {
    if (p.target !== "gate" && !services.includes(p.target)) {
      out.add(
        "E-14",
        "E",
        "warning",
        `The ${p.target} is not a service of a${doc.meta.kind === "outpost" ? "n outpost" : " town"}.`,
        [p.at],
        [id],
      );
    }
  }

  footprintChecks(doc, out);

  // E-15: doors and the arrival on floor; every door reachable from the arrival.
  const covers = townCovers(doc);
  const walkable = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && terrainOf(cell) === FLOOR && !covers.has(key);
  };
  if (arrivals.length !== 1) {
    out.error(
      "E-15",
      arrivals.length === 0
        ? "The hub has no arrival."
        : `The hub has ${arrivals.length} arrivals.`,
      arrivals.map(([, a]) => a.at),
      arrivals.map(([id]) => id),
    );
  }
  for (const [id, o] of [...places, ...arrivals]) {
    if (!walkable(keyOf(o.at))) {
      const name = o.kind === "place" ? `The ${o.target}'s door` : "The arrival";
      out.error("E-15", `${name} ${where(o.at)} is not floor.`, [o.at], [id]);
    }
  }
  const arrival = arrivals[0]?.[1];
  if (span && arrivals.length === 1 && arrival && walkable(keyOf(arrival.at))) {
    const plane = new Plane(doc);
    const covered = new Uint8Array(plane.cells.length);
    for (const key of covers) {
      const i = plane.index(tileOfKey(key));
      if (i >= 0) covered[i] = 1;
    }
    const decks = deckIndices(plane, doc);
    const reached = plane.reach(
      arrival.at,
      (cell, i) => cell >= 0 && (terrainOf(cell) === FLOOR || decks[i] === 1) && !covered[i],
    );
    const shut = places.filter(([, p]) => {
      const i = plane.index(p.at);
      return walkable(keyOf(p.at)) && (i < 0 || !reached[i]);
    });
    if (shut.length > 0) {
      out.error(
        "E-15",
        `${shut.length} doors are not reachable from the arrival.`,
        shut.map(([, p]) => p.at),
        shut.map(([id]) => id),
      );
    }
  }
}

/** The light (§2.3): error, warning, or none, with the counts. */
export function tally(findings: readonly Finding[]): { errors: number; warnings: number } {
  return {
    errors: findings.filter((f) => f.severity === "error").length,
    warnings: findings.filter((f) => f.severity !== "error").length,
  };
}

/**
 * A building's footprint (a town's, a zone's), authored per building (D-215 Q9), with the converter's
 * codes where it has them (ENG-09):
 *
 * - E-16: on land and painted, apart from the others' (the editor's own).
 * - E-43 (`export: footprint outside the set`): a zone's lies in the zone, inside the outline.
 * - E-44 (`export: footprint not connected`): one connected piece.
 */
function footprintChecks(doc: MapDocument, out: Findings, zone = false): void {
  const water = GROUND_KINDS.indexOf("water");
  const owner = new Map<number, number>();
  const buildings = [...doc.objects]
    .filter(([, o]) => kindOf(o).footprint)
    .sort(([a], [b]) => a - b);
  for (const [id, b] of buildings) {
    const name = OBJECT_NAMES[b.kind];
    const what = "building" in b ? b.building : "type" in b ? b.type : b.kind;
    const feet = footprintOf(b);
    // A zone's unpainted hex is outside the zone: E-43's, said once.
    const off = feet.filter((t) => {
      const cell = doc.hexes.get(keyOf(t));
      return cell === undefined ? !zone : groundOfCell(cell) === water;
    });
    if (off.length > 0) {
      out.error(
        "E-16",
        `${name} ${what} ${where(b.at)} stands on ${off.length} hexes off the land.`,
        off,
        [id],
      );
    }
    const keys = new Set(feet.map(keyOf));
    const reached = new Set([keyOf(feet[0]!)]);
    const pending = [feet[0]!];
    while (pending.length > 0) {
      const t = pending.pop()!;
      for (let side = 0; side < 6; side++) {
        const k = keyOf(sideOf(t, side));
        if (keys.has(k) && !reached.has(k)) {
          reached.add(k);
          pending.push(tileOfKey(k));
        }
      }
    }
    if (reached.size < keys.size) {
      const apart = feet.filter((t) => !reached.has(keyOf(t)));
      out.error(
        "E-44",
        `${name} ${what} ${where(b.at)}: its footprint is not one piece (${apart.length} hexes apart; export: footprint not connected).`,
        apart,
        [id],
      );
    }
    if (zone) {
      const outside = feet.filter((t) => {
        const cell = doc.hexes.get(keyOf(t));
        return cell === undefined || isOutside(cell);
      });
      if (outside.length > 0) {
        out.error(
          "E-43",
          `${name} ${what} ${where(b.at)} has ${outside.length} hexes outside the zone (export: footprint outside the set).`,
          outside,
          [id],
        );
      }
    }
    for (const t of feet) {
      const other = owner.get(keyOf(t));
      if (other !== undefined) {
        out.error(
          "E-16",
          `${name} ${what} ${where(b.at)} overlaps another building at ${where(t)}.`,
          [t],
          [other, id],
        );
        break;
      }
    }
    for (const t of feet) owner.set(keyOf(t), id);
  }
}

/**
 * The pack's objects (CLI-09e part 2), on a zone or a town. "Walkable" is a painted floor hex inside
 * the outline that no object covers (a building's footprint but its door, a blocking prop's hex):
 * what ENG-08's converter makes of it (track game, 2026-10-05).
 *
 * - E-20: a building's door is a hex of its footprint's border; E-45 (the converter's code): walkable.
 * - E-21: a character stands on a walkable hex.
 * - E-22: a prop stands on a painted hex inside the outline. A blocking one makes its hex
 *   unwalkable: a door or a character on it is refused by E-20 or E-21.
 * - E-23: the record ENG-08's export writes can be written: a kind of the table, a variant, a
 *   facing, a depth in range.
 */
function packChecks(doc: MapDocument, out: Findings): void {
  const covers = townCovers(doc);
  const painted = (t: Tile) => {
    const cell = doc.hexes.get(keyOf(t));
    return cell !== undefined && !isOutside(cell);
  };
  const walkable = (t: Tile) => {
    const cell = doc.hexes.get(keyOf(t));
    return cell !== undefined && isWalkable(cell) && !covers.has(keyOf(t));
  };
  for (const [id, o] of [...doc.objects].sort(([a], [b]) => a - b)) {
    if (!isPack(o)) continue;
    const door = o.kind === "building" ? doorOf(o) : null;
    const offBorder = o.kind === "building" && (!door || doorSide(footprintOf(o), door) === null);
    const record = kindOf(o).record?.(o);
    // A door off the border is E-20's: the record refuses it too, said once.
    if (record && "problem" in record && !offBorder) {
      out.error(
        "E-23",
        `${OBJECT_NAMES[o.kind]} ${o.type} ${where(o.at)}: ${record.problem}.`,
        [o.at],
        [id],
      );
    }
    switch (o.kind) {
      case "building": {
        if (offBorder) {
          const shown = door ? where(door) : `"${o.door}"`;
          out.error(
            "E-20",
            `The ${o.type}'s door ${shown} is not on its footprint's border.`,
            door ? [door] : [o.at],
            [id],
          );
        } else if (door && !walkable(door)) {
          out.error(
            "E-45",
            `The ${o.type}'s door ${where(door)} is not walkable (export: door not walkable).`,
            [door],
            [id],
          );
        }
        break;
      }
      case "npc":
        if (!walkable(o.at)) {
          out.error(
            "E-21",
            `The ${o.type} ${where(o.at)} does not stand on a walkable hex.`,
            [o.at],
            [id],
          );
        }
        break;
      case "scenery":
        if (!painted(o.at)) {
          out.error(
            "E-22",
            `The ${o.type} ${where(o.at)} stands off the painted map.`,
            [o.at],
            [id],
          );
        }
        break;
      case "bridge":
        break;
    }
  }
}

/**
 * A bridge's checks (CLI-09f; D-227, ADR-0008), on a zone or a town, for each bridge whose record
 * can be written (E-23 names the others), with `checks.json`'s ids and codes (ENG-09):
 *
 * - R-37 (`bridge: tile taken`), widened to the deck: no object stands on a bridge's ends or deck
 *   (an entry, a gate, a spawn point, a quota place, a feature, a character, a prop, a building's
 *   footprint, another bridge).
 * - E-46 (`export: deck outside the zone`): every deck hex painted, inside the outline.
 * - E-47 (`export: deck blocked`): no deck hex blocked (a building's footprint but its door, a
 *   blocking prop).
 * - E-25 (the editor's own): every deck hex over water (D-227: walkable ground drawn over water).
 * - R-34 (`bridge: end not floor`): each end walkable land: a painted floor hex inside the outline,
 *   not water, that no object blocks. R-34's deck half (`bridge: deck not floor`) holds by
 *   construction: the converter writes every deck hex walkable (ADR-0008 rule 1), and so do E-6's and
 *   E-7's reach here.
 */
function bridgeChecks(doc: MapDocument, out: Findings): void {
  const zone = isZone(doc);
  const water = GROUND_KINDS.indexOf("water");
  const covers = townCovers(doc);
  const inside = (t: Tile) => {
    const cell = doc.hexes.get(keyOf(t));
    return cell !== undefined && !(zone && isOutside(cell));
  };
  const objects = [...doc.objects].sort(([a], [b]) => a - b);
  /** The hexes an object stands on: a footprint, a bridge's hexes, else its hex. */
  const standsOn = (o: MapObject): Tile[] => {
    if (o.kind === "bridge") {
      const h = bridgeHexes(o);
      return h ? [h.ends[0], ...h.deck, h.ends[1]] : [o.at];
    }
    return footprintOf(o).length > 0 ? footprintOf(o) : [o.at];
  };
  for (const [id, o] of objects) {
    if (o.kind !== "bridge") continue;
    const hexes = bridgeHexes(o);
    if (!hexes) continue;
    const name = `The ${o.type} ${where(o.at)}`;
    const mine = new Set([hexes.ends[0], ...hexes.deck, hexes.ends[1]].map(keyOf));
    for (const [other, p] of objects) {
      if (other === id) continue;
      const taken = standsOn(p).filter((t) => mine.has(keyOf(t)));
      if (taken.length > 0) {
        const what = isPack(p) ? `the ${p.type}` : OBJECT_NAMES[p.kind].toLowerCase();
        out.error(
          "R-37",
          `${name}: ${what} ${where(p.at)} stands on its deck or ends (bridge: tile taken).`,
          taken,
          [id, other],
        );
      }
    }
    const outside = hexes.deck.filter((t) => !inside(t));
    if (outside.length > 0) {
      out.error(
        "E-46",
        `${name}: ${outside.length} deck hexes lie outside the zone (export: deck outside the zone).`,
        outside,
        [id],
      );
    }
    const blocked = hexes.deck.filter((t) => inside(t) && covers.has(keyOf(t)));
    if (blocked.length > 0) {
      out.error(
        "E-47",
        `${name}: ${blocked.length} deck hexes are blocked by a building or a prop (export: deck blocked).`,
        blocked,
        [id],
      );
    }
    const dry = hexes.deck.filter(
      (t) => inside(t) && groundOfCell(doc.hexes.get(keyOf(t))!) !== water,
    );
    if (dry.length > 0) {
      out.error("E-25", `${name}: ${dry.length} deck hexes are not over water.`, dry, [id]);
    }
    const ends = hexes.ends.filter((t) => {
      const cell = doc.hexes.get(keyOf(t));
      return !(
        inside(t) &&
        terrainOf(cell!) === FLOOR &&
        groundOfCell(cell!) !== water &&
        !covers.has(keyOf(t))
      );
    });
    if (ends.length > 0) {
      out.error(
        "R-34",
        `${name}: ${ends.length === 1 ? "an end is" : "both ends are"} not walkable land (bridge: end not floor).`,
        ends,
        [id],
      );
    }
  }
}
