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

    /// The built-ins offered on each side of the split, plus Custom.
    static let lightChoices: [ReaderTheme] = [.light, .sepia, .custom]
    static let darkChoices: [ReaderTheme] = [.dark, .black, .custom]

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

/// Whether the sub font pairs with whole words or with each letter.
enum SubMatch: String, CaseIterable, Identifiable {
    case word, letter
    var id: String { rawValue }
    var label: String { self == .word ? "Word" : "Letter" }
}

/// Which side of the light/dark split the reader shows. `system` follows iOS.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
}

/// A user-edited palette; one is kept for each side of the light/dark split.
struct CustomPalette: Codable, Equatable {
    var background: String
    var foreground: String
    var muted: String
    var accent: String

    var palette: Palette {
        Palette(background: background, foreground: foreground, muted: muted, accent: accent)
    }
    init(_ p: Palette) {
        background = p.background; foreground = p.foreground; muted = p.muted; accent = p.accent
    }
    init(background: String, foreground: String, muted: String, accent: String) {
        self.background = background; self.foreground = foreground
        self.muted = muted; self.accent = accent
    }

    static let lightDefault = CustomPalette(background: "#fbf7ee", foreground: "#2a2a2e",
                                            muted: "#4f7a5a", accent: "#2b6cb0")
    static let darkDefault = CustomPalette(background: "#101418", foreground: "#e8e2d4",
                                           muted: "#7fb28a", accent: "#7aa9e0")
}

/// How a chapter is laid out: one long scroll, screen-sized pages, or a word at a time.
enum ReadingMode: String, CaseIterable, Identifiable {
    case scroll, paged, word
    var id: String { rawValue }

    var label: String {
        switch self {
        case .scroll: return "Scroll"
        case .paged:  return "Pages"
        case .word:   return "Word"
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
    @Published var colorPunctuation: Bool { didSet { defaults.set(colorPunctuation, forKey: "colorPunctuation") } }
    @Published var punctuationColor: String { didSet { defaults.set(punctuationColor, forKey: "punctuationColor") } }
    /// Punctuation inside the sub annotation is tinted separately, so the two
    /// layers can be told apart (or the sub layer left untinted entirely).
    @Published var colorSubPunctuation: Bool { didSet { defaults.set(colorSubPunctuation, forKey: "colorSubPunctuation") } }
    @Published var subPunctuationColor: String { didSet { defaults.set(subPunctuationColor, forKey: "subPunctuationColor") } }
    @Published var showGrid: Bool     { didSet { defaults.set(showGrid, forKey: "showGrid") } }
    @Published var gridColor: String  { didSet { defaults.set(gridColor, forKey: "gridColor") } }
    @Published var gridDot: Double    { didSet { defaults.set(gridDot, forKey: "gridDot") } }
    @Published var readingMode: ReadingMode { didSet { defaults.set(readingMode.rawValue, forKey: "readingMode") } }
    /// Word-at-a-time text size, as a multiple of the text size.
    @Published var wordScale: Double { didSet { defaults.set(wordScale, forKey: "wordScale") } }
    @Published var subMatch: SubMatch { didSet { defaults.set(subMatch.rawValue, forKey: "subMatch") } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    /// The iOS appearance, for `Appearance.system`; refreshed whenever the app becomes active.
    @Published private(set) var systemIsDark: Bool

    @Published var lightTheme: ReaderTheme { didSet { defaults.set(lightTheme.rawValue, forKey: "lightTheme") } }
    @Published var darkTheme: ReaderTheme  { didSet { defaults.set(darkTheme.rawValue, forKey: "darkTheme") } }
    @Published var lightCustom: CustomPalette { didSet { Self.store(lightCustom, "lightCustom") } }
    @Published var darkCustom: CustomPalette  { didSet { Self.store(darkCustom, "darkCustom") } }

    /// True when the reader is currently showing the dark side.
    var showsDark: Bool {
        switch appearance {
        case .light:  return false
        case .dark:   return true
        case .system: return systemIsDark
        }
    }

    var palette: Palette {
        showsDark ? Self.resolve(darkTheme, darkCustom) : Self.resolve(lightTheme, lightCustom)
    }

    private static func resolve(_ theme: ReaderTheme, _ custom: CustomPalette) -> Palette {
        theme.builtIn ?? custom.palette
    }

    private static func store(_ c: CustomPalette, _ key: String) {
        if let data = try? JSONEncoder().encode(c) { UserDefaults.standard.set(data, forKey: key) }
    }
    private static func load(_ key: String) -> CustomPalette? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(CustomPalette.self, from: $0) }
    }

    func refreshSystemAppearance() {
        let dark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        if dark != systemIsDark { systemIsDark = dark }
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
        colorPunctuation = b("colorPunctuation", false)
        // The blue used for punctuation in the Red Rising print edition.
        punctuationColor = ud.string(forKey: "punctuationColor") ?? "#000091"
        colorSubPunctuation = b("colorSubPunctuation", false)
        subPunctuationColor = ud.string(forKey: "subPunctuationColor") ?? "#000091"
        showGrid  = b("showGrid", false)
        // 0.30 tint on white, the print build's default grid gray.
        gridColor = ud.string(forKey: "gridColor") ?? "#B3B3B3"
        gridDot   = d("gridDot", 1.0)
        readingMode = ReadingMode(rawValue: ud.string(forKey: "readingMode") ?? "") ?? .scroll
        wordScale  = d("wordScale", 2.5)
        subMatch   = SubMatch(rawValue: ud.string(forKey: "subMatch") ?? "") ?? .word
        systemIsDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark

        // Before the light/dark split there was one theme and one custom palette.
        // Keep that look: it moves to whichever side its background belongs on.
        let oldTheme = ReaderTheme(rawValue: ud.string(forKey: "theme") ?? "") ?? .light
        let oldCustom = CustomPalette(
            background: ud.string(forKey: "customBackground") ?? CustomPalette.darkDefault.background,
            foreground: ud.string(forKey: "customForeground") ?? CustomPalette.darkDefault.foreground,
            muted: ud.string(forKey: "customMuted") ?? CustomPalette.darkDefault.muted,
            accent: ud.string(forKey: "customAccent") ?? CustomPalette.darkDefault.accent)
        let oldDark = (oldTheme.builtIn ?? oldCustom.palette).isDark

        appearance = Appearance(rawValue: ud.string(forKey: "appearance") ?? "")
            ?? (oldDark ? .dark : .light)
        lightTheme = ReaderTheme(rawValue: ud.string(forKey: "lightTheme") ?? "")
            ?? (!oldDark ? oldTheme : .light)
        darkTheme = ReaderTheme(rawValue: ud.string(forKey: "darkTheme") ?? "")
            ?? (oldDark ? oldTheme : .dark)
        let oldCustomIsDark = oldCustom.palette.isDark
        lightCustom = Self.load("lightCustom") ?? (oldCustomIsDark ? .lightDefault : oldCustom)
        darkCustom  = Self.load("darkCustom")  ?? (oldCustomIsDark ? oldCustom : .darkDefault)
    }
}
