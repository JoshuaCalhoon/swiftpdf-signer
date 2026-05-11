import SwiftUI

struct ContentView: View {
    @Environment(DropboxService.self) private var dropbox

    var body: some View {
        switch dropbox.authState {
        case .notAuthorized, .authorizing, .authFailed:
            ConnectDropboxView()
        case .authorized:
            NavigationStack {
                FormView(template: .generalSafetyV1)
            }
        }
    }
}

#Preview("Connect screen") {
    ContentView()
        .environment(DropboxService())
}
