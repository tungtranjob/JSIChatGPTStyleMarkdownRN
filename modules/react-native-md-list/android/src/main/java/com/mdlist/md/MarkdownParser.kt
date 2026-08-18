package com.mdlist.md

/**
 * Block level markdown parser (CommonMark/GFM subset that LLM answers actually use):
 * headings, paragraphs, nested lists, task lists, block quotes, fenced code with a
 * language tag, tables with alignment, thematic breaks.
 *
 * Runs entirely off the main thread and is pure/stateless, so results are safely
 * cacheable per (messageId, content hash).
 */
object MarkdownParser {

    private val HEADING = Regex("^(#{1,6})\\s+(.*?)\\s*#*$")
    private val LIST_ITEM = Regex("^(\\s*)([*+-]|\\d{1,9}[.)])\\s+(.*)$")
    private val FENCE = Regex("^(\\s*)(```+|~~~+)\\s*([^`]*)$")

    fun parse(messageId: String, role: String, src: String, streaming: Boolean): List<MdRow> {
        val isUser = role == "user"
        val out = ArrayList<MdRow>(16)
        val ctx = Ctx(messageId, isUser, streaming, out)

        if (isUser) {
            // A user turn is a bubble: short, always one row, never split.
            out.add(
                MdRow(
                    id = "$messageId:0",
                    messageId = messageId,
                    type = RowType.BUBBLE,
                    isUser = true,
                    inline = InlineParser.parse(src.trim()),
                    isFirstInMessage = true,
                    isLastInMessage = true,
                    streaming = streaming,
                )
            )
            return out
        }

        parseBlocks(src.replace("\r\n", "\n").split('\n'), 0, ctx)

        if (out.isEmpty()) return out
        return out.mapIndexed { index, row ->
            if (index == 0 || index == out.size - 1) {
                row.copyFlags(first = index == 0, last = index == out.size - 1)
            } else row
        }
    }

    private class Ctx(
        val messageId: String,
        val isUser: Boolean,
        val streaming: Boolean,
        val out: MutableList<MdRow>,
    ) {
        var seq = 0
        fun nextId() = "$messageId:${seq++}"
    }

    private fun MdRow.copyFlags(first: Boolean, last: Boolean) = MdRow(
        id, messageId, type, isUser, inline, headingLevel, listMarker, listDepth, quoteDepth,
        checked, code, language, table, first, last, streaming,
    )

    private fun parseBlocks(lines: List<String>, quoteDepth: Int, ctx: Ctx) {
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            val trimmed = line.trim()

            if (trimmed.isEmpty()) { i++; continue }

            // ---- fenced code -------------------------------------------------
            val fence = FENCE.matchEntire(line)
            if (fence != null && fence.groupValues[2].length >= 3) {
                val marker = fence.groupValues[2]
                val lang = fence.groupValues[3].trim().substringBefore(' ')
                val body = StringBuilder()
                var j = i + 1
                var closed = false
                while (j < lines.size) {
                    val l = lines[j]
                    val t = l.trimStart()
                    if (t.startsWith(marker.substring(0, 3)) && t.trimEnd().all { it == marker[0] }) {
                        closed = true; j++; break
                    }
                    if (body.isNotEmpty()) body.append('\n')
                    body.append(l)
                    j++
                }
                ctx.out.add(
                    MdRow(
                        id = ctx.nextId(), messageId = ctx.messageId, type = RowType.CODE,
                        isUser = false, code = body.toString(),
                        language = lang.ifEmpty { "text" },
                        quoteDepth = quoteDepth,
                        // while streaming, an unterminated fence is still shown as code
                        streaming = ctx.streaming && !closed,
                    )
                )
                i = j
                continue
            }

            // ---- heading -----------------------------------------------------
            val heading = HEADING.matchEntire(trimmed)
            if (heading != null) {
                ctx.out.add(
                    MdRow(
                        id = ctx.nextId(), messageId = ctx.messageId, type = RowType.HEADING,
                        isUser = false, inline = InlineParser.parse(heading.groupValues[2]),
                        headingLevel = heading.groupValues[1].length, quoteDepth = quoteDepth,
                        streaming = ctx.streaming,
                    )
                )
                i++
                continue
            }

            // ---- setext heading (=== / --- under a line of text) --------------
            if (i + 1 < lines.size && trimmed.isNotEmpty()) {
                val next = lines[i + 1].trim()
                if (next.length >= 2 && (next.all { it == '=' } || next.all { it == '-' }) &&
                    LIST_ITEM.matchEntire(line) == null && !isThematicBreak(next)
                ) {
                    ctx.out.add(
                        MdRow(
                            id = ctx.nextId(), messageId = ctx.messageId, type = RowType.HEADING,
                            isUser = false, inline = InlineParser.parse(trimmed),
                            headingLevel = if (next[0] == '=') 1 else 2, quoteDepth = quoteDepth,
                            streaming = ctx.streaming,
                        )
                    )
                    i += 2
                    continue
                }
            }

            // ---- thematic break ----------------------------------------------
            if (isThematicBreak(trimmed)) {
                ctx.out.add(
                    MdRow(
                        id = ctx.nextId(), messageId = ctx.messageId, type = RowType.DIVIDER,
                        isUser = false, quoteDepth = quoteDepth, streaming = ctx.streaming,
                    )
                )
                i++
                continue
            }

            // ---- block quote ---------------------------------------------------
            if (trimmed.startsWith(">")) {
                val inner = ArrayList<String>()
                var j = i
                while (j < lines.size) {
                    val t = lines[j].trimStart()
                    if (t.startsWith(">")) {
                        inner.add(t.removePrefix(">").removePrefix(" "))
                    } else if (t.isNotEmpty() && inner.isNotEmpty()) {
                        inner.add(t) // lazy continuation
                    } else break
                    j++
                }
                parseBlocks(inner, quoteDepth + 1, ctx)
                i = j
                continue
            }

            // ---- table ----------------------------------------------------------
            if (line.contains('|') && i + 1 < lines.size && isTableDelimiter(lines[i + 1])) {
                val header = splitRow(line)
                val aligns = parseAligns(lines[i + 1], header.size)
                val rows = ArrayList<List<InlineText>>()
                var j = i + 2
                while (j < lines.size && lines[j].contains('|') && lines[j].isNotBlank()) {
                    val cells = splitRow(lines[j])
                    rows.add(List(header.size) { c -> InlineParser.parse(cells.getOrElse(c) { "" }) })
                    j++
                }
                ctx.out.add(
                    MdRow(
                        id = ctx.nextId(), messageId = ctx.messageId, type = RowType.TABLE,
                        isUser = false, quoteDepth = quoteDepth,
                        table = MdTable(header.map { InlineParser.parse(it) }, rows, aligns),
                        streaming = ctx.streaming,
                    )
                )
                i = j
                continue
            }

            // ---- list run --------------------------------------------------------
            if (LIST_ITEM.matchEntire(line) != null) {
                i = parseListRun(lines, i, quoteDepth, ctx)
                continue
            }

            // ---- paragraph -------------------------------------------------------
            val para = StringBuilder()
            var j = i
            while (j < lines.size) {
                val l = lines[j]
                val t = l.trim()
                if (t.isEmpty()) break
                if (j > i && (startsNewBlock(l, lines, j))) break
                if (para.isNotEmpty()) para.append('\n')
                para.append(t)
                j++
            }
            ctx.out.add(
                MdRow(
                    id = ctx.nextId(), messageId = ctx.messageId, type = RowType.PARAGRAPH,
                    isUser = false, inline = InlineParser.parse(para.toString()),
                    quoteDepth = quoteDepth, streaming = ctx.streaming,
                )
            )
            i = j
        }
    }

    private fun startsNewBlock(line: String, lines: List<String>, index: Int): Boolean {
        val t = line.trim()
        if (t.startsWith(">")) return true
        if (isThematicBreak(t)) return true
        if (HEADING.matchEntire(t) != null) return true
        if (FENCE.matchEntire(line) != null) return true
        if (LIST_ITEM.matchEntire(line) != null) return true
        if (line.contains('|') && index + 1 < lines.size && isTableDelimiter(lines[index + 1])) return true
        return false
    }

    /**
     * Parses one contiguous list, tracking indent on a stack so both 2 space and
     * 4 space nesting collapse to the same visual depth.
     */
    private fun parseListRun(lines: List<String>, start: Int, quoteDepth: Int, ctx: Ctx): Int {
        val indentStack = ArrayList<Int>()
        val counters = ArrayList<Int>()
        var i = start
        var lastIndent = 0

        while (i < lines.size) {
            val line = lines[i]
            if (line.isBlank()) {
                // a blank line only ends the list if the next line is not a deeper continuation
                val next = lines.getOrNull(i + 1)
                if (next == null || next.isBlank()) break
                val nextIndent = next.indexOfFirst { !it.isWhitespace() }.let { if (it < 0) 0 else it }
                if (LIST_ITEM.matchEntire(next) == null && nextIndent <= lastIndent) break
                i++
                continue
            }
            val m = LIST_ITEM.matchEntire(line)
            if (m == null) {
                val indent = line.indexOfFirst { !it.isWhitespace() }
                // fenced code nested inside a list item
                if (indent > lastIndent && FENCE.matchEntire(line.trimStart().let { " ".repeat(indent) + it }) != null) break
                if (indent > lastIndent && ctx.out.isNotEmpty()) {
                    // lazy continuation text of the previous item
                    val prev = ctx.out.removeAt(ctx.out.size - 1)
                    val merged = prev.inline.text + "\n" + line.trim()
                    ctx.out.add(
                        MdRow(
                            id = prev.id, messageId = prev.messageId, type = prev.type, isUser = false,
                            inline = InlineParser.parse(merged), listMarker = prev.listMarker,
                            listDepth = prev.listDepth, quoteDepth = prev.quoteDepth,
                            checked = prev.checked, streaming = ctx.streaming,
                        )
                    )
                    i++
                    continue
                }
                break
            }

            val indent = m.groupValues[1].length
            val rawMarker = m.groupValues[2]
            var content = m.groupValues[3]

            while (indentStack.isNotEmpty() && indent < indentStack.last()) {
                indentStack.removeAt(indentStack.size - 1)
                counters.removeAt(counters.size - 1)
            }
            if (indentStack.isEmpty() || indent > indentStack.last()) {
                indentStack.add(indent)
                counters.add(0)
            }
            val depth = indentStack.size - 1
            val ordered = rawMarker[0].isDigit()
            counters[depth] = counters[depth] + 1

            var checked = -1
            if (content.length >= 3 && content[0] == '[' && content[2] == ']') {
                when (content[1]) {
                    ' ' -> checked = 0
                    'x', 'X' -> checked = 1
                }
                if (checked >= 0) content = content.substring(3).trimStart()
            }

            val marker = if (ordered) {
                "${rawMarker.dropLast(1).toIntOrNull() ?: counters[depth]}."
            } else {
                bullet(depth)
            }

            ctx.out.add(
                MdRow(
                    id = ctx.nextId(), messageId = ctx.messageId, type = RowType.LIST_ITEM,
                    isUser = false, inline = InlineParser.parse(content),
                    listMarker = marker, listDepth = depth, quoteDepth = quoteDepth,
                    checked = checked, streaming = ctx.streaming,
                )
            )
            lastIndent = indent
            i++
        }
        return if (i == start) start + 1 else i
    }

    private fun bullet(depth: Int) = when (depth % 3) {
        0 -> "•"
        1 -> "◦"
        else -> "▪"
    }

    private fun isThematicBreak(t: String): Boolean {
        if (t.length < 3) return false
        val c = t[0]
        if (c != '-' && c != '*' && c != '_') return false
        return t.all { it == c || it == ' ' } && t.count { it == c } >= 3
    }

    private fun isTableDelimiter(line: String): Boolean {
        val t = line.trim()
        if (!t.contains('-') || !t.contains('|')) return false
        return t.all { it == '|' || it == '-' || it == ':' || it == ' ' }
    }

    private fun parseAligns(line: String, count: Int): IntArray {
        val parts = splitRow(line)
        return IntArray(count) { idx ->
            val p = parts.getOrElse(idx) { "" }.trim()
            when {
                p.startsWith(":") && p.endsWith(":") -> ALIGN_CENTER
                p.endsWith(":") -> ALIGN_RIGHT
                else -> ALIGN_LEFT
            }
        }
    }

    /** Splits a table row on unescaped pipes that are not inside inline code. */
    private fun splitRow(line: String): List<String> {
        val cells = ArrayList<String>()
        val cur = StringBuilder()
        var inCode = false
        var i = 0
        val s = line.trim().removePrefix("|").removeSuffix("|")
        while (i < s.length) {
            val c = s[i]
            when {
                c == '\\' && i + 1 < s.length -> { cur.append(s[i + 1]); i += 2; continue }
                c == '`' -> { inCode = !inCode; cur.append(c) }
                c == '|' && !inCode -> { cells.add(cur.toString().trim()); cur.setLength(0) }
                else -> cur.append(c)
            }
            i++
        }
        cells.add(cur.toString().trim())
        return cells
    }
}
