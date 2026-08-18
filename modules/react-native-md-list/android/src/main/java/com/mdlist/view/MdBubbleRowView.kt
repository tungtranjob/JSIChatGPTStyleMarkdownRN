package com.mdlist.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import com.mdlist.md.BubbleRowLayout
import com.mdlist.md.MdLinkSpan
import com.mdlist.md.MdTheme

/** Right aligned user turn, drawn as one rounded bubble. */
class MdBubbleRowView(context: Context, private val theme: MdTheme) : View(context) {

    private var row: BubbleRowLayout? = null
    private var callbacks: MdRowCallbacks? = null
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.bubbleBg }
    private val rect = RectF()

    fun bind(layout: BubbleRowLayout, cb: MdRowCallbacks) {
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
        rect.set(r.bubbleLeft, r.bubbleTop, r.bubbleLeft + r.bubbleWidth, r.bubbleTop + r.bubbleHeight)
        val radius = theme.dp(20f)
        canvas.drawRoundRect(rect, radius, radius, bgPaint)
        canvas.save()
        canvas.translate(r.bubbleLeft + r.pad, r.bubbleTop + r.pad)
        r.layout.draw(canvas)
        canvas.restore()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val r = row ?: return false
        if (event.actionMasked == MotionEvent.ACTION_UP) {
            val lx = event.x - r.bubbleLeft - r.pad
            val ly = event.y - r.bubbleTop - r.pad
            if (ly in 0f..r.layout.height.toFloat()) {
                val line = r.layout.getLineForVertical(ly.toInt())
                val offset = r.layout.getOffsetForHorizontal(line, lx)
                (r.text as? android.text.Spanned)
                    ?.getSpans(offset, offset, MdLinkSpan::class.java)
                    ?.firstOrNull()?.let { callbacks?.onLinkPress(it.url) }
            }
        }
        return true
    }
}
