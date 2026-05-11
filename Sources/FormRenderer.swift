import UIKit
import PencilKit

/// Renders a filled-and-signed `FormTemplate` to PDF Data.
/// Uses `UIGraphicsPDFRenderer` + `NSAttributedString` for text flow.
/// v1: single page, US Letter portrait.
struct FormRenderer {
    static let pageSize = CGSize(width: 612, height: 792)  // US Letter at 72dpi
    static let margin: CGFloat = 50

    static let kwikshipOrange = UIColor(red: 1.0, green: 0x51 / 255.0, blue: 0, alpha: 1.0)

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    func render(
        template: FormTemplate,
        printName: String,
        signature: PKDrawing,
        signedAt: Date
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(template.name) — \(printName)",
            kCGPDFContextAuthor as String: template.header.company,
            kCGPDFContextCreator as String: "SwiftPDF"
        ]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: Self.pageSize),
            format: format
        )

        return renderer.pdfData { context in
            context.beginPage()
            var y = Self.margin
            y = drawTitle(template.name, at: y)
            y = drawHeader(template.header, at: y)
            y = drawIntro(template.intro, at: y)
            y = drawRules(template.rules, at: y)
            y = drawAcknowledgment(template.acknowledgment, at: y)
            drawSignatureBlock(
                printName: printName,
                signature: signature,
                signedAt: signedAt,
                at: y
            )
        }
    }

    private func drawTitle(_ title: String, at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: Self.kwikshipOrange
        ]
        NSAttributedString(string: title, attributes: attrs)
            .draw(at: CGPoint(x: Self.margin, y: y))
        return y + 40
    }

    private func drawHeader(_ header: FormHeader, at y: CGFloat) -> CGFloat {
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
        let valueX = Self.margin + labelWidth + 8
        let valueWidth = Self.pageSize.width - valueX - Self.margin
        var currentY = y

        for (label, value) in rows {
            NSAttributedString(string: label, attributes: labelAttr)
                .draw(at: CGPoint(x: Self.margin, y: currentY))
            let valueStr = NSAttributedString(string: value, attributes: valueAttr)
            let bounds = valueStr.boundingRect(
                with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil
            )
            valueStr.draw(in: CGRect(x: valueX, y: currentY, width: valueWidth, height: bounds.height))
            currentY += max(18, ceil(bounds.height) + 2)
        }
        return currentY + 12
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

    private func drawSignature(_ drawing: PKDrawing, in rect: CGRect) {
        guard !drawing.strokes.isEmpty else { return }
        let sourceBounds = drawing.bounds
        let image = drawing.image(from: sourceBounds, scale: 3.0)
        let aspect = sourceBounds.width / max(sourceBounds.height, 1)
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
