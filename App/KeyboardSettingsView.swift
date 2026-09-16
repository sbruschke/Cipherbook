import SwiftUI

/// App-side keyboard settings. The keyboard extension can't see the app's own
/// storage, so every change is pushed into the shared App Group container.
@MainActor
final class KeyboardSettings: ObservableObject {
    @Published var fontID: String {
        didSet { UserDefaults.standard.set(fontID, forKey: "keyboardFontID") }
    }
    @Published var cipherSuggestions: Bool
    @Published var cipherFunctionKeys: Bool
    @Published var autocorrect: Bool
    @Published var swipeTyping: Bool
    @Published var glyphScale: Double
    @Published private(set) var sharedStorageReady = SharedKeyboard.containerURL != nil

    init() {
        let saved = KeyboardConfig.load()
        let ud = UserDefaults.standard
        fontID = ud.string(forKey: "keyboardFontID")
            ?? ud.string(forKey: "mainFontID")
            ?? FontChoice.systemDefault.id
        cipherSuggestions = saved.cipherSuggestions
        cipherFunctionKeys = saved.cipherFunctionKeys
        autocorrect = saved.autocorrect
        swipeTyping = saved.swipeTyping
        glyphScale = saved.glyphScale
    }

    func sync(using fonts: FontLibrary) {
        let choice = fonts.choice(for: fontID)
        var config = KeyboardConfig()
        config.fontName = choice.uiName
        config.cipherSuggestions = cipherSuggestions
        config.cipherFunctionKeys = cipherFunctionKeys
        config.autocorrect = autocorrect
        config.swipeTyping = swipeTyping
        config.glyphScale = glyphScale
        if let source = choice.fileURL {
            config.fontFile = SharedKeyboard.stageFont(source)
        }
        config.save()
        sharedStorageReady = SharedKeyboard.containerURL != nil
    }
}

struct KeyboardSettingsView: View {
    @EnvironmentObject var fonts: FontLibrary
    @StateObject private var keyboard = KeyboardSettings()
    @State private var testText = ""

    private var font: FontChoice { fonts.choice(for: keyboard.fontID) }

    var body: some View {
        Form {
            Section("Preview") {
                KeyRowsPreview(font: font, scale: keyboard.glyphScale)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                NavigationLink {
                    FontPickerView(title: "Key font", selection: $keyboard.fontID)
                } label: {
                    LabeledContent("Key font") {
                        Text(font.display).lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Glyph size")
                        Spacer()
                        Text(String(format: "%.0f%%", keyboard.glyphScale * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    Slider(value: $keyboard.glyphScale, in: 0.6...1.6, step: 0.05)
                }
                Toggle("Suggestions in this font", isOn: $keyboard.cipherSuggestions)
                Toggle("Function keys in this font", isOn: $keyboard.cipherFunctionKeys)
                Toggle("Auto-correction", isOn: $keyboard.autocorrect)
                Toggle("Swipe to type", isOn: $keyboard.swipeTyping)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Keys still type ordinary English letters — only what's drawn on them changes. Suggestions and auto-correction come from the iOS English dictionary and your text replacements.")
            }

            Section {
                TextField("Switch to Cipherbook with 🌐 and type here", text: $testText, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Try it")
            }

            Section {
                if keyboard.sharedStorageReady {
                    Text("Settings › General › Keyboard › Keyboards › Add New Keyboard… › Cipherbook")
                    Text("Then tap Cipherbook in that list and turn on Allow Full Access, so the keyboard can read the font you picked here.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("This install can't share fonts with the keyboard", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Keyboards are app extensions, which LiveContainer can't register. Install Cipherbook directly with SideStore (choose Keep App Extensions) to use the keyboard.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Turn it on")
            }
            .font(.footnote)
        }
        .navigationTitle("Cipher keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { keyboard.sync(using: fonts) }
        .onChange(of: keyboard.fontID) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.cipherSuggestions) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.cipherFunctionKeys) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.autocorrect) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.swipeTyping) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.glyphScale) { _ in keyboard.sync(using: fonts) }
    }
}

/// Static QWERTY rows drawn in the chosen font, roughly as the keyboard shows them.
private struct KeyRowsPreview: View {
    let font: FontChoice
    let scale: Double

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, letter in
                        Text(String(letter))
                            .font(uiFont(font, size: 22 * scale))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .frame(width: 26, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray5))
    }
}
