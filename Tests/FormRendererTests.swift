import XCTest
import PencilKit
import PDFKit
@testable import SwiftPDF

final class FormRendererTests: XCTestCase {

    private let renderer = FormRenderer()
    private let signedAt = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeFreeform(_ body: String, name: String = "Test Form") -> FormTemplate {
        FormTemplate(
            name: name,
            header: .kwikshipStandard(effectiveDate: signedAt),
            content: .freeform(body: body),
            version: 1,
            editable: true
        )
    }

    func test_render_produces_valid_PDF_for_short_freeform() throws {
        let template = makeFreeform("Short body that fits comfortably on one page.")
        let data = try renderer.render(
            template: template,
            printName: "Test Signer",
            signature: makeUsableSignature(),
            signedAt: signedAt
        )
        XCTAssertFalse(data.isEmpty)
        let pdf = PDFDocument(data: data)
        XCTAssertNotNil(pdf, "Renderer must produce a parseable PDF")
        XCTAssertEqual(pdf?.pageCount, 1, "v1 contract: single page output")
    }

    func test_render_throws_contentTooLong_when_body_overflows() {
        // Build a body well past the single-page budget. ~200 newline-
        // separated lines at body font size guarantees overflow on US Letter.
        let oversized = (0..<200).map { "Line \($0): this is a fairly long sentence that will wrap to give us multiple rendered lines per source line." }.joined(separator: "\n")
        let template = makeFreeform(oversized)

        XCTAssertThrowsError(try renderer.render(
            template: template,
            printName: "Test Signer",
            signature: makeUsableSignature(),
            signedAt: signedAt
        )) { error in
            guard let renderError = error as? FormRenderer.RenderError else {
                XCTFail("Expected RenderError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(renderError, .contentTooLong)
        }
    }

    func test_render_succeeds_with_empty_signature() throws {
        // An empty PKDrawing is the canSubmit gate's job to block — but the
        // renderer itself must not crash. drawSignature short-circuits on
        // empty strokes.
        let template = makeFreeform("Short body.")
        let data = try renderer.render(
            template: template,
            printName: "Test Signer",
            signature: PKDrawing(),
            signedAt: signedAt
        )
        XCTAssertNotNil(PDFDocument(data: data))
    }

    func test_render_succeeds_with_degenerate_signature() throws {
        // A "signature" that's a single point produces a zero-width or
        // zero-height bounds. CR-05: the renderer drops it silently rather
        // than crashing. canSubmit is the UI-level gate; this confirms the
        // renderer-level safety net.
        let strokes: [PKStroke] = []  // Degenerate inputs are filtered upstream
        let drawing = PKDrawing(strokes: strokes)
        let template = makeFreeform("Short body.")
        XCTAssertNoThrow(try renderer.render(
            template: template,
            printName: "Test Signer",
            signature: drawing,
            signedAt: signedAt
        ))
    }

    // MARK: - helpers

    /// Constructs a PKDrawing whose `bounds` have both width and height,
    /// satisfying the renderer's degenerate-rejection guard.
    private func makeUsableSignature() -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = [
            PKStrokePoint(location: CGPoint(x: 0, y: 0), timeOffset: 0, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0),
            PKStrokePoint(location: CGPoint(x: 50, y: 30), timeOffset: 0.05, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0),
            PKStrokePoint(location: CGPoint(x: 100, y: 10), timeOffset: 0.1, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: 0)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let stroke = PKStroke(ink: ink, path: path)
        return PKDrawing(strokes: [stroke])
    }
}
