// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import PencilKit
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Two PencilKit canvases stacked, both sized to the page and zoomed to fit:
///
/// - `display` shows every committed stroke from the room state, rebuilt with
///   identity transforms. It takes no touches.
/// - `input` takes the local pen. PencilKit draws the stroke in progress, so
///   it feels exactly like the notebook; when the stroke ends it is handed up,
///   sent to the room and removed from `input`, and from then on `display`
///   draws it like anyone else's.
///
/// Zooming the canvases (rather than scaling the view) keeps ink sharp, and
/// keeps PencilKit's drawing coordinates equal to page coordinates.
struct LivePageCanvas: UIViewRepresentable {
    var strokes: [LiveStroke]
    var pageSize: CGSize
    var scale: CGFloat
    /// nil turns local drawing off (another tool, or drawing is locked).
    var tool: PKTool?
    var allowsFingerDrawing: Bool
    var liveWidth: Double
    var onBegin: () -> Void
    var onPoints: ([CGPoint], Double) -> Void
    var onCancel: () -> Void
    var onStroke: (PKStroke) -> Void

    func makeUIView(context: Context) -> LivePageCanvasHost {
        LivePageCanvasHost()
    }

    func updateUIView(_ host: LivePageCanvasHost, context: Context) {
        host.onBegin = onBegin
        host.onPoints = { points in onPoints(points, liveWidth) }
        host.onCancel = onCancel
        host.onStroke = onStroke
        host.update(pageSize: pageSize, scale: scale, tool: tool, allowsFinger: allowsFingerDrawing)
        host.show(strokes)
    }
}

final class LivePageCanvasHost: UIView, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let display = PKCanvasView()
    let input = PKCanvasView()
    private let observer = LiveTouchObserver()

    var onBegin: (() -> Void)?
    var onPoints: (([CGPoint]) -> Void)?
    var onCancel: (() -> Void)?
    var onStroke: ((PKStroke) -> Void)?

    private var shown: [LiveStroke]?
    private var pageSize = CGSize(width: 1, height: 1)
    private var scale: CGFloat = 1
    private var clearing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for canvas in [display, input] {
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            // Paper is always light; without this PencilKit inverts ink
            // colours in dark mode.
            canvas.overrideUserInterfaceStyle = .light
            canvas.isScrollEnabled = false
            canvas.bouncesZoom = false
            canvas.showsVerticalScrollIndicator = false
            canvas.showsHorizontalScrollIndicator = false
            canvas.contentInsetAdjustmentBehavior = .never
            canvas.pinchGestureRecognizer?.isEnabled = false
            addSubview(canvas)
        }
        display.isUserInteractionEnabled = false
        input.delegate = self

        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = self
        observer.onBegan = { [weak self] point in
            guard let self else { return }
            self.onBegin?()
            self.onPoints?([self.pagePoint(point)])
        }
        observer.onMoved = { [weak self] points in
            guard let self else { return }
            self.onPoints?(points.map(self.pagePoint))
        }
        observer.onCancelled = { [weak self] in self?.onCancel?() }
        input.addGestureRecognizer(observer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(pageSize: CGSize, scale: CGFloat, tool: PKTool?, allowsFinger: Bool) {
        if pageSize != self.pageSize || scale != self.scale {
            self.pageSize = pageSize
            self.scale = scale
            setNeedsLayout()
        }
        if let tool {
            input.tool = tool
            input.isUserInteractionEnabled = true
        } else {
            input.isUserInteractionEnabled = false
        }
        input.drawingPolicy = allowsFinger ? .anyInput : .pencilOnly
        observer.acceptsFinger = allowsFinger
    }

    /// Redraws committed ink only when it actually changed.
    func show(_ strokes: [LiveStroke]) {
        guard strokes != shown else { return }
        shown = strokes
        display.drawing = LivePencilKit.drawing(from: strokes)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for canvas in [display, input] {
            canvas.frame = bounds
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
            canvas.zoomScale = scale
            canvas.contentSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
            canvas.contentOffset = .zero
        }
    }

    private func pagePoint(_ point: CGPoint) -> CGPoint {
        let zoom = max(input.zoomScale, 0.0001)
        return CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    // MARK: PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard canvasView === input, !clearing else { return }
        let finished = canvasView.drawing.strokes
        guard !finished.isEmpty else { return }
        clearing = true
        canvasView.drawing = PKDrawing()
        clearing = false
        // Show it at once, so there is no frame without the stroke before the
        // room state redraws it.
        display.drawing = display.drawing.appending(PKDrawing(strokes: finished))
        shown = nil
        for stroke in finished { onStroke?(stroke) }
    }

    // MARK: UIGestureRecognizerDelegate

    /// The observer only watches; it must never stop PencilKit drawing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Watches the touches PencilKit draws with, so the stroke in progress can
/// be streamed to others. It never recognizes, so it never interferes.
final class LiveTouchObserver: UIGestureRecognizer {
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: (([CGPoint]) -> Void)?
    var onCancelled: (() -> Void)?
    var acceptsFinger = false
    private weak var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, let touch = touches.first, let view else { return }
        guard acceptsFinger || touch.type == .pencil else { return }
        tracked = touch
        onBegan?(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked), let view else { return }
        let samples = event.coalescedTouches(for: tracked) ?? [tracked]
        onMoved?(samples.map { $0.location(in: view) })
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let tracked, touches.contains(tracked) { self.tracked = nil }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let tracked, touches.contains(tracked) {
            self.tracked = nil
            onCancelled?()
        }
    }

    override func reset() {
        super.reset()
        tracked = nil
    }
}
#endif
