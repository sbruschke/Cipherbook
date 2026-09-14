import Foundation
import CoreText
import UIKit

/// What Cipherbook and its keyboard extension share, through one App Group.
/// Compiled into both targets, so it must stay extension-safe.
enum SharedKeyboard {
    static let baseGroupID = "group.dev.dxshdw.cipherbook"

    /// SideStore/AltStore re-sign with a team-specific group and record the real
    /// identifier in each bundle's Info.plist under `ALTAppGroups`; a normally
    /// signed build keeps the base ID.
    static var groupID: String {
        let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return groups.filter { $0.contains(baseGroupID) }.min { $0.count < $1.count } ?? baseGroupID
    }

    /// Nil when the install has no App Group entitlement (e.g. inside LiveContainer).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var defaults: UserDefaults? {
        containerURL == nil ? nil : UserDefaults(suiteName: groupID)
    }

    static var fontsDir: URL? {
        containerURL?.appendingPathComponent("KeyboardFonts", isDirectory: true)
    }

    /// Copies `source` in as the only keyboard font and returns its file name.
    /// Only the app calls this; the keyboard just reads.
    static func stageFont(_ source: URL) -> String? {
        guard let dir = fontsDir else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != dest.lastPathComponent {
            try? fm.removeItem(at: old)
        }
        if !fm.contentsEqual(atPath: source.path, andPath: dest.path) {
            try? fm.removeItem(at: dest)
            do { try fm.copyItem(at: source, to: dest) } catch { return nil }
        }
        return dest.lastPathComponent
    }

    /// Registers a font file for this process and returns its PostScript name.
    static func registerFont(at url: URL) -> String? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor], let first = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }
}

enum KeyboardGlyphFont {
    case system
    case named(String)
    /// A font was chosen but this process can't read or load it.
    case missing
}

struct KeyboardConfig {
    /// File name inside `SharedKeyboard.fontsDir`, for imported fonts.
    var fontFile: String?
    /// `UIFont(name:)` name, for built-in fonts. Nil with no file means System.
    var fontName: String?
    var cipherSuggestions = true
    var autocorrect = true
    var glyphScale = 1.0
    /// False until the app has written a config the keyboard can see.
    var configured = false

    private enum Key {
        static let fontFile = "kb.fontFile"
        static let fontName = "kb.fontName"
        static let cipherSuggestions = "kb.cipherSuggestions"
        static let autocorrect = "kb.autocorrect"
        static let glyphScale = "kb.glyphScale"
        static let configured = "kb.configured"
    }

    static func load() -> KeyboardConfig {
        var config = KeyboardConfig()
        guard let d = SharedKeyboard.defaults else { return config }
        config.fontFile = d.string(forKey: Key.fontFile)
        config.fontName = d.string(forKey: Key.fontName)
        config.cipherSuggestions = d.object(forKey: Key.cipherSuggestions) as? Bool ?? true
        config.autocorrect = d.object(forKey: Key.autocorrect) as? Bool ?? true
        config.glyphScale = d.object(forKey: Key.glyphScale) as? Double ?? 1.0
        config.configured = d.bool(forKey: Key.configured)
        return config
    }

    func save() {
        guard let d = SharedKeyboard.defaults else { return }
        d.set(fontFile, forKey: Key.fontFile)
        d.set(fontName, forKey: Key.fontName)
        d.set(cipherSuggestions, forKey: Key.cipherSuggestions)
        d.set(autocorrect, forKey: Key.autocorrect)
        d.set(glyphScale, forKey: Key.glyphScale)
        d.set(true, forKey: Key.configured)
    }

    func resolveFont() -> KeyboardGlyphFont {
        if let file = fontFile {
            guard let url = SharedKeyboard.fontsDir?.appendingPathComponent(file),
                  FileManager.default.isReadableFile(atPath: url.path),
                  let name = SharedKeyboard.registerFont(at: url),
                  UIFont(name: name, size: 12) != nil else { return .missing }
            return .named(name)
        }
        if let name = fontName, UIFont(name: name, size: 12) != nil { return .named(name) }
        return .system
    }
}
