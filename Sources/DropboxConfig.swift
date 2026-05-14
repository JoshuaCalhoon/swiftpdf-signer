import Foundation

enum DropboxConfig {
    /// Public OAuth client identifier. Wired in via Configuration/Local.xcconfig →
    /// xcodegen-generated Info.plist → Bundle. Not a cryptographic secret (PKCE
    /// makes the key alone insufficient to impersonate), but gitignored as a habit.
    /// Returns a harmless placeholder in SwiftUI previews so the canvas doesn't crash.
    static let appKey: String = {
        if isPreviewMode { return "PREVIEW_PLACEHOLDER" }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DropboxAppKey") as? String,
              !raw.isEmpty,
              !raw.contains("REPLACE") else {
            #if DEBUG
            fatalError(
                """
                Missing or placeholder Dropbox App Key.
                Copy Configuration/Local.xcconfig.example → Configuration/Local.xcconfig,
                fill in DROPBOX_APP_KEY with the key from dropbox.com/developers/apps,
                then re-run `xcodegen generate`.
                """
            )
            #else
            // In a release build, returning "" lets the app launch and surface
            // a user-visible "App misconfigured" message in
            // `DropboxService.authorize` instead of crashing at the splash
            // screen. Worse UX than fixing the build, better UX than a silent
            // crash on a deployed iPad.
            return ""
            #endif
        }
        return raw
    }()

    private static var isPreviewMode: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Upload path relative to the app folder.
    /// With App-folder scope, "/Signed" maps to "/Apps/SwiftPDF/Signed" in the user's Dropbox.
    static let uploadFolder = "/Signed"

    /// Templates path relative to the app folder.
    /// "/Templates" maps to "/Apps/SwiftPDF/Templates" in the user's Dropbox.
    static let templatesFolder = "/Templates"

    /// OAuth scopes required: read+write within the app folder.
    /// `files.content.read` implies `files.metadata.read` per Dropbox's scope model,
    /// so `list_folder` and `delete_v2` work without an additional explicit grant.
    static let scopes = ["files.content.write", "files.content.read"]
}
