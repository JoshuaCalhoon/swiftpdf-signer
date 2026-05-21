import Foundation
import UIKit
import os
@preconcurrency import SwiftyDropbox

@MainActor
@Observable
final class DropboxSyncProvider: SyncProvider {

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "swiftpdf",
        category: "DropboxSyncProvider"
    )

    /// Forces evaluation of `DropboxConfig.appKey` at app launch so a missing
    /// or placeholder key produces a clean stack trace at startup rather than
    /// at first Connect tap. In debug builds the static-let initializer
    /// fatalErrors with a fix-your-Local.xcconfig message. In release builds
    /// it returns "" and the existing guard in `authorize(from:)` surfaces a
    /// user-visible "App misconfigured" message.
    ///
    /// Shaped as a provider-scoped entry point (rather than a bare call on
    /// DropboxConfig) so `SwiftPDFApp.init` can dispatch by active-provider
    /// type once a second provider lands: each conformer owns its own
    /// launch-time configuration check. (audit ME-05 / Dx-7)
    nonisolated static func validateConfigurationAtLaunch() {
        _ = DropboxConfig.appKey
    }

    enum AuthState: Equatable {
        case notAuthorized
        case authorizing
        case authorized
        case authFailed(message: String)
    }

    private(set) var authState: AuthState = .notAuthorized

    /// Holds the active OAuth flow object while it's in flight. ASWebAuth
    /// won't keep the session alive on its own — if we release this before
    /// the callback fires, the auth sheet silently disappears. Cleared in
    /// `handleRedirect` (success or cancel) and on hard failure.
    private var authFlow: DropboxASWebAuthFlow?

    /// Source of truth for the manager-overridable destination paths in
    /// Dropbox (`dropboxTemplatesPath`, `dropboxSignedPath`). Injected
    /// rather than read off `.standard` so the provider can be exercised
    /// against a throwaway `AppSettings` in tests / previews. (v1.1)
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        DropboxClientsManager.setupWithAppKey(DropboxConfig.appKey)
        if DropboxClientsManager.authorizedClient != nil {
            authState = .authorized
            // Covers app-relaunch with persisted credentials and
            // upgrade-from-prior-version: if we already have a client, we
            // are by definition past first setup, even if this is the first
            // launch under the gated-Connect-button code path.
            ManagerGate.markFirstSetupComplete()
            // A persisted client under the CURRENT (Full-Dropbox) app key
            // means we're past v1.1 migration too — record so the Connect
            // screen drops the "Reconnect" framing on the next disconnect.
            ManagerGate.markFullDropboxLinked()
        }
    }

    /// Routed from `App.onOpenURL` — completes the OAuth round-trip.
    ///
    /// Belt-and-suspenders scheme check before handing the URL to the SDK:
    /// SwiftyDropbox's PKCE state validation is the actual security gate, but
    /// rejecting the URL here means an unrelated deep link can never even
    /// reach the SDK's callback, which keeps `.none` returns out of our state
    /// machine entirely.
    func handleRedirect(_ url: URL) {
        let expectedScheme = "db-\(DropboxConfig.appKey)"
        guard url.scheme?.caseInsensitiveCompare(expectedScheme) == .orderedSame else { return }

        _ = DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false) { result in
            // Hop explicitly onto MainActor — the SDK's callback contract
            // doesn't statically promise main-queue delivery, and on Swift 6
            // mode this would be an isolation violation.
            Task { @MainActor in
                // Release the flow object on every redirect resolution. On the
                // dauth path (Dropbox.app installed), authorize(from:)'s
                // onResult closure never fires because presentAuthChannel is
                // never invoked, so this is the only place the ivar gets
                // cleared. The ASWebAuth path also clears it in its own
                // closure (line ~118); the duplicate is intentional and
                // idempotent.
                self.authFlow = nil
                switch result {
                case .success:
                    self.authState = .authorized
                    // First successful authorize on this install. From here
                    // on, Connect Dropbox taps require ManagerGate.
                    ManagerGate.markFirstSetupComplete()
                    // First successful authorize under the v1.1 key.
                    // Retires the migration-framed Connect copy from any
                    // future Disconnect/Reconnect within this install.
                    ManagerGate.markFullDropboxLinked()
                case .cancel:
                    // User backed out of the OAuth screen. Reset to the
                    // connect-prompt state.
                    self.authState = .notAuthorized
                case .none:
                    // The SDK didn't recognize the URL (e.g. an unrelated
                    // deep link). Leave authState untouched — we shouldn't
                    // have gotten here given the scheme guard above, but
                    // belt-and-suspenders.
                    break
                case .error(_, let description):
                    self.authState = .authFailed(message: description ?? "Authorization failed")
                @unknown default:
                    break
                }
            }
        }
    }

    /// Kicks off the in-app OAuth flow.
    ///
    /// - Dauth path (Dropbox.app installed): the SDK detects the
    ///   `dbapi-2`/`dbapi-8-emm` scheme via `canPresentExternalApp` and hands
    ///   off to the Dropbox app for one-tap consent. Result comes back via
    ///   `onOpenURL` → `handleRedirect(_:)`.
    /// - Web path (Dropbox.app not installed): the SDK falls through to our
    ///   `DropboxASWebAuthFlow.presentAuthChannel`, which presents an
    ///   `ASWebAuthenticationSession` with an ephemeral cookie jar. Result
    ///   comes back through the closure passed to `DropboxASWebAuthFlow`.
    ///
    /// The web path replaces the SDK's default `SFSafariViewController` so
    /// (a) OAuth UI stays clearly in-app for App Review Guideline 4 and
    /// (b) ephemeral cookies sidestep Guideline 5.1.2(i) — no tracking
    /// across contexts, no ATT prompt required.
    func authorize(from controller: UIViewController) {
        // Release builds with a missing/placeholder app key reach here with an
        // empty appKey (see `DropboxConfig.appKey`). Surface a clear error
        // instead of letting SwiftyDropbox produce an opaque failure.
        guard !DropboxConfig.appKey.isEmpty else {
            authState = .authFailed(message: "App is misconfigured: Dropbox App Key is missing. Contact IT.")
            return
        }
        authState = .authorizing
        let scopeRequest = ScopeRequest(
            scopeType: .user,
            scopes: DropboxConfig.scopes,
            includeGrantedScopes: false
        )
        let flow = DropboxASWebAuthFlow(presenting: controller) { [weak self] result in
            // Captured weak: the provider outlives the flow in practice
            // (it's owned by SyncCoordinator), but the flow is retained
            // here only for the lifetime of the auth attempt.
            guard let self else { return }
            switch result {
            case .redirected(let url):
                // Same code path as a redirect via onOpenURL — single source
                // of truth for cancel/success/error decoding.
                self.handleRedirect(url)
            case .failed(let message):
                self.authState = .authFailed(message: message)
            }
            self.authFlow = nil
        }
        self.authFlow = flow
        // Drive the SDK with our custom SharedApplication. The OAuth manager
        // tries dauth first (via `checkAndPresentPlatformSpecificAuth`) and
        // falls through to our `presentAuthChannel` for the web flow.
        DropboxOAuthManager.sharedOAuthManager.authorizeFromSharedApplication(
            flow,
            usePKCE: true,
            scopeRequest: scopeRequest
        )
    }

    /// Manual sign-out for testing or settings.
    ///
    /// Contract: "fully disconnect." Both the local credential cache AND the
    /// server-side authorization must end here, so the privacy policy's
    /// "removal" wording holds end-to-end. Future `SyncProvider` conformers
    /// (Google Drive, iCloud, NAS) should follow the same shape — revoke
    /// server-side authorization via the provider's own endpoint, then
    /// clear local credentials.
    ///
    /// Async (v1.1) so the revoke completes (or times out) BEFORE the local
    /// teardown and any subsequent OAuth attempt. The prior fire-and-forget
    /// design left the revoke's HTTP request racing on SwiftyDropbox's
    /// shared NetworkSession while the user was already tapping Reconnect;
    /// in that window, `ASWebAuthenticationSession.start()` returned `false`
    /// repeatedly until the revoke finished, surfacing as "Couldn't open the
    /// Dropbox sign-in page" until the user gave up and restarted the app.
    /// Sequencing the revoke ahead of the local cleanup eliminates the race.
    func unauthorize() async {
        // Best-effort server-side revoke before tearing down the local
        // client. Capture the authorized client now so the request body
        // doesn't lose its auth context when unlinkClients() wipes the SDK's
        // in-memory pointer. Bounded by a 2-second timeout so a slow /
        // failed network can't freeze the UI:
        //
        //   - If the call succeeds, Dropbox's server-side token dies
        //     immediately and the privacy policy's "removal" claim holds.
        //   - If the call fails or times out, local cleanup proceeds
        //     anyway. State is the same as the pre-revoke behavior: token
        //     continues server-side until expiration. No regression on
        //     failure.
        //
        // The revoke endpoint disables both the access token and its parent
        // refresh token (per Dropbox API docs) — one call kills the whole
        // session.
        if let client = DropboxClientsManager.authorizedClient {
            await Self.bestEffortRevoke(client: client, timeout: .seconds(2))
        }
        DropboxClientsManager.unlinkClients()
        authState = .notAuthorized
        // Wipe the manager's auth grace window. Without this, a customer who
        // takes the iPad within the 30-second `graceWindow` after the manager
        // disconnects could tap Connect and reach OAuth without a fresh
        // Face ID prompt — letting them link their own cloud account on the
        // manager-handoff path.
        ManagerGate.invalidate()
        // Idempotent belt-and-suspenders. Every realistic path that lands
        // authState = .authorized already sets this flag (init when an
        // existing client is found in the SDK store; handleRedirect.success
        // after first OAuth lands). The write here defends a future code
        // path that lands `.authorized` without going through handleRedirect
        // — without it, such a path would leave the kiosk Connect-button
        // bypass armed after disconnect. The cost is one UserDefaults
        // write; the cost of being wrong is the kiosk threat re-opening.
        // (audit HI-04 / Dx-3)
        ManagerGate.markFirstSetupComplete()
    }

    /// TaskGroup race between the revoke call and a sleep timeout — whichever
    /// finishes first wins, the other is cancelled. Non-isolated because the
    /// underlying SDK request is a network call; staying off MainActor lets
    /// it suspend without blocking UI even though the surrounding method is
    /// @MainActor-isolated. (v1.1)
    nonisolated private static func bestEffortRevoke(
        client: DropboxClient,
        timeout: Duration
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    _ = try await client.auth.tokenRevoke().response()
                    logger.info("token revoked server-side on disconnect")
                } catch {
                    logger.warning("token revoke failed: \(error.localizedDescription, privacy: .private)")
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Routes a ManagerGate failure into the same `authFailed` UI as Dropbox
    /// SDK errors. Used by `ConnectDropboxView` when the gate rejects a
    /// Connect attempt (cancelled biometric prompt, missing passcode).
    func surfaceAuthError(_ message: String) {
        authState = .authFailed(message: message)
    }

    /// Uploads the signed PDF; returns the canonical Dropbox path and a
    /// `wasAutorenamed` flag set when Dropbox renamed the upload to avoid a
    /// sibling collision. Token-revoked / refresh-failure errors are
    /// surfaced as `ServiceError.notAuthorized` after clearing the local
    /// client — `ContentView` will then route back to `ConnectDropboxView`.
    ///
    /// The autorename detection lives here because the comparison rules are
    /// Dropbox-specific: Dropbox stores paths in canonical NFC and matches
    /// case-insensitively, so a signer name with combining characters or
    /// mixed case round-trips as a normalized path. Without normalization
    /// the raw compare would falsely flag every Unicode-named upload.
    func uploadSigned(_ pdfData: Data, filename: String) async throws -> UploadResult {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        let requestedPath = "\(settings.dropboxSignedPath)/\(filename)"
        do {
            let response = try await client.files
                .upload(path: requestedPath, mode: .add, autorename: true, input: pdfData)
                .response()
            let resolvedPath = response.pathDisplay ?? requestedPath
            let resolvedKey = resolvedPath.precomposedStringWithCanonicalMapping
            let requestedKey = requestedPath.precomposedStringWithCanonicalMapping
            let wasAutorenamed = resolvedKey.caseInsensitiveCompare(requestedKey) != .orderedSame
            return UploadResult(path: resolvedPath, wasAutorenamed: wasAutorenamed)
        } catch let error as CallError<Files.UploadError> {
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    /// Lists `.json` files in the Templates folder. Treats "folder not found" as
    /// an empty list — the folder gets created automatically on first upload.
    func listTemplates() async throws -> [TemplateRef] {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            let result = try await client.files
                .listFolder(path: settings.dropboxTemplatesPath)
                .response()
            return result.entries.compactMap { entry in
                guard let file = entry as? Files.FileMetadata,
                      let path = file.pathLower,
                      file.name.hasSuffix(".json") else { return nil }
                return TemplateRef(name: file.name, identifier: path)
            }
        } catch let error as CallError<Files.ListFolderError> {
            if let route = Self.routeError(of: error),
               case .path(let lookup) = route,
               case .notFound = lookup {
                return []
            }
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    /// Downloads the raw JSON bytes for one template.
    func downloadTemplate(at identifier: String) async throws -> Data {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            let (_, data) = try await client.files
                .download(path: identifier)
                .response()
            return data
        } catch let error as CallError<Files.DownloadError> {
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    /// Creates or overwrites a template at /Templates/{filename}.
    /// Mode `.overwrite` so an edit-and-save round-trip updates in place rather
    /// than creating "template (1).json" siblings.
    @discardableResult
    func saveTemplate(_ data: Data, filename: String) async throws -> String {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        let path = "\(settings.dropboxTemplatesPath)/\(filename)"
        do {
            let result = try await client.files
                .upload(path: path, mode: .overwrite, autorename: false, input: data)
                .response()
            return result.pathDisplay ?? path
        } catch let error as CallError<Files.UploadError> {
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    // MARK: - Folder picker (v1.1)

    /// Lists folder entries (sub-folders only, not files) at the given
    /// Dropbox path. Used by `ChooseDropboxFolderView` to render the next
    /// level of the picker tree.
    ///
    /// - `path == ""` lists the user's Dropbox root.
    /// - A path that doesn't exist returns an empty list, NOT an error —
    ///   the picker handles "no subfolders here" the same as "this path
    ///   doesn't exist yet" by offering "Create folder here."
    /// - Pagination is intentionally not handled in v1; the SDK returns
    ///   up to 2000 entries per call which covers typical SwiftPDF use
    ///   cases (warehouse folders rarely exceed a few dozen siblings). A
    ///   future pagination pass would loop on the SDK's `listFolderContinue`
    ///   cursor.
    func listFolder(at path: String) async throws -> [DropboxFolderEntry] {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            let result = try await client.files
                .listFolder(path: path)
                .response()
            return result.entries.compactMap { entry in
                guard let folder = entry as? Files.FolderMetadata else { return nil }
                return DropboxFolderEntry(
                    name: folder.name,
                    path: folder.pathDisplay ?? "\(path)/\(folder.name)"
                )
            }
        } catch let error as CallError<Files.ListFolderError> {
            if let route = Self.routeError(of: error),
               case .path(let lookup) = route,
               case .notFound = lookup {
                return []
            }
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    /// Creates a new folder at the given absolute Dropbox path. Returns the
    /// folder's metadata for the picker to navigate into. A
    /// `ServiceError.folderAlreadyExists` is thrown when a folder of that
    /// name is already present at the parent path — the picker surfaces
    /// this distinctly from a network or auth error so the user sees a
    /// helpful "that name's already taken" hint rather than a generic
    /// failure banner.
    func createFolder(at path: String) async throws -> DropboxFolderEntry {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            let result = try await client.files
                .createFolderV2(path: path)
                .response()
            return DropboxFolderEntry(
                name: result.metadata.name,
                path: result.metadata.pathDisplay ?? path
            )
        } catch let error as CallError<Files.CreateFolderError> {
            if let route = Self.routeError(of: error),
               case .path(let writeError) = route,
               case .conflict = writeError {
                throw ServiceError.folderAlreadyExists(path: path)
            }
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    /// Permanently deletes one template file from Dropbox.
    func deleteTemplate(at identifier: String) async throws {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            _ = try await client.files
                .deleteV2(path: identifier)
                .response()
        } catch let error as CallError<Files.DeleteError> {
            if Self.isAuthFailure(error) {
                await unauthorize()
                throw ServiceError.notAuthorized
            }
            throw Self.translatingNetworkErrors(error)
        }
    }

    // The four helpers below are `internal` (not `private`) so the test target
    // can exercise the CallError → ServiceError mapping table directly via
    // `@testable import SwiftPDF`. They're `nonisolated` because they're pure
    // functions over CallError shapes — no MainActor-isolated state — so the
    // tests don't need to hop onto the main actor just to call them. (audit
    // TC-01)
    nonisolated static func isAuthFailure<E>(_ error: CallError<E>) -> Bool {
        if case .authError = error { return true }
        if case .clientError(let inner) = error, case .oauthError = inner { return true }
        return false
    }

    /// Extracts the unboxed route-specific error from a `CallError.routeError(...)`,
    /// or `nil` for any other case. Spares each call site the multi-level pattern match.
    nonisolated static func routeError<E>(of error: CallError<E>) -> E? {
        if case .routeError(let boxed, _, _, _) = error { return boxed.unboxed }
        return nil
    }

    /// SwiftyDropbox wraps URLSession failures (offline, timeout, DNS, etc.)
    /// as `CallError.clientError(.urlSessionError(URLError))`. Unwrap that
    /// shape so each call site can translate to a user-facing
    /// `ServiceError.networkUnreachable` instead of throwing a CallError
    /// whose `localizedDescription` is the SDK's debug format.
    ///
    /// The inner error may be a Swift `URLError` directly or an NSError
    /// bridged from one (URLError bridges to `NSURLErrorDomain`). Both
    /// shapes occur in practice depending on which underlying API path
    /// produced the failure.
    nonisolated static func unwrappedURLError<E>(from error: CallError<E>) -> URLError? {
        guard case .clientError(let clientError) = error,
              case .urlSessionError(let inner) = clientError else { return nil }
        if let urlError = inner as? URLError { return urlError }
        let ns = inner as NSError
        if ns.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: ns.code))
        }
        return nil
    }

    /// Replaces a CallError carrying a URLSession failure with a
    /// `ServiceError.networkUnreachable` so the resulting
    /// `localizedDescription` is the action-oriented copy from
    /// `ServiceError.errorDescription`. Non-network CallErrors pass through
    /// unchanged.
    nonisolated static func translatingNetworkErrors<E>(_ error: CallError<E>) -> Error {
        if let urlError = unwrappedURLError(from: error) {
            return ServiceError.networkUnreachable(urlError.code)
        }
        return error
    }

    enum ServiceError: LocalizedError, Equatable {
        case notAuthorized
        /// A URLSession failure surfaced through `DropboxSyncProvider` — usually
        /// offline, network lost, DNS unreachable, or timed-out. The wrapped
        /// `URLError.Code` lets the caller distinguish if needed, but the
        /// default `errorDescription` is sufficient for failure banners.
        case networkUnreachable(URLError.Code)
        /// `createFolder(at:)` hit a sibling with the same name. The picker
        /// surfaces this distinctly so the user sees "that name's already
        /// taken at this location" instead of a generic failure banner.
        case folderAlreadyExists(path: String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Dropbox is not connected"
            case .networkUnreachable(let code):
                switch code {
                case .notConnectedToInternet:
                    return "No internet connection. Connect to a network and try again."
                case .networkConnectionLost:
                    return "The network connection was lost. Reconnect and try again."
                case .timedOut:
                    return "The connection timed out. Try again once you have a stable network."
                case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    return "Couldn't reach Dropbox. Check your network and try again."
                default:
                    return "Network error. Check your connection and try again."
                }
            case .folderAlreadyExists(let path):
                let name = (path as NSString).lastPathComponent
                return "A folder named \"\(name)\" already exists here. Pick a different name."
            }
        }
    }
}

/// One folder entry returned by `DropboxSyncProvider.listFolder(at:)`.
/// `name` is the leaf display name (just "Templates"); `path` is the full
/// Dropbox path (`/SwiftPDF/Templates`) that the picker passes back to
/// `listFolder` when the user descends into the folder.
struct DropboxFolderEntry: Sendable, Equatable, Identifiable {
    let name: String
    let path: String
    /// SwiftUI `List` / `ForEach` identity. Path is unique within a Dropbox
    /// account, so it's a safe identifier even when two folders share a name
    /// at different depths.
    var id: String { path }
}
