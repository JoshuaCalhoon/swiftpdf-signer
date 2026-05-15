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

    private var isDemo: Bool {
        dropbox.authState == .demo
    }

    var body: some View {
        listView
            .listStyle(.insetGrouped)
            .navigationTitle("SwiftPDF Signer")
            .navigationDestination(for: FormTemplate.self) { template in
                FormView(template: template)
            }
            .toolbar { toolbarMenu }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isDemo {
                    DemoBanner(onConnect: exitDemo)
                }
            }
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
                onDisconnect: {
                    dropbox.unauthorize()
                    // Wipe the seed flag too — a "start over" disconnect should
                    // re-seed the sample if the next account's templates folder
                    // is empty. Without this, a manager who clears their
                    // Dropbox /Apps/.../Templates folder and reconnects sees an
                    // empty library forever.
                    store.resetSeedFlag()
                },
                onConfirmDelete: { template in
                    Task { await performDelete(template) }
                }
            ))
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
    }

    /// Demo → Connect transition. No confirmation dialog (the demo has no
    /// real data to lose) and no ManagerGate prompt (the bypass is already
    /// active; even without it, demo carries no manager-only state). The
    /// state flip routes ContentView back to ConnectDropboxView, where the
    /// user takes the real OAuth path.
    private func exitDemo() {
        dropbox.endDemoSession()
        store.resetForDemoExit()
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
                            onEdit: { editing = template },
                            onDuplicate: { Task { await duplicate(template) } },
                            onDelete: { deleting = template }
                        )
                    } else {
                        // Customer-facing row: tap to sign, no shortcut to
                        // Edit / Delete. Manager mutation lives behind the
                        // Manage-mode gate so a curious customer can't swipe
                        // to expose template-modification options.
                        NavigationLink(value: template) {
                            TemplateRow(template: template)
                        }
                    }
                }
            } header: {
                // Manage lives inside the section header (not the app
                // toolbar) so it's clearly scoped to "manage these
                // templates" rather than "manage the app." textCase(nil)
                // overrides the inset-grouped uppercase styling for the
                // button label.
                HStack {
                    Text("Templates")
                    Spacer()
                    if !store.templates.isEmpty {
                        Button(isManaging ? "Done" : "Manage") {
                            if isManaging {
                                // Exit is free — leaving Manage mode doesn't
                                // require auth, matches the 30s-grace pattern.
                                isManaging = false
                            } else {
                                Task { await tryEnterManage() }
                            }
                        }
                        .textCase(nil)
                        .fontWeight(isManaging ? .semibold : .regular)
                    }
                }
            } footer: {
                footer
            }

            Section {
                Button {
                    Task { await tryNewTemplate() }
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
                if isDemo {
                    // Demo has nothing to lose — non-destructive item, no
                    // confirmation dialog, no ManagerGate. Tapping ends the
                    // demo session and ContentView routes back to the
                    // ConnectDropboxView where the real OAuth path lives.
                    Button(action: exitDemo) {
                        Label("Connect Dropbox", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                } else {
                    Button(role: .destructive) {
                        Task { await tryDisconnect() }
                    } label: {
                        Label("Disconnect Dropbox", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More options")
            }
        }
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
            gateError = ManagerGate.noPasscodeMessage
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
            gateError = ManagerGate.noPasscodeMessage
        case .failed(let message):
            gateError = message
        }
    }

    /// Manager-only entry to Manage mode. Once in, Edit / Duplicate / Delete
    /// fire without further prompts (30s-grace pattern). Exit Manage mode is
    /// free — leaving doesn't mutate anything.
    private func tryEnterManage() async {
        switch await ManagerGate.require(reason: "Manage templates") {
        case .authenticated:
            isManaging = true
        case .userCancelled:
            break
        case .notConfigured:
            gateError = ManagerGate.noPasscodeMessage
        case .failed(let message):
            gateError = message
        }
    }

    /// New Template lives outside Manage mode (it's its own primary button on
    /// the library list), so it gets its own gate. Once authenticated, the
    /// editor sheet opens for the new-template flow.
    private func tryNewTemplate() async {
        switch await ManagerGate.require(reason: "Create a new template") {
        case .authenticated:
            showNewTemplate = true
        case .userCancelled:
            break
        case .notConfigured:
            gateError = ManagerGate.noPasscodeMessage
        case .failed(let message):
            gateError = message
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
    /// Structured content (today only the bundled sample) is flattened to
    /// freeform on duplicate — otherwise the copy wouldn't be editable in
    /// TemplateEditorView, which only round-trips freeform.
    private func duplicate(_ template: FormTemplate) async {
        inFlightActions.insert(template.id)
        defer { inFlightActions.remove(template.id) }
        let copy = FormTemplate(
            name: "\(template.name) copy",
            header: template.header,
            content: .freeform(body: template.content.flattenedToFreeform()),
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
                Text("You'll need to reconnect on this device before you can upload signed forms again.")
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
                Text("This removes the template from Dropbox on every device signed in to this account. Forms already signed and uploaded aren't affected.")
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
/// gesture to discover them. Edit is available for every editable template;
/// the editor flattens structured content to freeform on prefill so the
/// bundled sample (and any future structured template) is editable too.
private struct ManageRow: View {
    let template: FormTemplate
    let brandColor: Color
    let inFlight: Bool
    let onEdit: () -> Void
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
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(brandColor)
                .accessibilityLabel("Edit")
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
