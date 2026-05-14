# App Store listing screenshots

Output directory for `Design/capture-screenshots.sh`. One subdirectory per device size:

- `iphone-6.5/` — iPhone 11 Pro Max (1242×2688) — required for iPhone App Store listing
- `ipad-13/` — iPad Pro 13" M4 (2064×2752) — required for iPad App Store listing

The iPhone uses the latest installed iOS runtime (currently iOS 26.4) since the listing renders well on any iOS 18+ device. The iPad is pinned to iOS 18.6 to match the deployment target's actual hardware.

Each shot is named `01-library.png`, `02-form.png`, `03-signature.png`, etc. — leading number controls listing display order. Light-mode and dark-mode pairs use `-light` / `-dark` suffixes (e.g. `01-library-light.png`).

Generated PNGs are tracked in git so the listing assets stay in lock-step with the release that produced them.
