import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  type BuiltZone,
  type ExportFile,
  type Manifest,
  Plane,
  buildZone,
  convert,
  golden,
  pipeline,
  recordsFile,
} from "./convert";
import * as R from "./records";
import { validate } from "./schema";

/**
 * The port held to ENG-08's converter (CLI-09c's acceptance): the samples convert to the committed
 * outputs, text for text and felt for felt, and every case of `checks.json` is refused with its
 * code by the same mutation as `tools/map-format/tests/test_convert.py`'s (ENG-09).
 */

const FORMAT = new URL("../../../../../tools/map-format/", import.meta.url);
const read = (path: string) => readFileSync(new URL(path, FORMAT), "utf8");
const load = <T = ExportFile>(name: string): T => JSON.parse(read(`samples/${name}`)) as T;
const MANIFEST = load<Manifest>("manifest.json");
const TABLE = JSON.parse(read("checks.json")) as Record<
  "registry" | "pipeline" | "export",
  { case: string; id: string; code: string }[]
>;

const zone = (): BuiltZone => buildZone(load("zone.json"), MANIFEST);
const firstWall = (rec: R.ZoneChunk) => [...Array(225).keys()].find((t) => R.has(rec.walls, t))!;
const firstFloor = (rec: R.ZoneChunk) => [...Array(225).keys()].find((t) => !R.has(rec.walls, t))!;
const chunk = (z: R.Zone, c: number) => z.chunks.get(c)!;
const bridge = (z: R.Zone) => z.bridges.get(15)![0]!;

const ring = (t: number) => [0, 14].includes(Math.floor(t / 15)) || [0, 14].includes(t % 15);

/** Each registry case: the mutation of `test_zone.cairo`'s `test_refuse_<case>`. */
const MUTATIONS: Record<string, (z: R.Zone) => void> = {
  set_outside: (z) => {
    z.chunk_set |= R.bit(3);
  },
  count_above_members: (z) => {
    z.quotas[0] = [R.COLLECTOR_Q, 1, 6];
  },
  count_above_candidates: (z) => {
    z.quotas[0] = [R.COLLECTOR_Q, 1, 3];
  },
  spawn_on_wall: (z) => {
    chunk(z, 1).spawns[0]!.tile = firstWall(chunk(z, 1));
  },
  spawn_on_ring: (z) => {
    const rec = chunk(z, 1);
    rec.spawns[0]!.tile = [...Array(225).keys()].find((t) => !R.has(rec.walls, t) && ring(t))!;
  },
  object_kind: (z) => {
    expect(chunk(z, 0).objects[0]!.kind).toBe(R.OBJECTS.landmark);
    chunk(z, 0).objects[0]!.kind = R.OBJECTS.vein;
  },
  empty_with_value: (z) => {
    chunk(z, 0).tiles[1] = 5;
  },
  tile_taken: (z) => {
    const rec = chunk(z, 2);
    expect(rec.objects[0]!.kind).toBe(R.OBJECTS.chest);
    rec.objects[0]!.tile = rec.spawns[0]!.tile;
  },
  over_caps: (z) => {
    const rec = chunk(z, 2);
    const taken = new Set([...rec.spawns.map((s) => s.tile), ...rec.objects.map((o) => o.tile)]);
    z.candidates.forEach((set, i) => {
      if (R.has(set, 2)) taken.add(rec.tiles[i]!);
    });
    const free = [...Array(225).keys()].filter(
      (t) => !R.has(rec.walls, t) && !taken.has(t) && !ring(t),
    );
    rec.objects.push(
      { tile: free[0]!, kind: 1, state: 0, param: 0 },
      { tile: free[1]!, kind: 1, state: 0, param: 0 },
    );
  },
  gate_anchor_not_floor: (z) => {
    z.gates.get(3)!.anchor_tile = firstWall(chunk(z, 16));
  },
  mask_disagrees: (z) => {
    const rec = chunk(z, 2);
    expect(R.has(rec.walls, 14)).toBe(true);
    rec.walls &= ~R.bit(14);
  },
  chunk_not_in_set: (z) => {
    z.chunk_set &= ~1n;
  },
  gate_not_indexed: (z) => {
    chunk(z, 16).gates = [0, 0];
  },
  entry_not_floor: (z) => {
    z.location.entry_tile = firstWall(chunk(z, 0));
  },
  level_band: (z) => {
    z.location.level_min = 0;
    z.location.level_max = 255;
  },
  heart_template: (z) => {
    z.hearts.set(2, [0, 2]);
  },
  floor_rectangle: (z) => {
    z.location.kind = R.LOCATION_KINDS.dungeon;
    z.location.target = 6;
  },
  quota_kind: (z) => {
    const [, param, n] = z.quotas[1]!;
    z.quotas[1] = [R.EXIT, param, n];
  },
  quota_draws: (z) => {
    const every = R.rectangle(15, 15);
    z.location.width = z.location.height = 15;
    z.chunk_set = every;
    z.quotas = [
      [R.COLLECTOR_Q, 1, 112],
      [R.VEIN_Q, 0, 112],
      [R.LANDMARK_Q, 1, 112],
      [R.HEART, 1, 112],
      [R.HEART, 1, 112],
      [R.LANDMARK_Q, 2, 112],
    ];
    z.candidates = Array<bigint>(6).fill(every);
    z.hearts = new Map([
      [3, [2, 5]],
      [4, [2, 5]],
    ]);
  },
  candidates_outside: (z) => {
    z.candidates[0] = z.candidates[0]! | R.bit(3);
  },
  bridge_deck: (z) => {
    bridge(z).deck = 0n;
  },
  bridge_end: (z) => {
    const [a] = bridge(z).ends;
    bridge(z).ends = [a, a];
  },
  bridge_floor: (z) => {
    bridge(z).ends = [firstWall(chunk(z, 15)), bridge(z).ends[1]];
  },
  bridge_apart: (z) => {
    bridge(z).ends = [firstFloor(chunk(z, 15)), bridge(z).ends[1]];
  },
  bridge_deck_floor: (z) => {
    chunk(z, 15).walls |= bridge(z).deck;
  },
  bridge_tile_taken: (z) => {
    const [a] = bridge(z).ends;
    chunk(z, 15).objects.push({ tile: a, kind: R.OBJECTS.chest, state: 0, param: 0 });
  },
  bridge_index: (z) => {
    chunk(z, 15).bridges = 0;
  },
  candidates_rewrite_count: (z) => {
    z.quotas[0] = [R.COLLECTOR_Q, 1, 2];
    z.candidates[0] = R.bit(16);
  },
  candidates_rewrite_tile: (z) => {
    expect(R.has(z.candidates[0]!, 1)).toBe(true);
    z.candidates[0] = z.candidates[0]! & ~R.bit(1);
  },
  pack_rewrite_heart: (z) => {
    z.hearts.set(2, [0, 5]);
  },
};

/** The refusal's code of a conversion, or "accepted". */
function verdict(raw: unknown): string {
  const out = convert(raw, MANIFEST);
  return out instanceof R.Refused ? out.code : "accepted";
}

/** Each export and pipeline case: the edit of `test_convert.py`'s test of the same name. */
const EDITS: Record<string, () => unknown> = {
  unreachable: () => {
    const e = load("zone.json");
    const plane = new Plane(e);
    const walls = new Set(R.neighbours(3, 3).map(([x, y]) => `${x},${y}`));
    for (const span of e.rows) {
      span.terrain = [...span.terrain]
        .map((t, i) => (walls.has(plane.glob(span.x + i, span.y).join(",")) ? "#" : t))
        .join("");
    }
    return e;
  },
  deck_disconnected: () => {
    const e = load("zone.json");
    const [x, y] = e.bridges![0]!.deck[0]!;
    e.bridges![0]!.deck.push([x, y + 4]);
    return e;
  },
  origin_odd: () => {
    const e = load("zone.json");
    e.origin.y += 1;
    return e;
  },
  door_off_border: () => {
    const e = load("zone.json");
    const b = e.buildings![0]!;
    const [x, y] = b.door;
    b.footprint = [-1, 0, 1].flatMap((dx) => [-1, 0, 1].map((dy) => [x + dx, y + dy] as const));
    return e;
  },
  unknown_kind: () => {
    const e = load("zone.json");
    e.props![0]!.kind = "statue";
    return e;
  },
  two_candidates: () => {
    const e = load("zone.json");
    const c = { ...e.candidates![0]! };
    c.x += 1;
    e.candidates!.push(c);
    return e;
  },
  three_gates: () => {
    const e = load("zone.json");
    const g = e.gates![0]!;
    // Both into the dungeon, so that E-5 (a gate elsewhere on the outline) does not apply
    e.gates!.push(
      { ...g, gate: "to_floor", to: "floor_1", x: g.x + 2 },
      { ...g, to: "floor_1", x: g.x + 3 },
    );
    return e;
  },
  bridge_across: () => {
    const e = load("zone.json");
    e.bridges![0]!.ends[0] = [e.origin.x + 20, e.origin.y + 20];
    return e;
  },
  schema: () => ({ ...load<ExportFile>("zone.json"), biome: "lava" }),
  format: () => ({ ...load<ExportFile>("zone.json"), format: "grimworld-map" }),
  version: () => ({ ...load<ExportFile>("zone.json"), version: 2 }),
  hex_outside_size: () => {
    const e = load("zone.json");
    e.size.width = 2;
    return e;
  },
  row_lengths: () => {
    const e = load("zone.json");
    e.rows[0]!.outline = e.rows[0]!.outline!.slice(0, -1);
    return e;
  },
  field_missing: () => {
    const e = load("zone.json");
    delete e.entry;
    return e;
  },
  unknown_name: () => {
    const e = load("zone.json");
    e.spawns![0]!.template = "dragons";
    return e;
  },
  candidate_of_no_quota: () => {
    const e = load("zone.json");
    e.candidates![0]!.quota = 5;
    return e;
  },
  object_outside_set: () => {
    const e = load("zone.json");
    e.features![1]!.x = e.origin.x + 33;
    e.features![1]!.y = e.origin.y + 20;
    return e;
  },
  deck_outside: () => {
    const e = load("zone.json");
    e.bridges![0]!.deck = [[e.origin.x + 33, e.origin.y + 20]];
    return e;
  },
  deck_blocked: () => {
    const e = load("zone.json");
    const tree = e.props![0]!;
    e.bridges![0]!.deck = [[tree.x, tree.y]];
    return e;
  },
  footprint_outside: () => {
    const e = load("zone.json");
    e.buildings![0]!.footprint.push([e.origin.x + 33, e.origin.y + 20]);
    return e;
  },
  footprint_disconnected: () => {
    const e = load("zone.json");
    const b = e.buildings![0]!;
    const [x, y] = b.door;
    b.footprint.push([x + 4, y + 4]);
    return e;
  },
  door_not_walkable: () => {
    const e = load("zone.json");
    const plane = new Plane(e);
    const door = plane.glob(...e.buildings![0]!.door).join(",");
    for (const span of e.rows) {
      span.terrain = [...span.terrain]
        .map((t, i) => (plane.glob(span.x + i, span.y).join(",") === door ? "#" : t))
        .join("");
    }
    return e;
  },
  gate_inside: () => {
    // The gate to the town moved to the zone's inside (all six neighbours in the zone)
    const e = load("zone.json");
    const [g, inside] = e.gates!;
    g!.x = inside!.x;
    g!.y = inside!.y;
    return e;
  },
  set_piece_size: () => {
    const e = load("set_piece.json");
    e.size.width = 2;
    return e;
  },
  set_piece_corner: () => {
    const e = load("set_piece.json");
    e.rows[0]!.terrain = `.${e.rows[0]!.terrain.slice(1)}`;
    return e;
  },
  set_piece_tile: () => {
    const e = load("set_piece.json");
    e.spawns![0]!.x = 5;
    e.spawns![0]!.y = 5;
    return e;
  },
  set_piece_caps: () => {
    const e = load("set_piece.json");
    e.features!.push(
      { feature: "chest", param: null, x: 3, y: 3 },
      { feature: "chest", param: null, x: 4, y: 3 },
    );
    return e;
  },
};

describe("the converter's port (ENG-08's samples)", () => {
  it("writes the committed records files, text for text", () => {
    for (const name of ["zone", "town", "set_piece"]) {
      const out = convert(load(`${name}.json`), MANIFEST);
      if (out instanceof R.Refused) throw out;
      expect(recordsFile(out.writes, `${name}.json`), name).toBe(
        read(`samples/${name}.records.json`),
      );
    }
  });

  it("gives the golden file, felt for felt", () => {
    const out = convert(load("zone.json"), MANIFEST);
    if (out instanceof R.Refused) throw out;
    expect(golden(out.writes)).toEqual(load("zone.golden.json"));
  });

  it("finds the samples valid against the schema", () => {
    for (const name of ["zone.json", "town.json", "set_piece.json"]) {
      expect(() => validate(load(name))).not.toThrow();
    }
  });

  it("keeps the schema, the kind table and the checks' table equal to track game's", () => {
    for (const name of ["schema.json", "kinds.json", "checks.json"]) {
      const mine = readFileSync(new URL(`./${name}`, import.meta.url), "utf8");
      expect(JSON.parse(mine), name).toEqual(JSON.parse(read(name)));
    }
  });

  it("writes a bridge's deck walkable: with the ford painted water, it is the only crossing", () => {
    const e = load("zone.json");
    const z = buildZone(e, MANIFEST);
    for (const [x, y] of e.bridges![0]!.deck) {
      const g = z.plane.glob(x, y).join(",");
      expect(z.walk.has(g), "the deck walkable").toBe(true);
      expect(z.plane.cells.get(g)!.walk, "painted as water").toBe(false);
    }
    expect(verdict(e)).toBe("accepted");
  });

  it("lets a dungeon's entrance stand inside the chunk set (E-5)", () => {
    const e = load("zone.json");
    const z = buildZone(e, MANIFEST);
    const g = e.gates![1]!;
    expect(MANIFEST.location_kinds![g.to]).toBe("dungeon");
    const inner = R.neighbours(...z.plane.glob(g.x, g.y)).every(([x, y]) => z.zone.has(`${x},${y}`));
    expect(inner, "inside").toBe(true);
  });
});

describe("every case of checks.json, refused with its code", () => {
  it("passes the sample through the Registry's checks and the pipeline", () => {
    const z = zone();
    expect(() => R.checkZone(z)).not.toThrow();
    expect(() => pipeline(z)).not.toThrow();
  });

  it("has a mutation for each registry case", () => {
    expect(Object.keys(MUTATIONS).sort()).toEqual(TABLE.registry.map((c) => c.case).sort());
  });

  for (const c of TABLE.registry) {
    it(`registry ${c.case} (${c.id}): ${c.code}`, () => {
      const z = zone();
      MUTATIONS[c.case]!(z);
      expect(() => R.checkZone(z)).toThrow(expect.objectContaining({ code: c.code }));
    });
  }

  it("pipeline seam (P-2): a wall bit of chunk 1 flipped on its seam with chunk 0", () => {
    const z = zone();
    expect(R.has(chunk(z, 1).walls, 105)).toBe(false);
    chunk(z, 1).walls |= R.bit(105);
    expect(() => pipeline(z)).toThrow(expect.objectContaining({ code: "pipeline: seam" }));
  });

  for (const c of [...TABLE.pipeline, ...TABLE.export]) {
    if (c.case === "seam" || c.case === "malformed") continue;
    it(`${c.case} (${c.id}): ${c.code}`, () => {
      expect(EDITS[c.case], c.case).toBeDefined();
      expect(verdict(EDITS[c.case]!())).toBe(c.code);
    });
  }

  it("malformed (E-40): an error no check names is a refusal, not a throw", () => {
    const broken = { ...load("zone.json"), entry: { x: 0, y: 0 } } as ExportFile;
    broken.rows = new Proxy(broken.rows, {
      get(target, key, receiver) {
        if (key === Symbol.iterator) throw new TypeError("forced");
        return Reflect.get(target, key, receiver);
      },
    });
    expect(verdict(broken)).toBe("export: malformed");
  });

  it("has an edit for every export and pipeline case", () => {
    for (const c of [...TABLE.pipeline, ...TABLE.export]) {
      if (c.case !== "seam" && c.case !== "malformed") {
        expect(Object.keys(EDITS), c.case).toContain(c.case);
      }
    }
  });
});
