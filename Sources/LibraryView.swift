import SwiftUI

struct LibraryView: View {
    @Environment(DropboxService.self) private var dropbox
    @Environment(TemplateStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var isManaging = false
    @State private var showDisconnectConfirm = false
    @State private var showNewTemplate = false
    @State private var showSettings = false
    @State private var editing: FormTemplate?
    @State private var deleting: FormTemplate?
    @State private var actionError: String?
    @State private var gateError: String?
    @State private var inFlightActions: Set<UUID> = []

    var body: some View {
        listView
            .listStyle(.insetGrouped)
            .navigationTitle("SwiftPDF Signer")
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .modifier(LibraryDialogs(
                showDisconnectConfirm: $showDisconnectConfirm,
                deleting: $deleting,
                actionError: $actionError,
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
                    if isManaging {
                        ManageRow(
                            template: template,
                            brandColor: settings.brandColor,
                            inFlight: inFlightActions.contains(template.id),
                            onEdit: editAction(for: template),
                            onDuplicate: { Task { await duplicate(template) } },
                            onDelete: { deleting = template }
                        )
                    } else {
                        NavigationLink(value: template) {
                            TemplateRow(template: template)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            rowSwipeActions(for: template)
                        }
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
                        .foregroundStyle(settings.brandColor)
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        // "Manage" exposes Edit / Duplicate / Delete affordances inline on
        // each row. The swipe-actions in normal mode still work, but Manage
        // makes them discoverable for managers who don't know to swipe.
        ToolbarItem(placement: .topBarLeading) {
            Button(isManaging ? "Done" : "Manage") {
                isManaging.toggle()
            }
            .fontWeight(isManaging ? .semibold : .regular)
        }
        // Settings gets its own toolbar button (not buried inside the menu)
        // because it's the primary first-run customization surface — a
        // manager finishing setup needs to find it without exploring.
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await trySettings() }
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings")
            }
        }
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

    /// Edit is only safe for freeform content — the editor doesn't know how to
    /// round-trip `.structured(...)` and would flatten it on save. Returns nil
    /// for structured templates so the Manage row hides the Edit button.
    private func editAction(for template: FormTemplate) -> (() -> Void)? {
        guard case .freeform = template.content else { return nil }
        return { editing = template }
    }

    /// Settings exposes the brand color picker (and future per-install knobs).
    /// Gated by ManagerGate so a non-trusted customer can't reach the sheet
    /// from a shared iPad.
    private func trySettings() async {
        switch await ManagerGate.require(reason: "Open Settings") {
        case .authenticated:
            showSettings = true
        case .userCancelled:
            break
        case .notConfigured:
            gateError = "This iPad has no passcode or biometric configured. Ask IT to set one in iOS Settings → Face ID & Passcode before continuing."
        case .failed(let message):
            gateError = message
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
            .disabled(inFlightActions.contains(template.id))
            if case .freeform = template.content {
                Button {
                    editing = template
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(settings.brandColor)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch store.loadState {
        case .idle:
            EmptyView()
        case .loaded:
            if store.lastRefreshSkipCount > 0 {
                let count = store.lastRefreshSkipCount
                Label("Skipped \(count) template\(count == 1 ? "" : "s") that couldn't be loaded. Check Dropbox for corrupt JSON.", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                EmptyView()
            }
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
        inFlightActions.insert(template.id)
        defer { inFlightActions.remove(template.id) }
        do {
            try await store.delete(template)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Creates a copy of `template` with a fresh UUID and " copy" suffix on
    /// the name. Saving routes through TemplateStore.save → Dropbox upload,
    /// so the new template syncs back through refresh just like any other.
    private func duplicate(_ template: FormTemplate) async {
        inFlightActions.insert(template.id)
        defer { inFlightActions.remove(template.id) }
        let copy = FormTemplate(
            name: "\(template.name) copy",
            header: template.header,
            content: template.content,
            version: 1,
            editable: true
        )
        do {
            try await store.save(copy)
        } catch {
            actionError = "Couldn't duplicate: \(error.localizedDescription)"
        }
    }
}

/// Bundles the disconnect/delete confirmations + the action-error alert behind
/// a single `.modifier(...)` so `LibraryView.body` doesn't blow past the Swift
/// type-checker's complexity budget.
private struct LibraryDialogs: ViewModifier {
    @Binding var showDisconnectConfirm: Bool
    @Binding var deleting: FormTemplate?
    @Binding var actionError: String?
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
                "Action failed",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
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
            Text(template.name)
                .font(.body.weight(.semibold))
            Text("Effective \(template.header.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Row used while the library is in Manage mode — exposes Edit / Duplicate /
/// Delete buttons inline so a manager doesn't have to know about the swipe
/// gesture to discover them. `onEdit == nil` hides the Edit button for
/// structured templates that the editor can't round-trip.
private struct ManageRow: View {
    let template: FormTemplate
    let brandColor: Color
    let inFlight: Bool
    let onEdit: (() -> Void)?
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.body.weight(.semibold))
                Text("Effective \(template.header.effectiveDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(brandColor)
                    .accessibilityLabel("Edit")
                }
                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Duplicate")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete")
            }
            .disabled(inFlight)
        }
        .padding(.vertical, 4)
    }
}
