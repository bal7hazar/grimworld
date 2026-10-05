import { describe, expect, it } from "vitest";
import type { Tile } from "../render/view";
import { loadMap, saveMap } from "./file";
import { FLOOR, cellAt, createMap, keyOf, objectsAt, sideOf, terrainOf } from "./model";
import { objectLabel } from "./objects";
import { EditorSession, NOTHING } from "./session";

/**
 * CLI-09b's tools on the session (§3): Place, Select, Move, Cut, Copy, Paste, Delete, Mirror and the
 * inspector's edits, each one step of the undo history; the objects in the file.
 */

const zone = () => createMap({ kind: "zone", name: "Objects", location: 2, biome: "meadow" });
const town = () => createMap({ kind: "town", name: "Town", location: 1, biome: "meadow" });

const click = (s: EditorSession, tile: Tile, extra: { shift?: boolean; erase?: boolean } = {}) => {
  s.strokeStart(tile, { erase: extra.erase ?? false, alt: false, shift: extra.shift ?? false });
  s.strokeEnd();
};

const drag = (s: EditorSession, from: Tile, to: Tile, shift = false) => {
  s.strokeStart(from, { erase: false, alt: false, shift });
  s.strokeMove([to]);
  s.strokeEnd();
};

/** A floor block painted from (0, 0) to (w - 1, h - 1). */
function block(s: EditorSession, w: number, h: number): void {
  s.choose("terrain", FLOOR);
  s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
  const tiles: Tile[] = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) tiles.push({ x, y });
  s.strokeMove(tiles);
  s.strokeEnd();
}

describe("Place (§3)", () => {
  it("places the palette's object, selected; one entry a map: placing it again moves it", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "entry" });
    expect(s.tool).toBe("place");
    click(s, { x: 2, y: 3 });
    click(s, { x: 5, y: 1 });
    const entries = [...s.doc.objects.values()].filter((o) => o.kind === "entry");
    expect(entries).toEqual([{ kind: "entry", at: { x: 5, y: 1 } }]);
    expect(s.selection.objects.size).toBe(1);
    s.choosePlace({ kind: "gate" });
    click(s, { x: 0, y: 0 });
    click(s, { x: 9, y: 0 });
    expect([...s.doc.objects.values()].filter((o) => o.kind === "gate")).toHaveLength(2);
    // The same kind on the same hex is selected, not placed twice.
    click(s, { x: 9, y: 0 });
    expect(s.doc.objects.size).toBe(3);
    expect(s.history.steps).toBe(4);
    s.undo();
    s.undo();
    expect(s.doc.objects.size).toBe(1);
    s.undo();
    expect(objectsAt(s.doc, { x: 2, y: 3 })).toHaveLength(1);
  });

  it("a zone's palette places nothing of a town's, and the other way", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "arrival" });
    click(s, { x: 1, y: 1 });
    expect(s.doc.objects.size).toBe(0);
    const t = new EditorSession(town());
    t.choosePlace({ kind: "place", target: "guild" });
    click(t, { x: 4, y: 4 });
    expect([...t.doc.objects.values()]).toEqual([
      {
        kind: "place",
        at: { x: 4, y: 4 },
        target: "guild",
        building: "castle",
        depth: 1,
        mirror: false,
      },
    ]);
  });

  it("an object placed after a fit leaves the fit as it is; a stroke makes it stale", () => {
    const s = new EditorSession(zone());
    block(s, 4, 4);
    s.fitChunks();
    s.choosePlace({ kind: "entry" });
    click(s, { x: 1, y: 1 });
    expect(s.paintedSinceOrigin).toBe(false);
    block(s, 5, 4);
    expect(s.paintedSinceOrigin).toBe(true);
  });

  it("a right click with Place or Select inspects the hex", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "spawn" });
    click(s, { x: 1, y: 1 }, { erase: true });
    expect(s.inspected).toEqual({ x: 1, y: 1 });
    expect(s.doc.objects.size).toBe(0);
  });
});

describe("Select and Move (§3)", () => {
  it("a click selects the hex's last object or the hex; Shift adds; a box takes hexes and objects", () => {
    const s = new EditorSession(zone());
    block(s, 6, 4);
    s.choosePlace({ kind: "feature", feature: "chest" });
    click(s, { x: 1, y: 1 });
    s.armTool("select");
    click(s, { x: 4, y: 2 });
    expect(s.selection.hexes).toEqual(new Set([keyOf({ x: 4, y: 2 })]));
    click(s, { x: 1, y: 1 }, { shift: true });
    expect(s.selection.objects.size).toBe(1);
    expect(s.selection.hexes.size).toBe(1);
    drag(s, { x: 0, y: 0 }, { x: 2, y: 1 });
    expect(s.selection.hexes.size).toBe(6);
    expect(s.selection.objects.size).toBe(1);
    s.escape();
    expect(s.selection).toEqual(NOTHING);
  });

  it("dragging a selected object moves it, one step; a group keeps the rows' parity", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "spawn" });
    click(s, { x: 1, y: 1 });
    s.armTool("select");
    drag(s, { x: 1, y: 1 }, { x: 4, y: 2 });
    expect([...s.doc.objects.values()][0]!.at).toEqual({ x: 4, y: 2 });
    s.undo();
    expect([...s.doc.objects.values()][0]!.at).toEqual({ x: 1, y: 1 });
    s.redo();
    // A group of two moved by an odd number of rows snaps to an even one.
    s.choosePlace({ kind: "spawn" });
    click(s, { x: 7, y: 2 });
    s.armTool("select");
    drag(s, { x: 0, y: 0 }, { x: 9, y: 3 });
    expect(s.selection.objects.size).toBe(2);
    drag(s, { x: 4, y: 2 }, { x: 4, y: 5 });
    const at = [...s.doc.objects.values()].map((o) => o.at);
    expect(at).toEqual([
      { x: 4, y: 6 },
      { x: 7, y: 6 },
    ]);
  });
});

describe("Cut, Copy, Paste, Delete, Mirror (§3)", () => {
  it("a paste keeps the shape: it lands on a row of the same parity, every neighbour kept", () => {
    const s = new EditorSession(zone());
    // An L of hexes from an odd row.
    s.choose("terrain", FLOOR);
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: false });
    s.strokeMove([
      { x: 4, y: 3 },
      { x: 4, y: 4 },
    ]);
    s.strokeEnd();
    s.choosePlace({ kind: "feature", feature: "lever" });
    click(s, { x: 4, y: 4 });
    s.armTool("select");
    drag(s, { x: 3, y: 3 }, { x: 4, y: 4 });
    expect(s.copy()).toBe(true);
    s.paste();
    expect(s.pasting).toBe(true);
    // Pointed at an odd row: the anchor snaps to the even row below.
    click(s, { x: 20, y: 11 });
    expect(s.pasting).toBe(false);
    // The anchor is (3, 2) (the even row at or below 3); it lands on (20, 10): (dx, dy) = (17, 8).
    const moved = (t: Tile) => ({ x: t.x + 17, y: t.y + 8 });
    for (const t of [
      { x: 3, y: 3 },
      { x: 4, y: 3 },
      { x: 4, y: 4 },
    ]) {
      expect(cellAt(s.doc, moved(t))).not.toBeNull();
      // The same neighbours: the side across which a hex of the shape lies is the same.
      for (let side = 0; side < 6; side++) {
        const before = cellAt(s.doc, sideOf(t, side)) !== null;
        const after = cellAt(s.doc, sideOf(moved(t), side)) !== null;
        expect(after, `${t.x},${t.y} side ${side}`).toBe(before);
      }
    }
    expect(objectsAt(s.doc, moved({ x: 4, y: 4 }))).toHaveLength(1);
    expect(s.history.steps).toBe(3);
  });

  it("cut removes and copies; Delete unpaints hexes and removes objects; undo brings them back", () => {
    const s = new EditorSession(zone());
    block(s, 3, 2);
    s.choosePlace({ kind: "entry" });
    click(s, { x: 1, y: 0 });
    s.armTool("select");
    drag(s, { x: 0, y: 0 }, { x: 2, y: 1 });
    s.cut();
    expect(s.doc.hexes.size).toBe(0);
    expect(s.doc.objects.size).toBe(0);
    s.paste();
    click(s, { x: 10, y: 4 });
    expect(s.doc.hexes.size).toBe(6);
    expect([...s.doc.objects.values()]).toEqual([{ kind: "entry", at: { x: 11, y: 4 } }]);
    s.deleteSelection();
    expect(s.doc.hexes.size).toBe(0);
    s.undo();
    expect(s.doc.hexes.size).toBe(6);
    expect(s.doc.objects.size).toBe(1);
  });

  it("Mirror flips the selected buildings, decor and props; anything else is told", () => {
    const s = new EditorSession(town());
    s.choosePlace({ kind: "prop", sprite: "sheep" });
    click(s, { x: 2, y: 2 });
    s.mirror();
    expect([...s.doc.objects.values()][0]).toMatchObject({ kind: "prop", mirror: true });
    s.undo();
    expect([...s.doc.objects.values()][0]).toMatchObject({ mirror: false });
    s.choosePlace({ kind: "figure" });
    click(s, { x: 5, y: 5 });
    s.mirror();
    expect(s.said).toContain("Mirror");
  });
});

describe("the inspector's edits (§2.4)", () => {
  it("an object's field and the map's properties are one step each", () => {
    const s = new EditorSession(zone());
    s.choosePlace({ kind: "spawn" });
    click(s, { x: 1, y: 1 });
    const [id, spawn] = [...s.doc.objects][0]!;
    s.editObject(id, { ...spawn, kind: "spawn", template: 7 } as typeof spawn);
    expect(s.doc.objects.get(id)).toMatchObject({ template: 7 });
    s.editMeta({ ...s.doc.meta, quotas: [{ kind: "exit", param: 0, count: 2 }] });
    expect(s.history.steps).toBe(3);
    s.undo();
    expect(s.doc.meta.quotas).toEqual([]);
    s.undo();
    expect(s.doc.objects.get(id)).toMatchObject({ template: 0 });
  });

  it("removing a quota removes its candidates and renumbers the later ones, in one step", () => {
    const s = new EditorSession(zone());
    s.editMeta({
      ...s.doc.meta,
      quotas: [
        { kind: "exit", param: 0, count: 1 },
        { kind: "vein", param: 0, count: 1 },
      ],
    });
    s.choosePlace({ kind: "candidate", quota: 0 });
    click(s, { x: 1, y: 1 });
    s.choosePlace({ kind: "candidate", quota: 1 });
    click(s, { x: 2, y: 1 });
    s.removeQuota(0);
    expect([...s.doc.objects.values()]).toEqual([
      { kind: "candidate", at: { x: 2, y: 1 }, quota: 0 },
    ]);
    expect(s.doc.meta.quotas).toEqual([{ kind: "vein", param: 0, count: 1 }]);
    s.undo();
    expect(s.doc.objects.size).toBe(2);
    expect(s.doc.meta.quotas).toHaveLength(2);
  });

  it("Set terrain on a group paints the selected hexes", () => {
    const s = new EditorSession(zone());
    block(s, 2, 2);
    s.armTool("select");
    drag(s, { x: 0, y: 0 }, { x: 1, y: 1 });
    s.paintSelection({ layer: "terrain", value: 1 });
    expect([...s.doc.hexes.values()].every((c) => terrainOf(c) === 1)).toBe(true);
  });
});

describe("objects in the file (format 2, §6)", () => {
  it("every kind round-trips, in its order; labels name each", () => {
    const s = new EditorSession(zone());
    s.editMeta({ ...s.doc.meta, quotas: [{ kind: "collector", param: 3, count: 1 }] });
    s.choosePlace({ kind: "entry" });
    click(s, { x: 0, y: 0 });
    for (const choice of [
      { kind: "gate" },
      { kind: "candidate", quota: 0 },
      { kind: "feature", feature: "trap" },
      { kind: "spawn" },
    ] as const) {
      s.choosePlace(choice);
      click(s, { x: s.doc.objects.size, y: 1 });
    }
    const text = saveMap(s.doc, "test");
    const back = loadMap(text);
    if ("problem" in back) throw new Error(back.problem);
    expect(back.doc).toEqual(s.doc);
    expect(saveMap(back.doc, "test")).toBe(text);
    const labels = [...s.doc.objects.values()].map((o) => objectLabel(o, 1, s.doc.meta.quotas));
    expect(labels).toEqual(["E", "G1", "QC", "FT", "P"]);
    const t = new EditorSession(town());
    for (const choice of [
      { kind: "place", target: "vault" },
      { kind: "decor", building: "hut" },
      { kind: "prop", sprite: "rock2" },
      { kind: "figure" },
      { kind: "arrival" },
    ] as const) {
      t.choosePlace(choice);
      click(t, { x: t.doc.objects.size * 3, y: 2 });
    }
    const town2 = loadMap(saveMap(t.doc, "test"));
    if ("problem" in town2) throw new Error(town2.problem);
    expect(town2.doc).toEqual(t.doc);
  });

  it("refuses an object of the other kind of map, or an unknown one, with the reason", () => {
    const base = JSON.parse(
      saveMap(createMap({ kind: "town", name: "T", location: 1, biome: "meadow" })),
    );
    const withObject = (o: unknown) => JSON.stringify({ ...base, objects: [o] });
    expect(loadMap(withObject({ kind: "entry", x: 0, y: 0 }))).toEqual({
      problem: "The file is refused: a town or an outpost holds no entry.",
    });
    expect(loadMap(withObject({ kind: "dragon", x: 0, y: 0 }))).toMatchObject({
      problem: expect.stringContaining('an object "dragon" at (0, 0) is not read'),
    });
    // A format 2 file of CLI-09a2, without objects or quotas, opens with none.
    const old = { ...base };
    delete old.objects;
    const read = loadMap(JSON.stringify(old));
    if ("problem" in read) throw new Error(read.problem);
    expect(read.doc.objects.size).toBe(0);
  });
});
