import SwiftUI
import UIKit

struct ConnectDropboxView: View {
    @Environment(DropboxService.self) private var dropbox

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.kwikshipOrange)

            VStack(spacing: 8) {
                Text("Connect Dropbox")
                    .font(.largeTitle.bold())
                Text("One-time setup per iPad. Signed forms upload to /Apps/SwiftPDF/Signed/ in your Dropbox.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            if case .authorizing = dropbox.authState {
                ProgressView("Opening Dropbox…")
                    .padding(.top, 8)
            }

            if case .authFailed(let message) = dropbox.authState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color(.systemRed))
                    .padding(.horizontal)
            }

            Spacer()

            Button(action: startAuth) {
                Text("Connect Dropbox")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.kwikshipOrange)
            .controlSize(.large)
            .disabled(dropbox.authState == .authorizing)
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startAuth() {
        guard let controller = topViewController() else { return }
        dropbox.authorize(from: controller)
    }

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topPresented
    }
}

private extension UIViewController {
    var topPresented: UIViewController {
        presentedViewController?.topPresented ?? self
    }
}
