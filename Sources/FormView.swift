import SwiftUI
import PencilKit

struct FormView: View {
    let template: FormTemplate

    @Environment(DropboxService.self) private var dropbox
    @State private var printName = ""
    @State private var signature = PKDrawing()
    @State private var isUploading = false
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case success(path: String)
        case failure(message: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            signingPanel
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        ScrollView {
            TemplateBody(template: template)
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
        }
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
        switch status {
        case .idle:
            EmptyView()
        case .success(let path):
            Label("Uploaded to \(path)", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Color.kwikshipOrange)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color(.systemRed))
        }
    }

    private var canSubmit: Bool {
        !printName.trimmingCharacters(in: .whitespaces).isEmpty
            && !signature.strokes.isEmpty
            && !isUploading
    }

    private func submit() async {
        isUploading = true
        defer { isUploading = false }

        let renderer = FormRenderer()
        let pdfData = renderer.render(
            template: template,
            printName: printName,
            signature: signature,
            signedAt: Date()
        )
        let filename = makeFilename(for: printName, on: Date())
        do {
            let path = try await dropbox.upload(pdfData, filename: filename)
            status = .success(path: path)
            printName = ""
            signature = PKDrawing()
        } catch {
            status = .failure(message: error.localizedDescription)
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

            Text(template.intro)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(template.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .frame(width: 24, alignment: .trailing)
                        Text(rule)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().padding(.vertical, 8)

            Text(template.acknowledgment)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
