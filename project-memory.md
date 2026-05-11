# Project memory — SwiftPDF

## What this is
Native iPad app (SwiftUI). Opens a PDF form, lets a manager fill in name fields, hands iPad to a customer who signs with Pencil or finger, flattens to PDF, uploads to a Dropbox folder with a deterministic filename. v1 ships with one hardcoded form ("General Safety"); v2 adds an in-app form builder.

## Layout
- `Sources/` — Swift source (created during scaffolding)
- `Resources/` — bundled PDFs and signed-form templates (gitignored — see `.gitignore`)
- `references/` — source materials (Word docs etc.) — gitignored, never committed
- `project.yml` — XcodeGen spec; generates `SwiftPDF.xcodeproj`
- `SwiftPDF.xcodeproj/` — generated, gitignored

## Build & tooling
- Xcode 26.4.1 (iOS 26.4 SDK), deployment target **iOS 18.0** (iPad-only)
- Project generated with **xcodegen** from `project.yml`
- Word → PDF conversion via Microsoft Word + AppleScript (until/unless we move to native PDF generation)
- Dependencies via Swift Package Manager inside the Xcode project

## Pinned versions
- SwiftyDropbox **10.2.4** (Dec 2025) — OAuth PKCE flow, async/await upload API

## Conventions
- Filename pattern for uploaded signed PDFs: `{FormName} - {SignerName} [{YYYY-MM-DD}].pdf`
- Signer name captured by a form-field overlay (customer types their own name before signing)
- Date is the date of signing (local device time)
- Dropbox token stored in Keychain (never in UserDefaults)

## Gotchas
- The source Word doc currently has only a `Name: ___ Date: ___` footer — **no signature line**. Plan: append acknowledgment + signature line to the Word doc, re-export PDF.
- Word AppleScript `save as ... file format format PDF` requires `set theDoc to active document` after `open` (the `set theDoc to open ...` form silently fails to bind).
- `Resources/*.pdf` is gitignored — anyone cloning the repo must provide their own form PDF.
- **SourceKit-LSP false positives**: per-file diagnostics (the ones the harness surfaces inline) default to a macOS context, so they flag missing `UIViewRepresentable`, `NSColor` vs `UIColor`, etc. Ignore them. Truth is `swiftc -typecheck -sdk $(xcrun --show-sdk-path --sdk iphonesimulator) -target arm64-apple-ios18.0-simulator Sources/*.swift` (and `xcodebuild` once a simulator runtime is installed). To fix permanently: install `xcode-build-server` (`brew install xcode-build-server`) and generate `buildServer.json` — would give SourceKit the right target context.
- **Building requires installed iOS simulator runtime**: Xcode 26.4.1 ships with the SDK but the runtime is a separate download via Xcode → Settings → Platforms. Without it, `xcodebuild -destination ...` fails with "Found no destinations" or "iOS 26.4 is not installed".
- xcodegen does **not** auto-generate schemes from a bare target definition — must declare an explicit top-level `schemes:` block (see `project.yml`).

## Privacy
- `references/` and `Resources/*.pdf` are gitignored. The actual form content is not tracked.
- Memory files (this one, `architecture.md`, `mapfile.md`, etc.) may be committed — keep business-specific content out of them when possible; refer to the form generically.
