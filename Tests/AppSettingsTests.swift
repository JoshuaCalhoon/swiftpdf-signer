import XCTest
@testable import SwiftPDF

final class AppSettingsTests: XCTestCase {

    /// Isolated UserDefaults so tests don't tromp on `.standard`.
    private func freshDefaults() -> UserDefaults {
        // Use a unique suite name per test so parallel tests can't collide
        // on shared state inside the simulator.
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    func test_default_brand_color_when_no_value_stored() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.brandColorHex, "#FF9500")
    }

    @MainActor
    func test_persists_brand_color_to_user_defaults() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.brandColorHex = "#3366CC"

        XCTAssertEqual(defaults.string(forKey: "brandColorHex"), "#3366CC")
    }

    @MainActor
    func test_loads_persisted_brand_color() {
        let defaults = freshDefaults()
        defaults.set("#112233", forKey: "brandColorHex")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.brandColorHex, "#112233")
    }

    @MainActor
    func test_reset_returns_to_default() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.brandColorHex = "#000000"
        settings.resetBrandColor()

        XCTAssertEqual(settings.brandColorHex, "#FF9500")
    }

    @MainActor
    func test_color_round_trips_through_hex() {
        // ColorPicker → Color.toHex → UserDefaults → UIColor(hex:) round-trip
        // should preserve the 8-bit-per-channel value.
        let settings = AppSettings(defaults: freshDefaults())
        let cases = ["#000000", "#FFFFFF", "#FF5100", "#3366CC", "#AABBCC"]
        for hex in cases {
            settings.brandColorHex = hex
            let ui = settings.brandUIColor
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            let recovered = String(format: "#%02X%02X%02X",
                Int((r * 255).rounded()),
                Int((g * 255).rounded()),
                Int((b * 255).rounded())
            )
            XCTAssertEqual(recovered, hex, "round-trip failed for \(hex)")
        }
    }
}
