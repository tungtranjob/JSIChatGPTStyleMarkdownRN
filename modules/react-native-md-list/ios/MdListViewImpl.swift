import UIKit

private final class MdRowsBox {
    let rows: [MdRow]
    init(_ rows: [MdRow]) { self.rows = rows }
}

/// The native chat list. Everything Fabric needs is exposed through the small
/// `@objc` surface at the top; the Objective-C++ component view is a thin shim.
@objc(MdListViewImpl)
public final class MdListViewImpl: UIView {

    private struct Msg {
        let id: String
        let role: String
        let markdown: String
        let streaming: Bool
    }

    // MARK: - callbacks consumed by the Fabric component view

    @objc public var onStartReached: ((NSString) -> Void)?
    @objc public var onLinkPress: ((NSString) -> Void)?
    @objc public var onCodeCopy: ((NSString, NSString) -> Void)?
    @objc public var onAtBottomChange: ((Bool) -> Void)?
    @objc public var onVisibleRangeChange: ((Int, Int, Int) -> Void)?

    // MARK: - state

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var theme = MdTheme(dark: false, baseSize: 16)
    private var engine: MdLayoutEngine
    private var rows: [MdRow] = []
    private var pending: [Msg] = []

    private let parseQueue = DispatchQueue(label: "md.parse", qos: .userInitiated)
    private let layoutQueue = DispatchQueue(label: "md.layout", qos: .userInitiated)
    private let parseCache = NSCache<NSString, MdRowsBox>()

    private var generation = 0
    private var parseScheduled = false
    private var lastWidth: CGFloat = 0
    private var atBottom = true
    private var startReachedFor: String?
    private var lastVisible = (first: -1, last: -1)

    private var colorScheme = "light"
    private var fontSize: CGFloat = 16
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var prefetchRows = 12
    private var autoScrollToBottom = true
    private var startReachedThreshold: CGFloat = 600

    // MARK: - init

    @objc public override init(frame: CGRect) {
        engine = MdLayoutEngine(theme: theme)
        super.init(frame: frame)
        parseCache.countLimit = 80

        tableView.dataSource = self
        tableView.delegate = self
        tableView.prefetchDataSource = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 44
        tableView.backgroundColor = theme.background
        tableView.keyboardDismissMode = .interactive
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(MdTextCell.self, forCellReuseIdentifier: MdTextCell.reuseId)
        tableView.register(MdBubbleCell.self, forCellReuseIdentifier: MdBubbleCell.reuseId)
        tableView.register(MdCodeCell.self, forCellReuseIdentifier: MdCodeCell.reuseId)
        tableView.register(MdTableCell.self, forCellReuseIdentifier: MdTableCell.reuseId)
        tableView.register(MdDividerCell.self, forCellReuseIdentifier: MdDividerCell.reuseId)
        addSubview(tableView)

        spinner.hidesWhenStopped = true
        addSubview(spinner)
        backgroundColor = theme.background
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        tableView.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: topInset + 22)
        if bounds.width != lastWidth, bounds.width > 0 {
            lastWidth = bounds.width
            tableView.reloadData()
            warmAroundVisible()
        }
    }

    // MARK: - props

    @objc public func setMessages(_ messages: NSArray) {
        var next: [Msg] = []
        next.reserveCapacity(messages.count)
        for case let raw as NSDictionary in messages {
            next.append(Msg(
                id: raw["id"] as? String ?? UUID().uuidString,
                role: raw["role"] as? String ?? "assistant",
                markdown: raw["markdown"] as? String ?? "",
                streaming: raw["streaming"] as? Bool ?? false
            ))
        }
        pending = next
        scheduleParse()
    }

    @objc public func setColorScheme(_ value: NSString) {
        let next = value as String
        guard next != colorScheme else { return }
        colorScheme = next
        rebuildTheme()
    }

    @objc public func setFontSize(_ value: CGFloat) {
        guard value > 0, value != fontSize else { return }
        fontSize = value
        rebuildTheme()
    }

    @objc public func setTopInset(_ value: CGFloat) {
        topInset = value
        applyInsets()
    }

    @objc public func setBottomInset(_ value: CGFloat) {
        bottomInset = value
        applyInsets()
    }

    @objc public func setLoadingOlder(_ value: Bool) {
        if value { spinner.startAnimating() } else { spinner.stopAnimating(); startReachedFor = nil }
    }

    @objc public func setPrefetchRows(_ value: Int) {
        prefetchRows = max(0, min(value, 60))
    }

    @objc public func setAutoScrollToBottom(_ value: Bool) {
        autoScrollToBottom = value
    }

    @objc public func setStartReachedThreshold(_ value: CGFloat) {
        startReachedThreshold = value
    }

    /// Fabric pools component views: wipe the transcript so a reused view never
    /// flashes the previous surface's content before its props land.
    @objc public func reset() {
        generation += 1
        pending = []
        rows = []
        startReachedFor = nil
        atBottom = true
        lastVisible = (-1, -1)
        tableView.reloadData()
    }

    // MARK: - commands

    @objc(scrollToBottomAnimated:) public func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: animated)
    }

    @objc(scrollToMessage:animated:) public func scrollToMessage(_ messageId: NSString, animated: Bool) {
        guard let index = rows.firstIndex(where: { $0.messageId == messageId as String }) else { return }
        tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: animated)
    }

    // MARK: - parse pipeline

    private func scheduleParse() {
        guard !parseScheduled else { return }
        parseScheduled = true
        // Coalesce the prop bursts a streaming response produces into one parse.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.parseScheduled = false
            self.startParse()
        }
    }

    private func startParse() {
        let input = pending
        generation += 1
        let gen = generation
        let width = bounds.width
        let center = lastVisible.last >= 0 ? lastVisible.last : 0
        // pin the engine: a theme change swaps it out on the main thread
        let engine = self.engine

        parseQueue.async { [weak self] in
            guard let self else { return }
            var out: [MdRow] = []
            out.reserveCapacity(input.count * 8)
            for message in input {
                let key = "\(message.id)|\(message.role)|\(message.markdown.utf16.count)|\(message.markdown.hashValue)" as NSString
                if !message.streaming, let cached = self.parseCache.object(forKey: key) {
                    out.append(contentsOf: cached.rows)
                    continue
                }
                let parsed = MdMarkdownParser.parse(
                    messageId: message.id,
                    role: message.role,
                    markdown: message.markdown,
                    streaming: message.streaming
                )
                if !message.streaming {
                    self.parseCache.setObject(MdRowsBox(parsed), forKey: key)
                }
                out.append(contentsOf: parsed)
            }

            // Warm the rows the table is about to ask heights for, still off main.
            if width > 0 {
                let from = max(0, center - 60)
                let to = min(out.count - 1, center + 60)
                if from <= to {
                    for i in from...to { _ = engine.layout(for: out[i], width: width) }
                }
                let tailFrom = max(0, out.count - 30)
                if tailFrom < out.count {
                    for i in tailFrom..<out.count { _ = engine.layout(for: out[i], width: width) }
                }
            }

            DispatchQueue.main.async {
                guard gen == self.generation else { return }
                self.apply(out)
            }
        }
    }

    /// Prefix/suffix diff. Chat mutations are always "append at the end",
    /// "prepend a page at the top" or "the streaming tail changed", and all three
    /// collapse to a single contiguous middle range.
    private func apply(_ next: [MdRow]) {
        let old = rows
        guard !old.isEmpty, tableView.window != nil else {
            rows = next
            tableView.reloadData()
            if autoScrollToBottom, !next.isEmpty {
                DispatchQueue.main.async { self.scrollToBottom(animated: false) }
            }
            return
        }

        let minCount = min(old.count, next.count)
        var prefix = 0
        while prefix < minCount,
              old[prefix].id == next[prefix].id,
              old[prefix].contentHash == next[prefix].contentHash { prefix += 1 }

        var suffix = 0
        while suffix < minCount - prefix,
              old[old.count - 1 - suffix].id == next[next.count - 1 - suffix].id,
              old[old.count - 1 - suffix].contentHash == next[next.count - 1 - suffix].contentHash { suffix += 1 }

        let oldMid = prefix..<(old.count - suffix)
        let newMid = prefix..<(next.count - suffix)
        if oldMid.isEmpty && newMid.isEmpty {
            rows = next
            return
        }

        let wasAtBottom = atBottom
        let prependingAtTop = prefix == 0 && oldMid.isEmpty && !newMid.isEmpty
        let width = bounds.width

        var insertedHeight: CGFloat = 0
        if prependingAtTop, width > 0 {
            for i in newMid { insertedHeight += engine.layout(for: next[i], width: width).height }
        }

        rows = next
        let reloadCount = min(oldMid.count, newMid.count)
        let previousOffset = tableView.contentOffset.y

        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                if reloadCount > 0 {
                    tableView.reloadRows(
                        at: (prefix..<(prefix + reloadCount)).map { IndexPath(row: $0, section: 0) },
                        with: .none
                    )
                }
                if oldMid.count > newMid.count {
                    tableView.deleteRows(
                        at: ((prefix + reloadCount)..<(old.count - suffix)).map { IndexPath(row: $0, section: 0) },
                        with: .none
                    )
                } else if newMid.count > oldMid.count {
                    tableView.insertRows(
                        at: ((prefix + reloadCount)..<(next.count - suffix)).map { IndexPath(row: $0, section: 0) },
                        with: .none
                    )
                }
            }
        }

        if prependingAtTop {
            // keep the reading position pinned while an older page slides in above
            tableView.contentOffset.y = previousOffset + insertedHeight
            startReachedFor = nil
        } else if autoScrollToBottom, wasAtBottom {
            scrollToBottom(animated: false)
        }

        warmAroundVisible()
    }

    private func warmAroundVisible() {
        let width = bounds.width
        guard width > 0, !rows.isEmpty else { return }
        let visible = tableView.indexPathsForVisibleRows?.map { $0.row } ?? [0]
        let first = max(0, (visible.min() ?? 0) - prefetchRows)
        let last = min(rows.count - 1, (visible.max() ?? 0) + prefetchRows)
        guard first <= last else { return }
        let slice = Array(rows[first...last])
        let engine = self.engine
        layoutQueue.async {
            for row in slice { _ = engine.layout(for: row, width: width) }
        }
    }

    // MARK: - theme

    private func rebuildTheme() {
        theme = MdTheme(dark: colorScheme == "dark", baseSize: fontSize)
        engine = MdLayoutEngine(theme: theme)
        backgroundColor = theme.background
        tableView.backgroundColor = theme.background
        spinner.color = theme.textSecondary
        tableView.reloadData()
        warmAroundVisible()
    }

    private func applyInsets() {
        tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
        setNeedsLayout()
    }

    fileprivate func estimatedHeight(for row: MdRow) -> CGFloat {
        if let cached = engine.cachedLayout(for: row, width: bounds.width) { return cached.height }
        switch row.type {
        case .code:
            let lines = (row.code?.reduce(into: 1) { acc, c in if c == "\n" { acc += 1 } }) ?? 1
            return 56 + CGFloat(lines) * (fontSize * 0.84 + 5)
        case .table:
            return 40 + CGFloat((row.table?.rows.count ?? 0) + 1) * 40
        case .divider:
            return 25
        default:
            let chars = max(1, row.inline.text.count)
            let perLine = max(20, Int(bounds.width / (fontSize * 0.52)))
            let lines = (chars + perLine - 1) / perLine
            return 12 + CGFloat(lines) * (fontSize + 6)
        }
    }
}

// MARK: - data source / delegate

extension MdListViewImpl: UITableViewDataSource, UITableViewDelegate, UITableViewDataSourcePrefetching {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < rows.count, bounds.width > 0 else { return 0 }
        return engine.layout(for: rows[indexPath.row], width: bounds.width).height
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < rows.count else { return 44 }
        return estimatedHeight(for: rows[indexPath.row])
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let layout = engine.layout(for: row, width: bounds.width)

        switch row.type {
        case .code:
            let cell = tableView.dequeueReusableCell(withIdentifier: MdCodeCell.reuseId, for: indexPath) as! MdCodeCell
            cell.configure(layout as! MdCodeRowLayout, theme: theme, delegate: self)
            return cell
        case .table:
            let cell = tableView.dequeueReusableCell(withIdentifier: MdTableCell.reuseId, for: indexPath) as! MdTableCell
            cell.configure(layout as! MdTableRowLayout, theme: theme)
            return cell
        case .divider:
            let cell = tableView.dequeueReusableCell(withIdentifier: MdDividerCell.reuseId, for: indexPath) as! MdDividerCell
            cell.configure(layout as! MdDividerRowLayout, theme: theme)
            return cell
        case .bubble:
            let cell = tableView.dequeueReusableCell(withIdentifier: MdBubbleCell.reuseId, for: indexPath) as! MdBubbleCell
            cell.configure(layout as! MdBubbleRowLayout, theme: theme, delegate: self)
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: MdTextCell.reuseId, for: indexPath) as! MdTextCell
            cell.configure(layout as! MdTextRowLayout, theme: theme, delegate: self)
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let width = bounds.width
        guard width > 0 else { return }
        let slice = indexPaths.compactMap { $0.row < rows.count ? rows[$0.row] : nil }
        let engine = self.engine
        layoutQueue.async {
            for row in slice { _ = engine.layout(for: row, width: width) }
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !rows.isEmpty else { return }

        let visible = tableView.indexPathsForVisibleRows?.map { $0.row } ?? []
        let first = visible.min() ?? -1
        let last = visible.max() ?? -1
        if first != lastVisible.first || last != lastVisible.last {
            lastVisible = (first, last)
            onVisibleRangeChange?(first, last, rows.count)
            warmAroundVisible()
        }

        let bottomEdge = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        let nowAtBottom = scrollView.contentOffset.y >= bottomEdge - 24
        if nowAtBottom != atBottom {
            atBottom = nowAtBottom
            onAtBottomChange?(nowAtBottom)
        }

        if scrollView.contentOffset.y < startReachedThreshold - scrollView.contentInset.top {
            if let oldest = rows.first?.messageId, startReachedFor != oldest {
                startReachedFor = oldest
                onStartReached?(oldest as NSString)
            }
        }
    }
}

// MARK: - row callbacks

extension MdListViewImpl: MdRowDelegate {
    func mdDidTapLink(_ url: String) {
        onLinkPress?(url as NSString)
    }

    func mdDidCopyCode(_ code: String, language: String) {
        UIPasteboard.general.string = code
        onCodeCopy?(code as NSString, language as NSString)
    }

    func mdDidLongPressText(_ text: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
