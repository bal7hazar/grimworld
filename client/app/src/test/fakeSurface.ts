import { Container, type Rectangle, Texture, TextureSource } from "pixi.js";
import type { Surface } from "../render/renderer";

/** A surface without a GPU: it counts renders, bakes and offscreen passes. */
export class FakeSurface implements Surface {
  readonly stage = new Container();
  maxTextureSize = 4096;
  renders = 0;
  /** The colour bakes' resolutions. */
  readonly bakes: number[] = [];
  /** The grayscale bakes' (CLI-03n): the chunks' twins and the atlas's stills. */
  readonly greyBakes: number[] = [];
  /** Offscreen passes (`sharp`): the target of each. */
  readonly passes: Texture[] = [];
  /**
   * What each pass fills, in texels: the target's frame at its source's resolution (a Texture
   * target's frame is the pass's viewport in PixiJS).
   */
  readonly filled: number[] = [];

  constructor(
    public resolution = 2,
    readonly devicePixelRatio = resolution,
  ) {}

  render(): void {
    this.renders += 1;
  }

  bake(_target: Container, frame: Rectangle, resolution: number, grey = false): Texture {
    (grey ? this.greyBakes : this.bakes).push(resolution);
    return new Texture({ source: new TextureSource({ width: frame.width, height: frame.height }) });
  }

  renderTo(container: Container, target: Texture): void {
    if (container.parent) throw new Error("renderTo takes a root container");
    this.passes.push(target);
    const r = target.source.resolution;
    this.filled.push(Math.round(target.frame.width * r) * Math.round(target.frame.height * r));
  }
}
