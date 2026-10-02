import { describe, expect, it } from "vitest";
import { CairoPanic, P, shortString } from "../felt";
import { type Entry, replay } from "./replay";
import { parseTable, readTable } from "./table";

const lines = (...rows: object[]): string => rows.map((row) => JSON.stringify(row) + "\n").join("");

/** A mirror of two functions: `double` returns twice its felt, `refuse` panics. */
const entry: Entry = {
  file: "toy.jsonl",
  floor: 1,
  fns: {
    double: ([a]) => [a! * 2n],
    refuse: () => {
      throw new CairoPanic("toy: refused");
    },
    broken: () => {
      throw new TypeError("a bug of the mirror");
    },
  },
};

describe("the reader", () => {
  it("reads the tables in place", () => {
    expect(readTable("window.jsonl").length).toBeGreaterThan(0);
    expect(readTable("hit.jsonl")[0]!.fn).toBeUndefined();
  });

  it("fails on a table that does not exist", () => {
    expect(() => readTable("nothing.jsonl")).toThrow("vectors/nothing.jsonl: no such table");
  });

  it("fails on an empty table", () => {
    expect(() => parseTable("toy.jsonl", "")).toThrow("vectors/toy.jsonl: empty table");
  });

  it("fails on a malformed line, naming it", () => {
    const text = lines({ id: 0, case: ["0x1"], ok: ["0x2"] }) + "{not json\n";
    expect(() => parseTable("toy.jsonl", text)).toThrow("vectors/toy.jsonl line 2: not JSON");
  });

  it("fails on a felt not in hexadecimal, not below P, an unknown key, a missing ok", () => {
    const bad = [
      [{ id: 0, case: [1], ok: [] }, '"case" holds 1'],
      [{ id: 0, case: ["0x" + P.toString(16)], ok: [] }, "not below P"],
      [{ id: 0, case: [], ok: [], extra: 1 }, 'unknown key "extra"'],
      [{ id: 0, case: [] }, 'neither "ok" nor "err"'],
      [{ id: 0, fn: "", case: [], ok: [] }, '"fn" is not a name'],
      [{ id: 0, case: [], ok: ["0x0"], err: [] }, 'both "ok" and "err"'],
    ] as const;
    for (const [row, why] of bad) {
      expect(() => parseTable("toy.jsonl", lines(row))).toThrow(why);
    }
  });

  it("fails on ids that are not consecutive from 0", () => {
    const text = lines({ id: 0, case: [], ok: [] }, { id: 2, case: [], ok: [] });
    expect(() => parseTable("toy.jsonl", text)).toThrow("line 2: id 2, expected 1");
  });

  it("accepts a panicking case: err as short strings or felts, or ok false", () => {
    const text = lines(
      { id: 0, fn: "refuse", case: [], err: ["toy: refused"] },
      { id: 1, fn: "refuse", case: [], err: ["0x" + shortString("toy: refused").toString(16)] },
      { id: 2, fn: "refuse", case: [], ok: false },
    );
    const vectors = parseTable("toy.jsonl", text);
    expect(vectors.map((v) => v.err)).toEqual([["toy: refused"], ["toy: refused"], undefined]);
    expect(vectors.every((v) => v.ok === undefined)).toBe(true);
  });
});

describe("the replay", () => {
  const table = (...rows: object[]) => parseTable("toy.jsonl", lines(...rows));

  it("passes when the mirror agrees, counting each fn", () => {
    const vectors = table(
      { id: 0, fn: "double", case: ["0x3"], ok: ["0x6"] },
      { id: 1, fn: "refuse", case: [], err: ["toy: refused"] },
      { id: 2, fn: "refuse", case: [], ok: false },
    );
    expect(Object.fromEntries(replay(entry, vectors))).toEqual({ double: 1, refuse: 2 });
  });

  it("fails on an unknown fn", () => {
    const vectors = table({ id: 0, fn: "triple", case: ["0x3"], ok: ["0x9"] });
    expect(() => replay(entry, vectors)).toThrow(
      'vectors/toy.jsonl id 0 (triple): unknown fn "triple"',
    );
  });

  it("fails on a table without fn when the mirror has no default", () => {
    const vectors = table({ id: 0, case: ["0x3"], ok: ["0x6"] });
    expect(() => replay(entry, vectors)).toThrow('id 0: unknown fn ""');
  });

  it("fails on a count under the floor", () => {
    const vectors = table({ id: 0, fn: "double", case: ["0x3"], ok: ["0x6"] });
    expect(() => replay({ ...entry, floor: 2 }, vectors)).toThrow("1 cases, under the floor 2");
  });

  it("fails on a divergence, reporting its id", () => {
    const vectors = table(
      { id: 0, fn: "double", case: ["0x3"], ok: ["0x6"] },
      { id: 1, fn: "double", case: ["0x4"], ok: ["0x9"] },
    );
    expect(() => replay(entry, vectors)).toThrow(
      "id 1 (double): case [0x4]: got [0x8], Cairo [0x9]",
    );
  });

  it("fails on a result of another length", () => {
    const vectors = table({ id: 0, fn: "double", case: ["0x3"], ok: ["0x6", "0x0"] });
    expect(() => replay(entry, vectors)).toThrow("id 0 (double)");
  });

  it("fails on a case that throws where Cairo returned", () => {
    const vectors = table({ id: 0, fn: "refuse", case: [], ok: ["0x0"] });
    expect(() => replay(entry, vectors)).toThrow("id 0 (refuse): threw where Cairo returned [0x0]");
  });

  it("fails on a case that returns where Cairo panicked", () => {
    const vectors = table({ id: 0, fn: "double", case: ["0x1"], err: ["toy: refused"] });
    expect(() => replay(entry, vectors)).toThrow(
      "id 0 (double): returned [0x2] where Cairo panicked",
    );
  });

  it("fails on other panic data, and on an error that is not a Cairo panic", () => {
    expect(() =>
      replay(entry, table({ id: 0, fn: "refuse", case: [], err: ["toy: other"] })),
    ).toThrow("panicked with [toy: refused], Cairo with [toy: other]");
    expect(() => replay(entry, table({ id: 0, fn: "broken", case: [], ok: false }))).toThrow(
      "not a Cairo panic",
    );
  });
});
