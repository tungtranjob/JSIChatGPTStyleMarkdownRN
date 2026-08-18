package com.mdlist.md

import android.graphics.Color
import android.graphics.Typeface
import android.text.TextPaint

/**
 * All colors, fonts and metrics for one (colorScheme, fontSize, density) combo.
 * Paints are created once and never mutated afterwards, which is what makes it
 * safe to build StaticLayouts on a worker thread and draw them on the UI thread.
 */
class MdTheme(
    @JvmField val dark: Boolean,
    @JvmField val baseSp: Float,
    @JvmField val density: Float,
    @JvmField val fontScale: Float,
) {
    fun dp(v: Float): Float = v * density

    @JvmField val textPrimary = if (dark) 0xFFECECEC.toInt() else 0xFF0D0D0D.toInt()
    @JvmField val textSecondary = if (dark) 0xFF9B9B9B.toInt() else 0xFF6E6E80.toInt()
    @JvmField val link = if (dark) 0xFF7AB7FF.toInt() else 0xFF1A73E8.toInt()
    @JvmField val divider = if (dark) 0xFF2F2F2F.toInt() else 0xFFE5E5E5.toInt()

    @JvmField val inlineCodeBg = if (dark) 0xFF2B2B2B.toInt() else 0xFFF1F1F1.toInt()
    @JvmField val inlineCodeFg = if (dark) 0xFFF0A2A2.toInt() else 0xFFC7254E.toInt()

    @JvmField val codeBg = if (dark) 0xFF0F1115.toInt() else 0xFF1B1F27.toInt()
    @JvmField val codeHeaderBg = if (dark) 0xFF17191F.toInt() else 0xFF262B35.toInt()
    @JvmField val codeFg = 0xFFE6EDF3.toInt()
    @JvmField val codeHeaderFg = 0xFFB9C0CC.toInt()

    @JvmField val quoteBar = if (dark) 0xFF4A4A4A.toInt() else 0xFFD3D3D3.toInt()
    @JvmField val quoteFg = if (dark) 0xFFC0C0C0.toInt() else 0xFF5A5A66.toInt()

    @JvmField val bubbleBg = if (dark) 0xFF303030.toInt() else 0xFFF0F0F0.toInt()
    @JvmField val bubbleFg = textPrimary

    @JvmField val tableBorder = if (dark) 0xFF3A3A3A.toInt() else 0xFFDDDDDD.toInt()
    @JvmField val tableHeaderBg = if (dark) 0xFF232323.toInt() else 0xFFF7F7F8.toInt()

    @JvmField val background = if (dark) 0xFF212121.toInt() else Color.WHITE

    // --- syntax palette (One Dark-ish, readable on both code backgrounds) ---
    @JvmField val synKeyword = 0xFFC678DD.toInt()
    @JvmField val synString = 0xFF98C379.toInt()
    @JvmField val synNumber = 0xFFD19A66.toInt()
    @JvmField val synComment = 0xFF7F848E.toInt()
    @JvmField val synType = 0xFFE5C07B.toInt()
    @JvmField val synFunc = 0xFF61AFEF.toInt()

    private val mono: Typeface = Typeface.MONOSPACE

    private fun paint(sizeSp: Float, color: Int, tf: Typeface?): TextPaint {
        // Computed *outside* the apply block on purpose: TextPaint declares its own
        // public `density` field (1.0f), which would shadow the screen density here
        // and silently render every glyph at 1/3 size on an xhdpi screen.
        val sizePx = sizeSp * this.density * this.fontScale
        return TextPaint(TextPaint.ANTI_ALIAS_FLAG or TextPaint.SUBPIXEL_TEXT_FLAG).apply {
            textSize = sizePx
            this.color = color
            if (tf != null) typeface = tf
        }
    }

    @JvmField val body: TextPaint = paint(baseSp, textPrimary, null)
    @JvmField val bubble: TextPaint = paint(baseSp, bubbleFg, null)
    @JvmField val quote: TextPaint = paint(baseSp, quoteFg, null)
    @JvmField val code: TextPaint = paint(baseSp * 0.84f, codeFg, mono)
    @JvmField val codeHeader: TextPaint = paint(baseSp * 0.72f, codeHeaderFg, null)
    @JvmField val tableCell: TextPaint = paint(baseSp * 0.9f, textPrimary, null)
    @JvmField val tableHead: TextPaint = paint(baseSp * 0.9f, textPrimary, Typeface.DEFAULT_BOLD)

    private val headingScale = floatArrayOf(1.62f, 1.38f, 1.2f, 1.08f, 1.0f, 0.94f)
    @JvmField val headings: Array<TextPaint> = Array(6) { i ->
        paint(baseSp * headingScale[i], textPrimary, Typeface.DEFAULT_BOLD)
    }

    fun headingPaint(level: Int): TextPaint = headings[(level - 1).coerceIn(0, 5)]

    /** Identity used as part of every layout cache key. */
    @JvmField val key: String = "${if (dark) "d" else "l"}-$baseSp-$density-$fontScale"
}
