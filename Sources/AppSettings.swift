import SwiftUI
import UIKit

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

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can use an in-memory suite instead
    /// of polluting `.standard` across the simulator.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.brandColorHex = defaults.string(forKey: Self.brandColorKey) ?? Self.defaultBrandColorHex
        self.companyName = defaults.string(forKey: Self.companyNameKey) ?? ""
        self.companyLocation = defaults.string(forKey: Self.companyLocationKey) ?? ""
        self.companyDepartment = defaults.string(forKey: Self.companyDepartmentKey) ?? ""
    }

    /// SwiftUI consumers. Falls back to `defaultBrandColor` if the stored hex
    /// is somehow malformed — shouldn't happen on a normal save path, but a
    /// human-edited `plist` could land here.
    var brandColor: Color {
        Color(hex: brandColorHex) ?? Self.defaultBrandColor
    }

    /// PDF renderer consumes a `UIColor` because `UIGraphicsPDFRenderer`'s
    /// `NSAttributedString.Key.foregroundColor` wants `UIColor`, not `Color`.
    var brandUIColor: UIColor {
        UIColor(hex: brandColorHex) ?? Self.defaultBrandUIColor
    }

    /// Wipes the saved color back to the iOS system orange default.
    func resetBrandColor() {
        brandColorHex = Self.defaultBrandColorHex
    }

    private static let brandColorKey = "brandColorHex"
    private static let companyNameKey = "companyName"
    private static let companyLocationKey = "companyLocation"
    private static let companyDepartmentKey = "companyDepartment"
    /// Matches `UIColor.systemOrange` resolved against a light trait collection
    /// (the way it'll render in the PDF). SwiftUI's `Color.orange` resolves to
    /// the same RGB so the in-app surface matches the PDF output.
    private static let defaultBrandColorHex = "#FF9500"
    static let defaultBrandColor: Color = .orange
    static let defaultBrandUIColor: UIColor = .systemOrange
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
