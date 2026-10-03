import {
  type ButtonHTMLAttributes,
  type CSSProperties,
  type HTMLAttributes,
  type ReactNode,
  type Ref,
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import "./chrome.css";
import { type ChromeImages, ChromeSession, browserLoaders, chromeProperties } from "./load";

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
  return (
    <Mode.Provider value={mode}>
      <div
        {...rest}
        style={images ? { ...style, ...(chromeProperties(images) as CSSProperties) } : style}
        data-chrome={mode}
        data-chrome-dpr={images ? images.dpr : undefined}
      >
        {children}
      </div>
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

/** The pack's icons the chrome cuts (`icon_back`, `icon_close`, `icon_gold`). */
export type IconName = "back" | "close" | "gold";

/** One of the pack's icons at the chrome's scale; `text` stands for it without the art. */
export function Icon({ name, text }: { name: IconName; text: string }) {
  const atlas = useChromeMode() === "atlas";
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
  icon?: Exclude<IconName, "gold">;
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
