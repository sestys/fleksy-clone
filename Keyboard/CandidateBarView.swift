import UIKit
import FleksyCore

protocol CandidateBarDelegate: AnyObject {
    func candidateBar(_ bar: CandidateBarView, didSelect index: Int)
    func candidateBarDidTapSettings(_ bar: CandidateBarView)
}

/// Suggestion strip above the keys. Shows up to three candidates around the selected one.
final class CandidateBarView: UIView {
    weak var delegate: CandidateBarDelegate?
    var theme: Theme { didSet { applyTheme() } }
    var items: [CandidateItem] = [] { didSet { rebuild() } }
    var languageHint: String = "" { didSet { rebuild() } }
    /// Transient status shown centred instead of candidates (e.g. "learned").
    var notice: String? { didSet { rebuild() } }

    private let settingsButton = UIButton(type: .custom)
    private let stack = UIStackView()
    private var visibleIndices: [Int] = []
    private var labels: [UILabel] = []

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        accessibilityIdentifier = "fleksy.candidateBar"
        settingsButton.accessibilityIdentifier = "fleksy.settingsButton"
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsButton)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsButton.topAnchor.constraint(equalTo: topAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for i in 0..<3 {
            let l = UILabel()
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 17)
            l.isUserInteractionEnabled = true
            l.tag = i
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.7
            l.accessibilityIdentifier = "fleksy.candidate\(i)"
            l.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(candidateTapped(_:))))
            stack.addArrangedSubview(l)
            labels.append(l)
        }
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        backgroundColor = UIColor(theme.candidateBar)
        let dot = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        settingsButton.setImage(dot, for: .normal)
        settingsButton.tintColor = UIColor(theme.candidateSelected).withAlphaComponent(0.85)
        rebuild()
    }

    private func rebuild() {
        if let notice {
            for (slot, label) in labels.enumerated() {
                label.isHidden = false
                label.text = slot == 1 ? "✓ \(notice)" : ""
                label.textColor = UIColor(theme.candidateSelected)
                label.font = .systemFont(ofSize: 15, weight: .semibold)
                label.accessibilityIdentifier = slot == 1 ? "fleksy.notice" : "fleksy.candidate\(slot)"
            }
            return
        }
        for (slot, label) in labels.enumerated() { label.accessibilityIdentifier = "fleksy.candidate\(slot)" }
        let selected = items.firstIndex { $0.isSelected } ?? 0
        var start = 0
        if items.count > 3 {
            start = max(0, min(items.count - 3, selected - 1))
        }
        visibleIndices = Array(start..<min(items.count, start + 3))
        for (slot, label) in labels.enumerated() {
            if slot < visibleIndices.count {
                let item = items[visibleIndices[slot]]
                label.text = item.text
                label.textColor = UIColor(item.isSelected ? theme.candidateSelected : theme.candidateText)
                label.font = .systemFont(ofSize: 17, weight: item.isSelected ? .semibold : .regular)
                label.isHidden = false
            } else if items.isEmpty, slot == 1 {
                label.text = languageHint
                label.textColor = UIColor(theme.candidateText).withAlphaComponent(0.6)
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.isHidden = false
            } else {
                label.text = ""
                label.isHidden = false
            }
        }
    }

    @objc private func candidateTapped(_ g: UITapGestureRecognizer) {
        guard let slot = g.view?.tag, slot < visibleIndices.count else { return }
        delegate?.candidateBar(self, didSelect: visibleIndices[slot])
    }

    @objc private func settingsTapped() {
        delegate?.candidateBarDidTapSettings(self)
    }
}
