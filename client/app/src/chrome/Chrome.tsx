import {
  type ButtonHTMLAttributes,
  type CSSProperties,
  type HTMLAttributes,
  type ReactNode,
  type Ref,
  createContext,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { Profession } from "../render/view";
import "./chrome.css";
import {
  type ChromeImages,
  ChromeSession,
  type HudImages,
  PORTRAITS,
  type PortraitSize,
  browserLoaders,
  chromeProperties,
} from "./load";
import { fillWidth } from "./scale";

/**
 * The client's chrome (CLI-03i): the pack's papers, scroll, wooden board, buttons, ribbons and
 * icons around ordinary elements. `ChromeProvider` cuts the UI page and marks its root
 * `data-chrome="atlas"`; without the art it marks `plain`, and every component then renders with
 * its `plain` style, today's look exactly (`sandbox/loop/styles.ts`). The look itself is in
 * `chrome.css`, scoped to `[data-chrome="atlas"]`.
 */

export type ChromeMode = "atlas" | "plain";

const Mode = createContext<ChromeMode>("plain");

/** Whether the chrome's art is shown around this element. */
export const useChromeMode = () => useContext(Mode);

/** The HUD's images (null: plain) and the pixel ratio its fills are measured at (CLI-03l). */
const HudArt = createContext<{ readonly images: HudImages | null; readonly dpr: number }>({
  images: null,
  dpr: 1,
});

/** Whether the HUD's art is shown: `plain` without it, even when the chrome has its own. */
export const useHudMode = (): ChromeMode => (useContext(HudArt).images ? "atlas" : "plain");

const currentDpr = () => window.devicePixelRatio || 1;

/**
 * The root of the chromed screens: a `div` with the chrome's custom properties, `data-chrome` and
 * `data-chrome-dpr`. The images are cut again when the pixel ratio changes (a window moved to
 * another screen), and their URLs revoked when replaced or unmounted.
 */
export function ChromeProvider({
  children,
  style,
  ...rest
}: HTMLAttributes<HTMLDivElement> & { children: ReactNode }) {
  const [images, setImages] = useState<ChromeImages | null>(null);
  const [dpr, setDpr] = useState(currentDpr);
  const session = useRef<ChromeSession | null>(null);
  // One session while mounted (made in the effect, so React's replay of effects in development
  // gets a fresh one); a ratio change asks it for new images and it revokes the old ones.
  useEffect(() => {
    const made = new ChromeSession(setImages, browserLoaders);
    session.current = made;
    return () => {
      made.destroy();
      session.current = null;
    };
  }, []);
  useEffect(() => {
    void session.current?.show(dpr);
    const query = window.matchMedia?.(`(resolution: ${dpr}dppx)`);
    const changed = () => setDpr(currentDpr());
    query?.addEventListener("change", changed);
    return () => query?.removeEventListener("change", changed);
  }, [dpr]);
  const mode: ChromeMode = images ? "atlas" : "plain";
  const hud = images?.hud ?? null;
  const hudArt = useMemo(() => ({ images: hud, dpr: images?.dpr ?? dpr }), [hud, images, dpr]);
  return (
    <Mode.Provider value={mode}>
      <HudArt.Provider value={hudArt}>
        <div
          {...rest}
          style={images ? { ...style, ...(chromeProperties(images) as CSSProperties) } : style}
          data-chrome={mode}
          data-chrome-dpr={images ? images.dpr : undefined}
          data-cursors={hud ? "" : undefined}
        >
          {children}
        </div>
      </HudArt.Provider>
    </Mode.Provider>
  );
}

const classes = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(" ");

/** What a plain style says of the look, which the art replaces: the rest (layout) is kept. */
const LOOK = new Set<string>([
  "background",
  "border",
  "borderTop",
  "borderBottom",
  "borderColor",
  "borderRadius",
  "padding",
  "color",
  "font",
  "fontSize",
  "fontWeight",
  "lineHeight",
  "opacity",
  "minHeight",
  "minWidth",
  "width",
  "height",
]);

/** The style of a component: `plain` whole without the art, its layout only with it; `style` on top. */
function styleOf(atlas: boolean, plain?: CSSProperties, style?: CSSProperties) {
  if (!atlas) return { ...plain, ...style };
  const layout = Object.fromEntries(Object.entries(plain ?? {}).filter(([k]) => !LOOK.has(k)));
  return { ...layout, ...style };
}

type PanelVariant = "paper" | "dark" | "scroll" | "wood";

/**
 * A panel: the regular paper, the special (dark) paper, the scroll or the wooden board. `plain`
 * is its style without the art (today's), of which only the layout stays with it; `style` applies
 * in both.
 */
export function Panel({
  variant,
  as: Tag = "div",
  plain,
  style,
  className,
  ...rest
}: HTMLAttributes<HTMLElement> & {
  variant: PanelVariant;
  as?: "div" | "section" | "aside" | "nav";
  plain?: CSSProperties;
}) {
  const atlas = useChromeMode() === "atlas";
  return (
    <Tag
      {...rest}
      className={classes("gw-panel", `gw-panel-${variant}`, className)}
      style={styleOf(atlas, plain, style)}
    />
  );
}

type ButtonVariant = "action" | "commit" | "quiet";

/**
 * A button: `action` (the blue button) for what moves on, `commit` (the red one) for the second,
 * irreversible tap of I-5 and the Gate, `quiet` (paper, ink) for Back, Stay, Skip, Close. Its
 * label rides the face when pressed. `plain` is its look without the art (today's).
 */
export function Button({
  variant,
  plain,
  style,
  className,
  children,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant: ButtonVariant; plain?: CSSProperties }) {
  const atlas = useChromeMode() === "atlas";
  return (
    <button
      {...rest}
      className={classes("gw-button", `gw-button-${variant}`, className)}
      style={styleOf(atlas, plain, style)}
    >
      <span className="gw-label">{children}</span>
    </button>
  );
}

/** The pack's icons the chrome cuts (`icon_back`, `icon_close`, `icon_gold`), and the HUD's sword. */
export type IconName = "back" | "close" | "gold" | "sword";

/** One of the pack's icons at the chrome's scale; `text` stands for it without the art. */
export function Icon({ name, text }: { name: IconName; text: string }) {
  const chrome = useChromeMode() === "atlas";
  const hud = useHudMode() === "atlas";
  const atlas = name === "sword" ? hud : chrome;
  return atlas ? (
    <span className={`gw-icon gw-icon-${name}`} role="img" aria-label={text} />
  ) : (
    <>{text}</>
  );
}

/**
 * A small round blue button with an icon of the pack or a glyph (the pack has no recentre icon).
 * `label` is its accessible name; `plain` and `plainText` its look and text without the art,
 * `style` applies in both (layout).
 */
export function IconButton({
  icon,
  glyph,
  label,
  plain,
  plainText,
  style,
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  icon?: Exclude<IconName, "gold" | "sword">;
  glyph?: string;
  label: string;
  plain?: CSSProperties;
  plainText: string;
}) {
  const atlas = useChromeMode() === "atlas";
  return (
    <button
      {...rest}
      aria-label={label}
      className={classes("gw-icon-button", className)}
      style={styleOf(atlas, plain, style)}
    >
      {atlas ? (
        <span className="gw-label">
          {icon ? <span className={`gw-icon gw-icon-${icon}`} /> : glyph}
        </span>
      ) : (
        plainText
      )}
    </button>
  );
}

/**
 * A title or a name on a ribbon: big (screen titles) in blue or red, small (place names) in
 * yellow. White large text on the big ones, ink on the yellow one (`contrast.ts`).
 */
export function Ribbon({
  colour,
  size,
  as: Tag = "span",
  plain,
  style,
  className,
  ...rest
}: HTMLAttributes<HTMLElement> & {
  colour: "blue" | "red" | "yellow";
  size: "big" | "small";
  as?: "span" | "h1" | "div";
  plain?: CSSProperties;
  ref?: Ref<HTMLDivElement & HTMLSpanElement & HTMLHeadingElement>;
}) {
  const atlas = useChromeMode() === "atlas";
  return (
    <Tag
      {...rest}
      className={classes("gw-ribbon", `gw-ribbon-${size}`, `gw-ribbon-${colour}`, className)}
      style={styleOf(atlas, plain, style)}
    />
  );
}

/**
 * A line of secondary text: a caption (a section's label) or a muted line. Its colour follows the
 * surface it sits on (`chrome.css`); `plain` is today's style, kept without its colour on the art.
 */
export function Text({
  tone,
  as: Tag = "div",
  plain,
  className,
  style,
  ...rest
}: HTMLAttributes<HTMLElement> & {
  tone: "caption" | "muted";
  as?: "div" | "p" | "span" | "li";
  plain?: CSSProperties;
}) {
  const atlas = useChromeMode() === "atlas";
  const look = atlas ? { ...plain, color: undefined } : plain;
  return (
    <Tag
      {...rest}
      className={classes(`gw-text-${tone}`, className)}
      style={{ ...look, ...style }}
    />
  );
}

/** A bar's look without the art: a dark trough in a slate frame, of the art's height (CLI-03l). */
const PLAIN_BAR: Record<"big" | "small", CSSProperties> = {
  big: { height: 26, padding: "6px 6px 8px", background: "#2a2a33", borderRadius: 4 },
  small: { height: 10, padding: "3px 5px", background: "#2a2a33", borderRadius: 3 },
};
const PLAIN_TRACK: CSSProperties = { background: "#111" };
const PLAIN_FILL: Record<"health" | "energy", CSSProperties> = {
  health: { background: "#e04848" },
  energy: { background: "#41919d" },
};

/**
 * A bar (CLI-03l *The method* §2): the pack's wooden frame (`big`, health, the red fill) or its
 * thin one (`small`, energy, the fill recoloured blue), the fill inside the trough at
 * `fillWidth` whole device px of it; no fill element at 0. A `meter` with its figures in
 * `aria-*`; the visible figures sit beside it (the caller's). Without the HUD's art, CSS bars of
 * the same boxes. It renders again only on a resize of its trough or a change of its figures.
 */
export function Bar({
  size,
  tone,
  current,
  max,
  label,
}: {
  size: "big" | "small";
  tone: "health" | "energy";
  current: number;
  max: number;
  label: string;
}) {
  const { images, dpr } = useContext(HudArt);
  const atlas = images !== null;
  const track = useRef<HTMLDivElement>(null);
  const [trackPx, setTrackPx] = useState(0);
  useLayoutEffect(() => {
    const element = track.current;
    if (!element) return;
    const measure = () => setTrackPx(Math.round(element.getBoundingClientRect().width * dpr));
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [dpr, atlas]);
  const fill = fillWidth(trackPx, current, max);
  return (
    <div
      role="meter"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={max}
      aria-valuenow={Math.min(Math.max(current, 0), max)}
      className={classes("gw-bar", `gw-bar-${size}`, `gw-bar-${tone}`)}
      style={
        atlas
          ? undefined
          : { ...PLAIN_BAR[size], boxSizing: "border-box", display: "flex", flex: "1 1 auto" }
      }
      data-bar={tone}
    >
      <div
        ref={track}
        className="gw-bar-track"
        style={atlas ? undefined : { ...PLAIN_TRACK, flex: 1, minWidth: 96 }}
        data-track-px={trackPx}
      >
        {fill > 0 && (
          <div
            className="gw-bar-fill"
            style={{ width: `${fill / dpr}px`, height: "100%", ...(atlas ? {} : PLAIN_FILL[tone]) }}
            data-fill-px={fill}
          />
        )}
      </div>
    </div>
  );
}

/**
 * A portrait (CLI-03l *The method* §3): the profession's avatar of the pack in a `size` CSS px
 * box, cut at that size for the screen (smoothed when reduced), one image px per device px; the
 * Arcanist, or no HUD art, draws a lettered disc of the same box. `label` names who it shows.
 */
export function Portrait({
  profession,
  size,
  label,
}: {
  profession: Profession;
  size: PortraitSize;
  label: string;
}) {
  const { images, dpr } = useContext(HudArt);
  const entry = PORTRAITS[profession];
  const cut = entry ? images?.portraits.get(entry)?.get(size) : undefined;
  return (
    <span
      role="img"
      aria-label={label}
      className="gw-portrait"
      data-portrait={cut ? entry! : "plain"}
      style={{
        display: "inline-flex",
        flex: "none",
        alignItems: "center",
        justifyContent: "center",
        width: size,
        height: size,
      }}
    >
      {cut ? (
        <img
          src={cut.url}
          alt=""
          draggable={false}
          style={{ width: cut.w / dpr, height: cut.h / dpr, imageRendering: "pixelated" }}
        />
      ) : (
        <span
          aria-hidden
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            boxSizing: "border-box",
            width: size,
            height: size,
            borderRadius: "50%",
            background: "#2a2a33",
            border: "2px solid #f2c94c",
            color: "#fff",
            font: `700 ${Math.round(size * 0.45)}px/1 system-ui`,
          }}
        >
          {profession.charAt(0).toUpperCase()}
        </span>
      )}
    </span>
  );
}
