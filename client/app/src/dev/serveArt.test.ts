import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { serveArt } from "./serveArt";

// A scratch folder inside the package (removed after the tests): no image of the pack, plain text.
const scratch = mkdtempSync(fileURLToPath(new URL("../../.art-test-", import.meta.url)));
const root = join(scratch, "out");
const outside = join(scratch, "outside");

beforeAll(() => {
  mkdirSync(root);
  mkdirSync(outside);
  writeFileSync(join(root, "sprites.json"), '{"pages":[],"sprites":{}}');
  writeFileSync(join(root, "atlas-0.png"), "not a real png");
  writeFileSync(join(root, "notes.txt"), "text");
  mkdirSync(join(root, "dir.json"));
  writeFileSync(join(outside, "secret.json"), '{"secret":true}');
  symlinkSync(join(outside, "secret.json"), join(root, "leak.json"));
  symlinkSync(outside, join(root, "linked"));
  symlinkSync(join(root, "sprites.json"), join(root, "alias.json"));
});

afterAll(() => rmSync(scratch, { recursive: true, force: true }));

describe("serveArt (the dev server's /art/)", () => {
  it("serves the atlas's .json and .png", () => {
    const index = serveArt(root, "/sprites.json?t=1");
    expect(index.status).toBe(200);
    expect(index.status === 200 && index.type).toBe("application/json");
    expect(serveArt(root, "/atlas-0.png")).toMatchObject({ status: 200, type: "image/png" });
    // A link that stays inside the root is served.
    expect(serveArt(root, "/alias.json").status).toBe(200);
  });

  it("refuses a symbolic link to a file outside the root", () => {
    expect(serveArt(root, "/leak.json")).toEqual({ status: 404 });
    expect(serveArt(root, "/linked/secret.json")).toEqual({ status: 404 });
  });

  it("refuses paths out of the root, other types, folders, missing files", () => {
    for (const url of [
      "/../outside/secret.json",
      "/%2e%2e/outside/secret.json",
      "/notes.txt",
      "/dir.json",
      "/atlas-9.png",
      "/",
      "/sprites.json%00.png",
    ]) {
      expect(serveArt(root, url), url).toEqual({ status: 404 });
    }
  });

  it("answers 404 to a malformed escape instead of throwing", () => {
    for (const url of ["/%", "/%zz.json", "/sprites%E0%A4%A.json"]) {
      expect(serveArt(root, url), url).toEqual({ status: 404 });
    }
  });

  it("answers 404 when the root does not exist (no atlas built)", () => {
    expect(serveArt(join(scratch, "missing"), "/sprites.json")).toEqual({ status: 404 });
  });
});
