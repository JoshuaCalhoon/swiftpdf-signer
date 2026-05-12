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
    func test_company_fields_default_to_empty() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.companyName, "")
        XCTAssertEqual(settings.companyLocation, "")
        XCTAssertEqual(settings.companyDepartment, "")
    }

    @MainActor
    func test_company_fields_persist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.companyName = "Acme Corp"
        settings.companyLocation = "123 Main St"
        settings.companyDepartment = "Receiving"

        XCTAssertEqual(defaults.string(forKey: "companyName"), "Acme Corp")
        XCTAssertEqual(defaults.string(forKey: "companyLocation"), "123 Main St")
        XCTAssertEqual(defaults.string(forKey: "companyDepartment"), "Receiving")
    }

    func test_placeholder_falls_back_when_empty() {
        let header = FormHeader.placeholder(
            company: "",
            location: "   ",
            department: nil
        )
        XCTAssertEqual(header.company, "Your Company")
        XCTAssertEqual(header.location, "Your Location")
        XCTAssertEqual(header.department, "Your Department")
    }

    func test_placeholder_uses_overrides_when_present() {
        let header = FormHeader.placeholder(
            company: "Acme Corp",
            location: "  123 Main St  ",
            department: "Receiving"
        )
        XCTAssertEqual(header.company, "Acme Corp")
        XCTAssertEqual(header.location, "123 Main St", "leading/trailing whitespace should trim")
        XCTAssertEqual(header.department, "Receiving")
    }

    @MainActor
    func test_logo_persists_and_loads() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.companyLogo, "Fresh defaults have no logo")

        // Fabricate a 100x60 red image, compress, persist.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 60))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        }
        let compressed = AppSettings.compressLogoForStorage(image, maxDimension: 100, quality: 0.85)
        XCTAssertNotNil(compressed)
        settings.companyLogoData = compressed

        XCTAssertNotNil(defaults.data(forKey: "companyLogoData"))

        // Reload from defaults — second AppSettings instance should see the
        // same bytes and decode them to a UIImage.
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertNotNil(reloaded.companyLogo)
    }

    @MainActor
    func test_logo_clear_removes_key() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.companyLogoData = Data([0xFF, 0xD8, 0xFF])  // doesn't decode as image, fine for round-trip
        XCTAssertNotNil(defaults.data(forKey: "companyLogoData"))

        settings.companyLogoData = nil
        XCTAssertNil(defaults.data(forKey: "companyLogoData"))
    }

    func test_compress_logo_shrinks_oversized_image() {
        // 2000x2000 source → max 512 → resized to 512x512 → JPEG should be
        // well under 200KB.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 2000))
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 2000))
        }
        let compressed = AppSettings.compressLogoForStorage(image, maxDimension: 512, quality: 0.85)
        XCTAssertNotNil(compressed)
        XCTAssertLessThan(compressed!.count, 200_000, "Compressed logo should be under 200KB")
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
