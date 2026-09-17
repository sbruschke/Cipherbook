import UIKit
import UIKit.UIGestureRecognizerSubclass

enum KeyPlane { case letters, numbers, symbols }

enum KeyAction: Equatable {
    case character(String)
    case shift
    case delete
    case plane(KeyPlane)
    case space
    case newline
    case globe
    case emoji
}

/// Keyboard extensions drop touches on fully transparent pixels, so anything that should
/// be tappable across its whole frame gets this instead of `.clear`.
let touchableClear = UIColor(white: 1, alpha: 0.001)

struct KeySpec {
    let action: KeyAction
    /// In letter-key widths; 0 stretches to fill the row.
    let width: CGFloat

    init(_ action: KeyAction, width: CGFloat = 1) {
        self.action = action
        self.width = width
    }

    var isCharacter: Bool {
        if case .character = action { return true }
        return false
    }
}

enum KeyLayout {
    static func rows(for plane: KeyPlane, showGlobe: Bool, showEmoji: Bool) -> [[KeySpec]] {
        func chars(_ s: String, width: CGFloat = 1) -> [KeySpec] {
            s.map { KeySpec(.character(String($0)), width: width) }
        }
        var bottom = [KeySpec(.plane(plane == .letters ? .numbers : .letters), width: 1.25)]
        if showEmoji { bottom.append(KeySpec(.emoji, width: 1.25)) }
        if showGlobe { bottom.append(KeySpec(.globe, width: 1.25)) }
        bottom += [KeySpec(.space, width: 0), KeySpec(.newline, width: 2.2)]

        let punctuation = chars(".,?!'", width: 1.44)
        switch plane {
        case .letters:
            return [chars("qwertyuiop"),
                    chars("asdfghjkl"),
                    [KeySpec(.shift, width: 1.3)] + chars("zxcvbnm") + [KeySpec(.delete, width: 1.3)],
                    bottom]
        case .numbers:
            return [chars("1234567890"),
                    chars("-/:;()$&@\""),
                    [KeySpec(.plane(.symbols), width: 1.3)] + punctuation + [KeySpec(.delete, width: 1.3)],
                    bottom]
        case .symbols:
            return [chars("[]{}#%^*+="),
                    chars("_\\|~<>€£¥•"),
                    [KeySpec(.plane(.numbers), width: 1.3)] + punctuation + [KeySpec(.delete, width: 1.3)],
                    bottom]
        }
    }
}

/// Lays key rows out by frame. Key frames abut so there are no dead gaps
/// between keys; each key draws its cap inset inside its frame.
final class KeyboardView: UIView {
    private var rows: [[KeyButton]] = []

    var allKeys: [KeyButton] { rows.flatMap { $0 } }

    var rowHeight: CGFloat {
        bounds.height > 0 ? bounds.height / CGFloat(max(rows.count, 1)) : 54
    }

    func setRows(_ newRows: [[KeyButton]]) {
        allKeys.forEach { $0.removeFromSuperview() }
        rows = newRows
        for key in allKeys { addSubview(key) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 3
        let available = bounds.width - side * 2
        let unit = available / 10
        let height = rowHeight

        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * height
            let fixed = row.reduce(CGFloat(0)) { $0 + $1.spec.width * unit }
            let flexible = row.filter { $0.spec.width == 0 }.count

            func place(_ keys: ArraySlice<KeyButton>, from start: CGFloat, flexWidth: CGFloat = 0) {
                var x = start
                for key in keys {
                    let w = key.spec.width == 0 ? flexWidth : key.spec.width * unit
                    key.frame = CGRect(x: x, y: y, width: w, height: height)
                    x += w
                }
            }

            if flexible > 0 {
                place(row[...], from: side, flexWidth: max(unit, (available - fixed) / CGFloat(flexible)))
            } else if row.count > 2, let first = row.first, let last = row.last,
                      !first.spec.isCharacter, !last.spec.isCharacter {
                // Shift/delete pinned to the edges, characters centred between.
                place(row[0..<1], from: side)
                place(row[(row.count - 1)...], from: bounds.width - side - last.spec.width * unit)
                let middle = row[1..<(row.count - 1)]
                let middleWidth = middle.reduce(CGFloat(0)) { $0 + $1.spec.width * unit }
                place(middle, from: (bounds.width - middleWidth) / 2)
            } else {
                place(row[...], from: (bounds.width - fixed) / 2)
            }
        }
    }
}

final class KeyButton: UIControl {
    let spec: KeySpec
    private let cap = UIView()
    private let label = UILabel()
    private let icon = UIImageView()
    private var normalColor = UIColor.white
    private var pressedColor = UIColor.lightGray

    var capFrame: CGRect { cap.frame }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        backgroundColor = touchableClear  // so the gaps between caps still hit a key
        cap.isUserInteractionEnabled = false
        cap.layer.cornerRadius = 5
        cap.layer.shadowColor = UIColor.black.cgColor
        cap.layer.shadowOpacity = 0.3
        cap.layer.shadowRadius = 0
        cap.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.4
        label.baselineAdjustment = .alignCenters
        icon.contentMode = .center
        addSubview(cap)
        cap.addSubview(label)
        cap.addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { cap.backgroundColor = isHighlighted ? pressedColor : normalColor }
    }

    func setTitle(_ text: String, font: UIFont, color: UIColor) {
        label.isHidden = false
        icon.isHidden = true
        label.text = text
        label.font = font
        label.textColor = color
        accessibilityLabel = text
    }

    func setIcon(_ systemName: String, color: UIColor) {
        label.isHidden = true
        icon.isHidden = false
        icon.image = UIImage(systemName: systemName,
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        icon.tintColor = color
    }

    func setColors(normal: UIColor, pressed: UIColor) {
        normalColor = normal
        pressedColor = pressed
        cap.backgroundColor = isHighlighted ? pressed : normal
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cap.frame = bounds.insetBy(dx: 3, dy: 5.5)
        label.frame = cap.bounds.insetBy(dx: 2, dy: 0)
        icon.frame = cap.bounds
        cap.layer.shadowPath = UIBezierPath(roundedRect: cap.bounds, cornerRadius: 5).cgPath
    }
}

/// The enlarged glyph shown above a character key while it is held.
final class KeyPopup: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.4
        label.baselineAdjustment = .alignCenters
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String, font: UIFont, over key: KeyButton, in host: UIView,
              background: UIColor, ink: UIColor) {
        let cap = key.convert(key.capFrame, to: host)
        let width = cap.width + 24
        let height = min(cap.height * 2.1, cap.maxY)
        let x = min(max(2, cap.midX - width / 2), host.bounds.width - width - 2)
        frame = CGRect(x: x, y: cap.maxY - height, width: width, height: height)
        label.frame = CGRect(x: 2, y: 2, width: width - 4, height: height - cap.height - 4)
        label.text = text
        label.font = font
        label.textColor = ink
        backgroundColor = background
        host.addSubview(self)
    }
}

/// Recognises a finger dragged across the letter keys.
///
/// It stays `.possible` while the touch is still on the key it started on, so taps —
/// sloppy ones included — reach the key as before; it begins only once the finger
/// leaves that key, which cancels the key's own touch.
final class SwipeGestureRecognizer: UIGestureRecognizer {
    /// Frame of the letter key a touch starts on, or nil to refuse the gesture.
    var startKeyFrame: ((CGPoint) -> CGRect?)?
    private(set) var path: [CGPoint] = []
    private var startFrame = CGRect.null

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A second finger means two-thumb typing, not a swipe.
        guard state == .possible, path.isEmpty, touches.count == 1,
              (event.allTouches?.count ?? 1) == 1,
              let touch = touches.first, let view,
              let frame = startKeyFrame?(touch.location(in: view)) else {
            if state == .possible { state = .failed }
            return
        }
        startFrame = frame.insetBy(dx: -frame.width * 0.15, dy: -frame.height * 0.1)
        path = [touch.location(in: view)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        let point = touch.location(in: view)
        path.append(point)
        switch state {
        case .possible where !startFrame.contains(point): state = .began
        case .began, .changed: state = .changed
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { path.append(touch.location(in: view)) }
        state = state == .began || state == .changed ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        path = []
        startFrame = .null
    }
}

/// The fading line drawn under the finger while swiping.
final class SwipeTrail: UIView {
    private let line = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        line.fillColor = nil
        line.lineWidth = 7
        line.lineCap = .round
        line.lineJoin = .round
        layer.addSublayer(line)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func draw(_ points: [CGPoint], color: UIColor) {
        line.removeAllAnimations()
        line.opacity = 1
        line.strokeColor = color.withAlphaComponent(0.55).cgColor
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = path.cgPath
        CATransaction.commit()
    }

    func fade() {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [line] in line.path = nil }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.2
        line.opacity = 0
        line.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}

struct Suggestion: Equatable {
    /// `prediction`: a next word, inserted rather than replacing anything.
    /// `swiped`: the word a swipe just inserted, shown so its alternatives read as such.
    enum Kind { case literal, autocorrect, candidate, prediction, swiped }
    let text: String
    let kind: Kind
}

final class SuggestionBar: UIView {
    var onSelect: ((Suggestion) -> Void)?

    private var buttons: [UIButton] = []
    private var dividers: [UIView] = []
    private let hintLabel = UILabel()
    private var items: [Suggestion] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = touchableClear
        for index in 0..<3 {
            let button = UIButton(type: .custom)
            button.tag = index
            button.layer.cornerRadius = 6
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.5
            button.titleLabel?.lineBreakMode = .byClipping
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        for _ in 0..<2 {
            let divider = UIView()
            addSubview(divider)
            dividers.append(divider)
        }
        hintLabel.textAlignment = .center
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.7
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ newItems: [Suggestion], font: UIFont, dark: Bool, hint: String?) {
        items = Array(newItems.prefix(3))
        let ink: UIColor = dark ? .white : .black
        let quote = items.contains { $0.kind != .literal }

        for (index, button) in buttons.enumerated() {
            guard index < items.count else {
                button.isHidden = true
                continue
            }
            let item = items[index]
            let text = item.kind == .literal && quote ? "\u{201C}\(item.text)\u{201D}" : item.text
            button.isHidden = false
            button.setAttributedTitle(NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: ink,
            ]), for: .normal)
            button.backgroundColor = item.kind == .autocorrect || item.kind == .swiped
                ? (dark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 1, alpha: 0.85))
                : touchableClear
        }
        for (index, divider) in dividers.enumerated() {
            divider.backgroundColor = ink.withAlphaComponent(0.2)
            divider.isHidden = index + 1 >= items.count
        }
        hintLabel.text = hint
        hintLabel.textColor = ink.withAlphaComponent(0.6)
        hintLabel.isHidden = hint == nil || !items.isEmpty
    }

    @objc private func tapped(_ sender: UIButton) {
        guard sender.tag < items.count else { return }
        onSelect?(items[sender.tag])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let slot = bounds.width / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * slot, y: 0, width: slot, height: bounds.height)
                .insetBy(dx: 2, dy: 2)
        }
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: CGFloat(index + 1) * slot - 0.5, y: bounds.height * 0.25,
                                   width: 1, height: bounds.height * 0.5)
        }
        hintLabel.frame = bounds.insetBy(dx: 12, dy: 0)
    }
}
