import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { type Plugin, defineConfig } from "vite";
import { serveArt } from "./src/dev/serveArt.js";
import { serveDeployment } from "./src/dev/serveDeployment.js";

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

/**
 * The deployment the chain mode plays on (CLI-11 §2.2): `GRIMWORLD_DEPLOYMENT` names the keyless
 * JSON `scripts/devnet_deploy.py --out` writes; the development server serves its known fields at
 * `/deployment.json`, and prints the link to open. Without the variable, `/deployment.json` is 404.
 * A build (`vite build`, the site) serves nothing of it.
 */
function devDeployment(): Plugin {
  const path = process.env.GRIMWORLD_DEPLOYMENT;
  return {
    name: "grimworld-dev-deployment",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/deployment.json", (_req, res) => {
        const answer = serveDeployment(path);
        res.statusCode = answer.status;
        res.setHeader("Cache-Control", "no-store");
        if (answer.status !== 200) {
          res.end();
          return;
        }
        res.setHeader("Content-Type", "application/json");
        res.end(answer.body);
      });
      if (!path) return;
      server.httpServer?.once("listening", () => {
        const answer = serveDeployment(path);
        const node =
          answer.status === 200 ? (JSON.parse(answer.body) as { node_url?: unknown }).node_url : "";
        const base = server.resolvedUrls?.local[0] ?? "/";
        server.config.logger.info(
          typeof node === "string" && node !== ""
            ? `  chain: open ${base}?chain=${node}`
            : `  chain: ${path} is not a deployment`,
        );
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), devArt(), devDeployment()],
  build: {
    rollupOptions: {
      // The game (`index.html`) and the map editor (`editor.html`, CLI-09 O-1): two pages, two
      // bundles; the editor imports the game's modules, the game nothing of the editor.
      input: {
        main: fileURLToPath(new URL("./index.html", import.meta.url)),
        editor: fileURLToPath(new URL("./editor.html", import.meta.url)),
      },
    },
  },
});
