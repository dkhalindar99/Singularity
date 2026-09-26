// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// Draws ink outside PencilKit (a friend's stroke in progress) as a pen
/// does: smooth quadratic curves through the midpoints of the samples
/// (`InkSmoothing`, shared and tested in LiveCore), each piece at its own
/// point's width. Committed strokes are drawn by PencilKit, which smooths
/// them itself.
enum LiveInkRenderer {
    static func draw(_ samples: [InkSample], color: LiveColor, scale: CGFloat, in context: inout GraphicsContext) {
        let segments = InkSmoothing.segments(samples)
        guard !segments.isEmpty else { return }
        var opaque = color
        opaque.a = 1
        let shading = GraphicsContext.Shading.color(Color(live: opaque))
        // The pieces overlap at their round ends. Drawn opaque into one layer
        // and faded as a whole, a translucent highlighter stays even instead
        // of darkening at every joint.
        var faded = context
        faded.opacity = color.a
        faded.drawLayer { layer in
            for segment in segments {
                var path = Path()
                path.move(to: point(segment.start, scale))
                if let control = segment.control {
                    path.addQuadCurve(to: point(segment.end, scale), control: point(control, scale))
                } else if segment.start == segment.end {
                    // A dot: a zero-length line with round caps.
                    path.addLine(to: CGPoint(x: point(segment.end, scale).x + 0.01, y: point(segment.end, scale).y))
                } else {
                    path.addLine(to: point(segment.end, scale))
                }
                layer.stroke(path, with: shading,
                             style: StrokeStyle(lineWidth: max(1, CGFloat(segment.width) * scale), lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func point(_ sample: InkSample, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(sample.x) * scale, y: CGFloat(sample.y) * scale)
    }
}
#endif
