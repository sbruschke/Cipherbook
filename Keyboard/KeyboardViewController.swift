import UIKit

/// A QWERTY keyboard that types plain English but draws its keys (and,
/// optionally, its suggestions) in the font chosen in Cipherbook.
final class KeyboardViewController: UIInputViewController {
    private enum ShiftState { case off, on, locked }

    private var config = KeyboardConfig()
    private var glyphName: String?
    private var fontMissing = false

    private var plane: KeyPlane = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    /// Set right after an autocorrection so the next backspace undoes it.
    private var revert: (inserted: String, original: String)?

    private let bar = SuggestionBar()
    private let keyboard = KeyboardView()
    private let popup = KeyPopup()
    private let engine = SuggestionEngine()
    private var heightConstraint: NSLayoutConstraint!
    private var deleteDelay: Timer?
    private var deleteRepeat: Timer?
    private var laidOutRowHeight: CGFloat = 0

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        bar.translatesAutoresizingMaskIntoConstraints = false
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(keyboard)
        bar.onSelect = { [weak self] in self?.apply($0) }

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 262)
        heightConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            heightConstraint,
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 42),
            keyboard.topAnchor.constraint(equalTo: bar.bottomAnchor),
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])

        Task {
            let lexicon = await requestSupplementaryLexicon()
            engine.absorb(lexicon)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfig()
        switch proxy.keyboardType ?? .default {
        case .numberPad, .decimalPad, .numbersAndPunctuation, .phonePad, .asciiCapableNumberPad:
            plane = .numbers
        default:
            plane = .letters
        }
        rebuildKeys()
        refreshAutoShift()
        refreshSuggestions()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let target: CGFloat
        if traitCollection.userInterfaceIdiom == .pad {
            target = 320
        } else {
            target = traitCollection.verticalSizeClass == .compact ? 200 : 262
        }
        if heightConstraint.constant != target { heightConstraint.constant = target }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Glyph sizes follow the row height, which changes with rotation.
        if keyboard.rowHeight != laidOutRowHeight {
            laidOutRowHeight = keyboard.rowHeight
            updateKeyFaces()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Restyle rather than rebuild: a rebuild mid-touch would drop the key press.
        updateKeyFaces()
        refreshAutoShift()
        refreshSuggestions()
    }

    // MARK: Configuration

    private func reloadConfig() {
        config = KeyboardConfig.load()
        switch config.resolveFont() {
        case .system:
            glyphName = nil
            fontMissing = false
        case .named(let name):
            glyphName = name
            fontMissing = false
        case .missing:
            glyphName = nil
            fontMissing = true
        }
    }

    private func glyphFont(_ size: CGFloat) -> UIFont {
        if let name = glyphName, let font = UIFont(name: name, size: size) { return font }
        return .systemFont(ofSize: size)
    }

    private var hint: String? {
        if fontMissing || !config.configured {
            return hasFullAccess ? "Open Cipherbook to choose a key font"
                                 : "Allow Full Access so your font can load"
        }
        return nil
    }

    // MARK: Keys

    private func rebuildKeys() {
        let rows = KeyLayout.rows(for: plane, showGlobe: needsInputModeSwitchKey)
        keyboard.setRows(rows.map { $0.map(makeKey) })
        updateKeyFaces()
    }

    private func makeKey(_ spec: KeySpec) -> KeyButton {
        let key = KeyButton(spec: spec)
        switch spec.action {
        case .globe:
            key.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        case .delete:
            key.addTarget(self, action: #selector(deleteDown), for: .touchDown)
            key.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        case .character:
            key.addTarget(self, action: #selector(characterDown(_:)), for: [.touchDown, .touchDragEnter])
            key.addTarget(self, action: #selector(hidePopup), for: [.touchUpOutside, .touchCancel, .touchDragExit])
            key.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        default:
            key.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        }
        return key
    }

    private var isDark: Bool {
        (proxy.keyboardAppearance ?? .default) == .dark || traitCollection.userInterfaceStyle == .dark
    }

    private func updateKeyFaces() {
        let dark = isDark
        let ink: UIColor = dark ? .white : .black
        let letterKey = dark ? UIColor(white: 0.42, alpha: 1) : .white
        let functionKey = dark ? UIColor(white: 0.26, alpha: 1)
                               : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
        let labelFont = UIFont.systemFont(ofSize: 16)
        let glyphSize = min(max(keyboard.rowHeight * 0.5, 18), 26) * config.glyphScale
        let glyph = glyphFont(glyphSize)
        // "space"/"return" are whole words, so they need the label size rather than the
        // single-glyph size, or they shrink to fit and end up smaller than the letter keys.
        let wordFont = config.cipherFunctionKeys ? glyphFont(labelFont.pointSize) : labelFont

        for key in keyboard.allKeys {
            switch key.spec.action {
            case .character(let c):
                key.setTitle(shift == .off ? c : c.uppercased(), font: glyph, color: ink)
                key.setColors(normal: letterKey, pressed: functionKey)
            case .shift:
                let symbol = shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
                key.setIcon(symbol, color: ink)
                key.setColors(normal: shift == .off ? functionKey : letterKey, pressed: letterKey)
            case .delete:
                key.setIcon("delete.left", color: ink)
                key.setColors(normal: functionKey, pressed: letterKey)
            case .globe:
                key.setIcon("globe", color: ink)
                key.setColors(normal: functionKey, pressed: letterKey)
            case .plane(let target):
                let title = target == .letters ? "ABC" : (target == .numbers ? "123" : "#+=")
                key.setTitle(title, font: labelFont, color: ink)
                key.setColors(normal: functionKey, pressed: letterKey)
            case .space:
                key.setTitle("space", font: wordFont, color: ink)
                key.setColors(normal: letterKey, pressed: functionKey)
            case .newline:
                let returnType = proxy.returnKeyType ?? .default
                if returnType == .default {
                    key.setTitle(returnLabel(returnType), font: wordFont, color: ink)
                    key.setColors(normal: functionKey, pressed: letterKey)
                } else {
                    key.setTitle(returnLabel(returnType), font: wordFont, color: .white)
                    key.setColors(normal: .systemBlue, pressed: functionKey)
                }
            }
        }
    }

    private func returnLabel(_ type: UIReturnKeyType) -> String {
        switch type {
        case .go: return "go"
        case .google, .yahoo, .search: return "search"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .send: return "send"
        case .done: return "done"
        case .emergencyCall: return "Emergency"
        case .continue: return "continue"
        default: return "return"
        }
    }

    // MARK: Touch handling

    @objc private func characterDown(_ key: KeyButton) {
        guard traitCollection.userInterfaceIdiom == .phone,
              case .character(let c) = key.spec.action else { return }
        let dark = isDark
        popup.show(shift == .off ? c : c.uppercased(),
                   font: glyphFont(min(max(keyboard.rowHeight * 0.7, 24), 36) * config.glyphScale),
                   over: key, in: view,
                   background: dark ? UIColor(white: 0.42, alpha: 1) : .white,
                   ink: dark ? .white : .black)
    }

    @objc private func hidePopup() {
        popup.removeFromSuperview()
    }

    @objc private func keyUp(_ key: KeyButton) {
        hidePopup()
        switch key.spec.action {
        case .character(let c):
            typeCharacter(c)
        case .shift:
            tapShift()
        case .plane(let target):
            plane = target
            rebuildKeys()
            refreshAutoShift()
        case .space:
            typeSpace()
        case .newline:
            if !autocorrectCurrentWord(trailing: "\n") {
                revert = nil
                proxy.insertText("\n")
            }
            afterEdit()
        case .delete, .globe:
            break
        }
    }

    @objc private func deleteDown() {
        deleteOnce()
        deleteDelay = Timer.scheduledTimer(timeInterval: 0.45, target: self,
                                           selector: #selector(startDeleteRepeat),
                                           userInfo: nil, repeats: false)
    }

    @objc private func startDeleteRepeat() {
        deleteRepeat = Timer.scheduledTimer(timeInterval: 0.09, target: self,
                                            selector: #selector(deleteOnce),
                                            userInfo: nil, repeats: true)
    }

    @objc private func deleteUp() {
        deleteDelay?.invalidate()
        deleteRepeat?.invalidate()
        deleteDelay = nil
        deleteRepeat = nil
        afterEdit()
    }

    @objc private func deleteOnce() {
        if let r = revert, (proxy.documentContextBeforeInput ?? "").hasSuffix(r.inserted) {
            replaceTrailing(count: r.inserted.count, with: r.original)
        } else {
            proxy.deleteBackward()
        }
        revert = nil
        refreshSuggestions()
    }

    // MARK: Editing

    private func typeCharacter(_ c: String) {
        revert = nil
        proxy.insertText(shift == .off ? c : c.uppercased())
        if shift == .on {
            shift = .off
            updateKeyFaces()
        }
        if plane != .letters, c == "'" {
            plane = .letters
            rebuildKeys()
        }
        afterEdit()
    }

    private func tapShift() {
        let now = Date()
        switch shift {
        case .off:
            shift = .on
        case .on:
            shift = now.timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .off
        case .locked:
            shift = .off
        }
        lastShiftTap = now
        updateKeyFaces()
    }

    private func typeSpace() {
        let now = Date()
        let before = proxy.documentContextBeforeInput ?? ""
        // Double space after a word becomes ". ", as on the system keyboard.
        if now.timeIntervalSince(lastSpaceTap) < 0.35, before.hasSuffix(" "),
           let prior = before.dropLast().last, prior.isLetter || prior.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpaceTap = .distantPast
            revert = nil
        } else {
            lastSpaceTap = now
            if !autocorrectCurrentWord(trailing: " ") {
                revert = nil
                proxy.insertText(" ")
            }
        }
        if plane != .letters {
            plane = .letters
            rebuildKeys()
        }
        afterEdit()
    }

    /// Replaces the word before the caret with the engine's correction.
    private func autocorrectCurrentWord(trailing: String) -> Bool {
        guard config.autocorrect, (proxy.autocorrectionType ?? .default) != .no,
              let word = engine.currentWord(in: proxy.documentContextBeforeInput),
              !(proxy.documentContextAfterInput?.first?.isLetter ?? false),
              let fix = engine.suggest(for: word).correction, fix != word else { return false }
        replaceTrailing(count: word.count, with: fix + trailing)
        revert = (inserted: fix + trailing, original: word)
        return true
    }

    private func apply(_ suggestion: Suggestion) {
        guard let word = engine.currentWord(in: proxy.documentContextBeforeInput) else { return }
        if suggestion.kind == .literal { engine.learn(word) }
        replaceTrailing(count: word.count, with: suggestion.text + " ")
        revert = nil
        afterEdit()
    }

    private func replaceTrailing(count: Int, with text: String) {
        for _ in 0..<count { proxy.deleteBackward() }
        proxy.insertText(text)
    }

    private func afterEdit() {
        refreshAutoShift()
        refreshSuggestions()
    }

    private func refreshAutoShift() {
        guard shift != .locked else { return }
        let wanted: ShiftState = plane == .letters && shouldCapitalize() ? .on : .off
        if wanted != shift {
            shift = wanted
            updateKeyFaces()
        }
    }

    private func shouldCapitalize() -> Bool {
        let before = proxy.documentContextBeforeInput ?? ""
        switch proxy.autocapitalizationType ?? .sentences {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return before.last.map { $0.isWhitespace } ?? true
        case .sentences:
            guard let last = before.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            guard let end = before.trimmingCharacters(in: .whitespaces).last else { return true }
            return ".!?".contains(end) || end.isNewline
        @unknown default:
            return false
        }
    }

    private func refreshSuggestions() {
        let dark = isDark
        let font = config.cipherSuggestions ? glyphFont(18 * config.glyphScale) : .systemFont(ofSize: 17)
        guard let word = engine.currentWord(in: proxy.documentContextBeforeInput) else {
            bar.show([], font: font, dark: dark, hint: hint)
            return
        }
        let result = engine.suggest(for: word)
        var items = [Suggestion(text: word, kind: .literal)]
        if let fix = result.correction, fix != word {
            let autocorrects = config.autocorrect && (proxy.autocorrectionType ?? .default) != .no
            items.append(Suggestion(text: fix, kind: autocorrects ? .autocorrect : .candidate))
        }
        for option in result.options where items.count < 3 && !items.contains(where: { $0.text == option }) {
            items.append(Suggestion(text: option, kind: .candidate))
        }
        bar.show(items, font: font, dark: dark, hint: nil)
    }
}
