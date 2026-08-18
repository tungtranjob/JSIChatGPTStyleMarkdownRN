package com.mdlist.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import com.mdlist.md.CodeRowLayout
import com.mdlist.md.MdTheme

/**
 * Fenced code block: sticky header (language + copy) over a horizontally
 * scrollable, syntax highlighted body. Code never wraps, matching ChatGPT/Gemini.
 */
class MdCodeRowView(context: Context, private val theme: MdTheme) : ViewGroup(context) {

    private var row: CodeRowLayout? = null
    private var callbacks: MdRowCallbacks? = null
    private var copiedUntil = 0L

    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.codeBg }
    private val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.codeHeaderBg }
    private val rect = RectF()
    private val path = Path()

    private val header = HeaderView(context)
    private val scroller = HorizontalScrollView(context).apply {
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        clipToPadding = false
    }
    private val body = BodyView(context)

    init {
        setWillNotDraw(false)
        scroller.addView(body, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        addView(header)
        addView(scroller)
        header.setOnClickListener {
            row?.let {
                callbacks?.onCopyCode(it.code, it.language)
                copiedUntil = System.currentTimeMillis() + 1400
                header.invalidate()
                postDelayed({ header.invalidate() }, 1500)
            }
        }
    }

    fun bind(layout: CodeRowLayout, cb: MdRowCallbacks) {
        row = layout
        callbacks = cb
        scroller.scrollX = 0
        scroller.setPadding(layout.padding, layout.padding, layout.padding, layout.padding)
        requestLayout()
        invalidate()
        header.invalidate()
        body.invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val r = row
        if (r == null) {
            setMeasuredDimension(w, 0); return
        }
        header.measure(
            MeasureSpec.makeMeasureSpec(r.boxWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(r.headerHeight, MeasureSpec.EXACTLY),
        )
        val bodyH = r.layout.height + r.padding * 2
        scroller.measure(
            MeasureSpec.makeMeasureSpec(r.boxWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(bodyH, MeasureSpec.EXACTLY),
        )
        setMeasuredDimension(w, r.height)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, rr: Int, b: Int) {
        val r = row ?: return
        val top = r.topMargin
        header.layout(r.left, top, r.left + r.boxWidth, top + r.headerHeight)
        val bodyTop = top + r.headerHeight
        scroller.layout(r.left, bodyTop, r.left + r.boxWidth, bodyTop + scroller.measuredHeight)
    }

    override fun onDraw(canvas: Canvas) {
        val r = row ?: return
        val top = r.topMargin.toFloat()
        val boxH = (r.headerHeight + r.layout.height + r.padding * 2).toFloat()
        val radius = theme.dp(12f)
        rect.set(r.left.toFloat(), top, (r.left + r.boxWidth).toFloat(), top + boxH)
        canvas.drawRoundRect(rect, radius, radius, boxPaint)

        // header: rounded top corners only
        path.reset()
        rect.set(r.left.toFloat(), top, (r.left + r.boxWidth).toFloat(), top + r.headerHeight)
        path.addRoundRect(
            rect,
            floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f),
            Path.Direction.CW,
        )
        canvas.drawPath(path, headerPaint)
    }

    private inner class HeaderView(context: Context) : View(context) {
        private val paint = theme.codeHeader

        override fun onDraw(canvas: Canvas) {
            val r = row ?: return
            val fm = paint.fontMetrics
            val baseline = height / 2f - (fm.ascent + fm.descent) / 2f
            val pad = theme.dp(12f)
            canvas.drawText(r.language, pad, baseline, paint)
            val label = if (System.currentTimeMillis() < copiedUntil) "Copied" else "Copy"
            val w = paint.measureText(label)
            canvas.drawText(label, width - pad - w, baseline, paint)
        }
    }

    private inner class BodyView(context: Context) : View(context) {
        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val r = row
            if (r == null) { setMeasuredDimension(0, 0); return }
            setMeasuredDimension(r.contentWidth, r.layout.height)
        }

        override fun onDraw(canvas: Canvas) {
            row?.layout?.draw(canvas)
        }
    }
}
