// Copyright (c) 2026 Pillikandla Dada Khalindar. All rights reserved.
// Proprietary and confidential. Use is governed by the LICENSE file.

#if canImport(UIKit) && canImport(PencilKit)
import LiveCore
import SwiftUI
import UIKit

/// Every colour and font SpaceNotes Live draws with, in one place, so the
/// notebook can hand in its own theme with `.liveTheme(_:)`.
public struct LiveTheme {
    public var background: Color
    public var surface: Color
    public var raisedSurface: Color
    /// The page itself. Stays light in dark mode: ink colours are chosen
    /// against paper.
    public var paper: Color
    public var paperRule: Color
    public var primaryText: Color
    public var secondaryText: Color
    public var accent: Color
    public var onAccent: Color
    public var danger: Color
    public var warning: Color
    public var divider: Color
    public var laser: Color
    public var handRaised: Color
    /// The colour swatches in the toolbar.
    public var inkPalette: [LiveColor]
    public var cornerRadius: CGFloat

    public var title: Font
    public var body: Font
    public var label: Font
    public var caption: Font
    /// Text written on the page, at the page's zoom.
    public var pageText: (CGFloat) -> Font

    public init(background: Color, surface: Color, raisedSurface: Color, paper: Color, paperRule: Color,
                primaryText: Color, secondaryText: Color, accent: Color, onAccent: Color, danger: Color, warning: Color,
                divider: Color, laser: Color, handRaised: Color, inkPalette: [LiveColor],
                cornerRadius: CGFloat, title: Font, body: Font, label: Font, caption: Font,
                pageText: @escaping (CGFloat) -> Font) {
        self.background = background
        self.surface = surface
        self.raisedSurface = raisedSurface
        self.paper = paper
        self.paperRule = paperRule
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.onAccent = onAccent
        self.danger = danger
        self.warning = warning
        self.divider = divider
        self.laser = laser
        self.handRaised = handRaised
        self.inkPalette = inkPalette
        self.cornerRadius = cornerRadius
        self.title = title
        self.body = body
        self.label = label
        self.caption = caption
        self.pageText = pageText
    }

    /// Neutral and calm: soft greys, one slate-blue accent.
    public static var standard: LiveTheme {
        LiveTheme(
            background: .liveDynamic(light: 0xF3F4F6, dark: 0x111318),
            surface: .liveDynamic(light: 0xFFFFFF, dark: 0x1B1E24),
            raisedSurface: .liveDynamic(light: 0xFFFFFF, dark: 0x252932),
            paper: Color(liveHex: 0xFFFFFF),
            paperRule: Color(liveHex: 0xD7DCE4),
            primaryText: .liveDynamic(light: 0x1F2430, dark: 0xE8EAEE),
            secondaryText: .liveDynamic(light: 0x6B7280, dark: 0x9AA1AD),
            accent: .liveDynamic(light: 0x4A5D8F, dark: 0x8FA3D6),
            onAccent: .white,
            danger: .liveDynamic(light: 0xC2413B, dark: 0xF0837D),
            warning: .liveDynamic(light: 0xB7791F, dark: 0xF2C26B),
            divider: .liveDynamic(light: 0xE3E6EB, dark: 0x2E333D),
            laser: Color(liveHex: 0xFF3B30),
            handRaised: Color(liveHex: 0xF2B84B),
            inkPalette: [
                LiveColor(r: 0.12, g: 0.14, b: 0.19, a: 1),
                LiveColor(r: 0.20, g: 0.36, b: 0.72, a: 1),
                LiveColor(r: 0.78, g: 0.22, b: 0.20, a: 1),
                LiveColor(r: 0.16, g: 0.55, b: 0.36, a: 1),
                LiveColor(r: 0.93, g: 0.62, b: 0.12, a: 1),
                LiveColor(r: 0.52, g: 0.30, b: 0.70, a: 1),
            ],
            cornerRadius: 12,
            title: .headline,
            body: .body,
            label: .subheadline.weight(.semibold),
            caption: .caption,
            pageText: { size in .system(size: size) }
        )
    }
}

private struct LiveThemeKey: EnvironmentKey {
    static var defaultValue: LiveTheme { .standard }
}

extension EnvironmentValues {
    public var liveTheme: LiveTheme {
        get { self[LiveThemeKey.self] }
        set { self[LiveThemeKey.self] = newValue }
    }
}

extension View {
    /// Gives SpaceNotes Live the host app's look.
    public func liveTheme(_ theme: LiveTheme) -> some View {
        environment(\.liveTheme, theme)
    }
}

extension Color {
    init(liveHex hex: UInt32) {
        self.init(uiColor: UIColor(liveHex: hex))
    }

    static func liveDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(liveHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(live color: LiveColor) {
        self.init(.sRGB, red: color.r, green: color.g, blue: color.b, opacity: color.a)
    }

    /// A member colour from the server (`#RRGGBB`); grey if it cannot be read.
    init(memberHex text: String) {
        self.init(uiColor: UIColor(memberHex: text) ?? .systemGray)
    }
}

extension UIColor {
    convenience init(liveHex hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init?(memberHex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(liveHex: value)
    }

    convenience init(live color: LiveColor) {
        self.init(red: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: CGFloat(color.a))
    }

    var liveColor: LiveColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return LiveColor(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

/// "Asha Rao" → "AR".
func liveInitials(_ name: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
    let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
    return letters.isEmpty ? "?" : letters
}
#endif
