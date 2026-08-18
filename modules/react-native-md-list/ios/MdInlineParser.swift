import Foundation

/// Port of the Kotlin inline scanner. Emits a plain string plus UTF-16 ranges so
/// the result maps straight onto NSAttributedString without another pass.
enum MdInlineParser {

    private static let maxDepth = 8

    private struct Ctx {
        var out = ""
        var len = 0            // running UTF-16 length, so span offsets are O(1)
        var spans: [MdSpan] = []

        mutating func append(_ c: Character) {
            out.append(c)
            len += String(c).utf16.count
        }

        mutating func append(_ s: String) {
            out += s
            len += s.utf16.count
        }
    }

    static func parse(_ src: String) -> MdInlineText {
        if src.isEmpty { return .empty }
        let chars = Array(src)
        var ctx = Ctx()
        render(chars, 0, chars.count, [], nil, 0, &ctx)
        return MdInlineText(text: ctx.out, spans: ctx.spans)
    }

    private static func render(
        _ s: [Character],
        _ from: Int,
        _ to: Int,
        _ style: MdInlineStyle,
        _ link: String?,
        _ depth: Int,
        _ ctx: inout Ctx
    ) {
        let segStart = ctx.len
        var i = from
        while i < to {
            let c = s[i]

            if c == "\\", i + 1 < to, isPunct(s[i + 1]) {
                ctx.append(s[i + 1]); i += 2; continue
            }

            if c == "`" {
                var n = 0
                while i + n < to && s[i + n] == "`" { n += 1 }
                let close = findRun(s, i + n, to, "`", n)
                if close < 0 {
                    ctx.append(String(s[i..<(i + n)])); i += n
                } else {
                    var content = String(s[(i + n)..<close])
                    if content.count > 1 && content.hasPrefix(" ") && content.hasSuffix(" ") {
                        content = String(content.dropFirst().dropLast())
                    }
                    let start = ctx.len
                    ctx.append(content)
                    ctx.spans.append(MdSpan(start: start, end: ctx.len, style: style.union(.code), link: link))
                    i = close + n
                }
                continue
            }

            if (c == "*" || c == "_") && depth < maxDepth {
                let intraword = (c == "_") && i > from && isWordChar(s[i - 1])
                var n = 0
                while i + n < to && s[i + n] == c { n += 1 }
                let take = n >= 2 ? 2 : 1
                let close = intraword ? -1 : findRun(s, i + take, to, c, take)
                if close < 0 || close == i + take {
                    ctx.append(String(s[i..<(i + n)])); i += n
                } else {
                    let added: MdInlineStyle = take >= 2 ? .bold : .italic
                    render(s, i + take, close, style.union(added), link, depth + 1, &ctx)
                    i = close + take
                }
                continue
            }

            if c == "~", i + 1 < to, s[i + 1] == "~", depth < maxDepth {
                let close = findRun(s, i + 2, to, "~", 2)
                if close < 0 {
                    ctx.append(c); i += 1
                } else {
                    render(s, i + 2, close, style.union(.strike), link, depth + 1, &ctx)
                    i = close + 2
                }
                continue
            }

            if c == "!", i + 1 < to, s[i + 1] == "[" {
                let consumed = renderLink(s, i + 1, to, style, depth, &ctx, image: true)
                if consumed > 0 { i = consumed } else { ctx.append(c); i += 1 }
                continue
            }

            if c == "[" {
                let consumed = renderLink(s, i, to, style, depth, &ctx, image: false)
                if consumed > 0 { i = consumed } else { ctx.append(c); i += 1 }
                continue
            }

            if c == "<" {
                var gt = -1
                var k = i + 1
                while k < to { if s[k] == ">" { gt = k; break }; k += 1 }
                if gt > 0 {
                    let inner = String(s[(i + 1)..<gt])
                    if inner.hasPrefix("http://") || inner.hasPrefix("https://")
                        || (inner.contains("@") && !inner.contains(" ")) {
                        let start = ctx.len
                        ctx.append(inner)
                        ctx.spans.append(MdSpan(start: start, end: ctx.len, style: style, link: inner))
                        i = gt + 1
                        continue
                    }
                }
                ctx.append(c); i += 1
                continue
            }

            if (c == "h" || c == "w"), link == nil, isBareUrlStart(s, i, from, to) {
                var end = i
                while end < to && !s[end].isWhitespace { end += 1 }
                while end > i, ".,;:!?)”\"'".contains(s[end - 1]) { end -= 1 }
                let raw = String(s[i..<end])
                let start = ctx.len
                ctx.append(raw)
                let url = raw.hasPrefix("w") ? "https://\(raw)" : raw
                ctx.spans.append(MdSpan(start: start, end: ctx.len, style: style, link: url))
                i = end
                continue
            }

            ctx.append(c)
            i += 1
        }

        if ctx.len > segStart && (!style.isEmpty || link != nil) {
            ctx.spans.append(MdSpan(start: segStart, end: ctx.len, style: style, link: link))
        }
    }

    private static func renderLink(
        _ s: [Character],
        _ open: Int,
        _ to: Int,
        _ style: MdInlineStyle,
        _ depth: Int,
        _ ctx: inout Ctx,
        image: Bool
    ) -> Int {
        let close = matchBracket(s, open, to)
        guard close >= 0, close + 1 < to, s[close + 1] == "(" else { return -1 }
        let paren = matchParen(s, close + 1, to)
        guard paren >= 0 else { return -1 }
        var url = String(s[(close + 2)..<paren]).trimmingCharacters(in: .whitespaces)
        if let space = url.firstIndex(of: " ") { url = String(url[url.startIndex..<space]) }
        if url.hasPrefix("<") && url.hasSuffix(">") { url = String(url.dropFirst().dropLast()) }

        if image {
            let alt = String(s[(open + 1)..<close])
            let start = ctx.len
            ctx.append("🖼 " + (alt.isEmpty ? "image" : alt))
            ctx.spans.append(MdSpan(start: start, end: ctx.len, style: style.union(.italic), link: url))
        } else {
            render(s, open + 1, close, style, url, depth + 1, &ctx)
        }
        return paren + 1
    }

    // MARK: - helpers

    private static func isBareUrlStart(_ s: [Character], _ i: Int, _ from: Int, _ to: Int) -> Bool {
        if i > from, isWordChar(s[i - 1]) || s[i - 1] == "(" || s[i - 1] == "/" { return false }
        return matches(s, i, to, "http://") || matches(s, i, to, "https://") || matches(s, i, to, "www.")
    }

    private static func matches(_ s: [Character], _ i: Int, _ to: Int, _ needle: String) -> Bool {
        let n = Array(needle)
        if i + n.count > to { return false }
        for k in 0..<n.count where s[i + k] != n[k] { return false }
        return true
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private static func isPunct(_ c: Character) -> Bool { "\\`*_{}[]()#+-.!|~<>\"".contains(c) }

    private static func findRun(_ s: [Character], _ from: Int, _ to: Int, _ ch: Character, _ n: Int) -> Int {
        var i = from
        while i < to {
            if s[i] == "\\" { i += 2; continue }
            if s[i] == ch {
                var k = 0
                while i + k < to && s[i + k] == ch { k += 1 }
                if k >= n { return i }
                i += k
            } else {
                i += 1
            }
        }
        return -1
    }

    private static func matchBracket(_ s: [Character], _ open: Int, _ to: Int) -> Int {
        var level = 0
        var i = open
        while i < to {
            if s[i] == "\\" { i += 2; continue }
            if s[i] == "[" { level += 1 }
            else if s[i] == "]" { level -= 1; if level == 0 { return i } }
            i += 1
        }
        return -1
    }

    private static func matchParen(_ s: [Character], _ open: Int, _ to: Int) -> Int {
        var level = 0
        var i = open
        while i < to {
            if s[i] == "\\" { i += 2; continue }
            if s[i] == "(" { level += 1 }
            else if s[i] == ")" { level -= 1; if level == 0 { return i } }
            i += 1
        }
        return -1
    }
}
