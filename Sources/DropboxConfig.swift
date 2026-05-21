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
            // `DropboxSyncProvider.authorize` instead of crashing at the splash
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

    /// OAuth scopes required: read+write within the folders the user picks.
    /// `files.content.read` implies `files.metadata.read` per Dropbox's scope
    /// model, so `list_folder`, `create_folder_v2`, and `delete_v2` work
    /// without an additional explicit grant. Combined with the Full-Dropbox
    /// permission type on the registered app (v1.1+), these scopes let the
    /// app read and write any folder the user navigates to via
    /// `ChooseDropboxFolderView`, including team-shared folders that mount
    /// in the user's namespace.
    static let scopes = ["files.content.write", "files.content.read"]

    // The legacy `templatesFolder` / `uploadFolder` constants were removed in
    // v1.1 — destination paths are now manager-overridable per install and
    // live on `AppSettings.dropboxTemplatesPath` / `dropboxSignedPath`.
}
