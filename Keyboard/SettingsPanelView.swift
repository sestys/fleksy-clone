import UIKit
import FleksyCore

protocol SettingsPanelDelegate: AnyObject {
    func settingsPanelDidChange(_ panel: SettingsPanelView)
    func settingsPanelDidClose(_ panel: SettingsPanelView)
}

/// In-keyboard settings: theme, languages, Czech layout, correction toggles, key height.
final class SettingsPanelView: UIView {
    weak var delegate: SettingsPanelDelegate?
    private let settings = KeyboardSettings.shared
    private var theme: Theme
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var themeButtons: [UIButton] = []
    private let czechSwitch = UISwitch()
    private let englishSwitch = UISwitch()

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        accessibilityIdentifier = "fleksy.settingsPanel"
        backgroundColor = UIColor(theme.candidateBar)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .semibold) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = UIColor(theme.candidateText)
        return l
    }

    private func row(_ title: String, control: UIView) -> UIView {
        let h = UIStackView(arrangedSubviews: [label(title, size: 15, weight: .regular), control])
        h.axis = .horizontal
        h.alignment = .center
        h.distribution = .equalSpacing
        (h.arrangedSubviews[0] as? UILabel)?.textColor = UIColor(theme.candidateSelected)
        return h
    }

    private func build() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        // Header
        let title = label("Fleksy Clone settings", size: 15, weight: .bold)
        title.textColor = UIColor(theme.candidateSelected)
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        done.tintColor = UIColor(theme.candidateSelected)
        done.accessibilityIdentifier = "fleksy.settingsDone"
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, done])
        header.distribution = .equalSpacing
        stack.addArrangedSubview(header)

        // Theme swatches
        stack.addArrangedSubview(label("THEME"))
        let swatches = UIStackView()
        swatches.spacing = 14
        swatches.distribution = .fillEqually
        for t in Theme.all {
            let b = UIButton(type: .custom)
            b.backgroundColor = UIColor(t.background)
            b.layer.cornerRadius = 18
            b.layer.borderWidth = t.id == settings.theme.id ? 3 : 0
            b.layer.borderColor = UIColor(theme.candidateSelected).cgColor
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            b.accessibilityIdentifier = "fleksy.theme_\(t.id)"
            b.accessibilityLabel = t.name
            b.tag = Theme.all.firstIndex { $0.id == t.id } ?? 0
            b.addTarget(self, action: #selector(themeTapped(_:)), for: .touchUpInside)
            swatches.addArrangedSubview(b)
            themeButtons.append(b)
        }
        stack.addArrangedSubview(swatches)

        // Languages
        stack.addArrangedSubview(label("LANGUAGES"))
        czechSwitch.isOn = settings.languages.contains(.czech)
        czechSwitch.accessibilityIdentifier = "fleksy.lang_cs"
        czechSwitch.addTarget(self, action: #selector(languagesChanged), for: .valueChanged)
        englishSwitch.isOn = settings.languages.contains(.english)
        englishSwitch.accessibilityIdentifier = "fleksy.lang_en"
        englishSwitch.addTarget(self, action: #selector(languagesChanged), for: .valueChanged)
        stack.addArrangedSubview(row("Čeština", control: czechSwitch))
        stack.addArrangedSubview(row("English", control: englishSwitch))

        let layoutControl = UISegmentedControl(items: ["QWERTZ", "QWERTY"])
        layoutControl.selectedSegmentIndex = settings.czechQwertz ? 0 : 1
        layoutControl.accessibilityIdentifier = "fleksy.czechLayout"
        layoutControl.addTarget(self, action: #selector(layoutChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(row("Czech layout", control: layoutControl))

        // Typing
        stack.addArrangedSubview(label("TYPING"))
        let ac = UISwitch(); ac.isOn = settings.autocorrect; ac.accessibilityIdentifier = "fleksy.autocorrect"
        ac.addTarget(self, action: #selector(autocorrectChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(row("Autocorrect", control: ac))
        let cap = UISwitch(); cap.isOn = settings.autoCapitalize; cap.accessibilityIdentifier = "fleksy.autocap"
        cap.addTarget(self, action: #selector(autocapChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(row("Auto-capitalize", control: cap))
        let clicks = UISwitch(); clicks.isOn = settings.clicks; clicks.accessibilityIdentifier = "fleksy.clicks"
        clicks.addTarget(self, action: #selector(clicksChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(row("Key clicks", control: clicks))

        let slider = UISlider()
        slider.minimumValue = 44; slider.maximumValue = 66
        slider.value = Float(settings.keyHeight)
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        slider.accessibilityIdentifier = "fleksy.keyHeight"
        slider.addTarget(self, action: #selector(heightChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(row("Key height", control: slider))

        // Learned words
        let forget = UIButton(type: .system)
        forget.setTitle("Forget learned words (\(settings.learnedWords.count))", for: .normal)
        forget.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        forget.tintColor = UIColor(theme.candidateSelected)
        forget.contentHorizontalAlignment = .leading
        forget.accessibilityIdentifier = "fleksy.clearLearned"
        forget.addTarget(self, action: #selector(forgetTapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(forget)

        // Gesture cheat sheet
        stack.addArrangedSubview(label("GESTURES"))
        let help = label("→ space (again after a correction: restore typed word, again: learn it)   ←  delete word   ↑↓ change word   ⇄ on space bar: language   ⇊ two fingers: hide", size: 12, weight: .regular)
        help.numberOfLines = 0
        stack.addArrangedSubview(help)
    }

    @objc private func closeTapped() { delegate?.settingsPanelDidClose(self) }

    @objc private func forgetTapped(_ b: UIButton) {
        settings.clearLearnedWords()
        b.setTitle("Forget learned words (0)", for: .normal)
        delegate?.settingsPanelDidChange(self)
    }

    @objc private func themeTapped(_ b: UIButton) {
        settings.theme = Theme.all[b.tag]
        for btn in themeButtons { btn.layer.borderWidth = btn.tag == b.tag ? 3 : 0 }
        delegate?.settingsPanelDidChange(self)
    }

    @objc private func languagesChanged() {
        var langs: [Language] = []
        if czechSwitch.isOn { langs.append(.czech) }
        if englishSwitch.isOn { langs.append(.english) }
        if langs.isEmpty {
            // Keep at least one language enabled.
            englishSwitch.setOn(true, animated: true)
            langs = [.english]
        }
        settings.languages = langs
        if !langs.contains(settings.currentLanguage) { settings.currentLanguage = langs[0] }
        delegate?.settingsPanelDidChange(self)
    }

    @objc private func layoutChanged(_ c: UISegmentedControl) {
        settings.czechQwertz = c.selectedSegmentIndex == 0
        delegate?.settingsPanelDidChange(self)
    }

    @objc private func autocorrectChanged(_ s: UISwitch) { settings.autocorrect = s.isOn; delegate?.settingsPanelDidChange(self) }
    @objc private func autocapChanged(_ s: UISwitch) { settings.autoCapitalize = s.isOn; delegate?.settingsPanelDidChange(self) }
    @objc private func clicksChanged(_ s: UISwitch) { settings.clicks = s.isOn; delegate?.settingsPanelDidChange(self) }
    @objc private func heightChanged(_ s: UISlider) { settings.keyHeight = Double(s.value.rounded()); delegate?.settingsPanelDidChange(self) }
}
