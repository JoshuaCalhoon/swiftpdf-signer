import SwiftUI
import PencilKit

struct FormView: View {
    let template: FormTemplate

    @Environment(DropboxService.self) private var dropbox
    @State private var printName = ""
    @State private var signature = PKDrawing()
    @State private var isUploading = false
    @State private var status: Status = .idle
    @State private var pendingUpload: PendingUpload?

    enum Status: Equatable {
        case idle
        case success(path: String)
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
        .onChange(of: printName) { _, _ in invalidateAfterEdit() }
        .onChange(of: signature) { _, _ in invalidateAfterEdit() }
    }

    private var preview: some View {
        ScrollView {
            TemplateBody(template: template)
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var isSuccessShowing: Bool {
        if case .success = status { return true }
        return false
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if case .success(let path) = status {
            successPanel(path: path)
                .transition(.opacity)
        } else {
            signingPanel
                .transition(.opacity)
        }
    }

    private func successPanel(path: String) -> some View {
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
            && !signature.strokes.isEmpty
            && !isUploading
    }

    private func submit() async {
        isUploading = true
        defer { isUploading = false }

        let upload: PendingUpload
        if let existing = pendingUpload {
            upload = existing
        } else {
            let renderer = FormRenderer()
            let now = Date()
            let pdfData = renderer.render(
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
        }

        do {
            let path = try await dropbox.upload(upload.data, filename: upload.filename)
            status = .success(path: path)
            pendingUpload = nil
            // Inputs are left filled until the user taps "Sign Another" — the
            // success panel owns the reset so the manager has a clear hand-back
            // moment instead of a form that snaps back to blank.
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
    private func invalidateAfterEdit() {
        pendingUpload = nil
        if status != .idle {
            status = .idle
        }
    }

    private func makeFilename(for name: String, on date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: date)
        let safeName = name
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(template.name) - \(safeName) [\(dateStr)].pdf"
    }
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
