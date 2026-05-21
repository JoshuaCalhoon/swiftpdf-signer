import Foundation

/// Provider-neutral facade for the cloud sync layer. Holds the active
/// `SyncProvider`, owns the demo-preview state (hoisted out of provider land
/// so future no-auth providers like iCloud Drive don't need to model it),
/// and forwards CRUD calls so consumers depend on one observable instead
/// of N per-provider types.
///
/// Today only Dropbox exists; the typed `dropbox` accessor stays non-optional
/// for the production path so `ConnectDropboxView` can drive OAuth without
/// downcasting. The protocol-typed `provider` is what `TemplateStore` and
/// `FormView` route their CRUD through.
@MainActor
@Observable
final class SyncCoordinator {
    /// UI-routing auth state. Combines the demo bit with the active
    /// provider's own auth state machine. SwiftUI views switch on this to
    /// route between `ConnectDropboxView` and `LibraryView`.
    enum AuthState: Equatable {
        case notAuthorized
        case authorizing
        case authorized
        case authFailed(message: String)
        case demo
    }

    /// CRUD-only handle. Type-erased so tests can swap in a fake without
    /// pulling in the Dropbox SDK. Same instance as `dropbox` in production.
    let provider: any SyncProvider

    /// Typed accessor for Dropbox-specific UI (OAuth, the Connect screen).
    /// Non-nil in production; only the test-only init leaves this nil when
    /// a non-Dropbox fake is injected.
    let dropbox: DropboxSyncProvider?

    /// True while the app is in demo-preview mode. Reads in views register
    /// observation on this stored property so the demo banner / routing
    /// reacts to begin/endDemoSession calls.
    private(set) var isDemo: Bool = false

    /// Composed auth state. Observation cascades: reading this from a view
    /// registers tracking on `isDemo` and (transitively) on
    /// `dropbox.authState` — both `@Observable` properties. The actual
    /// mapping lives in `composeAuthState(isDemo:dropboxState:)` so tests can
    /// exhaustively cover the input cross-product without constructing a live
    /// provider.
    var authState: AuthState {
        Self.composeAuthState(isDemo: isDemo, dropboxState: dropbox?.authState)
    }

    /// Pure mapping from `(isDemo, dropbox.authState?)` to the coordinator's
    /// public `AuthState`. Extracted so the case-analysis is testable in
    /// isolation — adding a case to `DropboxSyncProvider.AuthState` without
    /// updating this mapping is the kind of drift TC-05 catches.
    ///
    /// `dropboxState == nil` is the "no Dropbox provider configured" path —
    /// only reachable through the test-only init today, but kept here so the
    /// signature stays valid as more providers come online and one of them
    /// may be absent in some configurations.
    nonisolated static func composeAuthState(
        isDemo: Bool,
        dropboxState: DropboxSyncProvider.AuthState?
    ) -> AuthState {
        if isDemo { return .demo }
        guard let dropboxState else { return .notAuthorized }
        switch dropboxState {
        case .notAuthorized: return .notAuthorized
        case .authorizing: return .authorizing
        case .authorized: return .authorized
        case .authFailed(let message): return .authFailed(message: message)
        }
    }

    /// Production init. Caller constructs the `DropboxSyncProvider` first
    /// (so AppSettings can be wired in) and hands it off. The previous
    /// no-arg default disappeared in v1.1 because `DropboxSyncProvider` now
    /// requires an `AppSettings` reference for its overridable destination
    /// paths.
    init(dropbox: DropboxSyncProvider) {
        self.dropbox = dropbox
        self.provider = dropbox
    }

    #if DEBUG
    /// Test-only init: inject any `SyncProvider` conformer (typically a
    /// `FakeSyncProvider` from the test target). Leaves the Dropbox typed
    /// accessor nil — Connect UI surfaces aren't reachable from tests.
    init(testingProvider: any SyncProvider) {
        self.dropbox = nil
        self.provider = testingProvider
    }
    #endif

    // MARK: - Demo lifecycle

    /// Enters demo preview. Refuses to clobber an in-flight authorize or an
    /// already-authorized session — both are real sessions and demo mode
    /// shouldn't silently take over. Sets `ManagerGate.demoBypass` so
    /// subsequent gated prompts (Settings, Manage) auto-pass for the
    /// reviewer.
    ///
    /// Intentionally does NOT call `ManagerGate.markFirstSetupComplete()` —
    /// entering demo doesn't count as setup, so if the user later taps
    /// Connect Dropbox the first-install bypass on that button still
    /// applies.
    func beginDemoSession() {
        guard let dropbox else {
            // Test path: no real provider to inspect, just enter demo.
            isDemo = true
            ManagerGate.demoBypass = true
            return
        }
        switch dropbox.authState {
        case .notAuthorized, .authFailed:
            isDemo = true
            ManagerGate.demoBypass = true
        case .authorizing, .authorized:
            break
        }
    }

    /// Leaves the demo preview. `ContentView` then routes back to the
    /// Connect screen. Clears the `ManagerGate` demo bypass so future
    /// prompts behave normally.
    func endDemoSession() {
        guard isDemo else { return }
        ManagerGate.demoBypass = false
        isDemo = false
    }

    // MARK: - CRUD forwarders
    //
    // Each method short-circuits with `SyncError.demoMode` when isDemo is
    // true — a defensive guard. Callers (TemplateStore, FormView) branch
    // on `isDemo` first and take an in-memory path; reaching one of these
    // throws indicates a missing demo branch in a caller, not a runtime
    // condition the user should see.

    func uploadSigned(_ pdfData: Data, filename: String) async throws -> UploadResult {
        if isDemo { throw SyncError.demoMode }
        return try await provider.uploadSigned(pdfData, filename: filename)
    }

    func listTemplates() async throws -> [TemplateRef] {
        if isDemo { throw SyncError.demoMode }
        return try await provider.listTemplates()
    }

    func downloadTemplate(at identifier: String) async throws -> Data {
        if isDemo { throw SyncError.demoMode }
        return try await provider.downloadTemplate(at: identifier)
    }

    @discardableResult
    func saveTemplate(_ data: Data, filename: String) async throws -> String {
        if isDemo { throw SyncError.demoMode }
        return try await provider.saveTemplate(data, filename: filename)
    }

    func deleteTemplate(at identifier: String) async throws {
        if isDemo { throw SyncError.demoMode }
        try await provider.deleteTemplate(at: identifier)
    }
}
