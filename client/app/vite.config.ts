import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { type Plugin, defineConfig } from "vite";
import { embedArt, embedArtWanted } from "./src/dev/embedArt.js";
import { serveArt } from "./src/dev/serveArt.js";

/**
 * The atlas `tools/art` builds (D-73: never committed, never bundled). The development server
 * serves it at `/art/` when it exists; `GRIMWORLD_ART_OUT` points elsewhere (another checkout).
 * Nothing of it is imported by a module, and `dist/` gets it only in a local build of the shell
 * (`embedArtBuild`): without it the sandbox draws shapes.
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

/**
 * The atlas copied into `dist/art/` for the iOS shell (CV-03, D-73): only with
 * `GRIMWORLD_EMBED_ART=1`, refused when `CI` is set. `ART_BASE` stays `/art/`, served from `dist/`.
 */
function embedArtBuild(): Plugin {
  let outDir = "dist";
  let wanted = false;
  return {
    name: "grimworld-embed-art",
    apply: "build",
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir);
      wanted = embedArtWanted(process.env);
      if (!wanted) return;
      if (!existsSync(join(ART_OUT, "sprites.json"))) {
        throw new Error(`art: ${ART_OUT} not built (run tools/art, or set GRIMWORLD_ART_OUT)`);
      }
    },
    writeBundle() {
      if (!wanted) return;
      const target = join(outDir, "art");
      const names = embedArt(ART_OUT, target);
      this.info(
        `art: ${names.length} files of ${ART_OUT} copied into ${target} (local build only)`,
      );
    },
  };
}

export default defineConfig({
  plugins: [react(), devArt(), embedArtBuild()],
});
