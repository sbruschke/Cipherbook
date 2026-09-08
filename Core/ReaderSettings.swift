import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark, black
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        case .black: return "Black"
        }
    }

    var background: String {
        switch self {
        case .light: return "#ffffff"
        case .sepia: return "#f6ecd9"
        case .dark:  return "#1c1c1e"
        case .black: return "#000000"
        }
    }

    var foreground: String {
        switch self {
        case .light: return "#14161a"
        case .sepia: return "#43382a"
        case .dark:  return "#d9d9de"
        case .black: return "#c8c8cc"
        }
    }

    var muted: String {
        switch self {
        case .light: return "#6d7480"
        case .sepia: return "#8a7458"
        case .dark:  return "#9a9aa2"
        case .black: return "#8a8a90"
        }
    }

    var uiBackground: Color {
        switch self {
        case .light: return Color(red: 1, green: 1, blue: 1)
        case .sepia: return Color(red: 0.965, green: 0.925, blue: 0.851)
        case .dark:  return Color(red: 0.110, green: 0.110, blue: 0.118)
        case .black: return .black
        }
    }

    var isDark: Bool { self == .dark || self == .black }
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
    @Published var dualFont: Bool     { didSet { defaults.set(dualFont, forKey: "dualFont") } }
    @Published var swapped: Bool      { didSet { defaults.set(swapped, forKey: "swapped") } }
    @Published var theme: ReaderTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }

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
        dualFont   = b("dualFont", false)
        swapped    = b("swapped", false)
        theme      = ReaderTheme(rawValue: ud.string(forKey: "theme") ?? "") ?? .light
    }
}
