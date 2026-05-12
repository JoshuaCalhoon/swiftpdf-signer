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
- **SourceKit-LSP false positives**: per-file diagnostics (the ones the harness surfaces inline) default to a macOS context, so they flag missing `UIViewRepresentable`, `NSColor` vs `UIColor`, `Color.kwikshipOrange`, etc. These fire after every edit and look alarming — they are NEVER the truth. The truth is `xcodebuild ... build` or `xcodebuild ... test`. To fix permanently: install `xcode-build-server` (`brew install xcode-build-server`) and generate `buildServer.json` — would give SourceKit the right target context.
- **Building requires installed iOS simulator runtime**: Xcode 26.4.1 ships with the SDK but the runtime is a separate download via Xcode → Settings → Platforms. Without it, `xcodebuild -destination ...` fails with "Found no destinations" or "iOS 26.4 is not installed".
- xcodegen does **not** auto-generate schemes from a bare target definition — must declare an explicit top-level `schemes:` block (see `project.yml`).
- **Simulator UUID drift**: `xcrun simctl list devices` can show different UUIDs than `xcodebuild -showdestinations` for the same physical simulator entry. **Always cross-check with `xcodebuild -showdestinations` before scripting a build** — that's the list xcodebuild actually accepts. Current iPad 7th-gen (iOS 18.6) ID: `60226EA0-7C80-458D-BFE9-F7A19F90CAE6` (subject to change after Xcode/simctl regeneration).
- **xcodegen YAML reparenting trap**: inserting a new target between an existing target's `settings:` block and its `info:` block silently reparents the `info:` block under the new target. After `xcodegen generate`, the original target ends up with no `INFOPLIST_FILE` and code-signing fails with "Cannot code sign because the target does not have an Info.plist file." Mitigation: put new target definitions at the END of `targets:`, never between fields of an existing target.
- **Filename convention (current, post-sanitization)**: `{sanitize(template.name)} - {sanitize(signer)} [yyyy-MM-dd].pdf`, truncated to ≤240 UTF-8 bytes before the `.pdf` extension. Both halves go through `String.sanitizedForFilename()` (strips `/ \ < > : " | ? *`, control chars, leading dots; collapses to `-`). Date formatter is locked to `en_US_POSIX` + Gregorian + America/Chicago.
- **Customer-handoff lock prerequisite**: the iPad must have a device passcode set in iOS Settings → Face ID & Passcode. `ManagerGate.require` falls back to passcode when biometrics fail; without a passcode set, `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication, ...)` returns false and the gate returns `.notConfigured`. The Library shows a user-visible "ask IT to set a passcode" alert in that case rather than trapping the manager.
- **Bundled-template sentinel IDs**: every bundled template has a stable UUID held in `FormTemplate.BundledID.all`. `TemplateStore.refresh()` rejects any synced JSON whose `id` is in that set — defense against malicious or accidentally-edited Dropbox files claiming to be a bundled template. Add a new sentinel any time a new bundled template ships.
- **`FormRenderer.render` throws** `RenderError.contentTooLong` if content would push the signature block past `pageSize.height - margin - signatureBlockHeight` (150pt reserved for the signature). v1 is single-page only; multi-page is a follow-on.

## Privacy
- `references/` and `Resources/*.pdf` are gitignored. The actual form content is not tracked.
- Memory files (this one, `architecture.md`, `mapfile.md`, etc.) may be committed — keep business-specific content out of them when possible; refer to the form generically.
