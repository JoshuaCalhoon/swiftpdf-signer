import SwiftUI

struct ContentView: View {
    @Environment(DropboxService.self) private var dropbox

    var body: some View {
        switch dropbox.authState {
        case .notAuthorized, .authorizing, .authFailed:
            ConnectDropboxView()
        case .authorized, .demo:
            // Demo session routes to the same Library surface as a real
            // Dropbox session. TemplateStore and FormView branch internally
            // on `dropbox.authState == .demo` so calls stay in-memory.
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
