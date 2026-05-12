import XCTest
@testable import SwiftPDF

final class FormTemplateCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func test_round_trips_freeform_template() throws {
        let header = FormHeader.placeholder(effectiveDate: Date(timeIntervalSince1970: 1_700_000_000))
        let template = FormTemplate(
            name: "Receiving Dock Acknowledgment",
            header: header,
            content: .freeform(body: "I acknowledge the receiving rules.\n\nMore lines."),
            version: 3,
            editable: true
        )

        let data = try encoder.encode(template)
        let decoded = try decoder.decode(FormTemplate.self, from: data)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.name, template.name)
        XCTAssertEqual(decoded.header, template.header)
        XCTAssertEqual(decoded.content, template.content)
        XCTAssertEqual(decoded.version, 3)
        XCTAssertTrue(decoded.editable)
    }

    func test_round_trips_structured_template() throws {
        let template = FormTemplate.makeFreshSample()
        let data = try encoder.encode(template)
        let decoded = try decoder.decode(FormTemplate.self, from: data)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertTrue(decoded.editable, "Sample seed must be editable so managers can morph it")

        switch decoded.content {
        case .structured(let intro, let rules, let acknowledgment):
            XCTAssertFalse(intro.isEmpty)
            XCTAssertFalse(rules.isEmpty)
            XCTAssertFalse(acknowledgment.isEmpty)
        case .freeform:
            XCTFail("Expected structured content for sample template")
        }
    }

    func test_fresh_sample_has_unique_ids() {
        // Each call to makeFreshSample() produces a distinct UUID so a manager
        // duplicating the seed (or re-seeding after wipe) never collides.
        let a = FormTemplate.makeFreshSample()
        let b = FormTemplate.makeFreshSample()
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_decode_defaults_editable_to_true_when_key_absent() throws {
        // Simulate a JSON authored by a tool that didn't write the editable
        // key. Default to editable=true per FormTemplate's decoder.
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "name": "Manually Authored",
          "header": {
            "company": "Test Company",
            "location": "Test Location",
            "department": "Test Department",
            "effectiveDate": "2026-05-11T00:00:00Z"
          },
          "content": {
            "freeform": {
              "body": "Hello world"
            }
          },
          "version": 1
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(FormTemplate.self, from: json)
        XCTAssertTrue(decoded.editable, "Missing `editable` key should default to true")
    }

    func test_flatten_freeform_returns_body_unchanged() {
        let content = FormContent.freeform(body: "Hello\n\nWorld")
        XCTAssertEqual(content.flattenedToFreeform(), "Hello\n\nWorld")
    }

    func test_flatten_structured_preserves_visible_structure() {
        let content = FormContent.structured(
            intro: "Read carefully.",
            rules: ["First rule.", "Second rule."],
            acknowledgment: "I acknowledge."
        )
        let expected = """
        Read carefully.

        1. First rule.
        2. Second rule.

        I acknowledge.
        """
        XCTAssertEqual(content.flattenedToFreeform(), expected)
    }

    func test_flatten_structured_omits_empty_sections() {
        // Only rules — no intro or acknowledgment. Output shouldn't have
        // leading/trailing blank lines from omitted sections.
        let content = FormContent.structured(
            intro: "",
            rules: ["Lone rule."],
            acknowledgment: ""
        )
        XCTAssertEqual(content.flattenedToFreeform(), "1. Lone rule.")
    }
}
