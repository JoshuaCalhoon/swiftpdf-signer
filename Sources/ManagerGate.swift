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

    /// When true, every `require(...)` call returns `.authenticated` without
    /// prompting. Flipped on by `SyncCoordinator.beginDemoSession()` and off
    /// by `endDemoSession()` so an App Store reviewer (or any demo-mode user)
    /// can reach Settings / Manage / Disconnect without owning the device's
    /// Face ID enrollment. Demo sessions don't have any real-data surface
    /// area worth gating, so this is safe.
    static var demoBypass = false

    /// Runs the biometric / passcode prompt and reports the outcome. `reason`
    /// becomes the subtitle of the system prompt — keep it short and concrete:
    /// "Return to template library", "Disconnect Dropbox", etc.
    ///
    /// Returns `.authenticated` without prompting if the most recent successful
    /// authentication is still inside the grace window. The grace is reset by
    /// `invalidate()` (called on app background and on customer-flow entry).
    static func require(reason: String) async -> Outcome {
        if demoBypass {
            return .authenticated
        }
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

    /// Standard surfaced-error copy when `require(...)` returns
    /// `.notConfigured` — no passcode or biometric is configured on the
    /// device. Single-sourced here because every gated surface (FormView,
    /// LibraryView, ConnectDropboxView) renders the same message and the
    /// app now runs on both iPhone and iPad, so the wording must be
    /// device-agnostic.
    static let noPasscodeMessage = "This device has no passcode or biometric configured. Ask IT to set one in iOS Settings → Face ID & Passcode."

    // MARK: - First-setup bookkeeping

    /// UserDefaults key for the persistent "this iPad has been configured"
    /// flag. Lives in standard defaults so iOS-managed app data backup
    /// captures it — the flag survives the app being killed but not a
    /// reinstall, which matches the "starting fresh" intent.
    private static let firstSetupKey = "managerGate.firstSetupCompleted"

    /// True once the device has completed initial Dropbox setup at least
    /// once in the current install. Read by `ConnectDropboxView` to decide
    /// whether the Connect button needs gating: a fresh install with no
    /// iOS passcode set must be able to authorize once (otherwise the app
    /// is unusable on a device that hasn't been through IT setup yet).
    /// Once true, never returns to false in the same install.
    static var hasCompletedFirstSetup: Bool {
        UserDefaults.standard.bool(forKey: firstSetupKey)
    }

    /// Idempotent flag-flip. Called from `DropboxSyncProvider` on the first
    /// successful authorize and on each unauthorize, and on init when an
    /// existing client is found in the SDK store (covers app-relaunch and
    /// upgrade-from-prior-version paths).
    static func markFirstSetupComplete() {
        UserDefaults.standard.set(true, forKey: firstSetupKey)
    }

    /// UserDefaults key for the "manager has tapped Connect at least once"
    /// flag. Lives alongside `firstSetupKey` in standard defaults.
    private static let connectInitiatedKey = "managerGate.connectInitiated"

    /// True once the Connect button has been tapped at least once on this
    /// install. Tracks tap *intent* independently of whether the OAuth flow
    /// actually completed. Paired with `hasCompletedFirstSetup` by
    /// `ConnectDropboxView` to scope the no-passcode IT escape hatch to the
    /// very first Connect attempt only: a manager cancelling mid-OAuth, a
    /// customer routing through Demo and back, or any other re-entrance now
    /// hits the Face ID gate even if `hasCompletedFirstSetup` is still false.
    /// Sticky for the lifetime of the install.
    static var hasInitiatedConnect: Bool {
        UserDefaults.standard.bool(forKey: connectInitiatedKey)
    }

    /// Idempotent flag-flip. Called from `ConnectDropboxView.startAuth` on
    /// every Connect tap; the first call is the one that closes the bypass.
    static func markConnectInitiated() {
        UserDefaults.standard.set(true, forKey: connectInitiatedKey)
    }

    /// UserDefaults key for the "this install has linked under the new
    /// Full-Dropbox app key at least once" flag. Set by
    /// `DropboxSyncProvider.handleRedirect` on first .success and by its
    /// init when an existing client is found. Used by `ConnectDropboxView`
    /// to distinguish the v1.1 migration case (user was linked under the
    /// retired app-folder key) from a routine reconnect (user already on
    /// v1.1 but chose to Disconnect). Decays into "always true" once
    /// every installed copy has migrated; deletable in a future cleanup. (v1.1)
    private static let fullDropboxLinkedKey = "managerGate.fullDropboxLinked"

    /// True once the install has successfully OAuthed under the v1.1
    /// Full-Dropbox app key at least once. Reads as false on pre-v1.1
    /// upgrades that previously linked under the old app-folder key —
    /// `ConnectDropboxView` shows migration-framed copy in that case.
    static var hasLinkedUnderFullDropboxKey: Bool {
        UserDefaults.standard.bool(forKey: fullDropboxLinkedKey)
    }

    /// Idempotent flag-flip. Called on every successful Dropbox link
    /// under the v1.1 key; the first call is the one that retires the
    /// migration copy on the Connect screen.
    static func markFullDropboxLinked() {
        UserDefaults.standard.set(true, forKey: fullDropboxLinkedKey)
    }

    // MARK: - Test seams (DEBUG only)

    #if DEBUG
    /// Test-only setter for the cached authentication time. The only
    /// legitimate production writer is `require()` itself — tests use this
    /// seam to put the gate into a known-good "within grace window" or
    /// "outside grace window" state without driving a real LAContext prompt.
    /// (audit TC-02)
    static func _setLastAuthenticatedAtForTesting(_ date: Date?) {
        lastAuthenticatedAt = date
    }

    /// Test-only reader so tests can verify `invalidate()` wipes the cache.
    static func _lastAuthenticatedAtForTesting() -> Date? {
        lastAuthenticatedAt
    }

    /// Grace-window length, exposed so tests can verify boundary behavior
    /// without hard-coding the constant in two places.
    static var _graceWindowForTesting: TimeInterval { graceWindow }
    #endif
}
