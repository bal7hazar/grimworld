import { describe, expect, it, vi } from "vitest";
import { DraftWriter, Drafts, type DraftStorage, type Timers } from "./drafts";
import { FLOOR, GROUND_KINDS, WALL, cellAt, createMap, isOutside, terrainOf } from "./model";
import { EditorSession } from "./session";
import { listenSpaceRelease } from "./spaceHold";

const zone = () => createMap({ kind: "zone", name: "Tools", location: 2, biome: "forest" });

const floors = (s: EditorSession) =>
  [...s.doc.hexes.values()].filter((c) => terrainOf(c) === FLOOR).length;

describe("the tools on strokes (§3)", () => {
  it("paint with a brush anywhere, right drag erases to the void, each stroke one step", () => {
    const s = new EditorSession(zone());
    s.choose("terrain", FLOOR);
    s.setBrush(1);
    s.strokeStart({ x: -10, y: -10 }, { erase: false, alt: false });
    s.strokeMove([
      { x: -11, y: -10 },
      { x: -12, y: -10 },
    ]);
    s.strokeEnd();
    expect(floors(s)).toBe(13);
    s.setBrush(0);
    s.strokeStart({ x: -11, y: -10 }, { erase: true, alt: false });
    s.strokeEnd();
    expect(cellAt(s.doc, { x: -11, y: -10 })).toBeNull();
    expect(s.history.steps).toBe(2);
    s.undo();
    expect(terrainOf(cellAt(s.doc, { x: -11, y: -10 })!)).toBe(FLOOR);
    s.undo();
    expect(s.doc.hexes.size).toBe(0);
    expect(s.revision).toBeGreaterThan(0);
  });

  it("Alt+click picks and Pick returns to the tool before it", () => {
    const s = new EditorSession(zone());
    const earth = GROUND_KINDS.indexOf("earth");
    s.choose("ground", earth);
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: false });
    s.strokeEnd();
    s.choose("ground", 0);
    s.armTool("erase");
    s.armTool("pick");
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: false });
    expect(s.ground).toBe(earth);
    expect(s.tool).toBe("erase");
    s.choose("ground", 0);
    s.strokeStart({ x: 3, y: 3 }, { erase: false, alt: true });
    expect(s.ground).toBe(earth);
    expect(s.tool).toBe("paint");
    expect(s.history.steps).toBe(1);
  });

  it("the outline tool marks inside and outside; Fill armed from it fills the outline", () => {
    const s = new EditorSession(zone());
    s.choose("terrain", WALL);
    s.setBrush(3);
    s.strokeStart({ x: 15, y: 15 }, { erase: false, alt: false });
    s.strokeEnd();
    s.armTool("outline");
    s.setBrush(2);
    s.strokeStart({ x: 15, y: 15 }, { erase: true, alt: false });
    s.strokeEnd();
    const outside = () => [...s.doc.hexes.values()].filter(isOutside).length;
    expect(outside()).toBe(19);
    s.armTool("fill");
    expect(s.fillOutline).toBe(true);
    s.strokeStart({ x: 15, y: 15 }, { erase: false, alt: false });
    expect(outside()).toBe(0);
    // A swatch arms Paint and Fill fills terrain again; an open empty region is refused.
    s.choose("terrain", FLOOR);
    s.armTool("fill");
    expect(s.fillOutline).toBe(false);
    s.strokeStart({ x: 15, y: 15 }, { erase: false, alt: false });
    expect(floors(s)).toBe(37);
    s.strokeStart({ x: 40, y: 15 }, { erase: false, alt: false });
    expect(s.said).toMatch(/open/);
    expect(s.doc.hexes.size).toBe(37);
  });

  it("a town refuses the outline tool and says why", () => {
    const s = new EditorSession(
      createMap({ kind: "town", name: "Town", location: 1, biome: "meadow" }),
    );
    s.armTool("outline");
    expect(s.tool).toBe("paint");
    expect(s.said).toMatch(/no outline/);
  });

  it("the brush is radius 0 to 3; K walks the layers; the fitted grid's layer starts off", () => {
    const s = new EditorSession(zone());
    s.setBrush(9);
    expect(s.brush).toBe(3);
    s.setBrush(-1);
    expect(s.brush).toBe(0);
    expect(s.layers.seams).toBe(false);
    s.toggleLayer("grid");
    expect(s.layers.grid).toBe(false);
    for (let k = 0; k < 6; k++) s.focusNextLayer();
    expect(s.layerFocus).toBe(0);
  });
});

describe("Fit chunks and the nudge in the session (D-216)", () => {
  it("fits, shows the grid, nudges, and tells when the map was painted since", () => {
    const s = new EditorSession(zone());
    s.fitChunks();
    expect(s.said).toMatch(/Nothing to fit/);
    expect(s.doc.origin).toBeNull();
    s.strokeStart({ x: 3, y: 4 }, { erase: false, alt: false });
    s.strokeEnd();
    s.fitChunks();
    expect(s.doc.origin).toEqual({ x: 0, y: 0, how: "fitted" });
    expect(s.layers.seams).toBe(true);
    expect(s.paintedSinceOrigin).toBe(false);
    s.nudgeOrigin(-1, 0);
    expect(s.doc.origin).toEqual({ x: 14, y: 0, how: "nudged" });
    s.strokeStart({ x: 5, y: 4 }, { erase: false, alt: false });
    s.strokeEnd();
    expect(s.paintedSinceOrigin).toBe(true);
    // The origin is not a step: undo undoes the paint only.
    s.undo();
    expect(s.doc.origin?.how).toBe("nudged");
  });
});

describe("CLI-09a's deferred minors (review of #361)", () => {
  it("(c) undo mid-stroke ends the stroke first: the stroke is one step, later moves draw nothing", () => {
    const s = new EditorSession(zone());
    s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
    s.strokeMove([{ x: 1, y: 0 }]);
    s.undo();
    expect(s.doc.hexes.size).toBe(0);
    expect(s.stroking).toBe(false);
    // The pointer still moves before its release: nothing is drawn, no stray step.
    s.strokeMove([{ x: 2, y: 0 }]);
    s.strokeEnd();
    expect(s.doc.hexes.size).toBe(0);
    expect(s.history.steps).toBe(0);
    s.redo();
    expect(s.doc.hexes.size).toBe(2);
    // Redo mid-stroke as well.
    s.strokeStart({ x: 9, y: 0 }, { erase: false, alt: false });
    s.undo();
    s.redo();
    s.strokeMove([{ x: 10, y: 0 }]);
    expect(s.history.steps).toBe(2);
    expect(s.doc.hexes.size).toBe(3);
  });

  it("(a) the pending draft is written at once on flush (unmount, pagehide), never twice", () => {
    let now = 0;
    const pending = new Map<number, { at: number; run: () => void }>();
    let next = 1;
    const timers: Timers = {
      setTimeout: (run, ms) => {
        pending.set(next, { at: now + ms, run });
        return next++;
      },
      clearTimeout: (id) => void pending.delete(id),
    };
    const advance = (ms: number) => {
      now += ms;
      for (const [id, t] of [...pending]) {
        if (t.at <= now) {
          pending.delete(id);
          t.run();
        }
      }
    };
    const write = vi.fn();
    const writer = new DraftWriter(write, 400, timers);
    writer.changed();
    advance(100);
    writer.changed();
    advance(399);
    expect(write).not.toHaveBeenCalled();
    // The tab closes within the debounce: the draft is written now.
    writer.flush();
    expect(write).toHaveBeenCalledTimes(1);
    advance(1000);
    expect(write).toHaveBeenCalledTimes(1);
    // Nothing pending: a flush writes nothing.
    writer.flush();
    expect(write).toHaveBeenCalledTimes(1);
    // The debounce alone still writes.
    writer.changed();
    advance(400);
    expect(write).toHaveBeenCalledTimes(2);
    // Save writes now and cancels the pending write.
    writer.changed();
    writer.now();
    advance(1000);
    expect(write).toHaveBeenCalledTimes(3);
    expect(writer.pending).toBe(false);
  });

  it("(b) the Space hold ends on its release, on a blur and when the page is hidden", () => {
    const win = new EventTarget();
    const doc = Object.assign(new EventTarget(), {
      visibilityState: "visible" as DocumentVisibilityState,
    });
    const release = vi.fn();
    const stop = listenSpaceRelease(win as Window, doc as unknown as Document, release);
    win.dispatchEvent(Object.assign(new Event("keyup"), { code: "KeyA" }));
    expect(release).not.toHaveBeenCalled();
    win.dispatchEvent(Object.assign(new Event("keyup"), { code: "Space" }));
    expect(release).toHaveBeenCalledTimes(1);
    win.dispatchEvent(new Event("blur"));
    expect(release).toHaveBeenCalledTimes(2);
    doc.dispatchEvent(new Event("visibilitychange"));
    expect(release).toHaveBeenCalledTimes(2);
    doc.visibilityState = "hidden";
    doc.dispatchEvent(new Event("visibilitychange"));
    expect(release).toHaveBeenCalledTimes(3);
    stop();
    win.dispatchEvent(new Event("blur"));
    expect(release).toHaveBeenCalledTimes(3);
  });
});

describe("drafts (O-5)", () => {
  const memory = (): DraftStorage & { map: Map<string, string> } => {
    const map = new Map<string, string>();
    return {
      map,
      getItem: (k) => map.get(k) ?? null,
      setItem: (k, v) => void map.set(k, v),
      removeItem: (k) => void map.delete(k),
    };
  };

  it("keeps the open map, lists it last edited first with its hexes and chunks, and forgets it", () => {
    const store = new Drafts(memory());
    const a = zone();
    const s = new EditorSession(a);
    s.setBrush(1);
    s.strokeStart({ x: 0, y: 0 }, { erase: false, alt: false });
    s.strokeEnd();
    s.fitChunks();
    store.put("a", a, new Date("2026-10-05T10:00:00Z"));
    store.put(
      "b",
      createMap({ ...a.meta, name: "Other", biome: "cave" }),
      new Date("2026-10-05T11:00:00Z"),
    );
    expect(store.list().map((e) => [e.id, e.hexes, e.chunks])).toEqual([
      ["b", 0, null],
      ["a", 7, 1],
    ]);
    expect(store.get("a")).toEqual(a);
    store.forget("b");
    expect(store.list().map((e) => e.id)).toEqual(["a"]);
    expect(store.get("b")).toMatch(/gone/);
  });

  it("a draft written by CLI-09a (format 1, the old index entry) still lists and opens", () => {
    const storage = memory();
    const old = {
      format: "grimworld-map",
      version: 1,
      editor: "cli-09a",
      map: {
        kind: "town",
        name: "Old town",
        location: 1,
        width: 1,
        height: 1,
        biome: null,
        start: "floor",
        levelMin: 1,
        levelMax: 1,
        rank: 0,
        spawnTable: 0,
      },
      layers: {
        terrain: Array(15).fill(".".repeat(15)),
        ground: Array(15).fill("g".repeat(15)),
        outline: null,
      },
      obstacles: [],
    };
    storage.setItem("grimworld.editor.draft.x", JSON.stringify(old));
    storage.setItem(
      "grimworld.editor.drafts",
      JSON.stringify([
        {
          id: "x",
          kind: "town",
          name: "Old town",
          width: 1,
          height: 1,
          location: 1,
          edited: "2026-10-05T09:00:00.000Z",
        },
      ]),
    );
    const store = new Drafts(storage);
    expect(store.list()[0]).toMatchObject({ id: "x", name: "Old town" });
    const doc = store.get("x");
    expect(typeof doc !== "string" && doc.hexes.size).toBe(225);
  });

  it("Duplicate copies a draft, and says so when the storage refuses the copy", () => {
    const storage = memory();
    const store = new Drafts(storage);
    store.put("a", zone());
    expect(store.duplicate("a", "b")).toBeNull();
    expect(store.list()).toHaveLength(2);
    const full = new Drafts({
      ...storage,
      getItem: storage.getItem,
      setItem: () => {
        throw new Error("full");
      },
    });
    expect(full.duplicate("a", "c")).toMatch(/refused/);
    expect(store.duplicate("missing")).toMatch(/gone/);
  });

  it("works without a storage, and with one that throws", () => {
    const none = new Drafts(null);
    expect(none.put("a", zone())).toBe(false);
    expect(none.list()).toEqual([]);
    const throwing = new Drafts({
      getItem: () => {
        throw new Error("blocked");
      },
      setItem: () => {
        throw new Error("full");
      },
      removeItem: () => {
        throw new Error("blocked");
      },
    });
    expect(throwing.put("a", zone())).toBe(false);
    expect(throwing.list()).toEqual([]);
    expect(throwing.get("a")).toMatch(/cannot be read/);
    expect(() => throwing.forget("a")).not.toThrow();
  });
});
