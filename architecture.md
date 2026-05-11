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
