import SwiftUI
import PDFKit

/// Embedded PDF viewer backed by `PDFKit.PDFView`. Used by the demo flow's
/// `View signed PDF` button so a reviewer (or any demo-mode user) can
/// validate the rendered output end-to-end without connecting a cloud
/// provider. Outside the demo path, signed PDFs land in the user's
/// configured provider and are opened via that provider's app — there's
/// no in-app viewer for real uploads (and intentionally so: customer
/// content shouldn't linger in app memory after a successful upload).
struct PDFViewerView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Re-encode-compare would be O(n); the document is identity-bound to
        // the bytes we passed in via init, and the demo path doesn't mutate
        // the bytes after success, so only swap when SwiftUI hands us a
        // genuinely different Data instance.
        if uiView.document?.dataRepresentation() != data {
            uiView.document = PDFDocument(data: data)
        }
    }
}
