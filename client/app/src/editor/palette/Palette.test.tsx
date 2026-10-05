import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { BUILDINGS, PROPS } from "./kinds";
import { Palette } from "./Palette";

describe("the palette component (CLI-09e)", () => {
  it("renders the four menus, the filter and the open menu's kinds", () => {
    const html = renderToStaticMarkup(<Palette thumbs={null} onSelect={() => {}} />);
    for (const category of ["prop", "building", "npc", "bridge"]) {
      expect(html).toContain(`data-category="${category}"`);
    }
    expect(html).toContain('aria-label="Filter the kinds"');
    expect(html.match(/data-kind="/g)).toHaveLength(PROPS.length);
    expect(html).toContain('data-kind="cannon"');
    // Without an atlas, a kind shows its label alone.
    expect(html).not.toContain("<canvas");
  });

  it("opens on a given menu with a selected kind", () => {
    const html = renderToStaticMarkup(
      <Palette
        thumbs={null}
        onSelect={() => {}}
        initial={{ category: "building", filter: "", selected: "castle" }}
      />,
    );
    expect(html.match(/data-kind="/g)).toHaveLength(BUILDINGS.length);
    expect(html).toMatch(/aria-pressed="true" data-kind="castle"/);
    expect(html).toMatch(/aria-pressed="true" data-category="building"/);
  });
});

/** An import of the palette module: a static `from` or a dynamic `import(`. */
const IMPORTS_PALETTE = /(from\s+|import\(\s*)["'][^"']*palette(\/[^"']*)?["']/;

/**
 * The modules outside the editor (paths from the app's root, `/src/…`) that import the palette.
 * The editor's own modules may (part 2 wires it into `Editor.tsx`); the palette's are not scanned.
 */
function gameImporters(files: readonly (readonly [string, string])[]): string[] {
  return files
    .filter(([path]) => !path.startsWith("/src/editor/"))
    .filter(([, text]) => IMPORTS_PALETTE.test(text))
    .map(([path]) => path);
}

describe("the palette stays the editor's (CLI-09e)", () => {
  const sources = import.meta.glob<string>("/src/**/*.{ts,tsx}", {
    query: "?raw",
    import: "default",
    eager: true,
  });

  it("no module outside the editor imports it, so the game's bundle never holds it", () => {
    const files = Object.entries(sources).filter(([path]) => !/\.test\.tsx?$/.test(path));
    expect(files.filter(([path]) => !path.startsWith("/src/editor/")).length).toBeGreaterThan(20);
    expect(files.some(([path]) => path === "/src/editor/palette/kinds.ts")).toBe(true);
    expect(gameImporters(files)).toEqual([]);
  });

  it("lets an editor module import it, and catches a game module, statically or dynamically", () => {
    expect(
      gameImporters([
        ["/src/editor/Editor.tsx", 'import { Palette } from "./palette";'],
        ["/src/editor/canvas.ts", 'import { drawPreview } from "./palette/preview";'],
        ["/src/editor/palette/Palette.tsx", 'import { kindOf } from "./kinds";'],
      ]),
    ).toEqual([]);
    expect(
      gameImporters([
        ["/src/render/renderer.ts", 'import { KINDS } from "../editor/palette";'],
        ["/src/sandbox/Sandbox.tsx", 'const p = await import("../editor/palette/kinds");'],
        ["/src/App.tsx", 'import { Palette } from "./editor/palette/index";'],
        ["/src/render/ground.ts", 'import { hexCorners } from "./shapes";'],
      ]),
    ).toEqual(["/src/render/renderer.ts", "/src/sandbox/Sandbox.tsx", "/src/App.tsx"]);
  });
});
