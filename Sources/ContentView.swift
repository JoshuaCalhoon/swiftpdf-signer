import SwiftUI

struct ContentView: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppSettings.self) private var settings

    /// One-shot onboarding sheet shown after the manager's first
    /// successful OAuth. Bound to `AppSettings.hasCompletedFolderSetup` so
    /// it appears once per install on .authorized and is suppressed
    /// thereafter. Not shown in demo — there are no real folders to
    /// configure. (v1.1)
    @State private var showingFolderSetup = false

    var body: some View {
        switch sync.authState {
        case .notAuthorized, .authorizing, .authFailed:
            ConnectDropboxView()
        case .authorized, .demo:
            // Demo session routes to the same Library surface as a real
            // session. TemplateStore and FormView branch on `sync.isDemo`
            // internally so calls stay in-memory.
            NavigationStack {
                LibraryView()
            }
            .sheet(isPresented: $showingFolderSetup) {
                FolderSetupSheet()
            }
            .onAppear { evaluateFolderSetupPrompt() }
            .onChange(of: sync.authState) { _, _ in
                evaluateFolderSetupPrompt()
            }
        }
    }

    /// Single decision point: present the folder-setup sheet only when
    /// the manager has just landed on real auth (not demo) and hasn't
    /// completed the setup yet. Called from both .onAppear (covers app-
    /// launch with persisted credentials) and .onChange (covers the
    /// .notAuthorized → .authorizing → .authorized transition from a
    /// fresh Connect tap).
    private func evaluateFolderSetupPrompt() {
        guard sync.authState == .authorized,
              !settings.hasCompletedFolderSetup
        else { return }
        showingFolderSetup = true
    }
}

#Preview("Connect screen") {
    let settings = AppSettings()
    let dropbox = DropboxSyncProvider(settings: settings)
    let coordinator = SyncCoordinator(dropbox: dropbox)
    ContentView()
        .environment(coordinator)
        .environment(TemplateStore(sync: coordinator))
        .environment(settings)
}
