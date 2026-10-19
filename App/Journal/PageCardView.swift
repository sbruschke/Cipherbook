import SwiftUI
import JournalCore

struct PageCardView: View {
    @EnvironmentObject var settings: JournalSettings
    @EnvironmentObject var fonts: FontLibrary
    @Environment(\.wallRenderer) private var renderer
    let page: Page
    var lift: Double = 0
    /// The editor draws its own text view over the parchment.
    var hideText = false
    /// Debounced text for the doodle while typing; nil ⇒ the page's own text.
    var artText: String? = nil
    static let nominal = CGSize(width: 240, height: 320)

    var body: some View {
        let style = settings.preset.style
        renderer.page(PageRenderSpec(
            look: PageLook.make(seed: page.lookSeedValue, preset: settings.preset),
            style: PresetStyle(baseHex: style.baseHex, edgeHex: style.edgeHex, inkHex: settings.effectiveInkHex, wear: style.wear),
            text: hideText ? "" : page.text, ink: Color(hex: settings.effectiveInkHex),
            mainFont: JournalFonts.ui(settings.mainFontID, size: settings.fontSize, fonts: fonts),
            subFont: settings.dualFont ? JournalFonts.ui(settings.subFontID, size: settings.fontSize * 0.55, fonts: fonts) : nil,
            art: settings.wordArt ? WordArtCache.drawing(text: artText ?? page.text, seed: page.lookSeedValue) : nil,
            artStrength: settings.wordArtStrength,
            artColor: Color(hex: settings.wordArtHex),
            exclusion: settings.wordArt && settings.wrapAroundArt ? WordArt.placement(seed: page.lookSeedValue).frame : nil,
            lift: lift, size: Self.nominal))
    }
}

enum JournalFonts {
    @MainActor static func ui(_ id: String, size: Double, fonts: FontLibrary) -> UIFont {
        let c = fonts.choice(for: id)
        if let n = c.uiName, let f = UIFont(name: n, size: size) { return f }
        return UIFont.systemFont(ofSize: size)
    }
}
