# Architecture decisions

### 2026-05-11 — Native Swift iPad app, not off-the-shelf
**Decision:** Build a native SwiftUI app for iPad to handle the fill-and-sign-and-upload flow.
**Why:** Off-the-shelf options (PDF Expert, Dropbox Sign, Acrobat Fill & Sign) all require the manager to remember a manual "Duplicate first" step plus a manual rename before saving, or charge per-signature for the routed signing flow we don't need. One forgotten duplicate = signed-over master template = data loss risk. PDF Expert was tried first as the interim solution.
**Consequences:** Owns the full filename/upload pipeline — the app will never overwrite a template. Cost is the build effort vs. paying for a SaaS.

### 2026-05-11 — Deployment target iOS 18.0
**Decision:** Minimum iOS 18.0; target iPad only.
**Why:** Fleet of business iPads is on iOS 18 and not auto-upgrading. iOS 18 has every API we need (PDFKit, PencilKit, modern SwiftUI, Swift 6, async/await). iOS 26's Liquid Glass + Apple Intelligence Foundation Models aren't relevant for this app.
**Consequences:** No iOS 19+/26+ APIs. Code stays portable to future iPadOS releases as long as we don't depend on backports.

### 2026-05-11 — SwiftyDropbox 10.2.4 with OAuth PKCE
**Decision:** Use the official SwiftyDropbox SDK (v10.2.4, Dec 2025), OAuth PKCE flow with short-lived tokens + automatic refresh. Add via Swift Package Manager.
**Why:** Considered three approaches: (1) FileProvider via the Dropbox iOS app — zero-config but sync timing not guaranteed and depends on the Dropbox app being installed; (2) Direct REST calls — reinventing the wheel; (3) SwiftyDropbox SDK — programmatic control, async/await API, official, handles token refresh. (3) wins for reliability.
**Consequences:** One-time "Connect Dropbox" tap on each iPad (OAuth in-app browser). Refresh token persisted in Keychain. Need a Dropbox app registered at dropbox.com/developers/apps to get an App Key and configure the URL scheme.

### 2026-05-11 — XcodeGen for project generation
**Decision:** Use `xcodegen` driven by `project.yml`; gitignore the generated `.xcodeproj`.
**Why:** `.xcodeproj` files are notoriously merge-hostile and not human-readable. `project.yml` is text, diffs cleanly, and regenerates the project deterministically. Already installed at `/opt/homebrew/bin/xcodegen`.
**Consequences:** Editing target/scheme/build settings means editing `project.yml` and re-running `xcodegen generate`. Anyone cloning the repo runs `xcodegen generate` after install — single command.

### 2026-05-11 — Name capture via form-field overlay
**Decision:** Customer types their own name into a tappable text-field overlay positioned on top of the existing PDF Name field. The app reads that field's value to build the filename.
**Why:** Considered: (a) manager types name before handoff — adds friction and the manager may not know the customer's spelling; (b) OCR the handwritten name — introduces errors that propagate into the filename; (c) post-sign prompt — two-step. The customer typing their own name is most accurate (they confirm their own spelling) and lowest-friction.
**Consequences:** App needs to know coordinates of name field on the PDF. v1 hardcodes coords for the General Safety form. v2 form builder must let managers define field coords on arbitrary PDFs.

### 2026-05-11 — v1 hardcoded form, v2 form builder
**Decision:** Ship v1 with the General Safety form hardcoded (struct describes field/signature positions in a `Resources/` PDF). Defer the in-app form builder to v2.
**Why:** The form-builder is a meaningful UX project on its own. v1's job is to prove the fill-sign-flatten-upload pipeline end-to-end on one real form.
**Consequences:** Adding a second form before v2 = code change + rebuild. Acceptable for the immediate timeframe; revisit once form count > 2.

### 2026-05-11 — Source-of-truth Word doc gets extended with a signature block
**Decision:** Append an acknowledgment paragraph + Print Name / Signature / Date block to the existing General Safety Word doc, replacing the current bare `Name: ___ Date: ___` footer. Then re-export to PDF for the app to bundle.
**Why:** The current Word doc has no signature line — only a print-name field. Without an explicit signature line and acknowledgment text, signed copies have weaker legal weight ("did the signer actually agree to follow these rules?"). Considered compositing the signature into open space without changing the source doc, but that produces a signed PDF that looks improvised. Keeping the Word doc as the canonical source is also healthier long-term.
**Consequences:** The Word doc edit is a one-time task. The app's PDF-overlay coordinates are anchored to the new signature block's position on the re-exported PDF — once we have it, hardcode coords for v1.

### 2026-05-11 — In-app form templates, dynamic PDF rendering (supersedes Word-doc-as-source-of-truth)
**Decision:** Forms are defined as in-app `FormTemplate` structs (header + intro + numbered rules + acknowledgment). The app renders each filled-and-signed instance to a PDF dynamically using `UIGraphicsPDFRenderer` + `NSAttributedString`. v1 ships with one hardcoded template ("General Safety Rules" — content seeded from the existing Word doc). Phase 2 adds an in-app template editor so managers can author / edit / version templates without a rebuild.
**Why:** User asked for the option to create and edit templates inside the app: "in case the form changes or we need new ones." Sticking with Word→PDF→bundle would require a developer (and a rebuild) every time the safety rules change. Owning the rendering pipeline also means the signature ends up in a deterministic location every time, no coordinate-fishing on each new PDF.
**Consequences:**
- Word doc and `Resources/General Safety.pdf` are no longer the source of truth — kept on disk for reference but no longer bundled into the app. v1 still seeds the template content from the existing Word doc text.
- Need a `FormTemplate` Codable model, a `FormRenderer` that produces PDF Data from a filled template, and a (phase 2) template-editor UI.
- The "convert Word to PDF" and "measure field coordinates" tasks are now moot — drops complexity.
- Signed PDFs are still uploaded to Dropbox with the same filename convention.
- Supersedes the 2026-05-11 decision about extending the Word doc with a signature block (that block becomes part of the rendered template's structure instead).

### 2026-05-11 — Brand accent: KwikShip orange `#FF5100`
**Decision:** App accent color is `#FF5100`, sourced from the live `KwikShip_Logo.svg` on kwikship.com. Supporting palette: `#3D3935` (warm dark), `#30261D` (deep brown), `#FFFFFF` (white).
**Why:** User asked to inspect the site for the brand ethos. The Word doc's title color (`#E97132`) was Microsoft Word's default orange accent style — close but not the actual brand color. The SVG gave us the true value. Site's overall ethos ("industrial-meets-approachable, utility-focused with personality") informed the minimalism of the rest of the design.
**Consequences:** All chrome (buttons, focus rings, accents) uses `#FF5100`. PDF rendering is unaffected — the PDF carries its own colors. If KwikShip rebrands later, accent change is a single-line edit in a `Color` extension.

### 2026-05-11 — Swift 5 language mode (deferred upgrade to Swift 6)
**Decision:** Target `SWIFT_VERSION: "5"` for the SwiftPDF app target.
**Why:** SwiftyDropbox 10.2.4 declares `DropboxClientsManager.authorizedClient` as `public static var DropboxClient?` without actor isolation. Swift 6 strict concurrency flags any access to this as "shared mutable state" — hard error. Lowering `SWIFT_STRICT_CONCURRENCY` to `minimal` doesn't help because Swift 6's baseline checking is still mandatory. Considered (a) wrapping accesses with `MainActor.assumeIsolated` and `nonisolated(unsafe)` shims (correct but adds boilerplate everywhere we touch the SDK), (b) Swift 5 language mode (clean, no dependency-specific workarounds). (b) wins for v1; iOS 18 / Swift 5.10 mode still gives us async/await, `@MainActor`, `@Observable`, and macros.
**Consequences:** Cannot use Swift 6-only language features (e.g. strict typed-throws improvements). When SwiftyDropbox ships a Swift 6-ready release (likely with `@MainActor` or `nonisolated(unsafe)` annotations on the singleton), upgrade `SWIFT_VERSION` back to `"6"`. No runtime behavior change — pure compile-time mode setting.

### 2026-05-11 — In-app template authoring with Dropbox-synced JSON
**Decision:** Templates are stored as `{uuid}.json` files in `/Apps/SwiftPDF/Templates/` on Dropbox. The app lists + downloads + decodes them at launch and on pull-to-refresh, merging the result with the bundled `[FormTemplate.generalSafetyV1]`. The library is the new home screen (replaces the hardcoded route into General Safety). Editor exposes `Title` + freeform `Body`; the header is locked to the KwikShip standard (`FormHeader.kwikshipStandard()`). The `FormContent` enum carries either `.structured(intro:rules:acknowledgment:)` (preserving the original General Safety rendering) or `.freeform(body:)` (for manager-authored templates). Bundled templates have `editable: false` — the Library hides delete + edit affordances for them.
**Why:** User asked for the ability to create new PDF templates in-app so non-developers can author new forms when warehouse rules change. Dropbox-synced was the explicit choice (over local-only Documents storage) so a template created on one iPad is visible on every other iPad logged in to the same Dropbox account — and so signed PDFs and the templates that produced them live in the same place. JSON-as-source-of-truth means existing bundled templates don't need a migration path; they continue rendering the structured way while user-authored content takes the freeform path.
**Consequences:**
- `FormTemplate` becomes `Codable, Hashable` (NavigationLink-value routing requires Hashable).
- `DropboxService` gains `listTemplates` / `downloadTemplate` / `saveTemplate` / `deleteTemplate`. The auth-failure-routing helper becomes generic on the `CallError` route type. `listTemplates` treats `.path(.notFound)` as empty (folder is auto-created on first upload).
- `files.content.read` implicitly includes `files.metadata.read` per Dropbox's scope model — `list_folder` works without an explicit scope addition, so existing OAuth tokens keep working. No forced re-auth.
- `TemplateStore` is a new `@Observable @MainActor` service. Sync errors don't blow away the previous template list — surfaced in the Library footer instead.
- The Disconnect Dropbox affordance migrates from the FormView toolbar to LibraryView (the new root screen). FormView's toolbar is now empty other than the navigation back button.

### 2026-05-11 — Dropbox App Key handled via xcconfig + Info.plist substitution
**Decision:** `DROPBOX_APP_KEY` lives in `Configuration/Local.xcconfig` (gitignored). xcodegen wires this xcconfig into both Debug and Release configurations. The build setting flows into `Info.plist` via `$(DROPBOX_APP_KEY)` substitution — exposed both as a custom `DropboxAppKey` key (read at runtime by `DropboxConfig`) and as the `CFBundleURLTypes` scheme `db-$(DROPBOX_APP_KEY)` for the OAuth callback. A `.example` template is committed so clones know what to fill in.
**Why:** App Keys are technically public OAuth client IDs (PKCE makes the key alone insufficient to impersonate), but the user has signaled a privacy preference (already gitignored `references/`). Keeping the App Key out of git follows that pattern with negligible build complexity. Considered hardcoding directly in `project.yml` (simpler, but App Key ends up in git history); rejected. Considered storing in both Swift source AND xcconfig (two sources of truth); rejected — xcconfig is the single source, Swift reads through Info.plist.
**Consequences:** Clone workflow: copy `Configuration/Local.xcconfig.example` → `Configuration/Local.xcconfig`, fill in real App Key, run `xcodegen generate`, build. If `Local.xcconfig` is missing at build time, Xcode warns and the `DropboxAppKey` key ends up empty — `DropboxConfig` will `fatalError` with a clear message pointing at the fix.

### 2026-05-11 — Customer-handoff lock via `LocalAuthentication`
**Decision:** Every transition from `FormView` back to `LibraryView`, and every Disconnect Dropbox tap, runs through `ManagerGate.require(reason:)` — a small wrapper over `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`. That policy prompts FaceID / TouchID first and falls back to the device passcode automatically. The "PIN" the manager enters is the iPad's own passcode; the app stores nothing.
**Why:** The product threat model is "manager hands iPad to customer for a 30-second signature, takes it back." Without a gate, the customer can tap the back arrow, reach the Library, disconnect Dropbox (with only a confirmation dialog), or create/edit/delete templates. `/cso` flagged this as HIGH severity. Considered three options: (A) iOS Guided Access setup docs (zero code, manager has to remember to triple-click before handoff), (B) app-level lock with PIN/biometric, (C) full manager/customer mode separation. (B) wins for v1 — it doesn't require remembering an iOS setup step before every customer, doesn't invent a PIN we have to manage, and biometrics are friction-free for the manager. iOS Guided Access remains a *complement* — IT can still configure it for an extra layer.
**Consequences:**
- Deployment prerequisite: the iPad must have a device passcode set in iOS Settings → Face ID & Passcode (or Touch ID & Passcode on older models). Without one, `ManagerGate.require` returns `.notConfigured` and the UI tells the manager to ask IT.
- New `Sources/ManagerGate.swift`. `NSFaceIDUsageDescription` added to `Info.plist` via `project.yml`.
- `FormView` hides the system back button (`.navigationBarBackButtonHidden(true)`) and surfaces an "Exit" toolbar button that runs the gate before dismissing.
- `LibraryView`'s Disconnect Dropbox tap runs the gate before showing the confirmation dialog.
- Edit / Create / Delete template actions are NOT gated for v1 — they're only reachable *after* the gate has already let the manager into the Library. Re-gating each action would be friction without changing the security boundary.

### 2026-05-11 — Bundled templates pinned to sentinel UUIDs; synced JSON can't impersonate
**Decision:** `FormTemplate.BundledID` holds a stable UUID per bundled template (`generalSafetyV1` = `00000000-0000-4000-8000-000000000001`, etc.). The bundled template instances pass these IDs explicitly to `init`. `TemplateStore.refresh()` rejects any synced JSON whose `id` is in `BundledID.all` and logs the impersonation attempt.
**Why:** Two bugs from the review chain. (1) `static let generalSafetyV1 = FormTemplate(...)` with the init default `id: UUID = UUID()` resolved to a fresh UUID per process — stable within a launch, different across launches. Latent foot-gun for SwiftUI NavigationStack state restoration and `TemplateStore.save`'s `firstIndex(where: { $0.id == ... })` lookup. (2) Without the impersonation check, anyone with Dropbox write access could upload a `{some-uuid}.json` claiming `editable: false` and the id of a bundled template; every iPad on the account would then show two "General Safety Rules" entries or, worse, surface a malicious doppelgänger under that name. The cheapest mitigation closes both.
**Consequences:** A new bundled template requires (a) adding a sentinel UUID to `BundledID.all`, (b) passing it as `id:` in the template's `static let` definition, (c) optionally documenting it in `BundledID`'s enum case list. Bundled IDs are now load-bearing — never change a sentinel value, only add new ones.

### 2026-05-11 — `FormRenderer.render` is a throwing API; v1 contract is single-page
**Decision:** `render(template:, printName:, signature:, signedAt:) throws -> Data`. Throws `RenderError.contentTooLong` when content would push the signature block past `pageSize.height - margin - signatureBlockHeight` (150pt reserved). `FormView.submit` surfaces the error as "This template is too long to fit on one page" and refuses to upload.
**Why:** With the v2 freeform template editor allowing arbitrary-length bodies, the previous "always render, even if signature falls off-page" behavior produced "signed and saved" PDFs whose signature lived at y ≈ 3000 — off-page, lost — with the manager getting a green-check success interstitial. /gsd-code-review flagged this as CR-04 ship-blocker level. Considered: (A) fail loud + tell manager to shorten; (B) real multi-page pagination. (A) wins for now because it's a one-day fix and we don't have a real form that overruns one page yet. (B) is in `to-do.md` for when a real template needs it.
**Consequences:** Every call site of `render` is now `try`. `FormView.PendingUpload` construction is wrapped in a do-catch that surfaces render errors as `.failure(message:)` before touching Dropbox. The `RenderError` enum is the contract — future renderer modes (multi-page, image-stamp variants) extend this enum rather than failing silently.

### 2026-05-11 — `SwiftPDFTests` target via xcodegen
**Decision:** Added `SwiftPDFTests` as a `bundle.unit-test` target in `project.yml`. Sources live in `Tests/` (sibling to `Sources/`). Scheme runs both build and test actions. Three suites: `FilenameSanitizationTests` (10 cases), `FormTemplateCodableTests` (4), `FormRendererTests` (4) — 18 total, all green.
**Why:** The `/gsd-code-review` cross-cutting finding flagged "no tests at all" against a business-critical fill→sign→render→upload pipeline. Rather than add a fourth set of integration tests, scope the test target to deterministic-output units: filename sanitization edge cases, Codable round-trip, renderer overflow + degenerate-signature safety. `TemplateStoreTests` was deferred because it requires extracting a `DropboxServiceProtocol` (current `DropboxService` is `final class`).
**Consequences:** `xcodebuild ... test` is the canonical entry point. New tests go in `Tests/{Feature}Tests.swift` using XCTest. Test target uses `GENERATE_INFOPLIST_FILE: YES` (no own plist file); the SwiftPDF main target keeps the existing `SwiftPDF-Info.plist` via xcodegen's `info:` block. **Insertion order matters in `project.yml`**: any new target must go AFTER the existing target's full block (including `info:`), or YAML reparenting will silently move the `info:` block under the new target.

### 2026-05-11 — Filename sanitization via shared `String.sanitizedForFilename` + `truncatedToUTF8Bytes`
**Decision:** Both halves of the signed-PDF filename (`template.name` and signer name) go through `String.sanitizedForFilename()`, then the joined stem is truncated to ≤240 UTF-8 bytes before appending `.pdf`. Sanitizer strips the Dropbox-disallowed set (`/ \ < > : " | ? *`), C0 control characters, leading dots, and surrounding whitespace/dashes; falls back to a literal placeholder on empty. `DateFormatter` in both `FormView` (filename) and `FormRenderer` (in-PDF "Date" field) is pinned to `en_US_POSIX` + Gregorian + America/Chicago.
**Why:** Three reviewers independently flagged the previous sanitization as too narrow. Prior code stripped only `/` and `:` from the signer name and didn't sanitize `template.name` at all — a template named `Onboarding/Customer` produced `/Signed/Onboarding/Customer - …pdf` (subfolder under the app folder; couldn't escape via Dropbox's App-folder scope but polluted the tree). Locale drift on `DateFormatter` was a separate concern: a Buddhist-locale iPad would write `2569` years.
**Consequences:** `Sources/StringSanitization.swift` holds both helpers; covered by 10 unit tests in `FilenameSanitizationTests`. UTF-8 byte budget (not character count) is what Dropbox enforces. Leaving 15 bytes of headroom from the 255-byte cap accommodates Dropbox's `(1).pdf` autorename suffix.
