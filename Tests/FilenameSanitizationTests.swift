import XCTest
@testable import SwiftPDF

final class FilenameSanitizationTests: XCTestCase {

    // MARK: - sanitizedForFilename

    func test_passthrough_for_plain_ascii() {
        XCTAssertEqual("Joe Smith".sanitizedForFilename(), "Joe Smith")
    }

    func test_strips_dropbox_disallowed_set() {
        // Every char in the disallowed set should collapse to a single "-"
        // when adjacent to text. Verify the most common offenders.
        XCTAssertEqual("Joe/Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe\\Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe:Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe\"Smith\"".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe<Smith>".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe|Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe?Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe*Smith".sanitizedForFilename(), "Joe-Smith")
    }

    func test_strips_control_characters() {
        XCTAssertEqual("Joe\u{0000}Smith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe\tSmith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe\nSmith".sanitizedForFilename(), "Joe-Smith")
        XCTAssertEqual("Joe\rSmith".sanitizedForFilename(), "Joe-Smith")
    }

    func test_path_traversal_resolves_to_safe_form() {
        // ".." sequences can't reach a parent in the Dropbox App Folder
        // scope (the server normalizes), but locally we still want the
        // string to lose its leading-dot quality so it doesn't produce
        // a hidden file when the Dropbox client syncs it back to macOS.
        XCTAssertEqual("../Templates/evil".sanitizedForFilename(), "Templates-evil")
        XCTAssertEqual(".hidden".sanitizedForFilename(), "hidden")
        XCTAssertEqual("...weird...".sanitizedForFilename(), "weird...")
    }

    func test_empty_input_returns_fallback() {
        XCTAssertEqual("".sanitizedForFilename(), "Untitled")
        XCTAssertEqual("   ".sanitizedForFilename(), "Untitled")
        XCTAssertEqual("////".sanitizedForFilename(), "Untitled")
        XCTAssertEqual("".sanitizedForFilename(fallback: "Anon"), "Anon")
    }

    func test_unicode_passes_through_untouched() {
        XCTAssertEqual("José".sanitizedForFilename(), "José")
        XCTAssertEqual("北京".sanitizedForFilename(), "北京")
        XCTAssertEqual("🦊 fox".sanitizedForFilename(), "🦊 fox")
    }

    // MARK: - truncatedToUTF8Bytes

    func test_short_string_unchanged() {
        XCTAssertEqual("Joe".truncatedToUTF8Bytes(240), "Joe")
    }

    func test_truncates_at_budget_for_ascii() {
        let s = String(repeating: "a", count: 300)
        let result = s.truncatedToUTF8Bytes(240)
        XCTAssertEqual(result.utf8.count, 240)
    }

    func test_does_not_split_multibyte_scalars() {
        // 🦊 is 4 UTF-8 bytes. A budget that would land mid-scalar must
        // stop before consuming it, not split it.
        let s = "a🦊b🦊c🦊d"
        // "a" + "🦊" + "b" + "🦊" = 1 + 4 + 1 + 4 = 10 bytes
        // budget 9 should land after "b" (no room for the next 🦊)
        let result = s.truncatedToUTF8Bytes(9)
        XCTAssertEqual(result, "a🦊b")
        XCTAssertEqual(result.utf8.count, 6)
    }

    func test_zero_budget_returns_empty() {
        XCTAssertEqual("abc".truncatedToUTF8Bytes(0), "")
    }
}
