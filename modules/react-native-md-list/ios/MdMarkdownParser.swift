import Foundation

/// Block level parser: same grammar subset and same output shape as the Kotlin one.
/// Hand rolled rather than regex based: on a 5 kB answer this is roughly an order
/// of magnitude cheaper than NSRegularExpression, and it runs per streamed token.
enum MdMarkdownParser {

    private final class Ctx {
        let messageId: String
        let streaming: Bool
        var out: [MdRow] = []
        var seq = 0
        init(messageId: String, streaming: Bool) {
            self.messageId = messageId
            self.streaming = streaming
        }
        func nextId() -> String {
            defer { seq += 1 }
            return "\(messageId):\(seq)"
        }
    }

    static func parse(messageId: String, role: String, markdown: String, streaming: Bool) -> [MdRow] {
        if role == "user" {
            return [MdRow(
                id: "\(messageId):0",
                messageId: messageId,
                type: .bubble,
                inline: MdInlineParser.parse(markdown.trimmingCharacters(in: .whitespacesAndNewlines)),
                isFirstInMessage: true,
                isLastInMessage: true,
                streaming: streaming
            )]
        }

        let ctx = Ctx(messageId: messageId, streaming: streaming)
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        parseBlocks(lines, quoteDepth: 0, ctx: ctx)

        ctx.out.first?.isFirstInMessage = true
        ctx.out.last?.isLastInMessage = true
        return ctx.out
    }

    // MARK: - blocks

    private static func parseBlocks(_ lines: [String], quoteDepth: Int, ctx: Ctx) {
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // fenced code
            if let fence = parseFence(line) {
                var body: [String] = []
                var j = i + 1
                var closed = false
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(fence.marker), t.allSatisfy({ $0 == fence.marker.first! }) {
                        closed = true; j += 1; break
                    }
                    body.append(lines[j])
                    j += 1
                }
                ctx.out.append(MdRow(
                    id: ctx.nextId(), messageId: ctx.messageId, type: .code,
                    quoteDepth: quoteDepth,
                    code: body.joined(separator: "\n"),
                    language: fence.language.isEmpty ? "text" : fence.language,
                    streaming: ctx.streaming && !closed
                ))
                i = j
                continue
            }

            // ATX heading
            if let heading = parseHeading(trimmed) {
                ctx.out.append(MdRow(
                    id: ctx.nextId(), messageId: ctx.messageId, type: .heading,
                    inline: MdInlineParser.parse(heading.content),
                    headingLevel: heading.level, quoteDepth: quoteDepth, streaming: ctx.streaming
                ))
                i += 1
                continue
            }

            // setext heading
            if i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.count >= 2,
                   next.allSatisfy({ $0 == "=" }) || next.allSatisfy({ $0 == "-" }),
                   parseListItem(line) == nil, !isThematicBreak(next) {
                    ctx.out.append(MdRow(
                        id: ctx.nextId(), messageId: ctx.messageId, type: .heading,
                        inline: MdInlineParser.parse(trimmed),
                        headingLevel: next.first == "=" ? 1 : 2,
                        quoteDepth: quoteDepth, streaming: ctx.streaming
                    ))
                    i += 2
                    continue
                }
            }

            // thematic break
            if isThematicBreak(trimmed) {
                ctx.out.append(MdRow(
                    id: ctx.nextId(), messageId: ctx.messageId, type: .divider,
                    quoteDepth: quoteDepth, streaming: ctx.streaming
                ))
                i += 1
                continue
            }

            // block quote
            if trimmed.hasPrefix(">") {
                var inner: [String] = []
                var j = i
                while j < lines.count {
                    let t = lines[j].drop(while: { $0 == " " || $0 == "\t" })
                    if t.hasPrefix(">") {
                        var s = String(t.dropFirst())
                        if s.hasPrefix(" ") { s.removeFirst() }
                        inner.append(s)
                    } else if !t.isEmpty && !inner.isEmpty {
                        inner.append(String(t))
                    } else {
                        break
                    }
                    j += 1
                }
                parseBlocks(inner, quoteDepth: quoteDepth + 1, ctx: ctx)
                i = j
                continue
            }

            // table
            if line.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                let headerCells = splitRow(line)
                let aligns = parseAligns(lines[i + 1], count: headerCells.count)
                var bodyRows: [[MdInlineText]] = []
                var j = i + 2
                while j < lines.count, lines[j].contains("|"),
                      !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    let cells = splitRow(lines[j])
                    bodyRows.append((0..<headerCells.count).map { c in
                        MdInlineParser.parse(c < cells.count ? cells[c] : "")
                    })
                    j += 1
                }
                ctx.out.append(MdRow(
                    id: ctx.nextId(), messageId: ctx.messageId, type: .table,
                    quoteDepth: quoteDepth,
                    table: MdTable(
                        header: headerCells.map { MdInlineParser.parse($0) },
                        rows: bodyRows,
                        aligns: aligns
                    ),
                    streaming: ctx.streaming
                ))
                i = j
                continue
            }

            // list
            if parseListItem(line) != nil {
                i = parseListRun(lines, start: i, quoteDepth: quoteDepth, ctx: ctx)
                continue
            }

            // paragraph
            var para: [String] = []
            var j = i
            while j < lines.count {
                let l = lines[j]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if j > i, startsNewBlock(l, lines, j) { break }
                para.append(t)
                j += 1
            }
            ctx.out.append(MdRow(
                id: ctx.nextId(), messageId: ctx.messageId, type: .paragraph,
                inline: MdInlineParser.parse(para.joined(separator: "\n")),
                quoteDepth: quoteDepth, streaming: ctx.streaming
            ))
            i = j
        }
    }

    private static func startsNewBlock(_ line: String, _ lines: [String], _ index: Int) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix(">") { return true }
        if isThematicBreak(t) { return true }
        if parseHeading(t) != nil { return true }
        if parseFence(line) != nil { return true }
        if parseListItem(line) != nil { return true }
        if line.contains("|"), index + 1 < lines.count, isTableDelimiter(lines[index + 1]) { return true }
        return false
    }

    private static func parseListRun(_ lines: [String], start: Int, quoteDepth: Int, ctx: Ctx) -> Int {
        var indentStack: [Int] = []
        var counters: [Int] = []
        var i = start
        var lastIndent = 0

        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard i + 1 < lines.count else { break }
                let next = lines[i + 1]
                if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                let nextIndent = indentOf(next)
                if parseListItem(next) == nil && nextIndent <= lastIndent { break }
                i += 1
                continue
            }

            guard let item = parseListItem(line) else {
                let indent = indentOf(line)
                if indent > lastIndent, parseFence(line) != nil { break }
                if indent > lastIndent, let prev = ctx.out.last {
                    ctx.out.removeLast()
                    let merged = prev.inline.text + "\n" + line.trimmingCharacters(in: .whitespaces)
                    ctx.out.append(MdRow(
                        id: prev.id, messageId: prev.messageId, type: prev.type,
                        inline: MdInlineParser.parse(merged),
                        listMarker: prev.listMarker, listDepth: prev.listDepth,
                        quoteDepth: prev.quoteDepth, checked: prev.checked, streaming: ctx.streaming
                    ))
                    i += 1
                    continue
                }
                break
            }

            while let top = indentStack.last, item.indent < top {
                indentStack.removeLast()
                counters.removeLast()
            }
            if indentStack.isEmpty || item.indent > indentStack.last! {
                indentStack.append(item.indent)
                counters.append(0)
            }
            let depth = indentStack.count - 1
            counters[depth] += 1

            var content = item.content
            var checked = -1
            let chars = Array(content)
            if chars.count >= 3, chars[0] == "[", chars[2] == "]" {
                if chars[1] == " " { checked = 0 }
                else if chars[1] == "x" || chars[1] == "X" { checked = 1 }
                if checked >= 0 {
                    content = String(chars[3...]).trimmingCharacters(in: .whitespaces)
                }
            }

            let ordered = item.marker.first?.isNumber == true
            let marker: String
            if ordered {
                let number = Int(item.marker.dropLast()) ?? counters[depth]
                marker = "\(number)."
            } else {
                marker = bullet(depth)
            }

            ctx.out.append(MdRow(
                id: ctx.nextId(), messageId: ctx.messageId, type: .listItem,
                inline: MdInlineParser.parse(content),
                listMarker: marker, listDepth: depth, quoteDepth: quoteDepth,
                checked: checked, streaming: ctx.streaming
            ))
            lastIndent = item.indent
            i += 1
        }
        return i == start ? start + 1 : i
    }

    // MARK: - line matchers

    private static func bullet(_ depth: Int) -> String {
        switch depth % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    private static func indentOf(_ line: String) -> Int {
        var n = 0
        for c in line {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return n
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, content: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var chars = Array(trimmed)
        while level < chars.count, chars[level] == "#" { level += 1 }
        guard level <= 6, level < chars.count, chars[level] == " " else { return nil }
        var content = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        while content.hasSuffix("#") { content.removeLast() }
        chars = []
        return (level, content.trimmingCharacters(in: .whitespaces))
    }

    private static func parseFence(_ line: String) -> (marker: String, language: String)? {
        let t = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = t.first, first == "`" || first == "~" else { return nil }
        var count = 0
        for c in t { if c == first { count += 1 } else { break } }
        guard count >= 3 else { return nil }
        let rest = String(t.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        if first == "`" && rest.contains("`") { return nil }
        let language = rest.components(separatedBy: " ").first ?? ""
        return (String(repeating: String(first), count: count), language)
    }

    private static func parseListItem(_ line: String) -> (indent: Int, marker: String, content: String)? {
        let indent = indentOf(line)
        let chars = Array(line)
        var i = indent
        guard i < chars.count else { return nil }
        var marker = ""
        if chars[i] == "*" || chars[i] == "+" || chars[i] == "-" {
            marker = String(chars[i]); i += 1
        } else if chars[i].isNumber {
            var digits = ""
            while i < chars.count, chars[i].isNumber, digits.count < 9 { digits.append(chars[i]); i += 1 }
            guard i < chars.count, chars[i] == "." || chars[i] == ")" else { return nil }
            marker = digits + String(chars[i])
            i += 1
        } else {
            return nil
        }
        guard i < chars.count, chars[i] == " " || chars[i] == "\t" else { return nil }
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        return (indent, marker, String(chars[i...]))
    }

    private static func isThematicBreak(_ t: String) -> Bool {
        guard t.count >= 3, let c = t.first, c == "-" || c == "*" || c == "_" else { return false }
        return t.allSatisfy { $0 == c || $0 == " " } && t.filter { $0 == c }.count >= 3
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func parseAligns(_ line: String, count: Int) -> [MdAlign] {
        let parts = splitRow(line)
        return (0..<count).map { idx in
            let p = idx < parts.count ? parts[idx].trimmingCharacters(in: .whitespaces) : ""
            if p.hasPrefix(":") && p.hasSuffix(":") { return .center }
            if p.hasSuffix(":") { return .right }
            return .left
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        var cells: [String] = []
        var cur = ""
        var inCode = false
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                cur.append(chars[i + 1]); i += 2; continue
            }
            if c == "`" { inCode.toggle(); cur.append(c) }
            else if c == "|" && !inCode { cells.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(c) }
            i += 1
        }
        cells.append(cur.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
