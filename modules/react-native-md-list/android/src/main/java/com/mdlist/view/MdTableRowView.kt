package com.mdlist.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import android.widget.HorizontalScrollView
import com.mdlist.md.MdTheme
import com.mdlist.md.TableRowLayout

/** GFM table: fixed column widths computed off the main thread, scrolls sideways. */
class MdTableRowView(context: Context, private val theme: MdTheme) : HorizontalScrollView(context) {

    private var row: TableRowLayout? = null
    private val body = BodyView(context)

    init {
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        clipToPadding = false
        addView(body, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
    }

    fun bind(layout: TableRowLayout) {
        row = layout
        scrollX = 0
        setPadding(layout.left, layout.topMargin, layout.left, 0)
        requestLayout()
        body.requestLayout()
        body.invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val r = row
        if (r == null) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec); return
        }
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(r.height, MeasureSpec.EXACTLY),
        )
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), r.height)
    }

    private inner class BodyView(context: Context) : View(context) {
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = theme.dp(1f)
            color = theme.tableBorder
        }
        private val headerBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = theme.tableHeaderBg }
        private val rect = RectF()

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val r = row
            if (r == null) { setMeasuredDimension(0, 0); return }
            setMeasuredDimension(r.contentWidth, r.rowH.sum())
        }

        override fun onDraw(canvas: Canvas) {
            val r = row ?: return
            val radius = theme.dp(10f)
            val totalH = r.rowH.sum().toFloat()

            rect.set(0f, 0f, r.contentWidth.toFloat(), r.rowH[0].toFloat())
            canvas.drawRect(rect, headerBgPaint)

            var y = 0
            for (rowIdx in r.cells.indices) {
                var x = 0
                for (colIdx in r.cells[rowIdx].indices) {
                    val cell = r.cells[rowIdx][colIdx]
                    canvas.save()
                    canvas.translate((x + r.cellPad).toFloat(), (y + r.cellPad).toFloat())
                    cell.draw(canvas)
                    canvas.restore()
                    x += r.colW[colIdx]
                    if (colIdx < r.colW.size - 1) {
                        canvas.drawLine(x.toFloat(), y.toFloat(), x.toFloat(), (y + r.rowH[rowIdx]).toFloat(), borderPaint)
                    }
                }
                y += r.rowH[rowIdx]
                if (rowIdx < r.cells.size - 1) {
                    canvas.drawLine(0f, y.toFloat(), r.contentWidth.toFloat(), y.toFloat(), borderPaint)
                }
            }

            rect.set(0.5f, 0.5f, r.contentWidth - 0.5f, totalH - 0.5f)
            canvas.drawRoundRect(rect, radius, radius, borderPaint)
        }
    }
}
