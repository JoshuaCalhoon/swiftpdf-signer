import SwiftUI
import PencilKit

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    /// Approximate human pen weight, in points. Pencil pressure modulates this
    /// at draw time but the base width keeps casual finger strokes from
    /// rendering as a hairline.
    private static let strokeWidth: CGFloat = 2

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.tool = PKInkingTool(.pen, color: .black, width: Self.strokeWidth)
        view.drawing = drawing
        view.backgroundColor = .clear
        view.isOpaque = false
        view.delegate = context.coordinator
        return view
    }

    /// Propagates external drawing changes into the canvas — symmetric for
    /// both clear (`drawing` flipped to empty) and pre-load (a future
    /// "edit your signature" surface). Guarded by equality so SwiftUI
    /// re-renders during an active stroke don't interrupt PencilKit's
    /// gesture state.
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: SignatureCanvas

        init(_ parent: SignatureCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
