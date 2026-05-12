import SwiftUI

struct LibraryView: View {
    @Environment(DropboxService.self) private var dropbox
    @Environment(TemplateStore.self) private var store

    @State private var showDisconnectConfirm = false
    @State private var showNewTemplate = false
    @State private var editing: FormTemplate?
    @State private var deleting: FormTemplate?
    @State private var deleteError: String?
    @State private var gateError: String?
    @State private var inFlightDeletes: Set<UUID> = []

    var body: some View {
        listView
            .listStyle(.insetGrouped)
            .navigationTitle("SwiftPDF")
            .navigationDestination(for: FormTemplate.self) { template in
                FormView(template: template)
            }
            .toolbar { toolbarMenu }
            .sheet(isPresented: $showNewTemplate) {
                TemplateEditorView(template: nil)
            }
            .sheet(item: $editing) { template in
                TemplateEditorView(template: template)
            }
            .modifier(LibraryDialogs(
                showDisconnectConfirm: $showDisconnectConfirm,
                deleting: $deleting,
                deleteError: $deleteError,
                gateError: $gateError,
                onDisconnect: { dropbox.unauthorize() },
                onConfirmDelete: { template in
                    Task { await performDelete(template) }
                }
            ))
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
    }

    private var listView: some View {
        List {
            Section {
                ForEach(store.templates) { template in
                    NavigationLink(value: template) {
                        TemplateRow(template: template)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        rowSwipeActions(for: template)
                    }
                }
            } header: {
                Text("Templates")
            } footer: {
                footer
            }

            Section {
                Button {
                    showNewTemplate = true
                } label: {
                    Label("New Template", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.kwikshipOrange)
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(role: .destructive) {
                    Task { await tryDisconnect() }
                } label: {
                    Label("Disconnect Dropbox", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More options")
            }
        }
    }

    /// Disconnect Dropbox affects every iPad on this account and is exactly
    /// the kind of action a non-trusted customer should never trigger. Gate
    /// it behind a manager re-auth before even showing the confirm dialog.
    private func tryDisconnect() async {
        switch await ManagerGate.require(reason: "Disconnect Dropbox") {
        case .authenticated:
            showDisconnectConfirm = true
        case .userCancelled:
            break
        case .notConfigured:
            gateError = "This iPad has no passcode or biometric configured. Ask IT to set one in iOS Settings → Face ID & Passcode before continuing."
        case .failed(let message):
            gateError = message
        }
    }

    @ViewBuilder
    private func rowSwipeActions(for template: FormTemplate) -> some View {
        if template.editable {
            Button(role: .destructive) {
                deleting = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
            // Disable the swipe action for a row whose delete is mid-flight so
            // a second tap can't fire a duplicate `deleteV2` call (harmless but
            // produces a misleading "couldn't delete" alert for a delete that
            // already succeeded).
            .disabled(inFlightDeletes.contains(template.id))
            // Edit is only safe for freeform content — the editor doesn't know
            // how to round-trip `.structured(...)` and would flatten it on save.
            if case .freeform = template.content {
                Button {
                    editing = template
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Color.kwikshipOrange)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch store.loadState {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Syncing templates…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label("Couldn't sync templates: \(message)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color(.systemRed))
        }
    }

    private func performDelete(_ template: FormTemplate) async {
        inFlightDeletes.insert(template.id)
        defer { inFlightDeletes.remove(template.id) }
        do {
            try await store.delete(template)
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

/// Bundles the disconnect/delete confirmations + the delete-error alert behind
/// a single `.modifier(...)` so `LibraryView.body` doesn't blow past the Swift
/// type-checker's complexity budget.
private struct LibraryDialogs: ViewModifier {
    @Binding var showDisconnectConfirm: Bool
    @Binding var deleting: FormTemplate?
    @Binding var deleteError: String?
    @Binding var gateError: String?
    let onDisconnect: () -> Void
    let onConfirmDelete: (FormTemplate) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Disconnect from Dropbox?",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive, action: onDisconnect)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to reconnect on this iPad before you can upload signed forms again.")
            }
            .confirmationDialog(
                deleting.map { "Delete \"\($0.name)\"?" } ?? "Delete template?",
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleting
            ) { template in
                Button("Delete", role: .destructive) { onConfirmDelete(template) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the template from Dropbox on every iPad signed in to this account. Forms already signed and uploaded aren't affected.")
            }
            .alert(
                "Couldn't delete template",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .alert(
                "Manager authentication required",
                isPresented: Binding(
                    get: { gateError != nil },
                    set: { if !$0 { gateError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(gateError ?? "")
            }
    }
}

private struct TemplateRow: View {
    let template: FormTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(template.name)
                    .font(.body.weight(.semibold))
                if !template.editable {
                    Text("BUILT-IN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color(.tertiarySystemFill))
                        )
                }
            }
            Text("Effective \(template.header.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
