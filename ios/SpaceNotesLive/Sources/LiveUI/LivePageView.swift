// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import PencilKit
import SwiftUI
import UIKit

/// One shared page, fitted to the space it is given: background, committed
/// ink, everyone else's ink in progress and pointers, text boxes, and the
/// active tool's input.
struct LivePageView: View {
    @ObservedObject var client: RoomClient
    let page: LivePage
    @ObservedObject var tools: LiveToolState
    @ObservedObject var assets: LiveAssetCache
    @Environment(\.liveTheme) private var theme

    @State private var erasedThisDrag: Set<String> = []
    @State private var localLaser: CGPoint?
    @State private var editing: LiveText?
    @State private var editingIsNew = false
    @State private var draft = ""
    @FocusState private var textFocused: Bool

    /// How far from the pen the eraser reaches, in screen points.
    private let eraserReach: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let scale = fitScale(in: geometry.size)
            let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
            ZStack(alignment: .topLeading) {
                LivePageBackground(background: page.background, scale: scale, assets: assets)
                LivePageCanvas(
                    strokes: page.visibleStrokes,
                    pageSize: pageSize,
                    scale: scale,
                    tool: tools.pencilKitTool(canDraw: client.canDraw),
                    allowsFingerDrawing: tools.allowsFingerDrawing,
                    liveWidth: tools.width,
                    onBegin: beginStroke,
                    onPoints: { points, width in
                        for point in points { tools.streamer?.add(x: point.x, y: point.y, width: width) }
                    },
                    onCancel: {
                        tools.streamer?.cancel()
                        tools.streamer = nil
                    },
                    onStroke: finishStroke
                )
                LiveRemoteOverlay(presence: client.presence,
                                  pageId: page.id,
                                  members: client.members,
                                  localLaser: localLaser,
                                  scale: scale)
                    .allowsHitTesting(false)
                // Tools under the texts: the text being edited must get its
                // own taps. Committed texts ignore touches.
                toolLayer(scale: scale)
                textLayer(scale: scale)
            }
            .frame(width: size.width, height: size.height)
            // A hovering Pencil (or trackpad) shows others where this person
            // is pointing. RoomClient throttles it and sends nothing while a
            // stroke is being drawn.
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard tools.tool != .laser else { return }
                switch phase {
                case .active(let location):
                    client.sendPointer(pageId: page.id, x: Double(location.x / scale), y: Double(location.y / scale), laser: false)
                case .ended:
                    client.hidePointer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var pageSize: CGSize { CGSize(width: page.width, height: page.height) }

    private func fitScale(in available: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0 else { return 1 }
        let fit: CGFloat = min(available.width / pageSize.width, available.height / pageSize.height)
        return max(0.05, fit)
    }

    // MARK: Ink

    private func beginStroke() {
        // A stroke that never produced a PencilKit stroke is closed off.
        tools.streamer?.cancel()
        tools.streamer = client.canDraw
            ? client.beginLiveInk(pageId: page.id, ink: tools.liveInk, color: tools.inkColor, width: tools.width)
            : nil
    }

    private func finishStroke(_ pkStroke: PKStroke) {
        guard client.canDraw else {
            tools.streamer?.cancel()
            tools.streamer = nil
            return
        }
        // PencilKit owns the gesture, so a stroke past 5,000 points is
        // carried on as new strokes when it ends rather than mid-draw.
        let id = tools.streamer?.liveId ?? LiveIDs.make()
        let pieces = LivePencilKit.liveStroke(from: pkStroke, id: id).continuedAtMaximumPoints()
        if let streamer = tools.streamer {
            streamer.finish(pieces[0])
        } else {
            client.addStroke(pageId: page.id, stroke: pieces[0])
        }
        for piece in pieces.dropFirst() {
            client.addStroke(pageId: page.id, stroke: piece)
        }
        tools.streamer = nil
    }

    // MARK: Text

    @ViewBuilder
    private func textLayer(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(page.visibleTexts.filter { $0.id != editing?.id }) { text in
                Text(text.text)
                    .font(theme.pageText(CGFloat(text.fontSize) * scale))
                    .foregroundColor(Color(live: text.color))
                    .frame(width: CGFloat(text.frame.width) * scale, height: CGFloat(text.frame.height) * scale, alignment: .topLeading)
                    .offset(x: CGFloat(text.frame.x) * scale, y: CGFloat(text.frame.y) * scale)
                    .allowsHitTesting(false)
            }
            if let editing {
                TextField("Text", text: $draft, axis: .vertical)
                    .font(theme.pageText(CGFloat(editing.fontSize) * scale))
                    .foregroundColor(Color(live: editing.color))
                    .focused($textFocused)
                    .padding(2)
                    .frame(width: CGFloat(editing.frame.width) * scale, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(theme.accent, lineWidth: 1))
                    .offset(x: CGFloat(editing.frame.x) * scale, y: CGFloat(editing.frame.y) * scale)
                    .onSubmit(commitText)
                    .onChange(of: textFocused) { _, focused in
                        if !focused { commitText() }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func beginText(at point: CGPoint, scale: CGFloat) {
        if editing != nil { commitText() }
        let x = Double(point.x / scale), y = Double(point.y / scale)
        if let existing = LiveHitTest.text(on: page, x: x, y: y) {
            editing = existing
            editingIsNew = false
            draft = existing.text
        } else {
            let width = min(260, max(80, page.width - x - 8))
            editing = LiveText(text: "", frame: LiveFrame(x: x, y: max(0, y - 14), width: width, height: 28),
                               fontSize: 18, color: tools.color)
            editingIsNew = true
            draft = ""
        }
        textFocused = true
    }

    private func commitText() {
        guard var text = editing else { return }
        editing = nil
        textFocused = false
        let content = draft
        guard client.canDraw else { return }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !editingIsNew { client.eraseTexts(pageId: page.id, textIds: [text.id]) }
            return
        }
        guard content != text.text || editingIsNew else { return }
        text.text = content
        let lines = max(1, content.split(separator: "\n", omittingEmptySubsequences: false).count)
        text.frame.height = max(text.frame.height, text.fontSize * 1.35 * Double(lines) + 6)
        client.upsertText(pageId: page.id, text: text)
    }

    // MARK: Eraser, laser and text taps

    @ViewBuilder
    private func toolLayer(scale: CGFloat) -> some View {
        switch tools.tool {
        case .eraser where client.canDraw:
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in erase(at: value.location, scale: scale) }
                    .onEnded { _ in erasedThisDrag = [] })
        case .text where client.canDraw:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in beginText(at: location, scale: scale) }
        case .laser:
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        localLaser = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                        client.sendPointer(pageId: page.id, x: Double(value.location.x / scale), y: Double(value.location.y / scale), laser: true)
                    }
                    .onEnded { _ in
                        localLaser = nil
                        client.hidePointer()
                    })
        default:
            EmptyView()
        }
    }

    private func erase(at location: CGPoint, scale: CGFloat) {
        let hits = LiveHitTest.strokes(on: page, x: Double(location.x / scale), y: Double(location.y / scale),
                                       radius: Double(eraserReach / scale))
        let fresh = hits.filter { !erasedThisDrag.contains($0) }
        guard !fresh.isEmpty else { return }
        erasedThisDrag.formUnion(fresh)
        client.eraseStrokes(pageId: page.id, strokeIds: fresh)
    }
}

/// Paper, ruling, or the page's picture.
struct LivePageBackground: View {
    let background: PageBackground
    let scale: CGFloat
    @ObservedObject var assets: LiveAssetCache
    @Environment(\.liveTheme) private var theme

    /// Ruling spacing in page points.
    private let spacing: CGFloat = 24

    var body: some View {
        ZStack {
            theme.paper
            switch background.resolved {
            case .blank:
                EmptyView()
            case .image(let assetId):
                if let image = assets.image(assetId) {
                    Image(uiImage: image).resizable().interpolation(.high)
                } else {
                    ProgressView()
                }
            case .template(let template):
                Canvas { context, size in
                    let step = spacing * scale
                    guard step > 2 else { return }
                    var path = Path()
                    switch template {
                    case .lined:
                        var y = step * 3
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += step
                        }
                        context.stroke(path, with: .color(theme.paperRule), lineWidth: 1)
                    case .grid:
                        var x = step
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            x += step
                        }
                        var y = step
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += step
                        }
                        context.stroke(path, with: .color(theme.paperRule.opacity(0.7)), lineWidth: 0.75)
                    case .dotted:
                        let radius = max(0.8, 1.1 * scale)
                        var y = step
                        while y < size.height {
                            var x = step
                            while x < size.width {
                                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                                x += step
                            }
                            y += step
                        }
                        context.fill(path, with: .color(theme.paperRule))
                    }
                }
            }
        }
        .task(id: background.assetId) {
            if case .image(let assetId) = background.resolved { await assets.load(assetId) }
        }
    }
}

/// Everyone else's strokes in progress and their pointers, in their colours.
///
/// It observes `client.presence` on its own, so each ink.live redraws this
/// overlay in the next frame without re-rendering the page, and without any
/// animation in between.
struct LiveRemoteOverlay: View {
    @ObservedObject var presence: LivePresence
    let pageId: String
    let members: [Member]
    let localLaser: CGPoint?
    let scale: CGFloat
    @Environment(\.liveTheme) private var theme

    /// A laser dot fades out over this long after its last move.
    private let laserFade: Double = 1.2

    var body: some View {
        let inks = presence.remoteInk.values.filter { $0.pageId == pageId }
        let pointers = presence.pointers.values.filter { $0.pageId == pageId }
        // Only a fading laser needs a clock; ink redraws when it arrives.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pointers.contains { $0.laser } && localLaser == nil)) { _ in
            Canvas { context, _ in
                let now = ProcessInfo.processInfo.systemUptime
                for ink in inks {
                    let samples = ink.points.map { InkSample(x: $0.x, y: $0.y, width: $0.width) }
                    LiveInkRenderer.draw(samples, color: ink.color, scale: scale, in: &context)
                    if let last = ink.points.last, let member = member(ink.uid) {
                        label(member, at: CGPoint(x: CGFloat(last.x) * scale + 10, y: CGFloat(last.y) * scale - 12), in: &context)
                    }
                }
                for pointer in pointers {
                    let center = CGPoint(x: CGFloat(pointer.x) * scale, y: CGFloat(pointer.y) * scale)
                    if pointer.laser {
                        let alpha = max(0, 1 - (now - pointer.updatedAt) / laserFade)
                        guard alpha > 0 else { continue }
                        laserDot(at: center, alpha: alpha, in: &context)
                    } else if let member = member(pointer.uid) {
                        let dot = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                        context.fill(Path(ellipseIn: dot), with: .color(Color(memberHex: member.color)))
                        label(member, at: CGPoint(x: center.x + 10, y: center.y - 12), in: &context)
                    }
                }
                if let localLaser {
                    laserDot(at: CGPoint(x: localLaser.x * scale, y: localLaser.y * scale), alpha: 1, in: &context)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func member(_ uid: String) -> Member? {
        members.first { $0.uid == uid }
    }

    private func laserDot(at center: CGPoint, alpha: Double, in context: inout GraphicsContext) {
        let glow = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        context.fill(Path(ellipseIn: glow), with: .color(theme.laser.opacity(0.25 * alpha)))
        let core = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: core), with: .color(theme.laser.opacity(alpha)))
    }

    private func label(_ member: Member, at point: CGPoint, in context: inout GraphicsContext) {
        let text = context.resolve(Text(member.name).font(theme.caption).foregroundColor(.white))
        let size = text.measure(in: CGSize(width: 200, height: 40))
        let box = CGRect(x: point.x, y: point.y, width: size.width + 10, height: size.height + 4)
        context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Color(memberHex: member.color)))
        context.draw(text, at: CGPoint(x: box.midX, y: box.midY))
    }
}
#endif
