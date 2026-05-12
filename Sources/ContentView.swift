import SwiftUI

struct ContentView: View {
    @Environment(DropboxService.self) private var dropbox

    var body: some View {
        switch dropbox.authState {
        case .notAuthorized, .authorizing, .authFailed:
            ConnectDropboxView()
        case .authorized:
            NavigationStack {
                LibraryView()
            }
        }
    }
}

#Preview("Connect screen") {
    let dropbox = DropboxService()
    ContentView()
        .environment(dropbox)
        .environment(TemplateStore(dropbox: dropbox))
        .environment(AppSettings())
}
