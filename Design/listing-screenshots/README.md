# App Store listing screenshots

Output directory for `Design/capture-screenshots.sh`. One subdirectory per device size:

- `iphone-6.5/` — iPhone Air on iOS 26.5 — required for iPhone App Store listing
- `ipad-13/` — iPad Pro 13" M4 on iOS 18.6 — required for iPad App Store listing

The iPhone Air was introduced in iOS 26.5 (its device class doesn't exist on earlier runtimes). The iPad is pinned to iOS 18.6 to match the physical iPad's OS version.

Each shot is named `01-library.png`, `02-form.png`, `03-signature.png`, etc. — leading number controls listing display order. Light-mode and dark-mode pairs use `-light` / `-dark` suffixes (e.g. `01-library-light.png`).

Generated PNGs are tracked in git so the listing assets stay in lock-step with the release that produced them.
