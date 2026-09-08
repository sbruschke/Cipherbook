import Foundation
import CoreText
import UIKit

struct FontChoice: Identifiable, Hashable {
    /// Stable token persisted in settings: "sys:Georgia" or "custom:MyRunes.ttf"
    let id: String
    let display: String
    /// CSS `font-family` value used inside the reader web view.
    let cssFamily: String
    /// PostScript/family name usable with `UIFont(name:)`, when known.
    let uiName: String?
    /// Nil for system fonts; the on-disk file for imported ones.
    let fileURL: URL?

    static func system(_ name: String) -> FontChoice {
        FontChoice(id: "sys:\(name)", display: name, cssFamily: "\"\(name)\"",
                   uiName: name, fileURL: nil)
    }

    static let systemDefault = FontChoice(id: "sys:-apple-system",
                                          display: "System",
                                          cssFamily: "-apple-system",
                                          uiName: nil,
                                          fileURL: nil)
}

@MainActor
final class FontLibrary: ObservableObject {
    @Published private(set) var custom: [FontChoice] = []

    static let builtIns: [FontChoice] = [
        .systemDefault,
        .system("New York"), .system("Georgia"), .system("Palatino"),
        .system("Charter"), .system("Iowan Old Style"), .system("Baskerville"),
        .system("Hoefler Text"), .system("Times New Roman"), .system("Athelas"),
        .system("Seravek"), .system("Helvetica Neue"), .system("Avenir Next"),
        .system("Optima"), .system("Verdana"), .system("Trebuchet MS"),
        .system("American Typewriter"), .system("Courier New"), .system("Menlo"),
        .system("Futura"), .system("Gill Sans"), .system("Noteworthy"),
        .system("Marker Felt"), .system("Chalkboard SE"), .system("Bradley Hand"),
        .system("Snell Roundhand"), .system("Papyrus"), .system("Zapfino"),
        .system("Apple Symbols")
    ]

    var all: [FontChoice] { FontLibrary.builtIns + custom }

    init() { reload() }

    func choice(for id: String) -> FontChoice {
        all.first { $0.id == id } ?? .systemDefault
    }

    func reload() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Storage.fontsDir,
                                                 includingPropertiesForKeys: nil)) ?? []
        custom = files
            .filter { ["ttf", "otf", "ttc", "woff", "woff2"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let uiName = FontLibrary.register(url)
                return FontChoice(id: "custom:\(url.lastPathComponent)",
                                  display: uiName ?? url.deletingPathExtension().lastPathComponent,
                                  cssFamily: "\"\(FontLibrary.cssFamilyName(for: url))\"",
                                  uiName: uiName,
                                  fileURL: url)
            }
    }

    /// Deterministic family name so generated `@font-face` blocks match the CSS.
    nonisolated static func cssFamilyName(for url: URL) -> String {
        "cb_" + url.lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
    }

    /// Registers with CoreText so the font can also be previewed in native UI.
    @discardableResult
    nonisolated private static func register(_ url: URL) -> String? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor], let first = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }

    @discardableResult
    func importFont(from source: URL) -> FontChoice? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let dest = Storage.fontsDir.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            return nil
        }
        reload()
        return custom.first { $0.fileURL?.lastPathComponent == dest.lastPathComponent }
    }

    func deleteFont(_ choice: FontChoice) {
        guard let url = choice.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    /// Mirrors every imported font into the book's extraction directory so the
    /// web view's file read-access scope covers the `@font-face` sources.
    func stageFonts(into contentDir: URL) -> [FontChoice] {
        let fm = FileManager.default
        let dir = contentDir.appendingPathComponent(Storage.bookFontDirName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var staged: [FontChoice] = []
        for font in custom {
            guard let src = font.fileURL else { continue }
            let dest = dir.appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: src, to: dest)
            }
            staged.append(FontChoice(id: font.id, display: font.display,
                                     cssFamily: font.cssFamily, uiName: font.uiName,
                                     fileURL: dest))
        }
        return staged
    }
}
