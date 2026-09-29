import { describe, expect, it } from "vitest";
import { DEFAULT_ZOOM } from "../render/renderer";
import { readAcross, readParams } from "./params";

describe("URL parameters", () => {
  it("reads the fixture, idle, panel and scale", () => {
    expect(readParams("?fixture=cave&idle=0&panel=1&scale=sharp")).toEqual({
      fixture: "cave",
      idle: false,
      panel: true,
      scale: "sharp",
      zoom: DEFAULT_ZOOM,
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
});
