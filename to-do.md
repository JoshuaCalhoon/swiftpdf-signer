## In progress
_(none — end-to-end pipeline validated)_

## Next
- [ ] **Validate template creation end-to-end**: create a new template via the Library screen, sign it, verify the signed PDF lands in `/Apps/SwiftPDF/Signed/` with the right name; verify the template's JSON shows up in `/Apps/SwiftPDF/Templates/`; verify edit + delete work; verify Library refreshes on pull-down. (Editor + library code path now hardened — WR-08/11/12/13 fixes in commit `10bf585`.)
- [ ] Keyboard avoidance behind the signature canvas if it comes up during real-world testing
- [ ] **Install on the real iPad** (blocked on Apple Developer Program approval): once approved, fill `DEVELOPMENT_TEAM` in `Configuration/Local.xcconfig`, run `xcodegen generate`, plug iPad in via USB-C, enable Developer Mode on the iPad, run from Xcode. Wireless after first install via Window → Devices & Simulators → "Connect via Network".
  - **Required iPad setup before handoff:** the iPad must have a device passcode set in iOS Settings → Face ID & Passcode (or Touch ID & Passcode). The customer-handoff lock (`ManagerGate`) falls back to the device passcode when biometrics fail. Without a passcode the gate refuses to authenticate and the manager can't return to the Library.
- [ ] (Optional, while waiting) Smoke-test device install via Xcode's free Personal Team — 7-day cert, fine for one-off confirmation that signing/install works before the paid cert lands.
- [ ] Revisit Swift 6 mode once SwiftyDropbox catches up (`SwiftyDropbox` 10.2.4 static singleton triggers strict concurrency errors)
- [ ] **`TemplateStoreTests`**: extract a `DropboxServiceProtocol` so the store can be unit-tested against a mocked Dropbox. Verifies `save()` create-vs-update branching, bundled-id reject path, `lastRefreshSkipCount` accounting. Deferred from commit 10 because the refactor of `DropboxService` (a `final class`) into a protocol abstraction was scope-larger than the test commit.

### Deferred from review remediation (2026-05-11)
These are real findings from the three-reviewer remediation but were scoped out of the 10-commit run:
- [ ] **Multi-page PDF rendering** (gsd CR-04 option B). Today `FormRenderer.render` throws `RenderError.contentTooLong` if content overflows a single US Letter page — fail-loud safety net. Real pagination (track remaining vertical space, `context.beginPage()` when needed, reserve signature for the last page) is the follow-on whenever a real template overruns.
- [ ] **Template integrity HMAC** (/cso #3 option B, **awaiting D3 decision**). Bundled-id reject is in (commit `25e0a7f`), but body-level integrity for user-authored templates is unspecified. Options: sign each JSON with an app-side Keychain key; or skip and rely on Dropbox's own version history.
- [ ] **Differentiated error categories with recovery hints** (gsd cross-cutting #2). Current `Status.failure(message:)` is undifferentiated — network / auth / quota / file-too-large / template-too-long all look identical to the user. Refactor into typed cases with per-case recovery suggestion.
- [ ] **Multi-tenant `FormHeader` config** (gsd cross-cutting #3). `FormHeader.kwikshipStandard()` is hardcoded. Read from `Info.plist` so a future second warehouse doesn't need a code change. Speculative; defer until a second site appears.
- [ ] **Accessibility audit** (gsd cross-cutting #4). Only the ellipsis menu has an explicit `accessibilityLabel` today. Signature pad, error banners, status panel, template rows all lack VoiceOver text.
- [ ] **Dropbox `rev`-based template cache** (gsd WR-09 follow-on). Parallel downloads landed in commit `cbb06d8`; caching by `rev` (skip re-download for unchanged templates) is the next perf step at >10 templates.
- [ ] **Localization**. All strings hardcoded English; no NSLocalizedString.

## Blocked / questions
- App icon / launch screen branding — defer until v1 ships (cosmetic)
- Should `references/` be cleaned up since the in-app template supersedes the Word-doc pipeline? (Word doc + Resources/General Safety.pdf are no longer used by the app — kept for reference only)
- **D3 — Template integrity strategy** (asked 2026-05-11, user thinking): bundled-id reject in, HMAC deferred pending decision. See `/cso` finding #3 in `SECURITY-REVIEW.md`.

## Done (recent)
- [x] Bootstrap project-memory files
- [x] Pull KwikShip brand colors from `KwikShip_Logo.svg`: #FF5100, #3D3935, #30261D
- [x] Write `design.md` with KwikShip orange accent — approved
- [x] Write `project.yml` for XcodeGen with configFiles + info.properties (URL scheme via xcconfig substitution)
- [x] Architectural pivot: in-app template authoring instead of Word-doc-bundled approach
- [x] Receive Dropbox App Key from user; store in gitignored `Configuration/Local.xcconfig`
- [x] Write v1 sources: `SwiftPDFApp`, `ContentView`, `ConnectDropboxView`, `FormView`, `FormTemplate`, `FormRenderer`, `SignatureCanvas`, `DropboxService`, `DropboxConfig`, `DesignTokens`
- [x] Install iOS 26.4.1 platform package via `xcodebuild -downloadPlatform iOS`
- [x] Switch project to Swift 5 mode (SwiftyDropbox 10.2.4 not Swift-6-strict-ready)
- [x] First successful build for iPad Pro 11 iOS 18.6 simulator — confirmed FormView renders correctly
- [x] Add first-launch Dropbox auth gate (`ConnectDropboxView`), gated by `dropbox.authState` in `ContentView`
- [x] Bump signature canvas to 200pt — fits Pencil/finger signing comfortably
- [x] Confirmed Connect Dropbox screen renders on the simulator
- [x] FormRenderer fix: use `UIGraphicsPDFRendererContext.beginPage()` (replace the `UIGraphicsGetCurrentContext()?.beginPDFPage(nil)` path)
- [x] Error-paths polish pass: cache rendered PDF + Retry button on failure; ellipsis-menu Disconnect Dropbox with confirmation; auth failures during upload (token revoked / refresh fail) clear local auth so ContentView routes back to ConnectDropboxView
- [x] **End-to-end pipeline validated** (2026-05-11): OAuth round-trip works in the simulator, one real signed upload landed in `/Apps/SwiftPDF/Signed/` with the correct filename, ellipsis menu Disconnect button verified visible
- [x] Success interstitial: bottom panel swaps to "Signed and Saved" + "Sign Another" CTA after upload (supersedes prior auto-dismiss banner + auto-clear behavior); see design.md decision log
- [x] **In-app template creation** (2026-05-11): Library screen replaces hardcoded route; `FormContent` enum splits structured (bundled General Safety) from freeform (user-authored); TemplateEditorView for create/edit; swipe-to-edit/delete on user templates; templates sync via Dropbox `/Apps/SwiftPDF/Templates/` as `{uuid}.json` files; Disconnect Dropbox moves to the Library toolbar.
- [x] **Pre-stage device-install signing** (2026-05-11): `DEVELOPMENT_TEAM` removed from `project.yml` (was hardcoded empty, shadowing xcconfig); `CODE_SIGN_STYLE: Automatic` set at project level; `Configuration/Local.xcconfig` extended with a `DEVELOPMENT_TEAM =` slot; `.example` updated with documentation. Once Apple Developer Program is approved, the install path is: fill team ID → `xcodegen generate` → run from Xcode.
- [x] **Three-reviewer code review** (2026-05-11): Ran Claude + `/gsd-code-review` + `/cso` on the full source tree. 43 raw findings → 24 distinct → 10-commit remediation plan (`REMEDIATION-PLAN.md`, gitignored). All three review docs gitignored alongside the plan.
- [x] **Remediation commits 1-10** (2026-05-11, pushed `ed34b31..9bed185`):
  - `25e0a7f` Stable bundled UUIDs (`FormTemplate.BundledID`) + impersonation reject in `TemplateStore.refresh()`. Addresses gsd CR-02, WR-10, /cso #3 partial.
  - `a89277f` `String.sanitizedForFilename()` + UTF-8 byte truncation; static `DateFormatter` pinned to `en_US_POSIX` + Gregorian + America/Chicago in both `FormView` and `FormRenderer`. Addresses Claude #1+#7, gsd CR-01, WR-03, IN-05, /cso #2.
  - `08c15b3` `FormRenderer.render` throws `RenderError.contentTooLong` on overflow; degenerate-signature reject (width/height > 0.5); `.scrollIndicators(.visible)` on FormView preview. Addresses gsd CR-04, CR-05, user scroll-affordance flag.
  - `45cafc7` `FormView.submit` early-exit on `isUploading`; autorename detection + warning; `Status.success(path:, autorenamedFrom:)`; `invalidateAfterEdit` gated on `!isUploading`; explicit catch for `ServiceError.notAuthorized`; `TemplateStore.save` filter-based reconstruction (no `dropFirst` invariant). Addresses gsd CR-03, CR-06, WR-04, Claude #2.
  - `32a38e3` `DropboxService.handleRedirect` validates URL scheme; distinguishes `.cancel` from `.none`; explicit `Task { @MainActor in ... }` hop; drops `[weak self]`. Addresses gsd WR-06, WR-07, /cso #5.
  - `41f8738` `ManagerGate` + biometric/passcode lock on FormView Exit and LibraryView Disconnect Dropbox; `NSFaceIDUsageDescription`; architecture.md decision entry. Addresses /cso #1.
  - `10bf585` Editor discard-changes guard; structural-content assertion in `prefill()`; `inFlightDeletes: Set<UUID>`; Edit gated on `.freeform` content; `saveError` reset. Addresses gsd WR-08, WR-11, WR-12, WR-13.
  - `14272db` `os.Logger` with `.private` error / `.public` filename; `lastRefreshSkipCount` surfaced in LibraryView footer. Addresses gsd IN-04, /cso #4.
  - `cbb06d8` `Calendar.date` fallback; DEBUG-only `fatalError` on app key + release-build `App is misconfigured` path; symmetric `SignatureCanvas.updateUIView`; parallel template downloads via `withTaskGroup`; iterative `topPresented`; named constants for `signatureRenderScale` + `strokeWidth`. Addresses gsd WR-01, WR-02, WR-05, WR-09, IN-01, IN-03, Claude #4+#9.
  - `9bed185` New `SwiftPDFTests` target — 18/18 green: `FilenameSanitizationTests` (10), `FormTemplateCodableTests` (4), `FormRendererTests` (4). Addresses gsd cross-cutting #1.
