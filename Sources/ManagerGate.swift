import Foundation
import LocalAuthentication

/// Biometric / device-passcode gate for manager-only actions on a customer-handed iPad.
///
/// `LAPolicy.deviceOwnerAuthentication` prompts FaceID / TouchID first, then
/// falls back to the device passcode if biometrics fail or aren't enrolled.
/// The "PIN" the manager enters is the iPad's own passcode — we don't store
/// one ourselves. Deployment prerequisite: the iPad must have a passcode set
/// in iOS Settings → Face ID & Passcode (or Touch ID & Passcode on older iPads).
/// Without one, `canEvaluatePolicy` returns false and `require` returns the
/// `.notConfigured` outcome so the caller can surface a setup message.
///
/// A short grace window means consecutive manager actions in the same setup
/// session don't each require a fresh prompt — see `graceWindow` below.
@MainActor
enum ManagerGate {
    enum Outcome: Equatable {
        case authenticated
        case userCancelled
        case notConfigured
        case failed(message: String)
    }

    /// How long a successful authentication keeps subsequent `require(...)`
    /// calls prompt-free. Sized so a manager hitting Settings then Disconnect
    /// in quick succession doesn't re-FaceID, but short enough that a customer
    /// who picks up the iPad after the manager auths can't realistically race
    /// to a gated action. Conservative for a kiosk model — banking apps often
    /// use 30s+ with explicit invalidation; we add invalidation on app
    /// background and on FormView appearance (a customer flow starting) so
    /// the surface for accidental inheritance is small.
    private static let graceWindow: TimeInterval = 30

    private static var lastAuthenticatedAt: Date?

    /// Runs the biometric / passcode prompt and reports the outcome. `reason`
    /// becomes the subtitle of the system prompt — keep it short and concrete:
    /// "Return to template library", "Disconnect Dropbox", etc.
    ///
    /// Returns `.authenticated` without prompting if the most recent successful
    /// authentication is still inside the grace window. The grace is reset by
    /// `invalidate()` (called on app background and on customer-flow entry).
    static func require(reason: String) async -> Outcome {
        if let last = lastAuthenticatedAt,
           Date().timeIntervalSince(last) < graceWindow {
            return .authenticated
        }

        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return .notConfigured
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok {
                lastAuthenticatedAt = Date()
            }
            return ok ? .authenticated : .userCancelled
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .systemCancel || laError.code == .appCancel {
            return .userCancelled
        } catch let laError as LAError where laError.code == .passcodeNotSet || laError.code == .biometryNotAvailable || laError.code == .biometryNotEnrolled {
            return .notConfigured
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Wipes the cached authentication so the next `require(...)` call
    /// prompts. Called when the app leaves foreground (SwiftPDFApp's
    /// scenePhase observer) and when a customer flow begins (FormView's
    /// `.onAppear`) so a manager's grace doesn't carry into customer hands.
    static func invalidate() {
        lastAuthenticatedAt = nil
    }
}
