import UIKit
import PencilKit

/// Renders a filled-and-signed `FormTemplate` to PDF Data.
/// Uses `UIGraphicsPDFRenderer` + `NSAttributedString` for text flow.
/// v1: single page, US Letter portrait. If content would overflow, `render`
/// throws `RenderError.contentTooLong` — there's no silent truncation.
struct FormRenderer {
    static let pageSize = CGSize(width: 612, height: 792)  // US Letter at 72dpi
    static let margin: CGFloat = 50

    /// Reserved vertical space the signature block needs at the bottom of the
    /// page. Matches `drawSignatureBlock`'s layout (Print Name / Date row +
    /// signature box + signature line + a little breathing room).
    static let signatureBlockHeight: CGFloat = 150

    /// Brand accent used for the title text. Injected from `AppSettings` at
    /// call sites; defaults to system orange so unit tests and any future
    /// internal caller without settings access still render reasonably.
    let brandColor: UIColor

    /// Optional square logo drawn to the left of the header table. Aspect-fit
    /// into a 64-pt slot; non-square images are letterboxed.
    let companyLogo: UIImage?

    init(brandColor: UIColor = AppSettings.defaultBrandUIColor, companyLogo: UIImage? = nil) {
        self.brandColor = brandColor
        self.companyLogo = companyLogo
    }

    enum RenderError: LocalizedError {
        case contentTooLong

        var errorDescription: String? {
            switch self {
            case .contentTooLong:
                return "This template is too long to fit on one page. Shorten the body or split it into multiple templates."
            }
        }
    }

    /// Pinned to `en_US_POSIX` + Gregorian so the in-PDF "Date" field always
    /// reads as a Western Gregorian date regardless of the device's regional
    /// settings. Time zone tracks the device's current zone so the date matches
    /// the signer's local calendar day.
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    func render(
        template: FormTemplate,
        printName: String,
        signature: PKDrawing,
        signedAt: Date
    ) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(template.name) - \(printName)",
            kCGPDFContextAuthor as String: template.header.company,
            kCGPDFContextCreator as String: "SwiftPDF"
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: Self.pageSize),
            format: format
        )

        // Capture overflow inside the closure (pdfData's block is non-throwing).
        // If content pushes the signature off-page, throw after the renderer
        // returns rather than silently producing a "signed" PDF whose signature
        // doesn't exist.
        var overflowed = false
        let signatureCeiling = Self.pageSize.height - Self.margin - Self.signatureBlockHeight

        // Pin a light trait collection for the entire PDF render. The page
        // background is always white, so a dynamic `UIColor` like
        // `AppSettings.defaultBrandUIColor` (which adapts to dark mode) must
        // resolve to its light-mode variant here regardless of the app's
        // current appearance — otherwise a manager signing on a dark-mode
        // iPad would bake bright-orange-on-white into the PDF and reproduce
        // the same low-contrast bug that's fixed in-app. Same precedent as
        // the inner wrap in `drawSignature` (kept for explicitness even
        // though this outer wrap supersedes it).
        //
        // `performAsCurrent` returns Void, so we capture the rendered bytes
        // into a local var rather than returning through the closure.
        var data = Data()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            data = renderer.pdfData { context in
                context.beginPage()
                var y = Self.margin
                y = drawTitle(template.name, at: y)
                y = drawHeader(template.header, at: y)
                switch template.content {
                case .structured(let intro, let rules, let acknowledgment):
                    y = drawIntro(intro, at: y)
                    y = drawRules(rules, at: y)
                    y = drawAcknowledgment(acknowledgment, at: y)
                case .freeform(let body):
                    y = drawFreeformBody(body, at: y)
                }
                if y > signatureCeiling {
                    overflowed = true
                    return  // signature block intentionally not drawn — we'll throw
                }
                drawSignatureBlock(
                    printName: printName,
                    signature: signature,
                    signedAt: signedAt,
                    at: y
                )
            }
        }
        if overflowed {
            throw RenderError.contentTooLong
        }
        return data
    }

    private func drawFreeformBody(_ body: String, at y: CGFloat) -> CGFloat {
        // Render whatever the manager typed as wrapped paragraphs. Newlines in
        // the source become paragraph breaks; the rendered text inherits the
        // same body-size font used for the structured intro/rules so the visual
        // weight matches across template types.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11)
        ]
        return drawWrappedText(body, attributes: attrs, at: y, extraSpacing: 18)
    }

    private func drawTitle(_ title: String, at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: brandColor
        ]
        NSAttributedString(string: title, attributes: attrs)
            .draw(at: CGPoint(x: Self.margin, y: y))
        return y + 40
    }

    /// Header layout: optional 64-pt square logo on the left, then a stacked
    /// label/value table to its right. Without a logo, the table starts at
    /// the page margin like before. The returned y is below whichever element
    /// (logo or table) extended further, so the body content doesn't collide
    /// with a tall logo.
    private func drawHeader(_ header: FormHeader, at y: CGFloat) -> CGFloat {
        let logoSize: CGFloat = 64
        let logoSpacing: CGFloat = 12

        if let companyLogo {
            drawAspectFit(
                companyLogo,
                in: CGRect(x: Self.margin, y: y, width: logoSize, height: logoSize)
            )
        }

        let labelX = (companyLogo != nil ? Self.margin + logoSize + logoSpacing : Self.margin)
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold)
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11)
        ]

        let rows: [(String, String)] = [
            ("Company", header.company),
            ("Location", header.location),
            ("Department", header.department),
            ("Effective Date", dateFormatter.string(from: header.effectiveDate))
        ]

        let labelWidth: CGFloat = 110
        let valueX = labelX + labelWidth + 8
        let valueWidth = Self.pageSize.width - valueX - Self.margin
        var currentY = y

        for (label, value) in rows {
            NSAttributedString(string: label, attributes: labelAttr)
                .draw(at: CGPoint(x: labelX, y: currentY))
            let valueStr = NSAttributedString(string: value, attributes: valueAttr)
            let bounds = valueStr.boundingRect(
                with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil
            )
            valueStr.draw(in: CGRect(x: valueX, y: currentY, width: valueWidth, height: bounds.height))
            currentY += max(18, ceil(bounds.height) + 2)
        }
        // Account for a logo taller than the rendered text rows.
        let endY = max(currentY, y + (companyLogo != nil ? logoSize : 0))
        return endY + 12
    }

    /// Aspect-fits `image` inside `rect` and draws it in the current PDF
    /// context. Wider-than-tall images vertically center; taller-than-wide
    /// images horizontally center. Both produce letterboxing if aspect
    /// differs from the rect.
    private func drawAspectFit(_ image: UIImage, in rect: CGRect) {
        let imageAspect = image.size.width / max(image.size.height, 0.0001)
        let rectAspect = rect.width / max(rect.height, 0.0001)
        let target: CGRect
        if imageAspect > rectAspect {
            let h = rect.width / imageAspect
            target = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        } else {
            let w = rect.height * imageAspect
            target = CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height)
        }
        image.draw(in: target)
    }

    private func drawIntro(_ intro: String, at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11)
        ]
        return drawWrappedText(intro, attributes: attrs, at: y, extraSpacing: 10)
    }

    private func drawRules(_ rules: [String], at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5)
        ]
        let bulletWidth: CGFloat = 24
        let textX = Self.margin + bulletWidth
        let width = Self.pageSize.width - textX - Self.margin
        var currentY = y

        for (index, rule) in rules.enumerated() {
            NSAttributedString(string: "\(index + 1).", attributes: attrs)
                .draw(at: CGPoint(x: Self.margin, y: currentY))
            let str = NSAttributedString(string: rule, attributes: attrs)
            let bounds = str.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil
            )
            str.draw(in: CGRect(x: textX, y: currentY, width: width, height: bounds.height))
            currentY += ceil(bounds.height) + 4
        }
        return currentY + 12
    }

    private func drawAcknowledgment(_ text: String, at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .medium)
        ]
        return drawWrappedText(text, attributes: attrs, at: y, extraSpacing: 18)
    }

    private func drawSignatureBlock(
        printName: String,
        signature: PKDrawing,
        signedAt: Date,
        at y: CGFloat
    ) {
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11)
        ]

        let columnWidth = (Self.pageSize.width - 2 * Self.margin) / 2 - 10
        let dateX = Self.margin + columnWidth + 20

        // Top row: Print Name | Date
        NSAttributedString(string: "Print Name", attributes: labelAttr)
            .draw(at: CGPoint(x: Self.margin, y: y))
        NSAttributedString(string: printName, attributes: valueAttr)
            .draw(at: CGPoint(x: Self.margin, y: y + 18))
        drawLine(from: CGPoint(x: Self.margin, y: y + 36),
                 to: CGPoint(x: Self.margin + columnWidth, y: y + 36))

        NSAttributedString(string: "Date", attributes: labelAttr)
            .draw(at: CGPoint(x: dateX, y: y))
        NSAttributedString(string: dateFormatter.string(from: signedAt), attributes: valueAttr)
            .draw(at: CGPoint(x: dateX, y: y + 18))
        drawLine(from: CGPoint(x: dateX, y: y + 36),
                 to: CGPoint(x: dateX + columnWidth, y: y + 36))

        // Bottom row: Signature
        let sigY = y + 56
        NSAttributedString(string: "Signature", attributes: labelAttr)
            .draw(at: CGPoint(x: Self.margin, y: sigY))

        let sigRect = CGRect(
            x: Self.margin,
            y: sigY + 16,
            width: Self.pageSize.width - 2 * Self.margin,
            height: 64
        )
        drawSignature(signature, in: sigRect)
        drawLine(from: CGPoint(x: Self.margin, y: sigY + 84),
                 to: CGPoint(x: Self.pageSize.width - Self.margin, y: sigY + 84))
    }

    /// 3x oversample so the signature ends up at roughly 216dpi inside the
    /// 72dpi PDF page — enough resolution that the rasterized strokes don't
    /// look pixelated when the form is printed.
    private static let signatureRenderScale: CGFloat = 3.0

    private func drawSignature(_ drawing: PKDrawing, in rect: CGRect) {
        guard !drawing.strokes.isEmpty else { return }
        let sourceBounds = drawing.bounds
        // Reject degenerate strokes (single point, perfect-horizontal-only,
        // perfect-vertical-only). PencilKit's behavior on a zero-dimension
        // bounds varies between iOS versions — this is the well-defined path.
        // `FormView.canSubmit` performs the same check at the UI layer.
        guard sourceBounds.width > 0.5, sourceBounds.height > 0.5 else { return }

        // Pin a light trait collection while rasterizing. PKDrawing.image()
        // resolves stroke colors against the current trait collection; in dark
        // mode the `.black` ink comes out near-white and disappears on the PDF's
        // white page — visible on the canvas (dark bg), gone in the export.
        var image: UIImage!
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: sourceBounds, scale: Self.signatureRenderScale)
        }
        let aspect = sourceBounds.width / sourceBounds.height
        let availableAspect = rect.width / rect.height
        let target: CGRect
        if aspect > availableAspect {
            let h = rect.width / aspect
            target = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        } else {
            let w = rect.height * aspect
            target = CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
        }
        image.draw(in: target)
    }

    private func drawWrappedText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        at y: CGFloat,
        extraSpacing: CGFloat
    ) -> CGFloat {
        let width = Self.pageSize.width - 2 * Self.margin
        let str = NSAttributedString(string: text, attributes: attributes)
        let bounds = str.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            context: nil
        )
        str.draw(in: CGRect(x: Self.margin, y: y, width: width, height: bounds.height))
        return y + ceil(bounds.height) + extraSpacing
    }

    private func drawLine(from: CGPoint, to: CGPoint) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = 0.5
        UIColor.black.setStroke()
        path.stroke()
    }
}
