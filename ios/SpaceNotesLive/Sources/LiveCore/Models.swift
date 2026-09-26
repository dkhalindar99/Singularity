// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

import Foundation

// The notebook data the protocol carries. The stroke types mirror the
// notebook's `PortableStroke` JSON field for field, so a notebook stroke
// becomes a live stroke by re-encoding it; this package deliberately does not
// depend on NotebookCore.

/// Straight RGBA, 0...1.
public struct LiveColor: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public struct LivePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Raw force as the capture surface reported it (PencilKit: ~1 is an
    /// average press). Not normalised, as in the notebook.
    public var pressure: Double
    public var timeOffset: Double
    public var width: Double
    public var azimuth: Double?
    public var altitude: Double?

    public init(x: Double, y: Double, pressure: Double, timeOffset: Double, width: Double,
                azimuth: Double? = nil, altitude: Double? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.timeOffset = timeOffset
        self.width = width
        self.azimuth = azimuth
        self.altitude = altitude
    }
}

public enum LiveInk: String, CaseIterable, Sendable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon, reed, unknown
}

public struct LiveStroke: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Kept as the raw string so an ink this build does not know survives a
    /// round trip. Read it through `inkType`.
    public var ink: String
    public var color: LiveColor
    public var width: Double
    /// ISO-8601 with whole seconds, kept as text so it round-trips exactly.
    /// Optional because the protocol's validator does not require it; the
    /// notebook adapter fills it in when it is missing.
    public var createdAt: String?
    public var points: [LivePoint]
    public var captureStamp: Double?

    public init(id: String = LiveIDs.make(), ink: LiveInk, color: LiveColor, width: Double,
                createdAt: String? = LiveDates.now(), points: [LivePoint], captureStamp: Double? = nil) {
        self.id = id
        self.ink = ink.rawValue
        self.color = color
        self.width = width
        self.createdAt = createdAt
        self.points = points
        self.captureStamp = captureStamp
    }

    public var inkType: LiveInk { LiveInk(rawValue: ink) ?? .unknown }

    /// The highlighter is a marker drawn translucent.
    public var isHighlighter: Bool { inkType == .marker && color.a < 1 }

    /// The same stroke with at most `maximum` points, keeping the first and
    /// last and spacing the rest evenly. PencilKit stores fitted control
    /// points rather than raw samples, so a real stroke rarely comes near the
    /// protocol's limit; this keeps a very long one drawable instead of lost.
    public func limitedToMaximumPoints(_ maximum: Int = 5000) -> LiveStroke {
        guard points.count > maximum, maximum >= 2 else { return self }
        var thinned = self
        let last = points.count - 1
        thinned.points = (0..<maximum).map { i in points[Int((Double(i) * Double(last) / Double(maximum - 1)).rounded())] }
        return thinned
    }
}

public struct LiveFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct LiveText: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var frame: LiveFrame
    public var fontSize: Double
    public var color: LiveColor

    public init(id: String = LiveIDs.make(), text: String, frame: LiveFrame, fontSize: Double, color: LiveColor) {
        self.id = id
        self.text = text
        self.frame = frame
        self.fontSize = fontSize
        self.color = color
    }
}

public struct PageBackground: Codable, Hashable, Sendable {
    public enum Template: String, Sendable { case lined, grid, dotted }

    /// What a reader draws. Anything unknown is drawn as blank.
    public enum Resolved: Hashable, Sendable {
        case blank
        case template(Template)
        case image(assetId: String)
    }

    /// Raw, so an unknown kind survives a round trip.
    public var kind: String
    public var template: String?
    public var assetId: String?

    public init(kind: String, template: String? = nil, assetId: String? = nil) {
        self.kind = kind
        self.template = template
        self.assetId = assetId
    }

    public static let blank = PageBackground(kind: "blank")
    public static func template(_ template: Template) -> PageBackground {
        PageBackground(kind: "template", template: template.rawValue)
    }
    public static func image(assetId: String) -> PageBackground {
        PageBackground(kind: "image", assetId: assetId)
    }

    public var resolved: Resolved {
        switch kind {
        case "template":
            if let template, let known = Template(rawValue: template) { return .template(known) }
            return .blank
        case "image":
            if let assetId { return .image(assetId: assetId) }
            return .blank
        default:
            return .blank
        }
    }
}

/// A page without its content: what `page.add` carries.
public struct LivePageSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var width: Double
    public var height: Double
    public var background: PageBackground

    public init(id: String = LiveIDs.make(), width: Double, height: Double, background: PageBackground = .blank) {
        self.id = id
        self.width = width
        self.height = height
        self.background = background
    }

    /// A4 portrait in points, the notebook's default paper.
    public static func a4(id: String = LiveIDs.make(), background: PageBackground = .blank) -> LivePageSpec {
        LivePageSpec(id: id, width: 595, height: 842, background: background)
    }
}

/// A page with its starting content, as `POST /rooms` takes it.
public struct LiveStartingPage: Codable, Hashable, Sendable {
    public var id: String
    public var width: Double
    public var height: Double
    public var background: PageBackground
    public var strokes: [LiveStroke]
    public var texts: [LiveText]

    public init(spec: LivePageSpec, strokes: [LiveStroke] = [], texts: [LiveText] = []) {
        self.id = spec.id
        self.width = spec.width
        self.height = spec.height
        self.background = spec.background
        self.strokes = strokes
        self.texts = texts
    }

    public var spec: LivePageSpec { LivePageSpec(id: id, width: width, height: height, background: background) }
}

public struct LiveStrokeItem: Codable, Hashable, Sendable {
    public var author: String
    public var seq: Int
    public var erased: Bool
    public var stroke: LiveStroke

    public init(author: String, seq: Int, erased: Bool = false, stroke: LiveStroke) {
        self.author = author
        self.seq = seq
        self.erased = erased
        self.stroke = stroke
    }
}

public struct LiveTextItem: Codable, Hashable, Sendable {
    public var author: String
    public var seq: Int
    public var erased: Bool
    public var text: LiveText

    public init(author: String, seq: Int, erased: Bool = false, text: LiveText) {
        self.author = author
        self.seq = seq
        self.erased = erased
        self.text = text
    }
}

/// A page in the room state: the page itself and every item ever added to it,
/// erased ones included (so an undo can bring them back).
public struct LivePage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var width: Double
    public var height: Double
    public var background: PageBackground
    public var strokes: [LiveStrokeItem]
    public var texts: [LiveTextItem]

    public init(spec: LivePageSpec, strokes: [LiveStrokeItem] = [], texts: [LiveTextItem] = []) {
        self.id = spec.id
        self.width = spec.width
        self.height = spec.height
        self.background = spec.background
        self.strokes = strokes
        self.texts = texts
    }

    enum CodingKeys: String, CodingKey { case id, width, height, background, strokes, texts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        background = try c.decode(PageBackground.self, forKey: .background)
        strokes = try c.decodeIfPresent([LiveStrokeItem].self, forKey: .strokes) ?? []
        texts = try c.decodeIfPresent([LiveTextItem].self, forKey: .texts) ?? []
    }

    public var spec: LivePageSpec { LivePageSpec(id: id, width: width, height: height, background: background) }
    public var visibleStrokes: [LiveStroke] { strokes.filter { !$0.erased }.map(\.stroke) }
    public var visibleTexts: [LiveText] { texts.filter { !$0.erased }.map(\.text) }
}

public enum DrawPolicy: String, Codable, CaseIterable, Sendable {
    case everyone, host, pen
}

public struct RoomState: Codable, Hashable, Sendable {
    public static let protocolVersion = 1

    public var `protocol`: Int
    public var seq: Int
    /// Raw, as the reducer stores whatever string it was given. Read it
    /// through `policy`.
    public var drawPolicy: String
    public var penHolder: String?
    public var hostPageId: String?
    public var pages: [LivePage]

    public init(protocol: Int = RoomState.protocolVersion, seq: Int = 0, drawPolicy: String = DrawPolicy.everyone.rawValue,
                penHolder: String? = nil, hostPageId: String? = nil, pages: [LivePage] = []) {
        self.protocol = `protocol`
        self.seq = seq
        self.drawPolicy = drawPolicy
        self.penHolder = penHolder
        self.hostPageId = hostPageId
        self.pages = pages
    }

    public static var empty: RoomState { RoomState() }

    public var policy: DrawPolicy? { DrawPolicy(rawValue: drawPolicy) }

    public func page(_ id: String) -> LivePage? { pages.first { $0.id == id } }
}

public enum LiveIDs {
    /// Uppercase UUID, as Swift writes it. Ids are compared as strings and
    /// never re-cased.
    public static func make() -> String { UUID().uuidString }
}

public enum LiveDates {
    /// ISO-8601 with whole seconds, the notebook's persistence format.
    public static func now(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
