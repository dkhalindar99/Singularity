// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import PencilKit
import SwiftUI
import UIKit

public enum LiveTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser, text, laser

    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .text: return "textformat"
        case .laser: return "cursorarrow.rays"
        }
    }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .text: return "Text"
        case .laser: return "Laser pointer"
        }
    }

    /// The laser changes nothing in the notebook, so it works even when
    /// drawing is locked.
    var changesNotebook: Bool { self != .laser }
}

/// The toolbar's choices, shared by the toolbar and the page.
@MainActor
final class LiveToolState: ObservableObject {
    @Published var tool: LiveTool = .pen
    @Published var color: LiveColor
    @Published var penWidth: Double = 2.5
    @Published var highlighterWidth: Double = 16
    /// Off: only Apple Pencil draws and fingers are free to scroll and tap.
    @Published var allowsFingerDrawing = false

    /// The stroke being streamed right now. Not published: it never changes
    /// what is drawn.
    var streamer: LiveInkStreamer?

    static let highlighterAlpha = 0.35

    init(color: LiveColor) {
        self.color = color
    }

    var inkColor: LiveColor {
        guard tool == .highlighter else { return color }
        var translucent = color
        translucent.a = LiveToolState.highlighterAlpha
        return translucent
    }

    var liveInk: LiveInk { tool == .highlighter ? .marker : .pen }
    var width: Double { tool == .highlighter ? highlighterWidth : penWidth }

    func pencilKitTool(canDraw: Bool) -> PKTool? {
        guard canDraw else { return nil }
        switch tool {
        case .pen: return PKInkingTool(.pen, color: UIColor(live: inkColor), width: penWidth)
        case .highlighter: return PKInkingTool(.marker, color: UIColor(live: inkColor), width: highlighterWidth)
        case .eraser, .text, .laser: return nil
        }
    }
}
#endif
