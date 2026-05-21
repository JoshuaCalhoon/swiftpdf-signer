import SwiftUI

/// Sheet-presented Dropbox folder picker. The manager descends through
/// their Dropbox tree, taps "Use this folder" at any level to commit, or
/// "Create folder here" to add a new one. Used twice from `SettingsView`
/// to set `dropboxTemplatesPath` and `dropboxSignedPath` independently.
///
/// Implementation: a NavigationStack with one `FolderBrowserView` per
/// depth. Each `NavigationLink` push fetches the children of that folder.
/// `onSelect` is captured through the stack so any level's "Use this
/// folder" button can commit and dismiss the whole sheet at once.
///
/// (v1.1 Phase B.3)
struct ChooseDropboxFolderView: View {
    /// Sheet title surfaced at the navigation root and in the parent's
    /// presentation context — "Choose Templates Folder" /
    /// "Choose Signed PDFs Folder". The per-level view shows the current
    /// folder name in the nav bar; this title is only seen at the root.
    let title: String

    /// Called with the absolute Dropbox path the manager picked. The root
    /// of the user's Dropbox surfaces as an empty string; callers that
    /// want to display this elsewhere should special-case it ("Your
    /// Dropbox" or similar) rather than rendering the empty string.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FolderBrowserView(
                path: "",
                titleOverride: title,
                onPick: { picked in
                    onSelect(picked)
                    dismiss()
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// One depth-level of the picker. Lists the subfolders at `path`, exposes
/// "Use this folder" and "Create folder here" actions, and pushes a fresh
/// `FolderBrowserView` for each subfolder the manager taps into.
///
/// Doesn't itself dismiss — the wrapping `ChooseDropboxFolderView` owns
/// dismissal so a deep selection collapses the whole stack at once
/// without each level needing to chain pops upward.
private struct FolderBrowserView: View {
    /// Absolute Dropbox path being browsed. `""` is the user's Dropbox
    /// root — the SDK accepts the empty string here.
    let path: String

    /// Optional override for the navigation title. Used by the root level
    /// so the sheet's purpose ("Choose Signed PDFs Folder") is visible
    /// before the user descends. Sub-levels pass `nil` and the leaf
    /// folder name takes its place.
    let titleOverride: String?

    /// Routed all the way down so any level can commit a selection and
    /// the sheet dismisses end-to-end in one hop.
    let onPick: (String) -> Void

    @Environment(SyncCoordinator.self) private var sync

    @State private var entries: [DropboxFolderEntry] = []
    @State private var loadState: LoadState = .loading
    @State private var showCreateSheet = false

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    var body: some View {
        List {
            switch loadState {
            case .loading:
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading folders…")
                            .foregroundStyle(.secondary)
                    }
                }

            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("Try again") {
                        Task { await load() }
                    }
                }

            case .loaded:
                if entries.isEmpty {
                    Section {
                        // Spell out the implication: an empty folder is a
                        // valid pick, and so is creating a fresh one here.
                        Text("This folder has no subfolders. You can use it as-is or create a new folder inside it.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                } else {
                    Section("Subfolders") {
                        ForEach(entries) { entry in
                            NavigationLink {
                                FolderBrowserView(
                                    path: entry.path,
                                    titleOverride: nil,
                                    onPick: onPick
                                )
                            } label: {
                                Label(entry.name, systemImage: "folder.fill")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    onPick(path)
                } label: {
                    Label {
                        Text(useThisFolderLabel)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create folder here", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showCreateSheet) {
            CreateFolderSheet(parentPath: path) {
                // Refresh after a successful create so the new folder
                // appears in the list immediately.
                Task { await load() }
            }
        }
    }

    private var navTitle: String {
        if let titleOverride { return titleOverride }
        if path.isEmpty { return "Your Dropbox" }
        return (path as NSString).lastPathComponent
    }

    private var useThisFolderLabel: String {
        if path.isEmpty {
            return "Use your Dropbox root"
        }
        let name = (path as NSString).lastPathComponent
        return "Use \"\(name)\""
    }

    private func load() async {
        loadState = .loading
        guard let provider = sync.dropbox else {
            loadState = .failed(message: "Dropbox is not connected.")
            return
        }
        do {
            let fetched = try await provider.listFolder(at: path)
            entries = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadState = .loaded
        } catch let error as DropboxSyncProvider.ServiceError {
            // .notAuthorized would mean the credential lapsed mid-pick.
            // The Connect screen handles re-link, so just surface the
            // message and let the user back out.
            loadState = .failed(message: error.errorDescription ?? "Couldn't load this folder.")
        } catch {
            loadState = .failed(message: error.localizedDescription)
        }
    }
}

/// Sub-sheet for "Create folder here." Two-input form (name + visible
/// hint) on top of `DropboxSyncProvider.createFolder(at:)`. Surfaces the
/// conflict-with-existing-folder case distinctly so the manager sees a
/// pointed "that name's already taken" instead of a generic banner.
private struct CreateFolderSheet: View {
    let parentPath: String
    /// Called on successful create. Picker reloads so the new folder
    /// appears in the parent list.
    let onCreated: () -> Void

    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var folderName: String = ""
    @State private var inFlight: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New folder name", text: $folderName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(submit)
                } header: {
                    Text("Inside \(parentPath.isEmpty ? "Your Dropbox" : parentPath)")
                } footer: {
                    Text("Letters, numbers, spaces, and hyphens work. Avoid colons, slashes, and question marks.")
                        .font(.footnote)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if inFlight {
                        ProgressView()
                    } else {
                        Button("Create", action: submit)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
    }

    private var trimmedName: String {
        folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        Task { await create(named: name) }
    }

    private func create(named name: String) async {
        inFlight = true
        errorMessage = nil
        defer { inFlight = false }

        guard let provider = sync.dropbox else {
            errorMessage = "Dropbox is not connected."
            return
        }

        let targetPath = parentPath.isEmpty ? "/\(name)" : "\(parentPath)/\(name)"
        do {
            _ = try await provider.createFolder(at: targetPath)
            onCreated()
            dismiss()
        } catch let error as DropboxSyncProvider.ServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
