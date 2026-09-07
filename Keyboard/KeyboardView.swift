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
///
/// Every touch is tracked independently: pressing a second key before releasing the
/// first still types both, in the order the fingers lift, so fast typing never drops a
/// letter. A two-finger gesture is only recognised once *both* fingers have actually
/// travelled far enough in the same direction, which is what tells it apart from two
/// keys being hit at the same moment.
final class KeyboardView: UIView, UIInputViewAudioFeedback {
    var layout: KeyboardLayout { didSet { setNeedsLayout(); setNeedsDisplay() } }
    var theme: Theme { didSet { setNeedsDisplay() } }
    var shift: ShiftState = .off { didSet { setNeedsDisplay() } }
    var returnLabel = "↵" { didSet { setNeedsDisplay() } }
    var clicksEnabled = true
    /// Requires Full Access; the controller turns it off when we do not have it.
    var hapticsEnabled = false {
        didSet { if hapticsEnabled { haptics.prepare() } }
    }
    weak var delegate: KeyboardViewDelegate?

    var enableInputClicksWhenVisible: Bool { clicksEnabled }

    struct KeyFrame {
        let key: Key
        let row: Int
        /// Hit area, highlight and label box. The edge keys of a short row stretch out
        /// to the screen edge, so every row reads end to end.
        let frame: CGRect
    }
    private(set) var keyFrames: [KeyFrame] = []

    /// How much of a short row's slack an edge key takes compared with an inner key.
    /// 1 spreads it perfectly evenly; this leaves A and L a little wider without the row
    /// looking lopsided.
    private static let edgeKeyShare = 2

    /// One in-flight finger.
    private final class TouchInfo {
        let start: CGPoint
        let time: TimeInterval
        let key: Key?
        var current: CGPoint
        var timer: Timer?
        /// Backspace auto-repeat fired, so the lift must not type one more.
        var repeated = false
        /// Swallowed by a two-finger gesture.
        var consumed = false
        var popup: AccentPopupView?

        init(start: CGPoint, time: TimeInterval, key: Key?) {
            self.start = start
            self.time = time
            self.key = key
            self.current = start
        }

        var displacement: CGPoint { CGPoint(x: current.x - start.x, y: current.y - start.y) }
        var distance: CGFloat { hypot(displacement.x, displacement.y) }
    }

    private var activeTouches: [UITouch: TouchInfo] = [:]
    /// Set once a two-finger swipe has been recognised and reported, so the fingers
    /// still on the glass do not also type.
    private var twoFingerGestureFired = false
    private var lastShiftTap: TimeInterval = 0
    private let classifier = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init(layout: KeyboardLayout, theme: Theme) {
        self.layout = layout
        self.theme = theme
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
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
            guard !row.isEmpty else { continue }
            let total = CGFloat(layout.rowWidth(r)) * unit
            // Rows narrower than the widest one (asdfghjkl, nine keys in a ten-wide grid)
            // are stretched to fill the screen. The slack is shared by every key so the row
            // keeps an even rhythm, like the original Fleksy; the two edge keys take a
            // slightly larger share because thumbs overshoot the sides of the screen.
            let slack = max(0, bounds.width - total)
            let weights = row.indices.map { $0 == 0 || $0 == row.count - 1 ? KeyboardView.edgeKeyShare : 1 }
            let totalWeight = CGFloat(weights.reduce(0, +))
            var x: CGFloat = 0
            let y = CGFloat(r) * rowH
            for (i, key) in row.enumerated() {
                let w = CGFloat(key.width) * unit + slack * CGFloat(weights[i]) / totalWeight
                frames.append(KeyFrame(key: key, row: r, frame: CGRect(x: x, y: y, width: w, height: rowH)))
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

    /// The key under a point. Edge keys already span to the screen edge, so a point is
    /// only outside every frame when the row is empty.
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

    // MARK: Pressed state

    /// Keys held down right now, derived from the live touches so two fingers on two
    /// keys both light up and lifting one does not clear the other.
    private var pressedKeys: Set<Key> {
        Set(activeTouches.values.filter { !$0.consumed }.compactMap { $0.key })
    }

    /// Repaints only the rows containing `keys`; a full-view redraw on every keystroke
    /// is what made fast typing feel sticky.
    private func redraw(_ keys: [Key?]) {
        let rects = keyFrames.filter { kf in keys.contains { $0 == kf.key } }.map(\.frame)
        guard let first = rects.first else { return }
        setNeedsDisplay(rects.dropFirst().reduce(first) { $0.union($1) })
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let rows = layout.rows
        let rowH = bounds.height / CGFloat(max(rows.count, 1))
        let pressed = pressedKeys
        for r in 0..<rows.count {
            let band = CGRect(x: 0, y: CGFloat(r) * rowH, width: bounds.width, height: rowH + 0.5)
            guard band.intersects(rect) else { continue }
            let color = r == rows.count - 1 ? theme.bottomRowColor : theme.rowColors[r % theme.rowColors.count]
            ctx.setFillColor(UIColor(color).cgColor)
            ctx.fill(band)
        }

        let separator = UIColor(theme.separator).cgColor
        ctx.setStrokeColor(separator)
        ctx.setLineWidth(1 / UIScreen.main.scale)
        let bottomRow = rows.count - 1
        for kf in keyFrames where kf.frame.intersects(rect) {
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
                if theme.separator.a > 0, kf.key != keyFrames.last(where: { $0.row == kf.row })?.key {
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
        let box = kf.frame
        let special = UIColor(theme.specialKeyText)
        if let name = symbolName(for: key),
           let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold)) {
            let tinted = image.withTintColor(special, renderingMode: .alwaysOriginal)
            let size = tinted.size
            tinted.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
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
            name.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
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
        let origin = CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            let key = key(at: p)
            let info = TouchInfo(start: p, time: touch.timestamp, key: key)
            activeTouches[touch] = info
            guard let key else { continue }
            feedback()
            switch key.action {
            case .globe:
                delegate?.keyboardView(self, globeTouched: event)
            case .backspace:
                startBackspaceRepeat(info, key: key)
            case .character where !key.accents.isEmpty:
                startAccentHold(info, key: key)
            default:
                break
            }
        }
        redraw(touches.compactMap { activeTouches[$0]?.key })
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let info = activeTouches[touch] else { continue }
            info.current = touch.location(in: self)
            if let popup = info.popup {
                popup.highlight(atX: convert(info.current, to: popup).x)
            }
        }
        detectTwoFingerGesture()
        if let info = activeTouches.values.first(where: { $0.key?.action == .globe }), !info.consumed {
            delegate?.keyboardView(self, globeTouched: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        var lifted: [Key?] = []
        for touch in touches {
            guard let info = activeTouches.removeValue(forKey: touch) else { continue }
            info.timer?.invalidate()
            lifted.append(info.key)
            info.current = touch.location(in: self)
            guard !info.consumed else { hidePopup(info); continue }
            finish(info, timestamp: touch.timestamp, event: event)
        }
        if activeTouches.isEmpty { twoFingerGestureFired = false }
        redraw(lifted)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        var lifted: [Key?] = []
        for touch in touches {
            guard let info = activeTouches.removeValue(forKey: touch) else { continue }
            info.timer?.invalidate()
            hidePopup(info)
            lifted.append(info.key)
        }
        if activeTouches.isEmpty { twoFingerGestureFired = false }
        redraw(lifted)
    }

    private func feedback() {
        if clicksEnabled { UIDevice.current.playInputClick() }
        if hapticsEnabled {
            haptics.impactOccurred(intensity: 0.6)
            haptics.prepare()
        }
    }

    private func startBackspaceRepeat(_ info: TouchInfo, key: Key) {
        info.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self, weak info] _ in
            guard let self, let info else { return }
            info.repeated = true
            self.delegate?.keyboardView(self, didTap: key)
            info.timer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.delegate?.keyboardView(self, didTap: key)
            }
        }
    }

    private func startAccentHold(_ info: TouchInfo, key: Key) {
        info.timer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self, weak info] _ in
            guard let self, let info, !info.consumed else { return }
            // Only open the popup if the finger has not started a swipe.
            if info.distance < 12 { self.showAccentPopup(for: key, owner: info) }
        }
    }

    /// A two-finger swipe is only a two-finger swipe once both fingers have travelled
    /// past the swipe threshold the same way. Until then the touches stay independent
    /// key presses, so hitting two keys at once types both letters.
    private func detectTwoFingerGesture() {
        guard !twoFingerGestureFired else { return }
        let displacements = activeTouches.values.map { Displacement(dx: $0.displacement.x, dy: $0.displacement.y) }
        guard let direction = classifier.multiFingerSwipe(displacements) else { return }
        twoFingerGestureFired = true
        for info in activeTouches.values {
            info.consumed = true
            info.timer?.invalidate()
            hidePopup(info)
        }
        setNeedsDisplay()
        delegate?.keyboardView(self, didSwipe: direction, fingers: 2, startedOn: nil)
    }

    private func finish(_ info: TouchInfo, timestamp: TimeInterval, event: UIEvent?) {
        guard let key = info.key else { return }

        if key.action == .globe {
            delegate?.keyboardView(self, globeTouched: event)
            return
        }
        if let popup = info.popup {
            let picked = popup.selectedAccent
            hidePopup(info)
            delegate?.keyboardView(self, didPickAccent: picked)
            return
        }
        if info.repeated { return }

        let d = info.displacement
        switch classifier.classify(dx: d.x, dy: d.y, duration: timestamp - info.time) {
        case .tap:
            if key.action == .shift {
                if timestamp - lastShiftTap < 0.35 {
                    lastShiftTap = 0
                    delegate?.keyboardViewDidDoubleTapShift(self)
                } else {
                    lastShiftTap = timestamp
                    delegate?.keyboardView(self, didTap: key)
                }
            } else {
                delegate?.keyboardView(self, didTap: key)
            }
        case .swipe(let dir):
            delegate?.keyboardView(self, didSwipe: dir, fingers: 1, startedOn: key)
        }
    }

    // MARK: Accent popup

    private func showAccentPopup(for key: Key, owner: TouchInfo) {
        guard owner.popup == nil, let frame = frame(for: key), case .character(let c) = key.action else { return }
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
        owner.popup = popup
        popup.highlight(atX: frame.midX - x)
    }

    private func hidePopup(_ info: TouchInfo) {
        info.popup?.removeFromSuperview()
        info.popup = nil
    }
}
