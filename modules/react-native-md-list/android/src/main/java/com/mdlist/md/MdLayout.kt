package com.mdlist.md

import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.graphics.Typeface
import android.util.LruCache
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Marker span carrying the URL; hit tested manually so we avoid ClickableSpan/TextView. */
class MdLinkSpan(@JvmField val url: String)

sealed class RowLayout {
    abstract val height: Int
}

class TextRowLayout(
    @JvmField val text: Spanned,
    @JvmField val layout: StaticLayout,
    @JvmField val textX: Float,
    @JvmField val textY: Float,
    @JvmField val marker: StaticLayout?,
    @JvmField val markerX: Float,
    @JvmField val quoteDepth: Int,
    @JvmField val quoteX: Float,
    @JvmField val checked: Int,
    override val height: Int,
) : RowLayout()

class CodeRowLayout(
    @JvmField val language: String,
    @JvmField val code: String,
    @JvmField val text: Spanned,
    @JvmField val layout: StaticLayout,
    @JvmField val headerHeight: Int,
    @JvmField val contentWidth: Int,
    @JvmField val padding: Int,
    @JvmField val left: Int,
    @JvmField val boxWidth: Int,
    @JvmField val topMargin: Int,
    override val height: Int,
) : RowLayout()

class TableRowLayout(
    @JvmField val cells: Array<Array<StaticLayout>>,
    @JvmField val colW: IntArray,
    @JvmField val rowH: IntArray,
    @JvmField val contentWidth: Int,
    @JvmField val cellPad: Int,
    @JvmField val left: Int,
    @JvmField val topMargin: Int,
    override val height: Int,
) : RowLayout()

class DividerRowLayout(@JvmField val inset: Float, override val height: Int) : RowLayout()

class BubbleRowLayout(
    @JvmField val text: Spanned,
    @JvmField val layout: StaticLayout,
    @JvmField val bubbleLeft: Float,
    @JvmField val bubbleTop: Float,
    @JvmField val bubbleWidth: Float,
    @JvmField val bubbleHeight: Float,
    @JvmField val pad: Float,
    override val height: Int,
) : RowLayout()

/**
 * Builds and caches the text layout of every row.
 *
 * Text measurement is *the* cost in a markdown list. Doing it here means:
 *  - it happens on a worker thread (StaticLayout is safe to build off the UI thread),
 *  - it happens once per (row content, width) and is then reused by every bind,
 *  - onMeasure of a recycled row is O(1): the height is already known.
 */
class MdLayoutEngine(@JvmField val theme: MdTheme) {

    private val cache = object : LruCache<String, RowLayout>(512) {}

    @JvmField val hPad: Float = theme.dp(16f)
    private val quoteInset = theme.dp(14f)
    private val listIndent = theme.dp(18f)
    private val markerGutter = theme.dp(20f)

    fun clear() = cache.evictAll()

    fun cached(row: MdRow, width: Int): RowLayout? = cache.get(key(row, width))

    fun layoutFor(row: MdRow, width: Int): RowLayout {
        val k = key(row, width)
        cache.get(k)?.let { return it }
        val built = build(row, width)
        cache.put(k, built)
        return built
    }

    private fun key(row: MdRow, width: Int) = "${row.layoutKey}|$width|${theme.key}"

    private fun build(row: MdRow, width: Int): RowLayout = when (row.type) {
        RowType.BUBBLE -> buildBubble(row, width)
        RowType.CODE -> buildCode(row, width)
        RowType.TABLE -> buildTable(row, width)
        RowType.DIVIDER -> DividerRowLayout(hPad, (theme.dp(25f)).toInt())
        else -> buildText(row, width)
    }

    // ------------------------------------------------------------------ text

    private fun buildText(row: MdRow, width: Int): RowLayout {
        val isQuote = row.quoteDepth > 0
        val paint: TextPaint = when {
            row.type == RowType.HEADING -> theme.headingPaint(row.headingLevel)
            isQuote -> theme.quote
            else -> theme.body
        }

        val quoteX = hPad
        val quotePad = row.quoteDepth * quoteInset
        var left = hPad + quotePad
        var marker: StaticLayout? = null
        var markerX = 0f

        if (row.type == RowType.LIST_ITEM) {
            left += row.listDepth * listIndent
            markerX = left
            if (row.checked < 0) {
                val m = SpannableStringBuilder(row.listMarker ?: "•")
                marker = staticLayout(m, markerPaint(paint), ceil(markerGutter).toInt(), Layout.Alignment.ALIGN_NORMAL)
            }
            left += markerGutter
        }

        val avail = max(1, (width - left - hPad).toInt())
        val spanned = spannable(row.inline, paint)
        val layout = staticLayout(spanned, paint, avail, Layout.Alignment.ALIGN_NORMAL)

        val topPad = topPadFor(row)
        val bottomPad = bottomPadFor(row)
        val height = (topPad + layout.height + bottomPad).toInt()

        return TextRowLayout(
            text = spanned,
            layout = layout,
            textX = left,
            textY = topPad,
            marker = marker,
            markerX = markerX,
            quoteDepth = row.quoteDepth,
            quoteX = quoteX,
            checked = row.checked,
            height = height,
        )
    }

    private fun markerPaint(base: TextPaint) = base

    private fun topPadFor(row: MdRow): Float {
        val extra = if (row.isFirstInMessage) theme.dp(10f) else 0f
        return extra + when (row.type) {
            RowType.HEADING -> when (row.headingLevel) {
                1 -> theme.dp(18f); 2 -> theme.dp(16f); 3 -> theme.dp(14f); else -> theme.dp(12f)
            }
            RowType.LIST_ITEM -> theme.dp(3f)
            else -> theme.dp(6f)
        }
    }

    private fun bottomPadFor(row: MdRow): Float {
        val extra = if (row.isLastInMessage) theme.dp(20f) else 0f
        return extra + when (row.type) {
            RowType.HEADING -> theme.dp(6f)
            RowType.LIST_ITEM -> theme.dp(3f)
            else -> theme.dp(6f)
        }
    }

    // ---------------------------------------------------------------- bubble

    private fun buildBubble(row: MdRow, width: Int): RowLayout {
        val pad = theme.dp(13f)
        val maxBubble = width * 0.84f
        val maxText = max(1f, maxBubble - pad * 2)
        val spanned = spannable(row.inline, theme.bubble)
        val desired = measureMaxLineWidth(spanned, theme.bubble)
        val textW = max(1, min(desired, maxText).toInt())
        val layout = staticLayout(spanned, theme.bubble, textW, Layout.Alignment.ALIGN_NORMAL)
        val bubbleW = layout.let { l ->
            var w = 0f
            for (i in 0 until l.lineCount) w = max(w, l.getLineWidth(i))
            min(maxText, w) + pad * 2
        }
        val bubbleH = layout.height + pad * 2
        val top = theme.dp(if (row.isFirstInMessage) 14f else 4f)
        val bottom = theme.dp(10f)
        return BubbleRowLayout(
            text = spanned,
            layout = layout,
            bubbleLeft = width - hPad - bubbleW,
            bubbleTop = top,
            bubbleWidth = bubbleW,
            bubbleHeight = bubbleH,
            pad = pad,
            height = (top + bubbleH + bottom).toInt(),
        )
    }

    // ------------------------------------------------------------------ code

    private fun buildCode(row: MdRow, width: Int): RowLayout {
        val code = row.code ?: ""
        val pad = theme.dp(12f).toInt()
        val headerH = theme.dp(32f).toInt()
        val left = (hPad + row.quoteDepth * quoteInset).toInt()
        val boxWidth = width - left - hPad.toInt()

        val spanned = SpannableStringBuilder(code)
        for (t in CodeHighlighter.tokenize(code, row.language ?: "text")) {
            val color = when (t.kind) {
                CodeHighlighter.KIND_KEYWORD -> theme.synKeyword
                CodeHighlighter.KIND_STRING -> theme.synString
                CodeHighlighter.KIND_NUMBER -> theme.synNumber
                CodeHighlighter.KIND_COMMENT -> theme.synComment
                CodeHighlighter.KIND_TYPE -> theme.synType
                else -> theme.synFunc
            }
            if (t.end <= spanned.length && t.start < t.end) {
                spanned.setSpan(ForegroundColorSpan(color), t.start, t.end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }

        // No wrapping: code scrolls horizontally, exactly like ChatGPT / Gemini.
        val natural = ceil(measureMaxLineWidth(spanned, theme.code)).toInt() + 2
        val contentWidth = max(natural, boxWidth - pad * 2)
        val layout = staticLayout(spanned, theme.code, contentWidth, Layout.Alignment.ALIGN_NORMAL)

        val vMargin = theme.dp(8f).toInt() + if (row.isFirstInMessage) theme.dp(10f).toInt() else 0
        val bottomMargin = theme.dp(8f).toInt() + if (row.isLastInMessage) theme.dp(20f).toInt() else 0
        val height = vMargin + headerH + pad + layout.height + pad + bottomMargin

        return CodeRowLayout(
            language = row.language ?: "text",
            code = code,
            text = spanned,
            layout = layout,
            headerHeight = headerH,
            contentWidth = contentWidth,
            padding = pad,
            left = left,
            boxWidth = boxWidth,
            topMargin = vMargin,
            height = height,
        )
    }

    // ----------------------------------------------------------------- table

    private fun buildTable(row: MdRow, width: Int): RowLayout {
        val table = row.table!!
        val cols = table.header.size
        val cellPad = theme.dp(10f).toInt()
        val left = (hPad + row.quoteDepth * quoteInset).toInt()
        val avail = width - left - hPad.toInt()
        val maxCol = theme.dp(230f)

        val allRows = ArrayList<List<InlineText>>(table.rows.size + 1)
        allRows.add(table.header)
        allRows.addAll(table.rows)

        val spanned = Array(allRows.size) { r ->
            Array(cols) { c ->
                val paint = if (r == 0) theme.tableHead else theme.tableCell
                spannable(allRows[r].getOrElse(c) { InlineText.EMPTY }, paint)
            }
        }

        val colW = IntArray(cols)
        for (c in 0 until cols) {
            var w = 0f
            for (r in spanned.indices) {
                val paint = if (r == 0) theme.tableHead else theme.tableCell
                w = max(w, measureMaxLineWidth(spanned[r][c], paint))
            }
            colW[c] = ceil(min(w, maxCol)).toInt() + cellPad * 2
        }

        // If the natural table is narrower than the viewport, stretch it to fill.
        val natural = colW.sum()
        if (natural < avail && natural > 0) {
            var used = 0
            for (c in 0 until cols) {
                val add = if (c == cols - 1) avail - natural - used else (avail - natural) * colW[c] / natural
                colW[c] += add
                used += add
            }
        }

        val cells = Array(spanned.size) { r ->
            Array(cols) { c ->
                val paint = if (r == 0) theme.tableHead else theme.tableCell
                val align = when (table.aligns.getOrElse(c) { ALIGN_LEFT }) {
                    ALIGN_CENTER -> Layout.Alignment.ALIGN_CENTER
                    ALIGN_RIGHT -> Layout.Alignment.ALIGN_OPPOSITE
                    else -> Layout.Alignment.ALIGN_NORMAL
                }
                staticLayout(spanned[r][c], paint, max(1, colW[c] - cellPad * 2), align)
            }
        }

        val rowH = IntArray(cells.size) { r ->
            var h = 0
            for (c in 0 until cols) h = max(h, cells[r][c].height)
            h + cellPad * 2
        }

        val vMargin = theme.dp(8f).toInt()
        val bottomMargin = theme.dp(8f).toInt() + if (row.isLastInMessage) theme.dp(20f).toInt() else 0
        return TableRowLayout(
            cells = cells,
            colW = colW,
            rowH = rowH,
            contentWidth = colW.sum(),
            cellPad = cellPad,
            left = left,
            topMargin = vMargin,
            height = vMargin + rowH.sum() + bottomMargin,
        )
    }

    // ----------------------------------------------------------------- utils

    fun spannable(inline: InlineText, base: TextPaint): Spanned {
        val sb = SpannableStringBuilder(inline.text)
        val n = sb.length
        for (s in inline.spans) {
            val start = s.start.coerceIn(0, n)
            val end = s.end.coerceIn(start, n)
            if (start == end) continue
            val f = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            val bold = s.style and SPAN_BOLD != 0
            val italic = s.style and SPAN_ITALIC != 0
            if (bold && italic) sb.setSpan(StyleSpan(Typeface.BOLD_ITALIC), start, end, f)
            else if (bold) sb.setSpan(StyleSpan(Typeface.BOLD), start, end, f)
            else if (italic) sb.setSpan(StyleSpan(Typeface.ITALIC), start, end, f)
            if (s.style and SPAN_STRIKE != 0) sb.setSpan(StrikethroughSpan(), start, end, f)
            if (s.style and SPAN_CODE != 0) {
                sb.setSpan(TypefaceSpan("monospace"), start, end, f)
                sb.setSpan(RelativeSizeSpan(0.9f), start, end, f)
                sb.setSpan(BackgroundColorSpan(theme.inlineCodeBg), start, end, f)
                sb.setSpan(ForegroundColorSpan(theme.inlineCodeFg), start, end, f)
            }
            if (s.link != null) {
                sb.setSpan(ForegroundColorSpan(theme.link), start, end, f)
                sb.setSpan(MdLinkSpan(s.link), start, end, f)
            }
        }
        return sb
    }

    private fun measureMaxLineWidth(text: CharSequence, paint: TextPaint): Float {
        var maxW = 0f
        var start = 0
        val len = text.length
        while (start <= len) {
            var end = start
            while (end < len && text[end] != '\n') end++
            maxW = max(maxW, Layout.getDesiredWidth(text, start, end, paint))
            if (end >= len) break
            start = end + 1
        }
        return maxW
    }

    private fun staticLayout(
        text: CharSequence,
        paint: TextPaint,
        width: Int,
        align: Layout.Alignment,
    ): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, max(1, width))
            .setAlignment(align)
            .setLineSpacing(theme.dp(3f), 1.06f)
            .setIncludePad(false)
            // SIMPLE + no hyphenation is 3-6x faster than the default balanced
            // strategy and is what makes long answers cheap to lay out.
            .setBreakStrategy(Layout.BREAK_STRATEGY_SIMPLE)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
            .build()
}
