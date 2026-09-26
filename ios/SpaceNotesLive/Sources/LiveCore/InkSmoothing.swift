// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

/// A point of ink to draw: where, and how wide the line is there.
public struct InkSample: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }
}

/// One piece of a smoothed stroke: from `start` to `end`, bending towards
/// `control` when it has one, drawn `width` wide with round caps.
public struct InkSegment: Hashable, Sendable {
    public var start: InkSample
    /// nil for a straight piece (the first and last half-segments).
    public var control: InkSample?
    public var end: InkSample
    public var width: Double
}

/// Turns sampled points into a smooth line, the way a pen looks rather than
/// a chain of straight segments: each sampled point becomes the control
/// point of a quadratic curve between the midpoints on either side of it.
/// The line passes through the first and last points exactly. Each piece
/// keeps the width of the point it bends around, so pressure still shows.
/// Kept in LiveCore so the geometry is tested on every platform.
public enum InkSmoothing {
    public static func segments(_ points: [InkSample]) -> [InkSegment] {
        guard let first = points.first else { return [] }
        if points.count == 1 {
            return [InkSegment(start: first, control: nil, end: first, width: first.width)]
        }
        if points.count == 2 {
            let last = points[1]
            return [InkSegment(start: first, control: nil, end: last, width: (first.width + last.width) / 2)]
        }
        var segments: [InkSegment] = []
        segments.reserveCapacity(points.count)
        var from = midpoint(points[0], points[1])
        segments.append(InkSegment(start: first, control: nil, end: from, width: first.width))
        for i in 1..<(points.count - 1) {
            let to = midpoint(points[i], points[i + 1])
            segments.append(InkSegment(start: from, control: points[i], end: to, width: points[i].width))
            from = to
        }
        let last = points[points.count - 1]
        segments.append(InkSegment(start: from, control: nil, end: last, width: last.width))
        return segments
    }

    public static func segments(_ stroke: LiveStroke) -> [InkSegment] {
        segments(stroke.points.map { InkSample(x: $0.x, y: $0.y, width: $0.width) })
    }

    static func midpoint(_ a: InkSample, _ b: InkSample) -> InkSample {
        InkSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, width: (a.width + b.width) / 2)
    }
}
