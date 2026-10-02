import { describe, expect, it } from "vitest";
import config from "../../capacitor.config";

/** CV-03, AC-2: the shell's configuration (scope 2). */
describe("capacitor.config.ts", () => {
  it("is the iOS shell of the production build", () => {
    expect(config.appId).toBe("com.example.grimworld");
    expect(config.appName).toBe("Grim World");
    expect(config.webDir).toBe("dist");
  });

  it("loads the bundled build, never a server", () => {
    expect(config.server?.url).toBeUndefined();
  });

  it("has no Android section (D-152)", () => {
    expect(config.android).toBeUndefined();
  });

  it("turns Web Inspector on and the web view's scroll off", () => {
    expect(config.ios?.webContentsDebuggingEnabled).toBe(true);
    expect(config.ios?.scrollEnabled).toBe(false);
  });
});
