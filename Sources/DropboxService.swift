import Foundation
import UIKit
@preconcurrency import SwiftyDropbox

@MainActor
@Observable
final class DropboxService {
    enum AuthState: Equatable {
        case notAuthorized
        case authorizing
        case authorized
        case authFailed(message: String)
    }

    private(set) var authState: AuthState = .notAuthorized

    init() {
        DropboxClientsManager.setupWithAppKey(DropboxConfig.appKey)
        if DropboxClientsManager.authorizedClient != nil {
            authState = .authorized
            // Covers app-relaunch with persisted credentials and
            // upgrade-from-prior-version: if we already have a client, we
            // are by definition past first setup, even if this is the first
            // launch under the gated-Connect-button code path.
            ManagerGate.markFirstSetupComplete()
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
                switch result {
                case .success:
                    self.authState = .authorized
                    // First successful authorize on this install. From here
                    // on, Connect Dropbox taps require ManagerGate.
                    ManagerGate.markFirstSetupComplete()
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

    /// Kicks off the in-app OAuth flow. Result arrives via `handleRedirect(_:)`.
    func authorize(from controller: UIViewController) {
        // Release builds with a missing/placeholder app key reach here with an
        // empty appKey (see `DropboxConfig.appKey`). Surface a clear error
        // instead of letting SwiftyDropbox produce an opaque failure.
        guard !DropboxConfig.appKey.isEmpty else {
            authState = .authFailed(message: "App is misconfigured — Dropbox App Key is missing. Contact IT.")
            return
        }
        authState = .authorizing
        let scopeRequest = ScopeRequest(
            scopeType: .user,
            scopes: DropboxConfig.scopes,
            includeGrantedScopes: false
        )
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: controller,
            loadingStatusDelegate: nil,
            openURL: { url in UIApplication.shared.open(url) },
            scopeRequest: scopeRequest
        )
    }

    /// Manual sign-out for testing or settings.
    func unauthorize() {
        DropboxClientsManager.unlinkClients()
        authState = .notAuthorized
        // We were authorized to be able to unauthorize — guarantee the
        // first-setup flag is set so the next Connect tap hits the gate.
        ManagerGate.markFirstSetupComplete()
    }

    /// Routes a ManagerGate failure into the same `authFailed` UI as Dropbox
    /// SDK errors. Used by `ConnectDropboxView` when the gate rejects a
    /// Connect attempt (cancelled biometric prompt, missing passcode).
    func surfaceAuthError(_ message: String) {
        authState = .authFailed(message: message)
    }

    /// Uploads the signed PDF; returns the canonical Dropbox path.
    /// Token-revoked / refresh-failure errors are surfaced as `ServiceError.notAuthorized`
    /// after clearing the local client — `ContentView` will then route back to `ConnectDropboxView`.
    func upload(_ pdfData: Data, filename: String) async throws -> String {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        let path = "\(DropboxConfig.uploadFolder)/\(filename)"
        do {
            let result = try await client.files
                .upload(path: path, mode: .add, autorename: true, input: pdfData)
                .response()
            return result.pathDisplay ?? path
        } catch let error as CallError<Files.UploadError> {
            if Self.isAuthFailure(error) {
                unauthorize()
                throw ServiceError.notAuthorized
            }
            throw error
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
                .listFolder(path: DropboxConfig.templatesFolder)
                .response()
            return result.entries.compactMap { entry in
                guard let file = entry as? Files.FileMetadata,
                      let path = file.pathLower,
                      file.name.hasSuffix(".json") else { return nil }
                return TemplateRef(name: file.name, path: path)
            }
        } catch let error as CallError<Files.ListFolderError> {
            if let route = Self.routeError(of: error),
               case .path(let lookup) = route,
               case .notFound = lookup {
                return []
            }
            if Self.isAuthFailure(error) {
                unauthorize()
                throw ServiceError.notAuthorized
            }
            throw error
        }
    }

    /// Downloads the raw JSON bytes for one template.
    func downloadTemplate(at path: String) async throws -> Data {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            let (_, data) = try await client.files
                .download(path: path)
                .response()
            return data
        } catch let error as CallError<Files.DownloadError> {
            if Self.isAuthFailure(error) {
                unauthorize()
                throw ServiceError.notAuthorized
            }
            throw error
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
        let path = "\(DropboxConfig.templatesFolder)/\(filename)"
        do {
            let result = try await client.files
                .upload(path: path, mode: .overwrite, autorename: false, input: data)
                .response()
            return result.pathDisplay ?? path
        } catch let error as CallError<Files.UploadError> {
            if Self.isAuthFailure(error) {
                unauthorize()
                throw ServiceError.notAuthorized
            }
            throw error
        }
    }

    /// Permanently deletes one template file from Dropbox.
    func deleteTemplate(at path: String) async throws {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw ServiceError.notAuthorized
        }
        do {
            _ = try await client.files
                .deleteV2(path: path)
                .response()
        } catch let error as CallError<Files.DeleteError> {
            if Self.isAuthFailure(error) {
                unauthorize()
                throw ServiceError.notAuthorized
            }
            throw error
        }
    }

    struct TemplateRef: Sendable, Equatable {
        let name: String   // e.g. "<uuid>.json"
        let path: String   // e.g. "/templates/<uuid>.json" (pathLower from Dropbox)
    }

    private static func isAuthFailure<E>(_ error: CallError<E>) -> Bool {
        if case .authError = error { return true }
        if case .clientError(let inner) = error, case .oauthError = inner { return true }
        return false
    }

    /// Extracts the unboxed route-specific error from a `CallError.routeError(...)`,
    /// or `nil` for any other case. Spares each call site the multi-level pattern match.
    private static func routeError<E>(of error: CallError<E>) -> E? {
        if case .routeError(let boxed, _, _, _) = error { return boxed.unboxed }
        return nil
    }

    enum ServiceError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Dropbox is not connected"
            }
        }
    }
}
