import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  FIXTURE_GATES,
  FIXTURE_LOCATIONS,
  SEED_GATES,
  SEED_LOCATIONS,
  SEED_OUTLINES,
  SEED_REGION,
  globalTile,
} from "./region";

/**
 * The fixtures copy what they need from ENG-03's seed: this test reads the seed itself and fails
 * if a copied field differs, so the copy cannot drift (CLI-03c).
 */
const seed = JSON.parse(
  readFileSync(new URL("../../../../../contracts/seed/test-region.json", import.meta.url), "utf8"),
) as Record<string, (number | string)[]>;

/** The seed's records of a kind, each as an object keyed by its `<kind>_fields`. */
function records(kind: string): Record<string, number | string>[] {
  const fields = seed[`${kind}_fields`] as string[];
  const flat = seed[`${kind}s`] ?? [];
  expect(flat.length % fields.length, kind).toBe(0);
  const out: Record<string, number | string>[] = [];
  for (let i = 0; i < flat.length; i += fields.length) {
    out.push(Object.fromEntries(fields.map((f, k) => [f, flat[i + k]!])));
  }
  return out;
}

describe("the fixed data copied from the seed (contracts/seed/test-region.json)", () => {
  it("region 1: its town and first location", () => {
    const region = records("region").find((r) => r.id === SEED_REGION.id);
    expect(region).toBeDefined();
    for (const [field, value] of Object.entries(SEED_REGION)) {
      expect(region?.[field], field).toBe(value);
    }
  });

  it("every copied location field equals the seed's", () => {
    const seeded = records("location");
    expect(SEED_LOCATIONS.map((l) => l.id)).toEqual([1, 2]);
    for (const location of SEED_LOCATIONS) {
      const row = seeded.find((r) => r.id === location.id);
      expect(row, `location ${location.id}`).toBeDefined();
      for (const [field, value] of Object.entries(location)) {
        expect(row?.[field], `location ${location.id}.${field}`).toBe(value);
      }
    }
  });

  it("every copied gate field equals the seed's", () => {
    const seeded = records("gate");
    expect(SEED_GATES.map((g) => g.id)).toEqual([1, 2]);
    for (const gate of SEED_GATES) {
      const row = seeded.find((r) => r.id === gate.id);
      expect(row, `gate ${gate.id}`).toBeDefined();
      for (const [field, value] of Object.entries(gate)) {
        expect(row?.[field], `gate ${gate.id}.${field}`).toBe(value);
      }
    }
  });

  it("the zone's outline equals the seed's, row by row", () => {
    const seeded = records("outline");
    for (const outline of SEED_OUTLINES) {
      const row = seeded.find((r) => r.location === outline.location && r.chunk === outline.chunk);
      expect(row, `outline ${outline.location}/${outline.chunk}`).toBeDefined();
      outline.rows.forEach((value, r) => expect(row?.[`row_${r}`], `row_${r}`).toBe(value));
    }
    // Every outline of the zone is copied.
    expect(seeded.filter((r) => r.location === 2)).toHaveLength(SEED_OUTLINES.length);
  });

  it("the outpost and its gates are fixtures: ids no seed record uses", () => {
    const locations = new Set(records("location").map((r) => r.id));
    const gates = new Set(records("gate").map((r) => r.id));
    for (const l of FIXTURE_LOCATIONS) expect(locations.has(l.id), `location ${l.id}`).toBe(false);
    for (const g of FIXTURE_GATES) expect(gates.has(g.id), `gate ${g.id}`).toBe(false);
  });

  it("reads a chunk and a tile index as the README says (gate 1's entry: chunk 0, tile 105)", () => {
    // "entered at chunk 0, tile 105 (row 7, column 0)"; chunk 16 is (1, 1) (outline 528).
    expect(globalTile(0, 105)).toEqual({ x: 0, y: 7 });
    expect(globalTile(16, 110)).toEqual({ x: 20, y: 22 });
    expect(globalTile(2, 115)).toEqual({ x: 40, y: 7 });
  });
});
