import SwiftUI

/// Persistent header strip shown above `LibraryView` and `FormView` while
/// `DropboxService.authState == .demo`. Spells out that uploads are disabled
/// and offers an inline path to switch into a real Dropbox session. Pinned
/// via `.safeAreaInset(edge: .top)` on each consuming surface so the
/// reviewer (and any first-time user exploring the demo) can't lose track of
/// the fact that nothing is being uploaded.
struct DemoBanner: View {
    @Environment(AppSettings.self) private var settings

    /// Invoked when the Connect button is tapped. The caller is responsible
    /// for the actual state transition — typically `dropbox.endDemoSession()`
    /// plus `store.resetForDemoExit()` — so this view stays a pure presenter
    /// with no service dependencies of its own.
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.callout)
                .foregroundStyle(settings.brandColor)

            Text("Demo mode: uploads disabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button("Connect", action: onConnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(settings.brandColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
