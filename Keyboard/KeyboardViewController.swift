import UIKit
import FleksyCore

final class KeyboardViewController: UIInputViewController {
    private let settings = KeyboardSettings.shared
    private let lexicons = LexiconLoader()
    private var composer: Composer!
    private var keyboardView: KeyboardView!
    private var candidateBar: CandidateBarView!
    private var settingsPanel: SettingsPanelView?
    private var heightConstraint: NSLayoutConstraint?
    private var layer: KeyboardLayer = .letters

    private let barHeight: CGFloat = 44

    override func viewDidLoad() {
        super.viewDidLoad()
        let document = ProxyDocument { [unowned self] in self.textDocumentProxy }
        composer = Composer(document: document, lexicons: lexicons, languages: settings.languages,
                            language: settings.currentLanguage, settings: settings.composerSettings)
        composer.onLanguageChange = { [weak self] lang in
            guard let self else { return }
            self.settings.currentLanguage = lang
            self.rebuildLayout()
        }
        lexicons.onLoaded = { [weak self] _ in
            self?.composer.invalidateCorrectors()
            self?.composer.handle(.contextChanged)
            self?.syncUI()
        }
        lexicons.preload(settings.languages)

        let theme = settings.theme
        view.backgroundColor = UIColor(theme.candidateBar)

        candidateBar = CandidateBarView(theme: theme)
        candidateBar.delegate = self
        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateBar)

        keyboardView = KeyboardView(layout: currentLayout(), theme: theme)
        keyboardView.delegate = self
        keyboardView.clicksEnabled = settings.clicks
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)

        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: view.topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: barHeight),
            keyboardView.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let h = view.heightAnchor.constraint(equalToConstant: totalHeight())
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightConstraint = h
        syncUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyInitialLayer()
        heightConstraint?.constant = totalHeight()
        composer.handle(.contextChanged)
        syncUI()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        heightConstraint?.constant = totalHeight(width: size.width)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        composer.handle(.contextChanged)
        syncUI()
    }

    // MARK: Layout helpers

    private func totalHeight(width: CGFloat? = nil) -> CGFloat {
        let w = width ?? view.bounds.width
        let landscape = w > 500
        let keyH = CGFloat(landscape ? min(settings.keyHeight, 40) : settings.keyHeight)
        return barHeight + keyH * 4
    }

    private func currentLayout() -> KeyboardLayout {
        let lang = composer?.language ?? settings.currentLanguage
        var layout = Layouts.layout(layer: layer, language: lang, qwertz: lang == .czech ? settings.czechQwertz : nil)
        if !needsInputModeSwitchKey {
            // The system draws its own globe below the keyboard on Face ID phones: give the space bar the room.
            var rows = layout.rows
            let last = rows.count - 1
            if let globeIdx = rows[last].firstIndex(where: { $0.action == .globe }) {
                let globe = rows[last].remove(at: globeIdx)
                if let spaceIdx = rows[last].firstIndex(where: { $0.action == .space }) {
                    let space = rows[last][spaceIdx]
                    rows[last][spaceIdx] = Key(.space, label: space.label, width: space.width + globe.width)
                }
                layout = KeyboardLayout(rows: rows)
            }
        }
        return layout
    }

    private func rebuildLayout() {
        keyboardView.layout = currentLayout()
        syncUI()
    }

    private func applyInitialLayer() {
        switch textDocumentProxy.keyboardType {
        case .numberPad, .decimalPad, .phonePad, .numbersAndPunctuation, .asciiCapableNumberPad:
            layer = .numbers
        default:
            layer = .letters
        }
        keyboardView.layout = currentLayout()
    }

    private func returnLabel() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"
        case .search: return "Search"
        case .send: return "Send"
        case .done: return "Done"
        case .next: return "Next"
        case .join: return "Join"
        case .continue: return "Continue"
        default: return "↵"
        }
    }

    private func syncUI() {
        keyboardView.shift = composer.shift
        keyboardView.returnLabel = returnLabel()
        candidateBar.items = composer.candidates
        candidateBar.languageHint = composer.language.displayName
    }

    private func applyTheme() {
        let theme = settings.theme
        view.backgroundColor = UIColor(theme.candidateBar)
        keyboardView.theme = theme
        candidateBar.theme = theme
    }

    private func setLayer(_ newLayer: KeyboardLayer) {
        guard newLayer != layer else { return }
        layer = newLayer
        rebuildLayout()
    }

    private func toggleSettingsPanel() {
        if let panel = settingsPanel {
            panel.removeFromSuperview()
            settingsPanel = nil
            return
        }
        let panel = SettingsPanelView(theme: settings.theme)
        panel.delegate = self
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: keyboardView.topAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        settingsPanel = panel
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, didTap key: Key) {
        switch key.action {
        case .character(let c):
            composer.handle(.character(c))
        case .shift:
            composer.handle(.shiftTap)
        case .backspace:
            composer.handle(.backspace)
        case .space:
            composer.handle(.space)
            if layer != .letters { setLayer(.letters) }
        case .enter:
            composer.handle(.enter)
        case .numbers:
            setLayer(.numbers)
        case .symbols:
            setLayer(.symbols)
        case .letters:
            setLayer(.letters)
        case .globe:
            break
        }
        syncUI()
    }

    func keyboardViewDidDoubleTapShift(_ view: KeyboardView) {
        composer.handle(.shiftDoubleTap)
        syncUI()
    }

    func keyboardView(_ view: KeyboardView, didSwipe direction: SwipeDirection, fingers: Int, startedOn key: Key?) {
        if fingers >= 2 {
            switch direction {
            case .down: dismissKeyboard()
            case .left, .right: composer.handle(.switchLanguage)
            case .up: break
            }
            syncUI()
            return
        }
        if key?.action == .space, direction == .left || direction == .right {
            composer.handle(.switchLanguage)
        } else {
            composer.handle(.swipe(direction))
            if direction == .right, layer != .letters { setLayer(.letters) }
        }
        syncUI()
    }

    func keyboardView(_ view: KeyboardView, didPickAccent accent: String) {
        composer.handle(.character(accent))
        syncUI()
    }

    func keyboardView(_ view: KeyboardView, globeTouched event: UIEvent?) {
        handleInputModeList(from: view, with: event ?? UIEvent())
    }
}

// MARK: - CandidateBarDelegate

extension KeyboardViewController: CandidateBarDelegate {
    func candidateBar(_ bar: CandidateBarView, didSelect index: Int) {
        composer.handle(.selectCandidate(index))
        syncUI()
    }

    func candidateBarDidTapSettings(_ bar: CandidateBarView) {
        toggleSettingsPanel()
    }
}

// MARK: - SettingsPanelDelegate

extension KeyboardViewController: SettingsPanelDelegate {
    func settingsPanelDidChange(_ panel: SettingsPanelView) {
        composer.settings = settings.composerSettings
        composer.setLanguages(settings.languages, current: settings.currentLanguage)
        composer.invalidateCorrectors()
        lexicons.preload(settings.languages)
        keyboardView.clicksEnabled = settings.clicks
        applyTheme()
        panel.backgroundColor = UIColor(settings.theme.candidateBar)
        rebuildLayout()
        heightConstraint?.constant = totalHeight()
    }

    func settingsPanelDidClose(_ panel: SettingsPanelView) {
        panel.removeFromSuperview()
        settingsPanel = nil
        composer.handle(.contextChanged)
        syncUI()
    }
}
