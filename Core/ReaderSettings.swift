import Foundation
import SwiftUI
import UIKit

struct Palette {
    var background: String
    var foreground: String
    var muted: String
    var accent: String

    var isDark: Bool { Palette.luminance(background) < 0.45 }
    var uiBackground: Color { Color(hex: background) }
    var uiForeground: Color { Color(hex: foreground) }
    var uiMuted: Color { Color(hex: muted) }

    static func luminance(_ hex: String) -> Double {
        let c = UIColor(Color(hex: hex))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark, black, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light:  return "Light"
        case .sepia:  return "Sepia"
        case .dark:   return "Dark"
        case .black:  return "Black"
        case .custom: return "Custom"
        }
    }

    /// Nil for `.custom`, whose colors live in ReaderSettings.
    var builtIn: Palette? {
        switch self {
        case .light:
            return Palette(background: "#ffffff", foreground: "#14161a",
                           muted: "#6d7480", accent: "#2b6cb0")
        case .sepia:
            return Palette(background: "#f6ecd9", foreground: "#43382a",
                           muted: "#8a7458", accent: "#8a5a2b")
        case .dark:
            return Palette(background: "#1c1c1e", foreground: "#d9d9de",
                           muted: "#9a9aa2", accent: "#7aa9e0")
        case .black:
            return Palette(background: "#000000", foreground: "#c8c8cc",
                           muted: "#8a8a90", accent: "#7aa9e0")
        case .custom:
            return nil
        }
    }
}

@MainActor
final class ReaderSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mainFontID: String { didSet { defaults.set(mainFontID, forKey: "mainFontID") } }
    @Published var subFontID: String  { didSet { defaults.set(subFontID, forKey: "subFontID") } }
    @Published var fontSize: Double   { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var subScale: Double   { didSet { defaults.set(subScale, forKey: "subScale") } }
    @Published var lineHeight: Double { didSet { defaults.set(lineHeight, forKey: "lineHeight") } }
    @Published var margin: Double     { didSet { defaults.set(margin, forKey: "margin") } }
    @Published var letterSpacing: Double { didSet { defaults.set(letterSpacing, forKey: "letterSpacing") } }
    @Published var justified: Bool    { didSet { defaults.set(justified, forKey: "justified") } }
    @Published var forceSize: Bool    { didSet { defaults.set(forceSize, forKey: "forceSize") } }
    @Published var dualFont: Bool     { didSet { defaults.set(dualFont, forKey: "dualFont") } }
    @Published var swapped: Bool      { didSet { defaults.set(swapped, forKey: "swapped") } }
    @Published var theme: ReaderTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            if theme.builtIn != nil { defaults.set(theme.rawValue, forKey: "lastBuiltInTheme") }
        }
    }

    // Custom theme colors (hex strings).
    @Published var customBackground: String { didSet { defaults.set(customBackground, forKey: "customBackground") } }
    @Published var customForeground: String { didSet { defaults.set(customForeground, forKey: "customForeground") } }
    @Published var customMuted: String      { didSet { defaults.set(customMuted, forKey: "customMuted") } }
    @Published var customAccent: String     { didSet { defaults.set(customAccent, forKey: "customAccent") } }

    var palette: Palette {
        theme.builtIn ?? Palette(background: customBackground,
                                 foreground: customForeground,
                                 muted: customMuted,
                                 accent: customAccent)
    }

    init() {
        let ud = UserDefaults.standard
        func d(_ key: String, _ fallback: Double) -> Double {
            ud.object(forKey: key) as? Double ?? fallback
        }
        func b(_ key: String, _ fallback: Bool) -> Bool {
            ud.object(forKey: key) as? Bool ?? fallback
        }
        mainFontID = ud.string(forKey: "mainFontID") ?? FontChoice.systemDefault.id
        subFontID  = ud.string(forKey: "subFontID")  ?? "sys:Georgia"
        fontSize   = d("fontSize", 19)
        subScale   = d("subScale", 0.6)
        lineHeight = d("lineHeight", 1.6)
        margin     = d("margin", 22)
        letterSpacing = d("letterSpacing", 0)
        justified  = b("justified", false)
        forceSize  = b("forceSize", true)
        dualFont   = b("dualFont", false)
        swapped    = b("swapped", false)
        theme      = ReaderTheme(rawValue: ud.string(forKey: "theme") ?? "") ?? .light
        customBackground = ud.string(forKey: "customBackground") ?? "#101418"
        customForeground = ud.string(forKey: "customForeground") ?? "#e8e2d4"
        customMuted      = ud.string(forKey: "customMuted")      ?? "#7fb28a"
        customAccent     = ud.string(forKey: "customAccent")     ?? "#7aa9e0"
    }
}
