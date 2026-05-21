import SwiftUI

/// One-shot onboarding sheet that appears right after the manager's first
/// successful Dropbox OAuth. Shows the same two folder-setting rows as
/// Settings, but with an explainer header that tells the manager this is
/// the moment to pick — defaults work, but rarely match what a real
/// manager wants for shared-with-team destinations.
///
/// Dismissal flips `AppSettings.hasCompletedFolderSetup` so subsequent
/// disconnect/reconnect cycles don't re-prompt; the manager already
/// established their preference (whether by picking custom paths or by
/// tapping Done on the defaults). Changes any time via Settings →
/// Dropbox Folders. (v1.1)
struct FolderSetupSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showingTemplatesPicker = false
    @State private var showingSignedPicker = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your folders")
                            .font(.title2.bold())
                        Text("SwiftPDF Signer reads templates from one folder in your Dropbox and saves signed PDFs to another. Pick where each lives. You can change them any time in Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

                Section {
                    Button {
                        showingTemplatesPicker = true
                    } label: {
                        folderRowLabel(title: "Templates folder", path: settings.dropboxTemplatesPath)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingSignedPicker = true
                    } label: {
                        folderRowLabel(title: "Signed PDFs folder", path: settings.dropboxSignedPath)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Dropbox Folders")
                } footer: {
                    Text("A folder shared with your team works, too. SwiftPDF Signer only reads and writes the folders you pick here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        settings.hasCompletedFolderSetup = true
                        dismiss()
                    } label: {
                        Text("Done").fontWeight(.semibold)
                    }
                }
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
            // Block back-swipe-to-dismiss without a Done tap. The flag has
            // to set; if the user swipes away, the sheet re-presents on
            // every relaunch until they Done it — annoying. The Done
            // button is the only path out.
            .interactiveDismissDisabled(true)
        }
    }

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
}
