import SwiftUI
import UIKit

struct ConnectDropboxView: View {
    @Environment(DropboxService.self) private var dropbox
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 72))
                .foregroundStyle(settings.brandColor)

            VStack(spacing: 8) {
                Text("Connect Dropbox")
                    .font(.largeTitle.bold())
                Text("One-time setup per device. Signed forms upload to your Dropbox app folder under /Apps.")
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
            .tint(settings.brandColor)
            .controlSize(.large)
            .disabled(dropbox.authState == .authorizing)
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startAuth() {
        // First install with no passcode set must reach the authorized state
        // at least once — the gate has no meaningful answer when the device
        // hasn't been through IT setup. Subsequent Connect taps (post a
        // previous authorize or unauthorize) require manager identity, since
        // by then a customer could be holding the iPad and a fresh Connect
        // would redirect uploads to their Dropbox.
        if !ManagerGate.hasCompletedFirstSetup {
            guard let controller = topViewController() else { return }
            dropbox.authorize(from: controller)
            return
        }

        Task {
            switch await ManagerGate.require(reason: "Connect Dropbox account") {
            case .authenticated:
                guard let controller = topViewController() else { return }
                dropbox.authorize(from: controller)
            case .userCancelled:
                // Manager backed out of the biometric prompt. Stay where we
                // are; the Connect button is still visible.
                break
            case .notConfigured:
                // Setup has happened before but the device's passcode is now
                // missing. Refuse rather than bypassing — if a customer
                // briefly held the device while IT removed the passcode,
                // bypassing here would defeat the gate.
                dropbox.surfaceAuthError(ManagerGate.noPasscodeMessage)
            case .failed(let message):
                dropbox.surfaceAuthError(message)
            }
        }
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
    /// Walks the `presentedViewController` chain iteratively so we never blow
    /// the stack on a pathological cycle. Cycles aren't supposed to be
    /// reachable in UIKit, but iterative is the same number of lines and
    /// resists future surprises.
    var topPresented: UIViewController {
        var current = self
        while let next = current.presentedViewController {
            current = next
        }
        return current
    }
}
