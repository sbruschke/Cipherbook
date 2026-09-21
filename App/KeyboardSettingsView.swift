import AudioToolbox
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
    @Published var soundTheme: KeySoundTheme
    /// Event raw value -> file name in the App Group, for the Custom theme.
    @Published var customSounds: [String: String]
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
        soundTheme = saved.soundTheme
        customSounds = saved.customSounds
    }

    func importSound(_ source: URL, for event: KeySoundEvent) -> Bool {
        guard let file = SharedKeyboard.stageSound(source, for: event) else { return false }
        customSounds[event.rawValue] = file
        return true
    }

    func clearSound(for event: KeySoundEvent) {
        SharedKeyboard.clearSound(for: event)
        customSounds[event.rawValue] = nil
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
        config.soundTheme = soundTheme
        config.customSounds = customSounds
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

    private var soundFooter: String {
        switch keyboard.soundTheme {
        case .off:
            return "The keyboard types silently."
        case .system:
            return "The stock iOS click — the only theme that follows Settings › Sounds & Haptics › Keyboard Feedback."
        case .typewriter:
            return "Built-in typewriter clacks, with the margin bell on return. Tap a row to hear it."
        case .custom:
            return "Pick a .wav, .aiff or .caf for each key — the formats iOS can play as a system sound. Anything left unset uses the typewriter sound. Keep them short; a clip still playing when the next key lands is cut off. Custom sounds need Allow Full Access, like the key font."
        }
    }

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
                Picker("Key sounds", selection: $keyboard.soundTheme) {
                    ForEach(KeySoundTheme.allCases) { Text($0.title).tag($0) }
                }
                if keyboard.soundTheme == .custom {
                    ForEach(KeySoundEvent.allCases) { event in
                        CustomSoundRow(event: event, keyboard: keyboard)
                    }
                } else if keyboard.soundTheme == .typewriter {
                    ForEach(KeySoundEvent.allCases) { event in
                        Button {
                            SoundPreview.play(bundled: event.typewriterResource)
                        } label: {
                            Label(event.title, systemImage: "play.circle")
                        }
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Text(soundFooter)
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
        .onChange(of: keyboard.soundTheme) { _ in keyboard.sync(using: fonts) }
        .onChange(of: keyboard.customSounds) { _ in keyboard.sync(using: fonts) }
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

/// One row of the Custom theme: which file is set, and the buttons to hear,
/// replace or clear it.
private struct CustomSoundRow: View {
    let event: KeySoundEvent
    @ObservedObject var keyboard: KeyboardSettings
    @State private var importing = false
    @State private var failed = false

    private var file: String? { keyboard.customSounds[event.rawValue] }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(failed ? "Couldn't read that file" : (file ?? "Typewriter"))
                    .font(.caption)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                if let file, let url = SharedKeyboard.soundURL(named: file) {
                    SoundPreview.play(url)
                } else {
                    SoundPreview.play(bundled: event.typewriterResource)
                }
            } label: {
                Image(systemName: "play.circle")
            }
            Button("Choose") { importing = true }
            if file != nil {
                Button(role: .destructive) { keyboard.clearSound(for: event) } label: {
                    Image(systemName: "xmark.circle")
                }
            }
        }
        .buttonStyle(.borderless)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: ImportTypes.keySound,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            failed = !keyboard.importSound(url, for: event)
            if failed { keyboard.clearSound(for: event) }
        }
    }
}

/// Plays a sound the same way the keyboard will, so the preview is honest.
private enum SoundPreview {
    private static var current: SystemSoundID = 0

    static func play(bundled name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        play(url)
    }

    static func play(_ url: URL) {
        if current != 0 { AudioServicesDisposeSystemSoundID(current) }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
        current = id
        AudioServicesPlaySystemSound(id)
    }
}
