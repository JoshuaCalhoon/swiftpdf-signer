## In progress
_(none — end-to-end pipeline validated)_

## Next
- [ ] **Validate template creation end-to-end**: create a new template via the Library screen, sign it, verify the signed PDF lands in `/Apps/SwiftPDF/Signed/` with the right name; verify the template's JSON shows up in `/Apps/SwiftPDF/Templates/`; verify edit + delete work; verify Library refreshes on pull-down.
- [ ] Keyboard avoidance behind the signature canvas if it comes up during real-world testing
- [ ] **Install on the real iPad** (blocked on Apple Developer Program approval): once approved, fill `DEVELOPMENT_TEAM` in `Configuration/Local.xcconfig`, run `xcodegen generate`, plug iPad in via USB-C, enable Developer Mode on the iPad, run from Xcode. Wireless after first install via Window → Devices & Simulators → "Connect via Network".
- [ ] (Optional, while waiting) Smoke-test device install via Xcode's free Personal Team — 7-day cert, fine for one-off confirmation that signing/install works before the paid cert lands.
- [ ] v1.1: in-app template editor (deferred — task #13)
- [ ] Revisit Swift 6 mode once SwiftyDropbox catches up (`SwiftyDropbox` 10.2.4 static singleton triggers strict concurrency errors)

## Blocked / questions
- App icon / launch screen branding — defer until v1 ships (cosmetic)
- Should `references/` be cleaned up since the in-app template supersedes the Word-doc pipeline? (Word doc + Resources/General Safety.pdf are no longer used by the app — kept for reference only)
- Multi-page rendering — current renderer assumes content fits one US Letter page. If a future template overruns, FormRenderer needs page-break logic. Not a v1 blocker.

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
