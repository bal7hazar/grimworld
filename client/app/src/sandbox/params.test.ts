import { describe, expect, it } from "vitest";
import { DEFAULT_FEET, DEFAULT_ZOOM, STEP_MS } from "../render/renderer";
import { OUTPOST, TOWN } from "./fixtures/region";
import { ENTRY_MS, readAcross, readFeet, readParams } from "./params";

describe("URL parameters", () => {
  it("reads the fixture, idle, panel and scale", () => {
    expect(readParams("?fixture=cave&idle=0&panel=1&scale=sharp")).toEqual({
      fixture: "cave",
      hub: null,
      entryMs: ENTRY_MS,
      idle: false,
      panel: true,
      scale: "sharp",
      zoom: DEFAULT_ZOOM,
      feet: DEFAULT_FEET,
      playOnTap: true,
      stepMs: STEP_MS,
    });
    expect(readParams("?scale=snap").scale).toBe("snap");
    expect(readParams("?scale=pixel").scale).toBe("continuous");
    expect(readParams("")).toMatchObject({
      fixture: null,
      idle: true,
      panel: false,
      scale: "continuous",
    });
  });

  it("accepts a zoom only when finite and within the panel's bounds", () => {
    expect(readParams("?zoom=9").zoom.defaultAcross).toBe(9);
    for (const zoom of ["Infinity", "-Infinity", "NaN", "1e308", "2", "32", "-13", "abc", ""]) {
      expect(readParams(`?zoom=${zoom}`).zoom, zoom).toEqual(DEFAULT_ZOOM);
    }
    expect(readAcross(3)).toBe(3);
    expect(readAcross(31)).toBe(31);
    expect(readAcross(Infinity)).toBeNull();
  });

  it("reads the feet, the confirmation setting and the step duration within bounds", () => {
    expect(readParams("?feet=0.8&confirm=1&step=300")).toMatchObject({
      feet: 0.8,
      playOnTap: false,
      stepMs: 300,
    });
    for (const feet of ["-0.1", "1.5", "NaN", "x", ""]) {
      expect(readParams(`?feet=${feet}`).feet, feet).toBe(DEFAULT_FEET);
    }
    expect(readFeet(0)).toBe(0);
    expect(readFeet(1)).toBe(1);
    expect(readParams("?step=10").stepMs).toBe(STEP_MS);
    expect(readParams("?confirm=0").playOnTap).toBe(true);
  });

  it("opens the loop on a hub (CLI-03c); rooms keep `fixture`", () => {
    expect(readParams("?hub=town").hub).toBe(TOWN);
    expect(readParams("?hub=outpost").hub).toBe(OUTPOST);
    expect(readParams("?loop=1").hub).toBe(TOWN);
    for (const hub of ["", "nowhere", "constructor", "toString", "1"]) {
      expect(readParams(`?hub=${hub}`).hub, hub).toBeNull();
    }
    expect(readParams("?fixture=zone")).toMatchObject({ fixture: "zone", hub: null });
    expect(readParams("?hub=town&entry=0").entryMs).toBe(0);
    expect(readParams("?entry=-5").entryMs).toBe(ENTRY_MS);
    expect(readParams("?entry=99999").entryMs).toBe(ENTRY_MS);
  });
});
