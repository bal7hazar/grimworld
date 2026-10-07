import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { loadMap, saveMap } from "../file";
import { createMap } from "../model";
import { validate } from "../validate";
import { type Manifest, convert, golden, recordsFile } from "./convert";
import { fromExport, readManifest, toExport } from "./document";
import { Refused } from "./records";

/**
 * CLI-09c's acceptance on ENG-08's sample zone: loaded in the editor it validates; exported, it is
 * the converter's output felt for felt; its export file round-trips.
 */

const SAMPLES = new URL("../../../../../spikes/SPK-16-authored-zone/samples/", import.meta.url);
const read = (name: string) => readFileSync(new URL(name, SAMPLES), "utf8");
const SAMPLE = JSON.parse(read("zone.json")) as Record<string, unknown>;
const MANIFEST = readManifest(read("manifest.json")) as Manifest;

function opened() {
  const out = fromExport(structuredClone(SAMPLE), MANIFEST);
  if ("problem" in out) throw new Error(out.problem);
  return out;
}

function exported(doc = opened().doc) {
  const out = toExport(doc, MANIFEST, "spike");
  if ("problem" in out) throw new Error(out.problem);
  return out.file;
}

describe("ENG-08's sample zone in the editor", () => {
  it("reads the sample's manifest", () => {
    expect(typeof MANIFEST).toBe("object");
  });

  it("opens with no note: the editor fits it where the file says", () => {
    expect(opened().notes).toEqual([]);
  });

  it("validates: no error, the converter's checks included", () => {
    const errors = validate(opened().doc, MANIFEST).filter((f) => f.severity === "error");
    expect(errors).toEqual([]);
  });

  it("exports to the converter's records file, text for text", () => {
    const out = convert(exported(), MANIFEST);
    if (out instanceof Refused) throw out;
    expect(recordsFile(out.writes, "zone.json")).toBe(read("zone.records.json"));
    expect(golden(out.writes)).toEqual(JSON.parse(read("zone.golden.json")));
  });

  it("round-trips: the export file is the sample, and opens to the same map", () => {
    expect(exported()).toEqual(SAMPLE);
    const again = fromExport(exported(), MANIFEST);
    if ("problem" in again) throw new Error(again.problem);
    expect(saveMap(again.doc, "x")).toBe(saveMap(opened().doc, "x"));
  });

  it("survives the editor's own file: saved, loaded, exported the same", () => {
    const loaded = loadMap(saveMap(opened().doc, "x"));
    if ("problem" in loaded) throw new Error(loaded.problem);
    expect(exported(loaded.doc)).toEqual(SAMPLE);
  });
});

describe("what the import refuses, the open map untouched", () => {
  const problem = (raw: unknown, manifest = MANIFEST) => {
    const out = fromExport(raw, manifest);
    return "problem" in out ? out.problem : "opened";
  };

  it("a newer version, another format, a schema break", () => {
    expect(problem({ ...SAMPLE, version: 2 })).toMatch(/version 2/);
    expect(problem({ ...SAMPLE, format: "grimworld-map" })).toMatch(/format/);
    expect(problem({ ...SAMPLE, biome: "lava" })).toMatch(/schema/);
  });

  it("a name the manifest lacks", () => {
    expect(problem(SAMPLE, { ...MANIFEST, packs: { raiders: 1 } })).toMatch(/packs "cubs"/);
  });

  it("a town, which is not exported for the chain", () => {
    expect(problem(JSON.parse(read("town.json")))).toMatch(/a town is not exported/);
  });
});

describe("what the export names", () => {
  it("an id the manifest lacks, as a name the converter refuses", () => {
    const { doc } = opened();
    doc.meta = { ...doc.meta, spawnTable: 9 };
    const file = toExport(doc, MANIFEST);
    if ("problem" in file) throw new Error(file.problem);
    expect(file.file.spawn_table).toBe("#9");
    const out = convert(file.file, MANIFEST);
    expect(out instanceof Refused && out.code).toBe("export: unknown name");
  });

  it("nothing of a town or an unfitted zone", () => {
    const town = createMap({ kind: "town", name: "T", location: 1, biome: "meadow" });
    expect(toExport(town, MANIFEST)).toHaveProperty("problem");
    const zone = createMap({ kind: "zone", name: "Z", location: 1, biome: "meadow" });
    expect(toExport(zone, MANIFEST)).toHaveProperty("problem");
  });
});
