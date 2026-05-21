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

    /// Per-test logo URL in the simulator temp directory so logo tests don't
    /// pollute the real Documents folder or contend with each other.
    private func freshLogoURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSettingsTests-\(UUID().uuidString).jpg")
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
    func test_logo_persists_to_file_and_loads() {
        let defaults = freshDefaults()
        let logoURL = freshLogoURL()
        defer { try? FileManager.default.removeItem(at: logoURL) }

        let settings = AppSettings(defaults: defaults, logoFileURL: logoURL)
        XCTAssertNil(settings.companyLogo, "Fresh install has no logo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logoURL.path), "No file before any logo set")

        // Fabricate a 100x60 red image, compress, persist.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 60))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        }
        let compressed = AppSettings.compressLogoForStorage(image, maxDimension: 100, quality: 0.85)
        XCTAssertNotNil(compressed)
        settings.companyLogoData = compressed

        XCTAssertTrue(FileManager.default.fileExists(atPath: logoURL.path), "Setter writes to the injected file URL")
        XCTAssertNil(defaults.data(forKey: "companyLogoData"), "No UserDefaults write — file is the only persistence")

        // Reload from disk — a second AppSettings instance pointing at the
        // same URL should see the same bytes and decode them to a UIImage.
        let reloaded = AppSettings(defaults: defaults, logoFileURL: logoURL)
        XCTAssertNotNil(reloaded.companyLogo)
        XCTAssertEqual(reloaded.companyLogoData, compressed)
    }

    @MainActor
    func test_logo_clear_removes_file() {
        let defaults = freshDefaults()
        let logoURL = freshLogoURL()
        defer { try? FileManager.default.removeItem(at: logoURL) }

        let settings = AppSettings(defaults: defaults, logoFileURL: logoURL)
        settings.companyLogoData = Data([0xFF, 0xD8, 0xFF])  // bytes round-trip; not required to decode
        XCTAssertTrue(FileManager.default.fileExists(atPath: logoURL.path))

        settings.companyLogoData = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: logoURL.path))
    }

    @MainActor
    func test_logo_migrates_from_user_defaults_to_file() {
        let defaults = freshDefaults()
        let logoURL = freshLogoURL()
        defer { try? FileManager.default.removeItem(at: logoURL) }

        // Pre-populate the legacy UserDefaults blob to simulate an
        // installation upgraded from the pre-file-storage version.
        let legacyBlob = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        defaults.set(legacyBlob, forKey: "companyLogoData")

        let settings = AppSettings(defaults: defaults, logoFileURL: logoURL)

        XCTAssertEqual(settings.companyLogoData, legacyBlob, "Logo loaded from migrated file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logoURL.path), "Migration wrote the file")
        XCTAssertNil(defaults.data(forKey: "companyLogoData"), "Legacy UserDefaults key removed after migration")
    }

    @MainActor
    func test_logo_migration_is_idempotent_on_second_init() {
        let defaults = freshDefaults()
        let logoURL = freshLogoURL()
        defer { try? FileManager.default.removeItem(at: logoURL) }

        // First init migrates the legacy blob.
        let originalBlob = Data([0xFF, 0xD8, 0xFF])
        defaults.set(originalBlob, forKey: "companyLogoData")
        _ = AppSettings(defaults: defaults, logoFileURL: logoURL)

        // Simulate a hostile retry — someone re-adds a different blob to
        // UserDefaults after migration completed. The file already exists,
        // so the next init MUST NOT overwrite it from UserDefaults.
        defaults.set(Data([0xAA, 0xBB]), forKey: "companyLogoData")
        let settings2 = AppSettings(defaults: defaults, logoFileURL: logoURL)

        XCTAssertEqual(settings2.companyLogoData, originalBlob, "Second init reads from file, ignores re-added legacy blob")
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

    // MARK: - Dropbox path settings (v1.1)

    @MainActor
    func test_dropbox_paths_default_when_unset() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.dropboxTemplatesPath, "/SwiftPDF/Templates")
        XCTAssertEqual(settings.dropboxSignedPath, "/SwiftPDF/Signed")
    }

    @MainActor
    func test_dropbox_paths_persist() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.dropboxTemplatesPath = "/Warehouse/Templates"
        settings.dropboxSignedPath = "/Warehouse/Signed Waivers"

        XCTAssertEqual(defaults.string(forKey: "dropboxTemplatesPath"), "/Warehouse/Templates")
        XCTAssertEqual(defaults.string(forKey: "dropboxSignedPath"), "/Warehouse/Signed Waivers")
    }

    @MainActor
    func test_dropbox_paths_load_persisted_values() {
        let defaults = freshDefaults()
        defaults.set("/Custom/Templates", forKey: "dropboxTemplatesPath")
        defaults.set("/Custom/Signed", forKey: "dropboxSignedPath")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.dropboxTemplatesPath, "/Custom/Templates")
        XCTAssertEqual(settings.dropboxSignedPath, "/Custom/Signed")
    }

    @MainActor
    func test_dropbox_paths_are_independent() {
        // Common manager configuration: templates in a manager-only folder,
        // signed PDFs in a Warehousing/HR shared folder.
        let settings = AppSettings(defaults: freshDefaults())
        settings.dropboxTemplatesPath = "/Manager/Templates"
        XCTAssertEqual(
            settings.dropboxSignedPath, "/SwiftPDF/Signed",
            "Changing one path must not disturb the other"
        )
    }

    @MainActor
    func test_hasCompletedFolderSetup_defaults_false() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertFalse(
            settings.hasCompletedFolderSetup,
            "Fresh install hasn't dismissed the folder-setup sheet yet"
        )
    }

    @MainActor
    func test_hasCompletedFolderSetup_persists() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedFolderSetup = true
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedFolderSetup"))

        // A fresh AppSettings against the same suite reads the persisted value.
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedFolderSetup)
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
