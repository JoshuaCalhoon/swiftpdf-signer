# App Store listing screenshots

Output directory for `Design/capture-screenshots.sh`. One subdirectory per device size:

- `iphone-6.9/` — iPhone 16 Pro Max (1320×2868) — required for App Store
- `iphone-6.5/` — iPhone 11 Pro Max (1284×2778) — required for App Store
- `ipad-13/` — iPad Pro 13" M4 (2064×2752) — required for App Store

Each shot is named `01-library.png`, `02-form.png`, `03-signature.png`, etc. — leading number controls listing display order. Light-mode and dark-mode pairs use `-light` / `-dark` suffixes (e.g. `01-library-light.png`).

Generated PNGs are tracked in git so the listing assets stay in lock-step with the release that produced them.
