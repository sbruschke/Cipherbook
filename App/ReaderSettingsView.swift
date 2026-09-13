import SwiftUI
import UIKit

struct ReaderSettingsView: View {
    @EnvironmentObject var settings: ReaderSettings
    @EnvironmentObject var fonts: FontLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var importingFont = false

    private var mainFont: FontChoice { fonts.choice(for: settings.mainFontID) }
    private var subFont: FontChoice { fonts.choice(for: settings.subFontID) }

    var body: some View {
        Form {
            Section("Preview") {
                DualSample(main: settings.swapped ? subFont : mainFont,
                           sub: settings.swapped ? mainFont : subFont,
                           settings: settings)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(settings.palette.uiBackground)
                    .listRowInsets(EdgeInsets())
            }

            Section("Fonts") {
                NavigationLink {
                    FontPickerView(title: "Main font", selection: $settings.mainFontID)
                } label: {
                    LabeledContent("Main font") {
                        Text(mainFont.display).lineLimit(1)
                    }
                }

                Toggle("Two fonts at once", isOn: $settings.dualFont)

                if settings.dualFont {
                    NavigationLink {
                        FontPickerView(title: "Sub font", selection: $settings.subFontID)
                    } label: {
                        LabeledContent("Sub font") {
                            Text(subFont.display).lineLimit(1)
                        }
                    }
                    Toggle("Swap main and sub", isOn: $settings.swapped)
                    slider("Sub size", value: $settings.subScale, range: 0.25...1.4, step: 0.05,
                           format: { String(format: "%.0f%%", $0 * 100) })
                }
            }

            Section("Layout") {
                slider("Text size", value: $settings.fontSize, range: 10...90, step: 1,
                       format: { "\(Int($0)) pt" })
                slider("Line spacing", value: $settings.lineHeight, range: 0.9...4.0, step: 0.05,
                       format: { String(format: "%.2f", $0) })
                slider("Margins", value: $settings.margin, range: 0...180, step: 2,
                       format: { "\(Int($0)) pt" })
                slider("Letter spacing", value: $settings.letterSpacing, range: -2...16, step: 0.5,
                       format: { String(format: "%.1f", $0) })
                Toggle("Justify text", isOn: $settings.justified)
                Toggle("Override the book's own text sizes", isOn: $settings.forceSize)
            }

            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ReaderTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if settings.theme == .custom {
                    ColorPicker("Background", selection: hexBinding($settings.customBackground))
                    ColorPicker("Main text", selection: hexBinding($settings.customForeground))
                    ColorPicker("Sub text", selection: hexBinding($settings.customMuted))
                    ColorPicker("Links", selection: hexBinding($settings.customAccent))
                    Button("Copy current theme's colors") { seedCustomFromBuiltIn() }
                        .font(.footnote)
                }
            } header: {
                Text("Theme")
            } footer: {
                if settings.theme == .custom {
                    Text("Sub text is the colour of the second font under each word.")
                }
            }

            Section {
                Toggle("Colour punctuation", isOn: $settings.colorPunctuation)
                if settings.colorPunctuation {
                    ColorPicker("Punctuation", selection: hexBinding($settings.punctuationColor))
                    HStack(spacing: 10) {
                        ForEach(PunctuationPreset.all) { preset in
                            Button {
                                settings.punctuationColor = preset.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: preset.hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().strokeBorder(Color.primary.opacity(
                                            settings.punctuationColor.caseInsensitiveCompare(preset.hex) == .orderedSame ? 0.9 : 0.15),
                                            lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Punctuation")
            } footer: {
                Text("Tints every punctuation mark and symbol, as in the printed cipher editions.")
            }

            Section {
                Toggle("Show grid", isOn: $settings.showGrid)
                if settings.showGrid {
                    ColorPicker("Dots", selection: hexBinding($settings.gridColor))
                    slider("Dot size", value: $settings.gridDot, range: 0.4...4.0, step: 0.2,
                           format: { String(format: "%.1f px", $0) })
                }
            } header: {
                Text("Grid")
            } footer: {
                Text("Dots at every character-cell corner — a space wide, a line tall — anchored so the text sits on the grid, like the notebook ruling in the print editions. Line up best with a monospaced main font.")
            }

            Section {
                Button {
                    importingFont = true
                } label: {
                    Label("Import font file…", systemImage: "square.and.arrow.down")
                }
                ForEach(fonts.custom) { font in
                    HStack {
                        Text(font.display)
                            .font(uiFont(font, size: 17))
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            fonts.deleteFont(font)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Custom fonts")
            } footer: {
                Text("Add .ttf/.otf files — cipher, conscript, or runic fonts work well as the main font with a readable sub font underneath.")
            }
        }
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .fileImporter(isPresented: $importingFont,
                      allowedContentTypes: ImportTypes.font,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach { fonts.importFont(from: $0) }
            }
        }
    }

    /// Seeds the custom palette from the last built-in theme so editing starts
    /// from something readable rather than from whatever was there before.
    private func seedCustomFromBuiltIn() {
        let source = ReaderTheme(rawValue: UserDefaults.standard.string(forKey: "lastBuiltInTheme") ?? "")
            ?? .light
        guard let p = source.builtIn else { return }
        settings.customBackground = p.background
        settings.customForeground = p.foreground
        settings.customMuted = p.muted
        settings.customAccent = p.accent
    }

    private func slider(_ title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        step: Double,
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: value, in: range, step: step)
        }
    }
}

func uiFont(_ choice: FontChoice, size: CGFloat) -> Font {
    if let name = choice.uiName, UIFont(name: name, size: size) != nil {
        return .custom(name, size: size)
    }
    return .system(size: size)
}

/// Mirrors the reader's ruby layout: main text with a smaller second font beneath.
struct DualSample: View {
    let main: FontChoice
    let sub: FontChoice
    @ObservedObject var settings: ReaderSettings

    private let words = ["the", "quick,", "brown", "fox."]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(words, id: \.self) { word in
                VStack(spacing: 2) {
                    Text(tinted(word, base: settings.palette.uiForeground))
                        .font(uiFont(main, size: min(settings.fontSize, 34)))
                    if settings.dualFont {
                        Text(tinted(word, base: settings.palette.uiMuted))
                            .font(uiFont(sub, size: min(settings.fontSize, 34) * settings.subScale))
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .background(alignment: .topLeading) {
            if settings.showGrid {
                GridBackdrop(cell: cellSize, dot: settings.gridDot,
                             color: Color(hex: settings.gridColor))
            }
        }
    }

    /// The reader measures this in the page; here the space advance comes from
    /// the registered UIFont, which is close enough for a sample.
    private var cellSize: CGSize {
        let size = min(settings.fontSize, 34)
        let name = main.uiName.flatMap { UIFont(name: $0, size: size) }
        let font = name ?? UIFont.systemFont(ofSize: size)
        let w = (" " as NSString).size(withAttributes: [.font: font]).width
        let lh = settings.dualFont ? settings.lineHeight + 0.9 : settings.lineHeight
        return CGSize(width: max(3, w), height: max(6, size * lh))
    }

    /// Mirrors `ReaderRenderer.punctuationJS`: punctuation and symbols pick up
    /// their own colour, everything else keeps the base one.
    private func tinted(_ word: String, base: Color) -> AttributedString {
        var out = AttributedString()
        let punct = Color(hex: settings.punctuationColor)
        for ch in word {
            var piece = AttributedString(String(ch))
            let isPunct = ch.isPunctuation || ch.isSymbol
            piece.foregroundColor = (settings.colorPunctuation && isPunct) ? punct : base
            out.append(piece)
        }
        return out
    }
}

struct PunctuationPreset: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }

    /// The first is the blue used in the Red Rising print edition.
    static let all = [
        PunctuationPreset(name: "Press blue", hex: "#000091"),
        PunctuationPreset(name: "Crimson", hex: "#A02020"),
        PunctuationPreset(name: "Moss", hex: "#3F6B3F"),
        PunctuationPreset(name: "Amber", hex: "#B7791F"),
        PunctuationPreset(name: "Violet", hex: "#6B46C1"),
        PunctuationPreset(name: "Slate", hex: "#64748B"),
    ]
}

struct FontPickerView: View {
    let title: String
    @Binding var selection: String
    @EnvironmentObject var fonts: FontLibrary
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Button {
                    importing = true
                } label: {
                    Label("Import font file…", systemImage: "square.and.arrow.down")
                }
            }
            if !fonts.custom.isEmpty {
                Section("Imported") { rows(fonts.custom) }
            }
            Section("Built in") { rows(FontLibrary.builtIns) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: ImportTypes.font,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let imported = urls.compactMap { fonts.importFont(from: $0) }
                if let first = imported.first { selection = first.id }
            }
        }
    }

    private func rows(_ list: [FontChoice]) -> some View {
        ForEach(list) { font in
            Button {
                selection = font.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(font.display).font(.caption).foregroundStyle(.secondary)
                        Text("The quick brown fox 0123")
                            .font(uiFont(font, size: 19))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer()
                    if font.id == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// The reader's dot grid, for the settings preview.
struct GridBackdrop: View {
    let cell: CGSize
    let dot: Double
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let r = max(0.4, dot)
            var y = 0.0
            while y <= size.height {
                var x = 0.0
                while x <= size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(color))
                    x += cell.width
                }
                y += cell.height
            }
        }
        .allowsHitTesting(false)
    }
}
