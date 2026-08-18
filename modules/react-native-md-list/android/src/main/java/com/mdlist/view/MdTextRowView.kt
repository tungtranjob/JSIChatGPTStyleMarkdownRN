package com.mdlist.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import com.mdlist.md.MdLinkSpan
import com.mdlist.md.MdTheme
import com.mdlist.md.TextRowLayout

/**
 * Paragraph / heading / list item / quoted text.
 *
 * Draws a pre-built StaticLayout straight onto the canvas. No TextView, no
 * BoringLayout re-measure, no span re-resolution at bind time: onMeasure is a
 * constant time call and onDraw is a single layout.draw().
 */
class MdTextRowView(context: Context, private val theme: MdTheme) : View(context) {

    private var row: TextRowLayout? = null
    private var callbacks: MdRowCallbacks? = null

    private val quotePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.quoteBar }
    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = theme.dp(1.5f)
        color = theme.textSecondary
    }
    private val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = theme.dp(1.8f)
        strokeCap = Paint.Cap.ROUND
        color = theme.link
    }
    private val rect = RectF()
    private var downX = 0f
    private var downY = 0f
    private var longPressed = false

    fun bind(layout: TextRowLayout, cb: MdRowCallbacks) {
        // a recycled row must not inherit the previous row's pending long press
        removeCallbacks(longPressRunnable)
        longPressed = false
        row = layout
        callbacks = cb
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), row?.height ?: 0)
    }

    override fun onDraw(canvas: Canvas) {
        val r = row ?: return

        if (r.quoteDepth > 0) {
            val barW = theme.dp(3f)
            for (d in 0 until r.quoteDepth) {
                val x = r.quoteX + d * theme.dp(14f)
                rect.set(x, 0f, x + barW, height.toFloat())
                canvas.drawRoundRect(rect, barW / 2f, barW / 2f, quotePaint)
            }
        }

        r.marker?.let { m ->
            canvas.save()
            canvas.translate(r.markerX, r.textY)
            m.draw(canvas)
            canvas.restore()
        }

        if (r.checked >= 0) {
            val size = theme.dp(15f)
            val top = r.textY + theme.dp(3f)
            rect.set(r.markerX, top, r.markerX + size, top + size)
            canvas.drawRoundRect(rect, theme.dp(4f), theme.dp(4f), boxPaint)
            if (r.checked == 1) {
                val p = theme.dp(3.5f)
                canvas.drawLine(rect.left + p, rect.centerY(), rect.centerX() - p * 0.2f, rect.bottom - p, tickPaint)
                canvas.drawLine(rect.centerX() - p * 0.2f, rect.bottom - p, rect.right - p * 0.7f, rect.top + p, tickPaint)
            }
        }

        canvas.save()
        canvas.translate(r.textX, r.textY)
        r.layout.draw(canvas)
        canvas.restore()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val r = row ?: return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x; downY = event.y; longPressed = false
                postDelayed(longPressRunnable, LONG_PRESS_MS)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (Math.abs(event.x - downX) > touchSlop || Math.abs(event.y - downY) > touchSlop) {
                    removeCallbacks(longPressRunnable)
                }
            }
            MotionEvent.ACTION_UP -> {
                removeCallbacks(longPressRunnable)
                if (!longPressed) linkAt(r, event.x, event.y)?.let { callbacks?.onLinkPress(it) }
                return true
            }
            MotionEvent.ACTION_CANCEL -> removeCallbacks(longPressRunnable)
        }
        return true
    }

    private val longPressRunnable = Runnable {
        longPressed = true
        row?.let { callbacks?.onCopyText(it.text) }
        performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
    }

    private val touchSlop = android.view.ViewConfiguration.get(context).scaledTouchSlop

    private fun linkAt(r: TextRowLayout, x: Float, y: Float): String? {
        val lx = x - r.textX
        val ly = y - r.textY
        if (ly < 0 || ly > r.layout.height) return null
        val line = r.layout.getLineForVertical(ly.toInt())
        if (lx < r.layout.getLineLeft(line) || lx > r.layout.getLineRight(line)) return null
        val offset = r.layout.getOffsetForHorizontal(line, lx)
        val spans = (r.text as? android.text.Spanned)
            ?.getSpans(offset, offset, MdLinkSpan::class.java) ?: return null
        return spans.firstOrNull()?.url
    }

    companion object {
        private const val LONG_PRESS_MS = 400L
    }
}
