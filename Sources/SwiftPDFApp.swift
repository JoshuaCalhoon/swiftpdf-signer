import SwiftUI

@main
struct SwiftPDFApp: App {
    @State private var dropbox = DropboxService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dropbox)
                .onOpenURL { url in dropbox.handleRedirect(url) }
        }
    }
}
