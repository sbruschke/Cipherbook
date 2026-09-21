import AudioToolbox
import UIKit

/// Plays the key-press sounds.
///
/// System sounds rather than `AVAudioPlayer`: they mix with whatever else is
/// playing, need no audio session, and go quiet with the ring switch — which is
/// what a keyboard click should do. The cost is that they have no volume
/// control, so a quieter theme means a quieter file.
final class KeySoundPlayer {
    private var theme = KeySoundTheme.system
    private var ids: [KeySoundEvent: SystemSoundID] = [:]

    deinit { dispose() }

    func reload(_ config: KeyboardConfig) {
        guard config.soundTheme != theme || theme == .custom else { return }
        theme = config.soundTheme
        dispose()
        guard theme == .typewriter || theme == .custom else { return }
        for event in KeySoundEvent.allCases {
            guard let url = url(for: event, config: config) else { continue }
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr { ids[event] = id }
        }
    }

    func play(_ event: KeySoundEvent) {
        switch theme {
        case .off:
            return
        case .system:
            UIDevice.current.playInputClick()
        case .typewriter, .custom:
            // An unloadable custom file leaves no id; click instead of going silent.
            guard let id = ids[event] else { return UIDevice.current.playInputClick() }
            AudioServicesPlaySystemSound(id)
        }
    }

    /// Custom files first, then the bundled Typewriter file for anything unset.
    private func url(for event: KeySoundEvent, config: KeyboardConfig) -> URL? {
        if theme == .custom, let file = config.customSounds[event.rawValue],
           let url = SharedKeyboard.soundURL(named: file) {
            return url
        }
        return Bundle(for: KeySoundPlayer.self)
            .url(forResource: event.typewriterResource, withExtension: "wav")
    }

    private func dispose() {
        for id in ids.values { AudioServicesDisposeSystemSoundID(id) }
        ids = [:]
    }
}

/// `playInputClick()` is ignored unless the input view opts in, and the input
/// view here is the one `UIInputViewController` makes for us — so the opt-in has
/// to come from the class rather than an instance we own.
extension UIInputView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
