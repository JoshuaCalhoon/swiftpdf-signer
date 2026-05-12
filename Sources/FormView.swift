import SwiftUI
import PencilKit

struct FormView: View {
    let template: FormTemplate

    @Environment(DropboxService.self) private var dropbox
    @Environment(\.dismiss) private var dismiss
    @State private var printName = ""
    @State private var signature = PKDrawing()
    @State private var isUploading = false
    @State private var status: Status = .idle
    @State private var pendingUpload: PendingUpload?
    @State private var gateError: String?

    enum Status: Equatable {
        case idle
        /// `autorenamedFrom` is non-nil when Dropbox's `autorename: true` kicked
        /// in (a duplicate filename existed and the upload landed as
        /// `…(1).pdf`). The success panel surfaces this so the manager knows
        /// to check for a sibling file before filing.
        case success(path: String, autorenamedFrom: String?)
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
            gateError = "This iPad has no passcode or biometric configured. Ask IT to set one in iOS Settings → Face ID & Passcode before continuing."
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
        if case .success = status { return true }
        return false
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if case .success(let path, let renamedFrom) = status {
            successPanel(path: path, autorenamedFrom: renamedFrom)
                .transition(.opacity)
        } else {
            signingPanel
                .transition(.opacity)
        }
    }

    private func successPanel(path: String, autorenamedFrom: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.kwikshipOrange)
            Text("Signed and Saved")
                .font(.title2.bold())
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if autorenamedFrom != nil {
                Label("Dropbox auto-renamed to avoid a duplicate. A sibling file may already exist.", systemImage: "exclamationmark.bubble.fill")
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
            .tint(Color.kwikshipOrange)
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
                        Text("Done — Save & Upload")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.kwikshipOrange)
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
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color(.systemRed))
        }
        // .success is rendered by `successPanel` — the bottom panel swaps wholesale.
        // .idle renders nothing.
    }

    private var canSubmit: Bool {
        !printName.trimmingCharacters(in: .whitespaces).isEmpty
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

        let upload: PendingUpload
        if let existing = pendingUpload {
            upload = existing
        } else {
            let renderer = FormRenderer()
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
            let resolved = try await dropbox.upload(upload.data, filename: upload.filename)
            // Detect Dropbox's autorename: if the returned path's filename
            // differs from what we asked for, mark the success so the manager
            // sees the warning. App-folder scope means `pathDisplay` looks
            // like "/Signed/{filename}".
            let requestedPath = "\(DropboxConfig.uploadFolder)/\(upload.filename)"
            let autorenamedFrom = resolved.caseInsensitiveCompare(requestedPath) == .orderedSame
                ? nil
                : requestedPath
            status = .success(path: resolved, autorenamedFrom: autorenamedFrom)
            pendingUpload = nil
            // Inputs are left filled until the user taps "Sign Another" — the
            // success panel owns the reset so the manager has a clear hand-back
            // moment instead of a form that snaps back to blank.
        } catch DropboxService.ServiceError.notAuthorized {
            // ContentView owns the re-auth UI by switching on dropbox.authState.
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

    /// Drops the cached PDF and any non-idle status whenever inputs change,
    /// so a fresh edit always re-renders from scratch. The success state is
    /// dismissed via `signAnother()`, not by editing — by the time onChange
    /// fires here, `status` is already `.idle`.
    ///
    /// Skipped while `isUploading` so a stray stylus tap mid-upload (which
    /// fires `onChange(of: signature)`) doesn't drop the cached `PendingUpload`
    /// while the server is mid-write. Without this, a transient failure +
    /// retry path could end up uploading a freshly-rendered PDF with a
    /// different `signedAt` than the first attempt.
    private func invalidateAfterEdit() {
        guard !isUploading else { return }
        pendingUpload = nil
        if status != .idle {
            status = .idle
        }
    }

    private func makeFilename(for name: String, on date: Date) -> String {
        let dateStr = Self.filenameDateFormatter.string(from: date)
        let safeTemplate = template.name.sanitizedForFilename(fallback: "Template")
        let safeName = name.sanitizedForFilename(fallback: "Unknown")
        let stem = "\(safeTemplate) - \(safeName) [\(dateStr)]"
        // Dropbox enforces a 255-byte name limit. Leave 15 bytes of headroom
        // for ` (1).pdf` autorename suffixes and the extension itself.
        return "\(stem.truncatedToUTF8Bytes(240)).pdf"
    }

    /// `en_US_POSIX` so the year is always Gregorian even if a customer has
    /// switched the device into a non-Western locale. Pinned to America/Chicago
    /// (KwikShip HQ) so the filename date doesn't shift around when the iPad
    /// happens to be sitting in a different timezone than `signedAt: Date()`.
    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct TemplateBody: View {
    let template: FormTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(template.name)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.kwikshipOrange)

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
        VStack(alignment: .leading, spacing: 4) {
            row("Company", template.header.company)
            row("Location", template.header.location)
            row("Department", template.header.department)
            row("Effective Date", template.header.effectiveDate.formatted(date: .long, time: .omitted))
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
