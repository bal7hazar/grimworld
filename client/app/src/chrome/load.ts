import { ART_BASE } from "../render/atlas";
import { type SpritesIndex, type UiSlices, readSpritesIndex } from "../render/sprites";
import { type SliceLengths, sliceLengths } from "./scale";

/**
 * The chrome's images (CLI-03i *The method* §1, option D): the `ui` page of the atlas `tools/art`
 * built is fetched once, each interface element's frame is cut into its own small image at the
 * device's scale (nearest-neighbour), and kept as an in-memory object URL; nothing per element is
 * served. Without the art, or with any problem, there are no images and the screens keep today's
 * plain look.
 */

/** The elements the stylesheet draws: all of them, or the plain look. */
export const CHROME_ENTRIES = [
  "paper",
  "paper_dark",
  "scroll",
  "wood",
  "button_blue",
  "button_red",
  "ribbon_big_blue",
  "ribbon_big_red",
  "ribbon_small_yellow",
  "round_blue",
  "icon_back",
  "icon_close",
  "icon_gold",
] as const;

export type ChromeEntryName = (typeof CHROME_ENTRIES)[number];
export type ChromeState = "regular" | "pressed";

export interface ChromeEntry {
  readonly ui: UiSlices;
  readonly lengths: SliceLengths;
  /** One object URL per state: `regular`, and `pressed` for an element that has it. */
  readonly urls: Readonly<Partial<Record<ChromeState, string>>>;
}

export interface ChromeImages {
  readonly dpr: number;
  readonly entries: ReadonlyMap<ChromeEntryName, ChromeEntry>;
  /** Every object URL made, to revoke when the images are replaced or dropped. */
  readonly urls: readonly string[];
}

export interface Frame {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
}

/** What the loader needs of the browser; injectable, so it is tested without one. */
export interface ChromeLoaders<Image = unknown> {
  fetchJson(url: string): Promise<unknown>;
  loadImage(url: string): Promise<Image>;
  /** The frame of `image`, scaled nearest-neighbour to `size` device px, as an object URL. */
  cut(
    image: Image,
    frame: Frame,
    size: { readonly w: number; readonly h: number },
  ): Promise<string>;
  revoke(url: string): void;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The frame `key` of a parsed page (TexturePacker "hash"), if it is one. */
function frameOf(page: unknown, key: string): Frame | null {
  if (!isRecord(page) || !isRecord(page.frames)) return null;
  const entry = page.frames[key];
  const f = isRecord(entry) ? entry.frame : null;
  if (!isRecord(f)) return null;
  const { x, y, w, h } = f;
  const whole = [x, y, w, h].every((v) => Number.isInteger(v) && (v as number) >= 0);
  return whole ? ({ x, y, w, h } as Frame) : null;
}

export const browserLoaders: ChromeLoaders<HTMLImageElement> = {
  async fetchJson(url) {
    const response = await fetch(url);
    if (!response.ok) return null;
    return response.json().catch(() => null);
  },
  async loadImage(url) {
    const image = new Image();
    image.src = url;
    await image.decode();
    return image;
  },
  async cut(image, frame, size) {
    const canvas = document.createElement("canvas");
    canvas.width = size.w;
    canvas.height = size.h;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("no 2D context");
    context.imageSmoothingEnabled = false;
    context.drawImage(image, frame.x, frame.y, frame.w, frame.h, 0, 0, size.w, size.h);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/png"));
    if (!blob) throw new Error("the canvas gave no image");
    return URL.createObjectURL(blob);
  },
  revoke: (url) => URL.revokeObjectURL(url),
};

/**
 * The chrome's images at a pixel ratio, or null: no `sprites.json`, a refused one, no `ui` page,
 * an element of `CHROME_ENTRIES` missing, a frame that is not its element's whole cell, or a load
 * that fails. The URLs made before a failure are revoked.
 */
export async function loadChrome<Image>(
  base: string,
  dpr: number,
  loaders: ChromeLoaders<Image>,
): Promise<ChromeImages | null> {
  let json: unknown;
  try {
    json = await loaders.fetchJson(`${base}sprites.json`);
  } catch {
    return null;
  }
  if (json === null || json === undefined) return null;
  const read = readSpritesIndex(json);
  if ("problem" in read) return null;
  const index: SpritesIndex = read.index;
  const missing = CHROME_ENTRIES.filter((name) => !index.sprites[name]?.ui);
  if (missing.length > 0) {
    if (index.pages.some((page) => page.group === "ui")) {
      console.warn(`[chrome] sprites.json lacks ${missing.join(", ")}; plain look`);
    }
    return null;
  }
  const urls: string[] = [];
  try {
    const pages = new Map<number, Promise<{ page: unknown; image: Image }>>();
    const pageOf = (n: number) => {
      let found = pages.get(n);
      if (!found) {
        const info = index.pages[n]!;
        found = loaders.fetchJson(base + info.json).then(async (page) => ({
          page,
          image: await loaders.loadImage(base + info.image),
        }));
        pages.set(n, found);
      }
      return found;
    };
    const entries = new Map<ChromeEntryName, ChromeEntry>();
    for (const name of CHROME_ENTRIES) {
      const sprite = index.sprites[name]!;
      const ui = sprite.ui!;
      const { page, image } = await pageOf(sprite.page);
      const lengths = sliceLengths(ui, sprite.cell, dpr);
      const made: Partial<Record<ChromeState, string>> = {};
      for (const state of ["regular", ...(ui.states ?? [])] as ChromeState[]) {
        const frame = frameOf(page, `${name}/${state}/00`);
        if (!frame || frame.w !== sprite.cell.w || frame.h !== sprite.cell.h) {
          throw new Error(`${name}/${state}: no frame of ${sprite.cell.w} × ${sprite.cell.h}`);
        }
        const url = await loaders.cut(image, frame, lengths.image);
        urls.push(url);
        made[state] = url;
      }
      entries.set(name, { ui, lengths, urls: made });
    }
    return { dpr, entries, urls };
  } catch (error) {
    console.error(`[chrome] the UI page could not be cut (${String(error)}); plain look`);
    for (const url of urls) loaders.revoke(url);
    return null;
  }
}

const px = (v: number) => `${+v.toFixed(4)}px`;
const cssName = (name: string) => name.replace(/_/g, "-");

/**
 * The custom properties the stylesheet reads, per element `--gw-<name>` (dashes for underscores):
 * the image (`url(…)`) and `-pressed`, `-slice` (image px), `-width` and `-pad` (CSS px, top right
 * bottom left), `-w` and `-h` (the image's CSS size), `-drop`, `-min-w` and `-min-h` (the slices'
 * sums); and `--gw-px`, one device pixel.
 */
export function chromeProperties(images: ChromeImages): Record<string, string> {
  const out: Record<string, string> = { "--gw-px": px(1 / images.dpr) };
  for (const [name, entry] of images.entries) {
    const n = `--gw-${cssName(name)}`;
    const { lengths, urls } = entry;
    out[n] = `url("${urls.regular}")`;
    if (urls.pressed) out[`${n}-pressed`] = `url("${urls.pressed}")`;
    out[`${n}-slice`] = lengths.slice.join(" ");
    out[`${n}-width`] = lengths.width.map(px).join(" ");
    out[`${n}-pad`] = lengths.content.map(px).join(" ");
    out[`${n}-w`] = px(lengths.size.w);
    out[`${n}-h`] = px(lengths.size.h);
    out[`${n}-drop`] = px(lengths.drop);
    // The least size that holds the slices unscaled: smaller, the browser would shrink them.
    out[`${n}-min-w`] = px(lengths.width[1] + lengths.width[3]);
    out[`${n}-min-h`] = px(lengths.width[0] + lengths.width[2]);
  }
  return out;
}

/**
 * The images for the current pixel ratio, replaced when it changes: each `show` loads a new set,
 * hands it to `apply`, and revokes the set it replaces; a load overtaken by a newer one is revoked
 * unseen. `destroy` revokes what is shown.
 */
export class ChromeSession<Image = unknown> {
  private shown: ChromeImages | null = null;
  private generation = 0;
  private destroyed = false;

  constructor(
    private readonly apply: (images: ChromeImages | null) => void,
    private readonly loaders: ChromeLoaders<Image>,
    private readonly base = ART_BASE,
  ) {}

  async show(dpr: number): Promise<void> {
    const generation = ++this.generation;
    const images = await loadChrome(this.base, dpr, this.loaders);
    if (this.destroyed || generation !== this.generation) {
      if (images) this.revoke(images);
      return;
    }
    const old = this.shown;
    this.shown = images;
    this.apply(images);
    if (old) this.revoke(old);
  }

  destroy(): void {
    this.destroyed = true;
    if (this.shown) this.revoke(this.shown);
    this.shown = null;
  }

  private revoke(images: ChromeImages): void {
    for (const url of images.urls) this.loaders.revoke(url);
  }
}
