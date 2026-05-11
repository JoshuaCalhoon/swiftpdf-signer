import SwiftUI

/// Create-or-edit form for a `FormTemplate`. Passed `nil` to create; passed an
/// existing template to edit. Header is locked to the KwikShip standard — the
/// editor only exposes title + freeform body.
struct TemplateEditorView: View {
    let template: FormTemplate?

    @Environment(TemplateStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var isEditing: Bool { template != nil }
    private var navigationTitle: String { isEditing ? "Edit Template" : "New Template" }

    private var formContent: some View {
        Form {
            Section("Document Title") {
                TextField("e.g. Receiving Dock Acknowledgment", text: $title)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
            }

            Section {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 240)
                    .font(.body)
            } header: {
                Text("Body")
            } footer: {
                Text("This text appears between the header and the signature block on the signed PDF. Use blank lines to separate paragraphs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                lockedHeaderPreview
            } header: {
                Text("Header (locked)")
            } footer: {
                Text("Company, location, and department come from the KwikShip standard. Effective date is set when the template is created.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color(.systemRed))
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "Save" : "Create") {
                            Task { await save() }
                        }
                        .disabled(!canSave || isSaving)
                        .fontWeight(.semibold)
                    }
                }
                .interactiveDismissDisabled(isSaving)
                .onAppear(perform: prefill)
                .overlay { savingOverlay }
        }
    }

    private var lockedHeaderPreview: some View {
        let header = template?.header ?? FormHeader.kwikshipStandard()
        return VStack(alignment: .leading, spacing: 4) {
            row("Company", header.company)
            row("Location", header.location)
            row("Department", header.department)
            row("Effective Date", header.effectiveDate.formatted(date: .long, time: .omitted))
        }
        .font(.caption)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var savingOverlay: some View {
        if isSaving {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView("Saving…")
                    .padding(20)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prefill() {
        guard let template, title.isEmpty, bodyText.isEmpty else { return }
        title = template.name
        if case .freeform(let existingBody) = template.content {
            bodyText = existingBody
        }
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        let toSave: FormTemplate
        if let existing = template {
            toSave = FormTemplate(
                id: existing.id,
                name: trimmedTitle,
                header: existing.header,
                content: .freeform(body: trimmedBody),
                version: existing.version + 1,
                editable: true
            )
        } else {
            toSave = FormTemplate(
                name: trimmedTitle,
                header: .kwikshipStandard(),
                content: .freeform(body: trimmedBody),
                version: 1,
                editable: true
            )
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await store.save(toSave)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
