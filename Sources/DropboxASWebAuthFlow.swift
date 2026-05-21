import Foundation
import UIKit
import AuthenticationServices
@preconcurrency import SwiftyDropbox

/// `SharedApplication` conformer that drives the Dropbox OAuth *web* flow
/// through `ASWebAuthenticationSession` instead of the SDK's default
/// `MobileSafariViewController` (an `SFSafariViewController` subclass).
///
/// Why this exists:
/// - App Review Guideline 4: keeps OAuth UI in-app rather than bouncing the
///   user to the system browser. ASWebAuth presents a system-managed sheet
///   that visually belongs to our app.
/// - App Review Guideline 5.1.2(i): `prefersEphemeralWebBrowserSession = true`
///   means the OAuth session uses a fresh cookie jar that is destroyed on
///   dismiss. Dropbox's cookies can't be re-read by anything else and can't
///   be used to track the user across contexts, so the AppTrackingTransparency
///   prompt isn't needed.
///
/// Scope of replacement:
/// - The dauth (Dropbox.app handoff) path is **left intact** —
///   `canPresentExternalApp(_:)` still delegates to
///   `UIApplication.canOpenURL`, so users who have the Dropbox app installed
///   keep the one-tap login experience.
/// - ASWebAuth only takes over when the Dropbox app is *not* installed
///   (the SDK's `checkAndPresentPlatformSpecificAuth` returns false, then
///   `authorizeFromSharedApplication` falls through to `presentAuthChannel`,
///   which is the method we override here).
///
/// Isolation: marked `@MainActor` because every method here touches UIKit
/// (`UIApplication`, `UIAlertController`) or `ASWebAuthenticationSession`,
/// all of which are main-actor types. SwiftyDropbox is imported with
/// `@preconcurrency` so we can conform to its non-isolated
/// `SharedApplication` protocol without each method explicitly hopping.
/// In practice the SDK calls these methods from the main thread (the auth
/// flow starts there and never leaves it for UI-presenting work).
@MainActor
final class DropboxASWebAuthFlow: NSObject, @preconcurrency SharedApplication {

    /// The result delivered to `DropboxSyncProvider` once the OAuth flow
    /// resolves. `.redirected` wraps a `db-{appKey}://...` URL that the
    /// SDK's `handleRedirectURL` can decode (success token, cancel, or
    /// error are all expressed as redirect URLs by Dropbox). `.failed` is
    /// reserved for ASWebAuth-level failures that don't produce a redirect
    /// URL — e.g. the system failing to present the auth sheet at all.
    enum Result {
        case redirected(URL)
        case failed(message: String)
    }

    private weak var presentingController: UIViewController?
    private let onResult: (Result) -> Void

    /// Retained for the lifetime of the auth flow — `ASWebAuthenticationSession`
    /// deallocates and silently fails if its owner drops the reference before
    /// the callback fires.
    private var webAuthSession: ASWebAuthenticationSession?

    /// The cancel-handler closure the SDK hands us in `presentAuthChannel`.
    /// We stash it so the ASWebAuth completion block can call it on user
    /// cancellation — that closure synthesizes a `db-{key}://2/cancel`
    /// redirect URL and routes it through `presentExternalApp`, which is the
    /// shape the SDK's state machine expects for a cancelled flow.
    private var pendingCancelHandler: (() -> Void)?

    /// The OAuth URL the SDK handed us in `presentAuthChannel`. Held so
    /// `finishWebAuthSession` can re-attempt presentation if iOS returns
    /// `presentationContextInvalid` (error 3) — which it does on Face ID
    /// → ASWebAuth transitions even when our scene reports
    /// `.foregroundActive` with a key window. (v1.1)
    private var pendingAuthURL: URL?

    /// Number of remaining error-3 retries for the current authentication
    /// attempt. Resets per `presentAuthChannel` call.
    private var presentationContextRetriesRemaining = 0

    /// Number of attempts we'll re-issue `session.start()` after iOS
    /// surfaces `presentationContextInvalid`. Each retry waits ~800ms.
    /// Empirical cap — Josh's test device needed "a few" before iOS
    /// accepted the anchor; 3 covers the observed worst case with margin.
    private static let presentationContextRetryLimit = 3

    init(
        presenting controller: UIViewController,
        onResult: @escaping (Result) -> Void
    ) {
        self.presentingController = controller
        self.onResult = onResult
        super.init()
    }

    // MARK: - SharedApplication

    func presentErrorMessage(_ message: String, title: String) {
        // The SDK calls this on terminal errors (e.g. missing
        // LSApplicationQueriesSchemes for the dauth path) and then returns
        // without falling through to presentAuthChannel. If we don't terminate
        // the flow here, DropboxSyncProvider.authState stays .authorizing and
        // the Connect screen hangs until the user force-quits the app.
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.onResult(.failed(message: message))
        })
        presentingController?.present(alert, animated: true)
    }

    func presentErrorMessageWithHandlers(
        _ message: String,
        title: String,
        buttonHandlers: [String: () -> Void]
    ) {
        // Cancel terminates the flow (same shape as user cancellation in
        // ASWebAuth — caller sees .failed). Retry stays inside the SDK's
        // state machine; the SDK will either re-enter via presentAuthChannel
        // or surface another error through this same path.
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            buttonHandlers["Cancel"]?()
            self?.onResult(.failed(message: message))
        })
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
            buttonHandlers["Retry"]?()
        })
        presentingController?.present(alert, animated: true)
    }

    /// Always returns `false`. The SDK's `DropboxMobileOAuthManager` runs its
    /// dauth check *before* asking us about platform-specific auth, so the
    /// Dropbox-app handoff still happens when applicable (via `presentExternalApp`).
    /// This hook is the SDK's escape valve for other custom platform auth
    /// (e.g. team SSO on macOS); we don't use it.
    func presentPlatformSpecificAuth(_ authURL: URL) -> Bool {
        false
    }

    /// SDK's web-flow entry point — invoked when the Dropbox app isn't
    /// available and the SDK needs to present the OAuth web page.
    ///
    /// `tryIntercept` is the SDK's mechanism for the embedded
    /// `SFSafariViewController` to detect when the web view navigates to a
    /// redirect URL and re-open it externally so it routes back through
    /// `onOpenURL`. ASWebAuth handles redirect interception natively via
    /// its `callbackURLScheme` parameter, so we ignore `tryIntercept`
    /// entirely — the callback URL arrives directly in our completion block.
    func presentAuthChannel(
        _ authURL: URL,
        tryIntercept: @escaping ((URL) -> Bool),
        cancelHandler: @escaping (() -> Void)
    ) {
        pendingCancelHandler = cancelHandler
        pendingAuthURL = authURL
        presentationContextRetriesRemaining = Self.presentationContextRetryLimit
        startSession(url: authURL, retryAllowed: true)
    }

    /// Constructs and starts an ASWebAuth session. On a `start()` failure,
    /// retries once after a short delay if `retryAllowed` is true.
    ///
    /// session.start() returning false on the first reconnect-after-disconnect
    /// attempt is the documented pattern of iOS-level ASWebAuth state retention
    /// from the prior session not yet being cleared. A single 500ms retry
    /// reliably clears that window in practice. The primary fix for the
    /// underlying race (the previously fire-and-forget tokenRevoke racing
    /// with the next OAuth on SwiftyDropbox's shared NetworkSession) is in
    /// `DropboxSyncProvider.unauthorize()`; this retry is the
    /// belt-and-suspenders against any remaining iOS quirk. (v1.1)
    private func startSession(url: URL, retryAllowed: Bool) {
        let callbackScheme = "db-\(DropboxConfig.appKey)"
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            // ASWebAuth's completion docs guarantee main-thread delivery,
            // but Swift 6 sees a non-isolated @Sendable closure here. Hop
            // through `MainActor.assumeIsolated` rather than spawning a
            // Task so the resolution is synchronous and we don't race a
            // user retap of "Connect" while the cancel state is in flight.
            MainActor.assumeIsolated {
                self?.finishWebAuthSession(callbackURL: callbackURL, error: error)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        webAuthSession = session

        if !session.start() {
            webAuthSession = nil
            if retryAllowed {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.startSession(url: url, retryAllowed: false)
                }
            } else {
                // System refused to present the auth sheet twice. Surface
                // as a hard failure so the user sees something actionable
                // rather than a stuck spinner.
                pendingCancelHandler = nil
                onResult(.failed(message: "Couldn't open the Dropbox sign-in page. Try again."))
            }
        }
    }

    func presentExternalApp(_ url: URL) {
        // Two callers in the SDK flow:
        //   1. Dauth path: open the Dropbox app via its custom URL scheme.
        //      `UIApplication.shared.open` is the right call.
        //   2. Cancel URL: the SDK synthesizes `db-{appKey}://2/cancel` and
        //      asks us to open it. Routing through UIApplication round-trips
        //      it via `onOpenURL` → `handleRedirect` → SDK cancel handling.
        // Both want the same plain open call.
        //
        // Failure path: iOS can refuse to open the URL (e.g. Dropbox.app
        // uninstalled between canPresentExternalApp and the open call, MDM
        // restriction). Without surfacing the failure, the flow stays on
        // .authorizing and the Connect screen hangs — same family as CR-01.
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            // Apple documents the completion as main-thread but the closure
            // is non-isolated to the compiler — match the assumeIsolated
            // pattern used by the ASWebAuth completion above.
            MainActor.assumeIsolated {
                guard let self, !success else { return }
                self.onResult(.failed(message: "Couldn't open Dropbox to continue sign-in. Try again."))
            }
        }
    }

    func canPresentExternalApp(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    func presentLoading() {
        // ASWebAuth shows its own spinner during page load. The PKCE token
        // exchange after the redirect happens fast enough that an extra
        // loading affordance from us would just flash and disappear; our
        // `DropboxSyncProvider.authState == .authorizing` already covers
        // the Connect screen during this window.
    }

    func dismissLoading() {
        // Paired no-op (see presentLoading).
    }

    // MARK: - Private

    private func finishWebAuthSession(callbackURL: URL?, error: Error?) {
        webAuthSession = nil

        if let callbackURL {
            pendingAuthURL = nil
            pendingCancelHandler = nil
            onResult(.redirected(callbackURL))
            return
        }

        // No callback URL means either user cancellation or a presentation
        // failure. Distinguish by inspecting the ASWebAuth error code so the
        // user sees an appropriate state (`.notAuthorized` vs `.authFailed`).
        let nsError = error as NSError?
        let isASWebAuthError = nsError?.domain == ASWebAuthenticationSessionError.errorDomain

        if isASWebAuthError,
           nsError?.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            // Route through the SDK's cancel handler so the state machine
            // sees the cancel via the same code path as a real cancel URL.
            let cancel = pendingCancelHandler
            pendingAuthURL = nil
            pendingCancelHandler = nil
            cancel?()
            return
        }

        // error 3 / presentationContextInvalid: iOS rejected the anchor as
        // not in a foreground scene, even though our scene reports
        // `.foregroundActive` with a key window. Empirically this happens
        // on the post-Face-ID Connect flow and self-corrects after one or
        // more re-attempts. Retry with the same URL up to
        // `presentationContextRetryLimit` times before surfacing. (v1.1)
        if isASWebAuthError,
           nsError?.code == ASWebAuthenticationSessionError.presentationContextInvalid.rawValue,
           let url = pendingAuthURL,
           presentationContextRetriesRemaining > 0 {
            presentationContextRetriesRemaining -= 1
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.startSession(url: url, retryAllowed: false)
            }
            return
        }

        let message = error?.localizedDescription ?? "Authorization failed"
        pendingAuthURL = nil
        pendingCancelHandler = nil
        onResult(.failed(message: message))
    }
}

extension DropboxASWebAuthFlow: ASWebAuthenticationPresentationContextProviding {
    /// Resolves the window iOS should anchor the OAuth sheet to. iOS rejects
    /// anchors that aren't in a foreground-active scene (`error 3 /
    /// presentationContextInvalid`), so the fallback chain prefers the
    /// active scene's key window. Returning an empty `ASPresentationAnchor()`
    /// (the prior worst-case fallback) was always doomed to be rejected;
    /// the hardened chain below at least returns a real window when ANY
    /// scene has one, even if conditions aren't perfect. (v1.1)
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // Best: foreground-active scene's key window. The scene state that
        // iOS actually requires for a valid presentation context.
        if let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow) {
            return window
        }

        // Good: any foreground scene's key window. Covers the
        // foreground-inactive transition window right after a Face ID
        // dismiss — iOS will likely still reject, but at minimum it's a
        // real window and the system error path is clearer than the empty
        // anchor case.
        if let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }

        // Last resort: ANY non-hidden window. Better than the empty anchor
        // because at least we're handing the system a real UIWindow.
        if let window = scenes.flatMap(\.windows).first(where: { !$0.isHidden }) {
            return window
        }

        // Genuinely no window — should not be reachable in a running iOS
        // app. The empty anchor will get rejected; surface helps debugging.
        return ASPresentationAnchor()
    }
}
