import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { EditorApp } from "./Editor";
import "./editor.css";

/** The map editor's page (O-1): its own entry, `editor.html`; the game's bundle does not carry it. */
const root = document.getElementById("root");
if (!root) throw new Error("missing #root");
createRoot(root).render(
  <StrictMode>
    <EditorApp />
  </StrictMode>,
);
