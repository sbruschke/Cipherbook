import SwiftUI
import JournalCore

struct JournalSettingsView: View {
    @EnvironmentObject var settings: JournalSettings
    @EnvironmentObject var fonts: FontLibrary
    @Environment(\.dismiss) private var dismiss
    var onSync: () -> Void

    var body: some View {
        Form {
            Section("Parchment") {
                Picker("Style", selection: $settings.preset) {
                    ForEach(Preset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                ColorPicker("Ink", selection: hexBinding(Binding(
                    get: { settings.effectiveInkHex }, set: { settings.inkHex = $0 })))
                if settings.inkHex != nil {
                    Button("Use the style's ink") { settings.inkHex = nil }
                }
            }
            Section("Writing") {
                Picker("Font", selection: $settings.mainFontID) {
                    ForEach(fonts.all) { Text($0.display).tag($0.id) }
                }
                Stepper("Size \(Int(settings.fontSize)) pt", value: $settings.fontSize, in: 14...32)
                Toggle("Sub font under each word", isOn: $settings.dualFont)
                if settings.dualFont {
                    Picker("Sub font", selection: $settings.subFontID) {
                        ForEach(fonts.all) { Text($0.display).tag($0.id) }
                    }
                }
            }
            Section("Word art") {
                Toggle("Draw a doodle on each page", isOn: $settings.wordArt)
                if settings.wordArt {
                    VStack(alignment: .leading) {
                        Text("Ink strength").font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $settings.wordArtStrength, in: 0...1)
                    }
                    ColorPicker("Doodle colour", selection: hexBinding($settings.wordArtHex))
                    Toggle("Wrap text around it", isOn: $settings.wrapAroundArt)
                }
            }
            Section("Sync") {
                TextField("Server", text: $settings.serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Token", text: Binding(get: { settings.token }, set: { settings.token = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Sync now") { onSync(); dismiss() }
            }
        }
        .navigationTitle("Journal settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
    }
}
