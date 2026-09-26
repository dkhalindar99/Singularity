// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI

/// Tools, colours, finger drawing, undo and redo. Anything that changes the
/// notebook is greyed out while drawing is locked.
struct LiveToolbar: View {
    @ObservedObject var tools: LiveToolState
    let canDraw: Bool
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    @Environment(\.liveTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LiveTool.allCases) { tool in
                    toolButton(tool)
                }
                divider
                ForEach(Array(theme.inkPalette.enumerated()), id: \.offset) { _, color in
                    swatch(color)
                }
                divider
                Button {
                    tools.allowsFingerDrawing.toggle()
                } label: {
                    Image(systemName: tools.allowsFingerDrawing ? "hand.draw.fill" : "hand.draw")
                        .imageScale(.large)
                        .frame(width: 40, height: 40)
                        .foregroundColor(tools.allowsFingerDrawing ? theme.accent : theme.secondaryText)
                }
                .accessibilityLabel(tools.allowsFingerDrawing ? "Finger drawing on" : "Finger drawing off")
                divider
                iconButton("arrow.uturn.backward", label: "Undo", enabled: canDraw && canUndo, action: undo)
                iconButton("arrow.uturn.forward", label: "Redo", enabled: canDraw && canRedo, action: redo)
                if !canDraw {
                    Label("Drawing is locked", systemImage: "lock.fill")
                        .font(theme.caption)
                        .foregroundColor(theme.secondaryText)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(theme.surface)
        .overlay(alignment: .top) { theme.divider.frame(height: 1) }
    }

    private var divider: some View {
        theme.divider.frame(width: 1, height: 28).padding(.horizontal, 4)
    }

    private func toolButton(_ tool: LiveTool) -> some View {
        let enabled = canDraw || !tool.changesNotebook
        let selected = tools.tool == tool
        return Button {
            tools.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .imageScale(.large)
                .frame(width: 40, height: 40)
                .foregroundColor(selected ? theme.onAccent : theme.primaryText)
                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? theme.accent : Color.clear))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatch(_ color: LiveColor) -> some View {
        let selected = tools.color == color
        return Button {
            tools.color = color
            if tools.tool != .pen && tools.tool != .highlighter && tools.tool != .text { tools.tool = .pen }
        } label: {
            Circle()
                .fill(Color(live: color))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(selected ? theme.accent : theme.divider, lineWidth: selected ? 3 : 1).padding(-4))
                .frame(width: 36, height: 40)
        }
        .disabled(!canDraw)
        .opacity(canDraw ? 1 : 0.35)
        .accessibilityLabel("Colour")
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .imageScale(.large)
                .frame(width: 40, height: 40)
                .foregroundColor(theme.primaryText)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
#endif
