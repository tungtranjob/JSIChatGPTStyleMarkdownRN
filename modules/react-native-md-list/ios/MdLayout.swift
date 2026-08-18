import UIKit
import CoreText

extension NSAttributedString.Key {
    /// URL carried on a range; hit tested manually against the CTFrame.
    static let mdLink = NSAttributedString.Key("MdLink")
}

/// A laid out block of text.
///
/// CoreText rather than TextKit on purpose: CTFramesetter is thread safe, so the
/// expensive part (line breaking) happens on a worker queue and the main thread
/// only ever calls CTFrameDraw.
final class MdTextFrame {
    let attributed: NSAttributedString
    let ctFrame: CTFrame
    let size: CGSize

    init(_ attributed: NSAttributedString, width: CGFloat) {
        self.attributed = attributed
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let constraints = CGSize(width: max(1, width), height: 100_000)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraints, &fitRange
        )
        let h = ceil(suggested.height)
        size = CGSize(width: ceil(suggested.width), height: h)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, width), height: max(1, h)), transform: nil)
        ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    }

    func draw(in ctx: CGContext, at origin: CGPoint) {
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: origin.x, y: origin.y + size.height)
        ctx.scaleBy(x: 1, y: -1)
        CTFrameDraw(ctFrame, ctx)
        ctx.restoreGState()
    }

    /// `point` is in UIKit coordinates relative to the frame's top-left corner.
    func link(at point: CGPoint) -> String? {
        guard let lines = CTFrameGetLines(ctFrame) as? [CTLine], !lines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &origins)
        let flipped = CGPoint(x: point.x, y: size.height - point.y)

        for (i, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let o = origins[i]
            let rect = CGRect(x: o.x, y: o.y - descent, width: w, height: ascent + descent)
            guard rect.contains(flipped) else { continue }
            let index = CTLineGetStringIndexForPosition(line, CGPoint(x: flipped.x - o.x, y: 0))
            guard index >= 0, index < attributed.length else { return nil }
            return attributed.attribute(.mdLink, at: index, effectiveRange: nil) as? String
        }
        return nil
    }
}

// MARK: - row layouts

class MdRowLayout {
    let height: CGFloat
    init(height: CGFloat) { self.height = height }
}

final class MdTextRowLayout: MdRowLayout {
    let frame: MdTextFrame
    let textOrigin: CGPoint
    let marker: MdTextFrame?
    let markerX: CGFloat
    let quoteDepth: Int
    let quoteX: CGFloat
    let checked: Int

    init(frame: MdTextFrame, textOrigin: CGPoint, marker: MdTextFrame?, markerX: CGFloat,
         quoteDepth: Int, quoteX: CGFloat, checked: Int, height: CGFloat) {
        self.frame = frame
        self.textOrigin = textOrigin
        self.marker = marker
        self.markerX = markerX
        self.quoteDepth = quoteDepth
        self.quoteX = quoteX
        self.checked = checked
        super.init(height: height)
    }
}

final class MdBubbleRowLayout: MdRowLayout {
    let frame: MdTextFrame
    let bubbleRect: CGRect
    let pad: CGFloat

    init(frame: MdTextFrame, bubbleRect: CGRect, pad: CGFloat, height: CGFloat) {
        self.frame = frame
        self.bubbleRect = bubbleRect
        self.pad = pad
        super.init(height: height)
    }
}

final class MdCodeRowLayout: MdRowLayout {
    let language: String
    let code: String
    let frame: MdTextFrame
    let headerHeight: CGFloat
    let contentWidth: CGFloat
    let padding: CGFloat
    let left: CGFloat
    let boxWidth: CGFloat
    let topMargin: CGFloat

    init(language: String, code: String, frame: MdTextFrame, headerHeight: CGFloat,
         contentWidth: CGFloat, padding: CGFloat, left: CGFloat, boxWidth: CGFloat,
         topMargin: CGFloat, height: CGFloat) {
        self.language = language
        self.code = code
        self.frame = frame
        self.headerHeight = headerHeight
        self.contentWidth = contentWidth
        self.padding = padding
        self.left = left
        self.boxWidth = boxWidth
        self.topMargin = topMargin
        super.init(height: height)
    }
}

final class MdTableRowLayout: MdRowLayout {
    let cells: [[MdTextFrame]]
    let colW: [CGFloat]
    let rowH: [CGFloat]
    let contentWidth: CGFloat
    let cellPad: CGFloat
    let left: CGFloat
    let topMargin: CGFloat

    init(cells: [[MdTextFrame]], colW: [CGFloat], rowH: [CGFloat], contentWidth: CGFloat,
         cellPad: CGFloat, left: CGFloat, topMargin: CGFloat, height: CGFloat) {
        self.cells = cells
        self.colW = colW
        self.rowH = rowH
        self.contentWidth = contentWidth
        self.cellPad = cellPad
        self.left = left
        self.topMargin = topMargin
        super.init(height: height)
    }
}

final class MdDividerRowLayout: MdRowLayout {
    let inset: CGFloat
    init(inset: CGFloat, height: CGFloat) {
        self.inset = inset
        super.init(height: height)
    }
}

// MARK: - engine

final class MdLayoutEngine {

    let theme: MdTheme
    let hPad: CGFloat = 16
    private let quoteInset: CGFloat = 14
    private let listIndent: CGFloat = 18
    private let markerGutter: CGFloat = 20

    private let cache = NSCache<NSString, MdRowLayout>()

    init(theme: MdTheme) {
        self.theme = theme
        cache.countLimit = 600
    }

    private func key(_ row: MdRow, _ width: CGFloat) -> NSString {
        "\(row.layoutKey)|\(Int(width))|\(theme.key)" as NSString
    }

    func cachedLayout(for row: MdRow, width: CGFloat) -> MdRowLayout? {
        cache.object(forKey: key(row, width))
    }

    @discardableResult
    func layout(for row: MdRow, width: CGFloat) -> MdRowLayout {
        let k = key(row, width)
        if let hit = cache.object(forKey: k) { return hit }
        let built = build(row, width: width)
        cache.setObject(built, forKey: k)
        return built
    }

    private func build(_ row: MdRow, width: CGFloat) -> MdRowLayout {
        switch row.type {
        case .bubble: return buildBubble(row, width: width)
        case .code: return buildCode(row, width: width)
        case .table: return buildTable(row, width: width)
        case .divider: return MdDividerRowLayout(inset: hPad, height: 25)
        default: return buildText(row, width: width)
        }
    }

    // MARK: text

    private func buildText(_ row: MdRow, width: CGFloat) -> MdRowLayout {
        let isQuote = row.quoteDepth > 0
        let font: UIFont = row.type == .heading ? theme.headingFont(row.headingLevel) : theme.body
        let color: UIColor = isQuote ? theme.quoteFg : theme.textPrimary

        var left = hPad + CGFloat(row.quoteDepth) * quoteInset
        var marker: MdTextFrame?
        var markerX: CGFloat = 0

        if row.type == .listItem {
            left += CGFloat(row.listDepth) * listIndent
            markerX = left
            if row.checked < 0, let m = row.listMarker {
                marker = MdTextFrame(
                    attributed(MdInlineText(text: m, spans: []), font: font, color: theme.textSecondary),
                    width: markerGutter
                )
            }
            left += markerGutter
        }

        let avail = max(1, width - left - hPad)
        let string = attributed(row.inline, font: font, color: color)
        let frame = MdTextFrame(string, width: avail)

        let topPad = topPadding(row)
        let bottomPad = bottomPadding(row)

        return MdTextRowLayout(
            frame: frame,
            textOrigin: CGPoint(x: left, y: topPad),
            marker: marker,
            markerX: markerX,
            quoteDepth: row.quoteDepth,
            quoteX: hPad,
            checked: row.checked,
            height: ceil(topPad + frame.size.height + bottomPad)
        )
    }

    private func topPadding(_ row: MdRow) -> CGFloat {
        let extra: CGFloat = row.isFirstInMessage ? 10 : 0
        switch row.type {
        case .heading:
            switch row.headingLevel {
            case 1: return extra + 18
            case 2: return extra + 16
            case 3: return extra + 14
            default: return extra + 12
            }
        case .listItem: return extra + 3
        default: return extra + 6
        }
    }

    private func bottomPadding(_ row: MdRow) -> CGFloat {
        let extra: CGFloat = row.isLastInMessage ? 20 : 0
        switch row.type {
        case .heading: return extra + 6
        case .listItem: return extra + 3
        default: return extra + 6
        }
    }

    // MARK: bubble

    private func buildBubble(_ row: MdRow, width: CGFloat) -> MdRowLayout {
        let pad: CGFloat = 13
        let maxText = max(1, width * 0.84 - pad * 2)
        let string = attributed(row.inline, font: theme.body, color: theme.textPrimary)
        let frame = MdTextFrame(string, width: maxText)
        let bubbleW = min(maxText, frame.size.width) + pad * 2
        let bubbleH = frame.size.height + pad * 2
        let top: CGFloat = row.isFirstInMessage ? 14 : 4
        let bottom: CGFloat = 10
        return MdBubbleRowLayout(
            frame: frame,
            bubbleRect: CGRect(x: width - hPad - bubbleW, y: top, width: bubbleW, height: bubbleH),
            pad: pad,
            height: ceil(top + bubbleH + bottom)
        )
    }

    // MARK: code

    private func buildCode(_ row: MdRow, width: CGFloat) -> MdRowLayout {
        let code = row.code ?? ""
        let pad: CGFloat = 12
        let headerH: CGFloat = 32
        let left = hPad + CGFloat(row.quoteDepth) * quoteInset
        let boxWidth = width - left - hPad

        let string = NSMutableAttributedString(string: code)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        para.lineBreakMode = .byClipping
        string.addAttributes(
            [.font: theme.codeFont, .foregroundColor: theme.codeFg, .paragraphStyle: para],
            range: NSRange(location: 0, length: string.length)
        )
        for token in MdCodeHighlighter.tokenize(code, language: row.language ?? "text") {
            let location = max(0, min(token.start, string.length))
            let length = max(0, min(token.end, string.length) - location)
            guard length > 0 else { continue }
            string.addAttribute(
                .foregroundColor,
                value: color(for: token.kind),
                range: NSRange(location: location, length: length)
            )
        }

        // measure unwrapped, then let the row scroll horizontally
        let natural = MdTextFrame(string, width: 100_000).size.width
        let contentWidth = max(natural, boxWidth - pad * 2)
        let frame = MdTextFrame(string, width: contentWidth)

        let topMargin: CGFloat = 8 + (row.isFirstInMessage ? 10 : 0)
        let bottomMargin: CGFloat = 8 + (row.isLastInMessage ? 20 : 0)

        return MdCodeRowLayout(
            language: row.language ?? "text",
            code: code,
            frame: frame,
            headerHeight: headerH,
            contentWidth: contentWidth,
            padding: pad,
            left: left,
            boxWidth: boxWidth,
            topMargin: topMargin,
            height: ceil(topMargin + headerH + pad * 2 + frame.size.height + bottomMargin)
        )
    }

    private func color(for kind: MdCodeHighlighter.Kind) -> UIColor {
        switch kind {
        case .keyword: return theme.synKeyword
        case .string: return theme.synString
        case .number: return theme.synNumber
        case .comment: return theme.synComment
        case .type: return theme.synType
        case .function: return theme.synFunc
        }
    }

    // MARK: table

    private func buildTable(_ row: MdRow, width: CGFloat) -> MdRowLayout {
        guard let table = row.table else { return MdDividerRowLayout(inset: hPad, height: 0) }
        let cols = table.header.count
        let cellPad: CGFloat = 10
        let left = hPad + CGFloat(row.quoteDepth) * quoteInset
        let avail = width - left - hPad
        let maxCol: CGFloat = 230

        var allRows: [[MdInlineText]] = [table.header]
        allRows.append(contentsOf: table.rows)

        let strings: [[NSAttributedString]] = allRows.enumerated().map { (r, cells) in
            (0..<cols).map { c in
                let font = r == 0 ? theme.tableHeadFont : theme.tableCellFont
                let alignment: NSTextAlignment
                switch table.aligns.indices.contains(c) ? table.aligns[c] : .left {
                case .center: alignment = .center
                case .right: alignment = .right
                case .left: alignment = .natural
                }
                return attributed(
                    c < cells.count ? cells[c] : .empty,
                    font: font, color: theme.textPrimary, alignment: alignment
                )
            }
        }

        var colW = [CGFloat](repeating: 0, count: cols)
        for c in 0..<cols {
            var w: CGFloat = 0
            for r in strings.indices {
                w = max(w, MdTextFrame(strings[r][c], width: 100_000).size.width)
            }
            colW[c] = ceil(min(w, maxCol)) + cellPad * 2
        }

        let natural = colW.reduce(0, +)
        if natural < avail, natural > 0 {
            var used: CGFloat = 0
            for c in 0..<cols {
                let add = c == cols - 1 ? (avail - natural - used) : (avail - natural) * colW[c] / natural
                colW[c] += add
                used += add
            }
        }

        let cells: [[MdTextFrame]] = strings.map { rowStrings in
            (0..<cols).map { c in MdTextFrame(rowStrings[c], width: max(1, colW[c] - cellPad * 2)) }
        }
        let rowH: [CGFloat] = cells.map { rowFrames in
            (rowFrames.map { $0.size.height }.max() ?? 0) + cellPad * 2
        }

        let topMargin: CGFloat = 8
        let bottomMargin: CGFloat = 8 + (row.isLastInMessage ? 20 : 0)
        return MdTableRowLayout(
            cells: cells,
            colW: colW,
            rowH: rowH,
            contentWidth: colW.reduce(0, +),
            cellPad: cellPad,
            left: left,
            topMargin: topMargin,
            height: ceil(topMargin + rowH.reduce(0, +) + bottomMargin)
        )
    }

    // MARK: attributed string

    func attributed(
        _ inline: MdInlineText,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(string: inline.text)
        let full = NSRange(location: 0, length: string.length)
        guard full.length > 0 else { return string }

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.alignment = alignment
        para.lineBreakMode = .byWordWrapping
        string.addAttributes([.font: font, .foregroundColor: color, .paragraphStyle: para], range: full)

        for span in inline.spans {
            let location = max(0, min(span.start, string.length))
            let length = max(0, min(span.end, string.length) - location)
            guard length > 0 else { continue }
            let range = NSRange(location: location, length: length)

            if span.style.contains(.code) {
                string.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular),
                    .foregroundColor: theme.inlineCodeFg,
                    .backgroundColor: theme.inlineCodeBg,
                ], range: range)
            } else if span.style.contains(.bold) || span.style.contains(.italic) {
                var updates: [(NSRange, UIFont)] = []
                string.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
                    let current = (value as? UIFont) ?? font
                    updates.append((sub, withTraits(
                        current,
                        bold: span.style.contains(.bold),
                        italic: span.style.contains(.italic)
                    )))
                }
                for (sub, f) in updates { string.addAttribute(.font, value: f, range: sub) }
            }

            if span.style.contains(.strike) {
                string.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if let link = span.link {
                string.addAttributes([.foregroundColor: theme.link, .mdLink: link], range: range)
            }
        }
        return string
    }

    private func withTraits(_ font: UIFont, bold: Bool, italic: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
