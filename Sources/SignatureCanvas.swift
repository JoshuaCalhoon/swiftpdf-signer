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

        // Publish at stroke boundaries rather than per Pencil sample.
        // `canvasViewDrawingDidChange` fires at 60-120 Hz during an active
        // stroke and churns SwiftUI's update graph for no benefit — every
        // sample wakes FormView's onChange(signature) hook, which short-
        // circuits via `pendingUpload == nil` but still re-evaluates the
        // view body. `canvasViewDidEndUsingTool` fires once per stroke
        // completion (5-15× for a typical signature), which is the cadence
        // any consumer of `@Binding<PKDrawing>` actually wants.
        //
        // Trade-off: the binding lags during an in-progress stroke, so any
        // future "live signature preview elsewhere on screen" would need a
        // separate mechanism. No current consumer needs that. A partial
        // stroke abandoned by the user (e.g., screen exits mid-stroke) is
        // lost — that's correct; a half-stroke isn't a valid signature.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
