import SwiftUI
import PencilKit

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.tool = PKInkingTool(.pen, color: .black, width: 2)
        view.drawing = drawing
        view.backgroundColor = .clear
        view.isOpaque = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if drawing.strokes.isEmpty && !uiView.drawing.strokes.isEmpty {
            uiView.drawing = PKDrawing()
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
