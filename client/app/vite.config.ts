import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { type Plugin, defineConfig } from "vite";
import { serveArt } from "./src/dev/serveArt.js";

/**
 * The atlas `tools/art` builds (D-73: never committed, never bundled). The development server
 * serves it at `/art/` when it exists; `GRIMWORLD_ART_OUT` points elsewhere (another checkout).
 * Nothing of it is imported by a module or copied into `dist/`: without it the sandbox draws shapes.
 */
const ART_OUT =
  process.env.GRIMWORLD_ART_OUT ?? fileURLToPath(new URL("../../tools/art/out", import.meta.url));

function devArt(): Plugin {
  return {
    name: "grimworld-dev-art",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/art", (req, res) => {
        const answer = serveArt(ART_OUT, req.url ?? "/");
        res.statusCode = answer.status;
        if (answer.status !== 200) {
          res.end();
          return;
        }
        res.setHeader("Content-Type", answer.type);
        res.setHeader("Cache-Control", "no-store");
        res.end(answer.body);
      });
      const found = existsSync(join(ART_OUT, "sprites.json"));
      server.config.logger.info(
        found
          ? `  art: serving ${ART_OUT} at /art/`
          : `  art: ${ART_OUT} not built, the sandbox draws shapes`,
      );
    },
  };
}

export default defineConfig({
  plugins: [react(), devArt()],
});
