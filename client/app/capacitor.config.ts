import type { CapacitorConfig } from "@capacitor/cli";

/**
 * The iOS shell of SPK-6.1 (CV-03, D-151, D-152): the production build in a WKWebView. No
 * `server.url` (the app loads its bundled `dist/`, never the Mac's dev server) and no Android.
 */
const config: CapacitorConfig = {
  // A placeholder: the owner sets the real identifier in `ios/App/Signing.local.xcconfig`.
  appId: "com.example.grimworld",
  appName: "Grim World",
  webDir: "dist",
  ios: {
    // On for the measurement builds (SPK-6 protocol §9 point 9): Safari's Web Inspector reaches
    // the page. A build for any store turns it off (HRD-08).
    webContentsDebuggingEnabled: true,
    // The web view's rubber-band scroll would fight the sandbox's pan and pinch.
    scrollEnabled: false,
  },
};

export default config;
