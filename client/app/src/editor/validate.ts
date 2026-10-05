import type { Tile } from "../render/view";
import { type Fitted, chunkAt, fitted } from "./fit";
import {
  CHUNK,
  FLOOR,
  GROUND_KINDS,
  type MapDocument,
  SIZE_MAX,
  type TileBox,
  WALL,
  groundOfCell,
  isOutside,
  isZone,
  keyOf,
  paintedBox,
  regionOf,
  sideOf,
  terrainOf,
  tileOfKey,
} from "./model";
import { type MapObject, OBJECT_NAMES, QUOTA_NAMES, servicesOf } from "./objects";
import { footprintOf, townCovers } from "./walkWorld";

/**
 * The validation (CLI-09b, brief §5): ENG-08's content checks for map records (**R**), the editor's
 * own (**E**), and the checks whose exact rule waits for ENG-08's spike (**○**, warnings until
 * then). It runs on the **fitted** map (D-216): chunk and tile indices in the fitted map's
 * coordinates. A tool's checks, not game rules (mandate §6): they live in the editor's folder.
 *
 * Reachability is connectivity by hex neighbours over walkable hexes (`regionOf`, the drawing's
 * neighbours), the reach `placeholders.ts`'s finder walks until CLI-02 gives `client/sim` its own.
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

/** Grown by one hex: a region of painted hexes never reaches past it. */
function around(box: TileBox): TileBox {
  return { x0: box.x0 - 1, y0: box.y0 - 1, x1: box.x1 + 1, y1: box.y1 + 1 };
}

/**
 * The hexes connected to `from` over hexes `walkable` accepts, by key; empty when `from` is not
 * walkable or the region is past `FILL_MAX` (then the checks that read it say nothing).
 */
function reach(doc: MapDocument, from: Tile, walkable: (key: number) => boolean): Set<number> {
  const box = paintedBox(doc);
  if (!box) return new Set();
  const region = regionOf(from, walkable, around(box));
  return new Set(Array.isArray(region) ? region : []);
}

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

/** Every finding of the map, errors first. */
export function validate(doc: MapDocument): Finding[] {
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
  if (zone) zoneChecks(doc, frame, out);
  else townChecks(doc, out);
  groundChecks(doc, out);
  const rank: Record<Severity, number> = { error: 0, warning: 1, hint: 2 };
  return out.list.sort((a, b) => rank[a.severity] - rank[b.severity]);
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

function zoneChecks(doc: MapDocument, fit: Fitted | null, out: Findings): void {
  const inside = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && !isOutside(cell);
  };
  const walkable = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && !isOutside(cell) && terrainOf(cell) === FLOOR;
  };
  const floor = (key: number) => {
    const cell = doc.hexes.get(key);
    return cell !== undefined && terrainOf(cell) === FLOOR;
  };
  const entries = objectsOf(doc, "entry");
  const gates = objectsOf(doc, "gate");
  const candidates = objectsOf(doc, "candidate");
  const features = objectsOf(doc, "feature");
  const spawns = objectsOf(doc, "spawn");
  const quotas = doc.meta.quotas;
  const insideKeys = [...doc.hexes.keys()].filter(inside);
  const walkableCount = insideKeys.filter(walkable).length;

  // E-2: the outline, not empty, one connected region.
  if (insideKeys.length === 0) {
    out.error("E-2", "The outline is empty: no painted hex is inside.");
  } else {
    const first = reach(doc, tileOfKey(insideKeys[0]!), inside);
    if (first.size < insideKeys.length) {
      const rest = insideKeys.filter((k) => !first.has(k)).map(tileOfKey);
      out.error(
        "E-2",
        `The outline is not one region: ${rest.length} inside hexes are apart from the rest.`,
        rest,
      );
    }
  }

  // E-3: closed; an inside hex touches an unpainted one only as a wall or a gate anchor.
  const anchors = new Set(gates.map(([, g]) => keyOf(g.at)));
  const open: Tile[] = [];
  for (const key of insideKeys) {
    const tile = tileOfKey(key);
    const cell = doc.hexes.get(key)!;
    if (terrainOf(cell) === WALL || anchors.has(key)) continue;
    for (let side = 0; side < 6; side++) {
      if (!doc.hexes.has(keyOf(sideOf(tile, side)))) {
        open.push(tile);
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
    if (!inside(keyOf(gate.at)) || !border) {
      out.error(
        "E-5",
        `${name}'s anchor ${where(gate.at)} is not on the outline's border.`,
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
  for (const [id, object] of [...spawns, ...features, ...candidates]) {
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

  // R-10, R-13, R-12 ○: the quota list and its candidates.
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
    if (quota.count > walkableCount) {
      out.add(
        "R-12",
        "○",
        "warning",
        `${name} counts ${quota.count}, more than the zone's ${walkableCount} walkable hexes (what "members" counts waits for ENG-08's spike).`,
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

  // E-6 and E-7: reachable from the entry over walkable hexes inside the outline.
  const entry = entries.length === 1 ? entries[0]![1] : null;
  if (entry && walkable(keyOf(entry.at))) {
    const reached = reach(doc, entry.at, walkable);
    const unreached = [...gates, ...candidates].filter(([, o]) => !reached.has(keyOf(o.at)));
    if (unreached.length > 0) {
      out.error(
        "E-6",
        `${unreached.length} gate anchors or quota places are not reachable from the entry.`,
        unreached.map(([, o]) => o.at),
        unreached.map(([id]) => id),
      );
    }
    const sealed = insideKeys.filter((k) => walkable(k) && !reached.has(k)).map(tileOfKey);
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
  if (range && insideKeys.length > 0) {
    const share = Math.round((100 * walkableCount) / insideKeys.length);
    if (share < range[0] || share > range[1]) {
      out.add(
        "E-13",
        "E",
        "hint",
        `Walkable share ${share} % (${doc.meta.biome} ${range[0]}–${range[1]} %).`,
      );
    }
  }

  if (!fit) return;

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

  // R-15 per chunk, and its ○ part: whether a candidate counts against the three objects.
  const perChunk = new Map<
    number,
    { spawns: number[]; features: number[]; candidates: number[] }
  >();
  const chunkOf = (o: MapObject) => chunkAt(o.at, fit).chunk;
  const bucket = (chunk: number) => {
    let b = perChunk.get(chunk);
    if (!b) perChunk.set(chunk, (b = { spawns: [], features: [], candidates: [] }));
    return b;
  };
  for (const [id, o] of spawns) bucket(chunkOf(o)).spawns.push(id);
  for (const [id, o] of features) bucket(chunkOf(o)).features.push(id);
  for (const [id, o] of candidates) bucket(chunkOf(o)).candidates.push(id);
  const tilesOf = (ids: number[]) => ids.map((id) => doc.objects.get(id)!.at);
  for (const [chunk, b] of [...perChunk].sort(([a], [z]) => a - z)) {
    if (b.spawns.length > SPAWNS_PER_CHUNK) {
      out.error(
        "R-15",
        `Chunk ${chunk} holds ${b.spawns.length} spawn points: at most ${SPAWNS_PER_CHUNK}.`,
        tilesOf(b.spawns),
        b.spawns,
      );
    }
    if (b.features.length > OBJECTS_PER_CHUNK) {
      out.error(
        "R-15",
        `Chunk ${chunk} holds ${b.features.length} features: at most ${OBJECTS_PER_CHUNK}.`,
        tilesOf(b.features),
        b.features,
      );
    } else if (b.features.length + b.candidates.length > OBJECTS_PER_CHUNK) {
      const ids = [...b.features, ...b.candidates];
      out.add(
        "R-15",
        "○",
        "warning",
        `Chunk ${chunk} holds ${b.features.length} features and ${b.candidates.length} quota places: more than ${OBJECTS_PER_CHUNK} if a candidate counts as an object (ENG-08's spike).`,
        tilesOf(ids),
        ids,
      );
    }
  }

  // E-17 ○: two neighbouring chunks of the set with no walkable crossing on their seam.
  const crossings = new Set<string>();
  for (const key of insideKeys) {
    if (!walkable(key)) continue;
    const tile = tileOfKey(key);
    const a = chunkAt(tile, fit).chunk;
    for (let side = 0; side < 6; side++) {
      const next = sideOf(tile, side);
      if (!walkable(keyOf(next))) continue;
      const b = chunkAt(next, fit).chunk;
      if (a !== b) crossings.add(`${Math.min(a, b)} ${Math.max(a, b)}`);
    }
  }
  const set = new Set(fit.chunkSet);
  for (const chunk of fit.chunkSet) {
    const cx = chunk % CHUNK;
    for (const next of [cx + 1 < CHUNK ? chunk + 1 : -1, chunk + CHUNK]) {
      if (!set.has(next) || crossings.has(`${chunk} ${next}`)) continue;
      out.add(
        "E-17",
        "○",
        "warning",
        `Chunks ${chunk} and ${next} share a seam with no walkable crossing (what "consistent" means waits for ENG-08's spike).`,
      );
    }
  }
}

function townChecks(doc: MapDocument, out: Findings): void {
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

  // E-16: footprints on land, painted, and apart.
  const water = GROUND_KINDS.indexOf("water");
  const owner = new Map<number, number>();
  for (const [id, b] of [...places, ...objectsOf(doc, "decor")]) {
    const name = OBJECT_NAMES[b.kind];
    const feet = footprintOf(b);
    const off = feet.filter((t) => {
      const cell = doc.hexes.get(keyOf(t));
      return cell === undefined || groundOfCell(cell) === water;
    });
    if (off.length > 0) {
      out.error(
        "E-16",
        `${name} ${b.building} ${where(b.at)} stands on ${off.length} hexes off the land.`,
        off,
        [id],
      );
    }
    for (const t of feet) {
      const other = owner.get(keyOf(t));
      if (other !== undefined) {
        out.error(
          "E-16",
          `${name} ${b.building} ${where(b.at)} overlaps another building at ${where(t)}.`,
          [t],
          [other, id],
        );
        break;
      }
    }
    for (const t of feet) owner.set(keyOf(t), id);
  }

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
  if (arrivals.length === 1 && arrival && walkable(keyOf(arrival.at))) {
    const reached = reach(doc, arrival.at, walkable);
    const shut = places.filter(([, p]) => walkable(keyOf(p.at)) && !reached.has(keyOf(p.at)));
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
