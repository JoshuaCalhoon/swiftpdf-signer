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
@MainActor
enum ManagerGate {
    enum Outcome: Equatable {
        case authenticated
        case userCancelled
        case notConfigured
        case failed(message: String)
    }

    /// Runs the biometric / passcode prompt and reports the outcome. `reason`
    /// becomes the subtitle of the system prompt — keep it short and concrete:
    /// "Return to template library", "Disconnect Dropbox", etc.
    static func require(reason: String) async -> Outcome {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return .notConfigured
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .authenticated : .userCancelled
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .systemCancel || laError.code == .appCancel {
            return .userCancelled
        } catch let laError as LAError where laError.code == .passcodeNotSet || laError.code == .biometryNotAvailable || laError.code == .biometryNotEnrolled {
            return .notConfigured
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
