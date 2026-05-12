import SwiftUI

@main
struct SwiftPDFApp: App {
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
    }
}
