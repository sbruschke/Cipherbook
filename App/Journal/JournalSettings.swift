import SwiftUI
import JournalCore

@MainActor
final class JournalSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var preset: Preset { didSet { d.set(preset.rawValue, forKey: "j.preset") } }
    @Published var inkHex: String? { didSet { d.set(inkHex, forKey: "j.ink") } }
    @Published var mainFontID: String { didSet { d.set(mainFontID, forKey: "j.mainFont") } }
    @Published var subFontID: String { didSet { d.set(subFontID, forKey: "j.subFont") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "j.fontSize") } }
    @Published var dualFont: Bool { didSet { d.set(dualFont, forKey: "j.dual") } }
    @Published var snapToGrid: Bool { didSet { d.set(snapToGrid, forKey: "j.snap") } }
    @Published var wordArt: Bool { didSet { d.set(wordArt, forKey: "j.art") } }
    /// false (default): the doodle sits under the text. true: text wraps around the doodle's frame.
    @Published var wrapAroundArt: Bool { didSet { d.set(wrapAroundArt, forKey: "j.artWrap") } }
    @Published var wordArtStrength: Double { didSet { d.set(wordArtStrength, forKey: "j.artStrength") } }
    /// The accent the doodle's first words are inked in; later words drift toward the writing ink.
    @Published var wordArtHex: String { didSet { d.set(wordArtHex, forKey: "j.artHex") } }
    @Published var serverURL: String { didSet { d.set(serverURL, forKey: "j.server") } }

    var token: String {
        get { Keychain.get("token") }
        set { Keychain.set(newValue, for: "token"); objectWillChange.send() }
    }

    var effectiveInkHex: String { inkHex ?? preset.style.inkHex }

    init() {
        preset = Preset(rawValue: d.string(forKey: "j.preset") ?? "") ?? .aged
        inkHex = d.string(forKey: "j.ink")
        mainFontID = d.string(forKey: "j.mainFont") ?? "sys:Georgia"
        subFontID = d.string(forKey: "j.subFont") ?? "sys:Georgia"
        fontSize = d.object(forKey: "j.fontSize") as? Double ?? 20
        dualFont = d.object(forKey: "j.dual") as? Bool ?? false
        snapToGrid = d.object(forKey: "j.snap") as? Bool ?? false
        wordArt = d.object(forKey: "j.art") as? Bool ?? true
        wrapAroundArt = d.object(forKey: "j.artWrap") as? Bool ?? false
        wordArtStrength = d.object(forKey: "j.artStrength") as? Double ?? 0.8
        wordArtHex = d.string(forKey: "j.artHex") ?? "#03A3FF"
        serverURL = d.string(forKey: "j.server") ?? "https://journal.dxshdw.dev"
    }
}
