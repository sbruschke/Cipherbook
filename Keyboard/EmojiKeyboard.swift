import KeyboardCore
import UIKit

/// Decodes emoji art off the main thread and keeps the recently shown images.
final class EmojiImageCache {
    private let catalog: EmojiCatalog
    private let cache = NSCache<NSNumber, UIImage>()
    private let queue = DispatchQueue(label: "dev.dxshdw.cipherbook.emoji-decode", qos: .userInitiated)

    init(catalog: EmojiCatalog) {
        self.catalog = catalog
        // ~30 KB decoded each; well inside the extension's memory ceiling.
        cache.countLimit = 240
    }

    /// Returns the image at once if cached; otherwise decodes it and calls `completion`
    /// on the main thread.
    func image(for span: Range<Int>, completion: @escaping (UIImage?) -> Void) -> UIImage? {
        let key = NSNumber(value: span.lowerBound)
        if let hit = cache.object(forKey: key) { return hit }
        queue.async { [catalog, cache] in
            // 96 px art at 3x draws at 32 pt.
            let image = UIImage(data: catalog.imageData(span), scale: 3)?.preparingForDisplay()
            if let image { cache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
        return nil
    }
}

/// Recents and remembered skin tones, kept in the extension's own defaults.
final class EmojiPreferences {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let recents = "emoji.recents"
        static let tones = "emoji.tones"
    }

    var recents: [String] { defaults.stringArray(forKey: Key.recents) ?? [] }

    func record(_ text: String) {
        defaults.set(EmojiRecents.recording(text, in: recents), forKey: Key.recents)
    }

    /// 0 is the default (yellow) variant, 1–5 light … dark.
    func tone(for emoji: Emoji) -> Int {
        let saved = (defaults.dictionary(forKey: Key.tones) as? [String: Int])?[emoji.text] ?? 0
        return saved < emoji.variants.count ? saved : 0
    }

    func setTone(_ tone: Int, for emoji: Emoji) {
        var all = defaults.dictionary(forKey: Key.tones) as? [String: Int] ?? [:]
        all[emoji.text] = tone
        defaults.set(all, forKey: Key.tones)
    }
}

final class EmojiCell: UICollectionViewCell {
    static let reuseID = "emoji"
    private let imageView = UIImageView()
    private let label = UILabel()
    private var shownSpan: Range<Int>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = touchableClear
        imageView.contentMode = .scaleAspectFit
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        contentView.addSubview(imageView)
        contentView.addSubview(label)
        selectedBackgroundView = UIView()
        selectedBackgroundView?.layer.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ variant: Emoji.Variant, images: EmojiImageCache, dark: Bool) {
        selectedBackgroundView?.backgroundColor = UIColor(white: dark ? 1 : 0, alpha: dark ? 0.18 : 0.1)
        shownSpan = variant.image
        guard let span = variant.image else {
            // No Fluent art (country flags, mostly): the system draws it.
            imageView.image = nil
            label.isHidden = false
            label.text = variant.text
            return
        }
        label.isHidden = true
        imageView.image = images.image(for: span) { [weak self] image in
            guard let self, self.shownSpan == span else { return }
            self.imageView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shownSpan = nil
        imageView.image = nil
        label.text = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height) * 0.78
        let square = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        imageView.frame = square
        label.frame = square
        label.font = .systemFont(ofSize: side * 0.82)
        selectedBackgroundView?.frame = square.insetBy(dx: -3, dy: -3)
    }
}

/// The skin-tone strip shown over an emoji while it is long-pressed.
final class EmojiTonePicker: UIView {
    private var views: [UIImageView] = []
    private var labels: [UILabel] = []
    private let highlight = UIView()
    private(set) var selected = 0
    private let cellWidth: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        highlight.layer.cornerRadius = 8
        addSubview(highlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ emoji: Emoji, selected: Int, over anchor: CGRect, in host: UIView,
              images: EmojiImageCache, dark: Bool) {
        views.forEach { $0.removeFromSuperview() }
        labels.forEach { $0.removeFromSuperview() }
        views = []
        labels = []
        backgroundColor = dark ? UIColor(white: 0.32, alpha: 1) : .white
        highlight.backgroundColor = dark ? UIColor(white: 1, alpha: 0.2) : UIColor(white: 0, alpha: 0.1)

        let variants = emoji.variants
        let width = cellWidth * CGFloat(variants.count) + 8
        let height: CGFloat = 52
        let x = min(max(4, anchor.midX - width / 2), host.bounds.width - width - 4)
        frame = CGRect(x: x, y: max(2, anchor.minY - height - 4), width: width, height: height)
        for (i, variant) in variants.enumerated() {
            let slot = CGRect(x: 4 + CGFloat(i) * cellWidth, y: 4, width: cellWidth, height: height - 8)
            let box = slot.insetBy(dx: 4, dy: 3)
            if let span = variant.image {
                let view = UIImageView(frame: box)
                view.contentMode = .scaleAspectFit
                view.image = images.image(for: span) { [weak view] in view?.image = $0 }
                addSubview(view)
                views.append(view)
            } else {
                let label = UILabel(frame: box)
                label.text = variant.text
                label.textAlignment = .center
                label.font = .systemFont(ofSize: 30)
                addSubview(label)
                labels.append(label)
            }
        }
        select(selected)
        host.addSubview(self)
    }

    /// Picks the variant under a point in `host` coordinates.
    func track(_ point: CGPoint, in host: UIView) {
        let local = convert(point, from: host)
        let count = views.count + labels.count
        select(min(max(0, Int((local.x - 4) / cellWidth)), count - 1))
    }

    private func select(_ index: Int) {
        selected = index
        highlight.frame = CGRect(x: 4 + CGFloat(index) * cellWidth, y: 4,
                                 width: cellWidth, height: bounds.height - 8).insetBy(dx: 1, dy: 0)
    }
}

/// The emoji page: search field, sideways-scrolling grid, category bar with ABC and delete.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegate,
                               UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    var onInsert: ((String) -> Void)?
    var onABC: (() -> Void)?
    var onSearch: (() -> Void)?
    var onDeleteDown: (() -> Void)?
    var onDeleteUp: (() -> Void)?

    private let catalog: EmojiCatalog
    private let images: EmojiImageCache
    private let prefs: EmojiPreferences
    private let searchField = UIControl()
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let searchLabel = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private let grid: UICollectionView
    private let abcButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var categoryButtons: [UIButton] = []
    private let tonePicker = EmojiTonePicker()
    private var pressed: Emoji?
    private var dark = false

    /// Section 0 is recents (as typed, tone included); 1… are the catalog's categories.
    private var recents: [Emoji.Variant] = []
    private let sections: [ArraySlice<Emoji>]

    private static let categoryIcons = ["clock", "face.smiling", "pawprint", "fork.knife", "soccerball",
                                        "car", "lightbulb", "heart", "flag"]
    private static let rows = 4
    private static let searchHeight: CGFloat = 44
    private static let barHeight: CGFloat = 42

    init(catalog: EmojiCatalog, images: EmojiImageCache, prefs: EmojiPreferences) {
        self.catalog = catalog
        self.images = images
        self.prefs = prefs
        sections = catalog.categories.indices.map { c in
            catalog.emoji[(catalog.firstIndex(ofCategory: c) ?? 0)...].prefix { $0.category == c }
        }
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        backgroundColor = touchableClear

        searchField.layer.cornerRadius = 10
        searchField.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        searchIcon.isUserInteractionEnabled = false
        searchLabel.isUserInteractionEnabled = false
        searchLabel.text = "Search Emoji"
        searchLabel.font = .systemFont(ofSize: 17)
        searchField.addSubview(searchIcon)
        searchField.addSubview(searchLabel)
        addSubview(searchField)

        grid.backgroundColor = touchableClear
        grid.showsHorizontalScrollIndicator = false
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        addSubview(grid)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        press.minimumPressDuration = 0.3
        press.delegate = self
        grid.addGestureRecognizer(press)

        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        abcButton.addTarget(self, action: #selector(abcTapped), for: .touchUpInside)
        addSubview(abcButton)

        for (i, name) in Self.categoryIcons.enumerated() {
            let button = UIButton(type: .system)
            button.tag = i
            button.setImage(UIImage(systemName: name, withConfiguration:
                UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
            button.layer.cornerRadius = 15
            button.accessibilityLabel = i == 0 ? "Frequently Used" : catalog.categories[i - 1]
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            addSubview(button)
            categoryButtons.append(button)
        }

        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addSubview(deleteButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Call when the page is shown: refreshes recents and colours. Recents only change
    /// here so nothing moves under the finger while browsing.
    func prepare(dark: Bool) {
        self.dark = dark
        let ink: UIColor = dark ? .white : .black
        searchField.backgroundColor = dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.07)
        searchIcon.tintColor = ink.withAlphaComponent(0.55)
        searchLabel.textColor = ink.withAlphaComponent(0.55)
        abcButton.tintColor = ink
        deleteButton.tintColor = ink
        categoryButtons.forEach { $0.tintColor = ink.withAlphaComponent(0.6) }
        recents = prefs.recents.compactMap { text in
            catalog.lookup(text).map { $0.emoji.variants[$0.variant] }
        }
        grid.reloadData()
        grid.layoutIfNeeded()
        // Open on recents when there are any, otherwise on the first category.
        if recents.isEmpty, !sections[0].isEmpty {
            grid.scrollToItem(at: IndexPath(item: 0, section: 1), at: .left, animated: false)
        } else {
            grid.setContentOffset(.zero, animated: false)
        }
        updateCategoryHighlight()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        searchField.frame = CGRect(x: 8, y: 4, width: w - 16, height: Self.searchHeight - 8)
        searchIcon.frame = CGRect(x: 10, y: 0, width: 22, height: searchField.bounds.height)
        searchIcon.contentMode = .center
        searchLabel.frame = CGRect(x: 38, y: 0, width: searchField.bounds.width - 46,
                                   height: searchField.bounds.height)

        let gridHeight = bounds.height - Self.searchHeight - Self.barHeight
        grid.frame = CGRect(x: 0, y: Self.searchHeight, width: w, height: gridHeight)
        let columns = max(6, floor((w - 8) / 52))
        let size = CGSize(width: floor((w - 8) / columns), height: floor(gridHeight / CGFloat(Self.rows)))
        if gridHeight > 0, w > 0, layout.itemSize != size {
            layout.itemSize = size
            layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: gridHeight - size.height * CGFloat(Self.rows), right: 4)
            layout.invalidateLayout()
        }

        let barY = bounds.height - Self.barHeight
        abcButton.frame = CGRect(x: 4, y: barY, width: 52, height: Self.barHeight)
        deleteButton.frame = CGRect(x: w - 52, y: barY, width: 48, height: Self.barHeight)
        let span = deleteButton.frame.minX - abcButton.frame.maxX
        let slot = span / CGFloat(categoryButtons.count)
        for (i, button) in categoryButtons.enumerated() {
            let side = min(slot, 30)
            button.frame = CGRect(x: abcButton.frame.maxX + CGFloat(i) * slot + (slot - side) / 2,
                                  y: barY + (Self.barHeight - side) / 2, width: side, height: side)
        }
    }

    // MARK: Data

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count + 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        section == 0 ? recents.count : sections[section - 1].count
    }

    private func variant(at path: IndexPath) -> (variant: Emoji.Variant, emoji: Emoji?) {
        if path.section == 0 { return (recents[path.item], nil) }
        let emoji = sections[path.section - 1][sections[path.section - 1].startIndex + path.item]
        return (emoji.variants[prefs.tone(for: emoji)], emoji)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: path)
        (cell as? EmojiCell)?.show(variant(at: path).variant, images: images, dark: dark)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: true)
        insert(variant(at: path).variant.text)
    }

    private func insert(_ text: String) {
        prefs.record(text)
        onInsert?(text)
    }

    // MARK: Categories

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCategoryHighlight()
    }

    private func updateCategoryHighlight() {
        let probe = CGPoint(x: grid.contentOffset.x + 30, y: grid.bounds.height / 2)
        var section = grid.indexPathForItem(at: probe)?.section
        if section == nil {
            // Between sections, or recents empty: use the nearest visible item.
            section = grid.indexPathsForVisibleItems.min {
                abs((grid.layoutAttributesForItem(at: $0)?.frame.minX ?? 0) - probe.x)
                    < abs((grid.layoutAttributesForItem(at: $1)?.frame.minX ?? 0) - probe.x)
            }?.section
        }
        let current = section ?? 0
        for button in categoryButtons {
            button.backgroundColor = button.tag == current
                ? (dark ? UIColor(white: 1, alpha: 0.18) : UIColor(white: 0, alpha: 0.1))
                : .clear
        }
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        let section = sender.tag
        if section == 0 || collectionView(grid, numberOfItemsInSection: section) == 0 {
            grid.setContentOffset(.zero, animated: false)
        } else {
            grid.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
            // scrollToItem leaves the section inset out of view; show it.
            grid.contentOffset.x = max(0, grid.contentOffset.x - layout.sectionInset.left)
        }
        updateCategoryHighlight()
    }

    // MARK: Skin tones

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture is UILongPressGestureRecognizer else { return super.gestureRecognizerShouldBegin(gesture) }
        guard let path = grid.indexPathForItem(at: gesture.location(in: grid)) else { return false }
        return variant(at: path).emoji.map { !$0.tones.isEmpty } ?? false
    }

    @objc private func longPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let path = grid.indexPathForItem(at: gesture.location(in: grid)),
                  let emoji = variant(at: path).emoji,
                  let cell = grid.cellForItem(at: path) else { return }
            pressed = emoji
            let host = superview ?? self
            tonePicker.show(emoji, selected: prefs.tone(for: emoji),
                            over: cell.convert(cell.bounds, to: host), in: host,
                            images: images, dark: dark)
        case .changed:
            guard let host = tonePicker.superview else { return }
            tonePicker.track(gesture.location(in: host), in: host)
        case .ended:
            tonePicker.removeFromSuperview()
            guard let emoji = pressed else { return }
            let choice = tonePicker.selected
            prefs.setTone(choice, for: emoji)
            insert(emoji.variants[choice].text)
            // Show the chosen tone in the grid from now on.
            grid.reloadItems(at: grid.indexPathsForVisibleItems.filter { $0.section > 0 })
            pressed = nil
        default:
            tonePicker.removeFromSuperview()
            pressed = nil
        }
    }

    // MARK: Buttons

    @objc private func searchTapped() { onSearch?() }
    @objc private func abcTapped() { onABC?() }
    @objc private func deleteDown() { onDeleteDown?() }
    @objc private func deleteUp() { onDeleteUp?() }
}

/// Shown above the letter keys while searching: the query and a row of results.
final class EmojiSearchHeader: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onInsert: ((String) -> Void)?
    var onClose: (() -> Void)?

    static let height: CGFloat = 88

    private let catalog: EmojiCatalog
    private let images: EmojiImageCache
    private let prefs: EmojiPreferences
    private let field = UIView()
    private let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let queryLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let layout = UICollectionViewFlowLayout()
    private let strip: UICollectionView
    private let emptyLabel = UILabel()
    private var results: [Emoji] = []
    private var dark = false

    init(catalog: EmojiCatalog, images: EmojiImageCache, prefs: EmojiPreferences) {
        self.catalog = catalog
        self.images = images
        self.prefs = prefs
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.itemSize = CGSize(width: 44, height: 44)
        strip = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        backgroundColor = touchableClear

        field.layer.cornerRadius = 10
        field.isUserInteractionEnabled = false
        icon.contentMode = .center
        queryLabel.font = .systemFont(ofSize: 17)
        field.addSubview(icon)
        field.addSubview(queryLabel)
        addSubview(field)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.accessibilityLabel = "Close search"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(closeButton)

        strip.backgroundColor = touchableClear
        strip.showsHorizontalScrollIndicator = false
        strip.dataSource = self
        strip.delegate = self
        strip.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        addSubview(strip)

        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 14)
        addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(query: String, dark: Bool) {
        self.dark = dark
        let ink: UIColor = dark ? .white : .black
        field.backgroundColor = dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.07)
        icon.tintColor = ink.withAlphaComponent(0.55)
        closeButton.tintColor = ink.withAlphaComponent(0.45)
        emptyLabel.textColor = ink.withAlphaComponent(0.5)
        if query.isEmpty {
            queryLabel.text = "Search Emoji"
            queryLabel.textColor = ink.withAlphaComponent(0.55)
        } else {
            queryLabel.text = query
            queryLabel.textColor = ink
        }
        results = catalog.search(query)
        emptyLabel.text = query.isEmpty ? nil : (results.isEmpty ? "No Emoji Found" : nil)
        strip.reloadData()
        strip.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        field.frame = CGRect(x: 8, y: 4, width: bounds.width - 52, height: 36)
        icon.frame = CGRect(x: 10, y: 0, width: 22, height: 36)
        queryLabel.frame = CGRect(x: 38, y: 0, width: field.bounds.width - 46, height: 36)
        closeButton.frame = CGRect(x: bounds.width - 44, y: 0, width: 44, height: 44)
        strip.frame = CGRect(x: 0, y: 44, width: bounds.width, height: 44)
        emptyLabel.frame = strip.frame
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: path)
        let emoji = results[path.item]
        (cell as? EmojiCell)?.show(emoji.variants[prefs.tone(for: emoji)], images: images, dark: dark)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt path: IndexPath) {
        collectionView.deselectItem(at: path, animated: true)
        let emoji = results[path.item]
        let text = emoji.variants[prefs.tone(for: emoji)].text
        prefs.record(text)
        onInsert?(text)
    }

    @objc private func closeTapped() { onClose?() }
}
