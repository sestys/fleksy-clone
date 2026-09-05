import UIKit
import FleksyCore

/// The bubble shown above a held key with its accented variants.
final class AccentPopupView: UIView {
    private let options: [String]
    private var labels: [UILabel] = []
    private let theme: Theme
    private(set) var selectedIndex = 0
    var itemWidth: CGFloat = 42 { didSet { setNeedsLayout() } }

    var selectedAccent: String { options[selectedIndex] }

    init(options: [String], theme: Theme) {
        self.options = options
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = UIColor(theme.popup)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        for o in options {
            let l = UILabel()
            l.text = o
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 24)
            l.textColor = UIColor(theme.popupText)
            l.layer.cornerRadius = 8
            l.layer.masksToBounds = true
            addSubview(l)
            labels.append(l)
        }
        accessibilityIdentifier = "fleksy.accentPopup"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 6 + CGFloat(i) * itemWidth, y: 4, width: itemWidth, height: bounds.height - 8)
        }
        updateHighlight()
    }

    func highlight(atX x: CGFloat) {
        let idx = Int((x - 6) / itemWidth)
        selectedIndex = max(0, min(options.count - 1, idx))
        updateHighlight()
    }

    private func updateHighlight() {
        for (i, l) in labels.enumerated() {
            let selected = i == selectedIndex
            l.backgroundColor = selected ? UIColor(theme.candidateSelected).withAlphaComponent(0.25) : .clear
            l.font = .systemFont(ofSize: 24, weight: selected ? .semibold : .regular)
        }
    }
}
