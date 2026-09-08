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
                    .padding(.vertical, 8)
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
                    slider("Sub size", value: $settings.subScale, range: 0.35...1.0, step: 0.05,
                           format: { String(format: "%.0f%%", $0 * 100) })
                }
            }

            Section("Layout") {
                slider("Text size", value: $settings.fontSize, range: 12...36, step: 1,
                       format: { "\(Int($0)) pt" })
                slider("Line spacing", value: $settings.lineHeight, range: 1.1...3.0, step: 0.1,
                       format: { String(format: "%.1f", $0) })
                slider("Margins", value: $settings.margin, range: 0...60, step: 2,
                       format: { "\(Int($0)) pt" })
                slider("Letter spacing", value: $settings.letterSpacing, range: -1...8, step: 0.5,
                       format: { String(format: "%.1f", $0) })
                Toggle("Justify text", isOn: $settings.justified)
            }

            Section("Theme") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ReaderTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
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

    private let words = ["the", "quick", "brown", "fox"]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(words, id: \.self) { word in
                VStack(spacing: 2) {
                    Text(word).font(uiFont(main, size: settings.fontSize))
                    if settings.dualFont {
                        Text(word)
                            .font(uiFont(sub, size: settings.fontSize * settings.subScale))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
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
