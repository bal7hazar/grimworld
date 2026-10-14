import { existsSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { type Plugin, defineConfig } from "vite";
import { createCreditRunner, fromLoopback } from "./src/dev/credit.js";
import { serveArt } from "./src/dev/serveArt.js";
import { serveDeployment } from "./src/dev/serveDeployment.js";
import { serveSepolia } from "./src/dev/serveSepolia.js";

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
 * `/devnet/credit` (CLI-11d3, `src/dev/credit.ts`) runs track game's credit-only mode for the
 * burner's adventurer, node-side: the browser sends only the adventurer's id. A build (`vite build`,
 * the site) serves nothing of either.
 */
function devDeployment(): Plugin {
  const path = process.env.GRIMWORLD_DEPLOYMENT;
  const credit = createCreditRunner({
    deploymentPath: path,
    root: fileURLToPath(new URL("../..", import.meta.url)),
  });
  return {
    name: "grimworld-dev-deployment",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/devnet/credit", (req, res) => {
        const remote = req.socket.remoteAddress;
        if (!fromLoopback(remote)) {
          // Refused before the body is read: this machine only
          res.statusCode = 403;
          res.setHeader("Content-Type", "application/json");
          res.end(JSON.stringify({ error: "loopback only" }));
          return;
        }
        let body = "";
        req.on("data", (chunk) => {
          // An adventurer's id needs a few bytes: a larger body is not read further
          if (body.length < 1024) body += String(chunk);
        });
        req.on("end", () => {
          void credit
            .request(remote, req.method ?? "", req.headers["content-type"], body)
            .then((answer) => {
              res.statusCode = answer.status;
              res.setHeader("Cache-Control", "no-store");
              res.setHeader("Content-Type", "application/json");
              res.end(answer.body);
            });
        });
      });
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

/**
 * Sepolia under the development server only (CLI-11e1, D-301): `/sepolia.json` answers the keyless
 * https endpoint `?chain=sepolia` plays on, `GRIMWORLD_SEPOLIA_RPC` or PublicNode's by default
 * (`src/dev/serveSepolia.ts`). A build serves nothing of it, and the app reads `?chain=sepolia` only
 * behind `import.meta.env.DEV`.
 */
function devSepolia(): Plugin {
  const setting = process.env.GRIMWORLD_SEPOLIA_RPC;
  return {
    name: "grimworld-dev-sepolia",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/sepolia.json", (_req, res) => {
        const answer = serveSepolia(setting);
        res.statusCode = answer.status;
        res.setHeader("Cache-Control", "no-store");
        if (answer.status !== 200) {
          res.end();
          return;
        }
        res.setHeader("Content-Type", "application/json");
        res.end(answer.body);
      });
      if (serveSepolia(setting).status !== 200) {
        // The setting's value is never printed: a keyed URL would carry its key
        server.config.logger.info("  sepolia: GRIMWORLD_SEPOLIA_RPC is not a keyless https URL");
      }
    },
  };
}

export default defineConfig({
  plugins: [react(), devArt(), devDeployment(), devSepolia()],
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
