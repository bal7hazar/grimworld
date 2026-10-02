import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { logShellStart } from "./shell/startLog";

const root = document.getElementById("root");
if (!root) throw new Error("missing #root");
createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

// The device state in the iOS shell's console (CV-03); nothing in a browser.
void logShellStart().catch((error: unknown) => console.error("[shell] device state", error));
