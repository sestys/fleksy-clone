import UIKit
import FleksyCore

protocol EmojiPanelDelegate: AnyObject {
    func emojiPanel(_ panel: EmojiPanelView, didPick emoji: String)
    func emojiPanelDidTapBackspace(_ panel: EmojiPanelView)
    func emojiPanelDidClose(_ panel: EmojiPanelView)
    /// The recent emoji, most used first. Asked for when the recent tab is opened, so
    /// that the order is settled before any tapping starts and stays put during it.
    func emojiPanelRecentEmoji(_ panel: EmojiPanelView) -> [String]
}

/// Fleksy-style emoji picker: a grid for one category at a time, category tabs along the
/// bottom with ABC on the left and backspace on the right, plus a "recent" category.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    weak var delegate: EmojiPanelDelegate?
    /// Ordering is deliberately frozen while this tab is on screen; see the delegate.
    private var recent: [String]

    private let theme: Theme
    private let collection: UICollectionView
    private let tabBar = UIStackView()
    private var tabButtons: [UIButton] = []
    private var selectedCategory = 1
    private let columns: CGFloat = 8

    private var categories: [(id: String, icon: String, emoji: [String])] {
        [("recent", "🕘", recent)] + EmojiData.categories.map { ($0.id, $0.icon, $0.emoji) }
    }

    init(theme: Theme, recent: [String]) {
        self.theme = theme
        self.recent = recent
        let flow = UICollectionViewFlowLayout()
        flow.minimumInteritemSpacing = 0
        flow.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
        super.init(frame: .zero)
        accessibilityIdentifier = "fleksy.emojiPanel"
        backgroundColor = UIColor(theme.rowColors[0])
        selectedCategory = recent.isEmpty ? 1 : 0
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "cell")
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.alwaysBounceVertical = true
        addSubview(collection)

        tabBar.axis = .horizontal
        tabBar.distribution = .fillEqually
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.backgroundColor = UIColor(theme.bottomRowColor)
        addSubview(tabBar)

        let abc = makeTab(title: "ABC", identifier: "fleksy.emojiABC")
        abc.addTarget(self, action: #selector(abcTapped), for: .touchUpInside)
        tabBar.addArrangedSubview(abc)
        for (i, cat) in categories.enumerated() {
            let b = makeTab(title: cat.icon, identifier: "fleksy.emojiCategory_\(cat.id)")
            b.tag = i
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(b)
            tabButtons.append(b)
        }
        let back = makeTab(title: "", identifier: "fleksy.emojiBackspace")
        back.setImage(UIImage(systemName: "delete.left.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        back.tintColor = UIColor(theme.specialKeyText)
        back.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        tabBar.addArrangedSubview(back)

        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 44),
        ])
        updateTabs()
    }

    private func makeTab(title: String, identifier: String) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: title == "ABC" ? 14 : 20, weight: .semibold)
        b.setTitleColor(UIColor(theme.specialKeyText), for: .normal)
        b.accessibilityIdentifier = identifier
        b.accessibilityLabel = identifier
        return b
    }

    private func updateTabs() {
        for b in tabButtons {
            b.backgroundColor = b.tag == selectedCategory ? UIColor(theme.pressed) : .clear
            b.layer.cornerRadius = 6
        }
    }

    @objc private func tabTapped(_ b: UIButton) {
        // Re-sort only on the way in. Picking an emoji updates the counts behind us, but
        // the grid keeps the order it opened with until the tab is opened again.
        if b.tag == 0, let fresh = delegate?.emojiPanelRecentEmoji(self) { recent = fresh }
        selectedCategory = b.tag
        updateTabs()
        collection.reloadData()
        if collection.numberOfItems(inSection: 0) > 0 {
            collection.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }
    }

    @objc private func abcTapped() { delegate?.emojiPanelDidClose(self) }
    @objc private func backspaceTapped() { delegate?.emojiPanelDidTapBackspace(self) }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories[selectedCategory].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmojiCell
        cell.emoji = categories[selectedCategory].emoji[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let w = floor(collectionView.bounds.width / columns)
        return CGSize(width: w, height: w)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let e = categories[selectedCategory].emoji[indexPath.item]
        UIDevice.current.playInputClick()
        delegate?.emojiPanel(self, didPick: e)
    }
}

final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()
    var emoji: String = "" {
        didSet {
            label.text = emoji
            accessibilityIdentifier = "emoji_\(emoji)"
            accessibilityLabel = emoji
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }
}
