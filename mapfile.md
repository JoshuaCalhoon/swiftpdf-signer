# Codebase map

## File tree

```
swiftpdf/
├── .gitignore                       # references/, Resources/*.pdf, .xcodeproj/, SwiftPDF-Info.plist,
│                                    #   Configuration/Local.xcconfig, secrets, REVIEW/SECURITY/CLAUDE-REVIEW/
│                                    #   REMEDIATION-PLAN .md, .gstack/
├── project-memory.md                # stable project facts (durable gotchas, conventions)
├── architecture.md                  # append-only decision log
├── mapfile.md                       # this file
├── to-do.md                         # active + deferred work
├── design.md                        # design system (KwikShip orange #FF5100)
├── nextchat.md                      # cross-session handoff (rewritten by checkpoint)
├── project.yml                      # XcodeGen spec — SwiftPDF + SwiftPDFTests targets,
│                                    #   info.properties with URL scheme + NSFaceIDUsageDescription
├── Configuration/
│   ├── Local.xcconfig.example       # committed template (DROPBOX_APP_KEY + DEVELOPMENT_TEAM placeholders)
│   └── Local.xcconfig               # gitignored — real values
├── Sources/                         # Swift source — app target
│   ├── SwiftPDFApp.swift            # @main, injects DropboxService + TemplateStore, routes onOpenURL → handleRedirect
│   ├── ContentView.swift            # root view — gates on dropbox.authState; either ConnectDropboxView or LibraryView
│   ├── ConnectDropboxView.swift     # first-launch auth gate; orange "Connect Dropbox" CTA; iterative topPresented helper
│   ├── LibraryView.swift            # template list (bundled + synced) + "+ New" + swipe edit/delete;
│   │                                #   ellipsis menu owns Disconnect Dropbox; ManagerGate guards Disconnect;
│   │                                #   inFlightDeletes Set<UUID> guard; skip-count footer
│   ├── TemplateEditorView.swift     # create/edit form (Title + freeform Body); header locked to KS standard;
│   │                                #   Discard-changes confirm; structured-content assertion in prefill
│   ├── TemplateStore.swift          # @Observable @MainActor — bundled + Dropbox-synced JSON; parallel TaskGroup
│   │                                #   downloads; rejects bundled-id impersonation; os.Logger w/ privacy hints;
│   │                                #   lastRefreshSkipCount surfaced to UI
│   ├── FormView.swift               # signing UI — preview + Print Name + 200pt SignatureCanvas + Done;
│   │                                #   success interstitial w/ autorename note; biometric Exit toolbar;
│   │                                #   .scrollIndicators(.visible) on preview; gateError alert
│   ├── FormTemplate.swift           # Codable Hashable model with content: FormContent (.structured or .freeform);
│   │                                #   BundledID sentinel UUIDs; bundled .generalSafetyV1 uses BundledID.generalSafetyV1
│   ├── FormRenderer.swift           # UIGraphicsPDFRenderer pipeline: throws RenderError.contentTooLong on overflow;
│   │                                #   reserves 150pt signatureBlockHeight; rejects degenerate signatures
│   ├── SignatureCanvas.swift        # UIViewRepresentable PKCanvasView wrapper; symmetric updateUIView;
│   │                                #   named strokeWidth constant
│   ├── DropboxService.swift         # @Observable @MainActor — auth + upload + template list/download/save/delete;
│   │                                #   handleRedirect validates URL scheme; explicit MainActor hop on callback;
│   │                                #   authorize() guards on empty app key (release-build "App is misconfigured")
│   ├── DropboxConfig.swift          # App Key from Info.plist; /Signed + /Templates folders;
│   │                                #   DEBUG-only fatalError, release returns "" for graceful misconfig path
│   ├── ManagerGate.swift            # @MainActor LAContext.evaluatePolicy(.deviceOwnerAuthentication) wrapper;
│   │                                #   Outcome enum: authenticated | userCancelled | notConfigured | failed
│   ├── StringSanitization.swift     # String.sanitizedForFilename + truncatedToUTF8Bytes; covered by tests
│   └── DesignTokens.swift           # Color.kwikshipOrange (#FF5100) + warm-dark neutrals
├── Tests/                           # Swift source — unit test target (SwiftPDFTests)
│   ├── FilenameSanitizationTests.swift  # 10 cases — sanitize set, control chars, path traversal, fallback,
│   │                                    #   unicode, UTF-8 byte truncation
│   ├── FormTemplateCodableTests.swift   # 4 cases — freeform round-trip, structured round-trip, editable default,
│   │                                    #   BundledID sentinel stability
│   └── FormRendererTests.swift          # 4 cases — short freeform PDF parseable, overflow throws, empty signature
│                                        #   safe, degenerate signature safe
├── Resources/                       # gitignored
│   └── General Safety.pdf           # remnant from the Word-doc pipeline; no longer bundled
├── references/                      # gitignored — Word source docs
│   └── General Safety_*.docx
├── SwiftPDF-Info.plist              # gitignored, regenerated by xcodegen
└── SwiftPDF.xcodeproj/              # gitignored, regenerated by xcodegen
```

## Modules

### `Configuration/`
xcconfig-based credential + signing storage. `Local.xcconfig` (gitignored) defines `DROPBOX_APP_KEY` (wired into `Info.plist` via `$(DROPBOX_APP_KEY)` substitution) and `DEVELOPMENT_TEAM` (Apple Developer Team ID for signing physical-iPad builds). Clone workflow: copy `.example` → real file, fill in, `xcodegen generate`. App reads the Dropbox key at runtime via `Bundle.main.infoDictionary["DropboxAppKey"]`; Xcode reads the team ID directly at build time.

### `Sources/`
Single iOS app target. Six layers (flat in `Sources/`, no subdirectories):
- **Entry/UI**: `SwiftPDFApp` (composition root) → `ContentView` → `LibraryView` → `FormView` (composes preview + signing panel) + `SignatureCanvas` (PencilKit wrapper). `TemplateEditorView` is presented as a sheet from `LibraryView`.
- **Model**: `FormTemplate` (Codable Hashable, BundledID sentinels) + `FormContent` enum + `FormRenderer` (throws RenderError on overflow; reserves signatureBlockHeight).
- **Services**: `TemplateStore` (@Observable; bundled + Dropbox-synced JSON, parallel downloads, impersonation reject) + `DropboxService` (OAuth + upload + template CRUD, scheme-validated redirect) + `DropboxConfig` (key/folders/scopes; preview-safe; DEBUG-only fatal).
- **Security**: `ManagerGate` (biometric/passcode wrapper) + the URL-scheme validation in `DropboxService.handleRedirect`.
- **Sanitization**: `StringSanitization` (filename helpers used by `FormView`).
- **Theme**: `DesignTokens` — Color extensions for brand palette.

### `Tests/`
Unit test target `SwiftPDFTests`. 18 tests across 3 files. Coverage is deliberately scoped to deterministic-output units: filename sanitization, Codable round-trip, renderer overflow + degenerate-signature safety. Run via `xcodebuild ... test` (the SwiftPDF scheme's test action drives `SwiftPDFTests`).

### `Resources/`
Bundled at build time via xcodegen's optional `resources` directive. Currently unused now that the renderer generates PDFs dynamically. Kept on disk as `General Safety.pdf` for reference. Gitignored.

### `references/`
Source materials (Word docs). Gitignored. Not bundled. Original source of the General Safety rules content that's now hardcoded in `FormTemplate.generalSafetyV1`.

## Cross-references

### Entry & root routing
- `SwiftPDFApp` → instantiates `DropboxService` + `TemplateStore` via `@State`, injects both via `.environment(...)`, routes `onOpenURL` → `dropbox.handleRedirect(url)`.
- `ContentView` → switches on `dropbox.authState`. Shows `ConnectDropboxView` for `.notAuthorized / .authorizing / .authFailed`. Shows `NavigationStack { LibraryView() }` when `.authorized`.
- `ConnectDropboxView` → reads `@Environment(DropboxService.self)`, locates topmost `UIViewController` (iterative walk via `topPresented`), calls `dropbox.authorize(from:)`.

### Library + editor
- `LibraryView` → reads `@Environment(TemplateStore.self)`, lists `store.templates` (bundled first, then synced alphabetically). `NavigationLink(value: template)` → `FormView`. Toolbar ellipsis menu calls `tryDisconnect()` → `ManagerGate.require("Disconnect Dropbox")` → on `.authenticated`, shows confirm dialog; on `.notConfigured`, surfaces "ask IT" alert via `gateError`. Edit swipe action gated on `template.editable AND case .freeform = template.content`. Delete swipe action disabled while row's id is in `inFlightDeletes: Set<UUID>`. Footer surfaces `store.lastRefreshSkipCount` when nonzero.
- `TemplateEditorView` → reads `@Environment(TemplateStore.self)`, captures `title` + `bodyText` against `initialTitle`/`initialBody` snapshot for `hasUnsavedChanges`. Cancel with unsaved changes → "Discard?" confirm. `prefill()` asserts on `.structured` content (caller must gate). Save builds a `FormTemplate(content: .freeform(body:))` and calls `store.save()`.

### Template sync
- `TemplateStore.refresh()` → `dropbox.listTemplates()` → for each ref, parallel `dropbox.downloadTemplate(at:)` + decode via `withTaskGroup`. Rejects `FormTemplate.BundledID.all` matches with a `.public`-tagged warning log. Merges remaining decoded templates with bundled (`[generalSafetyV1]`) and sorts the synced subset case-insensitively. `os.Logger` with `.private` error bodies. `loadState` + `lastRefreshSkipCount` surface to Library footer.
- `TemplateStore.save(_:)` → encode as `{uuid}.json`, upload with `mode:.overwrite`. Reconstructs the local `templates` array from scratch (bundled IDs filtered, current template replaced/appended, user templates sorted) — no `dropFirst(bundled.count)` invariant.
- `TemplateStore.delete(_:)` → silently no-op on bundled (`editable: false`); otherwise `dropbox.deleteTemplate` + remove from local list.

### Signing flow
- `FormView` → reads `@Environment(DropboxService.self)`, holds `printName: String` + `signature: PKDrawing` + `gateError: String?` state. `.navigationBarBackButtonHidden(true)`; toolbar "Exit" runs `tryExit()` → `ManagerGate.require("Return to template library")` → dismiss on success. On Done renders via `FormRenderer.render(... throws)` and uploads via `DropboxService`. Re-entry guard (`guard !isUploading else { return }`) plus `defer { isUploading = false }`. Caches the rendered `PendingUpload` between attempts so Retry doesn't re-render; `.onChange` invalidation is gated on `!isUploading` so stylus drift mid-upload doesn't corrupt the cache. Compares returned `pathDisplay` to requested path to detect Dropbox autorename, surfaces note in success panel. `catch DropboxService.ServiceError.notAuthorized` clears local status and lets ContentView own the re-auth UI.
- `FormView.canSubmit` → checks `!printName.isEmpty && hasUsableSignature && !isUploading`. `hasUsableSignature` requires `signature.bounds.width > 0.5 && height > 0.5` (rejects degenerate strokes at the UI layer; renderer has the same guard).
- `FormView.makeFilename` → `template.name.sanitizedForFilename()` + " - " + `signer.sanitizedForFilename()` + " [yyyy-MM-dd]", truncated to ≤240 UTF-8 bytes, then `.pdf` appended. Static `DateFormatter` pinned to en_US_POSIX + Gregorian + America/Chicago.
- `FormRenderer.render(... throws)` → draws into `UIGraphicsPDFRenderer` context using `NSAttributedString` + `PKDrawing.image(from:scale:)`. Tracks `y` against `pageSize.height - margin - signatureBlockHeight`; throws `RenderError.contentTooLong` if overflow. `drawSignature` requires `width AND height > 0.5`; image scale is `signatureRenderScale` (3.0). DateFormatter also pinned to en_US_POSIX + Gregorian + America/Chicago.

### Auth & security
- `DropboxService.handleRedirect(url:)` → validates `url.scheme == "db-\(DropboxConfig.appKey)"` before calling `DropboxClientsManager.handleRedirectURL`. SDK callback wrapped in `Task { @MainActor in ... }`. `.cancel` → `.notAuthorized`; `.none` → no-op (leaves state untouched).
- `DropboxService.authorize(from:)` → guards on `!DropboxConfig.appKey.isEmpty`; release-build misconfig surfaces `.authFailed("App is misconfigured")` instead of crashing.
- `DropboxService.upload(_:filename:)` / `listTemplates()` / `downloadTemplate(at:)` / `saveTemplate(_:filename:)` / `deleteTemplate(at:)` → each CallError is generic on the route's error type; shared `isAuthFailure(_:)` catches `.authError` / `.clientError(.oauthError)` → calls `unauthorize()` + rethrows `ServiceError.notAuthorized` so `ContentView` routes back to `ConnectDropboxView`. `listTemplates()` additionally treats `.routeError(.path(.notFound))` as empty.
- `ManagerGate.require(reason:)` → `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)` then `evaluatePolicy(...)`. Returns `Outcome.authenticated | userCancelled | notConfigured | failed(message:)`. Maps `LAError.passcodeNotSet / .biometryNotAvailable / .biometryNotEnrolled` to `.notConfigured` so the UI can show "ask IT to set a passcode".

### Build config
- `DropboxConfig.appKey` → loaded once via `Bundle.main.infoDictionary["DropboxAppKey"]` (substituted from xcconfig at build time). DEBUG: `fatalError` on missing/placeholder. Release: returns `""` and `DropboxService.authorize` surfaces a user-visible error. Preview escape: returns `"PREVIEW_PLACEHOLDER"` when `XCODE_RUNNING_FOR_PREVIEWS == "1"`.
- `Configuration/Local.xcconfig` — build-time entry for `DROPBOX_APP_KEY` and `DEVELOPMENT_TEAM`. Gitignored; `.example` committed as template.

## Entry points

- `Sources/SwiftPDFApp.swift:3` — `@main` — opens `ContentView()` in `WindowGroup`, injects `DropboxService` + `TemplateStore`, routes Dropbox OAuth redirect URLs.
- `Configuration/Local.xcconfig` — build-time entry for Dropbox App Key + Apple Developer Team ID.
- `xcodebuild -project SwiftPDF.xcodeproj -scheme SwiftPDF -destination 'platform=iOS Simulator,id=60226EA0-7C80-458D-BFE9-F7A19F90CAE6' -configuration Debug build` — canonical simulator build invocation. The destination UUID drifts; re-check via `-showdestinations` if it fails.
- `xcodebuild ... test` — runs the SwiftPDFTests target (18 tests).
