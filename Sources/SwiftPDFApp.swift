import SwiftUI

@main
struct SwiftPDFApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var dropbox: DropboxService
    @State private var templates: TemplateStore
    @State private var settings: AppSettings

    init() {
        let service = DropboxService()
        _dropbox = State(initialValue: service)
        _templates = State(initialValue: TemplateStore(dropbox: service))
        _settings = State(initialValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dropbox)
                .environment(templates)
                .environment(settings)
                .onOpenURL { url in dropbox.handleRedirect(url) }
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
