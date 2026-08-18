package com.mdlist.md

/**
 * Single pass inline markdown scanner.
 *
 * Produces a flat string + a list of ranges, which maps 1:1 onto Android
 * Spannables and NSAttributedString on iOS, so the same parse output can be
 * turned into a text layout without an intermediate tree walk.
 */
object InlineParser {

    private const val MAX_DEPTH = 8

    fun parse(src: String): InlineText {
        if (src.isEmpty()) return InlineText.EMPTY
        val sb = StringBuilder(src.length)
        val spans = ArrayList<InlineSpan>(4)
        render(src, 0, src.length, 0, null, 0, sb, spans)
        return InlineText(sb.toString(), spans)
    }

    private fun render(
        s: String,
        from: Int,
        to: Int,
        style: Int,
        link: String?,
        depth: Int,
        sb: StringBuilder,
        out: MutableList<InlineSpan>,
    ) {
        val segStart = sb.length
        var i = from
        while (i < to) {
            val c = s[i]
            when {
                c == '\\' && i + 1 < to && isPunct(s[i + 1]) -> {
                    sb.append(s[i + 1]); i += 2
                }

                c == '`' -> {
                    var n = 0
                    while (i + n < to && s[i + n] == '`') n++
                    val close = findRun(s, i + n, to, '`', n)
                    if (close < 0) {
                        sb.append(s, i, i + n); i += n
                    } else {
                        val start = sb.length
                        var content = s.substring(i + n, close)
                        if (content.length > 1 && content.startsWith(" ") && content.endsWith(" ")) {
                            content = content.substring(1, content.length - 1)
                        }
                        sb.append(content)
                        out.add(InlineSpan(start, sb.length, style or SPAN_CODE, link))
                        i = close + n
                    }
                }

                (c == '*' || c == '_') && depth < MAX_DEPTH -> {
                    // `_` must not fire inside words (snake_case_identifiers).
                    val intraword = c == '_' && i > from && isWordChar(s[i - 1])
                    var n = 0
                    while (i + n < to && s[i + n] == c) n++
                    val take = if (n >= 2) 2 else 1
                    val close = if (intraword) -1 else findRun(s, i + take, to, c, take)
                    if (close < 0 || close == i + take) {
                        sb.append(s, i, i + n); i += n
                    } else {
                        val added = if (take >= 2) SPAN_BOLD else SPAN_ITALIC
                        render(s, i + take, close, style or added, link, depth + 1, sb, out)
                        i = close + take
                    }
                }

                c == '~' && i + 1 < to && s[i + 1] == '~' && depth < MAX_DEPTH -> {
                    val close = findRun(s, i + 2, to, '~', 2)
                    if (close < 0) {
                        sb.append(c); i++
                    } else {
                        render(s, i + 2, close, style or SPAN_STRIKE, link, depth + 1, sb, out)
                        i = close + 2
                    }
                }

                c == '!' && i + 1 < to && s[i + 1] == '[' -> {
                    val consumed = renderLink(s, i + 1, to, style, depth, sb, out, image = true)
                    if (consumed > 0) i = consumed else { sb.append(c); i++ }
                }

                c == '[' -> {
                    val consumed = renderLink(s, i, to, style, depth, sb, out, image = false)
                    if (consumed > 0) i = consumed else { sb.append(c); i++ }
                }

                c == '<' -> {
                    val gt = s.indexOf('>', i + 1)
                    val inner = if (gt in 0 until to) s.substring(i + 1, gt) else ""
                    if (gt > 0 && (inner.startsWith("http://") || inner.startsWith("https://") ||
                            (inner.contains('@') && !inner.contains(' ')))
                    ) {
                        val start = sb.length
                        sb.append(inner)
                        out.add(InlineSpan(start, sb.length, style, inner))
                        i = gt + 1
                    } else {
                        sb.append(c); i++
                    }
                }

                (c == 'h' || c == 'w') && link == null && isBareUrlStart(s, i, to) -> {
                    var end = i
                    while (end < to && !s[end].isWhitespace()) end++
                    // don't swallow trailing punctuation
                    while (end > i && s[end - 1] in ".,;:!?)\u201d\"'") end--
                    val raw = s.substring(i, end)
                    val start = sb.length
                    sb.append(raw)
                    out.add(InlineSpan(start, sb.length, style, if (raw.startsWith("w")) "https://$raw" else raw))
                    i = end
                }

                else -> {
                    sb.append(c); i++
                }
            }
        }
        if (sb.length > segStart && (style != 0 || link != null)) {
            out.add(InlineSpan(segStart, sb.length, style, link))
        }
    }

    /** Returns the index just after the link, or -1 when this isn't a link. */
    private fun renderLink(
        s: String,
        open: Int,
        to: Int,
        style: Int,
        depth: Int,
        sb: StringBuilder,
        out: MutableList<InlineSpan>,
        image: Boolean,
    ): Int {
        val close = matchBracket(s, open, to) 
        if (close < 0 || close + 1 >= to || s[close + 1] != '(') return -1
        val paren = matchParen(s, close + 1, to)
        if (paren < 0) return -1
        var url = s.substring(close + 2, paren).trim()
        val sp = url.indexOf(' ')
        if (sp > 0) url = url.substring(0, sp)
        if (url.startsWith("<") && url.endsWith(">")) url = url.substring(1, url.length - 1)
        if (image) {
            val start = sb.length
            val alt = s.substring(open + 1, close)
            sb.append("\uD83D\uDDBC ").append(if (alt.isEmpty()) "image" else alt)
            out.add(InlineSpan(start, sb.length, style or SPAN_ITALIC, url))
        } else {
            render(s, open + 1, close, style, url, depth + 1, sb, out)
        }
        return paren + 1
    }

    private fun isBareUrlStart(s: String, i: Int, to: Int): Boolean {
        if (i > 0 && (isWordChar(s[i - 1]) || s[i - 1] == '(' || s[i - 1] == '/')) return false
        return s.startsWith("http://", i) || s.startsWith("https://", i) || s.startsWith("www.", i)
    }

    private fun isWordChar(c: Char) = c.isLetterOrDigit() || c == '_'

    private fun isPunct(c: Char) = c in "\\`*_{}[]()#+-.!|~<>\""

    /** Index of a run of exactly >= n [ch] characters at or after [from]. */
    private fun findRun(s: String, from: Int, to: Int, ch: Char, n: Int): Int {
        var i = from
        while (i < to) {
            if (s[i] == '\\') { i += 2; continue }
            if (s[i] == ch) {
                var k = 0
                while (i + k < to && s[i + k] == ch) k++
                if (k >= n) return i
                i += k
            } else i++
        }
        return -1
    }

    private fun matchBracket(s: String, open: Int, to: Int): Int {
        var level = 0
        var i = open
        while (i < to) {
            when {
                s[i] == '\\' -> i++
                s[i] == '[' -> level++
                s[i] == ']' -> { level--; if (level == 0) return i }
            }
            i++
        }
        return -1
    }

    private fun matchParen(s: String, open: Int, to: Int): Int {
        var level = 0
        var i = open
        while (i < to) {
            when {
                s[i] == '\\' -> i++
                s[i] == '(' -> level++
                s[i] == ')' -> { level--; if (level == 0) return i }
            }
            i++
        }
        return -1
    }
}
