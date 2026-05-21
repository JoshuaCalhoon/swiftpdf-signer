import SwiftUI

@main
struct SwiftPDFApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var sync: SyncCoordinator
    @State private var templates: TemplateStore
    @State private var settings: AppSettings

    init() {
        // Validate the active provider's configuration at launch so a
        // misconfigured dev environment (missing Configuration/Local.xcconfig
        // or a placeholder DROPBOX_APP_KEY) fails immediately with a clean
        // stack trace pointing at the app's init, rather than crashing on
        // first Connect tap with a static-let-initializer trace. Each
        // provider conformer owns its own launch-time check; when a second
        // provider lands, this call dispatches on the active provider type.
        DropboxSyncProvider.validateConfigurationAtLaunch()
        // Construction order: AppSettings holds the manager-overridable
        // Dropbox destination paths read by DropboxSyncProvider, so it
        // exists first. Coordinator wraps the provider; TemplateStore wraps
        // the coordinator. (v1.1)
        let appSettings = AppSettings()
        let dropbox = DropboxSyncProvider(settings: appSettings)
        let coordinator = SyncCoordinator(dropbox: dropbox)
        _settings = State(initialValue: appSettings)
        _sync = State(initialValue: coordinator)
        _templates = State(initialValue: TemplateStore(sync: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sync)
                .environment(templates)
                .environment(settings)
                // Optional-chain: in production `sync.dropbox` is always
                // non-nil (Dropbox is the only sync provider today). The
                // chain makes the test-only init path safe — a coordinator
                // wrapping a non-Dropbox fake just ignores OAuth redirects.
                //
                // Demo guard: a customer in demo mode shouldn't be able to
                // transition into a real-auth state via a stale or crafted
                // db-{appKey}:// URL. The provider's own handleRedirect could
                // do this check, but hoisting it here keeps SyncCoordinator
                // and provider state out of each other's frame.
                .onOpenURL { url in
                    guard !sync.isDemo else { return }
                    sync.dropbox?.handleRedirect(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Reset the manager-auth grace window whenever the iPad leaves
            // foreground. A customer picking up the iPad after a brief
            // background lock shouldn't inherit the manager's prior auth.
            if newPhase != .active {
                ManagerGate.invalidate()
            }
        }
    }
}
