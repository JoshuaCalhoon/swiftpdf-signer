import Foundation
import UIKit
import SwiftyDropbox

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
        }
    }

    /// Routed from `App.onOpenURL` — completes the OAuth round-trip.
    func handleRedirect(_ url: URL) {
        _ = DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                authState = .authorized
            case .cancel, .none:
                authState = .notAuthorized
            case .error(_, let description):
                authState = .authFailed(message: description ?? "Authorization failed")
            @unknown default:
                authState = .notAuthorized
            }
        }
    }

    /// Kicks off the in-app OAuth flow. Result arrives via `handleRedirect(_:)`.
    func authorize(from controller: UIViewController) {
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

    private static func isAuthFailure(_ error: CallError<Files.UploadError>) -> Bool {
        if case .authError = error { return true }
        if case .clientError(let inner) = error, case .oauthError = inner { return true }
        return false
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
