import SwiftUI
import UIKit
import os

/// Per-install configurable settings, persisted to `UserDefaults` and surfaced
/// through `SettingsView` (gated by `ManagerGate`).
///
/// v1 only carries the brand accent color. Future knobs (header defaults, time
/// zone override, etc.) drop in alongside — `@Observable` means consumers
/// re-render automatically when any tracked property changes.
@MainActor
@Observable
final class AppSettings {
    /// Hex string `#RRGGBB`. Source of truth — the `Color` / `UIColor`
    /// accessors decode this on read. Stored as a string so it round-trips
    /// through `UserDefaults` without needing a custom archiver.
    var brandColorHex: String {
        didSet {
            guard brandColorHex != oldValue else { return }
            defaults.set(brandColorHex, forKey: Self.brandColorKey)
        }
    }

    /// Header default values for newly-created templates. Empty strings fall
    /// back to "Your Company / Your Location / Your Department" placeholders
    /// at render time, so a fresh install still shows something sensible
    /// before a manager configures real values.
    var companyName: String {
        didSet {
            guard companyName != oldValue else { return }
            defaults.set(companyName, forKey: Self.companyNameKey)
        }
    }

    var companyLocation: String {
        didSet {
            guard companyLocation != oldValue else { return }
            defaults.set(companyLocation, forKey: Self.companyLocationKey)
        }
    }

    var companyDepartment: String {
        didSet {
            guard companyDepartment != oldValue else { return }
            defaults.set(companyDepartment, forKey: Self.companyDepartmentKey)
        }
    }

    /// Absolute Dropbox path where the app reads and writes JSON templates.
    /// Required to be a leading-slash path; the picker enforces shape on
    /// write. Defaults to `/SwiftPDF/Templates` at the user's Dropbox root —
    /// discoverable, top-level, doesn't collide with the legacy
    /// `/Apps/SwiftPDF/...` layout left over from the v1.0 app-folder Dropbox
    /// app (those folders aren't touched by v1.1; users moving content over
    /// do so manually via dropbox.com per the cheap-migration decision).
    var dropboxTemplatesPath: String {
        didSet {
            guard dropboxTemplatesPath != oldValue else { return }
            defaults.set(dropboxTemplatesPath, forKey: Self.dropboxTemplatesPathKey)
        }
    }

    /// Absolute Dropbox path where signed PDFs land. Same shape rules and
    /// migration story as `dropboxTemplatesPath`. The two paths are
    /// independent — managers commonly route signed documents into a folder
    /// shared with Warehousing / HR while templates live in a manager-only
    /// folder.
    var dropboxSignedPath: String {
        didSet {
            guard dropboxSignedPath != oldValue else { return }
            defaults.set(dropboxSignedPath, forKey: Self.dropboxSignedPathKey)
        }
    }

    /// Whether the manager has dismissed the first-connection folder-setup
    /// sheet. `false` until the manager either picks custom paths or taps
    /// Done to accept defaults — then `true` for the lifetime of the
    /// install. Drives one-shot presentation in `ContentView` so a routine
    /// reconnect doesn't re-prompt for folders the manager already
    /// configured. (v1.1)
    var hasCompletedFolderSetup: Bool {
        didSet {
            guard hasCompletedFolderSetup != oldValue else { return }
            defaults.set(hasCompletedFolderSetup, forKey: Self.hasCompletedFolderSetupKey)
        }
    }

    /// JPEG-encoded company logo. In-memory mirror of an on-disk file at
    /// `Documents/companyLogo.jpg` with `NSURLIsExcludedFromBackupKey` set —
    /// the bytes are kept out of iOS and iCloud backups so a company logo
    /// (which the privacy policy promises doesn't get uploaded anywhere)
    /// isn't silently exfiltrated via the user's iCloud account. The setter
    /// expects already-compressed bytes — callers should run images through
    /// `compressLogoForStorage(_:)` first so a multi-megabyte `PhotosPicker`
    /// payload doesn't end up on disk.
    var companyLogoData: Data? {
        didSet {
            guard companyLogoData != oldValue else { return }
            cachedCompanyLogo = companyLogoData.flatMap { UIImage(data: $0) }
            persistLogo(companyLogoData)
        }
    }

    /// Decoded mirror of `companyLogoData`. Updated in lockstep with the
    /// stored bytes (didSet on `companyLogoData` + init) so SwiftUI reads of
    /// `companyLogo` don't re-decode the JPEG. `FormView.TemplateBody.headerTable`
    /// reads `companyLogo` on every keystroke / signature change during the
    /// customer flow; without the cache, that re-decode runs through
    /// `UIImage(data:)` on a 30-80KB JPEG every redraw.
    private var cachedCompanyLogo: UIImage?

    private let defaults: UserDefaults
    private let logoFileURL: URL

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "swiftpdf",
        category: "AppSettings"
    )

    /// Both `defaults` and `logoFileURL` are injectable so tests can swap in
    /// throwaway suites + temp directories rather than polluting `.standard`
    /// or the real Documents directory. Production callers leave both at
    /// their defaults (`.standard` UserDefaults, `Documents/companyLogo.jpg`).
    init(defaults: UserDefaults = .standard, logoFileURL: URL? = nil) {
        self.defaults = defaults
        self.logoFileURL = logoFileURL ?? Self.defaultLogoFileURL()
        self.brandColorHex = defaults.string(forKey: Self.brandColorKey) ?? Self.defaultBrandColorHex
        self.companyName = defaults.string(forKey: Self.companyNameKey) ?? ""
        self.companyLocation = defaults.string(forKey: Self.companyLocationKey) ?? ""
        self.companyDepartment = defaults.string(forKey: Self.companyDepartmentKey) ?? ""
        self.dropboxTemplatesPath = defaults.string(forKey: Self.dropboxTemplatesPathKey)
            ?? Self.defaultDropboxTemplatesPath
        self.dropboxSignedPath = defaults.string(forKey: Self.dropboxSignedPathKey)
            ?? Self.defaultDropboxSignedPath
        self.hasCompletedFolderSetup = defaults.bool(forKey: Self.hasCompletedFolderSetupKey)
        // One-time migration for installs that already have a logo blob in
        // UserDefaults from before this change. Idempotent — once the file
        // exists, the legacy blob is ignored on subsequent inits.
        Self.migrateLogoFromUserDefaultsIfNeeded(defaults: defaults, to: self.logoFileURL)
        let loaded = Self.loadLogoData(from: self.logoFileURL)
        self.companyLogoData = loaded
        // didSet doesn't fire during init's own-property assignment — prime
        // the decoded cache explicitly here.
        self.cachedCompanyLogo = loaded.flatMap { UIImage(data: $0) }
    }

    /// Writes the in-memory logo bytes to disk and applies the backup
    /// exclusion attribute. Clearing the logo deletes the file. Errors are
    /// logged but don't propagate — a failed save is less bad than crashing
    /// the manager's Settings edit mid-flow.
    private func persistLogo(_ data: Data?) {
        do {
            if let data {
                try data.write(to: logoFileURL, options: [.atomic])
                try Self.applyBackupExclusion(to: logoFileURL)
            } else if FileManager.default.fileExists(atPath: logoFileURL.path) {
                try FileManager.default.removeItem(at: logoFileURL)
            }
        } catch {
            Self.logger.error("companyLogo persist failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func defaultLogoFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("companyLogo.jpg")
    }

    private static func loadLogoData(from url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// One-time migration: if the legacy UserDefaults blob exists and the
    /// on-disk file does not, copy bytes over and remove the UserDefaults
    /// entry. Subsequent inits no-op because the file exists. If the file
    /// write fails, the legacy blob is left intact so a future launch can
    /// retry (e.g. disk full at first launch).
    private static func migrateLogoFromUserDefaultsIfNeeded(
        defaults: UserDefaults,
        to fileURL: URL
    ) {
        if FileManager.default.fileExists(atPath: fileURL.path) { return }
        guard let legacy = defaults.data(forKey: legacyCompanyLogoKey) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try legacy.write(to: fileURL, options: [.atomic])
            try applyBackupExclusion(to: fileURL)
            defaults.removeObject(forKey: legacyCompanyLogoKey)
            logger.info("companyLogo migrated from UserDefaults to file storage")
        } catch {
            logger.error("companyLogo migration failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Marks the file so iOS does not include it in standard or iCloud
    /// backups. Reapplied on every persist — atomic file replacement resets
    /// the resource value, so re-applying after each write is necessary.
    private static func applyBackupExclusion(to fileURL: URL) throws {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Decoded `UIImage` view of `companyLogoData`. Returns nil if no logo is
    /// set or the persisted bytes don't decode. Backed by `cachedCompanyLogo`,
    /// which is updated in lockstep with `companyLogoData` so the JPEG decode
    /// happens once per logo change rather than once per read.
    var companyLogo: UIImage? {
        cachedCompanyLogo
    }

    /// Aspect-preserving resize + JPEG encode for `PhotosPicker`-sourced
    /// logos. `maxDimension` caps the longer side so a 4032×3024 photo
    /// doesn't end up consuming hundreds of KB of `UserDefaults` plist
    /// space. 512px at 0.85 quality lands around 30–80KB for typical
    /// logo-shaped images.
    nonisolated static func compressLogoForStorage(
        _ image: UIImage,
        maxDimension: CGFloat = 512,
        quality: CGFloat = 0.85
    ) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// SwiftUI consumers. When the stored hex equals the default sentinel,
    /// returns the adaptive `defaultBrandColor` (different shades in light vs
    /// dark mode) instead of decoding the sentinel as a static color — the
    /// bright `#FF9500` orange that looks excellent on dark backgrounds fails
    /// WCAG AA contrast on white, so the light-mode default uses a darker
    /// burnt orange. Manager-customized hexes round-trip as the literal stored
    /// color; the manager owns that contrast tradeoff.
    var brandColor: Color {
        if brandColorHex == Self.defaultBrandColorHex {
            return Self.defaultBrandColor
        }
        return Color(hex: brandColorHex) ?? Self.defaultBrandColor
    }

    /// PDF renderer consumes a `UIColor` because `UIGraphicsPDFRenderer`'s
    /// `NSAttributedString.Key.foregroundColor` wants `UIColor`, not `Color`.
    /// Same default-sentinel adaptation as `brandColor`. PDF rendering pins a
    /// light trait collection in `FormRenderer.render`, so the dynamic default
    /// resolves to its light-mode (darker) variant on the white page
    /// regardless of the app's current appearance.
    var brandUIColor: UIColor {
        if brandColorHex == Self.defaultBrandColorHex {
            return Self.defaultBrandUIColor
        }
        return UIColor(hex: brandColorHex) ?? Self.defaultBrandUIColor
    }

    /// Wipes the saved color back to the iOS system orange default.
    func resetBrandColor() {
        brandColorHex = Self.defaultBrandColorHex
    }

    private static let brandColorKey = "brandColorHex"
    private static let companyNameKey = "companyName"
    private static let companyLocationKey = "companyLocation"
    private static let companyDepartmentKey = "companyDepartment"
    private static let dropboxTemplatesPathKey = "dropboxTemplatesPath"
    private static let dropboxSignedPathKey = "dropboxSignedPath"
    private static let hasCompletedFolderSetupKey = "hasCompletedFolderSetup"

    /// Default Dropbox path for JSON templates — top-level so first-time users
    /// can find it easily. Manager-overridable via `ChooseDropboxFolderView`.
    static let defaultDropboxTemplatesPath = "/SwiftPDF/Templates"

    /// Default Dropbox path for signed PDFs. See `defaultDropboxTemplatesPath`.
    static let defaultDropboxSignedPath = "/SwiftPDF/Signed"
    /// Legacy UserDefaults key for the JPEG-encoded logo. Read once at
    /// init time to drive a one-shot migration to on-disk file storage.
    /// Not written to going forward.
    private static let legacyCompanyLogoKey = "companyLogoData"
    /// Sentinel hex marking "the manager has not customized the brand color".
    /// Stored as `#FF9500` (Apple's bright systemOrange) for backward
    /// compatibility with prior installs and so ColorPicker round-trips to a
    /// recognizable swatch. Rendering special-cases this value in
    /// `brandColor` / `brandUIColor` and returns the adaptive default instead
    /// — see `defaultBrandUIColor`.
    private static let defaultBrandColorHex = "#FF9500"

    /// Adaptive default brand color. Light mode resolves to a darker burnt
    /// orange (`#C93400`, 4.6:1 contrast on white — passes WCAG AA); dark
    /// mode resolves to bright Apple-orange (`#FF9500`, ~10:1 contrast on
    /// black). Built as a dynamic `UIColor` so SwiftUI consumers
    /// (`foregroundStyle`, `tint`) and UIKit consumers (PDF text rendering)
    /// both pick the right variant for the surface they're drawing on.
    ///
    /// Only the default adapts. If a manager picks a custom hex via
    /// `SettingsView`, the literal stored color is rendered as-is — they
    /// own that contrast call.
    nonisolated static let defaultBrandUIColor: UIColor = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)   // #FF9500
        default:
            return UIColor(red: 0.788, green: 0.204, blue: 0.0, alpha: 1.0) // #C93400
        }
    }

    /// SwiftUI mirror of `defaultBrandUIColor`. `Color(uiColor:)` preserves
    /// the dynamic resolution — SwiftUI re-resolves the wrapped UIColor
    /// against the consuming view's environment, so the light/dark variant
    /// auto-switches without an explicit `@Environment(\.colorScheme)` read.
    nonisolated static let defaultBrandColor: Color = Color(uiColor: defaultBrandUIColor)
}

// MARK: - Hex helpers

private extension Color {
    init?(hex: String) {
        guard let ui = UIColor(hex: hex) else { return nil }
        self = Color(uiColor: ui)
    }
}

extension Color {
    /// `#RRGGBB`. Returns nil for non-RGB color spaces (shouldn't happen for
    /// a `ColorPicker`-sourced value but the API can technically yield one).
    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        // ColorPicker on a P3-capable display can return components > 1.0 for
        // wide-gamut colors. Clamp to sRGB before serializing — brand colors
        // don't need P3 fidelity, and hex storage assumes 8-bit per channel.
        let R = Int((max(0, min(1, r)) * 255).rounded())
        let G = Int((max(0, min(1, g)) * 255).rounded())
        let B = Int((max(0, min(1, b)) * 255).rounded())
        return String(format: "#%02X%02X%02X", R, G, B)
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var sanitized = hex
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
