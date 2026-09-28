import { Application, Container, Graphics } from "pixi.js";

/** Size in pixels of the placeholder tile (the art tiles are 64 x 64, design/10). */
export const TILE_SIZE = 64;

/** The static content of the frame: one square tile. No game state is drawn yet. */
export function buildFrame(): Container {
  const frame = new Container();
  frame.addChild(new Graphics().rect(0, 0, TILE_SIZE, TILE_SIZE).fill(0x8b5e3c));
  return frame;
}

/**
 * Renders one frame into `host`, on demand (ADR-0003, power rules): the application never starts
 * its ticker, so nothing is drawn until this function or `app.render()` is called again.
 */
export async function renderFrame(host: HTMLElement): Promise<Application> {
  const app = new Application();
  await app.init({
    width: TILE_SIZE * 4,
    height: TILE_SIZE * 4,
    background: 0x1b1b1f,
    autoStart: false,
  });
  host.appendChild(app.canvas);
  app.stage.addChild(buildFrame());
  app.render();
  return app;
}
