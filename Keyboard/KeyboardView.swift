import UIKit
import FleksyCore

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTap key: Key)
    func keyboardViewDidDoubleTapShift(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, didSwipe direction: SwipeDirection, fingers: Int, startedOn key: Key?)
    func keyboardView(_ view: KeyboardView, didPickAccent accent: String)
    func keyboardView(_ view: KeyboardView, globeTouched event: UIEvent?)
}

/// The whole key area, drawn by hand (Fleksy style: colour bands, no key borders) and
/// driven by raw touch tracking so taps, swipes, two-finger swipes and long presses
/// can be told apart anywhere on the keyboard.
final class KeyboardView: UIView, UIInputViewAudioFeedback {
    var layout: KeyboardLayout { didSet { setNeedsLayout(); setNeedsDisplay() } }
    var theme: Theme { didSet { setNeedsDisplay() } }
    var shift: ShiftState = .off { didSet { setNeedsDisplay() } }
    var returnLabel = "↵" { didSet { setNeedsDisplay() } }
    var clicksEnabled = true
    weak var delegate: KeyboardViewDelegate?

    var enableInputClicksWhenVisible: Bool { clicksEnabled }

    struct KeyFrame {
        let key: Key
        let row: Int
        let frame: CGRect
    }
    private(set) var keyFrames: [KeyFrame] = []
    private var pressed: Set<Key> = []

    private struct TouchInfo {
        let start: CGPoint
        let time: TimeInterval
        let key: Key?
        var current: CGPoint
    }
    private var activeTouches: [UITouch: TouchInfo] = [:]
    private var multiTouchSession = false
    private var sessionDisplacements: [CGPoint] = []
    private var longPressTimer: Timer?
    private var backspaceTimer: Timer?
    private var backspaceRepeating = false
    private var accentPopup: AccentPopupView?
    private var lastShiftTap: TimeInterval = 0
    private let classifier = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)

    init(layout: KeyboardLayout, theme: Theme) {
        self.layout = layout
        self.theme = theme
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = true
        contentMode = .redraw
        clipsToBounds = false
        accessibilityIdentifier = "fleksy.keyboard"
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        computeFrames()
    }

    private func computeFrames() {
        let rows = layout.rows
        guard !rows.isEmpty, bounds.width > 0 else { keyFrames = []; return }
        let rowH = bounds.height / CGFloat(rows.count)
        let unit = bounds.width / CGFloat(layout.maxRowWidth)
        var frames: [KeyFrame] = []
        for (r, row) in rows.enumerated() {
            let total = CGFloat(layout.rowWidth(r)) * unit
            var x = (bounds.width - total) / 2
            for key in row {
                let w = CGFloat(key.width) * unit
                frames.append(KeyFrame(key: key, row: r, frame: CGRect(x: x, y: CGFloat(r) * rowH, width: w, height: rowH)))
                x += w
            }
        }
        keyFrames = frames
        rebuildAccessibility()
    }

    private func rebuildAccessibility() {
        accessibilityElements = keyFrames.map { kf in
            let el = UIAccessibilityElement(accessibilityContainer: self)
            el.accessibilityFrameInContainerSpace = kf.frame
            el.accessibilityLabel = kf.key.label.isEmpty ? String(describing: kf.key.action) : kf.key.label
            el.accessibilityIdentifier = KeyboardView.identifier(for: kf.key)
            el.accessibilityTraits = .keyboardKey
            return el
        }
    }

    static func identifier(for key: Key) -> String {
        switch key.action {
        case .character(let c): return "key_\(c)"
        case .shift: return "key_shift"
        case .backspace: return "key_backspace"
        case .space: return "key_space"
        case .enter: return "key_enter"
        case .numbers: return "key_numbers"
        case .symbols: return "key_symbols"
        case .letters: return "key_letters"
        case .globe: return "key_globe"
        case .emoji: return "key_emoji"
        }
    }

    /// The key under a point. Rows that are narrower than the view extend their edge keys.
    func key(at point: CGPoint) -> Key? {
        guard !keyFrames.isEmpty else { return nil }
        let rowH = bounds.height / CGFloat(layout.rows.count)
        let row = max(0, min(layout.rows.count - 1, Int(point.y / rowH)))
        let rowKeys = keyFrames.filter { $0.row == row }
        if let hit = rowKeys.first(where: { $0.frame.minX <= point.x && point.x < $0.frame.maxX }) { return hit.key }
        if point.x < (rowKeys.first?.frame.minX ?? 0) { return rowKeys.first?.key }
        return rowKeys.last?.key
    }

    func frame(for key: Key) -> CGRect? {
        keyFrames.first { $0.key == key }?.frame
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let rows = layout.rows
        let rowH = bounds.height / CGFloat(max(rows.count, 1))
        for r in 0..<rows.count {
            let color = r == rows.count - 1 ? theme.bottomRowColor : theme.rowColors[r % theme.rowColors.count]
            ctx.setFillColor(UIColor(color).cgColor)
            ctx.fill(CGRect(x: 0, y: CGFloat(r) * rowH, width: bounds.width, height: rowH + 0.5))
        }

        let separator = UIColor(theme.separator).cgColor
        ctx.setStrokeColor(separator)
        ctx.setLineWidth(1 / UIScreen.main.scale)
        let bottomRow = rows.count - 1
        for kf in keyFrames {
            let f = kf.frame
            if kf.row == bottomRow {
                // Fleksy bottom bar: rounded keys with small gaps.
                let inset = f.insetBy(dx: 3, dy: 5)
                let path = UIBezierPath(roundedRect: inset, cornerRadius: 6).cgPath
                let fill = kf.key.action == .space ? theme.spaceKey : theme.bottomKey
                ctx.setFillColor(UIColor(fill).cgColor)
                ctx.addPath(path); ctx.fillPath()
                if pressed.contains(kf.key) {
                    ctx.setFillColor(UIColor(theme.pressed).cgColor)
                    ctx.addPath(path); ctx.fillPath()
                }
            } else {
                if pressed.contains(kf.key) {
                    ctx.setFillColor(UIColor(theme.pressed).cgColor)
                    ctx.fill(f)
                }
                if theme.separator.a > 0 {
                    ctx.move(to: CGPoint(x: f.maxX, y: f.minY + f.height * 0.28))
                    ctx.addLine(to: CGPoint(x: f.maxX, y: f.maxY - f.height * 0.28))
                    ctx.strokePath()
                }
            }
            drawLabel(for: kf, in: ctx)
        }
    }

    private func symbolName(for key: Key) -> String? {
        switch key.action {
        case .shift: return shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        case .backspace: return "delete.left.fill"
        case .enter: return returnLabel == "↵" ? "return" : nil
        case .globe: return "globe"
        case .emoji: return "face.smiling"
        default: return nil
        }
    }

    private func drawLabel(for kf: KeyFrame, in ctx: CGContext) {
        let key = kf.key
        let special = UIColor(theme.specialKeyText)
        if let name = symbolName(for: key),
           let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)) {
            let tinted = image.withTintColor(special, renderingMode: .alwaysOriginal)
            let size = tinted.size
            tinted.draw(in: CGRect(x: kf.frame.midX - size.width / 2, y: kf.frame.midY - size.height / 2, width: size.width, height: size.height))
            return
        }
        if key.action == .space {
            let name = NSMutableAttributedString()
            let arrow: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: special.withAlphaComponent(0.55)]
            let main: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: special]
            name.append(NSAttributedString(string: "◁   ", attributes: arrow))
            name.append(NSAttributedString(string: key.label, attributes: main))
            name.append(NSAttributedString(string: "   ▷", attributes: arrow))
            let size = name.size()
            name.draw(at: CGPoint(x: kf.frame.midX - size.width / 2, y: kf.frame.midY - size.height / 2))
            return
        }
        var text = key.label
        var font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        var color = UIColor(theme.keyText)
        switch key.action {
        case .character(let c):
            if shift != .off, c.rangeOfCharacter(from: .letters) != nil { text = c.uppercased() }
            if c.rangeOfCharacter(from: .letters) == nil { font = .systemFont(ofSize: 21, weight: .semibold) }
        case .enter:
            text = returnLabel
            font = .systemFont(ofSize: 15, weight: .semibold)
            color = special
        default:
            font = .systemFont(ofSize: 16, weight: .semibold)
            color = special
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: kf.frame.midX - size.width / 2, y: kf.frame.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            let key = key(at: p)
            activeTouches[touch] = TouchInfo(start: p, time: touch.timestamp, key: key, current: p)
        }
        if activeTouches.count >= 2 {
            if !multiTouchSession {
                multiTouchSession = true
                sessionDisplacements = []
                cancelTimers()
                hideAccentPopup()
                pressed.removeAll()
                setNeedsDisplay()
            }
            return
        }
        guard let touch = touches.first, let info = activeTouches[touch], let key = info.key else { return }
        pressed.insert(key)
        setNeedsDisplay()
        if clicksEnabled { UIDevice.current.playInputClick() }
        switch key.action {
        case .globe:
            delegate?.keyboardView(self, globeTouched: event)
        case .backspace:
            backspaceRepeating = false
            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.backspaceRepeating = true
                self.delegate?.keyboardView(self, didTap: key)
                self.backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.keyboardView(self, didTap: key)
                }
            }
        case .character where !key.accents.isEmpty:
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in
                guard let self, let current = self.activeTouches[touch] else { return }
                // Only open the popup if the finger has not started a swipe.
                let d = hypot(current.current.x - current.start.x, current.current.y - current.start.y)
                if d < 12 { self.showAccentPopup(for: key) }
            }
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard var info = activeTouches[touch] else { continue }
            info.current = touch.location(in: self)
            activeTouches[touch] = info
            if let popup = accentPopup {
                popup.highlight(atX: convert(info.current, to: popup).x)
            }
        }
        if let key = activeTouches.values.first?.key, key.action == .globe {
            delegate?.keyboardView(self, globeTouched: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let info = activeTouches.removeValue(forKey: touch) else { continue }
            let end = touch.location(in: self)
            if multiTouchSession {
                sessionDisplacements.append(CGPoint(x: end.x - info.start.x, y: end.y - info.start.y))
                if activeTouches.isEmpty { finishMultiTouchSession(duration: touch.timestamp - info.time) }
                continue
            }
            finishSingleTouch(info: info, end: end, timestamp: touch.timestamp, event: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { activeTouches.removeValue(forKey: touch) }
        if activeTouches.isEmpty {
            multiTouchSession = false
            sessionDisplacements = []
        }
        cancelTimers()
        hideAccentPopup()
        pressed.removeAll()
        setNeedsDisplay()
    }

    private func finishMultiTouchSession(duration: TimeInterval) {
        multiTouchSession = false
        let n = CGFloat(max(sessionDisplacements.count, 1))
        let dx = sessionDisplacements.reduce(0) { $0 + $1.x } / n
        let dy = sessionDisplacements.reduce(0) { $0 + $1.y } / n
        sessionDisplacements = []
        if case .swipe(let dir) = classifier.classify(dx: dx, dy: dy, duration: duration) {
            delegate?.keyboardView(self, didSwipe: dir, fingers: 2, startedOn: nil)
        }
    }

    private func finishSingleTouch(info: TouchInfo, end: CGPoint, timestamp: TimeInterval, event: UIEvent?) {
        cancelTimers()
        if let key = info.key { pressed.remove(key) }
        setNeedsDisplay()
        guard let key = info.key else { return }

        if key.action == .globe {
            delegate?.keyboardView(self, globeTouched: event)
            return
        }
        if let popup = accentPopup {
            let picked = popup.selectedAccent
            hideAccentPopup()
            delegate?.keyboardView(self, didPickAccent: picked)
            return
        }
        if backspaceRepeating {
            backspaceRepeating = false
            return
        }
        let gesture = classifier.classify(dx: end.x - info.start.x, dy: end.y - info.start.y, duration: timestamp - info.time)
        switch gesture {
        case .tap:
            if key.action == .shift {
                let now = timestamp
                if now - lastShiftTap < 0.35 {
                    lastShiftTap = 0
                    delegate?.keyboardViewDidDoubleTapShift(self)
                } else {
                    lastShiftTap = now
                    delegate?.keyboardView(self, didTap: key)
                }
            } else {
                delegate?.keyboardView(self, didTap: key)
            }
        case .swipe(let dir):
            delegate?.keyboardView(self, didSwipe: dir, fingers: 1, startedOn: key)
        }
    }

    private func cancelTimers() {
        longPressTimer?.invalidate(); longPressTimer = nil
        backspaceTimer?.invalidate(); backspaceTimer = nil
    }

    // MARK: Accent popup

    private func showAccentPopup(for key: Key) {
        guard accentPopup == nil, let frame = frame(for: key), case .character(let c) = key.action else { return }
        let base = shift != .off ? c.uppercased() : c
        let options = [base] + key.accents.map { shift != .off ? $0.uppercased() : $0 }
        let popup = AccentPopupView(options: options, theme: theme)
        let itemW: CGFloat = max(frame.width, 42)
        let width = itemW * CGFloat(options.count) + 12
        var x = frame.midX - width / 2
        x = max(4, min(bounds.width - width - 4, x))
        popup.frame = CGRect(x: x, y: frame.minY - 62, width: width, height: 56)
        popup.itemWidth = itemW
        addSubview(popup)
        accentPopup = popup
        popup.highlight(atX: frame.midX - x)
    }

    private func hideAccentPopup() {
        accentPopup?.removeFromSuperview()
        accentPopup = nil
    }
}
