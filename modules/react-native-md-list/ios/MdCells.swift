import UIKit

protocol MdRowDelegate: AnyObject {
    func mdDidTapLink(_ url: String)
    func mdDidCopyCode(_ code: String, language: String)
    func mdDidLongPressText(_ text: String)
}

// MARK: - paragraph / heading / list item / quote

final class MdTextCell: UITableViewCell {
    static let reuseId = "MdTextCell"

    private let canvas = Canvas()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(canvas)
        canvas.isUserInteractionEnabled = true
        canvas.addGestureRecognizer(UITapGestureRecognizer(target: canvas, action: #selector(Canvas.handleTap(_:))))
        canvas.addGestureRecognizer(UILongPressGestureRecognizer(target: canvas, action: #selector(Canvas.handleLongPress(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ layout: MdTextRowLayout, theme: MdTheme, delegate: MdRowDelegate?) {
        canvas.layout = layout
        canvas.theme = theme
        canvas.delegate = delegate
        canvas.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        backgroundColor = theme.background
        canvas.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = contentView.bounds
    }

    private final class Canvas: UIView {
        var layout: MdTextRowLayout?
        var theme: MdTheme?
        weak var delegate: MdRowDelegate?

        override func draw(_ rect: CGRect) {
            guard let layout, let theme, let ctx = UIGraphicsGetCurrentContext() else { return }

            if layout.quoteDepth > 0 {
                ctx.setFillColor(theme.quoteBar.cgColor)
                for d in 0..<layout.quoteDepth {
                    let x = layout.quoteX + CGFloat(d) * 14
                    let bar = CGRect(x: x, y: 0, width: 3, height: bounds.height)
                    ctx.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 1.5).cgPath)
                    ctx.fillPath()
                }
            }

            layout.marker?.draw(in: ctx, at: CGPoint(x: layout.markerX, y: layout.textOrigin.y))

            if layout.checked >= 0 {
                let box = CGRect(x: layout.markerX, y: layout.textOrigin.y + 3, width: 15, height: 15)
                ctx.setStrokeColor(theme.textSecondary.cgColor)
                ctx.setLineWidth(1.5)
                ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: 4).cgPath)
                ctx.strokePath()
                if layout.checked == 1 {
                    ctx.setStrokeColor(theme.link.cgColor)
                    ctx.setLineWidth(1.8)
                    ctx.setLineCap(.round)
                    ctx.move(to: CGPoint(x: box.minX + 3.5, y: box.midY))
                    ctx.addLine(to: CGPoint(x: box.midX - 0.7, y: box.maxY - 3.5))
                    ctx.addLine(to: CGPoint(x: box.maxX - 2.5, y: box.minY + 3.5))
                    ctx.strokePath()
                }
            }

            layout.frame.draw(in: ctx, at: layout.textOrigin)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let layout else { return }
            let p = recognizer.location(in: self)
            let local = CGPoint(x: p.x - layout.textOrigin.x, y: p.y - layout.textOrigin.y)
            if let url = layout.frame.link(at: local) {
                delegate?.mdDidTapLink(url)
            }
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let layout else { return }
            delegate?.mdDidLongPressText(layout.frame.attributed.string)
        }
    }
}

// MARK: - user bubble

final class MdBubbleCell: UITableViewCell {
    static let reuseId = "MdBubbleCell"

    private let canvas = Canvas()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(canvas)
        canvas.isUserInteractionEnabled = true
        canvas.addGestureRecognizer(UITapGestureRecognizer(target: canvas, action: #selector(Canvas.handleTap(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ layout: MdBubbleRowLayout, theme: MdTheme, delegate: MdRowDelegate?) {
        canvas.layout = layout
        canvas.theme = theme
        canvas.delegate = delegate
        canvas.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        backgroundColor = theme.background
        canvas.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = contentView.bounds
    }

    private final class Canvas: UIView {
        var layout: MdBubbleRowLayout?
        var theme: MdTheme?
        weak var delegate: MdRowDelegate?

        override func draw(_ rect: CGRect) {
            guard let layout, let theme, let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.setFillColor(theme.bubbleBg.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: layout.bubbleRect, cornerRadius: 20).cgPath)
            ctx.fillPath()
            layout.frame.draw(
                in: ctx,
                at: CGPoint(x: layout.bubbleRect.minX + layout.pad, y: layout.bubbleRect.minY + layout.pad)
            )
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let layout else { return }
            let p = recognizer.location(in: self)
            let local = CGPoint(
                x: p.x - layout.bubbleRect.minX - layout.pad,
                y: p.y - layout.bubbleRect.minY - layout.pad
            )
            if let url = layout.frame.link(at: local) { delegate?.mdDidTapLink(url) }
        }
    }
}

// MARK: - fenced code

final class MdCodeCell: UITableViewCell {
    static let reuseId = "MdCodeCell"

    private let box = UIView()
    private let header = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let canvas = Canvas()

    private var layout: MdCodeRowLayout?
    private weak var delegate: MdRowDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        box.layer.cornerRadius = 12
        box.clipsToBounds = true
        contentView.addSubview(box)
        box.addSubview(header)
        header.addSubview(languageLabel)
        header.addSubview(copyButton)
        box.addSubview(scrollView)
        scrollView.addSubview(canvas)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ layout: MdCodeRowLayout, theme: MdTheme, delegate: MdRowDelegate?) {
        self.layout = layout
        self.delegate = delegate
        canvas.layout = layout
        contentView.backgroundColor = theme.background
        backgroundColor = theme.background
        box.backgroundColor = theme.codeBg
        header.backgroundColor = theme.codeHeaderBg
        canvas.backgroundColor = theme.codeBg
        languageLabel.text = layout.language
        languageLabel.font = theme.codeHeaderFont
        languageLabel.textColor = theme.codeHeaderFg
        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = theme.codeHeaderFont
        copyButton.setTitleColor(theme.codeHeaderFg, for: .normal)
        scrollView.contentOffset = .zero
        setNeedsLayout()
        canvas.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout else { return }
        let bodyHeight = layout.frame.size.height + layout.padding * 2
        box.frame = CGRect(
            x: layout.left, y: layout.topMargin,
            width: layout.boxWidth, height: layout.headerHeight + bodyHeight
        )
        header.frame = CGRect(x: 0, y: 0, width: layout.boxWidth, height: layout.headerHeight)
        languageLabel.frame = CGRect(x: 12, y: 0, width: 160, height: layout.headerHeight)
        copyButton.frame = CGRect(
            x: layout.boxWidth - 72, y: 0, width: 60, height: layout.headerHeight
        )
        scrollView.frame = CGRect(x: 0, y: layout.headerHeight, width: layout.boxWidth, height: bodyHeight)
        canvas.frame = CGRect(
            x: 0, y: 0,
            width: layout.contentWidth + layout.padding * 2,
            height: bodyHeight
        )
        scrollView.contentSize = canvas.frame.size
    }

    @objc private func copyTapped() {
        guard let layout else { return }
        delegate?.mdDidCopyCode(layout.code, language: layout.language)
        copyButton.setTitle("Copied", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copyButton.setTitle("Copy", for: .normal)
        }
    }

    private final class Canvas: UIView {
        var layout: MdCodeRowLayout?
        override func draw(_ rect: CGRect) {
            guard let layout, let ctx = UIGraphicsGetCurrentContext() else { return }
            layout.frame.draw(in: ctx, at: CGPoint(x: layout.padding, y: layout.padding))
        }
    }
}

// MARK: - table

final class MdTableCell: UITableViewCell {
    static let reuseId = "MdTableCell"

    private let scrollView = UIScrollView()
    private let canvas = Canvas()
    private var layout: MdTableRowLayout?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(scrollView)
        scrollView.addSubview(canvas)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ layout: MdTableRowLayout, theme: MdTheme) {
        self.layout = layout
        canvas.layout = layout
        canvas.theme = theme
        canvas.backgroundColor = theme.background
        scrollView.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        backgroundColor = theme.background
        scrollView.contentOffset = .zero
        setNeedsLayout()
        canvas.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout else { return }
        let height = layout.rowH.reduce(0, +)
        scrollView.frame = CGRect(
            x: layout.left, y: layout.topMargin,
            width: max(0, contentView.bounds.width - layout.left * 2), height: height
        )
        canvas.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: height)
        scrollView.contentSize = canvas.frame.size
    }

    private final class Canvas: UIView {
        var layout: MdTableRowLayout?
        var theme: MdTheme?

        override func draw(_ rect: CGRect) {
            guard let layout, let theme, let ctx = UIGraphicsGetCurrentContext() else { return }
            let total = layout.rowH.reduce(0, +)

            ctx.setFillColor(theme.tableHeaderBg.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.rowH.first ?? 0))

            ctx.setStrokeColor(theme.tableBorder.cgColor)
            ctx.setLineWidth(1)

            var y: CGFloat = 0
            for r in layout.cells.indices {
                var x: CGFloat = 0
                for c in layout.cells[r].indices {
                    layout.cells[r][c].draw(in: ctx, at: CGPoint(x: x + layout.cellPad, y: y + layout.cellPad))
                    x += layout.colW[c]
                    if c < layout.colW.count - 1 {
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addLine(to: CGPoint(x: x, y: y + layout.rowH[r]))
                        ctx.strokePath()
                    }
                }
                y += layout.rowH[r]
                if r < layout.cells.count - 1 {
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: layout.contentWidth, y: y))
                    ctx.strokePath()
                }
            }

            let border = CGRect(x: 0.5, y: 0.5, width: layout.contentWidth - 1, height: total - 1)
            ctx.addPath(UIBezierPath(roundedRect: border, cornerRadius: 10).cgPath)
            ctx.strokePath()
        }
    }
}

// MARK: - thematic break

final class MdDividerCell: UITableViewCell {
    static let reuseId = "MdDividerCell"

    private let line = UIView()
    private var layout: MdDividerRowLayout?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        contentView.addSubview(line)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ layout: MdDividerRowLayout, theme: MdTheme) {
        self.layout = layout
        line.backgroundColor = theme.divider
        contentView.backgroundColor = theme.background
        backgroundColor = theme.background
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout else { return }
        line.frame = CGRect(
            x: layout.inset,
            y: contentView.bounds.midY,
            width: max(0, contentView.bounds.width - layout.inset * 2),
            height: 1 / UIScreen.main.scale
        )
    }
}
