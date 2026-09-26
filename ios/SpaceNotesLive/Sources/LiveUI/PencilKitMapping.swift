// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit

/// PencilKit ↔ LiveStroke, the same mapping as the notebook's
/// `PortableStrokeMapping.swift`. PencilKit is only the input and rendering
/// surface; the room state is the source of truth.
enum LivePencilKit {
    static func inkType(_ ink: LiveInk) -> PKInk.InkType {
        switch ink {
        case .pen: return .pen
        case .pencil: return .pencil
        case .marker: return .marker
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .watercolor: return .watercolor
        case .crayon: return .crayon
        case .reed:
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { return .reed }
            #endif
            return .pen
        case .unknown:
            // No PencilKit equivalent; draw it as a pen rather than lose it.
            return .pen
        }
    }

    static func liveInk(_ type: PKInk.InkType) -> LiveInk {
        switch type {
        case .pen: return .pen
        case .pencil: return .pencil
        case .marker: return .marker
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .watercolor: return .watercolor
        case .crayon: return .crayon
        default:
            #if compiler(>=6.2)
            if #available(iOS 26.0, *), type == .reed { return .reed }
            #endif
            return .unknown
        }
    }

    /// Bakes the stroke's transform into absolute page coordinates (and its
    /// scale into the width), exactly as the notebook's
    /// `extractPortableStrokes` does.
    static func liveStroke(from stroke: PKStroke, id: String) -> LiveStroke {
        let t = stroke.transform
        let widthScale = Double(sqrt(abs(t.a * t.d - t.b * t.c)))
        let points = stroke.path.map { point -> LivePoint in
            let location = point.location.applying(t)
            return LivePoint(x: Double(location.x), y: Double(location.y), pressure: Double(point.force),
                             timeOffset: point.timeOffset, width: Double(point.size.width) * widthScale,
                             azimuth: Double(point.azimuth), altitude: Double(point.altitude))
        }
        let width = points.isEmpty ? 1 : points.reduce(0) { $0 + $1.width } / Double(points.count)
        let created = stroke.path.creationDate
        return LiveStroke(id: id, ink: liveInk(stroke.ink.inkType), color: stroke.ink.color.liveColor, width: width,
                          createdAt: LiveDates.now(created), points: points,
                          captureStamp: created.timeIntervalSince1970)
    }

    /// Coordinates are already absolute, so the transform is always identity;
    /// any other transform would move the ink twice.
    static func pkStroke(from stroke: LiveStroke) -> PKStroke {
        let ink = PKInk(inkType(stroke.inkType), color: UIColor(live: stroke.color))
        let points = stroke.points.map { point in
            PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: point.timeOffset,
                          size: CGSize(width: point.width, height: point.width), opacity: 1,
                          force: CGFloat(point.pressure), azimuth: CGFloat(point.azimuth ?? 0),
                          altitude: CGFloat(point.altitude ?? .pi / 2))
        }
        let created = stroke.captureStamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: created), transform: .identity)
    }

    static func drawing(from strokes: [LiveStroke]) -> PKDrawing {
        PKDrawing(strokes: strokes.map(pkStroke(from:)))
    }
}
#endif
