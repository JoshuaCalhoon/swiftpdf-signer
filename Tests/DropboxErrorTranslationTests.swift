import XCTest
@testable import SwiftPDF
@preconcurrency import SwiftyDropbox

/// Unit tests for `DropboxSyncProvider`'s pure error-translation helpers
/// (`isAuthFailure`, `unwrappedURLError`, `translatingNetworkErrors`,
/// `routeError`) and the user-facing copy in `ServiceError.errorDescription`.
///
/// The helpers are generic over the route error type `E`; tests pin `E` to
/// `Files.UploadError` to match the most-trafficked call site, but the
/// behavior under test does not depend on the route type.
final class DropboxErrorTranslationTests: XCTestCase {

    // MARK: - isAuthFailure

    func test_isAuthFailure_true_for_expired_access_token() {
        let error: CallError<Files.UploadError> = .authError(.expiredAccessToken, nil, nil, nil)
        XCTAssertTrue(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_true_for_invalid_access_token() {
        let error: CallError<Files.UploadError> = .authError(.invalidAccessToken, nil, nil, nil)
        XCTAssertTrue(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_true_for_user_suspended() {
        // The "user is no longer authorized" family — handled the same as
        // token expiry by the caller (drop credentials, route to Connect).
        let error: CallError<Files.UploadError> = .authError(.userSuspended, nil, nil, nil)
        XCTAssertTrue(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_true_for_oauth_clientError() {
        struct StubOAuth: Error {}
        let error: CallError<Files.UploadError> = .clientError(.oauthError(StubOAuth()))
        XCTAssertTrue(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_false_for_urlSession_clientError() {
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(URLError(.timedOut)))
        XCTAssertFalse(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_false_for_httpError() {
        let error: CallError<Files.UploadError> = .httpError(500, "internal server error", "request-id")
        XCTAssertFalse(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_false_for_serializationError() {
        struct StubDecoding: Error {}
        let error: CallError<Files.UploadError> = .serializationError(StubDecoding())
        XCTAssertFalse(DropboxSyncProvider.isAuthFailure(error))
    }

    func test_isAuthFailure_false_for_internalServerError() {
        let error: CallError<Files.UploadError> = .internalServerError(503, "unavailable", "request-id")
        XCTAssertFalse(DropboxSyncProvider.isAuthFailure(error))
    }

    // MARK: - unwrappedURLError

    func test_unwrappedURLError_returns_swift_URLError_directly() {
        let urlError = URLError(.notConnectedToInternet)
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(urlError))
        XCTAssertEqual(DropboxSyncProvider.unwrappedURLError(from: error)?.code, .notConnectedToInternet)
    }

    func test_unwrappedURLError_bridges_NSError_in_NSURLErrorDomain() {
        // SwiftyDropbox sometimes hands back an NSError-bridged URLError
        // (e.g. when the underlying URLSession surfaced its failure through
        // Objective-C bridging) — the helper must reconstruct the URLError.
        let ns = NSError(domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue, userInfo: nil)
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(ns))
        XCTAssertEqual(DropboxSyncProvider.unwrappedURLError(from: error)?.code, .timedOut)
    }

    func test_unwrappedURLError_returns_nil_for_unrelated_NSError() {
        // A non-URL error sneaking into the urlSessionError slot must not
        // be silently translated to a fabricated URLError.
        let ns = NSError(domain: "com.example.unrelated", code: 999, userInfo: nil)
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(ns))
        XCTAssertNil(DropboxSyncProvider.unwrappedURLError(from: error))
    }

    func test_unwrappedURLError_returns_nil_for_oauthError() {
        struct StubOAuth: Error {}
        let error: CallError<Files.UploadError> = .clientError(.oauthError(StubOAuth()))
        XCTAssertNil(DropboxSyncProvider.unwrappedURLError(from: error))
    }

    func test_unwrappedURLError_returns_nil_for_non_clientError() {
        let error: CallError<Files.UploadError> = .httpError(500, nil, nil)
        XCTAssertNil(DropboxSyncProvider.unwrappedURLError(from: error))
    }

    // MARK: - translatingNetworkErrors

    func test_translatingNetworkErrors_maps_urlSession_to_networkUnreachable() {
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(URLError(.timedOut)))
        let translated = DropboxSyncProvider.translatingNetworkErrors(error)
        guard case let DropboxSyncProvider.ServiceError.networkUnreachable(code) = translated else {
            return XCTFail("Expected ServiceError.networkUnreachable, got \(translated)")
        }
        XCTAssertEqual(code, .timedOut)
    }

    func test_translatingNetworkErrors_passes_through_non_network_callError() {
        let error: CallError<Files.UploadError> = .httpError(500, "internal", "req-1")
        let translated = DropboxSyncProvider.translatingNetworkErrors(error)
        // Pass-through: the same CallError comes back. Cast and pattern-match.
        guard let same = translated as? CallError<Files.UploadError>,
              case .httpError(let code, _, _) = same else {
            return XCTFail("Expected CallError.httpError pass-through, got \(translated)")
        }
        XCTAssertEqual(code, 500)
    }

    func test_translatingNetworkErrors_bridges_NSError_in_NSURLErrorDomain() {
        let ns = NSError(domain: NSURLErrorDomain, code: URLError.Code.networkConnectionLost.rawValue, userInfo: nil)
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(ns))
        let translated = DropboxSyncProvider.translatingNetworkErrors(error)
        guard case let DropboxSyncProvider.ServiceError.networkUnreachable(code) = translated else {
            return XCTFail("Expected ServiceError.networkUnreachable, got \(translated)")
        }
        XCTAssertEqual(code, .networkConnectionLost)
    }

    // MARK: - ServiceError.errorDescription mapping

    func test_serviceError_errorDescription_notAuthorized() {
        let error: DropboxSyncProvider.ServiceError = .notAuthorized
        XCTAssertEqual(error.errorDescription, "Dropbox is not connected")
    }

    func test_serviceError_errorDescription_offline() {
        let error: DropboxSyncProvider.ServiceError = .networkUnreachable(.notConnectedToInternet)
        XCTAssertEqual(
            error.errorDescription,
            "No internet connection. Connect to a network and try again."
        )
    }

    func test_serviceError_errorDescription_lost_connection() {
        let error: DropboxSyncProvider.ServiceError = .networkUnreachable(.networkConnectionLost)
        XCTAssertEqual(
            error.errorDescription,
            "The network connection was lost. Reconnect and try again."
        )
    }

    func test_serviceError_errorDescription_timeout() {
        let error: DropboxSyncProvider.ServiceError = .networkUnreachable(.timedOut)
        XCTAssertEqual(
            error.errorDescription,
            "The connection timed out. Try again once you have a stable network."
        )
    }

    func test_serviceError_errorDescription_dns_or_host_failures_share_copy() {
        // The three "can't reach the host" variants must share the same
        // user-facing copy — the user can't act differently on them.
        let expected = "Couldn't reach Dropbox. Check your network and try again."
        XCTAssertEqual(
            DropboxSyncProvider.ServiceError.networkUnreachable(.cannotConnectToHost).errorDescription,
            expected
        )
        XCTAssertEqual(
            DropboxSyncProvider.ServiceError.networkUnreachable(.cannotFindHost).errorDescription,
            expected
        )
        XCTAssertEqual(
            DropboxSyncProvider.ServiceError.networkUnreachable(.dnsLookupFailed).errorDescription,
            expected
        )
    }

    func test_serviceError_errorDescription_falls_back_to_generic_copy() {
        // Any URLError.Code not enumerated explicitly must produce the
        // generic "Network error" copy rather than nil or a debug-format
        // string. Picking a representative not-in-switch case.
        let error: DropboxSyncProvider.ServiceError = .networkUnreachable(.userCancelledAuthentication)
        XCTAssertEqual(
            error.errorDescription,
            "Network error. Check your connection and try again."
        )
    }

    func test_serviceError_folderAlreadyExists_quotes_the_leaf_name() {
        // The picker should show the manager "a folder named "X" already
        // exists here" — pulling the leaf from the full Dropbox path.
        let error: DropboxSyncProvider.ServiceError = .folderAlreadyExists(path: "/Warehouse/Signed Waivers")
        XCTAssertEqual(
            error.errorDescription,
            #"A folder named "Signed Waivers" already exists here. Pick a different name."#
        )
    }

    func test_serviceError_folderAlreadyExists_handles_root_relative_path() {
        // Top-level path: the leaf name is the only component after the
        // leading slash.
        let error: DropboxSyncProvider.ServiceError = .folderAlreadyExists(path: "/SwiftPDF")
        XCTAssertEqual(
            error.errorDescription,
            #"A folder named "SwiftPDF" already exists here. Pick a different name."#
        )
    }

    // MARK: - routeError
    //
    // The positive case (routeError → unbox the inner E) can't be tested at
    // unit-test scope: SwiftyDropbox's `Box<T>` initializer is `internal`,
    // so we can't synthesize a `CallError.routeError` in test code. The
    // negative case (every other CallError shape → nil) is testable and
    // catches the most likely regression (an accidental pattern-match
    // generalization that swallows non-routeError cases).

    func test_routeError_returns_nil_for_httpError() {
        let error: CallError<Files.UploadError> = .httpError(500, nil, nil)
        XCTAssertNil(DropboxSyncProvider.routeError(of: error))
    }

    func test_routeError_returns_nil_for_authError() {
        let error: CallError<Files.UploadError> = .authError(.invalidAccessToken, nil, nil, nil)
        XCTAssertNil(DropboxSyncProvider.routeError(of: error))
    }

    func test_routeError_returns_nil_for_clientError() {
        let error: CallError<Files.UploadError> = .clientError(.urlSessionError(URLError(.timedOut)))
        XCTAssertNil(DropboxSyncProvider.routeError(of: error))
    }
}
