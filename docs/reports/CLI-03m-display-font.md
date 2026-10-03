# CLI-03m — A pixel display font, and the review notes of CLI-03l

Closes open question 2 of `docs/briefs/CLI-03i-client-chrome.md` (reverse: a pixel display font, decided by the orchestrator, 2026-10-03).

## What changed

- **Font**: Pixelify Sans through `@fontsource/pixelify-sans` **5.3.0** (exact, no `^`), latin subset,
  weights 600 and 700, `woff2` only, `font-display: swap`. `client/app/src/chrome/fonts.css` declares the
  two faces and `--gw-display: "Pixelify Sans", system-ui`; `Chrome.tsx` imports it. Vite bundles the files.
- **Applied to**: buttons (blue, red, quiet), big and yellow ribbons, the plain look's buttons and title
  (`sandbox/loop/styles.ts`), and the HUD band's figures. Body text stays `system-ui`. Sizes stay in rem.
- **Not applied** (on purpose): the round icon button's glyph, the debug controls (their own look), the
  map's place plates, the desktop panels' small headings and the header's gold figure; they are labels or
  glyphs, not titles, ribbons or buttons.
- **Notes of #347**: the adventurer doc comment is back above `AdventurerSheet`; `bandSheet()` reads
  `readParams(...).hud`; `Bar` takes the model's `aria` (so `hud.test.ts` asserts what the rendered
  meter carries); the art test is `test_a_still_without_a_margin_keeps_its_size`; _Deviations_ 7 of
  `CLI-03l-hud.md` says "AC-8's p95 judged on the median of three pairs".
- `PLAN.md`: a CLI-03m row; CLI-03g2, h, i, k, l set to done with their PR numbers.
- `CREDITS.md`: one entry. `chrome/fonts.test.ts`: the font is a `woff2` of the package, no URL outside the site.

## Acceptance

- **AC-1**: package `@fontsource/pixelify-sans` 5.3.0, `"license": "OFL-1.1"` in its `package.json`. Its
  `LICENSE` begins "Copyright 2021 The Pixelify Sans Project Authors (https://github.com/eifetx/Pixelify-Sans)
  / This Font Software is licensed under the SIL Open Font License, Version 1.1." Lockfile integrity:
  `sha512-4RCe9nXbi7wUu5+H0FNX1sgPZ2kJ1MmY1uTkEfvQIzzqhoS8zGKJaJfdK8oreE0OU+5gM+NdurFi3H3FJRBvyw==`.
- **AC-2**: `vite build` emits `dist/assets/pixelify-sans-latin-600-normal-Dd_Dy7u5.woff2` (8216 bytes)
  and `…-700-normal-D3Xxx3QE.woff2` (7904 bytes). `grep -o 'url([^)]*)' dist/assets/*.css | sort -u` prints
  only `url(/assets/pixelify-sans-latin-600-normal-Dd_Dy7u5.woff2)` and the 700 one;
  `grep -c "https\?://" dist/assets/*.css` prints 0.
- **AC-3** (headless Chromium on `vite preview` of `dist/`, the look without art, computed `font-family`):
  button `"Pixelify Sans", system-ui` (Keys ?, Back); ribbon `"Pixelify Sans", system-ui` (Town A, Gate · Town A);
  HUD figure `"Pixelify Sans", system-ui`; body text `system-ui` (Attributes). `document.fonts`: both faces `loaded`.
  Zero requests outside the site during the run.
- **AC-4**: `pnpm --filter @grimworld/app test` 457 passed, 1 skipped; `lint` and `typecheck` clean;
  `python3 -m unittest discover -s tools/art/tests`: 85 run, OK, 51 skipped (they need the private `assets` submodule, absent here).
- **AC-5**: at 375 × 812 and 1440 × 900, in the town and after the Gate tap: no button or ribbon has
  `scrollWidth > clientWidth` or `scrollHeight > clientHeight` (10 buttons and 10 ribbons in the town at 375;
  11 and 10 at 1440), and the page does not scroll sideways. Screenshots are in the library folder, not committed.
- **AC-6**: the four notes as above.

## Follow-up: the atlas look at 375 px (measured on the live site)

At 375 × 812 (scale 3) the town's service row put "Enchanter" (label 100 px) in a 111 px button, 1 px past its right frame (`scrollWidth` 112 against `clientWidth` 111); all other screens, sizes and `?hud=` values held (0 sideways scroll, `data-chrome="atlas"`, both faces loaded). Fix: at `max-width: 480px` the row's labels are 1 rem with 8 px side padding; "Enchanter" is then 91 px, 10 px clear of the frame (measured with the rule injected into the live page; confirmed after deploy).

## What was not checked

- **The atlas look** (`data-chrome="atlas"`): this machine has neither the `assets` submodule nor a built
  atlas, so `verify-chrome.mjs` and `verify-hud.mjs` could not run, and the check above is of the plain look
  only. The CSS rules are the same four `font` declarations, so the risk is a wider label in a nine-slice
  at a larger text size; the buttons are `white-space: nowrap` and grow with their content, the ribbons grow taller.
  The owner's eye (D-177) or a run of those two scripts on the Mac settles it.
- No fallback-face metrics (`size-adjust`): swap can shift a label by a few pixels when the font arrives.
