import SwiftUI
import PencilKit

struct FormView: View {
    let template: FormTemplate

    @Environment(SyncCoordinator.self) private var sync
    @Environment(TemplateStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var printName = ""
    @State private var signature = PKDrawing()
    @State private var isUploading = false
    @State private var status: Status = .idle
    @State private var pendingUpload: PendingUpload?
    @State private var gateError: String?
    @State private var showingDemoPreview = false

    enum Status: Equatable {
        case idle
        /// `wasAutorenamed` is true when the provider had to rename the
        /// upload to avoid a sibling collision (Dropbox's `autorename: true`,
        /// or a future provider's equivalent). The success panel surfaces
        /// this so the manager knows to check for a sibling file before
        /// filing.
        case success(path: String, wasAutorenamed: Bool)
        /// Demo signing succeeded. The PDF was rendered locally (so any
        /// signature / renderer failure still surfaces as `.failure`) but
        /// nothing was uploaded. `filename` is the same deterministic name
        /// production would have used, surfaced so the reviewer can confirm
        /// the `{Form} - {Signer} [{Date}].pdf` convention. `pdfData`
        /// carries the rendered bytes so the "View signed PDF" affordance
        /// can present them in-app without re-rendering.
        case demoSuccess(filename: String, pdfData: Data)
        case failure(message: String)
    }

    /// Rendered PDF cached between attempts so a Retry doesn't re-render
    /// or shift the signed-at date if the user pauses between tries.
    struct PendingUpload {
        let data: Data
        let filename: String
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            bottomPanel
        }
        .animation(.easeOut(duration: 0.25), value: isSuccessShowing)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        // Hide the system back button so a customer can't navigate back to
        // the Library and disconnect Dropbox / edit templates while they hold
        // the iPad. The toolbar's "Exit" button replaces it, gated by
        // ManagerGate (FaceID / TouchID / device passcode).
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Exit") { Task { await tryExit() } }
                    .disabled(isUploading)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if sync.isDemo {
                DemoBanner(onConnect: exitDemo)
            }
        }
        .alert("Couldn't return to library", isPresented: Binding(
            get: { gateError != nil },
            set: { if !$0 { gateError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gateError ?? "")
        }
        .onChange(of: printName) { _, _ in invalidateAfterEdit() }
        .onChange(of: signature) { _, _ in invalidateAfterEdit() }
        // The customer signing flow begins here. Drop any cached manager auth
        // so a curious customer can't ride the manager's grace window to tap
        // Exit and reach the library.
        .onAppear { ManagerGate.invalidate() }
        // Hide signer name + signature from the App Switcher snapshot iOS
        // captures on scene transitions. See PrivacyShield.
        .privacyShield()
    }

    /// Demo → Connect transition from the persistent banner. Mirrors the
    /// same handler in LibraryView — endDemoSession flips ContentView to
    /// the Connect screen, and resetForDemoExit ensures a future demo
    /// re-entry re-seeds the sample instead of inheriting this session's
    /// edits.
    private func exitDemo() {
        sync.endDemoSession()
        store.resetForDemoExit()
    }

    /// Returns to the Library after a manager re-authenticates. Customer
    /// taps Exit → FaceID / passcode prompt → success pops, failure stays.
    private func tryExit() async {
        switch await ManagerGate.require(reason: "Return to template library") {
        case .authenticated:
            dismiss()
        case .userCancelled:
            break
        case .notConfigured:
            gateError = ManagerGate.noPasscodeMessage
        case .failed(let message):
            gateError = message
        }
    }

    private var preview: some View {
        ScrollView {
            TemplateBody(template: template)
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
        }
        // Always-on scroll indicator so the user can tell at a glance whether
        // the body extends past the visible area. SwiftUI's default fades the
        // indicator after a moment, which reads as "all the content is here."
        .scrollIndicators(.visible)
    }

    private var isSuccessShowing: Bool {
        switch status {
        case .success, .demoSuccess: return true
        case .idle, .failure: return false
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        switch status {
        case .success(let path, let wasAutorenamed):
            successPanel(path: path, wasAutorenamed: wasAutorenamed)
                .transition(.opacity)
        case .demoSuccess(let filename, let pdfData):
            demoSuccessPanel(filename: filename, pdfData: pdfData)
                .transition(.opacity)
        case .idle, .failure:
            signingPanel
                .transition(.opacity)
        }
    }

    /// Demo counterpart to `successPanel`. Renders the same checkmark hero
    /// and filename so the reviewer sees the deterministic naming format,
    /// but replaces the upload path with a "demo: not uploaded" notice and
    /// drops the autorename warning (which can't apply locally). Adds a
    /// "View signed PDF" affordance so the reviewer can validate the
    /// rendering pipeline end-to-end without connecting a cloud provider.
    private func demoSuccessPanel(filename: String, pdfData: Data) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(settings.brandColor)
            Text("Signed (Demo)")
                .font(.title2.bold())
            Text(filename)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Label("Demo mode: nothing was uploaded. Connect a cloud provider to enable real uploads.", systemImage: "info.circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                showingDemoPreview = true
            } label: {
                Label("View signed PDF", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(settings.brandColor)
            .controlSize(.large)
            Button(action: signAnother) {
                Text("Sign Another")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.brandColor)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingDemoPreview) {
            NavigationStack {
                PDFViewerView(data: pdfData)
                    .navigationTitle(filename)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingDemoPreview = false }
                        }
                    }
            }
        }
    }

    private func successPanel(path: String, wasAutorenamed: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(settings.brandColor)
            Text("Signed and Saved")
                .font(.title2.bold())
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if wasAutorenamed {
                Label("Auto-renamed to avoid a duplicate. A sibling file may already exist.", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button(action: signAnother) {
                Text("Sign Another")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.brandColor)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private var signingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Print Name", text: $printName)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Signature")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { signature = PKDrawing() }
                        .font(.footnote)
                        .disabled(signature.strokes.isEmpty)
                }
                SignatureCanvas(drawing: $signature)
                    .frame(height: 200)
                    .background(Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button(action: { Task { await submit() } }) {
                Group {
                    if isUploading {
                        ProgressView().controlSize(.regular)
                    } else if pendingUpload != nil {
                        Text("Retry Upload")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Done: Save & Upload")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.brandColor)
            .controlSize(.large)
            .disabled(!canSubmit)

            statusBanner
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var statusBanner: some View {
        if case .failure(let message) = status {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color(.systemRed))
                // Surfaced whenever the upload has failed. Mandatory when
                // `pendingUpload` is pinned (the cache survives canvas edits to
                // prevent a stylus-tap race producing two near-duplicate
                // signed PDFs), and harmless in the render-failure case too.
                Button("Start Over", action: startOver)
                    .font(.footnote)
                    .buttonStyle(.bordered)
            }
        }
        // .success is rendered by `successPanel` — the bottom panel swaps wholesale.
        // .idle renders nothing.
    }

    private var canSubmit: Bool {
        // Whitespace-trim guards a name that's only spaces. The post-sanitize
        // check guards a name composed entirely of filename-disallowed glyphs
        // (slashes, control chars, etc.) — without it, two such signers on
        // the same date collide on the "Unknown" fallback filename, and the
        // manager ends up with `Template - Unknown [date].pdf` files that
        // defeat the signer-identifies-the-file purpose of the naming scheme.
        // (audit HI-03 / Dx-2)
        !printName.trimmingCharacters(in: .whitespaces).isEmpty
            && !printName.sanitizedForFilename(fallback: "").isEmpty
            && hasUsableSignature
            && !isUploading
    }

    /// Rejects empty PKDrawings and degenerate strokes (a single tap, a
    /// strictly-horizontal swipe, etc.). PencilKit can return a zero-dimension
    /// `bounds` for those, and `FormRenderer.drawSignature` would silently
    /// drop them — surface "Done" disabled instead so the customer realizes
    /// their stroke didn't register.
    private var hasUsableSignature: Bool {
        guard !signature.strokes.isEmpty else { return false }
        let b = signature.bounds
        return b.width > 0.5 && b.height > 0.5
    }

    private func submit() async {
        // Belt + suspenders against a fast double-tap: @MainActor serializes
        // the flag write but the SwiftUI Button can still fire two `Task`s
        // back-to-back before `isUploading = true` lands. Without this guard
        // both would proceed and Dropbox's `autorename: true` would produce
        // two near-duplicate files.
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        // Demo session: render the PDF (so signature / renderer issues still
        // surface as `.failure`) but skip the upload entirely. The rendered
        // bytes ride into `.demoSuccess` so the success panel's "View signed
        // PDF" button can present them in-app — letting a reviewer (or any
        // demo user) validate the rendering pipeline end-to-end without
        // connecting a cloud provider. No `pendingUpload` cache needed —
        // there's no upload to retry.
        if sync.isDemo {
            let renderer = FormRenderer(
                brandColor: settings.brandUIColor,
                companyLogo: settings.companyLogo
            )
            let now = Date()
            do {
                let pdfData = try renderer.render(
                    template: template,
                    printName: printName,
                    signature: signature,
                    signedAt: now
                )
                status = .demoSuccess(
                    filename: makeFilename(for: printName, on: now),
                    pdfData: pdfData
                )
            } catch {
                status = .failure(message: error.localizedDescription)
            }
            return
        }

        let upload: PendingUpload
        if let existing = pendingUpload {
            upload = existing
        } else {
            let renderer = FormRenderer(
                brandColor: settings.brandUIColor,
                companyLogo: settings.companyLogo
            )
            let now = Date()
            do {
                let pdfData = try renderer.render(
                    template: template,
                    printName: printName,
                    signature: signature,
                    signedAt: now
                )
                upload = PendingUpload(
                    data: pdfData,
                    filename: makeFilename(for: printName, on: now)
                )
                pendingUpload = upload
            } catch {
                // Renderer-side failure (currently only `RenderError.contentTooLong`)
                // — surface and bail before touching Dropbox.
                status = .failure(message: error.localizedDescription)
                return
            }
        }

        do {
            let result = try await sync.uploadSigned(upload.data, filename: upload.filename)
            // The provider knows its own normalization rules (Dropbox does
            // case-insensitive NFC matching; future providers differ), so
            // the autorename signal arrives pre-computed via UploadResult.
            status = .success(path: result.path, wasAutorenamed: result.wasAutorenamed)
            pendingUpload = nil
            // Inputs are left filled until the user taps "Sign Another" — the
            // success panel owns the reset so the manager has a clear hand-back
            // moment instead of a form that snaps back to blank.
        } catch DropboxSyncProvider.ServiceError.notAuthorized {
            // ContentView owns the re-auth UI by switching on sync.authState.
            // Clear our local status so the failure banner doesn't double-display
            // alongside the connect screen.
            status = .idle
            pendingUpload = nil
        } catch {
            status = .failure(message: error.localizedDescription)
        }
    }

    private func signAnother() {
        status = .idle
        printName = ""
        signature = PKDrawing()
    }

    /// Failure-banner escape hatch. Customer hits this when they want to
    /// re-sign from scratch instead of retrying the cached upload — clears
    /// every field and drops the pinned cache so the next submit re-renders.
    private func startOver() {
        pendingUpload = nil
        status = .idle
        printName = ""
        signature = PKDrawing()
    }

    /// Resets transient status when inputs change *before* a render has
    /// happened. Once `pendingUpload` is set (i.e., we've already rendered
    /// once), the cache is pinned — a stylus tap on the canvas or a keystroke
    /// in the name field is a no-op here, so a Retry path re-uploads the
    /// SAME bytes/filename rather than a freshly-rendered PDF with a drifted
    /// `signedAt`. The customer clears the cache explicitly via the Start
    /// Over button on the failure banner.
    ///
    /// Skipped while `isUploading` for the same reason: a stray stylus tap
    /// mid-upload (which fires `onChange(of: signature)`) must not perturb
    /// the in-flight render.
    private func invalidateAfterEdit() {
        guard !isUploading else { return }
        guard pendingUpload == nil else { return }
        if status != .idle {
            status = .idle
        }
    }

    private func makeFilename(for name: String, on date: Date) -> String {
        let dateStr = Self.filenameDateFormatter.string(from: date)
        let safeTemplate = template.name.sanitizedForFilename(fallback: "Template")
        let safeName = name.sanitizedForFilename(fallback: "Unknown")
        let stem = "\(safeTemplate) - \(safeName) [\(dateStr)]"
        // Dropbox enforces a 255-byte name limit. Budget breakdown:
        //   stem        ≤ 240 bytes (truncatedToUTF8Bytes)
        //   ".pdf"      =   4 bytes
        //   subtotal    = 244 bytes
        //   remaining   =  11 bytes for autorename suffixes
        // Autorename ` (N).pdf` costs 8 bytes for ` (1).pdf` and stays under
        // the 11-byte headroom through ` (999).pdf`. Reaching ` (1000).pdf`
        // would require 1000 same-date collisions in one signed folder,
        // which doesn't happen in practice.
        return "\(stem.truncatedToUTF8Bytes(240)).pdf"
    }

    /// `en_US_POSIX` + Gregorian so the year is always Western even if the
    /// device is set to a non-Western locale. Time zone tracks the device's
    /// current zone so the filename date matches the signer's local calendar
    /// day — a manager filing forms at 11pm local time sees today's date, not
    /// tomorrow's UTC date.
    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct TemplateBody: View {
    let template: FormTemplate

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(template.name)
                .font(.largeTitle.bold())
                .foregroundStyle(settings.brandColor)

            headerTable

            switch template.content {
            case .structured(let intro, let rules, let acknowledgment):
                Text(intro)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .frame(width: 24, alignment: .trailing)
                            Text(rule)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider().padding(.vertical, 8)

                Text(acknowledgment)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .freeform(let body):
                Text(body)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerTable: some View {
        HStack(alignment: .top, spacing: 12) {
            if let logo = settings.companyLogo {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                row("Company", template.header.company)
                row("Location", template.header.location)
                row("Department", template.header.department)
                row("Effective Date", template.header.effectiveDate.formatted(date: .long, time: .omitted))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
