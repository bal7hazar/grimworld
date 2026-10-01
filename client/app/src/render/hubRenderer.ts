import { Container, Graphics, Sprite } from "pixi.js";
import { FIGURE_HEIGHT, type HubFit, type Size, hubFit } from "../input/hubTaps";
import type { HubFigure, HubPlace, HubView } from "./hubView";
import type { Surface } from "./renderer";
import { type FrameClient, type FrameHost, FrameScheduler, type FrameStats } from "./scheduler";
import { SHAPE_HEIGHT, drawBody } from "./shapes";
import type { SpriteLibrary } from "./sprites";

/** The animation name of a building's still in the atlas (`tools/art`, `STILL_ANIM`). */
export const STILL = "still";

const COLOURS = {
  grass: 0x5d7a3e,
  grassEdge: 0x2a3a1c,
  road: 0xb89b6a,
  roadEdge: 0x8a7148,
  wall: 0xd8cfb8,
  wallShade: 0x9c947f,
  roof: 0x3b6fb6,
  roofShade: 0x2a4f84,
  door: 0x4a3420,
  gate: 0x8a8577,
  gateShade: 0x5c574d,
};

/**
 * Draws a `HubView` on demand (CLI-03c): the ground, the buildings, the present adventurers. Nothing
 * in a hub moves (D-178: adventurers stand still, as decor), so a frame is drawn when the view,
 * the atlas or the size changes, and none otherwise: no ticker, no idle frame, no timer.
 */
export class HubRenderer implements FrameClient {
  readonly scheduler: FrameScheduler;
  private readonly scene = new Container();
  private view: HubView | null = null;
  private zone: Size = { width: 1, height: 1 };
  private library: SpriteLibrary | null;

  constructor(
    private readonly surface: Pick<Surface, "stage" | "render">,
    host: FrameHost,
    options: { library?: SpriteLibrary | null; onDraw?: (stats: FrameStats) => void } = {},
  ) {
    this.library = options.library ?? null;
    this.scheduler = new FrameScheduler(host, this, options.onDraw);
    surface.stage.addChild(this.scene);
  }

  setView(view: HubView): void {
    this.view = view;
    this.rebuild();
  }

  setLibrary(library: SpriteLibrary | null): void {
    this.library = library;
    this.rebuild();
  }

  resize(zone: Size): void {
    this.zone = zone;
    this.place();
    this.scheduler.invalidate();
  }

  /** The fit the scene is drawn with: the tap targets use the same (`input/hubTaps.ts`). */
  fit(): HubFit | null {
    return this.view ? hubFit(this.view, this.zone) : null;
  }

  /** Whether a building is drawn from the atlas (else a labelled shape: the label is the page's). */
  drawnFromAtlas(place: HubPlace): boolean {
    return this.stillOf(place) !== null;
  }

  advance(): { changed: boolean; next: number | null } {
    return { changed: false, next: null };
  }

  draw(): void {
    this.surface.render();
  }

  destroy(): void {
    this.scheduler.destroy();
    this.scene.destroy({ children: true });
  }

  private rebuild(): void {
    for (const child of this.scene.removeChildren()) child.destroy({ children: true });
    const view = this.view;
    if (view) {
      this.scene.addChild(drawGround(view));
      for (const place of view.places) this.scene.addChild(this.building(place));
      const figures = [...view.figures].sort((a, b) => a.y - b.y || a.id - b.id);
      for (const figure of figures) this.scene.addChild(this.figure(figure));
    }
    this.place();
    this.scheduler.invalidate();
  }

  private place(): void {
    const fit = this.fit();
    if (!fit) return;
    this.scene.scale.set(fit.scale);
    this.scene.position.set(fit.x, fit.y);
  }

  private stillOf(place: HubPlace) {
    return this.library?.get(place.building)?.animations[STILL]?.textures[0] ?? null;
  }

  /** The still scaled to the footprint's width, its base on the place's point; else a shape. */
  private building(place: HubPlace): Container {
    const texture = this.stillOf(place);
    if (!texture) return drawBuilding(place);
    const sprite = new Sprite(texture);
    const anchor = texture.defaultAnchor;
    sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
    sprite.scale.set(place.width / Math.max(1, texture.orig.width));
    sprite.position.set(place.x, place.y);
    return sprite;
  }

  /** The profession's first idle frame, standing still, or its shape; `FIGURE_HEIGHT` tall. */
  private figure(figure: HubFigure): Container {
    const art = this.library?.get(figure.profession);
    const texture = art?.animations.idle?.textures[0];
    const container = new Container();
    container.position.set(figure.x, figure.y);
    const mirror = figure.facing === "left" ? -1 : 1;
    if (art && texture) {
      const sprite = new Sprite(texture);
      const anchor = texture.defaultAnchor;
      sprite.anchor.set(anchor?.x ?? 0.5, anchor?.y ?? 1);
      const scale = FIGURE_HEIGHT / Math.max(1, art.baseline);
      sprite.scale.set(mirror * scale, scale);
      container.addChild(sprite);
    } else {
      const body = drawBody(figure.profession);
      const scale = FIGURE_HEIGHT / SHAPE_HEIGHT[figure.profession];
      body.scale.set(mirror * scale, scale);
      container.addChild(body);
    }
    return container;
  }
}

/** Grass over the whole illustration, and a road across it toward the Gate. */
function drawGround(view: HubView): Graphics {
  const g = new Graphics();
  g.rect(0, 0, view.width, view.height).fill(COLOURS.grass);
  g.rect(0.5, 0.5, view.width - 1, view.height - 1).stroke({ width: 1, color: COLOURS.grassEdge });
  const gate = view.places.find((p) => p.target.kind === "gate");
  const roadY = gate ? gate.y - 8 : view.height * 0.75;
  g.rect(0, roadY - 9, view.width, 18).fill(COLOURS.road);
  g.moveTo(0, roadY - 9)
    .lineTo(view.width, roadY - 9)
    .moveTo(0, roadY + 9)
    .lineTo(view.width, roadY + 9)
    .stroke({ width: 1, color: COLOURS.roadEdge });
  return g;
}

/** A building as a shape: walls, a roof, a door; the Gate as an arch between two pillars. */
function drawBuilding(place: HubPlace): Graphics {
  const g = new Graphics();
  const { x, y, width: w, height: h } = place;
  g.ellipse(x, y, w * 0.55, 4).fill({ color: 0x000000, alpha: 0.25 });
  if (place.target.kind === "gate") {
    const pillar = Math.max(6, w * 0.22);
    g.rect(x - w / 2, y - h, pillar, h).fill(COLOURS.gate);
    g.rect(x + w / 2 - pillar, y - h, pillar, h).fill(COLOURS.gate);
    g.rect(x - w / 2, y - h, w, h * 0.22).fill(COLOURS.gateShade);
    g.rect(x - w / 2 + pillar, y - h * 0.78, w - 2 * pillar, h * 0.78).fill({
      color: 0x000000,
      alpha: 0.35,
    });
    return g;
  }
  const wall = h * 0.58;
  g.rect(x - w / 2, y - wall, w, wall).fill(COLOURS.wall);
  g.rect(x - w / 2, y - wall * 0.25, w, wall * 0.25).fill(COLOURS.wallShade);
  g.poly([x - w / 2 - 4, y - wall, x + w / 2 + 4, y - wall, x, y - h]).fill(COLOURS.roof);
  g.poly([x, y - h, x + w / 2 + 4, y - wall, x, y - wall]).fill(COLOURS.roofShade);
  const door = Math.max(6, w * 0.16);
  g.rect(x - door / 2, y - wall * 0.5, door, wall * 0.5).fill(COLOURS.door);
  return g;
}
