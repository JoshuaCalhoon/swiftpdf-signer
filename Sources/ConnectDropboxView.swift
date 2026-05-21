import SwiftUI
import UIKit

struct ConnectDropboxView: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 72))
                .foregroundStyle(settings.brandColor)

            VStack(spacing: 8) {
                Text(headline)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            }

            if case .authorizing = sync.authState {
                ProgressView("Opening Dropbox…")
                    .padding(.top, 8)
            }

            if case .authFailed(let message) = sync.authState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color(.systemRed))
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: startAuth) {
                    Text(connectButtonLabel)
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.brandColor)
                .controlSize(.large)
                .disabled(sync.authState == .authorizing)

                // Scope disclosure: spells out that the broader OAuth scope
                // (visible on the Dropbox-side authorization screen) is
                // bounded by the manager's folder choice. Reads as a
                // promise to a real manager, and as context to an App
                // Store reviewer who taps Connect and lands on a
                // Full-Dropbox scope screen. (v1.1 Phase B.6)
                Text("SwiftPDF Signer only reads and writes the folders you pick in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 360)

                // "or" divider — standard auth-screen pattern that signals
                // the demo is a real alternative, not a curiosity link. Reads
                // natural to first-time users and unambiguous to App Store
                // reviewers scanning the screen for a no-credential path.
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(height: 1)
                    Text("or")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(height: 1)
                }
                .frame(maxWidth: 360)
                .padding(.vertical, 4)

                // Secondary CTA — visually subordinate to Connect so a real
                // user reads "sign in" as the default path. Reviewers (and
                // anyone who wants to look around before authorizing) get a
                // no-account way into the app. Demo state is purely
                // in-memory — see SyncCoordinator.beginDemoSession.
                Button(action: sync.beginDemoSession) {
                    Text("Try Demo (no sign-in required)")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .tint(settings.brandColor)
                .controlSize(.large)
                .disabled(sync.authState == .authorizing)
            }
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// True when this install previously linked under the retired v1.0
    /// app-folder Dropbox app and hasn't yet completed an OAuth round-trip
    /// under the v1.1 Full-Dropbox key. Drives the migration-framed copy.
    /// Once the manager reconnects, `markFullDropboxLinked` flips the
    /// flag and the screen reverts to the standard first-time copy on any
    /// future disconnect. (v1.1 Phase B.5)
    private var isMigratingFromAppFolderKey: Bool {
        ManagerGate.hasCompletedFirstSetup && !ManagerGate.hasLinkedUnderFullDropboxKey
    }

    private var headline: String {
        isMigratingFromAppFolderKey ? "Reconnect Dropbox" : "Connect Dropbox"
    }

    private var subtitle: String {
        if isMigratingFromAppFolderKey {
            return "SwiftPDF Signer now lets you pick where templates and signed PDFs land, including folders shared with your team. Reconnect to choose your preferred folders."
        }
        return "One-time setup per device. You'll pick which folders templates and signed PDFs go into, including folders shared with your team."
    }

    private var connectButtonLabel: String {
        isMigratingFromAppFolderKey ? "Reconnect Dropbox" : "Connect Dropbox"
    }

    private func startAuth() {
        // The Connect screen is only reachable in production where
        // `sync.dropbox` is always non-nil. The optional-bind is a defensive
        // no-op for the test-only coordinator path.
        guard let dropbox = sync.dropbox else { return }

        // Capture whether this is the very first Connect tap on this install
        // BEFORE flipping the flag, then mark the tap immediately. The next
        // tap (after a cancel, a demo round-trip, or any other re-entrance)
        // will observe hasInitiatedConnect == true and fall through to the
        // Face ID gate even if the first OAuth attempt never completed.
        let isFirstTap = !ManagerGate.hasInitiatedConnect
        ManagerGate.markConnectInitiated()

        // First install with no passcode set must reach the authorized state
        // at least once — the gate has no meaningful answer when the device
        // hasn't been through IT setup. The bypass fires only on the very
        // first Connect tap, scoped by both flags: hasCompletedFirstSetup
        // closes it once OAuth lands; hasInitiatedConnect closes it the
        // moment the manager tapped the button, regardless of whether the
        // first attempt completed. Closes the S2 demo→exit→Connect path.
        if isFirstTap && !ManagerGate.hasCompletedFirstSetup {
            guard let controller = topViewController() else { return }
            dropbox.authorize(from: controller)
            return
        }

        Task {
            switch await ManagerGate.require(reason: "Connect Dropbox account") {
            case .authenticated:
                // Face ID is a system overlay; while its sheet is up the
                // scene reports `.foregroundInactive`, and the transition
                // back to `.foregroundActive` after dismissal can lag the
                // prompt's UI dismiss by an indeterminate window
                // (100-1000ms observed). Calling `dropbox.authorize(from:)`
                // before that transition completes triggers
                // `WebAuthenticationSessionError.presentationContextInvalid`
                // (error 3) on the first attempt. Active wait — poll until
                // a scene is foregroundActive, bounded by a 2-second
                // timeout against the unlikely case where the scene never
                // re-activates. (v1.1)
                await Self.waitForForegroundActiveScene()
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

    /// Polls UIApplication scenes until at least one is foreground-active
    /// AND has a key window, bailing as soon as ready. Stricter than just
    /// `activationState == .foregroundActive` because Face ID dismissal
    /// sequences through that state briefly before the scene's key
    /// window is re-established — ASWebAuth's anchor check requires both.
    /// A 200ms buffer after readiness covers any additional UIKit lag.
    /// (v1.1)
    @MainActor
    private static func waitForForegroundActiveScene(timeout: Duration = .seconds(2)) async {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let ready = UIApplication.shared.connectedScenes.contains { scene in
                guard let windowScene = scene as? UIWindowScene,
                      windowScene.activationState == .foregroundActive else { return false }
                return windowScene.windows.contains(where: \.isKeyWindow)
            }
            if ready {
                // Even with active+keyWindow satisfied, UIKit can still
                // be a tick away from accepting the anchor. The buffer is
                // a defensive yield, not an empirical magic number.
                try? await Task.sleep(for: .milliseconds(200))
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Timed out — proceed anyway. ASWebAuth will surface its own
        // error if the anchor is still invalid; better than silently
        // freezing the Connect screen here.
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
