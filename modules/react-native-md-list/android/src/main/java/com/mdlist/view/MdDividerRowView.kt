package com.mdlist.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import com.mdlist.md.DividerRowLayout
import com.mdlist.md.MdTheme

class MdDividerRowView(context: Context, theme: MdTheme) : View(context) {
    private var row: DividerRowLayout? = null
    private val paint = Paint().apply {
        color = theme.divider
        strokeWidth = theme.dp(1f)
    }

    fun bind(layout: DividerRowLayout) {
        row = layout
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), row?.height ?: 0)
    }

    override fun onDraw(canvas: Canvas) {
        val r = row ?: return
        val y = height / 2f
        canvas.drawLine(r.inset, y, width - r.inset, y, paint)
    }
}
