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

describe("the palette stays the editor's (CLI-09e)", () => {
  const sources = import.meta.glob<string>("../../**/*.{ts,tsx}", {
    query: "?raw",
    import: "default",
    eager: true,
  });

  it("no module outside the editor imports it, so the game's bundle never holds it", () => {
    const outside = Object.entries(sources).filter(([path]) => path.startsWith("../../"));
    expect(outside.length).toBeGreaterThan(20);
    for (const [path, text] of outside) {
      expect(text, path).not.toMatch(/from\s+["'][^"']*palette["'/]/);
    }
  });
});
