import SwiftUI
import PhotosUI

/// Manager-facing settings sheet. Entry point is gated by `ManagerGate` from
/// `LibraryView`'s toolbar, so a customer signing on a shared iPad can't
/// reach this surface without manager authentication.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    /// `ColorPicker` updates its binding many times per second during slider
    /// drags. Mirror through local state instead of binding straight at
    /// `settings.brandColorHex` — that way UserDefaults sees one write per
    /// settled value, not per drag tick.
    @State private var workingColor: Color = AppSettings.defaultBrandColor

    /// Holds the user's most-recent PhotosPicker selection while the image
    /// data is being loaded asynchronously. Cleared back to nil after the
    /// data lands in `settings.companyLogoData` so picking the same image
    /// again still fires the change observer.
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var logoLoadFailed = false

    /// Sheet-presentation flags for the two Dropbox path pickers. Two
    /// independent flags rather than one enum so SwiftUI's `.sheet`
    /// transitions are crisp — switching between the two pickers via a
    /// single shared enum produced a momentary fade through the empty
    /// state during testing. (v1.1 Phase B.4)
    @State private var showingTemplatesPicker = false
    @State private var showingSignedPicker = false

    var body: some View {
        // Local @Bindable shadow so we can derive bindings ($settings.foo)
        // from an Environment-injected @Observable. The shadow is scoped to
        // this view's body — the actual state lives in the env-injected
        // instance.
        @Bindable var settings = settings

        NavigationStack {
            Form {
                preview

                Section {
                    ColorPicker("Accent color", selection: $workingColor, supportsOpacity: false)
                } header: {
                    Text("Brand Color")
                } footer: {
                    Text("Tints primary buttons and indicators in the app, and the document title in signed PDFs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                logoSection

                Section {
                    TextField("Company", text: $settings.companyName)
                        .textInputAutocapitalization(.words)
                    TextField("Location", text: $settings.companyLocation)
                        .textInputAutocapitalization(.words)
                    TextField("Department", text: $settings.companyDepartment)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Form Header Defaults")
                } footer: {
                    Text("Used for the company / location / department fields at the top of every newly-created template. Leave blank to keep the generic placeholders.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                dropboxFoldersSection

                Section {
                    Button("Reset brand color") {
                        settings.resetBrandColor()
                        workingColor = settings.brandColor
                    }
                }

                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { workingColor = settings.brandColor }
            // `onChange(of: workingColor)` fires every time the picker drag
            // updates the binding. Compare hex strings before writing back
            // so identical-color updates don't trigger a UserDefaults round-trip.
            .onChange(of: workingColor) { _, newValue in
                guard let hex = newValue.toHex(), hex != settings.brandColorHex else {
                    return
                }
                settings.brandColorHex = hex
            }
            .onChange(of: logoPickerItem) { _, newItem in
                Task { await loadPickedLogo(newItem) }
            }
            .alert("Couldn't load image", isPresented: $logoLoadFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The selected file isn't a readable image. Try a JPEG or PNG.")
            }
            .sheet(isPresented: $showingTemplatesPicker) {
                ChooseDropboxFolderView(title: "Choose Templates Folder") { pickedPath in
                    settings.dropboxTemplatesPath = pickedPath.isEmpty
                        ? AppSettings.defaultDropboxTemplatesPath
                        : pickedPath
                }
            }
            .sheet(isPresented: $showingSignedPicker) {
                ChooseDropboxFolderView(title: "Choose Signed PDFs Folder") { pickedPath in
                    settings.dropboxSignedPath = pickedPath.isEmpty
                        ? AppSettings.defaultDropboxSignedPath
                        : pickedPath
                }
            }
        }
    }

    /// Dropbox destination paths. Only surfaced when Dropbox is actually
    /// connected — the picker can't list folders without a live client,
    /// and showing disabled rows in demo / disconnected states would just
    /// raise the question "why am I seeing this?" with no good answer.
    /// (v1.1 Phase B.4)
    @ViewBuilder
    private var dropboxFoldersSection: some View {
        if sync.authState == .authorized {
            Section {
                Button {
                    showingTemplatesPicker = true
                } label: {
                    folderRowLabel(
                        title: "Templates folder",
                        path: settings.dropboxTemplatesPath
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showingSignedPicker = true
                } label: {
                    folderRowLabel(
                        title: "Signed PDFs folder",
                        path: settings.dropboxSignedPath
                    )
                }
                .buttonStyle(.plain)
            } header: {
                Text("Dropbox Folders")
            } footer: {
                Text("Templates and signed PDFs land in these folders in your Dropbox. Tap a row to pick a different folder. A folder shared with your team works, too.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Two-line row label: title on top, current path beneath in a
    /// monospaced caption so long paths read cleanly when wrapped /
    /// truncated. Trailing chevron mirrors the NavigationLink look so
    /// the row reads as tappable.
    private func folderRowLabel(title: String, path: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption.weight(.semibold))
        }
        .contentShape(Rectangle())
    }

    /// Inline sample of the brand color applied to a title and a button, so
    /// the manager can see the effect of the picker without dismissing the
    /// sheet to check.
    private var preview: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample Form Title")
                    .font(.title2.bold())
                    .foregroundStyle(settings.brandColor)
                Button {} label: {
                    Text("Sample Button")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.brandColor)
                .controlSize(.large)
                .allowsHitTesting(false)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Preview")
        }
    }

    @ViewBuilder
    private var logoSection: some View {
        Section {
            if let logo = settings.companyLogo {
                HStack(spacing: 16) {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.tertiarySystemFill))
                        )
                    PhotosPicker(selection: $logoPickerItem, matching: .images) {
                        Text("Change logo")
                    }
                }
                Button("Remove logo", role: .destructive) {
                    settings.companyLogoData = nil
                }
            } else {
                PhotosPicker(selection: $logoPickerItem, matching: .images) {
                    Label("Add company logo", systemImage: "photo")
                }
            }
        } header: {
            Text("Company Logo")
        } footer: {
            Text("Optional. Renders at the left of the header on signed PDFs and in the in-app preview. Square images look best. Non-square images are letterboxed inside a square slot.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Source-provenance row. `SourceRepository` and `SourceCommit` are wired
    /// in via `project.yml` and a preBuildScript that captures `git rev-parse
    /// HEAD` per build. Production builds should be made from a fresh clone of
    /// the public repo so the displayed commit corresponds to a real,
    /// reviewable revision.
    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("\(BuildInfo.version) (\(BuildInfo.build))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let url = BuildInfo.sourceCommitURL {
                Link(destination: url) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Source code")
                                .foregroundStyle(.primary)
                            Text("\(BuildInfo.sourceRepository) @ \(BuildInfo.sourceCommitShort)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source code")
                    Text("\(BuildInfo.sourceRepository) @ \(BuildInfo.sourceCommitShort)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("This app's source is published at the repository above. The commit hash identifies the exact source state this build was produced from. Anyone can clone, build, and verify the app's behavior. A `-dirty` suffix means the build was made from a working tree with uncommitted changes.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func loadPickedLogo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressed = AppSettings.compressLogoForStorage(image) else {
                logoLoadFailed = true
                logoPickerItem = nil
                return
            }
            settings.companyLogoData = compressed
            logoPickerItem = nil
        } catch {
            logoLoadFailed = true
            logoPickerItem = nil
        }
    }
}
