// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// Finds what is under a point on a page, in page coordinates. Used by the
/// stroke eraser and the text tool; kept here so it is the same on every
/// screen and testable without UIKit.
public enum LiveHitTest {
    /// Visible strokes that pass within `radius` of the point (plus half the
    /// stroke's own width), in the page's order.
    public static func strokes(on page: LivePage, x: Double, y: Double, radius: Double) -> [String] {
        page.strokes.compactMap { item in
            guard !item.erased else { return nil }
            return hits(item.stroke, x: x, y: y, radius: radius) ? item.stroke.id : nil
        }
    }

    /// The topmost visible text whose frame contains the point.
    public static func text(on page: LivePage, x: Double, y: Double) -> LiveText? {
        page.texts.last { item in
            let f = item.text.frame
            return !item.erased && x >= f.x && x <= f.x + f.width && y >= f.y && y <= f.y + f.height
        }?.text
    }

    public static func hits(_ stroke: LiveStroke, x: Double, y: Double, radius: Double) -> Bool {
        let points = stroke.points
        guard let first = points.first else { return false }
        let reach = radius + stroke.width / 2
        if points.count == 1 {
            return hypot(first.x - x, first.y - y) <= reach
        }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if distance(x, y, a.x, a.y, b.x, b.y) <= reach { return true }
        }
        return false
    }

    /// Distance from (px, py) to the segment (ax, ay)–(bx, by).
    static func distance(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(px - ax, py - ay) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }
}
