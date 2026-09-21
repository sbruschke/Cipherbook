import Foundation

/// The distinct noises a key press can make. One sound per event, so a theme is
/// five files (or five system clicks), not one per letter.
enum KeySoundEvent: String, CaseIterable, Identifiable {
    case key, space, delete, newline, modifier

    var id: String { rawValue }

    /// Label used in the app's settings and as the custom file's base name.
    var title: String {
        switch self {
        case .key: return "Letters & numbers"
        case .space: return "Space"
        case .delete: return "Delete"
        case .newline: return "Return"
        case .modifier: return "Shift, 123, 🌐"
        }
    }

    /// The bundled Typewriter theme's file for this event.
    var typewriterResource: String {
        switch self {
        case .key: return "tw-key"
        case .space: return "tw-space"
        case .delete: return "tw-delete"
        case .newline: return "tw-return"
        case .modifier: return "tw-modifier"
        }
    }
}

enum KeySoundTheme: String, CaseIterable, Identifiable {
    /// Silent, whatever the system keyboard-click setting says.
    case off
    /// `UIDevice.playInputClick()` — the stock iOS click, and the only one that
    /// honours Settings › Sounds › Keyboard Clicks.
    case system
    /// The bundled synthesised clacks.
    case typewriter
    /// One imported file per event; anything left unset falls back to Typewriter.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .system: return "Default (iOS)"
        case .typewriter: return "Typewriter"
        case .custom: return "Custom"
        }
    }
}

extension SharedKeyboard {
    /// Imported key sounds live beside the keyboard fonts in the App Group.
    static var soundsDir: URL? {
        containerURL?.appendingPathComponent("KeyboardSounds", isDirectory: true)
    }

    /// File types `AudioServicesCreateSystemSoundID` can actually open.
    static let soundExtensions = ["wav", "aif", "aiff", "caf"]

    /// Copies `source` in as the sound for `event` and returns its file name.
    /// Only the app calls this; the keyboard just reads.
    static func stageSound(_ source: URL, for event: KeySoundEvent) -> String? {
        guard let dir = soundsDir else { return nil }
        let ext = source.pathExtension.lowercased()
        guard soundExtensions.contains(ext) else { return nil }
        // Files picked through the document browser arrive security-scoped.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // The file name carries the event, so re-importing replaces the old one
        // even when the extension changes.
        clearSound(for: event)
        let dest = dir.appendingPathComponent("\(event.rawValue).\(ext)")
        do { try fm.copyItem(at: source, to: dest) } catch { return nil }
        return dest.lastPathComponent
    }

    static func clearSound(for event: KeySoundEvent) {
        guard let dir = soundsDir else { return }
        for ext in soundExtensions {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(event.rawValue).\(ext)"))
        }
    }

    static func soundURL(named file: String) -> URL? {
        guard let url = soundsDir?.appendingPathComponent(file),
              FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }
}
