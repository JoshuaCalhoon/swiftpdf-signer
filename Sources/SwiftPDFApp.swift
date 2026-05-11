import SwiftUI

@main
struct SwiftPDFApp: App {
    @State private var dropbox: DropboxService
    @State private var templates: TemplateStore

    init() {
        let service = DropboxService()
        _dropbox = State(initialValue: service)
        _templates = State(initialValue: TemplateStore(dropbox: service))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dropbox)
                .environment(templates)
                .onOpenURL { url in dropbox.handleRedirect(url) }
        }
    }
}
